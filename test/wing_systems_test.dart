import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/wing_systems.dart';

Uint8List sheet(List<List<String>> rows) {
  final xml = StringBuffer(
    '<?xml version="1.0"?>'
    '<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet" '
    'xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">'
    '<Worksheet ss:Name="Sheet1"><Table>',
  );
  for (final row in rows) {
    xml.write('<Row>');
    for (final value in row) {
      final numeric = double.tryParse(value) != null;
      xml.write(
        '<Cell><Data ss:Type="${numeric ? 'Number' : 'String'}">'
        '${const HtmlEscape().convert(value)}</Data></Cell>',
      );
    }
    xml.write('</Row>');
  }
  xml.write('</Table></Worksheet></Workbook>');
  return Uint8List.fromList(utf8.encode(xml.toString()));
}

void main() {
  test(
    'wing native system tables are correlated without inventing semantics',
    () {
      final catalog = WingSystemsCatalog.parse(
        decomposeBytes: sheet([
          ['WingID', 'Grade', 'OldWingItem', 'MaxLevel'],
          ['1', '0', '121017', '20'],
          ['1', '1', '121018', '40'],
          ['2', '0', '121028', '20'],
        ]),
        expBytes: sheet([
          ['ItemID'],
          ['125001'],
          ['125002'],
        ]),
        swapBytes: sheet([
          [
            'OldWingItem',
            'ExchangeItem1',
            'Count1',
            'ExchangeItem2',
            'Count2',
            'ExchangeItem3',
            'Count3',
          ],
          ['121017', '124001', '6', '0', '0', '0', '0'],
          ['121028', '124004', '1', '124005', '2', '0', '0'],
        ]),
      );

      expect(catalog.wingIds, [1, 2]);
      expect(catalog.progressionFor(1).map((r) => r.grade), [0, 1]);
      expect(catalog.progressionFor(1).last.maxLevel, 40);
      expect(catalog.expItems, [125001, 125002]);

      final swap = catalog.swapForItem(121028);
      expect(swap, isNotNull);
      expect(swap!.rewards, hasLength(2));
      expect(swap.rewards.first.itemId, 124004);
      expect(swap.rewards.last.count, 2);
    },
  );

  test('duplicate wing grade fails closed', () {
    expect(
      () => WingSystemsCatalog.parse(
        decomposeBytes: sheet([
          ['WingID', 'Grade', 'OldWingItem', 'MaxLevel'],
          ['1', '0', '121017', '20'],
          ['1', '0', '121018', '40'],
        ]),
      ),
      throwsFormatException,
    );
  });

  test('invalid swap item/count pair fails closed', () {
    expect(
      () => WingSystemsCatalog.parse(
        swapBytes: sheet([
          [
            'OldWingItem',
            'ExchangeItem1',
            'Count1',
            'ExchangeItem2',
            'Count2',
            'ExchangeItem3',
            'Count3',
          ],
          ['121017', '124001', '0', '0', '0', '0', '0'],
        ]),
      ),
      throwsFormatException,
    );
  });
}
