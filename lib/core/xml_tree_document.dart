import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';

class XmlTreeNode {
  final int index;
  final int depth;
  final String path;
  final XmlElement element;

  const XmlTreeNode({
    required this.index,
    required this.depth,
    required this.path,
    required this.element,
  });

  String get name => element.name.local;
  int get childElements => element.childElements.length;
  bool get leaf => childElements == 0;

  Map<String, String> get attributes => {
    for (final attribute in element.attributes)
      attribute.name.qualified: attribute.value,
  };

  String get text => leaf ? element.innerText : '';
}

/// Structured editor for the non-SpreadsheetML XML files that also live in
/// DATA/ExcelXml (events, map limits, move towns, monster respawn, etc.).
///
/// Only existing attributes and leaf text can be modified. Node names,
/// hierarchy, attribute names and element counts are immutable, which lets
/// Studio offer a professional form editor without inventing a schema.
class XmlTreeDocument {
  static const int maxBytes = 32 * 1024 * 1024;
  static const int maxElements = 200000;
  static const int maxDepth = 64;
  static const int maxAttributesPerElement = 256;

  final String path;
  final XmlDocument _document;
  final List<XmlTreeNode> nodes;
  final List<_XmlShape> _shape;

  XmlTreeDocument._(this.path, this._document, this.nodes, this._shape);

  String get rootName => _document.rootElement.name.local;

  static XmlTreeDocument parse(Uint8List bytes, String path) {
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw FormatException('$path: XML vacío o mayor de 32 MiB.');
    }
    var raw = bytes;
    if (raw.length >= 3 && raw[0] == 0xef && raw[1] == 0xbb && raw[2] == 0xbf) {
      raw = Uint8List.sublistView(raw, 3);
    }
    final source = utf8.decode(raw, allowMalformed: false);
    final document = XmlDocument.parse(source);
    final out = <XmlTreeNode>[];
    final shape = <_XmlShape>[];

    void walk(XmlElement element, int depth, String parentPath, int ordinal) {
      if (depth > maxDepth) {
        throw FormatException('$path: XML supera profundidad $maxDepth.');
      }
      if (element.attributes.length > maxAttributesPerElement) {
        throw FormatException(
          '$path: ${element.name.local} supera '
          '$maxAttributesPerElement atributos.',
        );
      }
      if (out.length >= maxElements) {
        throw FormatException('$path: XML supera $maxElements elementos.');
      }

      final nodePath =
          '$parentPath/${element.name.local}[${ordinal.toString()}]';
      final index = out.length;
      out.add(
        XmlTreeNode(
          index: index,
          depth: depth,
          path: nodePath,
          element: element,
        ),
      );
      shape.add(
        _XmlShape(
          name: element.name.qualified,
          attributeNames: [
            for (final attribute in element.attributes) attribute.name.qualified,
          ]..sort(),
          childCount: element.childElements.length,
        ),
      );

      final counts = <String, int>{};
      for (final child in element.childElements) {
        final name = child.name.local;
        final childOrdinal = counts.update(
          name,
          (value) => value + 1,
          ifAbsent: () => 0,
        );
        walk(child, depth + 1, nodePath, childOrdinal);
      }
    }

    walk(document.rootElement, 0, '', 0);
    return XmlTreeDocument._(
      path,
      document,
      List.unmodifiable(out),
      List.unmodifiable(shape),
    );
  }

  void setAttribute(int nodeIndex, String qualifiedName, String value) {
    final node = _node(nodeIndex);
    final attribute = node.element.attributes
        .where((item) => item.name.qualified == qualifiedName)
        .firstOrNull;
    if (attribute == null) {
      throw FormatException(
        '$path: ${node.path} no contiene el atributo $qualifiedName.',
      );
    }
    _validateValue(value);
    attribute.value = value;
  }

  void setLeafText(int nodeIndex, String value) {
    final node = _node(nodeIndex);
    if (!node.leaf) {
      throw FormatException(
        '$path: ${node.path} contiene nodos hijos; '
        'Studio no reemplaza su estructura con texto.',
      );
    }
    _validateValue(value);
    node.element.innerText = value;
  }

  Uint8List encode() =>
      Uint8List.fromList(utf8.encode(_document.toXmlString(pretty: false)));

  void validateEncoded(Uint8List bytes) {
    final parsed = XmlTreeDocument.parse(bytes, path);
    if (parsed.rootName != rootName || parsed.nodes.length != nodes.length) {
      throw FormatException('$path: la serialización alteró la estructura XML.');
    }
    for (var i = 0; i < _shape.length; i++) {
      final expected = _shape[i];
      final actual = parsed._shape[i];
      if (expected.name != actual.name ||
          expected.childCount != actual.childCount ||
          !_sameStrings(expected.attributeNames, actual.attributeNames)) {
        throw FormatException(
          '$path: la serialización alteró el nodo ${nodes[i].path}.',
        );
      }
    }
  }

  XmlTreeNode _node(int index) {
    if (index < 0 || index >= nodes.length) {
      throw const FormatException('Nodo XML fuera de rango.');
    }
    return nodes[index];
  }

  static void _validateValue(String value) {
    if (value.contains('\u0000')) {
      throw const FormatException('XML no admite NUL.');
    }
  }

  static bool _sameStrings(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class _XmlShape {
  final String name;
  final List<String> attributeNames;
  final int childCount;

  const _XmlShape({
    required this.name,
    required this.attributeNames,
    required this.childCount,
  });
}
