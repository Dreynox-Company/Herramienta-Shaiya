import 'dart:convert';
import 'dart:typed_data';

import 'legacy_text.dart';

/// An encoding is an on-disk contract, not a font setting. Lossy encoding is
/// never used by the editor. Untouched strings keep their original bytes.
enum GameTextEncoding { automatic, utf8, windows1252, big5, korean, utf16le }

extension GameTextEncodingLabel on GameTextEncoding {
  String get label => switch (this) {
    GameTextEncoding.automatic => 'Automática (solo lectura)',
    GameTextEncoding.utf8 => 'Unicode UTF-8',
    GameTextEncoding.windows1252 => 'Español / Occidental · Windows-1252',
    GameTextEncoding.big5 => 'Chino tradicional · Big5 / CP950',
    GameTextEncoding.korean => 'Coreano · CP949',
    GameTextEncoding.utf16le => 'Unicode UTF-16 LE',
  };
}

class GameTextCodec {
  final GameTextEncoding encoding;
  const GameTextCodec(this.encoding);
  static const windows = GameTextCodec(GameTextEncoding.windows1252);
  static const _cp = <int>[
    0x20ac,
    0x81,
    0x201a,
    0x0192,
    0x201e,
    0x2026,
    0x2020,
    0x2021,
    0x02c6,
    0x2030,
    0x0160,
    0x2039,
    0x0152,
    0x8d,
    0x017d,
    0x8f,
    0x90,
    0x2018,
    0x2019,
    0x201c,
    0x201d,
    0x2022,
    0x2013,
    0x2014,
    0x02dc,
    0x2122,
    0x0161,
    0x203a,
    0x0153,
    0x9d,
    0x017e,
    0x0178,
  ];
  String decode(List<int> b) => switch (encoding) {
    GameTextEncoding.utf8 => utf8.decode(b),
    GameTextEncoding.utf16le => _utf16(b),
    GameTextEncoding.windows1252 => String.fromCharCodes(
      b.map((v) => v >= 128 && v < 160 ? _cp[v - 128] : v),
    ),
    GameTextEncoding.big5 => LegacyText.decodeBig5(b),
    GameTextEncoding.korean => LegacyText.decodeKorean(b),
    GameTextEncoding.automatic => autoDecode(b),
  };
  static String autoDecode(List<int> b) {
    try {
      return utf8.decode(b);
    } on FormatException {
      /* legacy encoding */
    }
    if (b.where((v) => v >= 128).length > b.length * 0.3) {
      final value = LegacyText.decodeBig5(b);
      if (!value.contains('\uFFFD')) return value;
    }
    return windows.decode(b);
  }

  static String _utf16(List<int> b) {
    if (b.length.isOdd) {
      throw const FormatException('UTF-16 tiene un byte incompleto.');
    }
    final d = ByteData.sublistView(Uint8List.fromList(b));
    final units = List.generate(
      b.length ~/ 2,
      (i) => d.getUint16(i * 2, Endian.little),
    );
    final s = String.fromCharCodes(units);
    _checkSurrogates(s);
    return s;
  }

  static void _checkSurrogates(String text) {
    final u = text.codeUnits;
    for (var i = 0; i < u.length; i++) {
      if (u[i] >= 0xd800 && u[i] <= 0xdbff) {
        if (i + 1 >= u.length || u[i + 1] < 0xdc00 || u[i + 1] > 0xdfff) {
          throw const FormatException(
            'Unicode contiene un sustituto incompleto.',
          );
        }
        i++;
      } else if (u[i] >= 0xdc00 && u[i] <= 0xdfff) {
        throw const FormatException('Unicode contiene un sustituto aislado.');
      }
    }
  }

  Uint8List encode(String text) {
    _checkSurrogates(text);
    if (encoding == GameTextEncoding.automatic) {
      throw const FormatException(
        'Selecciona una codificación explícita antes de editar texto.',
      );
    }
    if (encoding == GameTextEncoding.utf8) {
      return Uint8List.fromList(utf8.encode(text));
    }
    if (encoding == GameTextEncoding.utf16le) {
      final d = ByteData(text.codeUnits.length * 2);
      for (var i = 0; i < text.codeUnits.length; i++) {
        d.setUint16(i * 2, text.codeUnitAt(i), Endian.little);
      }
      return d.buffer.asUint8List();
    }
    if (encoding == GameTextEncoding.big5 ||
        encoding == GameTextEncoding.korean) {
      return LegacyText.encodeLegacy(
        text,
        korean: encoding == GameTextEncoding.korean,
      );
    }
    final out = <int>[];
    for (final r in text.runes) {
      if (r < 128 || r >= 160 && r <= 255) {
        out.add(r);
        continue;
      }
      final i = _cp.indexOf(r);
      if (i < 0) {
        throw FormatException(
          'El carácter U+${r.toRadixString(16).toUpperCase()} no existe en Windows-1252. No se reemplaza por ?. Usa UTF-8 solo si tu cliente lo admite.',
        );
      }
      out.add(i + 128);
    }
    return Uint8List.fromList(out);
  }
}
