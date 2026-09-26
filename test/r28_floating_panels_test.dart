import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/ui/studio_workspace.dart';

void main() {
  Widget workspace() => MaterialApp(home: StudioWorkspace(
    viewport: const SizedBox.expand(key: ValueKey('test-viewport')),
    left: const TextField(key: ValueKey('left-editor')),
    right: const TextField(key: ValueKey('right-editor')),
    timeline: const SizedBox(), actions: const SizedBox(), status: const SizedBox(),
    tabs: const ['Recursos'], icons: const [Icons.folder_open], selectedTab: 0,
    onTab: (_) {}, onOpenData: () {},
  ));

  for (final side in ['left', 'right']) {
    testWidgets('$side detaches, moves, resizes, maximizes and redocks without losing fields', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(workspace());
      final field = find.byKey(ValueKey('$side-editor'));
      await tester.enterText(field, '1.25');
      final before = tester.getSize(find.byKey(const ValueKey('test-viewport')));
      await tester.tap(find.byKey(ValueKey('float-$side')));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('floating-$side')), findsOneWidget);
      expect(tester.widget<TextField>(field).controller, isNull);
      expect(find.text('1.25'), findsOneWidget);
      final detached = tester.getSize(find.byKey(const ValueKey('test-viewport')));
      expect(detached.width, greaterThan(before.width));
      await tester.drag(find.byKey(ValueKey('floating-resize-$side')), const Offset(90, 80));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(const ValueKey('test-viewport'))), detached);
      final panel = tester.getRect(find.byKey(ValueKey('floating-$side')));
      await tester.dragFrom(panel.topLeft + const Offset(45, 17), const Offset(25, 12));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(const ValueKey('test-viewport'))), detached);
      await tester.tap(find.byKey(ValueKey('maximize-$side'))); await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(const ValueKey('test-viewport'))), detached);
      await tester.tap(find.byKey(ValueKey('maximize-$side'))); await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('dock-$side'))); await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('floating-$side')), findsNothing);
      expect(find.text('1.25'), findsOneWidget);
      expect(tester.getSize(find.byKey(const ValueKey('test-viewport'))), before);
      await tester.enterText(field, '2.50');
      expect(find.text('2.50'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('dock expansion reserves a useful central area without hiding the other dock', (tester) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(workspace());
    await tester.drag(find.byKey(const ValueKey('resize-left-dock')), const Offset(300, 0));
    await tester.pumpAndSettle();
    await tester.drag(find.byKey(const ValueKey('resize-right-dock')), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const ValueKey('test-viewport'))).width, greaterThanOrEqualTo(380));
    expect(find.byKey(const ValueKey('right-editor')).hitTestable(), findsOneWidget);
    expect(find.byKey(const ValueKey('left-editor')).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
