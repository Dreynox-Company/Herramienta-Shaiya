import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart' as v;
import 'package:herramienta_shaiya/core/formats.dart';
import 'package:herramienta_shaiya/core/rig_anchors.dart';
import 'package:herramienta_shaiya/core/extra_motion.dart';

void main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln('Uso: audit_rig_anchors DATA informe.json [suplemento.gz]');
    exitCode = 2;
    return;
  }
  final root = Directory(args[0]);
  final files = {
    for (final f in root.listSync(recursive: true).whereType<File>())
      f.path
              .substring(root.path.length + 1)
              .replaceAll('\\', '/')
              .toLowerCase():
          f,
  };
  String? resolve(String base, String dir, String raw) {
    final name = raw.replaceAll('\\', '/').toLowerCase();
    for (final p in ['$base/$dir/$name', '$base/$name', name]) {
      if (files.containsKey(p)) return p;
    }
    return null;
  }

  final cache = <String, MeshData>{};
  final report = <Map<String, Object?>>[];
  for (final p in files.keys.where(
    (p) => p.startsWith('vehicle/') && p.endsWith('.mon'),
  )) {
    final base = p.substring(0, p.lastIndexOf('/'));
    for (final c in readMon(files[p]!.readAsBytesSync(), p)) {
      try {
        final parts = <MeshData>[];
        for (final r in c.parts.where((r) => !r.isNull)) {
          final path = resolve(base, '3dc', r.mesh);
          if (path == null) throw FormatException('Malla ausente: ${r.mesh}');
          parts.add(
            cache.putIfAbsent(
              path,
              () => MeshData.skinned(files[path]!.readAsBytesSync(), path),
            ),
          );
        }
        final clips = <String, ClipData>{};
        for (final e in c.animations.entries) {
          if (!['Respirar', 'Reposo', 'Caminar', 'Correr'].contains(e.key)) {
            continue;
          }
          final path = resolve(base, 'ani', e.value);
          if (path == null) continue;
          clips[e.key] = ClipData.parse(files[path]!.readAsBytesSync(), path);
        }
        final reference =
            clips['Respirar'] ?? clips['Reposo'] ?? clips.values.first;
        final seat = SurfaceAnchor.locate(parts, reference);
        if (seat == null) {
          report.add({
            'source': p,
            'id': c.id,
            'name': c.name,
            'status': 'manual-calibration',
            'reason': 'No se encontró superficie central segura',
          });
          continue;
        }
        double residual = 0, motion = 0;
        final initial = seat.position(reference.pose(0));
        for (final clip in clips.values) {
          for (var k = 0; k < 12; k++) {
            final pose = clip.pose(k * clip.duration / 12),
                target = seat.position(pose),
                q = seat.rotation(pose);
            if (!target.storage.every((n) => n.isFinite && n.abs() < 500)) {
              throw const FormatException(
                'Asiento no finito o fuera de escala.',
              );
            }
            final pelvis = v.Vector3(.01, 1.1, -.05);
            final matrix = seatedTransform(target, q, pelvis, height: .04);
            residual = math.max(
              residual,
              (matrix.transformed3(pelvis) - (target + v.Vector3(0, .04, 0)))
                  .length,
            );
            motion = math.max(motion, (initial - target).length);
          }
        }
        if (residual > 1e-6) {
          throw FormatException('Deriva de pelvis: $residual');
        }
        report.add({
          'source': p,
          'id': c.id,
          'name': c.name,
          'status': 'geometry-and-pose-verified',
          'seat': initial.storage.toList(),
          'animationCount': clips.length,
          'pelvisResidual': residual,
          'seatMotion': motion,
        });
      } catch (e) {
        report.add({
          'source': p,
          'id': c.id,
          'name': c.name,
          'status': 'diagnostic',
          'reason': '$e',
        });
      }
    }
  }
  final extraReport = <Map<String, Object?>>[];
  if (args.length > 2) {
    final extras = ExtraMotionLibrary.decode(File(args[2]).readAsBytesSync());
    for (final profile in extras.profiles.values) {
      final original = files.entries
          .where(
            (e) => ['normal', 'nomal', 'nromal'].any(
              (suffix) =>
                  e.key.endsWith('/${profile.archetype}_000_$suffix.ani'),
            ),
          )
          .firstOrNull;
      final match =
          original != null &&
          profile.matches(
            profile.archetype,
            profile.sex == 'Femenino',
            ClipData.parse(original.value.readAsBytesSync(), original.key),
          );
      extraReport.add({
        'archetype': profile.archetype,
        'originalHierarchyMatches': match,
        'mountedAttacks': profile.mounted.keys.toList(),
        'flightClips': 2,
      });
    }
  }
  File(args[1]).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'mounts': report,
      'extras': extraReport,
      'scope': 'Numeric animation/geometry verification; not a visual certification of all mount combinations.',
    }),
  );
  stdout.writeln(
    'Monturas: ${report.length}; geométricas: ${report.where((r) => r['status'] == 'geometry-and-pose-verified').length}; perfiles: ${extraReport.length}',
  );
}
