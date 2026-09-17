import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/ui/studio_workspace.dart';

Widget workspace(ValueChanged<bool> toggle) => MaterialApp(
  theme: ThemeData.dark(useMaterial3: true),
  home: StudioWorkspace(
    viewport: const SizedBox.expand(),
    left: SwitchListTile(
      key: const ValueKey('left-control'),
      title: const Text('Proteger rostro y cabello'),
      value: true,
      onChanged: toggle,
    ),
    right: SwitchListTile(
      key: const ValueKey('right-control'),
      title: const Text('Reproducción'),
      value: true,
      onChanged: toggle,
    ),
    timeline: const Text('Animación'),
    actions: const Text('Ataques'),
    status: const Text('Preparado'),
    tabs: const ['Personaje'],
    icons: const [Icons.person_outline],
    selectedTab: 0,
    onTab: (_) {},
    onOpenData: () {},
    hasLibrary: true,
  ),
);

void main() {
  testWidgets('desktop docks own Material surfaces for live ListTile controls', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var calls = 0;
    await tester.pumpWidget(workspace((_) => calls++));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('0.3.1 · Laboratorio 3D'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('left-control')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('toggle-right')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('right-control')));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile inspector keeps ListTile feedback on a Material surface', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var calls = 0;
    await tester.pumpWidget(workspace((_) => calls++));
    await tester.tap(find.byKey(const ValueKey('toggle-right')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('right-control')));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });
}
