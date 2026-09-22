import 'dart:convert';
import 'dart:typed_data';
import 'game_text_codec.dart';

/// A resource's locale is part of its format contract. Spanish text must never
/// be guessed as Big5 merely because several accented bytes appear together.
/// This resolver uses filenames/bom, not an assumed universal client episode.
class ClientLocale {
  static String canonicalPath(String path) =>
      path.replaceAll('\\', '/').toLowerCase();
  static String directory(String path) {
    final p = canonicalPath(path), i = p.lastIndexOf('/');
    return i < 0 ? '' : p.substring(0, i);
  }

  static String stem(String path) =>
      canonicalPath(path).split('/').last.replaceFirst(RegExp(r'\.[^.]+$'), '');
  static const spanishAliases = {'spn', 'spa', 'esp', 'es', 'spain', 'spanish'};
  static const englishAliases = {'usa', 'eng', 'en', 'english'};
  static const westernAliases = {
    'ger',
    'germany',
    'de',
    'frc',
    'france',
    'fr',
    'ita',
    'italy',
    'it',
    'brz',
    'brazil',
    'pt',
    'ptbr',
  };
  static String? languageOf(String path) {
    final words = stem(path).split(RegExp('[_-]'));
    if (words.any(spanishAliases.contains)) return 'es';
    if (words.any(englishAliases.contains)) return 'en';
    if (words.any((s) => s == 'chn' || s == 'china' || s == 'chinese')) {
      return 'zh';
    }
    if (words.any((s) => s == 'kor' || s == 'korea' || s == 'kr')) return 'ko';
    return words.any(westernAliases.contains) ? 'western' : null;
  }

  static GameTextEncoding encodingForPath(
    String path, {
    GameTextEncoding fallback = GameTextEncoding.automatic,
  }) => switch (languageOf(path)) {
    'es' || 'en' || 'western' => GameTextEncoding.windows1252,
    'zh' => GameTextEncoding.big5,
    'ko' => GameTextEncoding.korean,
    _ => fallback,
  };

  /// Resolve only this dataset's directory. Root DBItemData and BinarySData
  /// may carry different records; matching a basename cannot justify mixing.
  static List<String> tableCandidates(
    Iterable<String> paths,
    String family, {
    required String beside,
    String preferred = 'es',
  }) {
    final dir = directory(beside), f = family.toLowerCase();
    final result = paths.where((original) {
      final p = canonicalPath(original), name = stem(p);
      return directory(p) == dir &&
          p.endsWith('.sdata') &&
          (name == f || name.startsWith('${f}_')) &&
          !RegExp(r'_(generated|backup|bak|old)(_|$)').hasMatch(name);
    }).toList();
    int rank(String p) {
      final l = languageOf(p);
      return l == preferred
          ? 0
          : l == 'en'
          ? 1
          : l == 'western'
          ? 2
          : l == null
          ? 4
          : 3;
    }

    result.sort((a, b) {
      final n = rank(a).compareTo(rank(b));
      return n == 0 ? canonicalPath(a).compareTo(canonicalPath(b)) : n;
    });
    return result;
  }

  static String? nameFamily(String dataPath) {
    final n = stem(dataPath);
    if (n == 'npcquest') return 'npcquesttrans';
    if (n.contains('npcskill')) return 'dbnpcskilltext';
    if (n.contains('itemsell') || n == 'cash') return 'dbitemselltext';
    if (n.contains('setitem')) return 'dbsetitemtext';
    if (n.contains('monster')) return 'dbmonstertext';
    if (n.contains('skill')) return 'dbskilltext';
    if (n.contains('item')) return 'dbitemtext';
    return null;
  }

  /// For whole text resources only (never an SData container). UTF-16 BOM and
  /// UTF-8 BOM are authoritative, without changing the original bytes.
  static String decodeTextFile(Uint8List b, String path) {
    if (b.length >= 2 && b[0] == 0xff && b[1] == 0xfe) {
      return const GameTextCodec(GameTextEncoding.utf16le).decode(b.sublist(2));
    }
    if (b.length >= 2 && b[0] == 0xfe && b[1] == 0xff) {
      if (b.length.isOdd) throw const FormatException('UTF-16 BE truncado.');
      final le = Uint8List(b.length - 2);
      for (var i = 2; i < b.length; i += 2) {
        le[i - 2] = b[i + 1];
        le[i - 1] = b[i];
      }
      return const GameTextCodec(GameTextEncoding.utf16le).decode(le);
    }
    if (b.length >= 3 && b[0] == 0xef && b[1] == 0xbb && b[2] == 0xbf) {
      return utf8.decode(b.sublist(3));
    }
    // A valid UTF-8 stream may be used by custom loose XML/INI/CSV/TXT files.
    try {
      return utf8.decode(b);
    } on FormatException {
      /* explicit locale fallback */
    }
    return GameTextCodec(encodingForPath(path)).decode(b);
  }

  /// Preserves game placeholders and original spelling, including mistakes.
  /// Duplicated numeric IDs are rejected instead of silently replacing labels.
  static Map<int, String> indexedText(Uint8List bytes, String path) {
    final catalogue = indexedCatalogue(bytes, path);
    if (catalogue.duplicates.isNotEmpty) {
      throw FormatException(
        'IDs de texto duplicados en $path: ${catalogue.duplicates.keys.take(5).join(', ')}',
      );
    }
    return catalogue.resolved;
  }

  /// All duplicate variants remain available for inspection. A conflicting ID
  /// is excluded from resolved labels instead of guessing which the client uses.
  static LocalizedTextCatalogue indexedCatalogue(Uint8List bytes, String path) {
    final records = <int, List<String>>{};
    for (final line in const LineSplitter().convert(
      decodeTextFile(bytes, path),
    )) {
      if (line.trim().isEmpty || line.trimLeft().startsWith('//')) continue;
      final match = RegExp(r'^\s*(\d+)\s+(.+?)\s*$').firstMatch(line);
      if (match == null) continue;
      final id = int.parse(match[1]!);
      var text = match[2]!;
      if (text.startsWith('"') && text.endsWith('"') && text.length >= 2) {
        text = text.substring(1, text.length - 1);
      }
      records.putIfAbsent(id, () => []).add(text);
    }
    return LocalizedTextCatalogue(records);
  }
}

class LocalizedTextCatalogue {
  final Map<int, List<String>> records;
  LocalizedTextCatalogue(Map<int, List<String>> source)
    : records = Map<int, List<String>>.unmodifiable(
        source.map(
          (id, values) => MapEntry(id, List<String>.unmodifiable(values)),
        ),
      );
  Map<int, List<String>> get duplicates => {
    for (final e in records.entries)
      if (e.value.length > 1) e.key: e.value,
  };
  Map<int, List<String>> get conflicts => {
    for (final e in records.entries)
      if (e.value.toSet().length > 1) e.key: e.value,
  };
  Map<int, String> get resolved => {
    for (final e in records.entries)
      if (e.value.toSet().length == 1) e.key: e.value.first,
  };
}
