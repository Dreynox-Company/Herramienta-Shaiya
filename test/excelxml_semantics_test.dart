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
        issues.every((issue) => issue.severity == ExcelXmlIssueSeverity.error),
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

  test('WingPosition accepts exactly the canonical 48 identity profiles', () {
    final rows = <List<num>>[];
    for (var family = 0; family < 4; family++) {
      for (var job = 0; job < 6; job++) {
        for (var sex = 0; sex < 2; sex++) {
          rows.add([family, job, sex, 4, 0, 0, 90, .05, -.18, 0]);
        }
      }
    }
    final doc = ExcelXmlDocument.parse(
      workbook(
        const [
          'FAMILY',
          'JOB',
          'SEX',
          'BONE_IDX',
          'WING_ROT_X',
          'WING_ROT_Y',
          'WING_ROT_Z',
          'WING_UP_DOWN',
          'WING_FRONT_BACK',
          'WING_LEFT_RIGHT',
        ],
        rows,
      ),
      'excelxml/wingposition.xml',
    );
    expect(auditExcelXmlSemantics(doc), isEmpty);
  });

  test('WingPosition blocks duplicate identities and incomplete profile matrix', () {
    final doc = ExcelXmlDocument.parse(
      workbook(
        const [
          'FAMILY',
          'JOB',
          'SEX',
          'BONE_IDX',
          'WING_ROT_X',
          'WING_ROT_Y',
          'WING_ROT_Z',
          'WING_UP_DOWN',
          'WING_FRONT_BACK',
          'WING_LEFT_RIGHT',
        ],
        const [
          [0, 0, 0, 4, 170, 0, 90, .05, -.18, 0],
          [0, 0, 0, 4, 170, 0, 90, .05, -.18, 0],
        ],
      ),
      'excelxml/wingposition.xml',
    );
    final issues = auditExcelXmlSemantics(doc);
    expect(issues.any((issue) => issue.code == 'duplicate-key'), isTrue);
    expect(issues.any((issue) => issue.code == 'wing-profile-count'), isTrue);
  });

  test('BattleField prizes validate rank range and Item/Count pairs', () {
    final doc = ExcelXmlDocument.parse(
      workbook(
        const [
          'RankMin',
          'RankMax',
          'Item1',
          'Count1',
          'Item2',
          'Count2',
          'Item3',
          'Count3',
          'Item4',
          'Count4',
        ],
        const [
          [3, 1, 118236, 1, 0, 0, 0, 0, 0, 0],
          [4, 10, 95011, 0, 0, 0, 0, 0, 0, 0],
        ],
      ),
      'excelxml/BattleField3Prize.xml',
    );
    final issues = auditExcelXmlSemantics(doc);
    expect(issues.any((issue) => issue.code == 'rank-range'), isTrue);
    expect(issues.any((issue) => issue.code == 'item-count'), isTrue);
  });

  test('RenownShop rejects invalid IDs/counts but permits zero optional limits', () {
    final doc = ExcelXmlDocument.parse(
      workbook(
        const [
          'ID',
          'ItemID',
          'ItemCount',
          'Renown',
          'KillLevel',
          'LimitType',
          'LimitNum',
        ],
        const [
          [1, 125002, 10, 100, 0, 0, 0],
          [1, 0, 0, -1, 0, 0, 0],
        ],
      ),
      'excelxml/RenownShop.xml',
    );
    final issues = auditExcelXmlSemantics(doc);
    expect(issues.any((issue) => issue.code == 'duplicate-key'), isTrue);
    expect(
      issues.any((issue) => issue.message.contains('ItemID')),
      isTrue,
    );
    expect(
      issues.any((issue) => issue.message.contains('Renown')),
      isTrue,
    );
  });

  test('time notices validate calendar field ranges when fields are present', () {
    final doc = ExcelXmlDocument.parse(
      workbook(
        const [
          'WHO',
          'SYSMSGINDEX',
          'YEAR',
          'MONTH',
          'DAY',
          'HOUR',
          'MINUTE',
          'END_YEAR',
          'END_MONTH',
          'END_DAY',
          'END_HOUR',
          'END_MINUTE',
        ],
        const [
          [999, 13850, 2020, 13, 6, 25, 0, 2020, 7, 6, 1, 0],
        ],
      ),
      'excelxml/timenoticesystem.xml',
    );
    final issues = auditExcelXmlSemantics(doc);
    expect(
      issues.where((issue) => issue.message.contains('MONTH')),
      isNotEmpty,
    );
    expect(
      issues.where((issue) => issue.message.contains('HOUR')),
      isNotEmpty,
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
