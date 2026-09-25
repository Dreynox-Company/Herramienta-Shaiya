import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/excelxml_document.dart';

Uint8List spreadsheet() => Uint8List.fromList(
  utf8.encode(
    '<?xml version="1.0"?>'
    '<?mso-application progid="Excel.Sheet"?>'
    '<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet" '
    'xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">'
    '<Styles><Style ss:ID="s1"/></Styles>'
    '<Worksheet ss:Name="Wing">'
    '<Table>'
    '<Row><Cell><Data ss:Type="String">note</Data></Cell></Row>'
    '<Row>'
    '<Cell><Data ss:Type="String">FAMILY</Data></Cell>'
    '<Cell><Data ss:Type="String">WING_ROT_X</Data></Cell>'
    '<Cell><Data ss:Type="String">WING_UP_DOWN</Data></Cell>'
    '</Row>'
    '<Row ss:StyleID="s1">'
    '<Cell><Data ss:Type="Number">0</Data></Cell>'
    '<Cell><Data ss:Type="Number">170</Data><Comment><Data>keep</Data></Comment></Cell>'
    '<Cell><Data ss:Type="Number">0.05</Data></Cell>'
    '</Row>'
    '<Row>'
    '<Cell><Data ss:Type="Number">1</Data></Cell>'
    '<Cell ss:Index="3"><Data ss:Type="Number">0.10</Data></Cell>'
    '</Row>'
    '</Table>'
    '</Worksheet>'
    '</Workbook>',
  ),
);

void main() {
  test(
    'SpreadsheetML table is detected and edited without flattening metadata',
    () {
      final doc = ExcelXmlDocument.parse(
        spreadsheet(),
        'excelxml/wingposition.xml',
      );
      expect(doc.sheets, hasLength(1));
      final sheet = doc.sheets.single;
      expect(sheet.name, 'Wing');
      expect(sheet.headerRow, 2);
      expect(sheet.columns.map((c) => c.label), [
        'FAMILY',
        'WING_ROT_X',
        'WING_UP_DOWN',
      ]);
      expect(sheet.rows, hasLength(2));
      expect(sheet.rows.first.value(2), '170');

      doc.setCell(0, 0, 2, '182.5');
      final encoded = doc.encode();
      doc.validateEncoded(encoded);
      final xml = utf8.decode(encoded);
      expect(xml, contains('mso-application'));
      expect(xml, contains('Style'));
      expect(xml, contains('keep'));

      final reparsed = ExcelXmlDocument.parse(
        encoded,
        'excelxml/wingposition.xml',
      );
      expect(reparsed.sheets.single.rows.first.value(2), '182.5');
    },
  );

  test('SpreadsheetML Number validation rejects malformed edits', () {
    final doc = ExcelXmlDocument.parse(
      spreadsheet(),
      'excelxml/wingposition.xml',
    );
    final row = doc.sheets.single.rows.first;
    expect(row.cellType(2), 'Number');
    expect(() => doc.setCell(0, 0, 2, 'not-a-number'), throwsFormatException);
    expect(row.value(2), '170');
    doc.setCell(0, 0, 2, '-180.125');
    expect(row.value(2), '-180.125');
  });

  test(
    'missing sparse cell is fail-closed instead of inventing XML structure',
    () {
      final doc = ExcelXmlDocument.parse(spreadsheet(), 'excelxml/test.xml');
      expect(doc.sheets.single.rows[1].hasCell(2), isFalse);
      expect(
        () => doc.setCell(0, 1, 2, '123'),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test('WingExpItem uses the actual ItemID row as machine header', () {
    final bytes = Uint8List.fromList(
      utf8.encode(
        '<?xml version="1.0"?>'
        '<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet" '
        'xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">'
        '<Worksheet ss:Name="Sheet1"><Table>'
        '<Row><Cell><Data ss:Type="String">经验道具ID</Data></Cell></Row>'
        '<Row><Cell><Data ss:Type="String">ItemID</Data></Cell></Row>'
        '<Row><Cell><Data ss:Type="Number">125001</Data></Cell></Row>'
        '<Row><Cell><Data ss:Type="Number">125002</Data></Cell></Row>'
        '</Table></Worksheet></Workbook>',
      ),
    );

    final doc = ExcelXmlDocument.parse(bytes, 'excelxml/WingExpItem.xml');
    final sheet = doc.sheets.single;
    expect(sheet.headerRow, 2);
    expect(sheet.columns.single.label, 'ItemID');
    expect(sheet.rows.map((row) => row.value(1)), ['125001', '125002']);
  });

  test('purpose catalogue classifies high-value Studio tables', () {
    expect(excelXmlPurpose('excelxml/wingposition.xml'), contains('Alas'));
    expect(
      excelXmlPurpose('excelxml/ymwatershaderparams.xml'),
      contains('Mundo'),
    );
    expect(excelXmlPurpose('excelxml/mainquest.xml'), contains('Quests'));
    expect(
      excelXmlPurpose('excelxml/MonDeathItemWorldDrop.xml'),
      contains('Monstruos'),
    );
  });
}
