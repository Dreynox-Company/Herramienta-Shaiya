import 'dart:io';
import 'dart:convert';

import 'package:herramienta_shaiya/editor/schema_reader.dart';
import 'package:herramienta_shaiya/core/game_text_codec.dart';
import 'package:herramienta_shaiya/core/seed_data.dart';

void main(List<String> args) async {
  if (args.length < 2 || !Directory(args[0]).existsSync()) {
    stderr.writeln('Uso: audit_editor_data DATA informe.json [filtro]');
    exitCode = 2;
    return;
  }
  final root = Directory(args[0]);
  final report = <Map<String, Object?>>[];
  for (final f
      in root
          .listSync(recursive: true)
          .whereType<File>()
          .where(
            (f) =>
                f.path.toLowerCase().endsWith('.sdata') ||
                f.path.toLowerCase().endsWith('.svmap'),
          )) {
    final name = f.path.substring(root.path.length + 1);
    if (args.length > 2 &&
        !name.toLowerCase().contains(args[2].toLowerCase())) {
      continue;
    }
    try {
      final original = f.readAsBytesSync(),
          doc = EditorReader.open(
            original,
            name,
            encoding: GameTextEncoding.big5,
          );
      final same = doc.exportBytes();
      bool equal = same.length == original.length;
      for (var i = 0; equal && i < same.length; i++) {
        if (same[i] != original[i]) equal = false;
      }
      if (!equal) throw StateError('Exportación sin cambios difiere.');
      bool edit = false;
      if (doc.rows.isNotEmpty) {
        final editable = doc
            .fields(0)
            .where(
              (v) => v.spec.type != 'opaque' && !v.spec.text && v.spec.editable,
            )
            .toList();
        if (editable.isNotEmpty) {
          final field = editable.first, value = doc.read(field);
          final n = BigInt.tryParse(value);
          if (n != null) {
            final next = n == BigInt.zero ? '1' : '0';
            doc.edit(0, field, next);
            final output = doc.exportBytes();
            if (doc.encrypted) SeedData.decode(output, verifyChecksum: true);
            final fresh = EditorReader.open(
              output,
              name,
              encoding: doc.codec.encoding,
              forceProfile: doc.profile,
            );
            if (fresh.complete != doc.complete ||
                fresh.rows.length != doc.rows.length ||
                fresh.read(
                      fresh
                          .fields(0)
                          .firstWhere((f) => f.spec.name == field.spec.name),
                    ) !=
                    next) {
              throw StateError('Relectura no conserva cambio.');
            }
            doc.undo();
            if (doc.dirty) throw StateError('Undo no regresa al original.');
            edit = true;
          }
        }
      }
      report.add({
        ...doc.report(),
        'unchangedExact': equal,
        'editReread': edit,
      });
      stdout.writeln(
        '$name ${doc.profile} rows=${doc.rows.length} ${doc.complete ? 'OK' : 'NO'}',
      );
    } catch (e) {
      report.add({'path': name, 'error': e.toString()});
      stdout.writeln('ERROR $name $e');
    }
  }
  File(
    args.length > 1 ? args[1] : 'audit_editor.json',
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
}
