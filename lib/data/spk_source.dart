import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';
import 'package:zstandard/zstandard.dart';

const int _headerBytes = 128;
const int _recordBytes = 96;
const int _auxRecordBytes = 32;
const int _maxIndexBytes = 64 * 1024 * 1024;
const int _maxRecords = 200000;

class SpkFailure implements Exception {
  final String code;
  final String message;
  final Map<String, Object?> details;
  const SpkFailure(this.code, this.message, [this.details = const {}]);
  @override
  String toString() => '${code}: ${message}';
}

class SpkCryptoProfile {
  final String id;
  final Uint8List indexKey;
  final Uint8List resourceKey;
  SpkCryptoProfile(this.id, String indexKeyHex, String resourceKeyHex)
    : indexKey = _hex(indexKeyHex),
      resourceKey = _hex(resourceKeyHex);
}

/// Authenticated profiles observed from supported recent clients. A profile is
/// accepted only when AES-GCM authentication and every structural check pass.
final List<SpkCryptoProfile> spkCryptoProfiles = [
  SpkCryptoProfile(
    'recent-aes-gcm-zstd-01',
    '9a1f9c1bd3e9488dba7aa4543a466a5f',
    'c1552c44c3958bf204650aefbd110c72',
  ),
];

class SpkChunk {
  final int ordinal, dataOffset, storedBytes;
  final Uint8List metadata16;
  const SpkChunk({
    required this.ordinal,
    required this.dataOffset,
    required this.storedBytes,
    required this.metadata16,
  });
}

class SpkRecord {
  final int ordinal, dataOffset, storedBytes, decodedBytes, type, auxStart;
  final String entryId;
  final Uint8List metadata32;
  final List<SpkChunk> chunks;
  const SpkRecord({
    required this.ordinal,
    required this.entryId,
    required this.dataOffset,
    required this.storedBytes,
    required this.decodedBytes,
    required this.type,
    required this.auxStart,
    required this.metadata32,
    this.chunks = const [],
  });
  bool get extractable => type == 1;
  bool get chunked => type == 3;
  String get technicalName =>
      'resource_${ordinal.toString().padLeft(5, '0')}_${entryId}';
  Map<String, Object?> toJson() => {
    'ordinal': ordinal,
    'entryId': entryId,
    'dataOffset': dataOffset,
    'storedBytes': storedBytes,
    'decodedBytes': decodedBytes,
    'type': type,
    'auxStart': auxStart,
    'chunks': chunks.length,
  };
}

class SpkHeader {
  final int magic, version, indexOffset, indexBytes, decodedIndexBytes;
  final int recordCount, chunkSize, auxiliaryOffset, auxiliaryRecords;
  final Uint8List indexNonce, indexTag;
  const SpkHeader({
    required this.magic,
    required this.version,
    required this.indexOffset,
    required this.indexBytes,
    required this.decodedIndexBytes,
    required this.recordCount,
    required this.chunkSize,
    required this.indexNonce,
    required this.indexTag,
    required this.auxiliaryOffset,
    required this.auxiliaryRecords,
  });
  int get auxiliaryBytes => auxiliaryRecords * _auxRecordBytes;
  Map<String, Object?> toJson() => {
    'magic': '0x${magic.toRadixString(16).padLeft(8, '0')}',
    'version': '0x${version.toRadixString(16)}',
    'indexOffset': indexOffset,
    'indexBytes': indexBytes,
    'decodedIndexBytes': decodedIndexBytes,
    'recordCount': recordCount,
    'chunkSize': chunkSize,
    'auxiliaryOffset': auxiliaryOffset,
    'auxiliaryRecords': auxiliaryRecords,
    'auxiliaryBytes': auxiliaryBytes,
  };
}

class SpkExtractionProgress {
  final int completed, total, extracted, skipped, failed;
  final String? current;
  const SpkExtractionProgress({
    required this.completed,
    required this.total,
    required this.extracted,
    required this.skipped,
    required this.failed,
    this.current,
  });
}

class SpkSource {
  final String path;
  final int fileSize;
  final String headerSha256;
  final SpkHeader header;
  final SpkCryptoProfile profile;
  final List<SpkRecord> records;
  final Map<String, SpkRecord> byId;
  final Map<String, Object?> validation;
  int reads = 0, bytesRead = 0;
  final List<Map<String, Object?>> failures = [];

  SpkSource._({
    required this.path,
    required this.fileSize,
    required this.headerSha256,
    required this.header,
    required this.profile,
    required this.records,
    required this.validation,
  }) : byId = {for (final r in records) r.entryId: r};

  Iterable<SpkRecord> get resources =>
      records.where((r) => r.type == 1 || r.type == 3);
  Iterable<SpkRecord> get special =>
      records.where((r) => r.type != 1 && r.type != 3);
  int get simpleCount => records.where((r) => r.type == 1).length;
  int get chunkedCount => records.where((r) => r.type == 3).length;
  int get specialCount => records.length - simpleCount - chunkedCount;
  int get decodedBytesTotal =>
      resources.fold(0, (sum, r) => sum + r.decodedBytes);

  static Future<SpkSource> open(
    String path, {
    void Function(String)? progress,
  }) async {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      throw const SpkFailure(
        'SPK_PLATFORM',
        'La lectura directa SPK está habilitada primero en escritorio.',
      );
    }
    final file = File(path);
    if (!await file.exists()) {
      throw const SpkFailure('SPK_MISSING', 'No existe el archivo SPK.');
    }
    final size = await file.length();
    if (size < _headerBytes + 64) {
      throw const SpkFailure('SPK_TRUNCATED', 'El SPK es demasiado pequeño.');
    }
    final handle = await file.open(mode: FileMode.read);
    try {
      progress?.call('Leyendo cabecera SPK…');
      final headerBytes = await _readExact(handle, 0, _headerBytes);
      final header = _parseHeader(headerBytes, size);
      final headerHash = sha256.convert(headerBytes).toString();
      final encryptedIndex =
          await _readExact(handle, header.indexOffset, header.indexBytes);
      final auxiliaryRaw = await _readExact(
        handle,
        header.auxiliaryOffset,
        header.auxiliaryBytes,
      );
      Object? lastError;
      for (final candidate in spkCryptoProfiles) {
        try {
          progress?.call('Autenticando índice con ${candidate.id}…');
          final decrypted = _aesGcmDecrypt(
            candidate.indexKey,
            header.indexNonce,
            header.indexTag,
            encryptedIndex,
          );
          if (!_isZstd(decrypted)) {
            throw const SpkFailure(
              'SPK_INDEX_COMPRESSION',
              'El índice autenticado no contiene un frame Zstandard.',
            );
          }
          final decoded = await _zstd(decrypted);
          if (decoded.length != header.decodedIndexBytes) {
            throw SpkFailure(
              'SPK_INDEX_SIZE',
              'Tamaño de índice decodificado inesperado.',
              {'actual': decoded.length, 'expected': header.decodedIndexBytes},
            );
          }
          final parsed = _parseIndex(decoded, auxiliaryRaw, header, size);
          progress?.call(
            'SPK validado: ${parsed.records.length} registros · '
            '${parsed.simple} directos · ${parsed.chunked} fragmentados.',
          );
          return SpkSource._(
            path: file.absolute.path,
            fileSize: size,
            headerSha256: headerHash,
            header: header,
            profile: candidate,
            records: parsed.records,
            validation: parsed.validation,
          );
        } catch (e) {
          lastError = e;
        }
      }
      throw SpkFailure(
        'SPK_PROFILE_UNKNOWN',
        'La estructura SPK es válida, pero ningún perfil conocido autentica su índice.',
        {
          'header': header.toJson(),
          'headerSha256': headerHash,
          'lastError': lastError.toString(),
        },
      );
    } finally {
      await handle.close();
    }
  }

  Future<Uint8List> read(
    String entryId, {
    int limit = 64 * 1024 * 1024,
  }) async {
    final record = byId[entryId.toLowerCase()];
    if (record == null) {
      throw SpkFailure('SPK_ENTRY_MISSING', 'No existe el recurso ${entryId}.');
    }
    if (record.decodedBytes > limit || limit < 0) {
      throw SpkFailure(
        'SPK_ENTRY_LIMIT',
        'El recurso supera el límite de lectura.',
        {'decodedBytes': record.decodedBytes, 'limit': limit},
      );
    }
    if (record.type != 1) {
      throw SpkFailure(
        'SPK_CHUNK_PROFILE_PENDING',
        'El recurso ${entryId} está fragmentado. Se enumera sin ocultarlo, '
        'pero aún falta validar el nonce implícito de sus fragmentos.',
        {'chunks': record.chunks.length},
      );
    }
    final handle = await File(path).open(mode: FileMode.read);
    try {
      final cipher =
          await _readExact(handle, record.dataOffset, record.storedBytes);
      final decoded = await _decodeSimple(record, cipher);
      reads++;
      bytesRead += cipher.length;
      return decoded;
    } catch (e) {
      if (failures.length >= 100) failures.removeAt(0);
      failures.add({
        'entryId': record.entryId,
        'ordinal': record.ordinal,
        'offset': record.dataOffset,
        'storedBytes': record.storedBytes,
        'error': e.toString(),
      });
      rethrow;
    } finally {
      await handle.close();
    }
  }

  Future<Uint8List> _decodeSimple(SpkRecord record, Uint8List cipher) async {
    if (record.metadata32.length != 32) {
      throw const SpkFailure('SPK_METADATA', 'Metadatos AES-GCM incompletos.');
    }
    final nonce = Uint8List.sublistView(record.metadata32, 0, 12);
    final tag = Uint8List.sublistView(record.metadata32, 12, 28);
    final flags =
        ByteData.sublistView(record.metadata32, 28, 32)
            .getUint32(0, Endian.little);
    if (flags != 0) {
      throw SpkFailure(
        'SPK_FLAGS',
        'Flags de recurso no reconocidos.',
        {'flags': flags, 'entryId': record.entryId},
      );
    }
    final plain = _aesGcmDecrypt(profile.resourceKey, nonce, tag, cipher);
    final decoded = _isZstd(plain) ? await _zstd(plain) : plain;
    if (decoded.length != record.decodedBytes) {
      throw SpkFailure(
        'SPK_DECODED_SIZE',
        'El tamaño decodificado no coincide con el índice.',
        {
          'entryId': record.entryId,
          'actual': decoded.length,
          'expected': record.decodedBytes,
        },
      );
    }
    return decoded;
  }

  Future<Map<String, Object?>> extractAll(
    Directory destination, {
    void Function(SpkExtractionProgress)? progress,
    bool Function()? cancelled,
  }) async {
    if (await destination.exists()) {
      final any = await destination.list(followLinks: false).take(1).toList();
      if (any.isNotEmpty) {
        throw const SpkFailure(
          'SPK_OUTPUT_NOT_EMPTY',
          'La carpeta de extracción debe estar vacía.',
        );
      }
    } else {
      await destination.create(recursive: true);
    }
    final rows = resources.toList(growable: false);
    var extracted = 0, skipped = 0, failed = 0, completed = 0;
    final manifest = <Map<String, Object?>>[];
    final handle = await File(path).open(mode: FileMode.read);
    try {
      for (final record in rows) {
        if (cancelled?.call() == true) {
          manifest.add({'status': 'cancelled', 'completed': completed});
          break;
        }
        String status = 'extracted';
        String? relative, error;
        if (record.type != 1) {
          skipped++;
          status = 'chunked_pending';
        } else {
          try {
            final cipher =
                await _readExact(handle, record.dataOffset, record.storedBytes);
            final decoded = await _decodeSimple(record, cipher);
            final ext = detectSpkExtension(decoded);
            final bucket = record.entryId.substring(0, 2);
            relative = 'Recursos/${bucket}/${record.technicalName}${ext}';
            final target = File(
              '${destination.path}${Platform.pathSeparator}'
              '${relative.replaceAll('/', Platform.pathSeparator)}',
            );
            await target.parent.create(recursive: true);
            await target.writeAsBytes(decoded, flush: false);
            extracted++;
            reads++;
            bytesRead += cipher.length;
          } catch (e) {
            failed++;
            status = 'failed';
            error = e.toString();
          }
        }
        completed++;
        manifest.add({
          ...record.toJson(),
          'status': status,
          if (relative != null) 'output': relative,
          if (error != null) 'error': error,
        });
        progress?.call(
          SpkExtractionProgress(
            completed: completed,
            total: rows.length,
            extracted: extracted,
            skipped: skipped,
            failed: failed,
            current: record.entryId,
          ),
        );
      }
    } finally {
      await handle.close();
    }
    final report = {
      'schema': 1,
      'source': {
        'file': _fileBaseName(path),
        'bytes': fileSize,
        'headerSha256': headerSha256,
        'profile': profile.id,
      },
      'catalog': diagnostics(),
      'result': {
        'total': rows.length,
        'completed': completed,
        'extracted': extracted,
        'skippedChunked': skipped,
        'failed': failed,
      },
      'entries': manifest,
    };
    await File(
      '${destination.path}${Platform.pathSeparator}SPK_MANIFEST.json',
    ).writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
      flush: true,
    );
    return report;
  }

  Map<String, Object?> diagnostics() => {
    'schema': 1,
    'sourceMode': 'data.spk',
    'fileBytes': fileSize,
    'headerSha256': headerSha256,
    'profile': profile.id,
    'header': header.toJson(),
    'records': records.length,
    'simpleResources': simpleCount,
    'chunkedResources': chunkedCount,
    'specialRecords': specialCount,
    'decodedBytesTotal': decodedBytesTotal,
    'validation': validation,
    'reads': reads,
    'bytesRead': bytesRead,
    'failures': failures,
    'limitations': [
      if (chunkedCount > 0)
        'Los recursos tipo 3 se enumeran y preservan en el manifiesto, '
        'pero requieren validar su nonce implícito antes de extraerlos.',
      'El índice observado contiene IDs técnicos de 64 bits, no rutas '
        'originales en claro. Se usan nombres técnicos hasta disponer de un '
        'resolvedor de nombres validado.',
    ],
  };
}

class _ParsedIndex {
  final List<SpkRecord> records;
  final int simple, chunked;
  final Map<String, Object?> validation;
  const _ParsedIndex(this.records, this.simple, this.chunked, this.validation);
}

SpkHeader _parseHeader(Uint8List bytes, int fileSize) {
  if (bytes.length != _headerBytes) {
    throw const SpkFailure('SPK_HEADER', 'Cabecera SPK incompleta.');
  }
  final d = ByteData.sublistView(bytes);
  final magic = d.getUint32(0, Endian.little);
  final version = d.getUint32(4, Endian.little);
  final indexOffset = d.getUint64(8, Endian.little);
  final indexBytes = d.getUint64(16, Endian.little);
  final decodedIndexBytes = d.getUint64(24, Endian.little);
  final recordCount = d.getUint32(32, Endian.little);
  final chunkSize = d.getUint32(36, Endian.little);
  final auxiliaryOffset = d.getUint32(100, Endian.little);
  final auxiliaryRecords = d.getUint32(108, Endian.little);
  if (magic != 0x9e7bd34c ||
      version != 0x00030000 ||
      indexBytes <= 0 ||
      indexBytes > _maxIndexBytes ||
      decodedIndexBytes <= 0 ||
      decodedIndexBytes > _maxIndexBytes ||
      recordCount <= 0 ||
      recordCount > _maxRecords ||
      decodedIndexBytes != recordCount * _recordBytes ||
      chunkSize <= 0 ||
      auxiliaryRecords > _maxRecords ||
      auxiliaryOffset < _headerBytes ||
      indexOffset < auxiliaryOffset ||
      auxiliaryOffset + auxiliaryRecords * _auxRecordBytes > indexOffset ||
      indexOffset + indexBytes > fileSize) {
    throw SpkFailure(
      'SPK_HEADER_PROFILE',
      'La cabecera no coincide con la estructura SPK reciente validada.',
      {
        'magic': magic,
        'version': version,
        'indexOffset': indexOffset,
        'indexBytes': indexBytes,
        'decodedIndexBytes': decodedIndexBytes,
        'recordCount': recordCount,
        'chunkSize': chunkSize,
        'auxiliaryOffset': auxiliaryOffset,
        'auxiliaryRecords': auxiliaryRecords,
        'fileBytes': fileSize,
      },
    );
  }
  return SpkHeader(
    magic: magic,
    version: version,
    indexOffset: indexOffset,
    indexBytes: indexBytes,
    decodedIndexBytes: decodedIndexBytes,
    recordCount: recordCount,
    chunkSize: chunkSize,
    indexNonce: Uint8List.sublistView(bytes, 40, 52),
    indexTag: Uint8List.sublistView(bytes, 52, 68),
    auxiliaryOffset: auxiliaryOffset,
    auxiliaryRecords: auxiliaryRecords,
  );
}

_ParsedIndex _parseIndex(
  Uint8List decoded,
  Uint8List auxiliaryRaw,
  SpkHeader header,
  int fileSize,
) {
  if (decoded.length != header.recordCount * _recordBytes) {
    throw const SpkFailure(
      'SPK_INDEX_RECORDS',
      'El índice no contiene el número declarado de registros.',
    );
  }
  if (auxiliaryRaw.length != header.auxiliaryBytes) {
    throw const SpkFailure('SPK_AUXILIARY', 'Tabla auxiliar truncada.');
  }
  final aux = <SpkChunk>[];
  final auxData = ByteData.sublistView(auxiliaryRaw);
  for (var i = 0; i < header.auxiliaryRecords; i++) {
    final o = i * _auxRecordBytes;
    final dataOffset = auxData.getUint64(o, Endian.little);
    final stored = auxData.getUint32(o + 8, Endian.little);
    final mirror = auxData.getUint32(o + 12, Endian.little);
    if (stored != mirror ||
        dataOffset < _headerBytes ||
        dataOffset + stored > header.auxiliaryOffset) {
      throw SpkFailure(
        'SPK_AUX_RANGE',
        'Fragmento auxiliar fuera de la región de datos.',
        {'ordinal': i, 'offset': dataOffset, 'stored': stored},
      );
    }
    aux.add(
      SpkChunk(
        ordinal: i,
        dataOffset: dataOffset,
        storedBytes: stored,
        metadata16: Uint8List.sublistView(auxiliaryRaw, o + 16, o + 32),
      ),
    );
  }

  final records = <SpkRecord>[];
  final seen = <String>{};
  final data = ByteData.sublistView(decoded);
  var simple = 0, chunked = 0, auxCursor = 0;
  for (var i = 0; i < header.recordCount; i++) {
    final o = i * _recordBytes;
    final entryId = data
        .getUint64(o, Endian.little)
        .toRadixString(16)
        .padLeft(16, '0');
    final offset = data.getUint64(o + 8, Endian.little);
    final stored = data.getUint64(o + 16, Endian.little);
    final mirror = data.getUint64(o + 24, Endian.little);
    final decodedBytes = data.getUint64(o + 32, Endian.little);
    final type = data.getUint32(o + 40, Endian.little);
    final auxStart = data.getUint32(o + 44, Endian.little);
    final metadata = Uint8List.sublistView(decoded, o + 48, o + 80);
    final trailing = Uint8List.sublistView(decoded, o + 80, o + 96);
    if (stored != mirror || !trailing.every((b) => b == 0)) {
      throw SpkFailure(
        'SPK_RECORD_LAYOUT',
        'Registro inconsistente.',
        {'ordinal': i},
      );
    }
    if (!seen.add(entryId)) {
      throw SpkFailure(
        'SPK_DUPLICATE_ID',
        'ID técnico duplicado.',
        {'entryId': entryId},
      );
    }
    List<SpkChunk> chunks = const [];
    if (type == 1 || type == 3) {
      if (offset < _headerBytes ||
          offset + stored > header.auxiliaryOffset) {
        throw SpkFailure(
          'SPK_RECORD_RANGE',
          'Recurso fuera de la región de datos.',
          {'ordinal': i},
        );
      }
    }
    if (type == 1) {
      simple++;
      if (auxStart != 0xffffffff) {
        throw SpkFailure(
          'SPK_SINGLE_AUX',
          'Recurso simple con auxiliar inesperado.',
          {'ordinal': i},
        );
      }
    } else if (type == 3) {
      chunked++;
      final count =
          ByteData.sublistView(metadata, 28, 32).getUint32(0, Endian.little);
      if (auxStart != auxCursor ||
          count <= 0 ||
          auxStart + count > aux.length) {
        throw SpkFailure(
          'SPK_CHUNK_CHAIN',
          'Cadena de fragmentos no contigua.',
          {'ordinal': i, 'auxStart': auxStart, 'count': count},
        );
      }
      chunks = List.unmodifiable(aux.sublist(auxStart, auxStart + count));
      if (chunks.first.dataOffset != offset ||
          chunks.fold<int>(0, (n, c) => n + c.storedBytes) != stored) {
        throw SpkFailure(
          'SPK_CHUNK_SIZE',
          'La cadena auxiliar no reproduce el rango del recurso.',
          {'ordinal': i},
        );
      }
      for (var j = 1; j < chunks.length; j++) {
        if (chunks[j - 1].dataOffset + chunks[j - 1].storedBytes !=
            chunks[j].dataOffset) {
          throw SpkFailure(
            'SPK_CHUNK_GAP',
            'Hueco o solapamiento entre fragmentos.',
            {'ordinal': i, 'chunk': j},
          );
        }
      }
      auxCursor += count;
    }
    records.add(
      SpkRecord(
        ordinal: i,
        entryId: entryId,
        dataOffset: offset,
        storedBytes: stored,
        decodedBytes: decodedBytes,
        type: type,
        auxStart: auxStart,
        metadata32: Uint8List.fromList(metadata),
        chunks: chunks,
      ),
    );
  }
  if (auxCursor != aux.length) {
    throw const SpkFailure(
      'SPK_AUX_UNUSED',
      'No todos los auxiliares pertenecen a recursos fragmentados.',
    );
  }
  final actual = records.where((r) => r.type == 1 || r.type == 3).toList()
    ..sort((a, b) => a.dataOffset.compareTo(b.dataOffset));
  if (actual.isEmpty || actual.first.dataOffset != _headerBytes) {
    throw const SpkFailure(
      'SPK_COVERAGE_START',
      'La región de datos no empieza tras la cabecera.',
    );
  }
  for (var i = 1; i < actual.length; i++) {
    if (actual[i - 1].dataOffset + actual[i - 1].storedBytes !=
        actual[i].dataOffset) {
      throw SpkFailure(
        'SPK_COVERAGE_GAP',
        'La región de datos tiene huecos o solapamientos.',
        {'ordinal': actual[i].ordinal},
      );
    }
  }
  final end = actual.last.dataOffset + actual.last.storedBytes;
  if (end != header.auxiliaryOffset) {
    throw SpkFailure(
      'SPK_COVERAGE_END',
      'La región de datos no termina en la tabla auxiliar.',
      {'actual': end, 'expected': header.auxiliaryOffset},
    );
  }
  return _ParsedIndex(records, simple, chunked, {
    'fileBytes': fileSize,
    'recordBytes': _recordBytes,
    'recordCount': records.length,
    'resourceRecordCount': actual.length,
    'simpleResources': simple,
    'chunkedResources': chunked,
    'specialRecords': records.length - actual.length,
    'auxiliaryRecords': aux.length,
    'auxiliaryChainValidated': true,
    'dataCoverageStart': actual.first.dataOffset,
    'dataCoverageEnd': end,
    'dataCoverageContiguous': true,
    'indexAuthenticated': true,
    'indexCompression': 'zstd',
  });
}

Uint8List _aesGcmDecrypt(
  Uint8List key,
  Uint8List nonce,
  Uint8List tag,
  Uint8List cipherText,
) {
  try {
    final cipher = GCMBlockCipher(AESEngine());
    cipher.init(
      false,
      AEADParameters(KeyParameter(key), tag.length * 8, nonce, Uint8List(0)),
    );
    final input = Uint8List(cipherText.length + tag.length)
      ..setRange(0, cipherText.length, cipherText)
      ..setRange(cipherText.length, cipherText.length + tag.length, tag);
    return cipher.process(input);
  } catch (e) {
    throw SpkFailure(
      'SPK_AUTH',
      'AES-GCM rechazó el bloque.',
      {'detail': e.toString()},
    );
  }
}

Future<Uint8List> _zstd(Uint8List input) async {
  final out = await Zstandard().decompress(input);
  if (out == null) {
    throw const SpkFailure(
      'SPK_ZSTD',
      'Zstandard no pudo descomprimir el bloque autenticado.',
    );
  }
  return out;
}

bool _isZstd(Uint8List b) =>
    b.length >= 4 &&
    b[0] == 0x28 &&
    b[1] == 0xb5 &&
    b[2] == 0x2f &&
    b[3] == 0xfd;

Future<Uint8List> _readExact(
  RandomAccessFile handle,
  int offset,
  int length,
) async {
  if (offset < 0 || length < 0) {
    throw const SpkFailure('SPK_RANGE', 'Rango de lectura inválido.');
  }
  await handle.setPosition(offset);
  final out = Uint8List(length);
  var done = 0;
  while (done < length) {
    final n = await handle.readInto(out, done, length);
    if (n == 0) {
      throw const SpkFailure(
        'SPK_EOF',
        'Fin prematuro durante una lectura por rango.',
      );
    }
    done += n;
  }
  return out;
}

Uint8List _hex(String value) {
  if (value.length.isOdd || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(value)) {
    throw ArgumentError.value(value, 'hex');
  }
  return Uint8List.fromList([
    for (var i = 0; i < value.length; i += 2)
      int.parse(value.substring(i, i + 2), radix: 16),
  ]);
}

String detectSpkExtension(Uint8List bytes) {
  if (bytes.length >= 4 &&
      bytes[0] == 0x44 &&
      bytes[1] == 0x44 &&
      bytes[2] == 0x53 &&
      bytes[3] == 0x20) {
    return '.dds';
  }
  if (bytes.length >= 12 &&
      ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
      ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WAVE') {
    return '.wav';
  }
  if (bytes.length >= 4 &&
      ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'OggS') {
    return '.ogg';
  }
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      ascii.decode(bytes.sublist(1, 4), allowInvalid: true) == 'PNG') {
    return '.png';
  }
  if (bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xd8) {
    return '.jpg';
  }
  if (bytes.length >= 2 && bytes[0] == 0x42 && bytes[1] == 0x4d) {
    return '.bmp';
  }
  final head = utf8.decode(bytes.take(128).toList(), allowMalformed: true).trimLeft();
  if (head.startsWith('<?xml') || head.startsWith('<Workbook')) return '.xml';
  if (_looksUtf16LeText(bytes) || _looksUtf8Text(bytes)) return '.txt';
  return '.bin';
}

bool _looksUtf16LeText(Uint8List bytes) {
  if (bytes.length < 4) return false;
  if (bytes[0] == 0xff && bytes[1] == 0xfe) return true;
  final sample = bytes.take(256).toList();
  if (sample.length < 16) return false;
  var zeroOdd = 0, odd = 0;
  for (var i = 1; i < sample.length; i += 2) {
    odd++;
    if (sample[i] == 0) zeroOdd++;
  }
  return odd > 0 && zeroOdd / odd > .55;
}

bool _looksUtf8Text(Uint8List bytes) {
  if (bytes.isEmpty) return false;
  final sample = bytes.take(512).toList();
  var controls = 0;
  for (final b in sample) {
    if (b == 0) return false;
    if (b < 9 || (b > 13 && b < 32)) controls++;
  }
  if (controls > sample.length ~/ 20) return false;
  try {
    utf8.decode(sample);
    return true;
  } catch (_) {
    return false;
  }
}

String _fileBaseName(String path) =>
    path.replaceAll('\\', '/').split('/').last;
