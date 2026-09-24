import 'dart:typed_data';

import 'excelxml_document.dart';

class WingDecomposeRule {
  final int wingId;
  final int grade;
  final int oldWingItem;
  final int maxLevel;

  const WingDecomposeRule({
    required this.wingId,
    required this.grade,
    required this.oldWingItem,
    required this.maxLevel,
  });
}

class WingSwapReward {
  final int itemId;
  final int count;

  const WingSwapReward(this.itemId, this.count);
}

class WingSwapRule {
  final int oldWingItem;
  final List<WingSwapReward> rewards;

  const WingSwapRule({
    required this.oldWingItem,
    required this.rewards,
  });
}

class WingSystemsCatalog {
  final List<WingDecomposeRule> decompose;
  final List<int> expItems;
  final List<WingSwapRule> swaps;

  const WingSystemsCatalog({
    required this.decompose,
    required this.expItems,
    required this.swaps,
  });

  static WingSystemsCatalog parse({
    Uint8List? decomposeBytes,
    Uint8List? expBytes,
    Uint8List? swapBytes,
  }) {
    final decompose = decomposeBytes == null
        ? <WingDecomposeRule>[]
        : _parseDecompose(decomposeBytes);
    final expItems = expBytes == null ? <int>[] : _parseExp(expBytes);
    final swaps = swapBytes == null ? <WingSwapRule>[] : _parseSwap(swapBytes);
    return WingSystemsCatalog(
      decompose: List.unmodifiable(decompose),
      expItems: List.unmodifiable(expItems),
      swaps: List.unmodifiable(swaps),
    );
  }

  List<int> get wingIds {
    final out = decompose.map((rule) => rule.wingId).toSet().toList()..sort();
    return List.unmodifiable(out);
  }

  List<WingDecomposeRule> progressionFor(int wingId) {
    final out = decompose.where((rule) => rule.wingId == wingId).toList()
      ..sort((a, b) => a.grade.compareTo(b.grade));
    return List.unmodifiable(out);
  }

  WingSwapRule? swapForItem(int itemId) =>
      swaps.where((rule) => rule.oldWingItem == itemId).firstOrNull;

  static List<WingDecomposeRule> _parseDecompose(Uint8List bytes) {
    final doc = ExcelXmlDocument.parse(
      bytes,
      'excelxml/wingdecompose.xml',
    );
    final sheet = _sheet(
      doc,
      const {'WINGID', 'GRADE', 'OLDWINGITEM', 'MAXLEVEL'},
    );
    final columns = _columns(sheet);
    final out = <WingDecomposeRule>[];
    final seen = <String>{};
    for (final row in sheet.rows) {
      final wingId = _requiredInt(row, columns, 'WINGID');
      final grade = _requiredInt(row, columns, 'GRADE');
      final oldWingItem = _requiredInt(row, columns, 'OLDWINGITEM');
      final maxLevel = _requiredInt(row, columns, 'MAXLEVEL');
      if (wingId <= 0 ||
          grade < 0 ||
          oldWingItem <= 0 ||
          maxLevel <= 0) {
        throw const FormatException(
          'WingDecompose.xml contiene una regla fuera de rango.',
        );
      }
      final key = '$wingId/$grade';
      if (!seen.add(key)) {
        throw FormatException(
          'WingDecompose.xml contiene el grado duplicado $key.',
        );
      }
      out.add(
        WingDecomposeRule(
          wingId: wingId,
          grade: grade,
          oldWingItem: oldWingItem,
          maxLevel: maxLevel,
        ),
      );
    }
    out.sort((a, b) {
      final wing = a.wingId.compareTo(b.wingId);
      return wing != 0 ? wing : a.grade.compareTo(b.grade);
    });
    return out;
  }

  static List<int> _parseExp(Uint8List bytes) {
    final doc = ExcelXmlDocument.parse(bytes, 'excelxml/wingexpitem.xml');
    final sheet = _sheet(doc, const {'ITEMID'});
    final columns = _columns(sheet);
    final out = <int>[];
    final seen = <int>{};
    for (final row in sheet.rows) {
      final item = _requiredInt(row, columns, 'ITEMID');
      if (item <= 0) {
        throw const FormatException(
          'WingExpItem.xml contiene ItemID fuera de rango.',
        );
      }
      if (!seen.add(item)) {
        throw FormatException('WingExpItem.xml contiene ItemID duplicado $item.');
      }
      out.add(item);
    }
    out.sort();
    return out;
  }

  static List<WingSwapRule> _parseSwap(Uint8List bytes) {
    final doc = ExcelXmlDocument.parse(bytes, 'excelxml/wingswap.xml');
    final sheet = _sheet(
      doc,
      const {
        'OLDWINGITEM',
        'EXCHANGEITEM1',
        'COUNT1',
        'EXCHANGEITEM2',
        'COUNT2',
        'EXCHANGEITEM3',
        'COUNT3',
      },
    );
    final columns = _columns(sheet);
    final out = <WingSwapRule>[];
    final seen = <int>{};
    for (final row in sheet.rows) {
      final old = _requiredInt(row, columns, 'OLDWINGITEM');
      if (old <= 0 || !seen.add(old)) {
        throw FormatException(
          'WingSwap.xml contiene OldWingItem inválido o duplicado: $old.',
        );
      }
      final rewards = <WingSwapReward>[];
      for (var i = 1; i <= 3; i++) {
        final item = _requiredInt(row, columns, 'EXCHANGEITEM$i');
        final count = _requiredInt(row, columns, 'COUNT$i');
        if (item == 0 && count == 0) continue;
        if (item <= 0 || count <= 0) {
          throw FormatException(
            'WingSwap.xml: recompensa $i inválida para OldWingItem $old.',
          );
        }
        rewards.add(WingSwapReward(item, count));
      }
      out.add(
        WingSwapRule(
          oldWingItem: old,
          rewards: List.unmodifiable(rewards),
        ),
      );
    }
    out.sort((a, b) => a.oldWingItem.compareTo(b.oldWingItem));
    return out;
  }

  static ExcelXmlSheet _sheet(
    ExcelXmlDocument document,
    Set<String> required,
  ) {
    for (final sheet in document.sheets) {
      final labels = {
        for (final column in sheet.columns) column.label.trim().toUpperCase(),
      };
      if (required.every(labels.contains)) return sheet;
    }
    throw FormatException(
      '${document.path}: no contiene las columnas requeridas '
      '${required.join(', ')}.',
    );
  }

  static Map<String, int> _columns(ExcelXmlSheet sheet) => {
    for (final column in sheet.columns)
      column.label.trim().toUpperCase(): column.index,
  };

  static int _requiredInt(
    ExcelXmlRow row,
    Map<String, int> columns,
    String label,
  ) {
    final column = columns[label];
    if (column == null) {
      throw FormatException('Columna $label ausente.');
    }
    final raw = row.value(column).trim();
    final value = int.tryParse(raw);
    if (value == null) {
      throw FormatException(
        '$label no es un entero válido en fila ${row.sourceRow}: $raw',
      );
    }
    return value;
  }
}
