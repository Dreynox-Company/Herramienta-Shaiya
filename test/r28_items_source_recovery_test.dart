import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/data/library.dart';
import 'package:herramienta_shaiya/ui/items_source_recovery.dart';
import 'package:herramienta_shaiya/ui/items_page.dart';
import 'fixtures/resource_spk_fixture.dart';

void main() {
  testWidgets('missing DATA table shows recovery, retry and the original diagnosis', (tester) async {
    final lib = Library('no-table', false, {'script/a.txt': 'not-read'});
    addTearDown(lib.dispose);
    ItemsRecoveryAction? selected;
    await tester.pumpWidget(MaterialApp(home: ItemsPage(library: lib,
      onRecovery: (action) => selected = action)));
    await tester.pumpAndSettle();
    expect(find.text('El catálogo de Ítems necesita su tabla real'), findsOneWidget);
    expect(find.byKey(const ValueKey('items-open-spk')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('items-open-resources')));
    expect(selected, ItemsRecoveryAction.resources);
    await tester.tap(find.byKey(const ValueKey('items-retry-load')));
    await tester.pumpAndSettle();
    expect(find.text('El catálogo de Ítems necesita su tabla real'), findsOneWidget);
    await tester.tap(find.text('Diagnóstico técnico')); await tester.pumpAndSettle();
    expect(find.textContaining('Falta BinarySData/DBItemData.SData'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('locked SPK distinguishes metadata from read access and gates reference validation', (tester) async {
    final setup = await tester.runAsync(() async {
      final root = await Directory.systemTemp.createTemp('r28-spk-recovery-');
      final source = await resourceSpkFixture(root, {
        for (var i = 0; i < 3; i++) 'script/$i.txt': Uint8List.fromList(utf8.encode('resource $i test content')),
      });
      final lib = await Library.fromSpkEditable(source, allowLocked: true);
      return (root, source, lib);
    });
    final (root, source, lib) = setup!;
    addTearDown(() => root.delete(recursive: true));
    addTearDown(lib.dispose);
    final actions = <ItemsRecoveryAction>[];
    Widget panel() => MaterialApp(home: Scaffold(body: ItemsSourceRecovery(
      library: lib, error: 'fixture missing table', onRetry: () {}, onRecovery: actions.add)));
    await tester.pumpWidget(panel());
    expect(find.text('4 registros indexados · 0 rutas confirmadas'), findsOneWidget);
    expect(find.text('Lectura simple: pendiente · fragmentados: pendientes'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.byKey(const ValueKey('items-confirm-paths'))).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('items-open-spk')));
    expect(actions, [ItemsRecoveryAction.spk]);
    await tester.runAsync(() => source.validateSimpleResourceProfile());
    await tester.pumpWidget(panel()); await tester.pump();
    expect(find.text('Lectura simple: habilitada · fragmentados: pendientes'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('items-confirm-paths')));
    expect(actions.last, ItemsRecoveryAction.reference);
    expect(source.names.isConfirmed(0x1000), isFalse);
    expect(source.canReadFragmentedResources, isFalse);
    expect(source.canExtractAll, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
