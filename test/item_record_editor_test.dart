import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/ui/item_record_editor.dart';
import 'package:herramienta_shaiya/ui/studio_workspace.dart';
import 'fixtures/item_workspace_fixture.dart';

void main() {
  testWidgets(
    'consumable draft applies through the shared session and exposes all fields',
    (tester) async {
      final w = memoryItems();
      await tester.binding.setSurfaceSize(const Size(1200, 950));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () =>
                      showItemRecordEditor(ctx, w, w.byKey['25:1']!),
                  child: const Text('Editar manzana'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Editar manzana'));
      await tester.pumpAndSettle();
      final search = find.widgetWithText(
        TextField,
        'Buscar propiedad por nombre nativo o etiqueta',
      );
      await tester.enterText(search, 'consthp');
      await tester.pump();
      final hp = find.byKey(
        const ValueKey('item-field-binarysdata/dbitemdata.sdata-consthp'),
      );
      expect(hp, findsOneWidget);
      await tester.enterText(hp, '500');
      await tester.tap(find.byKey(const ValueKey('apply-item-draft')));
      await tester.pumpAndSettle();
      expect(w.byKey['25:1']!.values['consthp'], '500');
      expect(w.registry.byKey['25:1']!.values['consthp'], 500);
      w.undo();
      expect(w.byKey['25:1']!.values['consthp'], '119');
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('item navigation fits a narrow header without centered overlap', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: StudioWorkspace(
          viewport: const SizedBox(),
          left: const SizedBox(),
          right: const SizedBox(),
          timeline: const SizedBox(),
          actions: const SizedBox(),
          status: const Text('Fixture'),
          tabs: const ['Personaje'],
          icons: const [Icons.person_outline],
          selectedTab: 0,
          onTab: (_) {},
          onOpenData: () {},
          onOpenEditor: () {},
          onOpenItems: () => opened++,
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-items-catalog')));
    expect(opened, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
