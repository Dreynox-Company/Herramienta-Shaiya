import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/data/item_workspace.dart';
import 'package:herramienta_shaiya/data/library.dart';
import 'package:herramienta_shaiya/data/file_save.dart';
import 'package:herramienta_shaiya/editor/schema_reader.dart';
import 'package:herramienta_shaiya/core/game_text_codec.dart';

import 'fixtures/item_workspace_fixture.dart';

void main() {
  test(
    'catalog includes consumables, lapis, lapisia, quests and all equipment',
    () {
      final w = memoryItems();
      expect(w.items, hasLength(8));
      for (final key in [
        '25:1',
        '30:1',
        '95:1',
        '121:1',
        '125:1',
        '128:1',
        '1:1',
        '73:6',
      ]) {
        expect(w.byKey, contains(key));
      }
      expect(w.byKey['25:1']!.name, 'Manzana');
      expect(w.byKey['73:6']!.hasName, false);
      expect(w.registry.byKey['73:6']!.level, 80);
    },
  );
  test(
    'same ID in different types is not collapsed; duplicate identity fails',
    () {
      final library = Library('fixture', false, {});
      expect(
        () => ItemWorkspace.fromBytes(library, numericItems(duplicate: true)),
        throwsFormatException,
      );
      expect(
        () => ItemWorkspace.fromBytes(
          library,
          numericItems(),
          text: localizedItems(duplicate: true),
          textPath: itemTextPath,
        ),
        throwsFormatException,
      );
      expect(
        () => ItemWorkspace.fromBytes(
          library,
          numericItems(),
          text: localizedItems(),
        ),
        throwsArgumentError,
      );
      final w = memoryItems(missing: true);
      expect(w.byKey['1:1']!.textRow, isNull);
      expect(w.byKey['25:1']!.name, 'Manzana');
    },
  );
  test(
    'one operation changes all selected native types and keeps int64 precision',
    () {
      final w = memoryItems();
      final untouched = w.byKey['1:1']!.values['arg3'];
      w.apply([
        fieldEdit(w, '25:1', 'consthp', '250'),
        fieldEdit(w, '95:1', 'rec', '75'),
        fieldEdit(w, '121:1', 'conststr', '20'),
        fieldEdit(w, '128:1', 'count', '4'),
      ], title: 'multi-type');
      expect(w.byKey['25:1']!.values['consthp'], '250');
      expect(w.registry.byKey['25:1']!.values['consthp'], 250);
      expect(w.byKey['1:1']!.values['arg3'], untouched);
      w.undo();
      expect(w.byKey['25:1']!.values['consthp'], '119');
      w.redo();
      expect(w.byKey['95:1']!.values['rec'], '75');
    },
  );
  test(
    'paired edits undo/redo together and untouched rows remain byte-identical',
    () {
      final w = memoryItems(), original = memoryItems();
      w.apply([
        fieldEdit(w, '1:1', 'effect1', '100'),
        fieldEdit(w, '1:1', 'itemname', 'Espada Épica', localized: true),
      ], title: 'weapon');
      expect(w.byKey['1:1']!.name, 'Espada Épica');
      expect(w.byKey['1:1']!.values['effect1'], '100');
      w.undo();
      expect(w.byKey['1:1']!.name, 'Espada Larga');
      expect(w.data.exportBytes(), original.data.exportBytes());
      expect(w.text!.exportBytes(), original.text!.exportBytes());
      w.redo();
      expect(w.byKey['1:1']!.name, 'Espada Épica');
      expect(w.byKey['25:1']!.values, original.byKey['25:1']!.values);
    },
  );
  test(
    'stale or invalid draft refuses the whole operation without losing history',
    () {
      final w = memoryItems();
      final stale = fieldEdit(w, '25:1', 'consthp', '200');
      w.apply([fieldEdit(w, '25:1', 'consthp', '150')], title: 'earlier');
      expect(
        () => w.apply([
          fieldEdit(w, '1:1', 'effect1', '100'),
          stale,
        ], title: 'stale'),
        throwsFormatException,
      );
      expect(w.byKey['1:1']!.values['effect1'], '19');
      expect(
        () => w.apply([
          fieldEdit(w, '1:1', 'effect1', '100'),
          fieldEdit(w, '1:1', 'itemname', 'Emoji 🔥', localized: true),
        ], title: 'bad encoding'),
        throwsFormatException,
      );
      expect(w.byKey['1:1']!.values['effect1'], '19');
      expect(w.history, ['earlier']);
    },
  );
  test(
    'identity, duplicate edit, integer overflow and native Icon wrap are refused',
    () {
      final w = memoryItems();
      final value = fieldEdit(w, '1:1', 'icon', '2');
      for (final edits in [
        [fieldEdit(w, '1:1', 'itemtypeid', '2')],
        [value, value],
        [fieldEdit(w, '1:1', 'arg3', '9223372036854775808')],
        [fieldEdit(w, '1:1', 'icon', '256')],
        [fieldEdit(w, '1:1', 'icon', '-1')],
      ]) {
        expect(() => w.apply(edits, title: 'invalid'), throwsFormatException);
      }
      expect(w.dirty, false);
    },
  );
  test(
    'public views of the same Library return the same staging session',
    () async {
      final (temp, library, _) = await diskItems();
      addTearDown(() => temp.delete(recursive: true));
      final a = await ItemWorkspace.forLibrary(library),
          b = await ItemWorkspace.forLibrary(library);
      expect(identical(a, b), true);
      a.apply([fieldEdit(a, '25:1', 'consthp', '300')], title: 'shared');
      expect(b.registry.byKey['25:1']!.values['consthp'], 300);
      expect(await ItemWorkspace.forLibrary(a.preview), same(a));
    },
  );
  test('export is a new paired patch; never changes active DATA', () async {
    final (temp, lib, w) = await diskItems();
    addTearDown(() => temp.delete(recursive: true));
    final originalData = await lib.read(itemDataPath),
        originalText = await lib.read(itemTextPath);
    w.apply([
      fieldEdit(w, '25:1', 'itemname', 'Manzana Roja', localized: true),
    ], title: 'rename');
    final dest = await w.exportPatch(Directory('${temp.path}/patch'));
    expect(await lib.read(itemDataPath), originalData);
    expect(await lib.read(itemTextPath), originalText);
    final manifest =
        jsonDecode(await File('${dest.path}/manifest.json').readAsString())
            as Map;
    expect((manifest['files'] as List), hasLength(2));
    final changedText = await File(
      '${dest.path}/COPIAR_EN_DATA/$itemTextPath',
    ).readAsBytes();
    final reopened = EditorReader.open(
      changedText,
      itemTextPath,
      encoding: GameTextEncoding.windows1252,
    );
    expect(reopened.complete, true);
    expect(w.dirty, true);
  });
  test(
    'source conflict and destination-inside-DATA leave no partial publication',
    () async {
      final (temp, lib, w) = await diskItems();
      addTearDown(() => temp.delete(recursive: true));
      w.apply([fieldEdit(w, '1:1', 'effect1', '30')], title: 'damage');
      await expectLater(
        w.exportPatch(Directory('${lib.location}/wrong')),
        throwsFormatException,
      );
      expect(w.exporting, false);
      await File(lib.files[itemDataPath]!).writeAsBytes([1, 2, 3]);
      await expectLater(
        w.exportPatch(Directory('${temp.path}/conflict')),
        throwsFormatException,
      );
      expect(await Directory('${temp.path}/conflict').exists(), false);
      expect(w.exporting, false);
      expect(
        (await temp.list().toList()).where(
          (f) => f.path.contains('.studio-items-'),
        ),
        isEmpty,
      );
    },
  );
  test('overlapping export calls cannot both acquire the session', () async {
    final (temp, _, w) = await diskItems();
    addTearDown(() => temp.delete(recursive: true));
    w.apply([fieldEdit(w, '25:1', 'count', '20')], title: 'stack');
    final first = w.exportPatch(Directory('${temp.path}/first'));
    await expectLater(
      w.exportPatch(Directory('${temp.path}/second')),
      throwsStateError,
    );
    await first;
  });
  test(
    'explicit reload refreshes the same shared session and removes stale redo',
    () async {
      final (temp, lib, _) = await diskItems();
      addTearDown(() => temp.delete(recursive: true));
      final w = await ItemWorkspace.forLibrary(lib);
      w.apply([
        fieldEdit(w, '25:1', 'consthp', '222'),
      ], title: 'external fixture');
      final edited = w.data.exportBytes();
      w.discard();
      await File(lib.files[itemDataPath]!).writeAsBytes(edited);
      await w.reloadFromSource();
      expect(await ItemWorkspace.forLibrary(lib), same(w));
      expect(w.byKey['25:1']!.values['consthp'], '222');
      expect(w.canRedo, false);
      expect(w.dirty, false);
    },
  );
  test(
    'nested destination inside DATA creates no intermediate directory',
    () async {
      final (temp, lib, w) = await diskItems();
      addTearDown(() => temp.delete(recursive: true));
      w.apply([fieldEdit(w, '25:1', 'count', '2')], title: 'stack');
      await expectLater(
        w.exportPatch(Directory('${lib.location}/new/nested/patch')),
        throwsFormatException,
      );
      expect(await Directory('${lib.location}/new').exists(), false);
    },
  );
  test(
    'assets share undo history, detect conflicts and keep source bytes',
    () async {
      final (temp, lib, w) = await diskItems();
      addTearDown(() => temp.delete(recursive: true));
      final file = File('${lib.location}/texture.dds');
      await file.writeAsBytes([1, 2, 3]);
      lib.files['texture.dds'] = file.path;
      await w.stageAsset(
        'texture.dds',
        Uint8List.fromList([4, 5, 6]),
        expectedHash: FileSave.hash([1, 2, 3]),
        title: 'texture',
      );
      expect(await w.preview.read('texture.dds'), [4, 5, 6]);
      expect(await file.readAsBytes(), [1, 2, 3]);
      await expectLater(
        w.stageAsset(
          'texture.dds',
          Uint8List.fromList([7]),
          expectedHash: FileSave.hash([1, 2, 3]),
          title: 'stale',
        ),
        throwsFormatException,
      );
      w.undo();
      expect(await w.preview.read('texture.dds'), [1, 2, 3]);
      w.redo();
      expect(await w.preview.read('texture.dds'), [4, 5, 6]);
      w.discard();
      expect(w.dirty, false);
    },
  );
}
