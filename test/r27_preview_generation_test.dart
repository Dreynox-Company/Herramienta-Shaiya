import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/data/library.dart';
import 'package:herramienta_shaiya/data/resource_index.dart';
import 'package:herramienta_shaiya/ui/resource_workspace.dart';

// This controlled reader tests widget lifetime only. AES-GCM and real resource
// parsing are exercised by r27_resource_workspace_test and native integration.
class PendingPreviewIndex extends ResourceIndex {
  final pending = <String, Completer<ResourceRead>>{};
  PendingPreviewIndex()
    : super(
        Library('preview-fixture', false, {
          'a.ani': 'not-read',
          'b.ani': 'not-read',
          'c.ani': 'not-read',
        }),
      );

  @override
  Future<ResourceRead> read(
    ResourceEntry entry, {
    int limit = 64 * 1024 * 1024,
  }) {
    return pending.putIfAbsent(entry.key, Completer<ResourceRead>.new).future;
  }

  void complete(String key, List<int> bytes) {
    pending[key]!.complete(
      ResourceRead(
        entries.firstWhere((e) => e.key == key),
        Uint8List.fromList(bytes),
        'ANI',
      ),
    );
  }
}

void main() {
  testWidgets(
    'changing selection removes old bytes while the new resource loads',
    (tester) async {
      final index = PendingPreviewIndex();
      addTearDown(index.dispose);
      final selected = ValueNotifier<ResourceEntry>(index.entries.first);
      addTearDown(selected.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<ResourceEntry>(
              valueListenable: selected,
              builder: (_, entry, _) =>
                  ResourcePreview(index: index, entry: entry),
            ),
          ),
        ),
      );
      index.complete('a.ani', [1, 2, 3]);
      await tester.pump();
      await tester.pump();
      expect(find.text('a.ani · ANI · 3 B'), findsOneWidget);
      selected.value = index.entries.firstWhere((e) => e.key == 'b.ani');
      await tester.pump();
      expect(find.text('a.ani · ANI · 3 B'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      index.complete('b.ani', [4, 5]);
      await tester.pump();
      await tester.pump();
      expect(find.text('b.ani · ANI · 2 B'), findsOneWidget);
      expect(find.text('a.ani · ANI · 3 B'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'late completion cannot replace a newer selection or rebuild after disposal',
    (tester) async {
      final index = PendingPreviewIndex();
      addTearDown(index.dispose);
      final selected = ValueNotifier<ResourceEntry>(index.entries.first);
      addTearDown(selected.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<ResourceEntry>(
              valueListenable: selected,
              builder: (_, entry, _) =>
                  ResourcePreview(index: index, entry: entry),
            ),
          ),
        ),
      );
      selected.value = index.entries.firstWhere((e) => e.key == 'b.ani');
      await tester.pump();
      selected.value = index.entries.firstWhere((e) => e.key == 'c.ani');
      await tester.pump();
      index.complete('c.ani', [3]);
      await tester.pump();
      await tester.pump();
      index.complete('a.ani', [1, 1]);
      await tester.pump();
      await tester.pump();
      expect(find.text('c.ani · ANI · 1 B'), findsOneWidget);
      expect(find.textContaining('a.ani'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      index.complete('b.ani', [2, 2, 2]);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
