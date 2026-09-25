import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/archive_index.dart';
import 'package:herramienta_shaiya/data/archive_source.dart';
import 'package:herramienta_shaiya/data/library.dart';
import 'package:herramienta_shaiya/ui/data_editor.dart';
import 'package:herramienta_shaiya/ui/studio_workspace.dart';

import 'editor_document_test.dart' show binaryTable;

void main() {
  WidgetController.hitTestWarningShouldBeFatal = true;
  Future<void> settleIo(WidgetTester t) async {
    for (var i = 0; i < 15; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await t.pump(const Duration(milliseconds: 30));
    }
  }

  Library lib() {
    final b = binaryTable(
      ['id', 'money1', 'money2', 'item1', 'itemdroprate1', 'hp'],
      [
        [1, 10, 20, 206, 10, 400],
        [2, 30, 50, 99, 25, 500],
      ],
    );
    const path = 'binarysdata/dbmonsterdata.sdata';
    final source = ArchiveSource(
      ArchiveIndex({path: ArchiveEntry(path, 0, b.length, 0)}, {}),
      (o, n) async => Uint8List.sublistView(b, o, o + n),
    );
    return Library('test', false, {path: path}, archive: source);
  }

  for (final width in [1440.0, 980.0, 650.0, 390.0]) {
    testWidgets('editor responsive at $width without overflow', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final source = lib();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: DataEditorPage(library: source),
        ),
      );
      expect(find.text('EDITOR DE DATOS'), findsOneWidget);
      if (width < 1000) {
        await tester.tap(find.byIcon(Icons.folder_open));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('dbmonsterdata.sdata'));
      await settleIo(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('edit-selected-record')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('record-field-money1')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.enterText(
        find.byKey(const ValueKey('record-field-money1')),
        '-1',
      );
      await tester.tap(find.byKey(const ValueKey('record-accept')));
      await tester.pumpAndSettle();
      expect(find.text('-1'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Deshacer'));
      await tester.tap(find.text('Deshacer'));
      await tester.pumpAndSettle();
      expect(find.text('-1'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      source.dispose();
    });
  }
  testWidgets('SPK quick editor opens on requested semantic field group', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final source = lib();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: DataEditorPage(
          library: source,
          initialPath: 'binarysdata/dbmonsterdata.sdata',
          initialFieldGroup: 'Botín y oro',
        ),
      ),
    );
    await settleIo(tester);
    await tester.pumpAndSettle();
    expect(find.text('Botín y oro'), findsWidgets);
    expect(find.textContaining('Tasa de botín'), findsWidgets);
    expect(find.textContaining('Oro mínimo'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    source.dispose();
  });

  // The former centered overlay collided with adjacent actions. The toolbar
  // now reserves dock controls and scrolls its actions at narrow widths.
  // Assert reachability, geometry and the actual callback, not an obsolete X.
  for (final width in [1440.0, 980.0, 650.0, 390.0]) {
    testWidgets('every toolbar action remains usable at $width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final calls = <String, int>{};
      void record(String key) => calls.update(
        key,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: StudioWorkspace(
            viewport: const SizedBox(),
            left: const SizedBox(),
            right: const SizedBox(),
            timeline: const SizedBox(),
            actions: const SizedBox(),
            status: const SizedBox(),
            tabs: const ['Personaje'],
            icons: const [Icons.person],
            selectedTab: 0,
            onTab: (_) {},
            onOpenData: () => record('data'),
            onOpenEditor: () => record('editor'),
            onOpenItems: () => record('items'),
            onOpenSpk: () => record('spk'),
            onOpenExcelXml: () => record('xml'),
            onExportScene: () => record('export'),
          ),
        ),
      );
      final left = find.byKey(const ValueKey('toggle-left'));
      final right = find.byKey(const ValueKey('toggle-right'));
      final actions = <String, Finder>{
        'items': find.byKey(const ValueKey('open-items-catalog')),
        'editor': find.byKey(const ValueKey('open-data-editor')),
        'data': find.text('DATA'),
        'spk': find.byKey(const ValueKey('open-spk')),
        'xml': find.byKey(const ValueKey('open-excelxml')),
        'export': find.byKey(const ValueKey('export-game-scene')),
      };
      final expected = <String, int>{};
      // Also return through the actions in reverse to test scrolling both ways.
      for (final key in [...actions.keys, ...actions.keys.toList().reversed]) {
        final action = actions[key]!;
        await tester.ensureVisible(action);
        await tester.pumpAndSettle();
        expect(action.hitTestable(), findsOneWidget);
        final bounds = tester.getRect(action);
        expect(bounds.left, greaterThanOrEqualTo(tester.getRect(left).right - 1));
        expect(bounds.right, lessThanOrEqualTo(tester.getRect(right).left + 1));
        expect(left.hitTestable(), findsOneWidget);
        expect(right.hitTestable(), findsOneWidget);
        await tester.tap(action);
        await tester.pumpAndSettle();
        expected.update(key, (count) => count + 1, ifAbsent: () => 1);
        expect(calls, equals(expected));
        expect(tester.takeException(), isNull);
      }
    });
  }
}
