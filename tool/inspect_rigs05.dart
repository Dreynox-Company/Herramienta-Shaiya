import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;

import 'package:herramienta_shaiya/core/formats.dart';

void main(List<String> args) {
  final root = args[0];
  final map = <String, String>{
    for (final f in Directory(root).listSync(recursive: true).whereType<File>())
      f.path.substring(root.length + 1).toLowerCase(): f.path,
  };
  final rows = <Map<String, Object?>>[];
  for (final path in map.keys.where(
    (p) =>
        p.endsWith('.mon') &&
        (p.startsWith('vehicle/') || p.startsWith('character/wing/')),
  )) {
    final records = readMon(File(map[path]!).readAsBytesSync(), path);
    for (final c in records) {
      final base = path.substring(0, path.lastIndexOf('/'));
      String? resolve(String name, String dir) =>
          map['$base/$dir/${name.toLowerCase()}'];
      if (c.id > 40 && !args.contains('--all')) continue;
      try {
        final parts = c.parts
            .map(
              (p) => MeshData.skinned(
                File(resolve(p.mesh, '3dc')!).readAsBytesSync(),
                p.mesh,
              ),
            )
            .toList();
        final anims = {
          for (final e in c.animations.entries)
            if (resolve(e.value, 'ani') != null)
              e.key: resolve(e.value, 'ani')!,
        };
        final cpath =
            anims['Respirar'] ?? anims['Reposo'] ?? anims.values.first;
        final clip = ClipData.parse(File(cpath).readAsBytesSync(), cpath);
        final min = [double.infinity, double.infinity, double.infinity],
            max = [-double.infinity, -double.infinity, -double.infinity];
        for (final p in parts) {
          for (var i = 0; i < p.positions.length; i++) {
            min[i % 3] = math.min(min[i % 3], p.positions[i]);
            max[i % 3] = math.max(max[i % 3], p.positions[i]);
          }
        }
        rows.add({
          'source': path,
          'id': c.id,
          'name': c.name,
          'heightMeta': c.height,
          'parts': c.parts.map((p) => p.mesh).toList(),
          'min': min,
          'max': max,
          'bones': clip.bones.length,
          'anims': c.animations,
          'bonePoints': clip
              .pose(0)
              .take(10)
              .map((m) => m.getTranslation().storage.toList())
              .toList(),
        });
      } catch (e) {
        rows.add({'source': path, 'id': c.id, 'error': '$e'});
      }
    }
  }
  File(args[1])
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(rows));
}
