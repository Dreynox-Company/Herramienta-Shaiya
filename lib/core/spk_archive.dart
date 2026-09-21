import 'dart:typed_data';

const int spkMagic = 0x9e7bd34c;
const int spkVersion3 = 0x00030000;
const int spkHeaderBytes = 128;
const int spkFooterBytes = 64;
const int spkRecordBytes = 96;
const int spkAuxRecordBytes = 32;
const int spkMaxRecords = 200000;
const int spkMaxIndexBytes = 64 * 1024 * 1024;

int _u32(Uint8List b, int o) =>
    ByteData.sublistView(b, o, o + 4).getUint32(0, Endian.little);
int _u64(Uint8List b, int o) =>
    ByteData.sublistView(b, o, o + 8).getUint64(0, Endian.little);

String spkHex(Iterable<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List spkHexBytes(String value, {int? expectedBytes}) {
  final clean = value.replaceAll(RegExp(r'\s+'), '').toLowerCase();
  if (clean.isEmpty ||
      clean.length.isOdd ||
      !RegExp(r'^[0-9a-f]+$').hasMatch(clean)) {
    throw const FormatException('Valor hexadecimal inválido.');
  }
  final out = Uint8List(clean.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
  }
  if (expectedBytes != null && out.length != expectedBytes) {
    throw FormatException(
      'Longitud hexadecimal inválida: ${out.length} bytes.',
    );
  }
  return out;
}

class SpkFailure implements Exception {
  final String code;
  final String message;
  final Map<String, Object?> report;
  const SpkFailure(this.code, this.message, [this.report = const {}]);

  @override
  String toString() => '$code: $message';
}

class SpkHeader {
  final int version;
  final int indexOffset;
  final int indexStoredBytes;
  final int indexDecodedBytes;
  final int recordCount;
  final int blockBytes;
  final int auxiliaryOffset;
  final int auxiliaryCount;
  final Uint8List indexNonce;
  final Uint8List indexTag;

  const SpkHeader({
    required this.version,
    required this.indexOffset,
    required this.indexStoredBytes,
    required this.indexDecodedBytes,
    required this.recordCount,
    required this.blockBytes,
    required this.auxiliaryOffset,
    required this.auxiliaryCount,
    required this.indexNonce,
    required this.indexTag,
  });

  static SpkHeader parse(Uint8List bytes, int fileBytes) {
    if (bytes.length != spkHeaderBytes) {
      throw const SpkFailure(
        'SPK_HEADER_SIZE',
        'La cabecera SPK no tiene 128 bytes.',
      );
    }
    if (_u32(bytes, 0) != spkMagic) {
      throw SpkFailure('SPK_MAGIC', 'Firma SPK no reconocida.', {
        'magic': _u32(bytes, 0),
      });
    }
    final version = _u32(bytes, 4);
    if (version != spkVersion3) {
      throw SpkFailure('SPK_VERSION', 'Versión SPK todavía no compatible.', {
        'version': version,
      });
    }
    final indexOffset = _u64(bytes, 8);
    final stored = _u64(bytes, 16);
    final decoded = _u64(bytes, 24);
    final count = _u32(bytes, 32);
    final block = _u32(bytes, 36);
    final auxOffset = _u64(bytes, 100);
    final auxCount = _u32(bytes, 108);

    final sane =
        count > 0 &&
        count <= spkMaxRecords &&
        stored > 0 &&
        stored <= spkMaxIndexBytes &&
        decoded > 0 &&
        decoded <= spkMaxIndexBytes &&
        decoded == count * spkRecordBytes &&
        block > 0 &&
        indexOffset >= spkHeaderBytes &&
        auxOffset >= spkHeaderBytes &&
        auxOffset <= indexOffset &&
        indexOffset + stored <= fileBytes - spkFooterBytes &&
        auxOffset + auxCount * spkAuxRecordBytes <= indexOffset;
    if (!sane) {
      throw SpkFailure(
        'SPK_GEOMETRY',
        'Offsets, tamaños o contadores SPK inconsistentes.',
        {
          'fileBytes': fileBytes,
          'indexOffset': indexOffset,
          'indexStoredBytes': stored,
          'indexDecodedBytes': decoded,
          'recordCount': count,
          'blockBytes': block,
          'auxiliaryOffset': auxOffset,
          'auxiliaryCount': auxCount,
        },
      );
    }
    return SpkHeader(
      version: version,
      indexOffset: indexOffset,
      indexStoredBytes: stored,
      indexDecodedBytes: decoded,
      recordCount: count,
      blockBytes: block,
      auxiliaryOffset: auxOffset,
      auxiliaryCount: auxCount,
      indexNonce: Uint8List.fromList(bytes.sublist(40, 52)),
      indexTag: Uint8List.fromList(bytes.sublist(52, 68)),
    );
  }

  Map<String, Object?> toJson() => {
    'version': version,
    'indexOffset': indexOffset,
    'indexStoredBytes': indexStoredBytes,
    'indexDecodedBytes': indexDecodedBytes,
    'recordCount': recordCount,
    'blockBytes': blockBytes,
    'auxiliaryOffset': auxiliaryOffset,
    'auxiliaryCount': auxiliaryCount,
    'indexNonceHex': spkHex(indexNonce),
    'indexTagHex': spkHex(indexTag),
  };
}

class SpkRecord {
  final int ordinal;
  final int entryId;
  final int dataOffset;
  final int storedBytes;
  final int decodedBytes;
  final int recordType;
  final int auxiliaryStart;
  final int chunkCount;
  final Uint8List metadata;

  const SpkRecord({
    required this.ordinal,
    required this.entryId,
    required this.dataOffset,
    required this.storedBytes,
    required this.decodedBytes,
    required this.recordType,
    required this.auxiliaryStart,
    required this.chunkCount,
    required this.metadata,
  });

  String get idHex => entryId.toRadixString(16).padLeft(16, '0');
  bool get simple => recordType == 1;
  bool get fragmented => recordType == 3;
  bool get resource => simple || fragmented;

  Uint8List get nonce =>
      simple ? Uint8List.fromList(metadata.sublist(0, 12)) : Uint8List(0);
  Uint8List get tag =>
      simple ? Uint8List.fromList(metadata.sublist(12, 28)) : Uint8List(0);
  int get flags => simple ? _u32(metadata, 28) : 0;

  Map<String, Object?> toJson() => {
    'ordinal': ordinal,
    'entryId': idHex,
    'dataOffset': dataOffset,
    'storedBytes': storedBytes,
    'decodedBytes': decodedBytes,
    'recordType': recordType,
    'auxiliaryStart': auxiliaryStart,
    'chunkCount': chunkCount,
    'metadataHex': spkHex(metadata),
  };
}

class SpkAuxRecord {
  final int ordinal;
  final int dataOffset;
  final int storedBytes;
  final Uint8List metadata;

  const SpkAuxRecord({
    required this.ordinal,
    required this.dataOffset,
    required this.storedBytes,
    required this.metadata,
  });
}

class SpkIndex {
  final SpkHeader header;
  final List<SpkRecord> records;
  final List<SpkAuxRecord> auxiliary;
  final String encryptedIndexSha256;
  final String decodedIndexSha256;

  const SpkIndex({
    required this.header,
    required this.records,
    required this.auxiliary,
    required this.encryptedIndexSha256,
    required this.decodedIndexSha256,
  });

  Iterable<SpkRecord> get resources => records.where((e) => e.resource);
  Iterable<SpkRecord> get simpleResources => records.where((e) => e.simple);
  Iterable<SpkRecord> get fragmentedResources =>
      records.where((e) => e.fragmented);
  Iterable<SpkRecord> get specialRecords => records.where((e) => !e.resource);

  static List<SpkRecord> parseRecords(Uint8List decoded, SpkHeader header) {
    if (decoded.length != header.indexDecodedBytes ||
        decoded.length % spkRecordBytes != 0) {
      throw const SpkFailure(
        'SPK_INDEX_LENGTH',
        'El índice descifrado no tiene la longitud declarada.',
      );
    }
    final out = <SpkRecord>[];
    for (var i = 0; i < header.recordCount; i++) {
      final o = i * spkRecordBytes;
      final stored = _u64(decoded, o + 16);
      final mirror = _u64(decoded, o + 24);
      final trailing = decoded.sublist(o + 80, o + 96);
      if (stored != mirror || trailing.any((b) => b != 0)) {
        throw SpkFailure('SPK_RECORD_INTEGRITY', 'Registro SPK inválido.', {
          'ordinal': i,
        });
      }
      final type = _u32(decoded, o + 40);
      final metadata = Uint8List.fromList(decoded.sublist(o + 48, o + 80));
      out.add(
        SpkRecord(
          ordinal: i,
          entryId: _u64(decoded, o),
          dataOffset: _u64(decoded, o + 8),
          storedBytes: stored,
          decodedBytes: _u64(decoded, o + 32),
          recordType: type,
          auxiliaryStart: _u32(decoded, o + 44),
          chunkCount: type == 3 ? _u32(metadata, 28) : 0,
          metadata: metadata,
        ),
      );
    }
    return out;
  }

  static List<SpkAuxRecord> parseAuxiliary(Uint8List bytes, SpkHeader header) {
    if (bytes.length != header.auxiliaryCount * spkAuxRecordBytes) {
      throw const SpkFailure(
        'SPK_AUX_LENGTH',
        'La tabla auxiliar SPK está incompleta.',
      );
    }
    final out = <SpkAuxRecord>[];
    for (var i = 0; i < header.auxiliaryCount; i++) {
      final o = i * spkAuxRecordBytes;
      final offset = _u64(bytes, o);
      final stored = _u32(bytes, o + 8);
      final mirror = _u32(bytes, o + 12);
      if (stored != mirror ||
          offset < spkHeaderBytes ||
          offset + stored > header.auxiliaryOffset) {
        throw SpkFailure(
          'SPK_AUX_RANGE',
          'Fragmento auxiliar fuera de la región de datos.',
          {'ordinal': i, 'offset': offset, 'bytes': stored},
        );
      }
      out.add(
        SpkAuxRecord(
          ordinal: i,
          dataOffset: offset,
          storedBytes: stored,
          metadata: Uint8List.fromList(bytes.sublist(o + 16, o + 32)),
        ),
      );
    }
    return out;
  }

  static void validateRelationships(
    List<SpkRecord> records,
    List<SpkAuxRecord> auxiliary,
    SpkHeader header,
  ) {
    final resources = records.where((e) => e.resource).toList()
      ..sort((a, b) => a.dataOffset.compareTo(b.dataOffset));
    if (resources.isEmpty ||
        resources.first.dataOffset != spkHeaderBytes ||
        resources.last.dataOffset + resources.last.storedBytes !=
            header.auxiliaryOffset) {
      throw const SpkFailure(
        'SPK_DATA_COVERAGE',
        'Los recursos no cubren exactamente la región de datos.',
      );
    }
    for (var i = 0; i + 1 < resources.length; i++) {
      if (resources[i].dataOffset + resources[i].storedBytes !=
          resources[i + 1].dataOffset) {
        throw SpkFailure(
          'SPK_DATA_GAP',
          'Existe un hueco o solapamiento entre recursos.',
          {'left': resources[i].ordinal, 'right': resources[i + 1].ordinal},
        );
      }
    }

    var cursor = 0;
    for (final row in records.where((e) => e.fragmented)) {
      if (row.auxiliaryStart != cursor ||
          row.chunkCount <= 0 ||
          cursor + row.chunkCount > auxiliary.length) {
        throw SpkFailure('SPK_CHUNK_CHAIN', 'Cadena de fragmentos inválida.', {
          'entryId': row.idHex,
        });
      }
      final parts = auxiliary.sublist(cursor, cursor + row.chunkCount);
      final total = parts.fold<int>(0, (n, e) => n + e.storedBytes);
      if (total != row.storedBytes ||
          parts.first.dataOffset != row.dataOffset) {
        throw SpkFailure(
          'SPK_CHUNK_SIZE',
          'Los fragmentos no reconstruyen el recurso.',
          {'entryId': row.idHex},
        );
      }
      for (var i = 0; i + 1 < parts.length; i++) {
        if (parts[i].dataOffset + parts[i].storedBytes !=
            parts[i + 1].dataOffset) {
          throw SpkFailure('SPK_CHUNK_GAP', 'Fragmentos no contiguos.', {
            'entryId': row.idHex,
          });
        }
      }
      cursor += row.chunkCount;
    }
    if (cursor != auxiliary.length) {
      throw const SpkFailure(
        'SPK_AUX_UNUSED',
        'La tabla auxiliar contiene fragmentos sin propietario.',
      );
    }
  }

  Map<String, Object?> summary() => {
    'header': header.toJson(),
    'encryptedIndexSha256': encryptedIndexSha256,
    'decodedIndexSha256': decodedIndexSha256,
    'records': records.length,
    'resources': resources.length,
    'simpleResources': simpleResources.length,
    'fragmentedResources': fragmentedResources.length,
    'specialRecords': specialRecords.length,
    'auxiliaryRecords': auxiliary.length,
  };
}

class SpkCryptoProfile {
  final String profileId;
  final String indexSha256;
  final Uint8List indexSecret;
  final Uint8List? resourceSecret;
  final bool resourceKeyIsIndexKey;
  final String chunkNonceRule;

  const SpkCryptoProfile({
    required this.profileId,
    required this.indexSha256,
    required this.indexSecret,
    required this.resourceSecret,
    required this.resourceKeyIsIndexKey,
    required this.chunkNonceRule,
  });

  Uint8List? get effectiveResourceSecret =>
      resourceSecret ?? (resourceKeyIsIndexKey ? indexSecret : null);

  factory SpkCryptoProfile.fromJson(Map<String, dynamic> json) {
    if (json['secretHex'] is String && json['target'] == 'index') {
      return SpkCryptoProfile(
        profileId: (json['profileId'] ?? 'observed-index').toString(),
        indexSha256: (json['indexSha256'] ?? '').toString().toLowerCase(),
        indexSecret: spkHexBytes(
          json['secretHex'].toString(),
          expectedBytes: 16,
        ),
        resourceSecret: json['resourceSecretHex'] is String
            ? spkHexBytes(
                json['resourceSecretHex'].toString(),
                expectedBytes: 16,
              )
            : null,
        resourceKeyIsIndexKey: json['resourceKeyIsIndexKey'] == true,
        chunkNonceRule: (json['chunkNonceRule'] ?? 'unsupported').toString(),
      );
    }
    final index = Map<String, dynamic>.from(
      (json['index'] as Map?) ?? const {},
    );
    final resources = Map<String, dynamic>.from(
      (json['resources'] as Map?) ?? const {},
    );
    return SpkCryptoProfile(
      profileId: (json['profileId'] ?? 'local-profile').toString(),
      indexSha256: (json['indexSha256'] ?? '').toString().toLowerCase(),
      indexSecret: spkHexBytes(
        index['secretHex']?.toString() ?? '',
        expectedBytes: 16,
      ),
      resourceSecret: resources['secretHex'] == null
          ? null
          : spkHexBytes(resources['secretHex'].toString(), expectedBytes: 16),
      resourceKeyIsIndexKey: resources['useIndexKey'] == true,
      chunkNonceRule: (resources['chunkNonceRule'] ?? 'unsupported').toString(),
    );
  }

  Map<String, Object?> publicJson() => {
    'profileId': profileId,
    'indexSha256': indexSha256,
    'index': {'algorithm': 'AES-GCM', 'secretBytes': indexSecret.length},
    'resources': {
      'algorithm': 'AES-GCM',
      'secretAvailable': effectiveResourceSecret != null,
      'chunkNonceRule': chunkNonceRule,
    },
  };
}

class SpkNameMap {
  final Map<int, String> paths;
  final Map<int, String> hints;

  SpkNameMap(this.paths, [Map<int, String>? hints])
    : hints = hints ?? <int, String>{};

  static SpkNameMap empty() => SpkNameMap({}, {});

  static int? _parseId(Object value) {
    var key = value.toString().toLowerCase().replaceFirst('0x', '');
    if (key.contains('-')) {
      final negative = int.tryParse(key.split('-').last, radix: 16);
      if (negative == null) return null;
      return (-negative) & 0xffffffffffffffff;
    }
    return int.tryParse(key, radix: 16);
  }

  static String? _safePath(Object? raw) {
    if (raw == null) return null;
    final value = raw.toString().replaceAll('\\', '/');
    if (value.isEmpty || value.startsWith('/')) return null;
    final components = value.split('/');
    if (components.any(
      (p) =>
          p.isEmpty ||
          p == '.' ||
          p == '..' ||
          RegExp(r'[<>:"|?*\x00-\x1f\x7f]').hasMatch(p),
    )) {
      return null;
    }
    return value;
  }

  static Map<int, String> _readPaths(Object? raw) {
    if (raw is! Map) return <int, String>{};
    final out = <int, String>{};
    for (final entry in raw.entries) {
      final id = _parseId(entry.key);
      final value = entry.value is Map
          ? _safePath((entry.value as Map)['path'])
          : _safePath(entry.value);
      if (id != null && value != null) out[id] = value;
    }
    return out;
  }

  static SpkNameMap fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('Mapa de nombres SPK inválido.');
    }
    if (raw['paths'] is Map || raw['hints'] is Map) {
      return SpkNameMap(_readPaths(raw['paths']), _readPaths(raw['hints']));
    }
    return SpkNameMap(_readPaths(raw), {});
  }

  String? confirmedPath(int id) => paths[id];
  String? inferredPath(int id) => hints[id];
  String? operator [](int id) => paths[id] ?? hints[id];

  bool isConfirmed(int id) => paths.containsKey(id);
  bool isInferred(int id) => !paths.containsKey(id) && hints.containsKey(id);

  void mergeConfirmed(Map<int, String> values) {
    paths.addAll(values);
    for (final id in values.keys) {
      hints.remove(id);
    }
  }

  void mergeHints(Map<int, String> values) {
    for (final entry in values.entries) {
      if (!paths.containsKey(entry.key)) hints[entry.key] = entry.value;
    }
  }

  Map<String, Object?> toJson() => {
    'schema': 2,
    'paths': {
      for (final e in paths.entries)
        e.key.toRadixString(16).padLeft(16, '0'): e.value,
    },
    'hints': {
      for (final e in hints.entries)
        e.key.toRadixString(16).padLeft(16, '0'): {
          'path': e.value,
          'confidence': 'inferred',
        },
    },
  };
}
