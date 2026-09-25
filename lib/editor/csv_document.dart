import 'dart:convert';
import 'dart:typed_data';

import '../core/game_text_codec.dart';
import 'document.dart';

/// Optional companion for server-exported tables. Import/export only; this
/// class never connects to a database or claims to deploy server changes.
class CsvDocument extends EditDocument {
  final List<String> headers;
  final String separator, newline;
  final bool bom;
  final GameTextEncoding sourceEncoding;
  GameTextEncoding get exportEncoding =>
      dirty ? GameTextEncoding.utf8 : sourceEncoding;
  CsvDocument._({
    required super.path,
    required super.original,
    required super.payload,
    required super.rows,
    required this.headers,
    required this.separator,
    required this.newline,
    required this.bom,
    required this.sourceEncoding,
    required super.codec,
  }) : super(
         profile: 'server-csv',
         warnings: [
           'CSV de acompañamiento: exportar no actualiza el servidor. Conserva las columnas y valida sus tipos en el esquema SQL real antes de importarlo.',
         ],
         parsedBytes: payload.length,
       );
  @override
  String get authority =>
      'Servidor · CSV importado (sin despliegue automático)';
  static CsvDocument open(
    Uint8List bytes,
    String path,
    GameTextEncoding encoding,
  ) {
    if (bytes.length > 32 * 1024 * 1024) {
      throw const FormatException('El CSV supera 32 MiB.');
    }
    final inputCodec = GameTextCodec(
      encoding == GameTextEncoding.automatic ? GameTextEncoding.utf8 : encoding,
    );
    var text = inputCodec.decode(bytes);
    final bom = text.startsWith('\uFEFF');
    if (bom) text = text.substring(1);
    final first = text.split(RegExp(r'\r?\n')).first;
    final sep = first.contains('\t')
        ? '\t'
        : first.split(';').length > first.split(',').length
        ? ';'
        : ',';
    final table = _parse(text, sep);
    if (table.isEmpty || table.first.isEmpty) {
      throw const FormatException('CSV sin encabezado.');
    }
    final headers = table.removeAt(0);
    if (headers.length > 512 ||
        headers.any((h) => h.isEmpty) ||
        headers.toSet().length != headers.length) {
      throw const FormatException(
        'Columnas duplicadas, vacías o demasiadas columnas.',
      );
    }
    if (table.length > 200000) {
      throw const FormatException('El CSV supera 200.000 registros.');
    }
    final out = BytesBuilder(copy: false);
    var at = 0;
    final refs = <RecordRef>[];
    final schema = headers
        .map((h) => FieldSpec(h, 'text'))
        .toList(growable: false);
    for (var i = 0; i < table.length; i++) {
      final row = table[i];
      if (row.length != headers.length) {
        throw FormatException(
          'La fila ${i + 2} tiene ${row.length} columnas; se esperaban ${headers.length}.',
        );
      }
      final start = at;
      for (final value in row) {
        final b = utf8.encode(value);
        if (b.length > 65536) {
          throw const FormatException('Celda CSV demasiado larga.');
        }
        final p = ByteData(4)..setUint32(0, b.length, Endian.little);
        out.add(p.buffer.asUint8List());
        out.add(b);
        at += 4 + b.length;
      }
      refs.add(RecordRef(start, at, schema, kind: 'Servidor CSV', ordinal: i));
    }
    return CsvDocument._(
      path: path,
      original: Uint8List.fromList(bytes),
      payload: out.takeBytes(),
      rows: refs,
      headers: headers,
      separator: sep,
      newline: text.contains('\r\n') ? '\r\n' : '\n',
      bom: bom,
      sourceEncoding: inputCodec.encoding,
      codec: const GameTextCodec(GameTextEncoding.utf8),
    );
  }

  @override
  Uint8List exportBytes() {
    if (!dirty) return Uint8List.fromList(original);
    String quote(String s) =>
        s.contains(separator) ||
            s.contains('"') ||
            s.contains('\r') ||
            s.contains('\n')
        ? '"${s.replaceAll('"', '""')}"'
        : s;
    final out = StringBuffer(bom ? '\uFEFF' : '');
    out.write(headers.map(quote).join(separator));
    out.write(newline);
    for (var i = 0; i < rows.length; i++) {
      out.write(fields(i).map((f) => quote(read(f))).join(separator));
      out.write(newline);
    }
    // Edited companion CSV is explicitly UTF8, not silently written with the
    // legacy source codepage. Binary game exports retain their own encoding.
    return Uint8List.fromList(utf8.encode(out.toString()));
  }

  static List<List<String>> _parse(String text, String sep) {
    final rows = <List<String>>[];
    var row = <String>[], cell = StringBuffer();
    var quoted = false, closed = false;
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (quoted) {
        if (c == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            cell.write('"');
            i++;
          } else {
            quoted = false;
            closed = true;
          }
        } else {
          cell.write(c);
        }
        continue;
      }
      if (c == '"' && cell.isEmpty && !closed) {
        quoted = true;
        continue;
      }
      if (c == sep) {
        row.add(cell.toString());
        cell = StringBuffer();
        closed = false;
        continue;
      }
      if (c == '\r' || c == '\n') {
        if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        row.add(cell.toString());
        rows.add(row);
        row = [];
        cell = StringBuffer();
        closed = false;
        continue;
      }
      if (closed) {
        throw const FormatException(
          'Carácter inesperado tras cerrar una celda CSV.',
        );
      }
      cell.write(c);
    }
    if (quoted) throw const FormatException('CSV con comillas sin cerrar.');
    if (cell.isNotEmpty || row.isNotEmpty || closed) {
      row.add(cell.toString());
      rows.add(row);
    }
    return rows;
  }
}
