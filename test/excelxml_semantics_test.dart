import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/excelxml_document.dart';
import 'package:herramienta_shaiya/core/excelxml_semantics.dart';

Uint8List workbook(List<String> headers, List<List<num>> rows) {
  String row(Iterable<Object> values, {bool header = false}) =>
      '<Row>${values.map((value) => '<Cell><Data ss:Type="${header ? 'String' : 'Number'}">$value</Data></Cell>').join()}</Row>';
  return Uint8List.fromList(
    utf8.encode(
      '<?xml version="1.0"?>'
      '<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet" '
      'xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">'
      '<Worksheet ss:Name="Sheet1"><Table>'
      '${row(headers, header: true)}'
      '${rows.map(row).join()}'
      '</Table></Worksheet></Workbook>',
    ),
  );
}

void main() {
  test(
    'WingSwap rejects mismatched item/count pairs and duplicate source wing',
    () {
      final doc = ExcelXmlDocument.parse(
        workbook(
          const [
            'OldWingItem',
            'ExchangeItem1',
            'Count1',
            'ExchangeItem2',
            'Count2',
            'ExchangeItem3',
            'Count3',
          ],
          const [
            [121016, 124001, 1, 0, 0, 0, 0],
            [121016, 124004, 0, 0, 0, 0, 0],
          ],
        ),
        'excelxml/WingSwap.xml',
      );

      final issues = auditExcelXmlSemantics(doc);
      expect(
        issues.where((issue) => issue.code == 'duplicate-key'),
        hasLength(1),
      );
      expect(
        issues.where((issue) => issue.code == 'exchange-pair'),
        hasLength(1),
      );
      expect(
        issues.every(
          (issue) => issue.severity == ExcelXmlIssueSeverity.error,
        ),
        isTrue,
      );
    },
  );

  test('water shader enforces only ranges explicit in supplied DATA', () {
    final doc = ExcelXmlDocument.parse(
      workbook(
        const [
          'MapID',
          'UseFlag',
          'ShallowColorR',
          'ShallowColorG',
          'ShallowColorB',
          'ShallowColorA',
          'DeepColorR',
          'DeepColorG',
          'DeepColorB',
          'DeepColorA',
          'UnderwaterColorR',
          'UnderwaterColorG',
          'UnderwaterColorB',
          'UnderwaterViewDist',
          'UnderwaterIntensity',
          'WaveDensity',
          'WaveScale',
          'WaveSpeed',
          'WaterAmount',
          'ReflectionAmount',
          'ReflectionBlur',
          'FresnelBias',
          'HdrMultiplier',
          'SpecularPower',
        ],
        const [
          [
            7,
            2,
            300,
            128,
            150,
            30,
            999,
            50,
            60,
            80,
            50,
            70,
            60,
            6,
            .1,
            19,
            1.5,
            2.8,
            .36,
            .6,
            .1,
            .5,
            12,
            .4,
          ],
        ],
      ),
      'excelxml/ymwatershaderparams.xml',
    );

    final issues = auditExcelXmlSemantics(doc);
    final errors = issues
        .where((issue) => issue.severity == ExcelXmlIssueSeverity.error)
        .toList();
    final warnings = issues
        .where((issue) => issue.severity == ExcelXmlIssueSeverity.warning)
        .toList();

    expect(
      errors.map((issue) => issue.message).join('\n'),
      allOf(
        contains('UseFlag'),
        contains('shallowcolorr'),
        contains('wavescale'),
        contains('HdrMultiplier'),
      ),
    );
    expect(
      warnings.map((issue) => issue.message).join('\n'),
      contains('deepcolorr'),
    );
  });

  test('WingDecompose key is WingID plus Grade, not WingID alone', () {
    final doc = ExcelXmlDocument.parse(
      workbook(
        const ['WingID', 'Grade', 'OldWingItem', 'MaxLevel'],
        const [
          [1, 0, 121017, 20],
          [1, 1, 121018, 40],
          [1, 1, 121019, 60],
        ],
      ),
      'excelxml/WingDecompose.xml',
    );
    final issues = auditExcelXmlSemantics(doc);
    expect(
      issues.where((issue) => issue.code == 'duplicate-key'),
      hasLength(1),
    );
  });

  test('unknown ExcelXml tables stay fail-open semantically, not guessed', () {
    final doc = ExcelXmlDocument.parse(
      workbook(
        const ['Mystery', 'Value'],
        const [
          [-999, 999999],
        ],
      ),
      'excelxml/UnknownFutureTable.xml',
    );
    expect(auditExcelXmlSemantics(doc), isEmpty);
  });
}
