import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/game_text_codec.dart';
import 'package:herramienta_shaiya/core/game_metadata.dart';
import 'package:herramienta_shaiya/data/equipment_registry.dart';
import 'package:herramienta_shaiya/data/item_publication.dart';
import 'package:herramienta_shaiya/data/library.dart';
import 'editor_document_test.dart' show binaryTable;

Uint8List itemTextFixture(List<(int, int, String, String)> rows) {
  final header = binaryTable([
    'ItemType',
    'ItemTypeId',
    'ItemName',
    'Text',
  ], []);
  ByteData.sublistView(
    header,
  ).setUint32(header.length - 4, rows.length, Endian.little);
  final out = BytesBuilder()..add(header);
  for (final r in rows) {
    for (final n in [r.$1, r.$2]) {
      out.add(
        (ByteData(8)..setInt64(0, n, Endian.little)).buffer.asUint8List(),
      );
    }
    for (final s in [r.$3, r.$4]) {
      final b = GameTextCodec.windows.encode(s);
      out.add(
        (ByteData(
          4,
        )..setUint32(0, b.length, Endian.little)).buffer.asUint8List(),
      );
      out.add(b);
    }
  }
  return out.takeBytes();
}

Uint8List itemDataFixture() => binaryTable(
  [
    'ItemType',
    'ItemTypeId',
    'Image',
    'Icon',
    'ReqLv',
    'Country',
    'AttackFighter',
    'DefenseFighter',
  ],
  [
    [73, 6, 42, 47, 80, 0, 1, 0],
    [73, 7, 43, 48, 82, 0, 1, 0],
  ],
);
ItemPublication makePublication(
  List<ItemPublicationEdit> edits, {
  String textPath = 'binarysdata/dbitemtext_spn.sdata',
}) => ItemPublication.prepare(
  data: itemDataFixture(),
  text: itemTextFixture([
    (73, 6, '????', 'Descripción'),
    (73, 7, 'Armadura existente', 'Original'),
  ]),
  dataPath: 'binarysdata/dbitemdata.sdata',
  textPath: textPath,
  edits: edits,
);

void main() {
  test('broken Spanish name is existing, not an absent object', () {
    final items = EquipmentRegistry.parse({
      'data': itemDataFixture(),
      'dataPath': 'dbitemdata.sdata',
      'text': itemTextFixture([
        (73, 6, '????', 'Descripción'),
        (73, 7, 'Armadura existente', 'Original'),
      ]),
      'textPath': 'dbitemtext_spn.sdata',
    });
    expect(items[0].key, '73:6');
    expect(items[0].image, 42);
    expect(items[0].hasName, false);
    expect(items[0].label, contains('Sin nombre localizado'));
  });
  test(
    'repair retains Type/ID/Image and other records without adding a row',
    () {
      final p = makePublication([
        const ItemPublicationEdit(
          type: 73,
          id: 6,
          name: 'Armadura del Alba',
          description: 'Protección española',
          properties: {'Icon': '50', 'ReqLv': '81'},
        ),
      ]);
      final numeric = DataTable.open(p.dataAfter, p.dataPath).integers();
      expect(numeric, hasLength(2));
      expect(numeric.first['itemtypeid'], 6);
      expect(numeric.first['image'], 42);
      expect(numeric.first['icon'], 50);
      expect(numeric.first['reqlv'], 81);
      expect(
        numeric[1],
        DataTable.open(itemDataFixture(), 'data').integers()[1],
      );
      final text = readItemNames(p.textAfter, p.textPath);
      expect(text.first.name, 'Armadura del Alba');
      expect(text.first.description, 'Protección española');
      expect(text[1].name, 'Armadura existente');
      expect(p.changes.single['action'], 'repair-existing');
    },
  );
  test(
    'new item requires explicit same-type template and appears in both tables',
    () {
      final p = makePublication([
        const ItemPublicationEdit(
          type: 73,
          id: 8,
          templateId: 6,
          name: 'Nueva armadura',
          description: 'Prueba',
          properties: {'image': '44'},
        ),
      ]);
      expect(
        DataTable.open(p.dataAfter, p.dataPath).integers().last['image'],
        44,
      );
      final text = readItemNames(p.textAfter, p.textPath);
      expect(text, hasLength(3));
      expect(text.last.key, '73:8');
      expect(text.last.name, 'Nueva armadura');
    },
  );
  test(
    'duplicate creation, implicit creation, invalid encoding and keys fail closed',
    () {
      for (final edit in [
        const ItemPublicationEdit(
          type: 73,
          id: 6,
          templateId: 7,
          name: 'Duplicado',
          description: '',
        ),
        const ItemPublicationEdit(
          type: 73,
          id: 8,
          name: 'Sin plantilla',
          description: '',
        ),
        const ItemPublicationEdit(
          type: 73,
          id: 256,
          templateId: 6,
          name: 'Truncaría byte',
          description: '',
        ),
        const ItemPublicationEdit(
          type: 73,
          id: 6,
          name: '????',
          description: '',
        ),
        const ItemPublicationEdit(
          type: 73,
          id: 6,
          name: 'Inválido 🔥',
          description: '',
        ),
        const ItemPublicationEdit(
          type: 73,
          id: 6,
          name: 'Nombre',
          description: '',
          properties: {'itemtypeid': '7'},
        ),
        const ItemPublicationEdit(
          type: 73,
          id: 6,
          name: 'Nombre',
          description: '',
          properties: {'imaginary_field': '7'},
        ),
        const ItemPublicationEdit(
          type: 73,
          id: 6,
          name: 'Nombre',
          description: '',
          properties: {'icon': '-1'},
        ),
      ]) {
        expect(() => makePublication([edit]), throwsFormatException);
      }
      expect(
        () => makePublication([
          const ItemPublicationEdit(
            type: 73,
            id: 6,
            name: 'Nombre',
            description: '',
          ),
        ], textPath: 'dbitemtext_spn.sdata'),
        throwsFormatException,
      );
    },
  );
  test(
    'publication stages two files, does not mutate DATA, rejects stale input',
    () async {
      final dir = await Directory.systemTemp.createTemp('publication-');
      addTearDown(() => dir.delete(recursive: true));
      final p = makePublication([
        const ItemPublicationEdit(
          type: 73,
          id: 6,
          name: 'Nombre',
          description: '',
        ),
      ]);
      final data = File('${dir.path}/data.sdata'),
          text = File('${dir.path}/text.sdata');
      await data.writeAsBytes(p.dataBefore);
      await text.writeAsBytes(p.textBefore);
      final lib = Library(dir.path, false, {
        p.dataPath: data.path,
        p.textPath: text.path,
      });
      final out = await p.export(lib, Directory('${dir.path}/publication'));
      expect(
        await File('${out.path}/COPIAR_EN_DATA/${p.textPath}').readAsBytes(),
        p.textAfter,
      );
      expect(await data.readAsBytes(), p.dataBefore);
      expect(await text.readAsBytes(), p.textBefore);
      await data.writeAsBytes([0, 1, 2]);
      await expectLater(
        p.export(lib, Directory('${dir.path}/conflict')),
        throwsFormatException,
      );
      expect(await Directory('${dir.path}/conflict').exists(), false);
      expect(
        (await dir.list().toList()).where(
          (e) => e.path.contains('.appearance-stage-'),
        ),
        isEmpty,
      );
    },
  );
}
