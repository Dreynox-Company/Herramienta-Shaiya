import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'formats.dart';
import 'seed_data.dart';

/// Read-only index reader. SAH carries names/offsets; SAF carries payloads.
/// Layout verified against Parsec's Data/Sah, SDirectory, SFile and fixtures.
class ArchiveEntry {
  final String path;
  final int offset, length, version;
  final int metadataOffset;
  final List<Uint8List> rawComponents;
  const ArchiveEntry(
    this.path,
    this.offset,
    this.length,
    this.version, {
    this.rawComponents = const [],
    this.metadataOffset = -1,
  });
}

class ArchiveFailure implements Exception {
  final String code, message;
  final Map<String, Object?> report;
  const ArchiveFailure(this.code, this.message, this.report);
  @override
  String toString() => '$code: $message. Exporta el diagnóstico de archivo.';
}

class ArchiveIndex {
  static const maxIndexBytes = 64 * 1024 * 1024;
  static const maxEntries = 200000;
  final Map<String, ArchiveEntry> entries;
  final Map<String, Object?> report;
  ArchiveIndex(this.entries, this.report);

  static Map<String, Object?> fingerprint(Uint8List bytes, int safLength) => {
    'schema': 1,
    'sourceMode': 'sah+saf',
    'indexBytes': bytes.length,
    'payloadBytes': safLength,
    'indexSha256': sha256.convert(bytes).toString(),
    'indexHeaderHex': bytes
        .take(64)
        .map((n) => n.toRadixString(16).padLeft(2, '0'))
        .join(),
    'privacy': 'Sin rutas absolutas, usuario ni claves. Solo metadatos, hasta 64 bytes de cabecera SAH y hasta 16 bytes de las últimas cabeceras de recurso; nada se envía automáticamente.',
  };

  static ArchiveIndex decode(Uint8List input, int safLength, {int? countXor}) {
    if (input.length > maxIndexBytes) {
      throw const ArchiveFailure('INDEX_TOO_LARGE', 'El índice excede 64 MiB', {
        'schema': 1,
      });
    }
    final info = fingerprint(input, safLength);
    final errors = <Map<String, Object>>[];
    if (safLength < 0 || input.length < 51) {
      throw ArchiveFailure(
        'TRUNCATED_INDEX',
        'Falta una cabecera SAH completa o el tamaño SAF',
        info,
      );
    }
    var bytes = input;
    final profiles = <String>[];
    var uniformXor = 0;
    if (input.length >= 40 &&
        ascii.decode(input.sublist(0, 40), allowInvalid: true) ==
            '0001CBCEBC5B2784D3FC9A2A9DB84D1C3FEB6E99') {
      try {
        bytes = SeedData.decode(input, verifyChecksum: true);
        profiles.add('SEED estándar con checksum');
      } catch (e) {
        throw ArchiveFailure(
          'SEED_INVALID',
          'El contenedor SEED no supera su comprobación de integridad',
          {...info, 'detail': e.toString()},
        );
      }
    }
    // A uniform single-byte XOR is identified by all three signature bytes,
    // then accepted ONLY after the entire directory tree and all ranges validate.
    if (bytes.length >= 3) {
      final key = bytes[0] ^ 0x53;
      if (key != 0 && (bytes[1] ^ key) == 0x41 && (bytes[2] ^ key) == 0x48) {
        uniformXor = key;
        bytes = Uint8List.fromList(bytes.map((b) => b ^ key).toList());
        profiles.add('XOR uniforme de índice; SAF sin transformar');
      }
    }
    final keys = countXor == null ? [0, 0x55] : [countXor];
    if (keys.any((k) => k < 0 || k > 255)) {
      throw ArgumentError.value(
        countXor,
        'countXor',
        'Debe estar entre 0 y 255',
      );
    }
    for (final key in keys) {
      try {
        final reader = _SahReader(bytes, safLength, key);
        final entries = reader.parse();
        final signature = ascii.decode(
          bytes.take(3).toList(),
          allowInvalid: true,
        );
        return ArchiveIndex(entries, {
          ...info,
          'status': 'index_validated',
          'uniformXor': uniformXor,
          'countXor': key,
          'signature': signature,
          'version': reader.version,
          'declaredEntries': reader.declared,
          'entries': entries.length,
          'directories': reader.directories,
          'profile': [
            ...profiles,
            key == 0
                ? 'SAH estándar'
                : 'XOR de contador de archivos por directorio 0x${key.toRadixString(16)}',
          ].join(' + '),
          'warnings': [
            if (signature != 'SAH') 'Firma personalizada; estructura y rangos del índice completos verificados.',
            ...reader.warnings,
          ],
          'attempts': errors,
          'payloadValidation': 'La integridad de cada recurso se comprueba al leerlo; el índice no incluye un checksum global SAF.',
        });
      } catch (e) {
        errors.add({
          'profile': key == 0
              ? 'standard'
              : 'directory-count-xor-${key.toRadixString(16)}',
          'error': e.toString(),
        });
      }
    }
    throw ArchiveFailure(
      'UNKNOWN_OR_DAMAGED_ARCHIVE',
      'El índice no coincide con las variantes admitidas. Puede estar truncado, cifrado con un esquema distinto o emparejado con otro SAF',
      {
        ...info,
        'status': 'rejected',
        'attempts': errors,
        'nextStep': 'Conservar ambos archivos originales. Compartir este informe y, con autorización, el SAH de muestra. No se prueba una clave desconocida ni se altera el archivo.',
      },
    );
  }
}

class _SahReader {
  final Bin r;
  final int safLength, countXor;
  int directories = 0, declared = 0, version = 0;
  Uint8List lastNameBytes = Uint8List(0);
  final Map<String, ArchiveEntry> entries = {};
  final Set<String> folders = {};
  final List<String> warnings = [];
  _SahReader(Uint8List bytes, this.safLength, this.countXor)
    : r = Bin(bytes, 'índice SAH');
  String name({bool root = false}) {
    final n = r.count(4096);
    r.need(n);
    final raw = r.bytes.sublist(r.offset, r.offset + n);
    lastNameBytes = Uint8List.fromList(raw);
    r.skip(n);
    if (raw.contains(0) && raw.indexOf(0) != raw.length - 1) {
      r.fail('Nombre con terminador interior.');
    }
    final b = raw.isNotEmpty && raw.last == 0
        ? raw.sublist(0, raw.length - 1)
        : raw;
    String value;
    try {
      value = utf8.decode(b);
    } catch (_) {
      value = latin1.decode(b);
    }
    // ASCII asset paths remain exact. Legacy bytes are reversible (Latin-1),
    // never replacement characters that silently alias different entries.
    if ((!root && value.isEmpty) ||
        value == '.' ||
        value == '..' ||
        RegExp(r'[\\/:\x00-\x1f\x7f]').hasMatch(value)) {
      r.fail('Componente de ruta inseguro.');
    }
    return value;
  }

  Map<String, ArchiveEntry> parse() {
    r.skip(3);
    version = r.i32();
    declared = r.count(ArchiveIndex.maxEntries);
    r.skip(40);
    directory('', 0);
    final tail = r.remaining;
    if (tail > 16 || r.bytes.sublist(r.offset).any((b) => b != 0)) {
      r.fail('Datos adicionales no reconocidos al final del índice.');
    }
    if (entries.length != declared) {
      r.fail(
        'El encabezado declara $declared recursos, pero se leyeron ${entries.length}.',
      );
    }
    if (entries.isEmpty) {
      warnings.add('Archivo válido vacío. No contiene una biblioteca jugable.');
    }
    return entries;
  }

  void directory(
    String parent,
    int depth, [
    List<Uint8List> parentBytes = const [],
  ]) {
    if (depth > 48 || ++directories > 25000) {
      r.fail('Árbol de carpetas fuera de límite.');
    }
    final own = name(root: depth == 0);
    final components = depth == 0
        ? <Uint8List>[]
        : [...parentBytes, Uint8List.fromList(lastNameBytes)];
    final folder = depth == 0 ? '' : (parent.isEmpty ? own : '$parent/$own');
    if (!folders.add(folder.toLowerCase())) {
      r.fail('Directorio duplicado: $folder');
    }
    final n = r.u32() ^ countXor;
    if (n > ArchiveIndex.maxEntries ||
        n + entries.length > ArchiveIndex.maxEntries) {
      r.fail('Recuento de recursos fuera de límite.');
    }
    // Each record needs at least 4 (name length) + 1 name byte + 16 metadata.
    if (n > r.remaining ~/ 21) r.fail('Recuento no cabe en el índice.');
    for (var i = 0; i < n; i++) {
      final label = name(),
          path = (folder.isEmpty ? label : '$folder/$label').toLowerCase();
      if (path.length > 8192) r.fail('Ruta demasiado larga.');
      final metadataOffset = r.offset;
      final offset = r.i64(), length = r.i32(), fileVersion = r.i32();
      if (offset < 0 ||
          length < 0 ||
          offset > safLength ||
          length > safLength - offset) {
        r.fail(
          'Rango fuera del SAF en $path (offset=$offset, bytes=$length, total=$safLength).',
        );
      }
      if (entries.containsKey(path)) {
        r.fail('Recurso ambiguo por mayúsculas o duplicado: $path');
      }
      entries[path] = ArchiveEntry(
        path,
        offset,
        length,
        fileVersion,
        rawComponents: [...components, Uint8List.fromList(lastNameBytes)],
        metadataOffset: metadataOffset,
      );
    }
    final sub = r.count(25000);
    for (var i = 0; i < sub; i++) {
      directory(folder, depth + 1, components);
    }
  }
}
