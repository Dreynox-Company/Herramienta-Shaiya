/// Compose original, compatible upper-body attacks over the original seated
/// lower body. No cross-class retargeting or fabricated action fallback.
/// Run locally with an owned DATA folder and the separate flight supplement.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:vector_math/vector_math_64.dart' as v;
import 'package:herramienta_shaiya/core/formats.dart';
import 'package:herramienta_shaiya/core/extra_motion.dart';

const families = <String, String>{
  'mounted_sword': r'_\d{3}_onattack0?[1-4]\.ani$',
  'mounted_twohand': r'_\d{3}_thattack0?[1-4]\.ani$',
  'mounted_dual': r'_\d{3}_duattack0?[1-4]\.ani$',
  'mounted_spear': r'_\d{3}_spattack0?[1-4]\.ani$',
  'mounted_bow': r'_\d{3}_bowattack\.ani$',
  'mounted_crossbow': r'_\d{3}_crboattack\.ani$',
  'mounted_staff': r'_\d{3}_sfattack0?[1-2]\.ani$',
  'mounted_reverse_dagger': r'_\d{3}_rsattack0?[1-4]\.ani$',
  'mounted_dagger': r'_\d{3}_nfattack0?[1-4]\.ani$',
  'mounted_claws': r'_\d{3}_knattack0?[1-4]\.ani$',
};

bool sameHierarchy(ClipData c, List<int> p) =>
    c.bones.length == p.length &&
    List.generate(p.length, (i) => c.bones[i].parent == p[i]).every((x) => x);

ClipData? bodyClip(ClipData c, List<int> parents) {
  if (c.bones.length < parents.length) return null;
  for (var i = 0; i < parents.length; i++) {
    if (c.bones[i].parent != parents[i]) return null;
  }
  // Some original ANI append separate weapon/companion hierarchies. The
  // complete body prefix must match and every discarded track must belong
  // exclusively to an independent trailing hierarchy (not a body child).
  for (var i = parents.length; i < c.bones.length; i++) {
    final parent = c.bones[i].parent;
    if (parent >= 0 && parent < parents.length) return null;
  }
  return ClipData(c.source, c.duration, c.bones.take(parents.length).toList());
}

double blendWeight(double t) {
  double smooth(double x) {
    final u = x.clamp(0.0, 1.0);
    return u * u * (3 - 2 * u);
  }

  return math.min(smooth(t / .16), smooth((1 - t) / .23));
}

Uint8List compose(ClipData seat, ClipData attack, int spineRoot) {
  final frames = (attack.duration * 30).round().clamp(6, 300);
  final rest = seat.pose(0, loop: false);
  bool upper(int bone) {
    var b = bone;
    while (b >= 0) {
      if (b == spineRoot) return true;
      b = seat.bones[b].parent;
    }
    return false;
  }

  final out = BytesBuilder(copy: false);
  void i32(int n) => out.add(
    (ByteData(4)..setInt32(0, n, Endian.little)).buffer.asUint8List(),
  );
  void f32(double n) {
    if (!n.isFinite) throw const FormatException('Pose no finita.');
    out.add(
      (ByteData(4)..setFloat32(0, n, Endian.little)).buffer.asUint8List(),
    );
  }

  i32(0);
  i32(frames);
  out.add(
    (ByteData(
      2,
    )..setUint16(0, seat.bones.length, Endian.little)).buffer.asUint8List(),
  );
  for (var b = 0; b < seat.bones.length; b++) {
    i32(seat.bones[b].parent);
    for (final n in rest[b].storage) {
      f32(n);
    }
    final p = v.Vector3.zero(), q = v.Quaternion.identity();
    seat.bones[b].at(0).decompose(p, q, v.Vector3.zero());
    final isUpper = upper(b);
    i32(isUpper ? frames + 1 : 1);
    for (var k = 0; k <= (isUpper ? frames : 0); k++) {
      var rot = q;
      if (isUpper) {
        final aq = v.Quaternion.identity();
        attack.bones[b]
            .at(k / frames * attack.duration)
            .decompose(v.Vector3.zero(), aq, v.Vector3.zero());
        rot = BoneTrack.slerp(q, aq, blendWeight(k / frames));
      }
      i32(k);
      for (final n in rot.storage) {
        f32(n);
      }
    }
    // Translation is seated in all channels: bone lengths and the pelvis do
    // not acquire ground-attack root motion. Arms use original local rotations.
    i32(1);
    i32(0);
    for (final n in p.storage) {
      f32(n);
    }
  }
  return out.takeBytes();
}

void main(List<String> args) {
  if (args.length != 4 || !Directory(args[0]).existsSync()) {
    stderr.writeln(
      'Uso: prepare_mounted_supplement DATA vuelo.gz salida.gz informe.json',
    );
    exitCode = 2;
    return;
  }
  final root = Directory(args[0]).absolute;
  final source = File(args[1]).absolute, dest = File(args[2]).absolute;
  if (dest.path == source.path || dest.existsSync()) {
    throw const FileSystemException('La salida debe ser una copia nueva.');
  }
  final originalPack = source.readAsBytesSync();
  ExtraMotionLibrary.decode(originalPack);
  final pack = jsonDecode(utf8.decode(gzip.decode(originalPack))) as Map;
  final files =
      root
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.ani'))
          .toList()
        ..sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
  final report = <Map<String, Object?>>[];
  for (final row in pack['profiles'] as List) {
    final id = row['archetype'] as String;
    final parents = (row['parents'] as List).cast<int>();
    final prefix = '${id}_';
    final candidates = files
        .where((f) => f.uri.pathSegments.last.toLowerCase().startsWith(prefix))
        .toList();
    File? find(String pattern) {
      for (final f in candidates.where(
        (f) => RegExp(pattern).hasMatch(f.path.toLowerCase()),
      )) {
        try {
          if (bodyClip(ClipData.parse(f.readAsBytesSync(), f.path), parents) !=
              null) {
            return f;
          }
        } on FormatException {
          continue;
        }
      }
      return null;
    }

    final seatFile = find(r'_021_.*\.ani$');
    if (seatFile == null) {
      report.add({'archetype': id, 'status': 'missing-compatible-seat'});
      continue;
    }
    final seat = bodyClip(
      ClipData.parse(seatFile.readAsBytesSync(), seatFile.path),
      parents,
    )!;
    final spineRoot = ((row['semantic'] as Map)['spine'] as List).first as int;
    if (spineRoot <= 1 || spineRoot >= parents.length) {
      throw const FormatException('Raíz de torso inválida.');
    }
    final clips = row['clips'] as Map;
    final added = <String, Object?>{};
    for (final family in families.entries) {
      final file = find(family.value);
      if (file == null) continue;
      final attack = bodyClip(
        ClipData.parse(file.readAsBytesSync(), file.path),
        parents,
      )!;
      final data = compose(seat, attack, spineRoot);
      final check = ClipData.parse(data, 'extra:$id/${family.key}');
      if (!sameHierarchy(check, parents)) {
        throw StateError('Jerarquía alterada');
      }
      final rest = seat.pose(0, loop: false);
      double seam = 0, lowerDrift = 0;
      for (var k = 0; k <= 60; k++) {
        final pose = check.pose(k / 60 * check.duration, loop: false);
        for (var b = 0; b < parents.length; b++) {
          var at = b;
          var upper = false;
          while (at >= 0) {
            if (at == spineRoot) {
              upper = true;
              break;
            }
            at = parents[at];
          }
          for (var c = 0; c < 16; c++) {
            final n = pose[b].storage[c];
            if (!n.isFinite || n.abs() > 1000) {
              throw StateError('Pose fuera de rango');
            }
            final delta = (n - rest[b].storage[c]).abs();
            if (k == 0 || k == 60) seam = math.max(seam, delta);
            if (!upper) lowerDrift = math.max(lowerDrift, delta);
          }
        }
      }
      if (seam > 0.0001 || lowerDrift > 0.0001) {
        throw StateError('Piernas o inicio/final no se conservan');
      }
      clips[family.key] = {
        'data': base64Encode(data),
        'sha256': sha256.convert(data).toString(),
      };
      added[family.key] = {
        'source': file.path
            .substring(root.path.length + 1)
            .replaceAll('\\', '/'),
        'sourceSha256': sha256.convert(file.readAsBytesSync()).toString(),
        'outputSha256': sha256.convert(data).toString(),
        'duration': check.duration,
        'seamMax': seam,
        'lowerBodyDriftMax': lowerDrift,
      };
    }
    report.add({
      'archetype': id,
      'status': 'composed-compatible-original-attacks',
      'seatSource': seatFile.path
          .substring(root.path.length + 1)
          .replaceAll('\\', '/'),
      'seatSha256': sha256.convert(seatFile.readAsBytesSync()).toString(),
      'clips': added,
      'missingFamilies': families.keys
          .where((key) => !added.containsKey(key))
          .toList(),
    });
  }
  pack['mountedOrigin'] =
      'Upper-body original local rotations over original seated translations and lower-body; smoothstep entry/exit; missing compatible families are not fabricated.';
  final raw = utf8.encode(jsonEncode(pack));
  if (raw.length > 8 * 1024 * 1024) {
    throw StateError('Suplemento expandido demasiado grande');
  }
  final bytes = Uint8List.fromList(gzip.encode(raw));
  ExtraMotionLibrary.decode(bytes);
  dest.parent.createSync(recursive: true);
  dest.writeAsBytesSync(bytes, flush: true);
  File(args[3]).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'sourceSupplementSha256': sha256.convert(originalPack).toString(),
      'outputSupplementSha256': sha256.convert(bytes).toString(),
      'expandedBytes': raw.length,
      'compressedBytes': bytes.length,
      'scope':
          'Numeric compatibility, preserved lower-body and smooth endpoints; not a visual certification of every character/mount/weapon combination or online game installation.',
      'profiles': report,
    }),
    flush: true,
  );
  stdout.writeln(
    '${report.length} perfiles, ${report.fold<int>(0, (n, r) => n + ((r['clips'] as Map?)?.length ?? 0))} ataques propios compatibles, ${raw.length} bytes expandidos.',
  );
}
