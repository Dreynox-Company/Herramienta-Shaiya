import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/xml_tree_document.dart';

Uint8List fixture() => Uint8List.fromList(
  utf8.encode(
    '<?xml version="1.0"?>'
    '<!--keep-comment-->'
    '<CHAR_WAR_MODE>'
    '<MODE_CHANGE_TIME SEC="30"/>'
    '<NOT_REMOVE_BUF_LIST>'
    '<SKILL ID="197"/>'
    '<SKILL ID="198"/>'
    '</NOT_REMOVE_BUF_LIST>'
    '<LABEL LANG="es">Texto original</LABEL>'
    '</CHAR_WAR_MODE>',
  ),
);

void main() {
  test('custom XML tree edits existing values without changing structure', () {
    final doc = XmlTreeDocument.parse(
      fixture(),
      'excelxml/CharWarMode.xml',
    );
    expect(doc.rootName, 'CHAR_WAR_MODE');
    expect(doc.nodes.map((node) => node.name), [
      'CHAR_WAR_MODE',
      'MODE_CHANGE_TIME',
      'NOT_REMOVE_BUF_LIST',
      'SKILL',
      'SKILL',
      'LABEL',
    ]);

    final mode = doc.nodes.firstWhere((node) => node.name == 'MODE_CHANGE_TIME');
    final label = doc.nodes.firstWhere((node) => node.name == 'LABEL');
    doc.setAttribute(mode.index, 'SEC', '45');
    doc.setLeafText(label.index, 'Texto editado');

    final encoded = doc.encode();
    doc.validateEncoded(encoded);
    final text = utf8.decode(encoded);
    expect(text, contains('keep-comment'));
    expect(text, contains('SEC="45"'));
    expect(text, contains('Texto editado'));

    final reparsed = XmlTreeDocument.parse(
      encoded,
      'excelxml/CharWarMode.xml',
    );
    expect(
      reparsed.nodes
          .firstWhere((node) => node.name == 'MODE_CHANGE_TIME')
          .attributes['SEC'],
      '45',
    );
  });

  test('tree editor refuses attributes and text that would invent schema', () {
    final doc = XmlTreeDocument.parse(fixture(), 'excelxml/test.xml');
    final root = doc.nodes.first;
    final mode = doc.nodes[1];

    expect(
      () => doc.setAttribute(mode.index, 'MISSING', '1'),
      throwsFormatException,
    );
    expect(
      () => doc.setLeafText(root.index, 'flatten children'),
      throwsFormatException,
    );
  });

  test('round-trip validator rejects changed hierarchy', () {
    final doc = XmlTreeDocument.parse(fixture(), 'excelxml/test.xml');
    final changed = Uint8List.fromList(
      utf8.encode(
        '<CHAR_WAR_MODE>'
        '<MODE_CHANGE_TIME SEC="30"/>'
        '<EXTRA/>'
        '<NOT_REMOVE_BUF_LIST>'
        '<SKILL ID="197"/>'
        '<SKILL ID="198"/>'
        '</NOT_REMOVE_BUF_LIST>'
        '<LABEL LANG="es">Texto original</LABEL>'
        '</CHAR_WAR_MODE>',
      ),
    );

    expect(() => doc.validateEncoded(changed), throwsFormatException);
  });

  test('unsafe NUL values are rejected', () {
    final doc = XmlTreeDocument.parse(fixture(), 'excelxml/test.xml');
    expect(
      () => doc.setAttribute(1, 'SEC', '3\u0000'),
      throwsFormatException,
    );
  });
}
