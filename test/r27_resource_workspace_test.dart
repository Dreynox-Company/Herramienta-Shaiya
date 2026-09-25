import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/spk_archive.dart';
import 'package:herramienta_shaiya/core/game_text_codec.dart';
import 'package:herramienta_shaiya/data/library.dart';
import 'package:herramienta_shaiya/data/file_save.dart';
import 'package:herramienta_shaiya/data/resource_index.dart';
import 'package:herramienta_shaiya/data/spk_source.dart' show SpkExtractControl;
import 'package:herramienta_shaiya/editor/catalog_document.dart';
import 'package:herramienta_shaiya/editor/schema_reader.dart';
import 'package:herramienta_shaiya/ui/resource_workspace.dart';
import 'fixtures/resource_spk_fixture.dart';
import 'r26_models_layout_test.dart' show modelMlt;

Map<String, Uint8List> inputs() => {
  'Character/Human/humf_upper.mlt': modelMlt(),
  'script/readme.txt': Uint8List.fromList(
    utf8.encode('test fixture text, no game data.'),
  ),
  'script/second.txt': Uint8List.fromList(
    utf8.encode('second fixture text, no game data.'),
  ),
};

void main() {
  test(
    'index lists all SPK records without a Character and without any payload read',
    () async {
      final root = await Directory.systemTemp.createTemp('r27-index-');
      addTearDown(() => root.delete(recursive: true));
      final source = await resourceSpkFixture(root, inputs());
      final locked = await Library.fromSpkEditable(source, allowLocked: true);
      final lockedIndex = ResourceIndex(locked);
      addTearDown(lockedIndex.dispose);
      expect(lockedIndex.entries, hasLength(4));
      expect(lockedIndex.blockedCount, 4);
      expect(source.reads, 0);
      expect(locked.sourceLabel, contains('pendiente'));
      await source.validateSimpleResourceProfile();
      final before = source.reads;
      final lib = await Library.fromSpkEditable(source);
      final index = ResourceIndex(lib);
      addTearDown(index.dispose);
      expect(source.reads, before);
      expect(index.entries, hasLength(4));
      expect(index.readableCount, 3);
      expect(index.blockedCount, 1);
      expect(index.entries.map((e) => e.key).toSet(), hasLength(4));
      expect(lib.files.keys.any((p) => p.startsWith('character/')), isFalse);
      final mlt = index.filter('humf_upper', 'Todos').single;
      index.select(mlt);
      final read = await index.read(mlt);
      expect(read.format, 'MLT');
      expect(mlt.confirmed, isFalse);
      final doc = EditorReader.open(read.bytes, mlt.path!);
      expect(doc, isA<CatalogDocument>());
      expect(doc.complete, isTrue);
      expect(doc.path, mlt.path);
      expect(source.names.isConfirmed(0x1000), isFalse);
      expect(source.canExtractAll, isFalse);
      expect(source.fullResourceValidation, isNull);
    },
  );

  test(
    'anonymous MLT uses a complete byte parser and preserves its physical Entry ID',
    () {
      const path = '_spk_sinnombre/0000000000001000.bin';
      final doc = EditorReader.open(modelMlt(), path);
      expect(doc, isA<CatalogDocument>());
      expect(doc.complete, isTrue);
      expect(doc.rows, hasLength(2));
      final encoded = doc.exportBytes();
      expect(
        CatalogDocument.open(
          encoded,
          path,
          GameTextEncoding.automatic,
        ).materials(0),
        (doc as CatalogDocument).materials(0),
      );
    },
  );

  test(
    'two consecutive edits survive reopen, keep base hash and never alter SPK',
    () async {
      final root = await Directory.systemTemp.createTemp('r27-write-');
      addTearDown(() => root.delete(recursive: true));
      final source = await resourceSpkFixture(root, inputs());
      await source.validateSimpleResourceProfile();
      final lib = await Library.fromSpkEditable(source);
      final index = ResourceIndex(lib);
      addTearDown(index.dispose);
      final entry = index.filter('humf_upper', 'Todos').single,
          originalSpk = await source.file.readAsBytes();
      final read = await index.read(entry),
          first = Uint8List.fromList(read.bytes);
      // Last field is the second row's alpha. It stays within the native range.
      ByteData.sublistView(first).setUint32(first.length - 4, 0, Endian.little);
      await index.replace(read, first);
      final reopened = await Library.fromSpkEditable(source);
      final second = Uint8List.fromList(first);
      ByteData.sublistView(
        second,
      ).setUint32(second.length - 4, 1, Endian.little);
      final path = reopened.files.entries
          .firstWhere((e) => e.value == entry.key)
          .key;
      expect(await reopened.read(path), first);
      await reopened.writeSpkOverlay(
        {path: second},
        expectedHashes: {path: FileSave.hash(first)},
      );
      final manifest =
          jsonDecode(
                await File(
                  '${lib.spkOverlayRoot}/_SPK_OVERLAY.json',
                ).readAsString(),
              )
              as Map;
      final info = (manifest['entries'] as Map).values.single as Map;
      expect(info['originalSha256'], read.hash);
      expect(info['overlaySha256'], FileSave.hash(second));
      expect(await reopened.read(path), second);
      expect(await source.file.readAsBytes(), originalSpk);
      await expectLater(
        reopened.writeSpkOverlay(
          {path: first},
          expectedHashes: {path: read.hash},
        ),
        throwsFormatException,
      );
      expect(await reopened.read(path), second);
      source.names.mergeConfirmed({0x1000: 'Character/Human/humf_upper.mlt'});
      final named = await Library.fromSpkEditable(source);
      expect(await named.read('character/human/humf_upper.mlt'), second);
      await named.writeSpkOverlay(
        {'character/human/humf_upper.mlt': first},
        expectedHashes: {
          'character/human/humf_upper.mlt': FileSave.hash(second),
        },
      );
      final manifest2 =
          jsonDecode(
                await File(
                  '${lib.spkOverlayRoot}/_SPK_OVERLAY.json',
                ).readAsString(),
              )
              as Map;
      expect(manifest2['entries'], hasLength(1));
      expect(await named.read('character/human/humf_upper.mlt'), first);
      expect(await source.file.readAsBytes(), originalSpk);
    },
  );

  test(
    'tampered base is rejected even when a valid edit exists in the overlay',
    () async {
      final root = await Directory.systemTemp.createTemp('r27-tamper-base-');
      addTearDown(() => root.delete(recursive: true));
      final source = await resourceSpkFixture(root, inputs());
      await source.validateSimpleResourceProfile();
      final lib = await Library.fromSpkEditable(source);
      final path = lib.files.entries
          .firstWhere((e) => e.value == '0000000000001000')
          .key;
      final original = await lib.read(path);
      await lib.writeSpkOverlay(
        {path: original},
        expectedHashes: {path: FileSave.hash(original)},
      );
      final bytes = await source.file.readAsBytes();
      bytes[source.index.simpleResources.first.dataOffset + 8] ^= 1;
      await source.file.writeAsBytes(bytes);
      await expectLater(
        lib.read(path),
        throwsA(
          isA<SpkFailure>().having(
            (e) => e.code,
            'code',
            'SPK_RESOURCE_AUTHENTICATION',
          ),
        ),
      );
      final other = lib.files.entries
          .firstWhere((e) => e.value == '0000000000001001')
          .key;
      expect(await lib.read(other), inputs()['script/readme.txt']);
    },
  );

  test(
    'tampered overlay and foreign manifest never masquerade as editable DATA',
    () async {
      final root = await Directory.systemTemp.createTemp('r27-tamper-overlay-');
      addTearDown(() => root.delete(recursive: true));
      final source = await resourceSpkFixture(root, inputs());
      await source.validateSimpleResourceProfile();
      final lib = await Library.fromSpkEditable(source);
      final path = lib.files.entries
          .firstWhere((e) => e.value == '0000000000001000')
          .key;
      final original = await lib.read(path);
      await lib.writeSpkOverlay(
        {path: original},
        expectedHashes: {path: FileSave.hash(original)},
      );
      final f = File('${lib.spkOverlayRoot}/_SPK_OVERLAY.json'),
          manifest = jsonDecode(await f.readAsString()) as Map;
      final info = (manifest['entries'] as Map).values.single as Map;
      final editedFile = File('${lib.spkOverlayRoot}/${info['file']}');
      await editedFile.writeAsBytes([1, 2, 3]);
      await expectLater(lib.read(path), throwsFormatException);
      await editedFile.writeAsBytes(original);
      manifest['indexSha256'] = 'another-spk';
      await f.writeAsString(jsonEncode(manifest));
      await expectLater(lib.read(path), throwsFormatException);
    },
  );

  test(
    'cancelable indexing retains locked entries and never promotes filename guesses',
    () async {
      final root = await Directory.systemTemp.createTemp('r27-scan-');
      addTearDown(() => root.delete(recursive: true));
      final source = await resourceSpkFixture(root, inputs());
      await source.validateSimpleResourceProfile();
      final index = ResourceIndex(await Library.fromSpkEditable(source));
      addTearDown(index.dispose);
      final scan = index.scan();
      index.cancelled = true;
      await scan;
      expect(index.indexing, isFalse);
      expect(index.entries, hasLength(4));
      expect(index.blockedCount, 1);
      await index.scan();
      expect(index.scanned, 3);
      expect(index.rejected, 0);
      expect(index.readCount, 3);
      expect(source.names.isConfirmed(0x1000), isFalse);
      expect(source.fullResourceValidation, isNull);
      await File('${root.path}/_SPK_MANIFEST.json').writeAsString('{}');
      await expectLater(
        source.verifyNamesFromDirectory(
          root,
          control: SpkExtractControl(),
          progress: (_, _, _) {},
        ),
        throwsFormatException,
      );
    },
  );

  testWidgets(
    'sidebar selection works without any Character catalog and includes blocked records',
    (tester) async {
      final library = Library('test', false, {
        'a.txt': 'not-read',
        'b.dds': 'not-read',
      });
      final index = ResourceIndex(library);
      addTearDown(index.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                SizedBox(width: 260, child: ResourceSidebar(index: index)),
                Expanded(child: ResourceDetails(index: index)),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('resource-a.txt')));
      await tester.pump();
      expect(index.selected?.path, 'a.txt');
      expect(find.textContaining('Identidad: a.txt'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('resource-query')),
        'b.dds',
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('resource-a.txt')), findsNothing);
      expect(find.byKey(const ValueKey('resource-b.dds')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
