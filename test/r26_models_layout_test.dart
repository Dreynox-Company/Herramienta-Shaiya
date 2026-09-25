import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/archive_index.dart';
import 'package:herramienta_shaiya/data/archive_source.dart';
import 'package:herramienta_shaiya/data/item_workspace.dart';
import 'package:herramienta_shaiya/data/library.dart';
import 'package:herramienta_shaiya/editor/item_model_catalog.dart';
import 'package:herramienta_shaiya/editor/model_reference.dart';
import 'package:herramienta_shaiya/ui/editor_style.dart';
import 'package:herramienta_shaiya/ui/item_model_picker.dart';
import 'package:herramienta_shaiya/ui/studio_sections.dart';
import 'package:herramienta_shaiya/ui/studio_workspace.dart';

import 'fixtures/item_workspace_fixture.dart';

Uint8List modelMlt() {
  final out = BytesBuilder()..add(ascii.encode('MLT'));
  void number(int value) { final b = ByteData(4)..setUint32(0, value, Endian.little); out.add(b.buffer.asUint8List()); }
  void name(String text) { final b = ascii.encode(text); number(b.length); out.add(b); }
  number(2); name('upper015.3dc'); name('upper016.3dc');
  number(2); name('upper015.dds'); name('upper016.dds');
  number(2);
  // Deliberately cross the texture indices. Never infer pairing by filename.
  number(0); number(1); number(0);
  number(1); number(0); number(1);
  return out.takeBytes();
}

Map<String, Uint8List> modelFiles() => {
  itemDataPath: numericItems(), itemTextPath: localizedItems(),
  'character/human/humf_upper.mlt': modelMlt(),
  'character/human/3dc/upper015.3dc': Uint8List.fromList([1]),
  'character/human/3dc/upper016.3dc': Uint8List.fromList([2]),
  'character/human/dds/upper015.dds': Uint8List.fromList([3]),
  'character/human/dds/upper016.dds': Uint8List.fromList([4]),
};

void main() {
  test('model source families never mix armor, weapons, wings or consumables', () {
    final paths = ['character/human/humf_upper.mlt', 'character/elf/elmm_lower.mlt',
      'character/wing/wing.mon', 'vehicle/vehicle_hu.mon', 'item/01.itm'];
    expect(ItemModelCatalog.pathsFor(paths, 73), ['character/human/humf_upper.mlt']);
    expect(ItemModelCatalog.pathsFor(paths, 121), ['character/wing/wing.mon']);
    expect(ItemModelCatalog.pathsFor(paths, 125), ['vehicle/vehicle_hu.mon']);
    expect(ItemModelCatalog.pathsFor(paths, 1), ['item/01.itm']);
    expect(ItemModelCatalog.pathsFor(paths, 25), isEmpty);
    expect(ItemModelCatalog.supports(25), isFalse);
  });

  for (final transport in ['folder', 'SAH/SAF range']) {
    test('$transport uses exact MLT texture pairing; browsing never edits data', () async {
      final root = await Directory.systemTemp.createTemp('r26-models-');
      addTearDown(() => root.delete(recursive: true));
      final entries = modelFiles();
      late Library library;
      if (transport == 'folder') {
        final paths = <String, String>{};
        for (final entry in entries.entries) {
          final file = File('${root.path}/${entry.key}');
          await file.parent.create(recursive: true); await file.writeAsBytes(entry.value);
          paths[entry.key] = file.path;
        }
        library = Library(root.path, false, paths);
      } else {
        final buffer = BytesBuilder(copy: false), index = <String, ArchiveEntry>{};
        for (final entry in entries.entries) {
          index[entry.key] = ArchiveEntry(entry.key, buffer.length, entry.value.length, 0);
          buffer.add(entry.value);
        }
        final bytes = buffer.takeBytes();
        library = Library('SAH fixture', false, {for (final p in index.keys) p: p},
          archive: ArchiveSource(ArchiveIndex(index, {}),
            (offset, length) async => Uint8List.sublistView(bytes, offset, offset + length)));
      }
      addTearDown(library.dispose);
      final w = ItemWorkspace.fromBytes(library, entries[itemDataPath]!,
        text: entries[itemTextPath], textPath: itemTextPath);
      final before = w.data.exportBytes();
      final catalog = await ItemModelCatalog.load(w, item: w.byKey['73:6']);
      expect(catalog.warnings, isEmpty); expect(catalog.choices, hasLength(2));
      expect(catalog.choices[0].model.parts.single.$1, 'character/human/3dc/upper015.3dc');
      expect(catalog.choices[0].model.parts.single.$2, 'character/human/dds/upper016.dds');
      expect(catalog.choices[1].model.parts.single.$2, 'character/human/dds/upper015.dds');
      expect(catalog.choices[0].searchText, contains('016'));
      expect(catalog.choices.every((c) => c.available), isTrue);
      expect(w.dirty, isFalse); expect(w.data.exportBytes(), before);
      expect(w.byKey['73:6']!.image, 42); // Resource suffix 016 is not Image.
    });
  }

  const source = 'character/human/humf_upper.mlt';
  ItemModelChoice choice(int id, {bool missing = false}) => ItemModelChoice(
    model: ModelReference('Model $id', [('mesh$id.3dc', 'texture$id.dds', 0)],
      sourcePath: source, sourceOrdinal: id), name: 'Torso recurso 0$id',
    row: id, fields: const {}, missing: missing ? ['texture$id.dds'] : const []);

  for (final width in [390.0, 800.0, 1366.0]) {
    testWidgets('3D picker preserves cancel/confirm and stale-load safety at $width', (tester) async {
      tester.view.physicalSize = Size(width, 900); tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
      ItemModelChoice? result;
      final callbacks = <int, ValueChanged<bool>>{};
      var opens = 0;
      await tester.pumpWidget(MaterialApp(theme: EditorStyle.theme(ThemeData.dark(useMaterial3: true)),
        home: Scaffold(body: Builder(builder: (ctx) => TextButton(onPressed: () async {
          opens++;
          result = await showDialog<ItemModelChoice>(context: ctx, builder: (_) => ItemModelPicker(
            library: Library('fixture', false, {}),
            catalog: Future.value(ItemModelCatalog([choice(15), choice(16), choice(17, missing: true)], [], 0)),
            currentOrdinal: 15, currentSource: source,
            previewBuilder: (context, lib, model, ready) {
              callbacks[model.sourceOrdinal!] = ready;
              return Center(child: Text('Native preview test double ${model.sourceOrdinal}'));
            }));
        }, child: const Text('Modelos'))))));
      await tester.tap(find.text('Modelos')); await tester.pumpAndSettle();
      final confirm = find.byKey(const ValueKey('confirm-model-picker'));
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      final stale = callbacks[15]!;
      await tester.tap(find.byKey(const ValueKey('model-choice-$source#16')));
      await tester.pumpAndSettle();
      stale(true); await tester.pump();
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      callbacks[16]!(true); await tester.pump();
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
      await tester.tap(find.byKey(const ValueKey('cancel-model-picker')));
      await tester.pumpAndSettle(); expect(result, isNull);
      await tester.tap(find.text('Modelos')); await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('model-choice-$source#17')));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      expect(find.textContaining('Faltan recursos'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('model-choice-$source#16')));
      await tester.pumpAndSettle(); callbacks[16]!(true); await tester.pump();
      await tester.tap(confirm); await tester.pumpAndSettle();
      expect(result?.ordinal, 16); expect(opens, 2); expect(tester.takeException(), isNull);
    });
  }

  testWidgets('explicit inspector sections move once, remain collapsible and preserve controls', (tester) async {
    tester.view.physicalSize = const Size(1366, 900); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    var clicks = 0;
    final docks = StudioDockContent.split(Column(children: [
      const StudioSection(title: 'Alas', children: [Text('Selector de alas')]),
      StudioSection(title: 'Ajustes de alas', children: [TextButton(
        onPressed: () => clicks++, child: const Text('Ajustar XYZ'))]),
    ]));
    await tester.pumpWidget(MaterialApp(theme: EditorStyle.theme(ThemeData.dark(useMaterial3: true)),
      home: StudioWorkspace(viewport: const Text('3D'), left: docks.navigation, right: docks.inspector,
        timeline: const SizedBox(), actions: const SizedBox(), status: const SizedBox(),
        tabs: const ['Alas'], icons: const [Icons.view_in_ar], selectedTab: 0,
        onTab: (_) {}, onOpenData: () {})));
    expect(find.text('Ajustar XYZ'), findsOneWidget);
    final viewport = tester.getRect(find.byKey(const ValueKey('viewport-region')));
    expect(tester.getCenter(find.text('Selector de alas')).dx, lessThan(viewport.left));
    expect(tester.getCenter(find.text('Ajustar XYZ')).dx, greaterThan(viewport.right));
    await tester.tap(find.text('Ajustar XYZ')); expect(clicks, 1);
    await tester.tap(find.text('Ajustes de alas')); await tester.pumpAndSettle();
    expect(find.text('Ajustar XYZ').hitTestable(), findsNothing);
    await tester.tap(find.text('Ajustes de alas')); await tester.pumpAndSettle();
    await tester.tap(find.text('Ajustar XYZ')); expect(clicks, 2);
    expect(tester.takeException(), isNull);
  });
}
