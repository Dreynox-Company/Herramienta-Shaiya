import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/seed_data.dart';
import 'package:herramienta_shaiya/core/archive_index.dart';
import 'package:herramienta_shaiya/data/archive_source.dart';
import 'package:herramienta_shaiya/data/archive_write.dart';
import 'package:herramienta_shaiya/data/archive_export.dart';
import 'package:herramienta_shaiya/data/directory_pack.dart';
import 'package:herramienta_shaiya/data/file_save.dart';
import 'package:herramienta_shaiya/editor/schema_reader.dart';
import 'package:herramienta_shaiya/editor/structure_editor.dart';

import 'editor_document_test.dart' show binaryTable;
import 'archive_test.dart' show sampleIndex;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final encoded in [false, true]) {
    test(
      'explicit IDs duplicate/delete are lossless and undoable, SEED=$encoded',
      () {
        final b = binaryTable(
          ['ItemType', 'ItemTypeId', 'Buy', 'Sell'],
          [
            [1, 1, 100, 30],
            [1, 2, 200, 40],
          ],
        );
        final original = encoded ? SeedData.encode(b) : b;
        final d = EditorReader.open(original, 'binarysdata/dbitemdata.sdata');
        d.edit(0, d.fields(0)[3], '-1');
        StructureEditor.duplicate(d, 0, {'ItemType': '1', 'ItemTypeId': '3'});
        expect(d.rows.length, 3);
        expect(d.structuralChanges, true);
        expect(d.read(d.fields(0)[1]), '1');
        expect(d.read(d.fields(2)[1]), '3');
        expect(d.read(d.fields(2)[3]), '-1');
        expect(SeedData.isEncoded(d.exportBytes()), encoded);
        expect(() => d.exportPatch(), throwsFormatException);
        d.undo();
        expect(d.rows.length, 2);
        expect(d.read(d.fields(0)[3]), '-1');
        d.undo();
        expect(d.exportBytes(), original);
        d.redo();
        d.redo();
        StructureEditor.delete(d, 1);
        expect(d.rows.length, 2);
        expect(d.read(d.fields(1)[1]), '3');
        d.undo();
        expect(d.rows.length, 3);
        d.discard();
        expect(d.exportBytes(), original);
      },
    );
  }
  test(
    'duplicate identity rejects equivalent leading-zero key and never mutates source',
    () {
      final b = binaryTable(
            ['ItemType', 'ItemTypeId'],
            [
              [1, 1],
            ],
          ),
          d = EditorReader.open(b, 'dbitemdata.sdata');
      expect(
        () => StructureEditor.duplicate(d, 0, {
          'ItemType': '01',
          'ItemTypeId': '001',
        }),
        throwsFormatException,
      );
      expect(d.exportBytes(), b);
    },
  );
  test(
    'directory construction includes unknown formats and Unicode files with overrides',
    () async {
      final dir = await Directory.systemTemp.createTemp('dir-pack-');
      try {
        final data = Directory('${dir.path}/DATA')..createSync(),
            out = Directory('${dir.path}/out')..createSync();
        await Directory('${data.path}/Personalizado').create();
        await File(
          '${data.path}/Personalizado/Ñandú.extra',
        ).writeAsBytes([1, 2, 3]);
        await File('${data.path}/empty.zero').writeAsBytes([]);
        await File('${data.path}/config.ini').writeAsString('X=1');
        final result = await DirectoryPack.build(
          data,
          out,
          replacements: {'config.ini': Uint8List.fromList(utf8.encode('X=2'))},
          control: ExportControl(),
          progress: (_) {},
        );
        final archive = await ArchiveSource.fromFiles(
          '${result.folder}/data.sah',
          '${result.folder}/data.saf',
        );
        expect(archive.index.entries.length, 3);
        expect(await archive.read('personalizado/ñandú.extra'), [1, 2, 3]);
        expect(await archive.read('empty.zero'), isEmpty);
        expect(utf8.decode(await archive.read('config.ini')), 'X=2');
        archive.close();
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'directory construction rejects inside destination, case collisions, and links',
    () async {
      final dir = await Directory.systemTemp.createTemp('dir-reject-');
      try {
        final data = Directory('${dir.path}/DATA')..createSync(),
            out = Directory('${dir.path}/out')..createSync();
        final inside = Directory('${data.path}/dest')..createSync();
        await File('${data.path}/a').writeAsBytes([1]);
        await expectLater(
          DirectoryPack.build(
            data,
            inside,
            control: ExportControl(),
            progress: (_) {},
          ),
          throwsFormatException,
        );
        if (!Platform.isWindows) {
          await File('${data.path}/A').writeAsBytes([2]);
          await expectLater(
            DirectoryPack.build(
              data,
              out,
              control: ExportControl(),
              progress: (_) {},
            ),
            throwsFormatException,
          );
          await File('${data.path}/A').delete();
          await Link('${data.path}/alias').create(out.path);
          await expectLater(
            DirectoryPack.build(
              data,
              out,
              control: ExportControl(),
              progress: (_) {},
            ),
            throwsFormatException,
          );
        }
        expect(await out.list().isEmpty, true);
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'file replacement is atomic, opt-in backup and stale-content protection',
    () async {
      final dir = await Directory.systemTemp.createTemp('file-save-');
      try {
        final file = File('${dir.path}/Ñandú.ini');
        await file.writeAsBytes([1, 2]);
        await FileSave.replace(
          file.path,
          Uint8List.fromList([3]),
          expectedHash: FileSave.hash([1, 2]),
          keepBackup: true,
        );
        expect(await file.readAsBytes(), [3]);
        final backups = await dir
            .list()
            .where((f) => f.path.endsWith('.bak'))
            .toList();
        expect(backups.length, 1);
        expect(await File(backups.single.path).readAsBytes(), [1, 2]);
        await expectLater(
          FileSave.replace(
            file.path,
            Uint8List.fromList([4]),
            expectedHash: FileSave.hash([1, 2]),
          ),
          throwsFormatException,
        );
        expect(await file.readAsBytes(), [3]);
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  for (final committed in [false, true]) {
    test(
      'crash recovery retains ${committed ? 'new' : 'old'} complete archive',
      () async {
        final dir = await Directory.systemTemp.createTemp('recovery-');
        try {
          final sah = File('${dir.path}/data.sah'),
              saf = File('${dir.path}/data.saf'),
              old = sampleIndex();
          await sah.writeAsBytes(old);
          await saf.writeAsBytes([1, 2, 3, 4]);
          final entry = ArchiveIndex.decode(old, 4).entries.values.single;
          final next = Uint8List.fromList(old);
          final b = ByteData.sublistView(next);
          b.setInt64(entry.metadataOffset, 4, Endian.little);
          b.setInt32(entry.metadataOffset + 8, 2, Endian.little);
          await File('${sah.path}.shaiya-old').writeAsBytes(old);
          await File('${sah.path}.shaiya-next').writeAsBytes(next);
          await File('${sah.path}.shaiya-transaction.json').writeAsString(
            jsonEncode({
              'schema': 1,
              'oldIndex': sha256.convert(old).toString(),
              'newIndex': sha256.convert(next).toString(),
              'oldLength': 4,
              'newLength': 6,
            }),
          );
          await saf.writeAsBytes(
            committed ? [1, 2, 3, 4, 8, 9] : [1, 2, 3, 4, 8],
          );
          if (committed) await sah.writeAsBytes(next);
          await ArchiveWriter.recover(sah.path, saf.path);
          final reopened = await ArchiveSource.fromFiles(sah.path, saf.path);
          expect(
            await reopened.read(entry.path),
            committed ? [8, 9] : [1, 2, 3, 4],
          );
          reopened.close();
          expect((await dir.list().toList()).length, 2);
        } finally {
          await dir.delete(recursive: true);
        }
      },
    );
  }
}
