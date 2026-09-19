import 'legacy_text.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:vector_math/vector_math_64.dart' as v;

/// Lectura acotada: valida todos los recuentos antes de reservar memoria.
class Bin {
  final Uint8List bytes;
  late final ByteData data = ByteData.sublistView(bytes);
  final String source;
  int offset = 0;
  String Function(List<int>) decoder = LegacyText.decode;
  Bin(this.bytes, [this.source = 'recurso']);
  Never fail(String message) =>
      throw FormatException('$source · byte $offset: $message');
  void need(int n) {
    if (n < 0 || offset + n > bytes.length) {
      fail('Archivo truncado ($n bytes).');
    }
  }

  void skip(int n) {
    need(n);
    offset += n;
  }

  int u8() {
    need(1);
    return bytes[offset++];
  }

  int u16() {
    need(2);
    final x = data.getUint16(offset, Endian.little);
    offset += 2;
    return x;
  }

  int u32() {
    need(4);
    final x = data.getUint32(offset, Endian.little);
    offset += 4;
    return x;
  }

  int i32() {
    need(4);
    final x = data.getInt32(offset, Endian.little);
    offset += 4;
    return x;
  }

  double rawFloat() {
    need(4);
    final x = data.getFloat32(offset, Endian.little);
    offset += 4;
    return x;
  }

  double f32() {
    final x = rawFloat();
    if (!x.isFinite) fail('Número no finito.');
    return x;
  }

  int count([int max = 1000000]) {
    final x = u32();
    if (x > max) fail('Recuento fuera del límite: $x.');
    return x;
  }

  String str([int? length]) {
    final n = length ?? count(65536);
    need(n);
    final raw = bytes.sublist(offset, offset + n);
    offset += n;
    final end = raw.indexOf(0);
    return decoder(end < 0 ? raw : raw.sublist(0, end));
  }

  List<double> floats(int n) => List.generate(n, (_) => f32());
  v.Vector3 vec() => v.Vector3(f32(), f32(), f32());
  v.Quaternion quat() {
    final q = v.Quaternion(f32(), f32(), f32(), f32());
    if (q.length2 < 1e-12) return v.Quaternion.identity();
    q.normalize();
    return q;
  }

  v.Matrix4 matrix() => v.Matrix4.fromList(floats(16));
  v.Matrix4 rawMatrix() =>
      v.Matrix4.fromList(List.generate(16, (_) => rawFloat()));
  int get remaining => bytes.length - offset;
  int i64() {
    need(8);
    final n = data.getInt64(offset, Endian.little);
    offset += 8;
    return n;
  }

  String ustr() {
    final n = count(1000000);
    need(n * 2);
    final text = LegacyText.unicode(bytes.sublist(offset, offset + n * 2));
    offset += n * 2;
    return text;
  }

  void meshEnd() {
    if (remaining == 8 && bytes.sublist(offset).every((b) => b == 0)) skip(8);
    end();
  }

  void end() {
    if (offset != bytes.length) {
      fail('Quedan ${bytes.length - offset} bytes sin interpretar.');
    }
  }
}

class MeshData {
  final Float32List positions, normals, uv, weights;
  final Uint16List indices;
  final Uint8List joints;
  final List<v.Matrix4> inverses;
  final String source;
  final List<String> repairs = [];
  MeshData(
    this.positions,
    this.normals,
    this.uv,
    this.indices,
    this.joints,
    this.weights,
    this.inverses,
    this.source,
  );
  int get vertices => positions.length ~/ 3;
  int get triangles => indices.length ~/ 3;
  double get minY {
    var y = double.infinity;
    for (var i = 1; i < positions.length; i += 3) {
      y = math.min(y, positions[i]);
    }
    return y;
  }

  double get maxY {
    var y = -double.infinity;
    for (var i = 1; i < positions.length; i += 3) {
      y = math.max(y, positions[i]);
    }
    return y;
  }

  int get requiredBones {
    var n = 0;
    for (var i = 0; i < weights.length; i++) {
      if (weights[i] > 1e-6) n = math.max(n, joints[i] + 1);
    }
    return n;
  }

  static MeshData object(Uint8List bytes, String source) {
    final r = Bin(bytes, source);
    r.str();
    final result = rigid(r);
    r.meshEnd();
    return result;
  }

  static MeshData skinned(Uint8List bytes, String source) {
    final r = Bin(bytes, source);
    r.need(4);
    final version = r.u32();
    r.offset = 0;
    // Algunas piezas MON con extensión 3DC contienen realmente una malla 3DO.
    if (version != 0 && version != 444) {
      final texture = r.str();
      if (!RegExp(r'\.(tga|dds)$', caseSensitive: false).hasMatch(texture)) {
        r.fail('Versión de malla desconocida.');
      }
      final out = rigid(r);
      r.end();
      return out;
    }
    var model = _skinnedOne(r);
    // Dos recursos del catálogo contienen varios bloques 3DC consecutivos.
    // Solo se combinan cuando utilizan exactamente el mismo espacio de enlace.
    var blocks = 1;
    while (r.offset < bytes.length) {
      if (++blocks > 16) r.fail('Demasiados bloques 3DC.');
      final next = _skinnedOne(r);
      model = model.join(next, r);
    }
    return model;
  }

  MeshData join(MeshData b, Bin r) {
    if (inverses.length != b.inverses.length || vertices + b.vertices > 65536) {
      r.fail('Bloques 3DC incompatibles.');
    }
    for (var i = 0; i < inverses.length; i++) {
      for (var k = 0; k < 16; k++) {
        if ((inverses[i].storage[k] - b.inverses[i].storage[k]).abs() > 1e-4) {
          r.fail('Los bloques 3DC no comparten matrices de enlace.');
        }
      }
    }
    return MeshData(
      Float32List.fromList([...positions, ...b.positions]),
      Float32List.fromList([...normals, ...b.normals]),
      Float32List.fromList([...uv, ...b.uv]),
      Uint16List.fromList([...indices, ...b.indices.map((n) => n + vertices)]),
      Uint8List.fromList([...joints, ...b.joints]),
      Float32List.fromList([...weights, ...b.weights]),
      inverses,
      source,
    );
  }

  static MeshData _skinnedOne(Bin r) {
    final version = r.u32();
    if (version != 0 && version != 444) {
      r.fail('Versión 3DC no soportada: $version.');
    }
    final nb = r.count(256);
    if (nb == 0) r.fail('Esqueleto vacío.');
    final inv = List.generate(nb, (_) => r.rawMatrix());
    final n = r.count(65536);
    r.need(n * (version == 444 ? 48 : 40));
    final p = Float32List(n * 3),
        normal = Float32List(n * 3),
        uv = Float32List(n * 2),
        weights = Float32List(n * 4),
        joints = Uint8List(n * 4);
    for (var i = 0; i < n; i++) {
      for (var k = 0; k < 3; k++) {
        p[i * 3 + k] = r.f32();
      }
      final w = [r.f32(), 0.0, 0.0, 0.0];
      if (version == 444) {
        w[1] = r.f32();
        w[2] = r.f32();
      } else {
        w[1] = 1 - w[0];
      }
      final js = List.generate(4, (_) => r.u8());
      for (var k = 0; k < 3; k++) {
        normal[i * 3 + k] = r.rawFloat();
      }
      for (var k = 0; k < 2; k++) {
        uv[i * 2 + k] = r.f32();
      }
      var sum = 0.0;
      for (var k = 0; k < 4; k++) {
        w[k] = w[k].clamp(0.0, 1.0);
        if (w[k] > 1e-6 && js[k] >= nb) {
          r.fail('Peso enlazado a un hueso inexistente.');
        }
        sum += w[k];
      }
      if (sum < 1e-9) {
        w[0] = 1;
        js[0] = 0;
        sum = 1;
      }
      for (var k = 0; k < 4; k++) {
        joints[i * 4 + k] = js[k] < nb ? js[k] : 0;
        weights[i * 4 + k] = w[k] / sum;
      }
    }
    final index = readIndices(r, n);
    final model = MeshData(
      p,
      normal,
      uv,
      index,
      joints,
      weights,
      inv,
      r.source,
    );
    final used = <int>{};
    for (var i = 0; i < weights.length; i++) {
      if (weights[i] > 1e-6) used.add(joints[i]);
    }
    for (var i = 0; i < inv.length; i++) {
      final valid =
          inv[i].storage.every((x) => x.isFinite) &&
          inv[i].determinant().abs() > 1e-12;
      if (!valid && used.contains(i)) {
        r.fail('Matriz de enlace inválida en el hueso utilizado $i.');
      }
      if (!valid) {
        inv[i] = v.Matrix4.identity();
        model.repairs.add('Matriz auxiliar no utilizada $i omitida.');
      }
    }
    model.repairNormals();
    return model;
  }

  void repairNormals() {
    if (normals.every((n) => n.isFinite)) return;
    normals.fillRange(0, normals.length, 0);
    for (var i = 0; i < indices.length; i += 3) {
      final a = indices[i] * 3, b = indices[i + 1] * 3, c = indices[i + 2] * 3;
      final ax = positions[b] - positions[a],
          ay = positions[b + 1] - positions[a + 1],
          az = positions[b + 2] - positions[a + 2];
      final bx = positions[c] - positions[a],
          by = positions[c + 1] - positions[a + 1],
          bz = positions[c + 2] - positions[a + 2];
      final nx = ay * bz - az * by,
          ny = az * bx - ax * bz,
          nz = ax * by - ay * bx;
      for (final k in [a, b, c]) {
        normals[k] += nx;
        normals[k + 1] += ny;
        normals[k + 2] += nz;
      }
    }
    for (var i = 0; i < normals.length; i += 3) {
      final length = math.sqrt(
        normals[i] * normals[i] +
            normals[i + 1] * normals[i + 1] +
            normals[i + 2] * normals[i + 2],
      );
      if (length > 1e-12) {
        for (var k = 0; k < 3; k++) {
          normals[i + k] /= length;
        }
      } else {
        normals[i + 1] = 1;
      }
    }
    repairs.add(
      'Normales no finitas reconstruidas desde los triángulos; posiciones, UV y pesos originales conservados.',
    );
  }

  static Uint16List readIndices(Bin r, int vertices) {
    final nf = r.count(2000000);
    r.need(nf * 6);
    final idx = Uint16List(nf * 3);
    for (var i = 0; i < idx.length; i++) {
      idx[i] = r.u16();
      if (idx[i] >= vertices) r.fail('Triángulo fuera de la malla.');
    }
    return idx;
  }

  static MeshData rigid(Bin r, {bool boneField = false, bool lightUv = false}) {
    final n = r.count(65536);
    r.need(n * (32 + (boneField ? 4 : 0) + (lightUv ? 8 : 0)));
    final p = Float32List(n * 3),
        no = Float32List(n * 3),
        uv = Float32List(n * 2);
    for (var i = 0; i < n; i++) {
      for (var k = 0; k < 3; k++) {
        p[3 * i + k] = r.rawFloat();
      }
      for (var k = 0; k < 3; k++) {
        no[3 * i + k] = r.rawFloat();
      }
      if (boneField) r.i32();
      uv[i * 2] = r.rawFloat();
      uv[i * 2 + 1] = r.rawFloat();
      if (lightUv) r.skip(8);
    }
    final indices = readIndices(r, n), used = indices.toSet();
    var omitted = 0;
    for (var i = 0; i < n; i++) {
      final invalid =
          p.sublist(i * 3, i * 3 + 3).any((x) => !x.isFinite) ||
          uv.sublist(i * 2, i * 2 + 2).any((x) => !x.isFinite);
      if (!invalid) continue;
      if (used.contains(i)) {
        r.fail('Posición o UV inválida en el vértice utilizado $i.');
      }
      // Exporters retain dead vertices with NaN UVs. They have no faces and
      // must not invalidate all the roofs/buildings that use the same mesh.
      p.fillRange(i * 3, i * 3 + 3, 0);
      uv.fillRange(i * 2, i * 2 + 2, 0);
      omitted++;
    }
    final out = MeshData(
      p,
      no,
      uv,
      indices,
      Uint8List(0),
      Float32List(0),
      [],
      r.source,
    )..repairNormals();
    if (omitted > 0) {
      out.repairs.add(
        '$omitted vértices no referenciados con valores no finitos neutralizados; todos los triángulos originales conservados.',
      );
    }
    return out;
  }
}

class BoneTrack {
  final int parent;
  final v.Matrix4 bind;
  final List<double> rotationTimes, positionTimes;
  final List<v.Quaternion> rotations;
  final List<v.Vector3> positions;
  BoneTrack(
    this.parent,
    this.bind,
    this.rotationTimes,
    this.rotations,
    this.positionTimes,
    this.positions,
  );
  int frame(List<double> times, double t) {
    var a = 0, b = times.length - 1;
    while (a < b) {
      final m = (a + b + 1) ~/ 2;
      if (times[m] <= t) {
        a = m;
      } else {
        b = m - 1;
      }
    }
    return a;
  }

  v.Matrix4 at(double t) {
    var q = rotations.first;
    var p = positions.first;
    if (rotations.length > 1) {
      final i = frame(rotationTimes, t),
          j = math.min(i + 1, rotations.length - 1),
          span = rotationTimes[j] - rotationTimes[i];
      final k = span > 0
          ? ((t - rotationTimes[i]) / span).clamp(0.0, 1.0)
          : 0.0;
      q = slerp(rotations[i], rotations[j], k);
    }
    if (positions.length > 1) {
      final i = frame(positionTimes, t),
          j = math.min(i + 1, positions.length - 1),
          span = positionTimes[j] - positionTimes[i];
      final k = span > 0
          ? ((t - positionTimes[i]) / span).clamp(0.0, 1.0)
          : 0.0;
      p = positions[i] * (1 - k) + positions[j] * k;
    }
    return v.Matrix4.compose(p, q, v.Vector3.all(1));
  }

  static v.Quaternion slerp(v.Quaternion a, v.Quaternion b, double t) {
    var dot = a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;
    var sign = 1.0;
    if (dot < 0) {
      sign = -1;
      dot = -dot;
    }
    var x = 1 - t, y = t;
    if (dot < .9995) {
      final theta = math.acos(dot.clamp(-1.0, 1.0)), s = math.sin(theta);
      x = math.sin((1 - t) * theta) / s;
      y = math.sin(t * theta) / s;
    }
    return v.Quaternion(
      a.x * x + b.x * y * sign,
      a.y * x + b.y * y * sign,
      a.z * x + b.z * y * sign,
      a.w * x + b.w * y * sign,
    )..normalize();
  }
}

class ClipData {
  final String source;
  final double duration;
  final List<BoneTrack> bones;
  ClipData(this.source, this.duration, this.bones);
  static ClipData parse(Uint8List bytes, String source) {
    final r = Bin(bytes, source);
    if (bytes.length >= 6 &&
        ascii.decode(bytes.sublist(0, 6), allowInvalid: true) == 'ANI_V2') {
      r.skip(6);
    }
    // Hay clips originales que comienzan en -1 o -40; leer como uint crea
    // una duración de miles de millones de fotogramas.
    final start = r.i32(), end = r.i32(), count = r.u16();
    if (end < start || end - start > 1000000 || count == 0 || count > 256) {
      r.fail('Cabecera ANI inválida.');
    }
    final tracks = <BoneTrack>[];
    for (var i = 0; i < count; i++) {
      final parent = r.i32();
      if (parent < -1 || parent >= i) {
        r.fail('Jerarquía cíclica o no ordenada.');
      }
      final world = r.rawMatrix();
      final p = v.Vector3.zero(), s = v.Vector3.zero();
      final q = v.Quaternion.identity();
      final rt = <double>[],
          rq = <v.Quaternion>[],
          pt = <double>[],
          pv = <v.Vector3>[];
      final nr = r.count(100000);
      r.need(nr * 20);
      for (var k = 0; k < nr; k++) {
        rt.add((r.i32() - start) / 30);
        rq.add(r.quat());
        if (k > 0 && rt[k] < rt[k - 1]) {
          r.fail('Claves de rotación desordenadas.');
        }
      }
      final nt = r.count(100000);
      r.need(nt * 16);
      for (var k = 0; k < nt; k++) {
        pt.add((r.i32() - start) / 30);
        pv.add(r.vec());
        if (k > 0 && pt[k] < pt[k - 1]) {
          r.fail('Claves de traslación desordenadas.');
        }
      }
      // Solo se usa el enlace como respaldo cuando falta un canal.
      if (rt.isEmpty || pt.isEmpty) {
        if (!world.storage.every((x) => x.isFinite) ||
            world.determinant().abs() < 1e-12) {
          r.fail('Matriz inválida para un canal de animación sin claves.');
        }
        v.Matrix4 local = world;
        if (parent >= 0) {
          final bind = tracks[parent].bind;
          if (!bind.storage.every((x) => x.isFinite) ||
              bind.determinant().abs() < 1e-12) {
            r.fail('Respaldo de animación singular.');
          }
          local = v.Matrix4.inverted(bind) * world;
        }
        local.decompose(p, q, s);
        if (!p.storage.every((x) => x.isFinite) ||
            !q.storage.every((x) => x.isFinite)) {
          r.fail('No se pudo recuperar el canal de animación.');
        }
      }
      tracks.add(
        BoneTrack(
          parent,
          world,
          rt.isEmpty ? [0] : rt,
          rq.isEmpty ? [q] : rq,
          pt.isEmpty ? [0] : pt,
          pv.isEmpty ? [p] : pv,
        ),
      );
    }
    r.end();
    return ClipData(source, math.max(1 / 30, (end - start) / 30), tracks);
  }

  List<v.Matrix4> pose(double seconds, {bool loop = true}) {
    final t = loop ? seconds % duration : seconds.clamp(0.0, duration);
    final out = <v.Matrix4>[];
    for (final bone in bones) {
      final local = bone.at(t);
      out.add(bone.parent < 0 ? local : out[bone.parent] * local);
    }
    return out;
  }
}

class MaterialRecord {
  final int id, alpha;
  final String mesh, texture;
  const MaterialRecord(this.id, this.mesh, this.texture, this.alpha);
  bool get isNull =>
      mesh.isEmpty ||
      mesh.toLowerCase() == 'null.3dc' ||
      texture.toLowerCase() == 'null.dds';
}

List<MaterialRecord> readMlt(Uint8List bytes, String path) {
  final r = Bin(bytes, path), sig = r.str(3);
  if (!sig.startsWith('ML')) r.fail('Cabecera MLT desconocida.');
  final meshes = List.generate(r.count(20000), (_) => r.str()),
      textures = List.generate(r.count(20000), (_) => r.str());
  final n = r.count(30000), rows = <MaterialRecord>[];
  for (var i = 0; i < n; i++) {
    final m = r.u32(), t = r.u32(), a = r.u32();
    if (m >= meshes.length || t >= textures.length) {
      r.fail('Índice MLT inexistente.');
    }
    rows.add(MaterialRecord(i, meshes[m], textures[t], a));
  }
  r.end();
  return rows;
}

class Attachment {
  final int bone;
  final v.Vector3 position;
  final v.Quaternion rotation;
  Attachment(this.bone, this.position, this.rotation);
  factory Attachment.read(Bin r) => Attachment(r.i32(), r.vec(), r.quat());
  bool get defined =>
      bone >= 0 &&
      (bone != 0 ||
          position.length2 > 1e-12 ||
          rotation.x.abs() + rotation.y.abs() + rotation.z.abs() > 1e-6);
  v.Matrix4 get matrix =>
      v.Matrix4.compose(position, rotation, v.Vector3.all(1));
}

class WeaponRecord extends MaterialRecord {
  final String source;
  final List<List<Attachment>> transforms;
  WeaponRecord(
    super.id,
    super.mesh,
    super.texture,
    super.alpha,
    this.source,
    this.transforms,
  );
}

List<WeaponRecord> readItm(Uint8List bytes, String path) {
  final r = Bin(bytes, path);
  final panda =
      bytes.length >= 8 &&
      ascii.decode(bytes.sublist(0, 8), allowInvalid: true) == 'pandaIT2';
  if (panda) r.skip(5);
  final sig = r.str(3);
  if (sig != 'ITM' && sig != 'IT2') r.fail('Cabecera ITM no soportada.');
  final meshes = List.generate(r.count(20000), (_) => r.str()),
      textures = List.generate(r.count(20000), (_) => r.str());
  final n = r.count(30000), out = <WeaponRecord>[];
  for (var i = 0; i < n; i++) {
    final m = r.u32(), t = r.u32(), alpha = r.i32();
    r.i32();
    final extended = r.i32();
    r.i32();
    if (extended != 0 && extended != 1) r.fail('Registro ITM desconocido.');
    if (extended == 1) r.skip(16);
    if (m >= meshes.length || t >= textures.length) {
      r.fail('Referencia ITM inválida.');
    }
    final transforms = <List<Attachment>>[];
    if (sig == 'IT2') {
      for (var a = 0; a < (panda ? 24 : 16); a++) {
        transforms.add([Attachment.read(r), Attachment.read(r)]);
      }
    }
    out.add(WeaponRecord(i, meshes[m], textures[t], alpha, path, transforms));
  }
  r.end();
  return out;
}

class CreatureRecord {
  final int id;
  final String name, source;
  final Map<String, String> animations, sounds, effects;
  final List<MaterialRecord> parts;
  final double height;
  CreatureRecord(
    this.id,
    this.name,
    this.source,
    this.animations,
    this.sounds,
    this.effects,
    this.parts,
    this.height,
  );
}

List<CreatureRecord> readMon(Uint8List bytes, String path) {
  final r = Bin(bytes, path), sig = r.str(3);
  if (sig != 'MO2' && sig != 'MO4') r.fail('Cabecera MON desconocida.');
  final n = r.count(10000), out = <CreatureRecord>[];
  for (var i = 0; i < n; i++) {
    final name = r.str();
    r.u8();
    final anim = <String, String>{},
        sounds = <String, String>{},
        effects = <String, String>{};
    for (final key in [
      'Caminar',
      'Correr',
      'Ataque 1',
      'Ataque 2',
      'Ataque 3',
      'Caída',
      'Respirar',
      'Daño',
      'Reposo',
    ]) {
      anim[key] = r.str();
    }
    for (final key in ['Ataque 1', 'Ataque 2', 'Ataque 3', 'Caída']) {
      sounds[key] = r.str();
    }
    for (final key in ['Ataque 1', 'Ataque 2', 'Ataque 3', 'Caída']) {
      effects[key] = r.str();
    }
    if (sig == 'MO4') effects['Adjunto'] = r.str();
    final parts = List.generate(
      r.count(1000),
      (j) => MaterialRecord(j, r.str(), r.str(), 0),
    );
    final height = r.f32();
    r.skip(r.count(10000) * 8);
    out.add(
      CreatureRecord(i, name, path, anim, sounds, effects, parts, height),
    );
  }
  r.end();
  return out;
}

class WorldLayer {
  final String texture, sound;
  final double tile;
  WorldLayer(this.texture, this.tile, this.sound);
}

class WorldInstance {
  final String category, asset;
  final v.Vector3 position, forward, up;
  WorldInstance(
    this.category,
    this.asset,
    this.position,
    this.forward,
    this.up,
  );
}

class WorldData {
  final int size;
  final Uint16List heights;
  final Uint8List types;
  final List<WorldLayer> layers;
  final List<WorldInstance> objects;
  final String layout;
  WorldData(
    this.size,
    this.heights,
    this.types,
    this.layers,
    this.objects,
    this.layout,
  );
  static WorldData parse(Uint8List bytes, String source) {
    final r = Bin(bytes, source), sig = r.str(4);
    if (sig != 'FLD' && sig != 'DUN') r.fail('Cabecera WLD desconocida.');
    var size = 0;
    var heights = Uint16List(0);
    var types = Uint8List(0);
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
      final nl = r.count(256);
      for (var i = 0; i < nl; i++) {
        layers.add(WorldLayer(r.str(256), r.f32(), r.str(256)));
      }
    }
    final layout = r.str(256), objects = <WorldInstance>[];
    for (final category in [
      'Building',
      'Shape',
      'Tree',
      'Grass',
      'VAni',
      'VAni',
      'dungeon',
    ]) {
      final names = List.generate(r.count(20000), (_) => r.str(256));
      final n = r.count(1000000);
      r.need(n * 40);
      for (var i = 0; i < n; i++) {
        final id = r.u32(), p = r.vec(), f = r.vec(), u = r.vec();
        if (id >= names.length) r.fail('Objeto WLD no definido.');
        objects.add(WorldInstance(category, names[id], p, f, u));
      }
    }
    return WorldData(size, heights, types, layers, objects, layout);
  }

  double heightAt(
    double x,
    double z, {
    double scale = .02,
    double offset = -200,
  }) {
    if (size == 0) return 0;
    final width = size ~/ 2 + 1;
    final fx = (x / 2).clamp(0.0, width - 1.001),
        fz = (z / 2).clamp(0.0, width - 1.001),
        a = fx.floor(),
        b = fz.floor(),
        tx = fx - a,
        tz = fz - b;
    double h(int i, int j) => heights[j * width + i] * scale + offset;
    return (h(a, b) * (1 - tx) + h(a + 1, b) * tx) * (1 - tz) +
        (h(a, b + 1) * (1 - tx) + h(a + 1, b + 1) * tx) * tz;
  }
}

class StaticPart {
  final String texture;
  final MeshData mesh;
  StaticPart(this.texture, this.mesh);
}

List<StaticPart> readSmod(Uint8List bytes, String source) {
  final r = Bin(bytes, source);
  r.skip(40);
  final out = <StaticPart>[];
  final n = r.count(10000);
  for (var i = 0; i < n; i++) {
    final tex = r.str();
    out.add(StaticPart(tex, MeshData.rigid(r, boneField: true)));
  }
  return out;
}
