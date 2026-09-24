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
    'wingposition.xml' => _wingPosition(document),
    'wingdecompose.xml' => _wingDecompose(document),
    'wingexpitem.xml' => _wingExpItem(document),
    'wingswap.xml' => _wingSwap(document),
    'battlefield3prize.xml' => _battleFieldPrize(document),
    'guildgemitem.xml' => _guildGemItem(document),
    'infinitedungeonrebirth.xml' => _infiniteDungeonRebirth(document),
    'renownshop.xml' => _renownShop(document),
    'functionalpetsize.xml' => _functionalPetSize(document),
    'healskilllist.xml' => _healSkillList(document),
    'itemaddoptiondata.xml' => _itemAddOption(document),
    'fontstyleset.xml' => _fontStyleSet(document),
    'gmnoticeinfo.xml' => _gmNotice(document),
    'ymeventinfo.xml' => _ymEventInfo(document),
    'visiblepartybufskill.xml' => _visiblePartyBuff(document),
    'npcdisablesystem.xml' => _npcDisable(document),
    'timenoticesystem.xml' => _timeNotice(document),
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

void _numberRangeIfPresent(
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
  final raw = sheet.rows[rowIndex].value(column).trim();
  if (raw.isEmpty) return;
  _numberRange(
    out,
    sheet,
    sheetIndex,
    rowIndex,
    column,
    label,
    min,
    max,
    severity: severity,
  );
}

void _finiteNumberError(
  List<ExcelXmlSemanticIssue> out,
  ExcelXmlSheet sheet,
  int sheetIndex,
  int rowIndex,
  int? column,
  String label,
) {
  if (column == null) return;
  final raw = sheet.rows[rowIndex].value(column).trim();
  final value = double.tryParse(raw);
  if (value == null || !value.isFinite) {
    out.add(
      ExcelXmlSemanticIssue(
        severity: ExcelXmlIssueSeverity.error,
        sheetIndex: sheetIndex,
        rowIndex: rowIndex,
        columnIndex: column,
        code: 'number',
        message: '$label requiere un número finito; valor actual: "$raw".',
      ),
    );
  }
}

void _itemCountPair(
  List<ExcelXmlSemanticIssue> out,
  ExcelXmlSheet sheet,
  int sheetIndex,
  int rowIndex,
  int? itemColumn,
  int? countColumn,
  String label,
) {
  if (itemColumn == null || countColumn == null) return;
  final itemRaw = sheet.rows[rowIndex].value(itemColumn).trim();
  final countRaw = sheet.rows[rowIndex].value(countColumn).trim();
  if (itemRaw.isEmpty && countRaw.isEmpty) return;
  final item = _intValue(sheet.rows[rowIndex], itemColumn);
  final count = _intValue(sheet.rows[rowIndex], countColumn);
  if (item == null || count == null) {
    out.add(
      ExcelXmlSemanticIssue(
        severity: ExcelXmlIssueSeverity.error,
        sheetIndex: sheetIndex,
        rowIndex: rowIndex,
        columnIndex: item == null ? itemColumn : countColumn,
        code: 'item-count',
        message: '$label requiere Item/Count enteros.',
      ),
    );
    return;
  }
  final emptyItem = item == 0;
  final emptyCount = count == 0;
  if (item < 0 || count < 0 || emptyItem != emptyCount) {
    out.add(
      ExcelXmlSemanticIssue(
        severity: ExcelXmlIssueSeverity.error,
        sheetIndex: sheetIndex,
        rowIndex: rowIndex,
        columnIndex: emptyItem ? countColumn : itemColumn,
        code: 'item-count',
        message:
            '$label debe usar Item=0/Count=0 para vacío o ambos valores '
            'positivos.',
      ),
    );
  }
}

void _datePart(
  List<ExcelXmlSemanticIssue> out,
  ExcelXmlSheet sheet,
  int sheetIndex,
  int rowIndex,
  int? column,
  String label,
  int min,
  int max, {
  bool optional = false,
}) {
  if (column == null) return;
  final raw = sheet.rows[rowIndex].value(column).trim();
  if (optional && raw.isEmpty) return;
  _integerError(
    out,
    sheet,
    sheetIndex,
    rowIndex,
    column,
    label,
    min: min,
    max: max,
  );
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

List<ExcelXmlSemanticIssue> _wingPosition(ExcelXmlDocument document) {
  final out = <ExcelXmlSemanticIssue>[];
  for (var s = 0; s < document.sheets.length; s++) {
    final sheet = document.sheets[s];
    final c = _columns(sheet);
    final family = c['family'];
    final job = c['job'];
    final sex = c['sex'];
    final bone = c['bone_idx'];
    final required = [
      family,
      job,
      sex,
      bone,
      c['wing_rot_x'],
      c['wing_rot_y'],
      c['wing_rot_z'],
      c['wing_up_down'],
      c['wing_front_back'],
      c['wing_left_right'],
    ];
    if (required.any((value) => value == null)) continue;
    for (var r = 0; r < sheet.rows.length; r++) {
      _integerError(out, sheet, s, r, family, 'FAMILY', min: 0, max: 3);
      _integerError(out, sheet, s, r, job, 'JOB', min: 0, max: 5);
      _integerError(out, sheet, s, r, sex, 'SEX', min: 0, max: 1);
      _integerError(out, sheet, s, r, bone, 'BONE_IDX', min: 0);
      for (final name in const [
        'wing_rot_x',
        'wing_rot_y',
        'wing_rot_z',
        'wing_up_down',
        'wing_front_back',
        'wing_left_right',
      ]) {
        _finiteNumberError(out, sheet, s, r, c[name], name.toUpperCase());
      }
    }
    _duplicateKeys(
      out,
      sheet,
      s,
      [family!, job!, sex!],
      label: 'La combinación FAMILY + JOB + SEX',
    );
    if (sheet.rows.length != 48) {
      out.add(
        ExcelXmlSemanticIssue(
          severity: ExcelXmlIssueSeverity.error,
          sheetIndex: s,
          code: 'wing-profile-count',
          message:
              'WingPosition requiere 48 perfiles (4 familias × 6 jobs × '
              '2 sexos); hay ' + sheet.rows.length.toString() + '.',
        ),
      );
    }
  }
  return out;
}

List<ExcelXmlSemanticIssue> _battleFieldPrize(
  ExcelXmlDocument document,
) {
  final out = <ExcelXmlSemanticIssue>[];
  for (var s = 0; s < document.sheets.length; s++) {
    final sheet = document.sheets[s];
    final c = _columns(sheet);
    final minRank = c['rankmin'];
    final maxRank = c['rankmax'];
    if (minRank == null || maxRank == null) continue;
    for (var r = 0; r < sheet.rows.length; r++) {
      _integerError(out, sheet, s, r, minRank, 'RankMin', min: 1);
      _integerError(out, sheet, s, r, maxRank, 'RankMax', min: 1);
      final a = _intValue(sheet.rows[r], minRank);
      final b = _intValue(sheet.rows[r], maxRank);
      if (a != null && b != null && a > b) {
        out.add(
          ExcelXmlSemanticIssue(
            severity: ExcelXmlIssueSeverity.error,
            sheetIndex: s,
            rowIndex: r,
            columnIndex: minRank,
            code: 'rank-range',
            message: 'RankMin no puede ser mayor que RankMax.',
          ),
        );
      }
      for (var slot = 1; slot <= 4; slot++) {
        _itemCountPair(
          out,
          sheet,
          s,
          r,
          c['item' + slot.toString()],
          c['count' + slot.toString()],
          'Recompensa ' + slot.toString(),
        );
      }
    }
  }
  return out;
}

List<ExcelXmlSemanticIssue> _guildGemItem(ExcelXmlDocument document) {
  final out = <ExcelXmlSemanticIssue>[];
  for (var s = 0; s < document.sheets.length; s++) {
    final sheet = document.sheets[s];
    final c = _columns(sheet);
    final item = c['gemitemid'];
    final count = c['gemitemcnt'];
    if (item == null || count == null) continue;
    for (var r = 0; r < sheet.rows.length; r++) {
      _integerError(
        out,
        sheet,
        s,
        r,
        item,
        'GEMITEMID',
        min: 1,
        allowZero: false,
      );
      _integerError(
        out,
        sheet,
        s,
        r,
        count,
        'GEMITEMCNT',
        min: 1,
        allowZero: false,
      );
    }
    _duplicateKeys(out, sheet, s, [item], label: 'GEMITEMID');
  }
  return out;
}

List<ExcelXmlSemanticIssue> _infiniteDungeonRebirth(
  ExcelXmlDocument document,
) {
  final out = <ExcelXmlSemanticIssue>[];
  for (var s = 0; s < document.sheets.length; s++) {
    final sheet = document.sheets[s];
    final c = _columns(sheet);
    final map = c['mapid'];
    final birth = c['isbirth'];
    if (map == null || birth == null) continue;
    for (var r = 0; r < sheet.rows.length; r++) {
      _integerError(out, sheet, s, r, map, 'MapID', min: 0);
      _integerError(out, sheet, s, r, birth, 'IsBirth', min: 0, max: 1);
    }
    _duplicateKeys(out, sheet, s, [map], label: 'MapID');
  }
  return out;
}

List<ExcelXmlSemanticIssue> _renownShop(ExcelXmlDocument document) {
  final out = <ExcelXmlSemanticIssue>[];
  for (var s = 0; s < document.sheets.length; s++) {
    final sheet = document.sheets[s];
    final c = _columns(sheet);
    final id = c['id'];
    if (id == null) continue;
    for (var r = 0; r < sheet.rows.length; r++) {
      _integerError(out, sheet, s, r, id, 'ID', min: 1, allowZero: false);
      _integerError(
        out,
        sheet,
        s,
        r,
        c['itemid'],
        'ItemID',
        min: 1,
        allowZero: false,
      );
      _integerError(
        out,
        sheet,
        s,
        r,
        c['itemcount'],
        'ItemCount',
        min: 1,
        allowZero: false,
      );
      _integerError(out, sheet, s, r, c['renown'], 'Renown', min: 0);
      _integerError(out, sheet, s, r, c['killlevel'], 'KillLevel', min: 0);
      _integerError(out, sheet, s, r, c['limittype'], 'LimitType', min: 0);
      _integerError(out, sheet, s, r, c['limitnum'], 'LimitNum', min: 0);
    }
    _duplicateKeys(out, sheet, s, [id], label: 'ID');
  }
  return out;
}

List<ExcelXmlSemanticIssue> _functionalPetSize(
  ExcelXmlDocument document,
) {
  final out = <ExcelXmlSemanticIssue>[];
  for (var s = 0; s < document.sheets.length; s++) {
    final sheet = document.sheets[s];
    final c = _columns(sheet);
    final monster = c['monsterid'];
    if (monster == null) continue;
    for (var r = 0; r < sheet.rows.length; r++) {
      _integerError(
        out,
        sheet,
        s,
        r,
        monster,
        'MonsterID',
        min: 1,
        allowZero: false,
      );
      for (final name in const [
        'dyeingsize',
        'pointshopsize',
        'particleeffectsize',
        '3deffectsize',
        '3deffectheight',
      ]) {
        _finiteNumberError(out, sheet, s, r, c[name], name);
      }
    }
    _duplicateKeys(out, sheet, s, [monster], label: 'MonsterID');
  }
  return out;
}

List<ExcelXmlSemanticIssue> _healSkillList(ExcelXmlDocument document) {
  final out = <ExcelXmlSemanticIssue>[];
  for (var s = 0; s < document.sheets.length; s++) {
    final sheet = document.sheets[s];
    final skill = _columns(sheet)['skillid'];
    if (skill == null) continue;
    for (var r = 0; r < sheet.rows.length; r++) {
      _integerError(
        out,
        sheet,
        s,
        r,
        skill,
        'SKILLID',
        min: 1,
        allowZero: false,
      );
    }
    _duplicateKeys(out, sheet, s, [skill], label: 'SKILLID');
  }
  return out;
}

List<ExcelXmlSemanticIssue> _itemAddOption(ExcelXmlDocument document) {
  final out = <ExcelXmlSemanticIssue>[];
  for (var s = 0; s < document.sheets.length; s++) {
    final sheet = document.sheets[s];
    final c = _columns(sheet);
    final type = c['type'];
    final typeId = c['typeid'];
    if (type == null || typeId == null) continue;
    for (var r = 0; r < sheet.rows.length; r++) {
      _integerError(out, sheet, s, r, type, 'Type', min: 0);
      _integerError(out, sheet, s, r, typeId, 'TypeID', min: 0);
      _finiteNumberError(
        out,
        sheet,
        s,
        r,
        c['criticalhitdamage'],
        'CriticalHitDamage',
      );
    }
    _duplicateKeys(out, sheet, s, [type, typeId], label: 'Type + TypeID');
  }
  return out;
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
    if ([wing, grade, oldItem, maxLevel].any((value) => value == null)) {
      continue;
    }
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

List<ExcelXmlSemanticIssue> _fontStyleSet(ExcelXmlDocument document) {
  final out = <ExcelXmlSemanticIssue>[];
  for (var s = 0; s < document.sheets.length; s++) {
    final sheet = document.sheets[s];
    final c = _columns(sheet);
    final index = c['index'];
    if (index == null) continue;
    for (var r = 0; r < sheet.rows.length; r++) {
      _integerError(out, sheet, s, r, index, 'Index', min: 0);
      for (final name in const [
        'textcolor_r',
        'textcolor_g',
        'textcolor_b',
      ]) {
        _numberRange(out, sheet, s, r, c[name], name, 0, 255);
      }
      for (final name in const [
        'textstrokecolor_r',
        'textstrokecolor_g',
        'textstrokecolor_b',
      ]) {
        _numberRangeIfPresent(out, sheet, s, r, c[name], name, 0, 255);
      }
    }
    _duplicateKeys(out, sheet, s, [index], label: 'Index');
  }
  return out;
}

List<ExcelXmlSemanticIssue> _gmNotice(ExcelXmlDocument document) {
  final out = <ExcelXmlSemanticIssue>[];
  for (var s = 0; s < document.sheets.length; s++) {
    final sheet = document.sheets[s];
    final c = _columns(sheet);
    final type = c['type'];
    final legacy = c['textcolor_r1'] != null;
    for (var r = 0; r < sheet.rows.length; r++) {
      if (type != null) {
        _integerError(
          out,
          sheet,
          s,
          r,
          type,
          'Type',
          min: 1,
          allowZero: false,
        );
      }
      final colors = legacy
          ? const [
              'textcolor_r1',
              'textcolor_g1',
              'textcolor_b1',
              'textcolor_r2',
              'textcolor_g2',
              'textcolor_b2',
              'bgalpha',
            ]
          : const ['textcolor_r', 'textcolor_g', 'textcolor_b'];
      for (final name in colors) {
        _numberRange(out, sheet, s, r, c[name], name, 0, 255);
      }
    }
    if (type != null) {
      _duplicateKeys(out, sheet, s, [type], label: 'Type');
    }
  }
  return out;
}

List<ExcelXmlSemanticIssue> _ymEventInfo(ExcelXmlDocument document) {
  final out = <ExcelXmlSemanticIssue>[];
  for (var s = 0; s < document.sheets.length; s++) {
    final sheet = document.sheets[s];
    final c = _columns(sheet);
    final id = c['id'];
    if (id == null) continue;
    for (var r = 0; r < sheet.rows.length; r++) {
      _integerError(out, sheet, s, r, id, 'ID', min: 1, allowZero: false);
      _integerError(out, sheet, s, r, c['flagnew'], 'FlagNew', min: 0, max: 1);
    }
    _duplicateKeys(out, sheet, s, [id], label: 'ID');
  }
  return out;
}

List<ExcelXmlSemanticIssue> _visiblePartyBuff(
  ExcelXmlDocument document,
) {
  final out = <ExcelXmlSemanticIssue>[];
  for (var s = 0; s < document.sheets.length; s++) {
    final sheet = document.sheets[s];
    final c = _columns(sheet);
    final id = c['id'];
    final level = c['skilllevel'];
    if (id == null || level == null) continue;
    for (var r = 0; r < sheet.rows.length; r++) {
      _integerError(out, sheet, s, r, id, 'id', min: 1, allowZero: false);
      _integerError(
        out,
        sheet,
        s,
        r,
        level,
        'skilllevel',
        min: 1,
        allowZero: false,
      );
    }
    _duplicateKeys(out, sheet, s, [id, level], label: 'id + skilllevel');
  }
  return out;
}

List<ExcelXmlSemanticIssue> _npcDisable(ExcelXmlDocument document) {
  final out = <ExcelXmlSemanticIssue>[];
  for (var s = 0; s < document.sheets.length; s++) {
    final sheet = document.sheets[s];
    final c = _columns(sheet);
    for (var r = 0; r < sheet.rows.length; r++) {
      for (final prefix in const ['start_', 'end_']) {
        _datePart(
          out,
          sheet,
          s,
          r,
          c[prefix + 'year'],
          prefix.toUpperCase() + 'YEAR',
          0,
          9999,
        );
        _datePart(
          out,
          sheet,
          s,
          r,
          c[prefix + 'month'],
          prefix.toUpperCase() + 'MONTH',
          1,
          12,
        );
        _datePart(
          out,
          sheet,
          s,
          r,
          c[prefix + 'day'],
          prefix.toUpperCase() + 'DAY',
          1,
          31,
        );
        _datePart(
          out,
          sheet,
          s,
          r,
          c[prefix + 'time'],
          prefix.toUpperCase() + 'TIME',
          0,
          23,
        );
        _datePart(
          out,
          sheet,
          s,
          r,
          c[prefix + 'minute'],
          prefix.toUpperCase() + 'MINUTE',
          0,
          59,
        );
      }
      _integerError(out, sheet, s, r, c['npc_type'], 'NPC_TYPE', min: 0);
      _integerError(out, sheet, s, r, c['npc_typeid'], 'NPC_TYPEID', min: 0);
    }
  }
  return out;
}

List<ExcelXmlSemanticIssue> _timeNotice(ExcelXmlDocument document) {
  final out = <ExcelXmlSemanticIssue>[];
  for (var s = 0; s < document.sheets.length; s++) {
    final sheet = document.sheets[s];
    final c = _columns(sheet);
    for (var r = 0; r < sheet.rows.length; r++) {
      _integerError(out, sheet, s, r, c['who'], 'WHO', min: 0);
      _integerError(out, sheet, s, r, c['sysmsgindex'], 'SYSMSGINDEX', min: 0);
      _datePart(out, sheet, s, r, c['year'], 'YEAR', 0, 9999);
      _datePart(out, sheet, s, r, c['month'], 'MONTH', 1, 12);
      _datePart(out, sheet, s, r, c['day'], 'DAY', 1, 31);
      _datePart(out, sheet, s, r, c['hour'], 'HOUR', 0, 23);
      _datePart(out, sheet, s, r, c['minute'], 'MINUTE', 0, 59);
      _datePart(
        out,
        sheet,
        s,
        r,
        c['end_year'],
        'END_YEAR',
        0,
        9999,
        optional: true,
      );
      _datePart(
        out,
        sheet,
        s,
        r,
        c['end_month'],
        'END_MONTH',
        1,
        12,
        optional: true,
      );
      _datePart(
        out,
        sheet,
        s,
        r,
        c['end_day'],
        'END_DAY',
        1,
        31,
        optional: true,
      );
      _datePart(
        out,
        sheet,
        s,
        r,
        c['end_hour'],
        'END_HOUR',
        0,
        23,
        optional: true,
      );
      _datePart(
        out,
        sheet,
        s,
        r,
        c['end_minute'],
        'END_MINUTE',
        0,
        59,
        optional: true,
      );
    }
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
