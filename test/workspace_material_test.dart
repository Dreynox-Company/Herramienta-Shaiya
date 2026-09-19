import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/ui/studio_workspace.dart';

/// Regression for Windows integration run 35177675771: the dock background
/// must be a Material surface, not an opaque widget hiding ListTile's ink.
void expectUnobstructedMaterial(WidgetTester tester) {
  final tiles = find.byType(ListTile);
  expect(tiles, findsWidgets);
  for (final element in tiles.evaluate()) {
    var foundMaterial = false;
    element.visitAncestorElements((ancestor) {
      final widget = ancestor.widget;
      if (widget is Material) {
        foundMaterial = true;
        return false;
      }
      if (widget is ColoredBox) {
        expect(widget.color.a, 0, reason: 'An opaque box hides ListTile ink.');
      }
      if (widget is DecoratedBox && widget.decoration is BoxDecoration) {
        final decoration = widget.decoration as BoxDecoration;
        expect(
          decoration.color?.a ?? 0,
          0,
          reason: 'Panel decoration must not obscure its Material surface.',
        );
      }
      return true;
    });
    expect(foundMaterial, isTrue);
  }
}

void main() {
  for (final size in [
    const Size(1440, 900),
    const Size(1024, 768),
    const Size(390, 844),
    const Size(844, 390),
  ]) {
    testWidgets('interactive panel Material at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var protectIdentity = true;
      var showMesh = false;
      var playSound = false;
      var updates = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: Brightness.dark,
            useMaterial3: true,
            visualDensity: VisualDensity.compact,
          ),
          home: StatefulBuilder(
            builder: (context, update) => StudioWorkspace(
              viewport: const SizedBox.expand(),
              left: Column(
                children: [
                  SwitchListTile(
                    key: const ValueKey('protect-identity'),
                    title: const Text('Proteger rostro y cabello'),
                    value: protectIdentity,
                    onChanged: (value) => update(() {
                      protectIdentity = value;
                      updates++;
                    }),
                  ),
                  CheckboxListTile(
                    key: const ValueKey('show-mesh'),
                    title: const Text('Mostrar malla'),
                    value: showMesh,
                    onChanged: (value) => update(() {
                      showMesh = value!;
                      updates++;
                    }),
                  ),
                ],
              ),
              right: SwitchListTile(
                key: const ValueKey('play-sound'),
                title: const Text('Activar sonido'),
                value: playSound,
                onChanged: (value) => update(() {
                  playSound = value;
                  updates++;
                }),
              ),
              timeline: const SizedBox(height: 32),
              actions: const SizedBox(height: 36),
              status: const Text('Listo'),
              tabs: const ['Personaje'],
              icons: const [Icons.person_outline],
              selectedTab: 0,
              onTab: (_) {},
              onOpenData: () {},
              hasLibrary: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (size.width < 840) {
        await tester.tap(find.byKey(const ValueKey('toggle-left')));
        await tester.pumpAndSettle();
      }
      expectUnobstructedMaterial(tester);
      await tester.tap(find.byKey(const ValueKey('protect-identity')));
      await tester.pumpAndSettle();
      expect(protectIdentity, isFalse);
      await tester.tap(find.byKey(const ValueKey('show-mesh')));
      await tester.pumpAndSettle();
      expect(showMesh, isTrue);
      expect(tester.takeException(), isNull);
      final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold));
      if (scaffold.isDrawerOpen) {
        scaffold.closeDrawer();
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const ValueKey('toggle-right')));
      await tester.pumpAndSettle();
      expectUnobstructedMaterial(tester);
      await tester.tap(find.byKey(const ValueKey('play-sound')));
      await tester.pumpAndSettle();
      expect(playSound, isTrue);
      expect(updates, 3);
      expect(tester.takeException(), isNull);
      if (scaffold.isEndDrawerOpen) {
        scaffold.closeEndDrawer();
      } else {
        await tester.tap(find.byKey(const ValueKey('toggle-right')));
      }
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('toggle-right')));
      await tester.pumpAndSettle();
      expectUnobstructedMaterial(tester);
      expect(
        tester
            .widget<SwitchListTile>(find.byKey(const ValueKey('play-sound')))
            .value,
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }
}
