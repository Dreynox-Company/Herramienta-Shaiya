import 'dart:io';
import 'dart:typed_data';

import 'package:herramienta_shaiya/data/item_workspace.dart';
import 'package:herramienta_shaiya/data/library.dart';

import '../editor_document_test.dart' show binaryTable;
import '../item_publication_test.dart' show itemTextFixture;

const itemDataPath = 'binarysdata/dbitemdata.sdata';
const itemTextPath = 'binarysdata/dbitemtext_spn.sdata';
const itemFields = [
  'itemtype',
  'itemtypeid',
  'image',
  'icon',
  'level',
  'effect1',
  'effect2',
  'consthp',
  'conststr',
  'rec',
  'special',
  'count',
  'arg3',
];
Uint8List numericItems({bool duplicate = false}) => binaryTable(itemFields, [
  [1, 1, 1, 1, 1, 19, 2, 0, 0, 0, 0, 1, 9223372036854775000],
  [25, 1, 1, 1, 0, 0, 0, 119, 0, 0, 0, 255, 0],
  [30, 1, 1, 1, 1, 0, 0, 0, 3, 0, 0, 1, 0],
  [95, 1, 1, 71, 0, 0, 0, 0, 0, 0, 78, 1, 0],
  [121, 1, 12, 1, 61, 0, 0, 0, 10, 0, 0, 1, 0],
  [125, 1, 41, 1, 1, 0, 0, 0, 0, 0, 0, 1, 0],
  [128, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0],
  [73, 6, 42, 47, 80, 0, 0, 77, 0, 0, 0, 1, 0],
  if (duplicate) [1, 1, 1, 1, 1, 19, 2, 0, 0, 0, 0, 1, 0],
]);
Uint8List localizedItems({bool missing = false, bool duplicate = false}) =>
    itemTextFixture([
      if (!missing) (1, 1, 'Espada Larga', 'Daño base de ejemplo'),
      (25, 1, 'Manzana', 'Restaura 119 HP'),
      (30, 1, 'Lapis Artesanal', 'Fuerza +3'),
      (95, 1, 'Arma Lapisia', 'Mejora un arma'),
      (121, 1, 'Alas de Ángeles', 'Alas'),
      (125, 1, 'Cabello de Ángel', 'Montura'),
      (128, 1, 'Fármaco Antipirético', 'Objeto de misión'),
      (73, 6, '????', 'Nombre por reparar'),
      if (duplicate) (25, 1, 'Manzana duplicada', 'No elegir silenciosamente'),
    ]);
ItemWorkspace memoryItems({bool missing = false}) => ItemWorkspace.fromBytes(
  Library('fixture', false, {}),
  numericItems(),
  text: localizedItems(missing: missing),
  textPath: itemTextPath,
);
Future<(Directory, Library, ItemWorkspace)> diskItems() async {
  final temp = await Directory.systemTemp.createTemp('studio-items-test-');
  final data = File('${temp.path}/DATA/$itemDataPath'),
      text = File('${temp.path}/DATA/$itemTextPath');
  await data.parent.create(recursive: true);
  await data.writeAsBytes(numericItems());
  await text.writeAsBytes(localizedItems());
  final library = Library('${temp.path}/DATA', false, {
    itemDataPath: data.path,
    itemTextPath: text.path,
  });
  return (
    temp,
    library,
    ItemWorkspace.fromBytes(
      library,
      numericItems(),
      text: localizedItems(),
      textPath: itemTextPath,
    ),
  );
}

ItemFieldEdit fieldEdit(
  ItemWorkspace w,
  String key,
  String name,
  String value, {
  bool localized = false,
}) {
  final item = w.byKey[key]!, doc = localized ? w.text! : w.data;
  final row = localized ? item.textRow! : item.row;
  final f = doc
      .fields(row)
      .singleWhere((f) => f.spec.name.toLowerCase() == name);
  return ItemFieldEdit(doc.path, row, f.spec.name, doc.read(f), value);
}
