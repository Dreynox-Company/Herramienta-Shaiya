import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/equipment_rules.dart';
import 'package:herramienta_shaiya/data/equipment_registry.dart';
import 'editor_document_test.dart' show binaryTable;
import 'item_publication_test.dart' show itemDataFixture, itemTextFixture;

void main() {
  test('modern armor type is classified by native slot, not filename 016', () {
    final items = EquipmentRegistry.parse({
      'data': itemDataFixture(),
      'dataPath': 'dbitemdata.sdata',
      'text': itemTextFixture([(73, 6, 'Armadura', '')]),
      'textPath': 'dbitemtext_spn.sdata',
    });
    expect(items.first.slots, [1]);
    expect(items.first.id, 6);
    expect(items.first.image, 42);
    expect(ItemRule.fromRow(items.first.values).allows('human', fighter), true);
    expect(
      ItemRule.fromRow(items.first.values).allows('human', defender),
      false,
    );
    expect(ItemRule.fromRow(items.first.values).allows('vile', pagan), false);
  });
  test('duplicate primary IDs do not silently overwrite the registry', () {
    expect(
      () => EquipmentRegistry.parse({
        'data': binaryTable(
          ['ItemType', 'ItemTypeId', 'Image'],
          [
            [121, 5, 7],
            [121, 5, 8],
          ],
        ),
        'dataPath': 'dbitemdata.sdata',
      }),
      throwsFormatException,
    );
  });
  test('shared Image is valid and preserves distinct registered items', () {
    final items = EquipmentRegistry.parse({
      'data': binaryTable(
        ['ItemType', 'ItemTypeId', 'Image'],
        [
          [121, 5, 7],
          [121, 6, 7],
        ],
      ),
      'dataPath': 'dbitemdata.sdata',
    });
    expect(items.map((i) => i.key), ['121:5', '121:6']);
    expect(items.map((i) => i.image), [7, 7]);
  });
}
