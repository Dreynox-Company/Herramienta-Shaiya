import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:herramienta_shaiya/core/game_text_codec.dart';
import 'package:herramienta_shaiya/core/seed_data.dart';
import 'package:herramienta_shaiya/data/archive_source.dart';
import 'package:herramienta_shaiya/data/archive_export.dart';
import 'package:herramienta_shaiya/data/archive_write.dart';
import 'package:herramienta_shaiya/editor/schema_reader.dart';
import 'package:herramienta_shaiya/editor/workbench_model.dart';
import 'package:herramienta_shaiya/editor/catalog_document.dart';
import 'package:herramienta_shaiya/editor/text_document.dart';

import 'archive_test.dart' show sampleIndex, SahWriter;
import 'editor_document_test.dart' show binaryTable;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('natural IDs and 64-bit values retain numeric precision', () {
    final values = [
      '18446744073709551615',
      '2',
      '9007199254740993',
      '9007199254740992',
    ]..sort(compareEditorValues);
    expect(values, [
      '2',
      '9007199254740992',
      '9007199254740993',
      '18446744073709551615',
    ]);
    expect(compareEditorValues('2:10', '10:1'), lessThan(0));
    expect(foldedSearch('Ñandú Élite'), 'nandu elite');
  });
  test(
    'drafts remain isolated until atomic apply and reject field conflicts',
    () {
      final d = EditorReader.open(
        binaryTable(
          ['id', 'hp', 'level'],
          [
            [1, 100, 5],
          ],
        ),
        'binarysdata/dbmonsterdata.sdata',
      );
      final a = RecordDraft(d, 0), b = RecordDraft(d, 0);
      a.values['hp'] = '200';
      expect(b.values['hp'], '100');
      a.apply();
      b.values['hp'] = '300';
      expect(() => b.apply(), throwsFormatException);
      expect(d.read(d.fields(0)[1]), '200');
      final c = RecordDraft(d, 0);
      c.values['hp'] = '400';
      c.values['level'] = 'not-number';
      expect(() => c.apply(), throwsFormatException);
      expect(d.read(d.fields(0)[1]), '200');
    },
  );
  test('MLT preserves exact bytes and validates reference edits', () {
    final w = SahWriter();
    w.out.add(ascii.encode('MLT'));
    w.u(1);
    w.str('body.3dc');
    w.u(2);
    w.str('base.dds');
    w.str('otra.dds');
    w.u(1);
    w.u(0);
    w.u(0);
    w.u(0);
    final b = w.out.takeBytes(),
        d = CatalogDocument.open(b, 'human.mlt', GameTextEncoding.windows1252);
    expect(d.exportBytes(), b);
    final row = d.rows.length - 1, f = d.fields(row)[1];
    d.edit(row, f, '1');
    final round = CatalogDocument.open(
      d.exportBytes(),
      'human.mlt',
      GameTextEncoding.windows1252,
    );
    expect(round.materials(row).single.$2, 'otra.dds');
    expect(() => d.edit(row, f, '2'), throwsFormatException);
    d.undo();
    expect(d.exportBytes(), b);
  });
  for (final encoding in [
    GameTextEncoding.windows1252,
    GameTextEncoding.utf8,
    GameTextEncoding.utf16le,
  ]) {
    test(
      'configuration preserves comments, line endings and ${encoding.name}',
      () {
        final codec = GameTextCodec(encoding),
            text = '; Ñandú\r\n[VIDEO]\nWIDTH=800\rWIDTH=900';
        final bom = encoding == GameTextEncoding.utf16le
            ? [255, 254]
            : encoding == GameTextEncoding.utf8
            ? [239, 187, 191]
            : <int>[];
        final b = Uint8List.fromList([...bom, ...codec.encode(text)]),
            d = TextDocument.open(b, 'config.ini', encoding);
        expect(d.exportBytes(), b);
        d.edit(2, d.fields(2).single, 'WIDTH=1024');
        final changed = d.exportBytes();
        expect(
          codec.decode(changed.sublist(bom.length)),
          text.replaceFirst('WIDTH=800', 'WIDTH=1024'),
        );
        expect(
          reopenDocument(
            d,
            changed,
          ).read(reopenDocument(d, changed).fields(0).single),
          '; Ñandú',
        );
      },
    );
  }
  for (final mode in ['standard', 'seed', 'uniform', 'count']) {
    test(
      'save into original $mode SAH/SAF keeps names, structure and data',
      () async {
        final dir = await Directory.systemTemp.createTemp('sah-transaction-');
        try {
          var b = sampleIndex(xor: mode == 'count' ? 0x55 : 0);
          if (mode == 'uniform') {
            b = Uint8List.fromList(b.map((v) => v ^ 0x39).toList());
          }
          if (mode == 'seed') b = SeedData.encode(b);
          final sah = File('${dir.path}/data.sah'),
              saf = File('${dir.path}/data.saf');
          await sah.writeAsBytes(b);
          await saf.writeAsBytes([1, 2, 3, 4]);
          final src = await ArchiveSource.fromFiles(sah.path, saf.path),
              name = src.index.entries.keys.single;
          await ArchiveWriter.writeInPlace(
            src,
            {
              name: Uint8List.fromList([8, 9, 10]),
            },
            expectedHashes: {
              name: sha256.convert([1, 2, 3, 4]).toString(),
            },
            control: ExportControl(),
            progress: (_) {},
          );
          expect(await src.read(name), [8, 9, 10]);
          expect(await saf.readAsBytes(), [1, 2, 3, 4, 8, 9, 10]);
          expect(
            src.index.report['profile'],
            contains(
              mode == 'seed'
                  ? 'SEED'
                  : mode == 'uniform'
                  ? 'XOR uniforme'
                  : mode == 'count'
                  ? '0x55'
                  : 'SAH estándar',
            ),
          );
          expect((await dir.list().toList()).length, 2);
          await ArchiveWriter.writeInPlace(
            src,
            {
              name: Uint8List.fromList([50]),
            },
            expectedHashes: {
              name: sha256.convert([8, 9, 10]).toString(),
            },
            control: ExportControl(),
            progress: (_) {},
          );
          expect(await src.read(name), [50]);
          src.close();
        } finally {
          await dir.delete(recursive: true);
        }
      },
    );
  }
  for (final phase in ['prepared', 'payload', 'committed']) {
    test(
      'archive interruption at $phase never exposes a broken pair',
      () async {
        final dir = await Directory.systemTemp.createTemp('sah-interrupt-');
        try {
          final sah = File('${dir.path}/data.sah'),
              saf = File('${dir.path}/data.saf');
          await sah.writeAsBytes(sampleIndex());
          await saf.writeAsBytes([1, 2, 3, 4]);
          final src = await ArchiveSource.fromFiles(sah.path, saf.path),
              key = src.index.entries.keys.single;
          await expectLater(
            ArchiveWriter.writeInPlace(
              src,
              {
                key: Uint8List.fromList([8, 9]),
              },
              expectedHashes: {
                key: sha256.convert([1, 2, 3, 4]).toString(),
              },
              control: ExportControl(),
              progress: (_) {},
              testCheckpoint: (p) async {
                if (p == phase) throw StateError('Injected IO failure');
              },
            ),
            throwsStateError,
          );
          expect(
            await src.read(key),
            phase == 'committed' ? [8, 9] : [1, 2, 3, 4],
          );
          expect(src.writing, false);
          expect((await dir.list().toList()).length, 2);
          src.close();
        } finally {
          await dir.delete(recursive: true);
        }
      },
    );
  }
  test('external edited resource is not overwritten by stale editor', () async {
    final dir = await Directory.systemTemp.createTemp('sah-stale-');
    try {
      final sah = File('${dir.path}/data.sah'),
          saf = File('${dir.path}/data.saf');
      await sah.writeAsBytes(sampleIndex());
      await saf.writeAsBytes([1, 2, 3, 4]);
      final src = await ArchiveSource.fromFiles(sah.path, saf.path),
          key = src.index.entries.keys.single;
      await saf.writeAsBytes([5, 6, 7, 8]);
      await expectLater(
        ArchiveWriter.writeInPlace(
          src,
          {
            key: Uint8List.fromList([9]),
          },
          expectedHashes: {
            key: sha256.convert([1, 2, 3, 4]).toString(),
          },
          control: ExportControl(),
          progress: (_) {},
        ),
        throwsFormatException,
      );
      expect(await saf.readAsBytes(), [5, 6, 7, 8]);
      src.close();
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
