import 'excelxml_document.dart';

enum ExcelXmlIssueSeverity { warning, error }

class ExcelXmlSemanticIssue {
  final ExcelXmlIssueSeverity severity;
  final int sheetIndex;
  final int? rowIndex;
  final int? columnIndex;
  final String code;
  final String message;

  const ExcelXmlSemanticIssue({
    required this.severity,
    required this.sheetIndex,
    required this.code,
    required this.message,
    this.rowIndex,
    this.columnIndex,
  });

  Map<String, Object?> toJson(ExcelXmlDocument document) => {
    'severity': severity.name,
    'code': code,
    'message': message,
    'sheet': sheetIndex >= 0 && sheetIndex < document.sheets.length
        ? document.sheets[sheetIndex].name
        : sheetIndex,
    if (rowIndex != null) 'rowIndex': rowIndex,
    if (rowIndex != null &&
        sheetIndex >= 0 &&
        sheetIndex < document.sheets.length &&
        rowIndex! >= 0 &&
        rowIndex! < document.sheets[sheetIndex].rows.length)
      'sourceRow': document.sheets[sheetIndex].rows[rowIndex!].sourceRow,
    if (columnIndex != null) 'columnIndex': columnIndex,
  };
}

/// Semantic checks are intentionally restricted to fields whose meaning is
/// explicit in the supplied DATA/ExcelXml source. Unknown tables are not
/// guessed: SpreadsheetML type validation remains the only gate there.
List<ExcelXmlSemanticIssue> auditExcelXmlSemantics(ExcelXmlDocument document) {
  final file = document.path
      .replaceAll('\\', '/')
      .split('/')
      .last
      .toLowerCase();
  if (document.sheets.isEmpty) return const [];

  return switch (file) {
    'wingdecompose.xml' => _wingDecompose(document),
    'wingexpitem.xml' => _wingExpItem(document),
    'wingswap.xml' => _wingSwap(document),
    'ymwatershaderparams.xml' => _waterShader(document),
    'mapcountry.xml' => _mapCountry(document),
    'startmapchange.xml' => _startMapChange(document),
    _ => const <ExcelXmlSemanticIssue>[],
  };
}

Map<String, int> _columns(ExcelXmlSheet sheet) => {
  for (final column in sheet.columns)
    column.label.trim().toLowerCase(): column.index,
};

int? _intValue(ExcelXmlRow row, int? column) {
  if (column == null) return null;
  final raw = row.value(column).trim();
  if (raw.isEmpty) return null;
  final numeric = double.tryParse(raw);
  if (numeric == null ||
      !numeric.isFinite ||
      numeric != numeric.roundToDouble()) {
    return null;
  }
  return numeric.toInt();
}

double? _numberValue(ExcelXmlRow row, int? column) {
  if (column == null) return null;
  final raw = row.value(column).trim();
  if (raw.isEmpty) return null;
  final value = double.tryParse(raw);
  return value != null && value.isFinite ? value : null;
}

void _integerError(
  List<ExcelXmlSemanticIssue> out,
  ExcelXmlSheet sheet,
  int sheetIndex,
  int rowIndex,
  int? column,
  String label, {
  int? min,
  int? max,
  bool allowZero = true,
}) {
  if (column == null) return;
  final row = sheet.rows[rowIndex];
  final raw = row.value(column).trim();
  final value = _intValue(row, column);
  if (value == null) {
    out.add(
      ExcelXmlSemanticIssue(
        severity: ExcelXmlIssueSeverity.error,
        sheetIndex: sheetIndex,
        rowIndex: rowIndex,
        columnIndex: column,
        code: 'integer',
        message: '$label requiere un entero; valor actual: "$raw".',
      ),
    );
    return;
  }
  if ((!allowZero && value == 0) ||
      (min != null && value < min) ||
      (max != null && value > max)) {
    final range = [
      if (min != null) '>= $min',
      if (max != null) '<= $max',
      if (!allowZero) 'distinto de 0',
    ].join(' y ');
    out.add(
      ExcelXmlSemanticIssue(
        severity: ExcelXmlIssueSeverity.error,
        sheetIndex: sheetIndex,
        rowIndex: rowIndex,
        columnIndex: column,
        code: 'integer-range',
        message: '$label debe ser $range; valor actual: $value.',
      ),
    );
  }
}

void _numberRange(
  List<ExcelXmlSemanticIssue> out,
  ExcelXmlSheet sheet,
  int sheetIndex,
  int rowIndex,
  int? column,
  String label,
  double min,
  double max, {
  ExcelXmlIssueSeverity severity = ExcelXmlIssueSeverity.error,
}) {
  if (column == null) return;
  final row = sheet.rows[rowIndex];
  final raw = row.value(column).trim();
  final value = _numberValue(row, column);
  if (value == null || value < min || value > max) {
    out.add(
      ExcelXmlSemanticIssue(
        severity: severity,
        sheetIndex: sheetIndex,
        rowIndex: rowIndex,
        columnIndex: column,
        code: 'number-range',
        message: '$label debe estar entre $min y $max; valor actual: "$raw".',
      ),
    );
  }
}

void _duplicateKeys(
  List<ExcelXmlSemanticIssue> out,
  ExcelXmlSheet sheet,
  int sheetIndex,
  Iterable<int> columns, {
  required String label,
}) {
  final seen = <String, int>{};
  for (var rowIndex = 0; rowIndex < sheet.rows.length; rowIndex++) {
    final row = sheet.rows[rowIndex];
    final values = [for (final column in columns) row.value(column).trim()];
    if (values.any((value) => value.isEmpty)) continue;
    final key = values.join('\u001f');
    final first = seen[key];
    if (first == null) {
      seen[key] = rowIndex;
      continue;
    }
    final column = columns.firstOrNull;
    out.add(
      ExcelXmlSemanticIssue(
        severity: ExcelXmlIssueSeverity.error,
        sheetIndex: sheetIndex,
        rowIndex: rowIndex,
        columnIndex: column,
        code: 'duplicate-key',
        message:
            '$label duplicado; ya existe en la fila '
            '${sheet.rows[first].sourceRow}.',
      ),
    );
  }
}

List<ExcelXmlSemanticIssue> _wingDecompose(ExcelXmlDocument document) {
  final out = <ExcelXmlSemanticIssue>[];
  for (var s = 0; s < document.sheets.length; s++) {
    final sheet = document.sheets[s];
    final c = _columns(sheet);
    final wing = c['wingid'];
    final grade = c['grade'];
    final oldItem = c['oldwingitem'];
    final maxLevel = c['maxlevel'];
    if ([wing, grade, oldItem, maxLevel].any((value) => value == null))
      continue;
    for (var r = 0; r < sheet.rows.length; r++) {
      _integerError(out, sheet, s, r, wing, 'WingID', min: 0);
      _integerError(out, sheet, s, r, grade, 'Grade', min: 0);
      _integerError(
        out,
        sheet,
        s,
        r,
        oldItem,
        'OldWingItem',
        min: 1,
        allowZero: false,
      );
      _integerError(out, sheet, s, r, maxLevel, 'MaxLevel', min: 0);
    }
    _duplicateKeys(out, sheet, s, [
      wing!,
      grade!,
    ], label: 'La combinación WingID + Grade');
  }
  return out;
}

List<ExcelXmlSemanticIssue> _wingExpItem(ExcelXmlDocument document) {
  final out = <ExcelXmlSemanticIssue>[];
  for (var s = 0; s < document.sheets.length; s++) {
    final sheet = document.sheets[s];
    final item = _columns(sheet)['itemid'];
    if (item == null) continue;
    for (var r = 0; r < sheet.rows.length; r++) {
      _integerError(out, sheet, s, r, item, 'ItemID', min: 1, allowZero: false);
    }
    _duplicateKeys(out, sheet, s, [item], label: 'ItemID');
  }
  return out;
}

List<ExcelXmlSemanticIssue> _wingSwap(ExcelXmlDocument document) {
  final out = <ExcelXmlSemanticIssue>[];
  for (var s = 0; s < document.sheets.length; s++) {
    final sheet = document.sheets[s];
    final c = _columns(sheet);
    final oldItem = c['oldwingitem'];
    if (oldItem == null) continue;
    for (var r = 0; r < sheet.rows.length; r++) {
      _integerError(
        out,
        sheet,
        s,
        r,
        oldItem,
        'OldWingItem',
        min: 1,
        allowZero: false,
      );
      for (var slot = 1; slot <= 3; slot++) {
        final itemColumn = c['exchangeitem$slot'];
        final countColumn = c['count$slot'];
        if (itemColumn == null || countColumn == null) continue;
        _integerError(
          out,
          sheet,
          s,
          r,
          itemColumn,
          'ExchangeItem$slot',
          min: 0,
        );
        _integerError(out, sheet, s, r, countColumn, 'Count$slot', min: 0);
        final item = _intValue(sheet.rows[r], itemColumn);
        final count = _intValue(sheet.rows[r], countColumn);
        if (item == null || count == null) continue;
        if ((item == 0) != (count == 0)) {
          out.add(
            ExcelXmlSemanticIssue(
              severity: ExcelXmlIssueSeverity.error,
              sheetIndex: s,
              rowIndex: r,
              columnIndex: item == 0 ? countColumn : itemColumn,
              code: 'exchange-pair',
              message:
                  'ExchangeItem$slot y Count$slot deben estar ambos en 0 '
                  'o ambos contener una recompensa.',
            ),
          );
        }
      }
    }
    _duplicateKeys(out, sheet, s, [oldItem], label: 'OldWingItem');
  }
  return out;
}

List<ExcelXmlSemanticIssue> _waterShader(ExcelXmlDocument document) {
  final out = <ExcelXmlSemanticIssue>[];
  for (var s = 0; s < document.sheets.length; s++) {
    final sheet = document.sheets[s];
    final c = _columns(sheet);
    final mapId = c['mapid'];
    if (mapId == null) continue;
    for (var r = 0; r < sheet.rows.length; r++) {
      _integerError(out, sheet, s, r, mapId, 'MapID', min: 0);
      _integerError(out, sheet, s, r, c['useflag'], 'UseFlag', min: 0, max: 1);
      for (final name in const [
        'shallowcolorr',
        'shallowcolorg',
        'shallowcolorb',
        'shallowcolora',
      ]) {
        _numberRange(out, sheet, s, r, c[name], name, 0, 255);
      }
      // Deep/underwater fields are colors too, but their source headers do not
      // state an explicit numeric range. Surface suspicious values as warnings
      // rather than blocking a DATA value we cannot prove invalid.
      for (final name in const [
        'deepcolorr',
        'deepcolorg',
        'deepcolorb',
        'deepcolora',
        'underwatercolorr',
        'underwatercolorg',
        'underwatercolorb',
      ]) {
        _numberRange(
          out,
          sheet,
          s,
          r,
          c[name],
          name,
          0,
          255,
          severity: ExcelXmlIssueSeverity.warning,
        );
      }
      for (final name in const [
        'wavescale',
        'wateramount',
        'reflectionamount',
        'reflectionblur',
        'fresnelbias',
        'specularpower',
      ]) {
        _numberRange(out, sheet, s, r, c[name], name, 0, 1);
      }
      _numberRange(
        out,
        sheet,
        s,
        r,
        c['hdrmultiplier'],
        'HdrMultiplier',
        0,
        10,
      );
    }
    _duplicateKeys(out, sheet, s, [mapId], label: 'MapID');
  }
  return out;
}

List<ExcelXmlSemanticIssue> _mapCountry(ExcelXmlDocument document) {
  final out = <ExcelXmlSemanticIssue>[];
  for (var s = 0; s < document.sheets.length; s++) {
    final sheet = document.sheets[s];
    final c = _columns(sheet);
    final light = c['light_map'];
    final fury = c['fury_map'];
    if (light == null && fury == null) continue;
    for (var r = 0; r < sheet.rows.length; r++) {
      _integerError(out, sheet, s, r, light, 'LIGHT_MAP', min: 0);
      _integerError(out, sheet, s, r, fury, 'FURY_MAP', min: 0);
    }
  }
  return out;
}

List<ExcelXmlSemanticIssue> _startMapChange(ExcelXmlDocument document) {
  final out = <ExcelXmlSemanticIssue>[];
  for (var s = 0; s < document.sheets.length; s++) {
    final sheet = document.sheets[s];
    final map = _columns(sheet)['map'];
    if (map == null) continue;
    for (var r = 0; r < sheet.rows.length; r++) {
      _integerError(out, sheet, s, r, map, 'MAP', min: 0);
    }
    _duplicateKeys(out, sheet, s, [map], label: 'MAP');
  }
  return out;
}
