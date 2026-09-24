import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import '../core/game_text_codec.dart';
import '../core/seed_data.dart';

/// Lossless editor: only validated spans change. Unrecognized bytes and headers
/// are preserved. Never reinterpret unsigned values as signed to accept a minus.
class FieldSpec {
  final String name, type;
  final bool editable;
  const FieldSpec(this.name, this.type, {this.editable = true});
  int get width => switch (type) {
    'u8' || 'i8' => 1,
    'u16' || 'i16' => 2,
    'u32' || 'i32' || 'f32' => 4,
    'i64' || 'u64' || 'f64' => 8,
    'text256' => 256,
    _ => 0,
  };
  bool get text => type.startsWith('text');
  bool get signed => type.startsWith('i') || type.startsWith('f');
  String get limits {
    if (text) return 'Texto · codificación del documento';
    if (type == 'opaque') {
      return 'Bytes sin significado documentado · solo lectura';
    }
    if (type.startsWith('f')) return '$type · número real finito';
    final bits = width * 8;
    return signed
        ? '${-(BigInt.one << (bits - 1))} … ${(BigInt.one << (bits - 1)) - BigInt.one}'
        : '0 … ${(BigInt.one << bits) - BigInt.one}';
  }
}

class FieldSpan {
  final FieldSpec spec;
  final int start, length, prefix, stringUnit, terminators;
  const FieldSpan(
    this.spec,
    this.start,
    this.length, {
    this.prefix = 0,
    this.stringUnit = 1,
    this.terminators = 0,
  });
}

class RecordRef {
  final int offset, end, group, ordinal;
  final String kind;
  final List<FieldSpec> schema;

  /// Dynamic records have explicitly recorded, nonoverlapping spans.
  final List<FieldSpan>? dynamicSpans;
  const RecordRef(
    this.offset,
    this.end,
    this.schema, {
    this.kind = 'Registro',
    this.group = 0,
    this.ordinal = 0,
    this.dynamicSpans,
  });
}

class FieldChange {
  final int row;
  final FieldSpan field;
  final Uint8List before, after;
  final String beforeText, afterText;
  const FieldChange(
    this.row,
    this.field,
    this.before,
    this.after,
    this.beforeText,
    this.afterText,
  );
}

class ChangeBatch {
  final List<FieldChange> changes;
  final String title;
  final DocumentStructureState? beforeStructure, afterStructure;
  const ChangeBatch(this.changes, this.title)
    : beforeStructure = null,
      afterStructure = null;
  const ChangeBatch.structure(
    this.title,
    this.beforeStructure,
    this.afterStructure,
  ) : changes = const [];
}

class DocumentStructureState {
  final Uint8List payload;
  final List<RecordRef> rows;
  final int parsedBytes;
  final Map<int, FieldChange> changes;
  final bool structural;
  const DocumentStructureState(
    this.payload,
    this.rows,
    this.parsedBytes,
    this.changes,
    this.structural,
  );
}

class EditDocument {
  final String path, profile, sha;
  final Uint8List original;
  Uint8List payload;
  final GameTextCodec codec;
  List<RecordRef> rows;
  final List<String> warnings;
  final bool complete;
  int parsedBytes;
  bool _structural = false;
  late final Uint8List _initialPayload;
  late final List<RecordRef> _initialRows;
  late final int _initialParsed;
  final Map<int, FieldChange> _changes = {};
  final List<ChangeBatch> _undo = [], _redo = [];
  int revision = 0;
  EditDocument({
    required this.path,
    required this.profile,
    required this.original,
    required this.payload,
    required this.codec,
    required this.rows,
    required this.warnings,
    required this.parsedBytes,
    this.complete = true,
  }) : sha = sha256.convert(original).toString() {
    _initialPayload = payload;
    _initialRows = rows;
    _initialParsed = parsedBytes;
  }
  bool get structuralChanges => _structural;
  bool get dirty => _structural || _changes.isNotEmpty;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  int get changeCount => _changes.length + (_structural ? 1 : 0);
  Iterable<FieldChange> get changes => _changes.values;
  bool get encrypted => SeedData.isEncoded(original);
  String get authority => path.toLowerCase().endsWith('.svmap')
      ? 'Servidor · archivo SVMAP'
      : 'Cliente · verificar correspondencia con servidor';

  List<FieldSpan> fields(int row) {
    final rec = rows[row];
    if (rec.dynamicSpans != null) return rec.dynamicSpans!;
    final result = <FieldSpan>[];
    var offset = rec.offset;
    final d = ByteData.sublistView(payload);
    for (final spec in rec.schema) {
      if (spec.text) {
        final prefix = spec.type == 'text8' ? 1 : 4;
        final n = prefix == 1
            ? payload[offset]
            : d.getUint32(offset, Endian.little);
        final unit = codec.encoding == GameTextEncoding.utf16le ? 2 : 1;
        final length = prefix + n * unit;
        var zeros = 0;
        while (zeros + unit <= n * unit &&
            payload
                .sublist(
                  offset + length - zeros - unit,
                  offset + length - zeros,
                )
                .every((b) => b == 0)) {
          zeros += unit;
        }
        result.add(
          FieldSpan(
            spec,
            offset,
            length,
            prefix: prefix,
            stringUnit: unit,
            terminators: zeros,
          ),
        );
        offset += length;
      } else {
        result.add(FieldSpan(spec, offset, spec.width));
        offset += spec.width;
      }
    }
    if (offset != rec.end) {
      throw StateError('El esquema no cubre el registro $row.');
    }
    return result;
  }

  String read(FieldSpan span, {bool originalValue = false}) {
    final patch = originalValue ? null : _changes[span.start];
    return _decode(
      span,
      patch?.after ??
          Uint8List.sublistView(payload, span.start, span.start + span.length),
    );
  }

  String _decode(FieldSpan f, Uint8List b) {
    if (f.spec.type == 'text256') {
      final zero = b.indexOf(0);
      final end = zero < 0 ? b.length : zero;
      return codec.decode(b.sublist(0, end));
    }
    if (f.spec.text) {
      final end = b.length - f.terminators;
      return codec.decode(b.sublist(f.prefix, end));
    }
    if (f.spec.type == 'opaque') {
      return '${b.take(4096).map((x) => x.toRadixString(16).padLeft(2, '0')).join(' ')}${b.length > 4096 ? ' … (${b.length} bytes conservados)' : ''}';
    }
    final d = ByteData.sublistView(b);
    return switch (f.spec.type) {
      'u8' => d.getUint8(0).toString(),
      'i8' => d.getInt8(0).toString(),
      'u16' => d.getUint16(0, Endian.little).toString(),
      'i16' => d.getInt16(0, Endian.little).toString(),
      'u32' => d.getUint32(0, Endian.little).toString(),
      'i32' => d.getInt32(0, Endian.little).toString(),
      'i64' => d.getInt64(0, Endian.little).toString(),
      'u64' =>
        ((BigInt.from(d.getUint32(4, Endian.little)) << 32) +
                BigInt.from(d.getUint32(0, Endian.little)))
            .toString(),
      'f32' => d.getFloat32(0, Endian.little).toString(),
      'f64' => d.getFloat64(0, Endian.little).toString(),
      _ => throw FormatException('Tipo no admitido: ${f.spec.type}'),
    };
  }

  Uint8List validate(FieldSpan field, String text) {
    final f = field.spec;
    if (!f.editable || f.type == 'opaque') {
      throw FormatException(
        '${f.name} es estructural o no está documentado; no se edita.',
      );
    }
    if (f.text) {
      if (text.contains('\u0000')) {
        throw const FormatException(
          'No se admiten terminadores NUL dentro de una cadena.',
        );
      }
      if (f.type == 'text256') {
        final bytes = codec.encode(text);
        if (bytes.length > 255) {
          throw const FormatException(
            'La cadena fija DATA admite como máximo 255 bytes más NUL.',
          );
        }
        final out = Uint8List(256);
        out.setRange(0, bytes.length, bytes);
        return out;
      }
      final bytes = codec.encode(text),
          total = bytes.length + field.terminators;
      final n = total ~/ field.stringUnit;
      if (n > (field.prefix == 1 ? 255 : 65536) ||
          total % field.stringUnit != 0) {
        throw const FormatException('Cadena demasiado larga para su formato.');
      }
      final out = Uint8List(field.prefix + total);
      final d = ByteData.sublistView(out);
      if (field.prefix == 1) {
        d.setUint8(0, n);
      } else {
        d.setUint32(0, n, Endian.little);
      }
      out.setRange(field.prefix, field.prefix + bytes.length, bytes);
      return out;
    }
    final clean = text.trim().replaceAll('\u2212', '-');
    final d = ByteData(f.width);
    if (f.type.startsWith('f')) {
      final value = double.tryParse(clean.replaceAll(',', '.'));
      if (value == null || !value.isFinite) {
        throw const FormatException('Introduce un número real finito.');
      }
      if (f.type == 'f32') {
        d.setFloat32(0, value, Endian.little);
        if (!d.getFloat32(0, Endian.little).isFinite) {
          throw const FormatException('El valor desborda float32.');
        }
      } else {
        d.setFloat64(0, value, Endian.little);
      }
    } else {
      if (!RegExp(r'^[+-]?\d+$').hasMatch(clean)) {
        throw const FormatException(
          'Introduce un entero decimal sin separadores.',
        );
      }
      final number = BigInt.parse(clean), bits = f.width * 8;
      final min = f.signed ? -(BigInt.one << (bits - 1)) : BigInt.zero;
      final max = (BigInt.one << (f.signed ? bits - 1 : bits)) - BigInt.one;
      if (number < min || number > max) {
        throw FormatException(
          '${f.name}: ${f.type} admite $min … $max. No se trunca ni se transforma el signo.',
        );
      }
      var v = number.isNegative ? number + (BigInt.one << bits) : number;
      for (var i = 0; i < f.width; i++) {
        d.setUint8(i, (v & BigInt.from(255)).toInt());
        v >>= 8;
      }
    }
    return d.buffer.asUint8List();
  }

  bool isChanged(FieldSpan field) => _changes.containsKey(field.start);
  void edit(int row, FieldSpan field, String text) =>
      editMany([(row, field, text)]);
  void editMany(
    List<(int, FieldSpan, String)> edits, {
    String title = 'Editar campos',
  }) {
    if (edits.length > 200000) {
      throw const FormatException('Demasiados cambios en una operación.');
    }
    final batch = <FieldChange>[];
    final seen = <int>{};
    for (final (row, field, text) in edits) {
      if (row < 0 ||
          row >= rows.length ||
          !fields(row).any(
            (f) =>
                f.start == field.start &&
                f.length == field.length &&
                f.spec.name == field.spec.name &&
                f.spec.type == field.spec.type,
          )) {
        throw const FormatException('El campo no pertenece al documento.');
      }
      if (!seen.add(field.start)) {
        throw const FormatException('Campo repetido en la misma operación.');
      }
      final after = validate(field, text),
          before =
              _changes[field.start]?.after ??
              Uint8List.sublistView(
                payload,
                field.start,
                field.start + field.length,
              );
      if (_equal(before, after)) continue;
      batch.add(
        FieldChange(
          row,
          field,
          Uint8List.fromList(before),
          after,
          _decode(field, before),
          _decode(field, after),
        ),
      );
    }
    if (batch.isEmpty) return;
    for (final change in batch) {
      _apply(change, true);
    }
    _undo.add(ChangeBatch(batch, title));
    _redo.clear();
    revision++;
  }

  void _apply(FieldChange c, bool forward) {
    final bytes = forward ? c.after : c.before;
    final orig = Uint8List.sublistView(
      payload,
      c.field.start,
      c.field.start + c.field.length,
    );
    if (_equal(bytes, orig)) {
      _changes.remove(c.field.start);
    } else {
      _changes[c.field.start] = FieldChange(
        c.row,
        c.field,
        Uint8List.fromList(orig),
        bytes,
        _decode(c.field, orig),
        _decode(c.field, bytes),
      );
    }
  }

  DocumentStructureState _state() => DocumentStructureState(
    payload,
    rows,
    parsedBytes,
    Map.of(_changes),
    _structural,
  );
  void _restore(DocumentStructureState state) {
    payload = state.payload;
    rows = state.rows;
    parsedBytes = state.parsedBytes;
    _changes
      ..clear()
      ..addAll(state.changes);
    _structural = state.structural;
  }

  void replaceStructure(EditDocument parsed, String title) {
    if (profile != 'binary' ||
        !complete ||
        !parsed.complete ||
        parsed.profile != profile ||
        parsed.path != path ||
        parsed.codec.encoding != codec.encoding ||
        parsed.dirty) {
      throw const FormatException(
        'La estructura candidata no coincide con la tabla DB validada.',
      );
    }
    if (payload.length > 32 * 1024 * 1024 ||
        _undo.where((b) => b.beforeStructure != null).length >= 16) {
      throw const FormatException(
        'Historial estructural completo. Guarda y vuelve a abrir antes de seguir creando filas.',
      );
    }
    final before = _state();
    payload = parsed.payload;
    rows = parsed.rows;
    parsedBytes = parsed.parsedBytes;
    _changes.clear();
    _structural = !_equal(payload, _initialPayload);
    _undo.add(ChangeBatch.structure(title, before, _state()));
    _redo.clear();
    revision++;
  }

  void undo() {
    if (_undo.isEmpty) return;
    final b = _undo.removeLast();
    if (b.beforeStructure != null) {
      _restore(b.beforeStructure!);
    } else {
      for (final c in b.changes.reversed) {
        _apply(c, false);
      }
    }
    _redo.add(b);
    revision++;
  }

  void redo() {
    if (_redo.isEmpty) return;
    final b = _redo.removeLast();
    if (b.afterStructure != null) {
      _restore(b.afterStructure!);
    } else {
      for (final c in b.changes) {
        _apply(c, true);
      }
    }
    _undo.add(b);
    revision++;
  }

  void discard() {
    payload = _initialPayload;
    rows = _initialRows;
    parsedBytes = _initialParsed;
    _structural = false;
    _changes.clear();
    _undo.clear();
    _redo.clear();
    revision++;
  }

  Uint8List exportPayload() {
    if (!dirty) return Uint8List.fromList(payload);
    final patches = _changes.values.toList()
      ..sort((a, b) => a.field.start.compareTo(b.field.start));
    final out = BytesBuilder(copy: false);
    var at = 0;
    for (final change in patches) {
      if (change.field.start < at ||
          change.field.start + change.field.length > payload.length) {
        throw const FormatException('Cambios solapados.');
      }
      out.add(Uint8List.sublistView(payload, at, change.field.start));
      out.add(change.after);
      at = change.field.start + change.field.length;
    }
    out.add(Uint8List.sublistView(payload, at));
    return out.takeBytes();
  }

  Uint8List exportBytes() {
    if (!dirty) return Uint8List.fromList(original);
    final out = exportPayload();
    return encrypted ? SeedData.encode(out, template: original) : out;
  }

  String exportPatch() {
    if (_structural) {
      throw const FormatException(
        'Hay filas nuevas o eliminadas. Guarda el archivo completo; un parche de campos no conserva cambios estructurales.',
      );
    }
    return const JsonEncoder.withIndent('  ').convert({
      'format': 'shaiya-editor-patch',
      'version': 1,
      'path': path,
      'sourceSha256': sha,
      'profile': profile,
      'encoding': codec.encoding.name,
      'changes': changes
          .map(
            (c) => {
              'row': c.row,
              'name': c.field.spec.name,
              'type': c.field.spec.type,
              'before': c.beforeText,
              'after': c.afterText,
            },
          )
          .toList(),
    });
  }

  void importPatch(String text) {
    if (_structural) {
      throw const FormatException(
        'No se importa un parche sobre una estructura con filas cambiadas.',
      );
    }
    final obj = jsonDecode(text);
    if (obj is! Map ||
        obj['format'] != 'shaiya-editor-patch' ||
        obj['version'] != 1 ||
        obj['sourceSha256'] != sha ||
        obj['profile'] != profile ||
        obj['encoding'] != codec.encoding.name) {
      throw const FormatException(
        'El parche no corresponde exactamente a este archivo, perfil y codificación.',
      );
    }
    if (obj['changes'] is! List || (obj['changes'] as List).length > 200000) {
      throw const FormatException('Parche fuera de límite.');
    }
    final edits = <(int, FieldSpan, String)>[];
    for (final c in obj['changes']) {
      if (c is! Map ||
          c['row'] is! int ||
          c['row'] < 0 ||
          c['row'] >= rows.length) {
        throw const FormatException('Registro de parche inválido.');
      }
      final candidates = fields(c['row'])
          .where((f) => f.spec.name == c['name'] && f.spec.type == c['type'])
          .toList();
      if (candidates.length != 1 ||
          c['after'] is! String ||
          read(candidates.single) != c['before']) {
        throw const FormatException(
          'El parche entra en conflicto con el valor actual.',
        );
      }
      edits.add((c['row'], candidates.single, c['after']));
    }
    editMany(edits, title: 'Importar parche verificado');
  }

  Map<String, Object?> report() => {
    'path': path,
    'profile': profile,
    'encoding': codec.encoding.name,
    'records': rows.length,
    'payloadBytes': payload.length,
    'parsedBytes': parsedBytes,
    'complete': complete,
    'originalSha256': sha,
    'encrypted': encrypted,
    'changes': changeCount,
    'structuralChanges': structuralChanges,
    'warnings': warnings,
    'authority': authority,
  };
  static bool _equal(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
