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
      expect(find.text('Oro mínimo (Money1)'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Oro mínimo (Money1)'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('editor-field-input')),
        '-1',
      );
      await tester.tap(find.byKey(const ValueKey('editor-apply')));
      await tester.pumpAndSettle();
      expect(find.text('-1'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Deshacer'));
      await tester.pumpAndSettle();
      expect(find.text('-1'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      source.dispose();
    });
  }
  testWidgets('editor button centered on main toolbar', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var calls = 0;
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
          onOpenData: () {},
          onOpenEditor: () {
            calls++;
          },
        ),
      ),
    );
    expect(
      tester.getCenter(find.byKey(const ValueKey('open-data-editor'))).dx,
      closeTo(720, 1),
    );
    await tester.tap(find.byKey(const ValueKey('open-data-editor')));
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });
}
