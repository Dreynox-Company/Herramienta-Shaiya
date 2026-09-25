import 'dart:io';
import 'package:herramienta_shaiya/editor/item_field_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/item_icon_layout.dart';
import 'package:herramienta_shaiya/data/library.dart';
import 'package:herramienta_shaiya/editor/item_workspace.dart';
import 'package:herramienta_shaiya/editor/document.dart';
import 'package:herramienta_shaiya/ui/editor_icons.dart';
import 'package:herramienta_shaiya/ui/item_workbench.dart';
import 'editor_document_test.dart' show binaryTable;
import 'item_publication_test.dart' show itemTextFixture;

ItemWorkspace fixture({bool text = true}) => ItemWorkspace.parse({
  'path': 'binarysdata/dbitemdata.sdata',
  'data': binaryTable(
    [
      'ItemType',
      'ItemTypeId',
      'Image',
      'Icon',
      'Level',
      'Effect1',
      'ConstStr',
      'Arg12',
    ],
    [
      [1, 1, 0, 1, 1, 10, 0, 0],
      [25, 1, 0, 1, 0, 119, 0, 0],
      [29, 1, 0, 2, 0, 0, 0, 0],
      [95, 1, 0, 3, 0, 0, 0, 0],
      [121, 7, 7, 3, 80, 0, 10, 0],
      [42, 1, 0, 4, 1, 0, 0, 0],
      [73, 6, 42, 47, 80, 1, 20, 0],
      [200, 1, 0, 0, 0, 0, 0, 0],
    ],
  ),
  'textPath': 'binarysdata/dbitemtext_spn.sdata',
  'text': text
      ? itemTextFixture([
          (1, 1, 'Espada', 'Arma'),
          (25, 1, 'Manzana', 'Restaura HP'),
          (29, 1, 'Objeto de misión', 'Quest'),
          (95, 1, 'Lapisia', 'Mejora'),
          (121, 7, 'Alas del alba', 'Alas'),
          (42, 1, 'Montura', 'Animal'),
          (73, 6, '????', 'Original'),
          (200, 1, 'Especial', ''),
        ])
      : null,
});
FieldSpan field(EditDocument d, int row, String name) => d
    .fields(row)
    .singleWhere((f) => f.spec.name.toLowerCase() == name.toLowerCase());
void main() {
  test('field meaning follows type without inventing generic effect units', () {
    final s = fixture();
    expect(
      ItemFieldProfile.meaning(s.byKey['25:1']!, 'ConstHp').group,
      'Uso y recuperación',
    );
    expect(
      ItemFieldProfile.meaning(s.byKey['1:1']!, 'Effect1').group,
      'Daño y efectos',
    );
    expect(
      ItemFieldProfile.meaning(s.byKey['95:1']!, 'Effect1').group,
      'Mejora y efectos',
    );
    expect(
      ItemFieldProfile.meaning(s.byKey['73:6']!, 'Effect1').group,
      'Defensa y efectos',
    );
    expect(
      ItemFieldProfile.meaning(s.byKey['200:1']!, 'Arg12').label,
      contains('Arg12'),
    );
  });

  test('native icons use one-based IDs and actual per-type family tables', () {
    expect(ItemIconLayout.resolve(1, 1)!.tile, 0);
    final set = ItemIconLayout.resolve(73, 47)!;
    expect(set.stem, '17');
    expect(set.tile, 46);
    expect(set.columns, 4);
    expect(ItemIconLayout.resolve(25, 1)!.stem, 'icon_somo');
    expect(ItemIconLayout.resolve(121, 1)!.stem, 'icon_wing');
    expect(ItemIconLayout.resolve(122, 1)!.stem, 'icon_wing');
    expect(ItemIconLayout.resolve(125, 1)!.stem, 'icon_125_mount');
    expect(ItemIconLayout.resolve(94, 1)!.stem, 'icon_somo');
    expect(ItemIconLayout.resolve(30, 1)!.stem, 'icon_rapis');
    expect(ItemIconLayout.resolve(99, 1)!.stem, 'icon_quest2');
    expect(ItemIconLayout.resolve(128, 1)!.stem, 'icon_128_questitem');
  });
  test('page boundary 100 belongs only to the native paged types', () {
    final page = ItemIconLayout.resolve(5, 101)!;
    expect(page.stem, '105');
    expect(page.tile, 0);
    expect(page.pageBase, 101);
    expect(ItemIconLayout.resolve(121, 101)!.tile, 100);
    expect(ItemIconLayout.resolve(121, 101)!.stem, 'icon_wing');
    expect(ItemIconLayout.resolve(29, 101)!.stem, '127');
    for (final value in [-1, 0, 256]) {
      expect(ItemIconLayout.resolve(1, value), isNull);
    }
    expect(ItemIconLayout.resolve(200, 1), isNull);
    expect(ItemIconLayout.resolve(1, 65)!.inBounds, isFalse);
  });
  test('missing real atlas never substitutes an unrelated potion icon', () {
    final s = fixture(),
        images = EditorImages(
          Library('', false, {'interface/icon/icon_somo.dds': 'x'}),
        );
    addTearDown(images.dispose);
    expect(images.icon(s.data.path, s.byKey['121:7']!.summary), isNull);
    expect(images.icon(s.data.path, s.byKey['25:1']!.summary)!.index, 0);
  });
  test(
    'global list retains consumables quest materials equipment and unknown types',
    () {
      final s = fixture();
      expect(s.entries, hasLength(8));
      expect(s.byKey['73:6']!.named, false);
      expect(s.byKey['73:6']!.name, '????');
      expect(s.byKey['200:1'], isNotNull);
      expect(fixture(text: false).entries, hasLength(8));
    },
  );
  test('names accents IDs exclusion and typed comparisons all work', () {
    final s = fixture();
    expect(
      s.entries
          .where(ItemQuery.parse('mision', s.fieldNames).matches)
          .single
          .key,
      '29:1',
    );
    expect(
      s.entries
          .where(ItemQuery.parse('Level>=80 ConstStr>15', s.fieldNames).matches)
          .single
          .key,
      '73:6',
    );
    expect(
      s.entries
          .where(
            ItemQuery.parse('"alas del alba" -espada', s.fieldNames).matches,
          )
          .single
          .key,
      '121:7',
    );
    expect(
      () => ItemQuery.parse('invented=1', s.fieldNames),
      throwsFormatException,
    );
    expect(
      () => ItemQuery.parse('Level=NaN', s.fieldNames),
      throwsFormatException,
    );
    final f = field(s.data, 7, 'Arg12');
    s.apply({
      s.data: [(7, f, '9007199254740993')],
    });
    expect(
      s.entries
          .where(
            ItemQuery.parse('Arg12>9007199254740992', s.fieldNames).matches,
          )
          .single
          .key,
      '200:1',
    );
  });
  test('all categories edit typed native properties with paired undo redo', () {
    final s = fixture(),
        f = field(s.data, 6, 'Effect1'),
        name = field(s.text!, 6, 'ItemName');
    s.apply({
      s.data: [(6, f, '25')],
      s.text!: [(6, name, 'Armadura del Alba')],
    });
    expect(s.byKey['73:6']!.name, 'Armadura del Alba');
    expect(s.data.read(f), '25');
    s.undo();
    expect(s.byKey['73:6']!.name, '????');
    expect(s.data.read(f), '1');
    s.redo();
    expect(s.byKey['73:6']!.name, 'Armadura del Alba');
    expect(s.data.read(f), '25');
    final old = s.data.read(f);
    expect(
      () => s.apply({
        s.data: [(6, f, '26')],
        s.text!: [(6, name, 'Bad\u0000name')],
      }),
      throwsFormatException,
    );
    expect(s.data.read(f), old);
    expect(
      () => s.apply({
        s.data: [(6, field(s.data, 6, 'ItemTypeId'), '7')],
      }),
      throwsFormatException,
    );
  });
  test('raw signed-64-bit fields validate overflow without truncation', () {
    final s = fixture(), f = field(s.data, 7, 'Arg12');
    s.apply({
      s.data: [(7, f, '9223372036854775807')],
    });
    expect(s.data.read(f), '9223372036854775807');
    expect(
      () => s.apply({
        s.data: [(7, f, '9223372036854775808')],
      }),
      throwsFormatException,
    );
    s.apply({
      s.data: [(7, f, '-9223372036854775808')],
    });
    expect(s.data.read(f), '-9223372036854775808');
  });
  test(
    'export reopens pair, preserves original, rejects source conflict',
    () async {
      final dir = await Directory.systemTemp.createTemp('items-export-');
      addTearDown(() => dir.delete(recursive: true));
      final s = fixture(), files = <String, String>{};
      for (final d in s.documents.values) {
        final f = File('${dir.path}/${d.path}');
        await f.parent.create(recursive: true);
        await f.writeAsBytes(d.original);
        files[d.path] = f.path;
      }
      final lib = Library(dir.path, false, files),
          f = field(s.data, 1, 'Effect1');
      s.apply({
        s.data: [(1, f, '250')],
      });
      final out = await s.export(lib, Directory('${dir.path}/publication'));
      expect(
        await File('${out.path}/COPIAR_EN_DATA/${s.data.path}').exists(),
        true,
      );
      expect(await File(files[s.data.path]!).readAsBytes(), s.data.original);
      await File(files[s.data.path]!).writeAsBytes([1, 2, 3]);
      await expectLater(
        s.export(lib, Directory('${dir.path}/conflict')),
        throwsFormatException,
      );
      expect(await Directory('${dir.path}/conflict').exists(), false);
    },
  );
  testWidgets(
    'property editor offers every numeric field and localized text without changing DATA',
    (tester) async {
      final s = fixture(),
          e = s.byKey['25:1']!,
          images = EditorImages(Library('', false, {}));
      addTearDown(images.dispose);
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (c) => TextButton(
                onPressed: () => showDialog<void>(
                  context: c,
                  builder: (_) => ItemPropertiesDialog(
                    session: s,
                    images: images,
                    entry: e,
                    bindings: [
                      for (final f in s.data.fields(e.row))
                        PropertyBinding(s.data, e.row, f),
                      for (final f in s.text!.fields(e.textRow!))
                        if (f.spec.text)
                          PropertyBinding(s.text!, e.textRow!, f),
                    ],
                  ),
                ),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Manzana'), findsOneWidget);
      expect(find.text('Aplicar al borrador'), findsOneWidget);
      expect(find.textContaining('Buscar propiedad'), findsOneWidget);
      expect(s.dirty, false);
      expect(tester.takeException(), isNull);
    },
  );
}
