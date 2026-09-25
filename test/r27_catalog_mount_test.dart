import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/archive_index.dart';
import 'package:herramienta_shaiya/data/archive_source.dart';
import 'package:herramienta_shaiya/data/catalog.dart';
import 'package:herramienta_shaiya/data/library.dart';
import 'package:herramienta_shaiya/data/resource_index.dart';
import 'fixtures/resource_spk_fixture.dart';
import 'r26_models_layout_test.dart' show modelMlt;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'loose DATA without Character remains available to the resource editor',
    () async {
      final root = await Directory.systemTemp.createTemp('r27-no-rig-data-');
      addTearDown(() => root.delete(recursive: true));
      final file = File('${root.path}/readme.txt');
      await file.writeAsString('Resource workspace; no playable character.');
      final lib = await Library.fromDirectory(root.path, (_) {});
      addTearDown(lib.dispose);
      await expectLater(Catalog(lib).load((_) {}), throwsFormatException);
      final catalog = Catalog(lib);
      await catalog.load((_) {}, requireArchetypes: false);
      expect(catalog.archetypes, isEmpty);
      expect(
        catalog.warnings.any((w) => w.contains('biblioteca de recursos')),
        isTrue,
      );
      final index = ResourceIndex(lib);
      addTearDown(index.dispose);
      expect(index.entries, hasLength(1));
      expect((await index.read(index.entries.single)).format, 'TXT');
    },
  );

  test(
    'SAH/SAF resource library does not need an equipped character',
    () async {
      final bytes = Uint8List.fromList(
        utf8.encode('Archive resource without rig.'),
      );
      const path = 'script/note.txt';
      final source = ArchiveSource(
        ArchiveIndex({path: ArchiveEntry(path, 0, bytes.length, 0)}, {}),
        (offset, length) async =>
            Uint8List.sublistView(bytes, offset, offset + length),
      );
      final lib = Library('synthetic-archive', false, {
        path: path,
      }, archive: source);
      addTearDown(lib.dispose);
      final catalog = Catalog(lib);
      await catalog.load((_) {}, requireArchetypes: false);
      expect(catalog.archetypes, isEmpty);
      expect(await lib.read(path), bytes);
      await expectLater(Catalog(lib).load((_) {}), throwsFormatException);
    },
  );

  test(
    'SPK partial catalog retains all IDs and missing-rig diagnostics',
    () async {
      final root = await Directory.systemTemp.createTemp('r27-no-rig-spk-');
      addTearDown(() => root.delete(recursive: true));
      final source = await resourceSpkFixture(root, {
        'Character/Human/humf_upper.mlt': modelMlt(),
        'script/a.txt': Uint8List.fromList(utf8.encode('First readable text.')),
        'script/b.txt': Uint8List.fromList(
          utf8.encode('Second readable text.'),
        ),
      });
      await source.validateSimpleResourceProfile();
      final lib = await Library.fromSpkEditable(source);
      addTearDown(lib.dispose);
      final before = source.reads;
      final catalog = Catalog(lib);
      await catalog.load((_) {}, requireArchetypes: false);
      expect(catalog.archetypes, isEmpty);
      expect(source.reads, before);
      final index = ResourceIndex(lib);
      addTearDown(index.dispose);
      expect(index.entries, hasLength(4));
      expect(index.readableCount, 3);
      expect(index.blockedCount, 1);
      expect(
        (await index.read(index.filter('humf_upper', 'Todos').single)).format,
        'MLT',
      );
      expect(source.names.isConfirmed(0x1000), isFalse);
      expect(source.canReadFragmentedResources, isFalse);
      expect(source.fullResourceValidation, isNull);
    },
  );
}
