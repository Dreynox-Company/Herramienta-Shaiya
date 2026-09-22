import 'dart:convert';
import 'dart:io';
import 'package:herramienta_shaiya/core/client_locale.dart';
import 'package:herramienta_shaiya/core/game_text_codec.dart';
import 'package:herramienta_shaiya/core/game_metadata.dart';
import 'package:herramienta_shaiya/core/world_resources.dart';
import 'package:herramienta_shaiya/editor/schema_reader.dart';
import 'package:crypto/crypto.dart';

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln(
      'Uso: dart audit_spanish_client.dart CARPETA_JUEGO informe.json',
    );
    exitCode = 2;
    return;
  }
  final root = Directory(args[0]), out = File(args[1]);
  final files = root
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .toList();
  final reports = <Map<String, Object?>>[];
  final changes = <Map<String, Object?>>[];
  for (final f in files.where(
    (p) =>
        p.path.toLowerCase().endsWith('.sdata') ||
        p.path.toLowerCase().endsWith('.svmap'),
  )) {
    final path = f.path.substring(root.path.length + 1).replaceAll('\\', '/');
    final bytes = f.readAsBytesSync();
    final doc = EditorReader.open(
      bytes,
      path,
      encoding: ClientLocale.encodingForPath(path),
    );
    final exported = doc.exportBytes();
    final same =
        sha256.convert(bytes).toString() == sha256.convert(exported).toString();
    final sample = <String>[];
    if (doc.profile == 'binary' && ClientLocale.languageOf(path) == 'es') {
      for (var i = 0; i < doc.rows.length && sample.length < 6; i++) {
        for (final field in doc.fields(i).where((f) => f.spec.text)) {
          final s = doc.read(field);
          if (s.contains(RegExp('[áéíóúñÑü¿¡]'))) {
            sample.add(s);
            break;
          }
        }
      }
    }
    var edited = false;
    String? editError;
    if (doc.complete && doc.rows.isNotEmpty) {
      for (final field in doc.fields(0)) {
        if (field.spec.text &&
            field.spec.editable &&
            doc.codec.encoding != GameTextEncoding.automatic) {
          try {
            final original = doc.read(field), v = '$original ñ';
            doc.edit(0, field, v);
            final copy = doc.exportBytes();
            final check = EditorReader.open(
              copy,
              path,
              encoding: doc.codec.encoding,
              forceProfile: doc.profile,
            );
            final match = check
                .fields(0)
                .firstWhere((p) => p.spec.name == field.spec.name);
            edited = check.read(match) == v;
            doc.undo();
          } catch (e) {
            editError = '$e';
          }
          break;
        }
      }
    }
    reports.add({
      'path': path,
      'sha256': sha256.convert(bytes).toString(),
      'profile': doc.profile,
      'encoding': doc.codec.encoding.name,
      'records': doc.rows.length,
      'complete': doc.complete,
      'lossless_roundtrip': same,
      'test_edit_reread': edited,
      'edit_error': editError,
      'samples': sample,
      'warnings': doc.warnings.take(2).toList(),
    });
    if (!same ||
        sha256.convert(f.readAsBytesSync()).toString() !=
            sha256.convert(bytes).toString()) {
      changes.add({'path': path, 'error': 'Integrity mismatch'});
    }
  }
  final names = <String, Object?>{};
  for (final p in files.where(
    (p) =>
        p.path.endsWith('dbitemtext_spn.sdata') ||
        p.path.endsWith('dbskilltext_spn.sdata') ||
        p.path.endsWith('dbnpcskilltext_spn.sdata') ||
        p.path.endsWith('dbmonstertext_spn.sdata'),
  )) {
    try {
      final b = p.readAsBytesSync(),
          path = p.path.substring(root.path.length + 1);
      Object data;
      if (path.contains('dbitemtext')) {
        final n = readItemNames(b, path);
        data = {
          'records': n.length,
          'sample': n
              .where((v) => v.name.contains('ó'))
              .take(4)
              .map((v) => {'key': v.key, 'name': v.name})
              .toList(),
        };
      } else if (path.contains('skilltext')) {
        final n = readSkillNames(b, path);
        data = {
          'records': n.length,
          'sample': n
              .where((v) => v.name.contains('í'))
              .take(4)
              .map((v) => {'key': v.key, 'name': v.name})
              .toList(),
        };
      } else {
        final n = readMonsterNames(b, path);
        data = {
          'records': n.length,
          'sample': n.entries
              .where((v) => v.value.contains('ñ'))
              .take(4)
              .map((v) => {'key': v.key, 'name': v.value})
              .toList(),
        };
      }
      names[path] = data;
    } catch (e) {
      names[p.path] = {'error': '$e'};
    }
  }
  final maps = <String, Object?>{};
  final w = files.where((f) => f.path.endsWith('/World/1.wld')).firstOrNull;
  if (w != null) {
    try {
      final world = WorldResource.parse(w.readAsBytesSync(), w.path);
      final t = ClientLocale.indexedText(
        File('${w.parent.path}/1_spn.txt').readAsBytesSync(),
        '1_spn.txt',
      );
      maps['world/1.wld'] = {
        'areas': world.areas.length,
        'labels': t.length,
        'samples': List.generate(
          world.areas.length < 5 ? world.areas.length : 5,
          (i) => {
            'index': i,
            'name': world.areas[i].name,
            'comment': world.areas[i].comment,
            'spanish': t[i],
          },
        ),
      };
    } catch (e) {
      maps['error'] = '$e';
    }
  }
  final report = {
    'source': 'Juego.zip supplied by user',
    'total_tables': reports.length,
    'complete_schemas': reports.where((r) => r['complete'] == true).length,
    'lossless_roundtrips': reports
        .where((r) => r['lossless_roundtrip'] == true)
        .length,
    'edit_reread_passes': reports
        .where((r) => r['test_edit_reread'] == true)
        .length,
    'source_modified': false,
    'failures': changes,
    'name_readers': names,
    'world_labels': maps,
    'tables': reports,
  };
  out.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
  stdout.writeln(
    jsonEncode({
      for (final e in report.entries)
        if (!['tables', 'name_readers', 'world_labels'].contains(e.key))
          e.key: e.value,
    }),
  );
  if (changes.isNotEmpty) exitCode = 1;
}
