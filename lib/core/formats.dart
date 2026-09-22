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
  Bin(this.bytes, [this.source = 'recurso']);
  Never fail(String message) =>
      throw FormatException('$source · byte $offset: $message');
  void need(int n) {
    if (n < 0 || offset + n > bytes.length)
      fail('Archivo truncado ($n bytes).');
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

  int i16() {
    need(2);
    final x = data.getInt16(offset, Endian.little);
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
    return utf8.decode(
      end < 0 ? raw : raw.sublist(0, end),
      allowMalformed: true,
    );
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
  void end() {
    if (offset != bytes.length)
      fail('Quedan ${bytes.length - offset} bytes sin interpretar.');
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

  static MeshData skinned(Uint8List bytes, String source) {
    final r = Bin(bytes, source);
    r.need(4);
    final version = r.u32();
    r.offset = 0;
    // Algunas piezas MON con extensión 3DC contienen realmente una malla 3DO.
    if (version != 0 && version != 444) {
      final texture = r.str();
      if (!RegExp(r'\.(tga|dds)$', caseSensitive: false).hasMatch(texture))
        r.fail('Versión de malla desconocida.');
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
    if (inverses.length != b.inverses.length || vertices + b.vertices > 65536)
      r.fail('Bloques 3DC incompatibles.');
    for (var i = 0; i < inverses.length; i++) {
      for (var k = 0; k < 16; k++) {
        if ((inverses[i].storage[k] - b.inverses[i].storage[k]).abs() > 1e-4)
          r.fail('Los bloques 3DC no comparten matrices de enlace.');
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
    if (version != 0 && version != 444)
      r.fail('Versión 3DC no soportada: $version.');
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
        // EP6 stores exactly three bone weights and three bone-group IDs.
        // The fourth byte that follows is an unknown field (normally zero),
        // not a fourth bone group.  Keep weight #4 at zero and normalize
        // the three actual weights below.
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
        if (w[k] > 1e-6 && js[k] >= nb)
          r.fail('Peso enlazado a un hueso inexistente.');
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
      if (!valid && used.contains(i))
        r.fail('Matriz de enlace inválida en el hueso utilizado $i.');
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
    var repairedUv=false;
    for (var i = 0; i < n; i++) {
      for (var k = 0; k < 3; k++) {
        p[3 * i + k] = r.f32();
      }
      for (var k = 0; k < 3; k++) {
        no[3 * i + k] = r.rawFloat();
      }
      if (boneField) r.i32();
      for(var k=0;k<2;k++){
        final value=r.rawFloat();
        if(value.isFinite){
          uv[i*2+k]=value;
        }else{
          // Several original SMODs contain NaN in an unused UV coordinate.
          // The native client still renders the object; zero is the neutral
          // recoverable coordinate and preserves all geometry.
          uv[i*2+k]=0;
          repairedUv=true;
        }
      }
      if (lightUv) r.skip(8);
    }
    final model=MeshData(
      p,
      no,
      uv,
      readIndices(r, n),
      Uint8List(0),
      Float32List(0),
      [],
      r.source,
    )..repairNormals();
    if(repairedUv){
      model.repairs.add('UV no finitas originales normalizadas a 0.');
    }
    return model;
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
        ascii.decode(bytes.sublist(0, 6), allowInvalid: true) == 'ANI_V2')
      r.skip(6);
    // Hay clips originales que comienzan en -1 o -40; leer como uint crea
    // una duración de miles de millones de fotogramas.
    final start = r.i32(), end = r.i32(), count = r.u16();
    if (end < start || end - start > 1000000 || count == 0 || count > 256)
      r.fail('Cabecera ANI inválida.');
    final tracks = <BoneTrack>[];
    for (var i = 0; i < count; i++) {
      final parent = r.i32();
      if (parent < -1 || parent >= i)
        r.fail('Jerarquía cíclica o no ordenada.');
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
        if (k > 0 && rt[k] < rt[k - 1])
          r.fail('Claves de rotación desordenadas.');
      }
      final nt = r.count(100000);
      r.need(nt * 16);
      for (var k = 0; k < nt; k++) {
        pt.add((r.i32() - start) / 30);
        pv.add(r.vec());
        if (k > 0 && pt[k] < pt[k - 1])
          r.fail('Claves de traslación desordenadas.');
      }
      // Solo se usa el enlace como respaldo cuando falta un canal.
      if (rt.isEmpty || pt.isEmpty) {
        if (!world.storage.every((x) => x.isFinite) ||
            world.determinant().abs() < 1e-12)
          r.fail('Matriz inválida para un canal de animación sin claves.');
        v.Matrix4 local = world;
        if (parent >= 0) {
          final bind = tracks[parent].bind;
          if (!bind.storage.every((x) => x.isFinite) ||
              bind.determinant().abs() < 1e-12)
            r.fail('Respaldo de animación singular.');
          local = v.Matrix4.inverted(bind) * world;
        }
        local.decompose(p, q, s);
        if (!p.storage.every((x) => x.isFinite) ||
            !q.storage.every((x) => x.isFinite))
          r.fail('No se pudo recuperar el canal de animación.');
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
    if (m >= meshes.length || t >= textures.length)
      r.fail('Índice MLT inexistente.');
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
    if (m >= meshes.length || t >= textures.length)
      r.fail('Referencia ITM inválida.');
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

class WorldBounds {
  final v.Vector3 lower,upper;
  const WorldBounds(this.lower,this.upper);
  bool contains(double x,double y,double z)=>x>=lower.x&&x<=upper.x&&
    y>=lower.y&&y<=upper.y&&z>=lower.z&&z<=upper.z;
}

class WorldMusicZone {
  final WorldBounds bounds;
  final double radius;
  final int assetId,unknown;
  const WorldMusicZone(this.bounds,this.radius,this.assetId,this.unknown);
}

class WorldSoundEffect {
  final int assetId;
  final v.Vector3 center;
  final double radius;
  const WorldSoundEffect(this.assetId,this.center,this.radius);
  bool contains(double x,double y,double z){
    final dx=x-center.x,dy=y-center.y,dz=z-center.z;
    return dx*dx+dy*dy+dz*dz<=radius*radius;
  }
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

class WorldManiInstance {
  final String buildingAsset,maniAsset;
  final v.Vector3 position,forward,up;
  const WorldManiInstance(
    this.buildingAsset,this.maniAsset,this.position,this.forward,this.up,
  );
  WorldInstance get building=>WorldInstance('Building',buildingAsset,position,forward,up);
}

class ManiData {
  final int version,unknown1,unknown5,unknown6,enableRotation,unknownShort1,unknownShort2,unknown13;
  final v.Vector3 unknownVec1,unknownVec2,rotation,unknownVec4;
  final double unknown2,unknown3,unknown4,unknown7,unknown8,animationSpeed,unknown11,unknown12;
  const ManiData({
    required this.version,required this.unknown1,required this.unknownVec1,
    required this.unknown2,required this.unknown3,required this.unknown4,
    required this.unknown5,required this.unknown6,required this.unknownVec2,
    required this.unknown7,required this.unknown8,required this.enableRotation,
    required this.rotation,required this.animationSpeed,required this.unknownShort1,
    required this.unknownShort2,required this.unknownVec4,required this.unknown11,
    required this.unknown12,required this.unknown13,
  });
  static ManiData parse(Uint8List bytes,String source){
    final r=Bin(bytes,source);
    final out=ManiData(
      version:r.i32(),unknown1:r.i32(),unknownVec1:r.vec(),
      unknown2:r.f32(),unknown3:r.f32(),unknown4:r.f32(),
      unknown5:r.i32(),unknown6:r.i32(),unknownVec2:r.vec(),
      unknown7:r.f32(),unknown8:r.f32(),enableRotation:r.i32(),
      rotation:r.vec(),animationSpeed:r.f32(),
      unknownShort1:r.i16(),unknownShort2:r.i16(),unknownVec4:r.vec(),
      unknown11:r.f32(),unknown12:r.f32(),unknown13:r.i32(),
    );
    r.end();
    if(out.version!=0x21)throw FormatException('$source · versión MAni inesperada: ${out.version}.');
    return out;
  }
}

v.Matrix4 worldInstanceMatrix(WorldInstance obj,double originX,double originZ){
  v.Vector3 safe(v.Vector3 value,v.Vector3 fallback){
    final out=value.clone();
    final length=out.length;
    if(!length.isFinite||length<1e-6)return fallback.clone();
    return out..scale(1/length);
  }
  final forward=safe(obj.forward,v.Vector3(0,0,1));
  final up0=safe(obj.up,v.Vector3(0,1,0));
  var right=v.Vector3(
    up0.y*forward.z-up0.z*forward.y,
    up0.z*forward.x-up0.x*forward.z,
    up0.x*forward.y-up0.y*forward.x,
  );
  if(right.length<1e-6){right=v.Vector3(1,0,0);}else{right.scale(1/right.length);}
  final up=v.Vector3(
    forward.y*right.z-forward.z*right.y,
    forward.z*right.x-forward.x*right.z,
    forward.x*right.y-forward.y*right.x,
  );
  final m=v.Matrix4.identity(),s=m.storage;
  // Shaiya's WLD basis is left-handed. Three.js is right-handed, so this
  // is S*M with S=diag(1,1,-1): the reflection is part of the instance
  // matrix, not an extra yaw approximation.
  s[0]=right.x;s[1]=right.y;s[2]=-right.z;s[3]=0;
  s[4]=up.x;s[5]=up.y;s[6]=-up.z;s[7]=0;
  s[8]=forward.x;s[9]=forward.y;s[10]=-forward.z;s[11]=0;
  s[12]=obj.position.x-originX;s[13]=obj.position.y;s[14]=-(obj.position.z-originZ);s[15]=1;
  return m;
}

class WorldData {
  final int size;
  final Uint16List heights;
  final Uint8List types;
  final List<WorldLayer> layers;
  final List<WorldInstance> objects;
  final List<WorldManiInstance> maniInstances;
  final String layout;
  final String skyFile,primaryCloudFile,secondaryCloudFile;
  final List<String> musicAssets,soundEffectAssets;
  final List<WorldMusicZone> musicZones;
  final List<WorldSoundEffect> soundEffects;
  final v.Vector3 fogColor;
  final double fogStart,fogEnd;
  WorldData(
    this.size,
    this.heights,
    this.types,
    this.layers,
    this.objects,
    this.layout,{
    this.maniInstances=const [],
    this.skyFile='',
    this.primaryCloudFile='',
    this.secondaryCloudFile='',
    this.musicAssets=const [],
    this.musicZones=const [],
    this.soundEffectAssets=const [],
    this.soundEffects=const [],
    v.Vector3? fogColor,
    this.fogStart=0,
    this.fogEnd=0,
  }):fogColor=fogColor??v.Vector3.zero();

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

    final layout = r.str(256), objects = <WorldInstance>[],maniInstances=<WorldManiInstance>[];

    List<String> readCategory(String category,{bool keep=true}) {
      final names = List.generate(r.count(20000), (_) => r.str(256));
      final n = r.count(1000000);
      r.need(n * 40);
      for (var i = 0; i < n; i++) {
        final id = r.i32(), p = r.vec(), f = r.vec(), u = r.vec();
        if (id < 0 || id >= names.length) r.fail('Objeto WLD no definido.');
        if(keep)objects.add(WorldInstance(category, names[id], p, f, u));
      }
      return names;
    }
    void skipBox()=>r.skip(24);

    final buildingAssets=readCategory('Building');
    readCategory('Shape');
    readCategory('Tree');
    readCategory('Grass');
    readCategory('VAni');
    readCategory('VAni');
    readCategory('dungeon',keep:false);

    var skyFile='',primaryCloud='',secondaryCloud='';
    var fog=v.Vector3.zero(),fogStart=0.0,fogEnd=0.0;
    var musicAssets=<String>[],soundEffectAssets=<String>[];
    final musicZones=<WorldMusicZone>[],soundEffects=<WorldSoundEffect>[];

    // Full WLD tail.  Older lab fixtures intentionally ended after the seven
    // legacy categories, so keep that minimal form readable for unit tests.
    if(r.offset < bytes.length){
      final maniAssets=List.generate(r.count(20000),(_)=>r.str(256));
      final maniCount=r.count(1000000);
      r.need(maniCount*44);
      for(var i=0;i<maniCount;i++){
        final buildingId=r.i32(),maniId=r.i32(),p=r.vec(),forward=r.vec(),up=r.vec();
        if(buildingId<0||buildingId>=buildingAssets.length){
          r.fail('MAni referencia Building inexistente: $buildingId.');
        }
        if(maniId<0||maniId>=maniAssets.length){
          r.fail('MAni referencia asset inexistente: $maniId.');
        }
        maniInstances.add(WorldManiInstance(
          buildingAssets[buildingId],maniAssets[maniId],p,forward,up,
        ));
      }
      r.str(256); // EFT file.
      final effects=r.count(1000000);r.skip(effects*40);
      r.skip(12); // Unknown1..3.

      // Entity/Object is a real render category used by the native client.
      readCategory('Object');

      final musicCount=r.count(20000);
      musicAssets=List.generate(musicCount,(_)=>r.str(256));
      final musicZoneCount=r.count(1000000);
      for(var i=0;i<musicZoneCount;i++){
        final lower=r.vec(),upper=r.vec(),radius=r.f32(),assetId=r.i32(),unknown=r.i32();
        if(assetId<0||assetId>=musicAssets.length)r.fail('Zona de música referencia asset inexistente: $assetId.');
        musicZones.add(WorldMusicZone(WorldBounds(lower,upper),radius,assetId,unknown));
      }
      final soundCount=r.count(20000);
      soundEffectAssets=List.generate(soundCount,(_)=>r.str(256));

      final zones=r.count(1000000);
      for(var i=0;i<zones;i++){
        skipBox();
        final ids=r.count(1000000);r.skip(ids*4);
      }

      final soundEffectCount=r.count(1000000);
      for(var i=0;i<soundEffectCount;i++){
        final assetId=r.i32(),center=r.vec(),radius=r.f32();
        if(assetId<0||assetId>=soundEffectAssets.length)r.fail('Efecto de sonido referencia asset inexistente: $assetId.');
        soundEffects.add(WorldSoundEffect(assetId,center,radius));
      }
      final restricted=r.count(1000000);r.skip(restricted*28);
      final portals=r.count(1000000);r.skip(portals*556);
      final spawns=r.count(1000000);r.skip(spawns*40);
      final named=r.count(1000000);r.skip(named*548);

      var npcRows=r.i32();
      if(npcRows<0)r.fail('Recuento de NPC WLD inválido.');
      while(npcRows>0){
        r.skip(4+4+12+4);
        final patrol=r.count(1000000);
        r.skip(patrol*12);
        npcRows-=patrol+1;
        if(npcRows<0)r.fail('Patrulla NPC WLD excede el recuento declarado.');
      }

      if(sig=='FLD'){
        skyFile=r.str(256);
        primaryCloud=r.str(256);
        secondaryCloud=r.str(256);
      }

      // unusedColor1, unusedColor2, fogColor, fogStart, fogEnd.
      r.skip(24);
      fog=r.vec();
      fogStart=r.f32();
      fogEnd=r.f32();
      r.end();
    }

    return WorldData(
      size, heights, types, layers, objects, layout,
      maniInstances:List.unmodifiable(maniInstances),
      skyFile:skyFile,
      primaryCloudFile:primaryCloud,
      secondaryCloudFile:secondaryCloud,
      musicAssets:List.unmodifiable(musicAssets),
      musicZones:List.unmodifiable(musicZones),
      soundEffectAssets:List.unmodifiable(soundEffectAssets),
      soundEffects:List.unmodifiable(soundEffects),
      fogColor:fog,
      fogStart:fogStart,
      fogEnd:fogEnd,
    );
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

  v.Vector3 normalAt(
    double x,
    double z, {
    double scale=.02,
    double offset=-200,
    double step=1,
  }){
    if(size==0||step<=0)return v.Vector3(0,1,0);
    final hL=heightAt(x-step,z,scale:scale,offset:offset);
    final hR=heightAt(x+step,z,scale:scale,offset:offset);
    final hD=heightAt(x,z-step,scale:scale,offset:offset);
    final hU=heightAt(x,z+step,scale:scale,offset:offset);
    final out=v.Vector3(-(hR-hL)/(2*step),1,(hU-hD)/(2*step));
    if(out.length2<1e-12)return v.Vector3(0,1,0);
    return out..normalize();
  }
}


class DgPart {
  final String texture;
  final MeshData mesh;
  const DgPart(this.texture,this.mesh);
}

class DgData {
  final v.Vector3 lower,upper;
  final int lightmapCount;
  final List<DgPart> parts;
  final List<SmodCollisionMesh> collisions;
  const DgData(this.lower,this.upper,this.lightmapCount,this.parts,this.collisions);

  v.Vector3 get center=>(lower+upper)*.5;

  v.Vector3 get presentationAnchor {
    DgPart? best;
    var bestScore=-double.infinity;
    for(final part in parts){
      final p=part.mesh.positions;
      if(p.length<9)continue;
      var minX=double.infinity,minY=double.infinity,minZ=double.infinity;
      var maxX=-double.infinity,maxY=-double.infinity,maxZ=-double.infinity;
      for(var i=0;i<p.length;i+=3){
        minX=math.min(minX,p[i]);maxX=math.max(maxX,p[i]);
        minY=math.min(minY,p[i+1]);maxY=math.max(maxY,p[i+1]);
        minZ=math.min(minZ,p[i+2]);maxZ=math.max(maxZ,p[i+2]);
      }
      final sx=maxX-minX,sy=maxY-minY,sz=maxZ-minZ;
      if(sy>1||sx<2||sz<2||sx>12||sz>12)continue;
      final cx=(minX+maxX)/2,cz=(minZ+maxZ)/2;
      final dx=cx-center.x,dz=cz-center.z,dist=math.sqrt(dx*dx+dz*dz);
      if(dist>20)continue;
      final score=part.mesh.vertices-dist*2-sy*20;
      if(score>bestScore){bestScore=score;best=part;}
    }
    if(best==null)return center;
    final p=best.mesh.positions;
    var minX=double.infinity,minZ=double.infinity,maxX=-double.infinity,maxZ=-double.infinity;
    for(var i=0;i<p.length;i+=3){
      minX=math.min(minX,p[i]);maxX=math.max(maxX,p[i]);
      minZ=math.min(minZ,p[i+2]);maxZ=math.max(maxZ,p[i+2]);
    }
    return v.Vector3((minX+maxX)/2,floorAt((minX+maxX)/2,(minZ+maxZ)/2),(minZ+maxZ)/2);
  }

  double floorAt(double x,double z,{double radius=6}){
    final ys=<double>[];
    for(final part in parts){
      final p=part.mesh.positions;
      for(var i=0;i<p.length;i+=3){
        if((p[i]-x).abs()<=radius&&(p[i+2]-z).abs()<=radius){
          final y=p[i+1];
          if(y.isFinite&&y<=lower.y+12)ys.add(y);
        }
      }
    }
    if(ys.isEmpty)return lower.y;
    ys.sort();
    // Dungeon floor vertices are repeated heavily; the median of the low
    // band is stable and avoids isolated wall/bounding-box points.
    return ys[ys.length~/2];
  }

  static DgData parse(Uint8List bytes,String source){
    final r=Bin(bytes,source);
    final lower=r.vec(),upper=r.vec();
    final textureCount=r.count(4096);
    final textures=List.generate(textureCount,(_)=>r.str(256));
    final lightmapCount=r.count(65536);
    final hasRoot=r.i32();
    final parts=<DgPart>[];
    final collisions=<SmodCollisionMesh>[];

    void readNode(){
      r.skip(12+24+24); // center, view box, collision box.
      final groupCount=r.count(100000);
      for(var g=0;g<groupCount;g++){
        final textureIndex=r.i32();
        if(textureIndex<0||textureIndex>=textures.length){
          r.fail('DG referencia textura inexistente: $textureIndex.');
        }
        final meshCount=r.count(100000);
        for(var m=0;m<meshCount;m++){
          r.i32(); // lightmap index; geometry is still valid without lightmap.
          final mesh=MeshData.rigid(r,boneField:true,lightUv:true);
          parts.add(DgPart(textures[textureIndex],mesh));
        }
      }
      final collisionType=r.i32();
      if(collisionType==1){
        final vertexCount=r.count(2000000);
        final vertices=<v.Vector3>[];
        for(var i=0;i<vertexCount;i++)vertices.add(r.vec());
        final faceCount=r.count(2000000);
        r.need(faceCount*6);
        final indices=Uint16List(faceCount*3);
        for(var i=0;i<indices.length;i++){
          final index=r.u16();
          if(index>=vertexCount)r.fail('Triángulo de colisión DG fuera de la malla.');
          indices[i]=index;
        }
        collisions.add(SmodCollisionMesh(List.unmodifiable(vertices),indices));
      }else if(collisionType!=0){
        r.fail('Tipo de colisión DG desconocido: $collisionType.');
      }
      for(var i=0;i<8;i++){
        if(r.i32()>0)readNode();
      }
    }

    if(hasRoot>0)readNode();
    r.end();
    return DgData(
      lower,upper,lightmapCount,List.unmodifiable(parts),List.unmodifiable(collisions),
    );
  }
}


class SvmapNpcWaypoint {
  final v.Vector3 position;
  final double yaw;
  const SvmapNpcWaypoint(this.position,this.yaw);
}
class SvmapNpcPlacement {
  final int type,id;
  final List<SvmapNpcWaypoint> route;
  const SvmapNpcPlacement(this.type,this.id,this.route);
  v.Vector3 get position=>route.first.position;
  double get yaw=>route.first.yaw;
}
class SvmapMobSpawn {
  final int id,count;
  SvmapMobSpawn(this.id,this.count);
}
class SvmapMobArea {
  final v.Vector3 lower,upper;
  final List<SvmapMobSpawn> mobs;
  SvmapMobArea(this.lower,this.upper,this.mobs);
  v.Vector3 get center=>(lower+upper)*.5;
}
class SvmapPortal {
  final v.Vector3 position,target;
  final int factionOrId,minLevel,maxLevel,targetMap;
  SvmapPortal(this.position,this.factionOrId,this.minLevel,this.maxLevel,this.targetMap,this.target);
}
class SvmapSpawnArea {
  final int faction;
  final v.Vector3 lower,upper;
  SvmapSpawnArea(this.faction,this.lower,this.upper);
  v.Vector3 get center=>(lower+upper)*.5;
}
class SvmapNamedArea {
  final v.Vector3 lower,upper;
  final int name1,name2;
  SvmapNamedArea(this.lower,this.upper,this.name1,this.name2);
}
class SvmapData {
  final int mapSize,cellSize;
  final List<SvmapNpcPlacement> npcs;
  final List<SvmapMobArea> mobAreas;
  final List<SvmapPortal> portals;
  final List<SvmapSpawnArea> spawns;
  final List<SvmapNamedArea> namedAreas;
  SvmapData(this.mapSize,this.cellSize,this.npcs,this.mobAreas,this.portals,this.spawns,this.namedAreas);
  static SvmapData parse(Uint8List bytes,String source){
    final r=Bin(bytes,source);
    final mapSize=r.i32();
    if(mapSize<=0||mapSize>16384)r.fail('Tamaño SVMAP inválido: $mapSize.');
    final mask=(mapSize*mapSize)~/8;r.skip(mask);
    final cellSize=r.i32();
    final ladders=r.count(100000);r.skip(ladders*12);
    final areas=<SvmapMobArea>[];
    final areaCount=r.count(100000);
    for(var i=0;i<areaCount;i++){
      final lower=r.vec(),upper=r.vec(),mobs=<SvmapMobSpawn>[];
      final n=r.count(10000);
      for(var j=0;j<n;j++){mobs.add(SvmapMobSpawn(r.u32(),r.u32()));}
      areas.add(SvmapMobArea(lower,upper,mobs));
    }
    final npcs=<SvmapNpcPlacement>[];
    final npcGroups=r.count(100000);
    for(var i=0;i<npcGroups;i++){
      final type=r.i32(),id=r.i32(),n=r.count(10000),route=<SvmapNpcWaypoint>[];
      for(var j=0;j<n;j++){route.add(SvmapNpcWaypoint(r.vec(),r.f32()));}
      if(route.isNotEmpty)npcs.add(SvmapNpcPlacement(type,id,List.unmodifiable(route)));
    }
    final portals=<SvmapPortal>[];
    final portalCount=r.count(100000);
    for(var i=0;i<portalCount;i++){
      final position=r.vec(),factionOrId=r.i32(),minLevel=r.u16(),maxLevel=r.u16(),targetMap=r.u32(),target=r.vec();
      portals.add(SvmapPortal(position,factionOrId,minLevel,maxLevel,targetMap,target));
    }
    final spawns=<SvmapSpawnArea>[];
    final spawnCount=r.count(100000);
    for(var i=0;i<spawnCount;i++){
      r.i32();final faction=r.i32();r.i32();final lower=r.vec(),upper=r.vec();
      spawns.add(SvmapSpawnArea(faction,lower,upper));
    }
    final named=<SvmapNamedArea>[];
    final namedCount=r.count(100000);
    for(var i=0;i<namedCount;i++){
      final lower=r.vec(),upper=r.vec(),name1=r.i32(),name2=r.i32();
      named.add(SvmapNamedArea(lower,upper,name1,name2));
    }
    if(r.offset>bytes.length)r.fail('SVMAP truncado.');
    return SvmapData(mapSize,cellSize,npcs,areas,portals,spawns,named);
  }
}
class StaticPart {
  final String texture;
  final MeshData mesh;
  StaticPart(this.texture, this.mesh);
}

class VaniMeshData {
  final String texture,source;
  final Uint16List indices;
  final List<Float32List> positions,normals,uv;
  const VaniMeshData(this.texture,this.indices,this.positions,this.normals,this.uv,this.source);
  int get frameCount=>positions.length;
  int get vertices=>positions.isEmpty?0:positions.first.length~/3;
  MeshData frame(int index){
    if(frameCount==0)throw FormatException('$source · VAni sin frames.');
    final i=index%frameCount;
    return MeshData(
      Float32List.fromList(positions[i]),
      Float32List.fromList(normals[i]),
      Float32List.fromList(uv[i]),
      Uint16List.fromList(indices),
      Uint8List(0),
      Float32List(0),
      const [],
      source,
    );
  }
}

class VaniData {
  final v.Vector3 center,lower,upper,lower2,upper2;
  final double radius;
  final int frameCount,unknown1,unknown2;
  final List<VaniMeshData> meshes;
  const VaniData(
    this.center,this.radius,this.lower,this.upper,this.frameCount,this.unknown1,
    this.meshes,this.lower2,this.upper2,this.unknown2,
  );
  static VaniData parse(Uint8List bytes,String source){
    final r=Bin(bytes,source);
    final center=r.vec(),radius=r.f32(),lower=r.vec(),upper=r.vec();
    final meshCount=r.count(10000),frameCount=r.count(10000),unknown1=r.i32();
    if(frameCount==0)r.fail('VAni sin frames.');
    final meshes=<VaniMeshData>[];
    for(var meshIndex=0;meshIndex<meshCount;meshIndex++){
      final texture=r.str();
      final faceCount=r.count(2000000);
      r.need(faceCount*6);
      final rawIndices=Uint16List(faceCount*3);
      for(var i=0;i<rawIndices.length;i++)rawIndices[i]=r.u16();
      final vertexCount=r.count(65535);
      final total=vertexCount*frameCount;
      if(total>50000000)r.fail('VAni excede el límite de vertices animados: $total.');
      final positions=List.generate(frameCount,(_)=>Float32List(vertexCount*3));
      final normals=List.generate(frameCount,(_)=>Float32List(vertexCount*3));
      final uv=List.generate(frameCount,(_)=>Float32List(vertexCount*2));
      for(var frame=0;frame<frameCount;frame++){
        for(var vertex=0;vertex<vertexCount;vertex++){
          final p=positions[frame],n=normals[frame],t=uv[frame],po=vertex*3,to=vertex*2;
          p[po]=r.f32();p[po+1]=r.f32();p[po+2]=r.f32();
          n[po]=r.rawFloat();n[po+1]=r.rawFloat();n[po+2]=r.rawFloat();
          r.i32(); // VAni bone id; native files use -1.
          t[to]=r.f32();t[to+1]=r.f32();
        }
      }
      for(final index in rawIndices){if(index>=vertexCount)r.fail('Triángulo VAni fuera de la malla.');}
      meshes.add(VaniMeshData(
        texture,rawIndices,List.unmodifiable(positions),List.unmodifiable(normals),
        List.unmodifiable(uv),'$source#$meshIndex',
      ));
    }
    final lower2=r.vec(),upper2=r.vec(),unknown2=r.i32();
    r.end();
    return VaniData(
      center,radius,lower,upper,frameCount,unknown1,List.unmodifiable(meshes),
      lower2,upper2,unknown2,
    );
  }
}

class SmodCollisionMesh {
  final List<v.Vector3> vertices;
  final Uint16List indices;
  const SmodCollisionMesh(this.vertices,this.indices);
  int get triangles=>indices.length~/3;
}

class SmodData {
  final v.Vector3 center,viewLower,viewUpper,collisionLower,collisionUpper;
  final double radius;
  final List<StaticPart> parts;
  final List<SmodCollisionMesh> collisions;
  const SmodData(
    this.center,this.radius,this.viewLower,this.viewUpper,
    this.parts,this.collisionLower,this.collisionUpper,this.collisions,
  );
}

SmodData readSmodData(Uint8List bytes,String source){
  final r=Bin(bytes,source);
  final center=r.vec(),radius=r.f32(),viewLower=r.vec(),viewUpper=r.vec();
  final parts=<StaticPart>[];
  final textured=r.count(10000);
  for(var i=0;i<textured;i++){
    final tex=r.str();
    parts.add(StaticPart(tex,MeshData.rigid(r,boneField:true)));
  }
  final collisionLower=r.vec(),collisionUpper=r.vec();
  final collisions=<SmodCollisionMesh>[];
  final collisionCount=r.count(10000);
  for(var i=0;i<collisionCount;i++){
    final vertexCount=r.count(1000000);
    final vertices=<v.Vector3>[];
    for(var j=0;j<vertexCount;j++)vertices.add(r.vec());
    final faceCount=r.count(2000000);
    r.need(faceCount*6);
    final indices=Uint16List(faceCount*3);
    for(var j=0;j<indices.length;j++){
      final index=r.u16();
      if(index>=vertexCount)r.fail('Triángulo de colisión SMOD fuera de la malla.');
      indices[j]=index;
    }
    collisions.add(SmodCollisionMesh(List.unmodifiable(vertices),indices));
  }
  r.end();
  return SmodData(
    center,radius,viewLower,viewUpper,List.unmodifiable(parts),
    collisionLower,collisionUpper,List.unmodifiable(collisions),
  );
}

List<StaticPart> readSmod(Uint8List bytes,String source)=>readSmodData(bytes,source).parts;
