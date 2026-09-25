import 'dart:typed_data';

import 'document.dart';
import 'schema_reader.dart';

/// Tables with explicit primary keys only. Deleting a classic implicit-ID row
/// would renumber every later reference; such files intentionally refuse this.
class StructureEditor {
  static List<FieldSpan> identity(EditDocument d, int row) {
    final fs = d.fields(row);
    FieldSpan? named(List<String> n) =>
        fs.where((f) => n.contains(f.spec.name.toLowerCase())).firstOrNull;
    final type = named(['type', 'itemtype']),
        sub = named(['typeid', 'itemtypeid']);
    if (type != null && sub != null) return [type, sub];
    final id = named(['id', 'goodsid', 'goods_id']),
        level = named(['skilllevel']);
    return id == null ? [] : [id, ?level];
  }

  static bool supported(EditDocument d) =>
      d.profile == 'binary' &&
      d.complete &&
      d.rows.isNotEmpty &&
      identity(d, 0).isNotEmpty;
  static EditDocument fresh(EditDocument d) =>
      reopenDocument(d, d.exportBytes());
  static int countOffset(Uint8List b) {
    final data = ByteData.sublistView(b);
    var at = 128;
    if (b.length < 136) throw const FormatException('Cabecera DB truncada.');
    final n = data.getUint32(at, Endian.little);
    at += 4;
    if (n > 256) throw const FormatException('Cabecera DB inválida.');
    for (var i = 0; i < n; i++) {
      if (at >= b.length) throw const FormatException('Cabecera DB truncada.');
      final size = b[at++] * 2;
      at += size;
    }
    if (at + 4 > b.length) throw const FormatException('Recuento DB truncado.');
    return at;
  }

  static void duplicate(
    EditDocument document,
    int row,
    Map<String, String> newKey,
  ) {
    if (!supported(document)) {
      throw const FormatException(
        'La creación requiere una tabla DB con IDs explícitos.',
      );
    }
    final edited = fresh(document), ids = identity(edited, row);
    if (ids.any((f) => !newKey.containsKey(f.spec.name))) {
      throw const FormatException('Falta parte de la clave del registro.');
    }
    for (final f in ids) {
      edited.edit(row, f, newKey[f.spec.name]!);
    }
    final key = ids.map(edited.read).join(':');
    final original = fresh(document);
    for (var i = 0; i < original.rows.length; i++) {
      if (identity(original, i).map(original.read).join(':') == key) {
        throw const FormatException('Ese identificador ya existe.');
      }
    }
    final changed = fresh(edited),
        record = changed.rows[row],
        end = original.rows.last.end;
    final out = BytesBuilder(copy: false)
      ..add(Uint8List.sublistView(original.payload, 0, end))
      ..add(Uint8List.sublistView(changed.payload, record.offset, record.end))
      ..add(Uint8List.sublistView(original.payload, end));
    final bytes = out.takeBytes();
    ByteData.sublistView(
      bytes,
    ).setUint32(countOffset(bytes), original.rows.length + 1, Endian.little);
    final parsed = EditorReader.open(
      bytes,
      document.path,
      encoding: document.codec.encoding,
      forceProfile: document.profile,
    );
    if (!parsed.complete || parsed.rows.length != original.rows.length + 1) {
      throw const FormatException('La fila nueva no supera la relectura.');
    }
    document.replaceStructure(parsed, 'Crear registro $key');
  }

  static void delete(EditDocument document, int row) {
    if (!supported(document)) {
      throw const FormatException(
        'No se elimina una fila con identificador implícito.',
      );
    }
    final original = fresh(document), r = original.rows[row];
    final out = BytesBuilder(copy: false)
      ..add(Uint8List.sublistView(original.payload, 0, r.offset))
      ..add(Uint8List.sublistView(original.payload, r.end));
    final bytes = out.takeBytes();
    ByteData.sublistView(
      bytes,
    ).setUint32(countOffset(bytes), original.rows.length - 1, Endian.little);
    final parsed = EditorReader.open(
      bytes,
      document.path,
      encoding: document.codec.encoding,
      forceProfile: document.profile,
    );
    if (!parsed.complete || parsed.rows.length != original.rows.length - 1) {
      throw const FormatException('La eliminación no supera la relectura.');
    }
    document.replaceStructure(parsed, 'Eliminar registro ${row + 1}');
  }
}
