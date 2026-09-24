import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/wing_position.dart';

Uint8List fixture({bool oneBased = false, bool includeIdentity = true}) {
  final out = StringBuffer('<WingPosition>');
  for (var family = 0; family < 4; family++) {
    for (var job = 0; job < 6; job++) {
      for (var sex = 0; sex < 2; sex++) {
        final id = includeIdentity
            ? ' FAMILY="${family + (oneBased ? 1 : 0)}"'
                  ' JOB="${job + (oneBased ? 1 : 0)}"'
                  ' SEX="${sex + (oneBased ? 1 : 0)}"'
                  ' BONE_INDEX="4"'
            : '';
        out
          ..write('<Row$id>')
          ..write('<WING_ROT_X>${170 + family}</WING_ROT_X>')
          ..write('<WING_ROT_Y>${job * 2}</WING_ROT_Y>')
          ..write('<WING_ROT_Z>90</WING_ROT_Z>')
          ..write('<WING_UP_DOWN>${(sex + 1) / 100}</WING_UP_DOWN>')
          ..write('<WING_FRONT_BACK>-${(job + 1) / 10}</WING_FRONT_BACK>')
          ..write('<WING_LEFT_RIGHT>${family / 20}</WING_LEFT_RIGHT>')
          ..write('</Row>');
      }
    }
  }
  out.write('</WingPosition>');
  return Uint8List.fromList(utf8.encode(out.toString()));
}

Uint8List spreadsheetFixture() {
  final out = StringBuffer(
    '<?xml version="1.0"?>'
    '<?mso-application progid="Excel.Sheet"?>'
    '<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet" '
    'xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">'
    '<Worksheet ss:Name="Sheet1"><Table>'
    '<Row><Cell ss:StyleID="blank"><Data ss:Type="String"></Data></Cell></Row>'
    '<Row>'
    '<Cell><Data ss:Type="String">FAMILY</Data><Comment><Data>family comment</Data></Comment></Cell>'
    '<Cell><Data ss:Type="String">JOB</Data></Cell>'
    '<Cell><Data ss:Type="String">SEX</Data></Cell>'
    '<Cell><Data ss:Type="String">BONE_IDX</Data></Cell>'
    '<Cell><Data ss:Type="String">WING_ROT_X</Data></Cell>'
    '<Cell><Data ss:Type="String">WING_ROT_Y</Data></Cell>'
    '<Cell><Data ss:Type="String">WING_ROT_Z</Data></Cell>'
    '<Cell><Data ss:Type="String">WING_UP_DOWN</Data></Cell>'
    '<Cell><Data ss:Type="String">WING_FRONT_BACK</Data></Cell>'
    '<Cell><Data ss:Type="String">WING_LEFT_RIGHT</Data></Cell>'
    '</Row>',
  );
  for (var family = 0; family < 4; family++) {
    for (var job = 0; job < 6; job++) {
      for (var sex = 0; sex < 2; sex++) {
        out
          ..write('<Row ss:AutoFitHeight="0">')
          ..write('<Cell><Data ss:Type="Number">$family</Data></Cell>')
          ..write('<Cell><Data ss:Type="Number">$job</Data></Cell>')
          ..write('<Cell><Data ss:Type="Number">$sex</Data></Cell>')
          ..write('<Cell><Data ss:Type="Number">4</Data></Cell>')
          ..write('<Cell><Data ss:Type="Number">${170 + family}</Data></Cell>')
          ..write('<Cell><Data ss:Type="Number">${job * 2}</Data></Cell>')
          ..write('<Cell><Data ss:Type="Number">90</Data></Cell>')
          ..write(
            '<Cell><Data ss:Type="Number">${(sex + 1) / 100}</Data></Cell>',
          )
          ..write(
            '<Cell><Data ss:Type="Number">-${(job + 1) / 10}</Data></Cell>',
          )
          ..write('<Cell><Data ss:Type="Number">${family / 20}</Data></Cell>')
          ..write('</Row>');
      }
    }
  }
  out.write('</Table></Worksheet></Workbook>');
  return Uint8List.fromList(utf8.encode(out.toString()));
}

void main() {
  test('verified ps0032 baseline contains 48 bone-4 profiles', () {
    final rows = WingPositionDocument.verifiedBaseline;
    expect(rows, hasLength(48));
    expect(rows.every((p) => p.boneIndex == 4), isTrue);

    final humanFighterMale = WingPositionDocument.verifiedResolve(0, 0, 0)!;
    expect(humanFighterMale.rotX, 170);
    expect(humanFighterMale.rotZ, 90);
    expect(humanFighterMale.upDown, .05);
    expect(humanFighterMale.frontBack, -.18);

    final nordeinHunterFemale = WingPositionDocument.verifiedResolve(3, 3, 1)!;
    expect(nordeinHunterFemale.rotX, 170);
    expect(nordeinHunterFemale.frontBack, -.19);
  });

  test(
    'canonical identity labels follow the ExcelXml family/job/sex comments',
    () {
      final p = WingPositionDocument.verifiedResolve(3, 3, 1)!;
      expect(p.familyLabel, 'Nordein / DeathEater');
      expect(p.jobLabel, 'Archer / Hunter');
      expect(p.sexLabel, 'Femenino');
      expect(p.identityLabel, contains('Archer / Hunter'));
    },
  );

  test('WingPosition XML parses explicit zero-based identities', () {
    final doc = WingPositionDocument.parse(
      fixture(),
      'excelxml/wingposition.xml',
    );
    expect(doc.profiles, hasLength(48));
    final p = doc.resolve(2, 4, 1)!;
    expect(p.boneIndex, 4);
    expect(p.rotX, 172);
    expect(p.rotY, 8);
    expect(p.rotZ, 90);
    expect(p.upDown, .02);
    expect(p.frontBack, -.5);
    expect(p.leftRight, .1);
    expect(p.boneWritable, isTrue);
  });

  test('WingPosition XML accepts generic name/value column layout', () {
    final out = StringBuffer('<WingPosition>');
    for (var family = 0; family < 4; family++) {
      for (var job = 0; job < 6; job++) {
        for (var sex = 0; sex < 2; sex++) {
          out
            ..write('<Row FAMILY="$family" JOB="$job" SEX="$sex">')
            ..write('<Col name="WING_ROT_X" value="171"/>')
            ..write('<Col name="WING_ROT_Y" value="2"/>')
            ..write('<Col name="WING_ROT_Z" value="91"/>')
            ..write('<Col name="WING_UP_DOWN" value="0.12"/>')
            ..write('<Col name="WING_FRONT_BACK" value="-0.22"/>')
            ..write('<Col name="WING_LEFT_RIGHT" value="0.03"/>')
            ..write('</Row>');
        }
      }
    }
    out.write('</WingPosition>');
    final doc = WingPositionDocument.parse(
      Uint8List.fromList(utf8.encode(out.toString())),
      'excelxml/wingposition.xml',
    );
    expect(doc.resolve(2, 4, 1)?.rotX, 171);
    expect(doc.resolve(2, 4, 1)?.leftRight, .03);
  });

  test('parses real Excel 2003 SpreadsheetML layout with BONE_IDX', () {
    final doc = WingPositionDocument.parse(
      spreadsheetFixture(),
      'excelxml/wingposition.xml',
    );
    expect(doc.profiles, hasLength(48));
    final p = doc.resolve(3, 3, 1)!;
    expect(p.boneIndex, 4);
    expect(p.boneWritable, isTrue);
    expect(p.rotX, 173);
    expect(p.rotY, 6);
    expect(p.rotZ, 90);
    expect(p.upDown, .02);
    expect(p.frontBack, -.4);
    expect(p.leftRight, .15);
  });

  test(
    'SpreadsheetML editing preserves workbook metadata and round-trips bone',
    () {
      final doc = WingPositionDocument.parse(
        spreadsheetFixture(),
        'excelxml/wingposition.xml',
      );
      final original = doc.resolve(0, 0, 0)!;
      doc.update(
        original.copyWith(
          boneIndex: 7,
          rotX: -45.25,
          rotY: 123.5,
          rotZ: 271.75,
          upDown: .333,
          frontBack: -.777,
          leftRight: .222,
        ),
      );
      final encoded = doc.encode();
      final xml = utf8.decode(encoded);
      expect(xml, contains('mso-application'));
      expect(xml, contains('family comment'));
      expect(xml, contains('ss:AutoFitHeight="0"'));

      doc.validateEncoded(encoded);
      final reparsed = WingPositionDocument.parse(
        encoded,
        'excelxml/wingposition.xml',
      );
      final edited = reparsed.resolve(0, 0, 0)!;
      expect(edited.boneIndex, 7);
      expect(edited.rotX, -45.25);
      expect(edited.rotY, 123.5);
      expect(edited.rotZ, 271.75);
      expect(edited.upDown, .333);
      expect(edited.frontBack, -.777);
      expect(edited.leftRight, .222);
    },
  );

  test('WingPosition XML accepts one-based identity columns', () {
    final doc = WingPositionDocument.parse(
      fixture(oneBased: true),
      'excelxml/wingposition.xml',
    );
    expect(doc.resolve(0, 0, 0), isNotNull);
    expect(doc.resolve(3, 5, 1), isNotNull);
  });

  test('WingPosition XML falls back to canonical 4x6x2 row order', () {
    final doc = WingPositionDocument.parse(
      fixture(includeIdentity: false),
      'excelxml/wingposition.xml',
    );
    expect(doc.resolve(0, 0, 0)?.rotX, 170);
    expect(doc.resolve(3, 5, 1)?.rotX, 173);
    expect(doc.resolve(3, 5, 1)?.boneIndex, 4);
    expect(doc.resolve(3, 5, 1)?.boneWritable, isFalse);
  });

  test('editing six game fields round-trips without losing profiles', () {
    final doc = WingPositionDocument.parse(
      fixture(),
      'excelxml/wingposition.xml',
    );
    final original = doc.resolve(1, 2, 1)!;
    doc.update(
      original.copyWith(
        rotX: -123.5,
        rotY: 222.25,
        rotZ: 359.75,
        upDown: .321,
        frontBack: -.456,
        leftRight: .789,
      ),
    );

    final encoded = doc.encode();
    doc.validateEncoded(encoded);
    final reparsed = WingPositionDocument.parse(
      encoded,
      'excelxml/wingposition.xml',
    );
    final edited = reparsed.resolve(1, 2, 1)!;
    expect(edited.rotX, -123.5);
    expect(edited.rotY, 222.25);
    expect(edited.rotZ, 359.75);
    expect(edited.upDown, .321);
    expect(edited.frontBack, -.456);
    expect(edited.leftRight, .789);
    expect(reparsed.profiles, hasLength(48));
  });

  test('invalid or incomplete files fail closed', () {
    final short = Uint8List.fromList(
      utf8.encode(
        '<WingPosition><Row><WING_ROT_X>1</WING_ROT_X></Row></WingPosition>',
      ),
    );
    expect(
      () => WingPositionDocument.parse(short, 'wingposition.xml'),
      throwsA(isA<FormatException>()),
    );
  });
}
