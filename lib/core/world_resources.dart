import 'dart:math' as math;
import 'dart:typed_data';
import 'package:vector_math/vector_math_64.dart' as v;
import 'formats.dart';
import 'legacy_text.dart';

class WorldArea {
  final String name, comment;
  final v.Vector3 lower, upper;
  WorldArea(this.name, this.comment, this.lower, this.upper);
  v.Vector3 get center => (lower + upper) * .5;
}

/// NPC placement stored directly in the original WLD resource.
/// Type/typeId are resolved against NpcQuest.SData by the game client.
class WorldNpc {
  final int type, typeId;
  final v.Vector3 position;
  final double orientation;
  final List<v.Vector3> patrol;
  const WorldNpc(this.type, this.typeId, this.position, this.orientation, this.patrol);
}

class WorldResource {
  final WorldData terrain;
  final List<WorldArea> areas = [], spawns = [];
  final List<String> music = [];
  final List<v.Vector3> portals = [];
  final List<WorldNpc> npcs = [];
  String sky = '', cloud = '', secondCloud = '';
  int fogColor = 0x9ab5c6;
  double fogNear = 120, fogFar = 600;
  final List<String> diagnostics = [];
  WorldResource(this.terrain);
  static WorldResource parse(Uint8List bytes, String source) {
    final r = Bin(bytes, source)..decoder = LegacyText.korean;
    final sig = r.str(4);
    if (sig != 'FLD' && sig != 'DUN') r.fail('Cabecera WLD desconocida.');
    var size = 0;
    var heights = Uint16List(0), types = Uint8List(0);
    final layers = <WorldLayer>[];
    if (sig == 'FLD') {
      size = r.count(8192);
      if (size < 2 || size.isOdd) r.fail('Dimensiones WLD inválidas.');
      final n = (size ~/ 2 + 1) * (size ~/ 2 + 1);
      r.need(n * 3);
      heights = Uint16List(n);
      for (var i = 0; i < n; i++) {
        heights[i] = r.u16();
      }
      types = Uint8List.fromList(bytes.sublist(r.offset, r.offset + n));
      r.skip(n);
      final count = r.count(256);
      for (var i = 0; i < count; i++) {
        layers.add(WorldLayer(r.str(256), r.f32(), r.str(256)));
      }
    }
    final layout = r.str(256), objects = <WorldInstance>[];
    void objectsOf(String category) {
      final names = List.generate(r.count(30000), (_) => r.str(256)),
          n = r.count(1000000);
      r.need(n * 40);
      for (var i = 0; i < n; i++) {
        final id = r.u32(), p = r.vec(), forward = r.vec(), up = r.vec();
        if (id >= names.length) r.fail('Índice de objeto inválido.');
        objects.add(WorldInstance(category, names[id], p, forward, up));
      }
    }

    for (final category in [
      'Building',
      'Shape',
      'Tree',
      'Grass',
      'VAni',
      'VAni',
      'dungeon',
    ]) {
      objectsOf(category);
    }
    final result = WorldResource(
      WorldData(size, heights, types, layers, objects, layout),
    );
    // An intentionally minimal synthetic WLD ends here. Real files continue.
    if (r.remaining == 0) {
      result.diagnostics.add('WLD mínimo sin metadatos ambientales.');
      return result;
    }
    r.skip(r.count(30000) * 256);
    r.skip(r.count(1000000) * 44);
    r.str(256);
    r.skip(r.count(1000000) * 40);
    r.skip(12);
    objectsOf('Object');
    result.music.addAll(List.generate(r.count(30000), (_) => r.str(256)));
    r.skip(r.count(1000000) * 36);
    r.skip(r.count(30000) * 256);
    final zones = r.count(1000000);
    for (var i = 0; i < zones; i++) {
      r.skip(24);
      r.skip(r.count(1000000) * 4);
    }
    r.skip(r.count(1000000) * 20);
    r.skip(r.count(1000000) * 28);
    final portals = r.count(100000);
    for (var i = 0; i < portals; i++) {
      final low = r.vec(), high = r.vec();
      r.skip(4);
      r.str(256);
      r.str(256);
      r.skip(4);
      r.vec();
      result.portals.add((low + high) * .5);
    }
    final spawns = r.count(100000);
    for (var i = 0; i < spawns; i++) {
      r.skip(4);
      final low = r.vec(), high = r.vec();
      r.skip(12);
      result.spawns.add(
        WorldArea('Punto de aparición ${i + 1}', '', low, high),
      );
    }
    final areas = r.count(100000);
    for (var i = 0; i < areas; i++) {
      final low = r.vec(), high = r.vec();
      r.skip(4);
      final name = r.str(256), comment = r.str(256);
      r.skip(8);
      result.areas.add(WorldArea(name, comment, low, high));
    }
    var npc = r.count(1000000);
    while (npc > 0) {
      final type = r.i32(),
          typeId = r.i32(),
          position = r.vec(),
          orientation = r.f32(),
          patrolCount = r.count(100000),
          patrol = List.generate(patrolCount, (_) => r.vec());
      result.npcs.add(WorldNpc(type, typeId, position, orientation, patrol));
      npc -= 1 + patrolCount;
      if (npc < 0) r.fail('Recuento NPC no coincide.');
    }
    if (size > 0) {
      result.sky = r.str(256);
      result.cloud = r.str(256);
      result.secondCloud = r.str(256);
    }
    r.skip(24);
    final rgb = r.floats(3);
    result.fogColor =
        (rgb[0].round().clamp(0, 255) << 16) |
        (rgb[1].round().clamp(0, 255) << 8) |
        rgb[2].round().clamp(0, 255);
    result.fogNear = r.f32();
    result.fogFar = r.f32();
    // Some DUN clients append the same three sky-name slots as exterior maps.
    if (r.remaining == 768) {
      result.sky = r.str(256);
      result.cloud = r.str(256);
      result.secondCloud = r.str(256);
    }
    r.end();
    return result;
  }

  v.Vector3 spawn() {
    if (spawns.isNotEmpty) return spawns.first.center;
    if (portals.isNotEmpty) return portals.first;
    if (areas.isNotEmpty) return areas.first.center;
    if (terrain.size > 0) {
      final x = terrain.size * .5;
      return v.Vector3(x, terrain.heightAt(x, x), x);
    }
    return v.Vector3.zero();
  }
}

class DungeonSurface {
  final int texture, lightmap;
  final MeshData mesh;
  DungeonSurface(this.texture, this.lightmap, this.mesh);
}

class DungeonResource {
  final v.Vector3 minimum, maximum;
  final List<String> textures;
  final List<DungeonSurface> surfaces = [];
  final List<MeshData> collisions = [];
  int nodeCount = 0;
  DungeonResource(this.minimum, this.maximum, this.textures);
  static DungeonResource parse(Uint8List bytes, String source) {
    final r = Bin(bytes, source), min = r.vec(), max = r.vec();
    final names = List.generate(r.count(30000), (_) => r.str(256));
    r.count(30000);
    final out = DungeonResource(min, max, names);
    void node(int depth) {
      if (depth > 30 || ++out.nodeCount > 200000) {
        r.fail('Árbol DG fuera de límite.');
      }
      r.skip(60);
      final groups = r.count(30000);
      for (var i = 0; i < groups; i++) {
        final tex = r.i32();
        if (tex < 0 || tex >= names.length) {
          r.fail('Textura DG fuera de catálogo.');
        }
        final n = r.count(100000);
        for (var j = 0; j < n; j++) {
          final light = r.i32();
          out.surfaces.add(
            DungeonSurface(
              tex,
              light,
              MeshData.rigid(r, boneField: true, lightUv: true),
            ),
          );
        }
      }
      final collision = r.i32();
      if (collision == 1) {
        final n = r.count(65536);
        r.need(n * 12);
        final p = Float32List(n * 3);
        for (var i = 0; i < p.length; i++) {
          p[i] = r.f32();
        }
        final indices = MeshData.readIndices(r, n);
        out.collisions.add(
          MeshData(
            p,
            Float32List(n * 3),
            Float32List(n * 2),
            indices,
            Uint8List(0),
            Float32List(0),
            [],
            source,
          ),
        );
      } else if (collision != 0) {
        r.fail('Tipo de colisión DG desconocido.');
      }
      for (var i = 0; i < 8; i++) {
        final present = r.i32();
        if (present > 0) node(depth + 1);
      }
    }

    if (r.i32() > 0) node(0);
    r.end();
    return out;
  }
}

class EnvironmentFrame {
  final int start, end;
  final List<int> colors;
  final List<String> skies;
  final List<double> light;
  final bool weather;
  EnvironmentFrame(
    this.start,
    this.end,
    this.colors,
    this.skies,
    this.light,
    this.weather,
  );
}

List<EnvironmentFrame> readEnvironment(Uint8List bytes, String source) {
  final r = Bin(bytes, source);
  if (r.str(2) != 'V2') r.fail('ENV no soportado.');
  final count = r.count(64), out = <EnvironmentFrame>[];
  for (var i = 0; i < count; i++) {
    final start = r.i32(), end = r.i32(), colors = <int>[];
    for (var j = 0; j < 3; j++) {
      final red = r.i32(), green = r.i32(), blue = r.i32();
      if ([red, green, blue].any((v) => v < 0 || v > 255)) {
        r.fail('Color ENV inválido.');
      }
      colors.add((red << 16) | (green << 8) | blue);
    }
    final skies = List.generate(4, (_) => r.str()),
        light = r.floats(6),
        weather = r.u8() != 0;
    r.i32();
    out.add(EnvironmentFrame(start, end, colors, skies, light, weather));
  }
  r.end();
  return out;
}

/// Stable spatial query for floor selection and movement, independent of renderer.
class SurfaceIndex {
  final double cellSize;
  final Map<String, List<List<v.Vector3>>> _cells = {};
  final Map<Object, List<(String, List<v.Vector3>)>> _owners = {};
  int get residentCells => _cells.length;
  int get ownedGroups => _owners.length;
  void removeOwner(Object owner) {
    for (final pair in _owners.remove(owner) ?? <(String, List<v.Vector3>)>[]) {
      final entries = _cells[pair.$1];
      entries?.remove(pair.$2);
      if (entries?.isEmpty ?? false) _cells.remove(pair.$1);
    }
  }

  void clear() {
    _cells.clear();
    _owners.clear();
  }

  SurfaceIndex({this.cellSize = 16});
  String key(int x, int z) => '$x:$z';
  void add(MeshData mesh, {v.Matrix4? transform, Object? owner}) {
    final p = mesh.positions;
    for (var i = 0; i < mesh.indices.length; i += 3) {
      final tri = List.generate(3, (k) {
        final n = mesh.indices[i + k] * 3;
        final pt = v.Vector3(p[n], p[n + 1], p[n + 2]);
        return transform == null ? pt : transform.transformed3(pt);
      });
      final a = tri[1] - tri[0], b = tri[2] - tri[0], normal = a.cross(b);
      if (normal.length2 < 1e-12) continue;
      final minX = tri.map((v) => v.x).reduce(math.min),
          maxX = tri.map((v) => v.x).reduce(math.max),
          minZ = tri.map((v) => v.z).reduce(math.min),
          maxZ = tri.map((v) => v.z).reduce(math.max);
      if ((maxX - minX) * (maxZ - minZ) > 1000000) continue;
      for (
        var x = (minX / cellSize).floor();
        x <= (maxX / cellSize).floor();
        x++
      ) {
        for (
          var z = (minZ / cellSize).floor();
          z <= (maxZ / cellSize).floor();
          z++
        ) {
          final cell = key(x, z);
          _cells.putIfAbsent(cell, () => []).add(tri);
          if (owner != null) {
            _owners.putIfAbsent(owner, () => []).add((cell, tri));
          }
        }
      }
    }
  }

  bool blocks(
    v.Vector3 a,
    v.Vector3 b, {
    double radius = .22,
    double height = 1.6,
  }) {
    final delta = b - a,
        distance = math.sqrt(delta.x * delta.x + delta.z * delta.z);
    if (distance < 1e-8) return false;
    final side = v.Vector3(-delta.z / distance, 0, delta.x / distance) * radius;
    final candidates = <List<v.Vector3>>{};
    final minX = (math.min(a.x, b.x) - radius) / cellSize,
        maxX = (math.max(a.x, b.x) + radius) / cellSize,
        minZ = (math.min(a.z, b.z) - radius) / cellSize,
        maxZ = (math.max(a.z, b.z) + radius) / cellSize;
    for (var x = minX.floor(); x <= maxX.floor(); x++) {
      for (var z = minZ.floor(); z <= maxZ.floor(); z++) {
        candidates.addAll(_cells[key(x, z)] ?? []);
      }
    }
    for (final triangle in candidates) {
      final edge1 = triangle[1] - triangle[0],
          edge2 = triangle[2] - triangle[0],
          normal = edge1.cross(edge2);
      // Floors/ramps are handled by height queries, not by wall blocking.
      if (normal.y.abs() > .8 * normal.length) continue;
      for (final lateral in [-1.0, 0.0, 1.0]) {
        for (final level in [.35, height * .65, height * .94]) {
          final origin = a + side * lateral + v.Vector3(0, level, 0),
              end = b + side * lateral + v.Vector3(0, level, 0),
              ray = end - origin;
          final h = ray.cross(edge2), det = edge1.dot(h);
          if (det.abs() < 1e-9) continue;
          final s = origin - triangle[0], u = s.dot(h) / det;
          if (u < 0 || u > 1) continue;
          final q = s.cross(edge1), vv = ray.dot(q) / det;
          if (vv < 0 || u + vv > 1) continue;
          final t = edge2.dot(q) / det;
          if (t > 1e-6 && t < 1.000001) return true;
        }
      }
    }
    return false;
  }

  double? floor(double x, double z, double expected, {double maxRise = 1.1}) {
    double? best;
    for (final tri
        in _cells[key((x / cellSize).floor(), (z / cellSize).floor())] ??
            <List<v.Vector3>>[]) {
      final a = tri[0],
          b = tri[1],
          c = tri[2],
          den = (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z);
      if (den.abs() < 1e-8) continue;
      final u = ((b.z - c.z) * (x - c.x) + (c.x - b.x) * (z - c.z)) / den,
          vv = ((c.z - a.z) * (x - c.x) + (a.x - c.x) * (z - c.z)) / den;
      if (u < -.001 || vv < -.001 || u + vv > 1.001) continue;
      final y = u * a.y + vv * b.y + (1 - u - vv) * c.y;
      if (y <= expected + maxRise && (best == null || y > best)) best = y;
    }
    return best;
  }
}
