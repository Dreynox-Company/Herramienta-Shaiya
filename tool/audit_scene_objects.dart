import 'dart:io';
import 'dart:convert';

import 'package:herramienta_shaiya/core/scene_objects.dart';
import 'package:herramienta_shaiya/core/world_resources.dart';

void main(List<String> args) async {
  final counts = <String, int>{}, errors = <String>[];
  await for (final entry in Directory(args[0]).list(recursive: true)) {
    if (entry is! File) continue;
    final ext = entry.path.split('.').last.toLowerCase();
    if (!['smod', 'vani', 'env'].contains(ext)) continue;
    try {
      final b = await entry.readAsBytes();
      if (ext == 'smod') {
        SmodResource.parse(b, entry.path);
      } else if (ext == 'vani') {
        VertexAnimation.parse(b, entry.path);
      } else {
        readEnvironment(b, entry.path);
      }
      counts.update(ext, (n) => n + 1, ifAbsent: () => 1);
    } catch (e) {
      errors.add('$e');
    }
  }
  final result = {'verified': counts, 'errors': errors};
  await File(
    args[1],
  ).writeAsString(const JsonEncoder.withIndent(' ').convert(result));
  stdout.writeln(counts);
  for (final e in errors.take(20)) {
    stdout.writeln(e);
  }
  stdout.writeln('${errors.length} incompatibilities');
}
