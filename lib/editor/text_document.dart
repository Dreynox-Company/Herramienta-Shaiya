import 'dart:convert';
import 'dart:typed_data';

import '../core/game_text_codec.dart';
import 'document.dart';

/// An editable physical-line document. BOM, per-line terminators, comments,
/// repeated keys and whitespace survive. There is no global INI reformatter.
class TextDocument extends EditDocument {
  final List<String> endings;
  final Uint8List bom;
  final GameTextEncoding sourceEncoding;
  final bool bigEndian;
  TextDocument._({
    required super.path,
    required super.original,
    required super.payload,
    required super.rows,
    required this.endings,
    required this.bom,
    required this.sourceEncoding,
    required this.bigEndian,
  }) : super(
         profile: 'text-lines',
         codec: const GameTextCodec(GameTextEncoding.utf8),
         parsedBytes: payload.length,
         warnings: const [
           'Texto original. Los comentarios, secciones y claves duplicadas se conservan. Los valores se validan por el cliente al cargar; no se les asigna un significado inventado.',
         ],
       );
  static TextDocument open(
    Uint8List bytes,
    String path,
    GameTextEncoding encoding,
  ) {
    if (bytes.length > 16 * 1024 * 1024) {
      throw const FormatException('Texto mayor de 16 MiB.');
    }
    Uint8List bom = Uint8List(0);
    var source = encoding;
    bool bigEndian = false;
    if (bytes.length >= 3 &&
        bytes[0] == 239 &&
        bytes[1] == 187 &&
        bytes[2] == 191) {
      bom = bytes.sublist(0, 3);
      source = GameTextEncoding.utf8;
    } else if (bytes.length >= 2 && bytes[0] == 255 && bytes[1] == 254) {
      bom = bytes.sublist(0, 2);
      source = GameTextEncoding.utf16le;
    } else if (bytes.length >= 2 && bytes[0] == 254 && bytes[1] == 255) {
      if (bytes.length.isOdd) {
        throw const FormatException('UTF-16 BE truncado.');
      }
      bom = bytes.sublist(0, 2);
      source = GameTextEncoding.utf16le;
      bigEndian = true;
    }
    if (source == GameTextEncoding.automatic) {
      source = GameTextEncoding.windows1252;
    }
    final body = Uint8List.fromList(bytes.sublist(bom.length));
    if (bigEndian) {
      for (var i = 0; i < body.length; i += 2) {
        final a = body[i];
        body[i] = body[i + 1];
        body[i + 1] = a;
      }
    }
    final codec = GameTextCodec(source), text = codec.decode(body);
    // Do not write a lossy decode: malformed input remains available as bytes.
    final round = codec.encode(text);
    if (round.length != body.length ||
        List.generate(
          round.length,
          (i) => round[i] == body[i],
        ).contains(false)) {
      throw const FormatException(
        'La codificación elegida no reproduce los bytes originales. Elige la correcta.',
      );
    }
    final lines = <String>[], endings = <String>[];
    int begin = 0;
    for (final m in RegExp(r'\r\n|\r|\n').allMatches(text)) {
      lines.add(text.substring(begin, m.start));
      endings.add(m[0]!);
      begin = m.end;
    }
    if (begin < text.length || lines.isEmpty) {
      lines.add(text.substring(begin));
      endings.add('');
    }
    if (lines.length > 200000) {
      throw const FormatException('Demasiadas líneas.');
    }
    final out = BytesBuilder(copy: false), rows = <RecordRef>[];
    var at = 0;
    String section = 'Texto';
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().startsWith('[') && line.trim().endsWith(']')) {
        section = line.trim();
      }
      final data = utf8.encode(line);
      if (data.length > 65536) {
        throw const FormatException('Línea mayor de 64 KiB.');
      }
      final prefix = ByteData(4)..setUint32(0, data.length, Endian.little);
      out.add(prefix.buffer.asUint8List());
      out.add(data);
      rows.add(
        RecordRef(
          at,
          at + 4 + data.length,
          const [FieldSpec('Text', 'text32')],
          kind: section,
          ordinal: i,
        ),
      );
      at += 4 + data.length;
    }
    return TextDocument._(
      path: path,
      original: Uint8List.fromList(bytes),
      payload: out.takeBytes(),
      rows: rows,
      endings: endings,
      bom: bom,
      sourceEncoding: source,
      bigEndian: bigEndian,
    );
  }

  @override
  Uint8List validate(FieldSpan field, String text) {
    if (text.contains('\r') || text.contains('\n')) {
      throw const FormatException(
        'Edita una línea física sin insertar saltos internos.',
      );
    }
    GameTextCodec(sourceEncoding).encode(text);
    return super.validate(field, text);
  }

  @override
  Uint8List exportBytes() {
    if (!dirty) return Uint8List.fromList(original);
    final text = StringBuffer();
    for (var i = 0; i < rows.length; i++) {
      text.write(read(fields(i).single));
      text.write(endings[i]);
    }
    final encoded = GameTextCodec(sourceEncoding).encode(text.toString());
    if (bigEndian) {
      for (var i = 0; i < encoded.length; i += 2) {
        final a = encoded[i];
        encoded[i] = encoded[i + 1];
        encoded[i + 1] = a;
      }
    }
    return (BytesBuilder(copy: false)
          ..add(bom)
          ..add(encoded))
        .takeBytes();
  }
}
