import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';

class ExcelXmlColumn {
  final int index;
  final String label;
  const ExcelXmlColumn(this.index, this.label);
}

class ExcelXmlRow {
  final int sourceRow;
  final Map<int, XmlElement> cells;
  const ExcelXmlRow(this.sourceRow, this.cells);

  String value(int column) => cells[column]?.innerText.trim() ?? '';
  bool hasCell(int column) => cells.containsKey(column);

  String? cellType(int column) => cells[column]?.attributes
      .where((attribute) => attribute.name.local.toLowerCase() == 'type')
      .map((attribute) => attribute.value.trim())
      .where((value) => value.isNotEmpty)
      .firstOrNull;
}

class ExcelXmlSheet {
  final String name;
  final int headerRow;
  final List<ExcelXmlColumn> columns;
  final List<ExcelXmlRow> rows;

  const ExcelXmlSheet({
    required this.name,
    required this.headerRow,
    required this.columns,
    required this.rows,
  });
}

/// SpreadsheetML editor for DATA/ExcelXml.
///
/// The parsed XML tree remains authoritative, so styles, comments, processing
/// instructions and worksheet metadata are preserved. Only an existing <Data>
/// node selected by the user is changed.
class ExcelXmlDocument {
  static const maxBytes = 32 * 1024 * 1024;

  final String path;
  final XmlDocument _document;
  final List<ExcelXmlSheet> sheets;
  final int worksheetCount;
  final int tableCount;

  ExcelXmlDocument._(
    this.path,
    this._document,
    this.sheets,
    this.worksheetCount,
    this.tableCount,
  );

  bool get tabular => sheets.isNotEmpty;

  static ExcelXmlDocument parse(Uint8List bytes, String path) {
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw FormatException('$path: XML vacío o mayor de 32 MiB.');
    }
    var raw = bytes;
    if (raw.length >= 3 && raw[0] == 0xef && raw[1] == 0xbb && raw[2] == 0xbf) {
      raw = Uint8List.sublistView(raw, 3);
    }
    final source = utf8.decode(raw, allowMalformed: false);
    final document = XmlDocument.parse(source);
    final worksheets = document.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local.toLowerCase() == 'worksheet')
        .toList(growable: false);
    final tables = document.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local.toLowerCase() == 'table')
        .toList(growable: false);
    final out = <ExcelXmlSheet>[];

    for (var w = 0; w < worksheets.length; w++) {
      final worksheet = worksheets[w];
      final name =
          worksheet.attributes
              .where((a) => a.name.local.toLowerCase() == 'name')
              .map((a) => a.value.trim())
              .where((v) => v.isNotEmpty)
              .firstOrNull ??
          'Hoja ${w + 1}';
      final table = worksheet.descendants
          .whereType<XmlElement>()
          .where((e) => e.name.local.toLowerCase() == 'table')
          .firstOrNull;
      if (table == null) continue;
      final rows = table.childElements
          .where((e) => e.name.local.toLowerCase() == 'row')
          .toList(growable: false);
      if (rows.isEmpty) continue;

      final parsedRows = <Map<int, XmlElement>>[
        for (final row in rows) _dataCells(row),
      ];
      final header = _headerIndex(parsedRows, path: path, sheetName: name);
      if (header < 0) continue;
      final headerCells = parsedRows[header];
      final maxColumn = parsedRows.fold<int>(
        0,
        (max, row) => row.keys.fold<int>(max, (m, col) => col > m ? col : m),
      );
      if (maxColumn <= 0 || maxColumn > 512) {
        throw FormatException('$path: tabla con columnas fuera de límite.');
      }

      final columns = <ExcelXmlColumn>[
        for (var column = 1; column <= maxColumn; column++)
          ExcelXmlColumn(
            column,
            _columnLabel(headerCells[column]?.innerText.trim(), column),
          ),
      ];
      final dataRows = <ExcelXmlRow>[];
      for (var i = header + 1; i < rows.length; i++) {
        final cells = parsedRows[i];
        if (cells.values.every((e) => e.innerText.trim().isEmpty)) continue;
        dataRows.add(ExcelXmlRow(i + 1, cells));
      }
      if (dataRows.length > 200000) {
        throw FormatException('$path: demasiadas filas SpreadsheetML.');
      }
      out.add(
        ExcelXmlSheet(
          name: name,
          headerRow: header + 1,
          columns: columns,
          rows: dataRows,
        ),
      );
    }

    return ExcelXmlDocument._(
      path,
      document,
      List.unmodifiable(out),
      worksheets.length,
      tables.length,
    );
  }

  void setCell(int sheetIndex, int rowIndex, int columnIndex, String value) {
    if (sheetIndex < 0 || sheetIndex >= sheets.length) {
      throw const FormatException('Hoja ExcelXml fuera de rango.');
    }
    final sheet = sheets[sheetIndex];
    if (rowIndex < 0 || rowIndex >= sheet.rows.length) {
      throw const FormatException('Fila ExcelXml fuera de rango.');
    }
    if (!sheet.columns.any((column) => column.index == columnIndex)) {
      throw const FormatException('Columna ExcelXml fuera de rango.');
    }
    final data = sheet.rows[rowIndex].cells[columnIndex];
    if (data == null) {
      throw FormatException(
        '$path: la celda C$columnIndex no existe físicamente; '
        'Studio no inventa celdas SpreadsheetML.',
      );
    }
    if (value.contains('\u0000')) {
      throw const FormatException('ExcelXml no admite NUL en una celda.');
    }
    _validateCellValue(data, value);
    data.innerText = value;
  }

  Uint8List encode() =>
      Uint8List.fromList(utf8.encode(_document.toXmlString(pretty: false)));

  void validateEncoded(Uint8List bytes) {
    final parsed = ExcelXmlDocument.parse(bytes, path);
    if (parsed.worksheetCount != worksheetCount ||
        parsed.tableCount != tableCount ||
        parsed.sheets.length != sheets.length) {
      throw FormatException(
        '$path: la serialización alteró la estructura XML.',
      );
    }
    for (var i = 0; i < sheets.length; i++) {
      final expected = sheets[i];
      final actual = parsed.sheets[i];
      if (actual.columns.length != expected.columns.length ||
          actual.rows.length != expected.rows.length) {
        throw FormatException(
          '$path: la serialización alteró filas/columnas de ${expected.name}.',
        );
      }
    }
  }

  static void _validateCellValue(XmlElement data, String value) {
    final type = data.attributes
        .where((attribute) => attribute.name.local.toLowerCase() == 'type')
        .map((attribute) => attribute.value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .firstOrNull;
    if (type == null || type == 'string') return;

    final source = value.trim();
    switch (type) {
      case 'number':
        final number = double.tryParse(source);
        if (number == null || !number.isFinite) {
          throw FormatException(
            'La celda SpreadsheetML es Number y requiere un número finito: '
            '$value',
          );
        }
        return;
      case 'boolean':
        if (source != '0' && source != '1') {
          throw FormatException(
            'La celda SpreadsheetML es Boolean y requiere 0 o 1: $value',
          );
        }
        return;
      case 'datetime':
        if (DateTime.tryParse(source) == null) {
          throw FormatException(
            'La celda SpreadsheetML es DateTime y el valor no es válido: '
            '$value',
          );
        }
        return;
      default:
        // Error and custom/legacy cell types are preserved without inventing
        // semantics that are not present in the source workbook.
        return;
    }
  }

  static Map<int, XmlElement> _dataCells(XmlElement row) {
    final cells = <int, XmlElement>{};
    var column = 1;
    for (final cell in row.childElements.where(
      (e) => e.name.local.toLowerCase() == 'cell',
    )) {
      final index = cell.attributes
          .where((a) => a.name.local.toLowerCase() == 'index')
          .map((a) => int.tryParse(a.value))
          .whereType<int>()
          .firstOrNull;
      if (index != null && index > 0) column = index;
      final data = cell.childElements
          .where((e) => e.name.local.toLowerCase() == 'data')
          .firstOrNull;
      if (data != null) cells[column] = data;
      column++;
    }
    return cells;
  }

  static int _headerIndex(
    List<Map<int, XmlElement>> rows, {
    required String path,
    required String sheetName,
  }) {
    final file = path.replaceAll('\\', '/').split('/').last.toLowerCase();

    // WingExpItem carries a human-facing title in row 1 and the actual machine
    // column name ItemID in row 2. Prefer the explicit field name so semantic
    // validation and editing target the real data column.
    if (file == 'wingexpitem.xml') {
      final limit = rows.length < 8 ? rows.length : 8;
      for (var i = 0; i < limit; i++) {
        final values = rows[i].values
            .map((element) => element.innerText.trim().toLowerCase())
            .toList(growable: false);
        if (values.contains('itemid')) return i;
      }
    }

    // The sheet name is intentionally accepted for future source-confirmed
    // multi-row headers. Unknown workbooks still use the generic heuristic.
    final _ = sheetName;
    var bestIndex = -1;
    var bestScore = -1;
    final limit = rows.length < 32 ? rows.length : 32;
    for (var i = 0; i < limit; i++) {
      final values = rows[i].values
          .map((e) => e.innerText.trim())
          .where((v) => v.isNotEmpty)
          .toList(growable: false);
      if (values.isEmpty) continue;
      final identifiers = values
          .where(
            (v) =>
                RegExp(r'[A-Za-z_]').hasMatch(v) &&
                !RegExp(r'^-?\d+(?:[.,]\d+)?$').hasMatch(v),
          )
          .length;
      final unique = values.toSet().length;
      final score = identifiers * 5 + unique * 2 + values.length;
      if (identifiers > 0 && score > bestScore) {
        bestIndex = i;
        bestScore = score;
      }
    }
    return bestIndex;
  }

  static String _columnLabel(String? value, int index) {
    final label = value?.trim() ?? '';
    return label.isEmpty ? 'C$index' : label;
  }
}

String excelXmlPurpose(String path) {
  final file = path.replaceAll('\\', '/').split('/').last.toLowerCase();
  if (file == 'wingposition.xml') return 'Alas · posición/rotación/hueso';
  if (file == 'wingdecompose.xml') return 'Alas · descomposición/grade';
  if (file == 'wingexpitem.xml') return 'Alas · objetos de experiencia';
  if (file == 'wingswap.xml') return 'Alas · intercambio';
  if (file == 'ymwatershaderparams.xml') return 'Mundo · shader/agua por mapa';
  if (file == 'fontstyleset.xml') return 'UI · fuentes/colores/estilos';
  if (file == 'gmnoticeinfo.xml') return 'UI · avisos GM';
  if (file == 'mainquest.xml') return 'Quests · configuración principal';
  if (file == 'startmapchange.xml' ||
      file == 'mapcountry.xml' ||
      file == 'maplimitlv.xml') {
    return 'Mundo · mapas/reglas';
  }
  if (file.contains('monster') || file.startsWith('mondeath')) {
    return 'Monstruos · drop/respawn/eventos';
  }
  if (file.startsWith('item') ||
      file.contains('renownshop') ||
      file.contains('guildgemitem')) {
    return 'Objetos · creación/opciones/uso/recompensas';
  }
  if (file.contains('event') || file.contains('notice')) {
    return 'Eventos · calendario/mensajes';
  }
  if (file.contains('marriage')) return 'Sistema · matrimonio/recompensas';
  if (file.contains('npc')) return 'NPC · disponibilidad';
  if (file.contains('skill')) return 'Skills · reglas/listas';
  if (file.contains('pet')) return 'Mascotas · tamaño/efectos';
  return 'ExcelXml · tabla de DATA';
}

/// Exact filename literals found in the audited ps0032 game.exe
/// (SHA-256 509c4a8f...). Absence from this set is not proof that a table is
/// unused: it may be server-side or resolved without a literal filename.
const Set<String> ps0032ClientExcelXmlFiles = {
  'chaoticsquaretype.xml',
  'fontstyleset.xml',
  'functionalpetsize.xml',
  'gmnoticeinfo.xml',
  'healskilllist.xml',
  'itemaddoptiondata.xml',
  'mainquest.xml',
  'visiblepartybufskill.xml',
  'wingposition.xml',
  'ymeventinfo.xml',
  'ymwatershaderparams.xml',
};

bool excelXmlHasPs0032ClientLiteral(String path) {
  final file = path.replaceAll('\\', '/').split('/').last.toLowerCase();
  return ps0032ClientExcelXmlFiles.contains(file);
}

String excelXmlClientEvidence(String path) =>
    excelXmlHasPs0032ClientLiteral(path)
        ? 'ps0032: nombre/ruta literal confirmado en game.exe'
        : 'ps0032: sin literal de nombre; puede ser server-side o resolución dinámica';
