import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:zstandard/zstandard.dart';
import 'package:path/path.dart' as p;

import '../core/spk_archive.dart';

typedef SpkProgress = void Function(String message, int done, int total);

class SpkExtractControl {
  bool cancelled = false;
  void check() {
    if (cancelled) {
      throw const SpkFailure(
        'SPK_EXPORT_CANCELLED',
        'Extracción cancelada; el origen no se modificó.',
      );
    }
  }
}

class SpkReadResult {
  final SpkRecord record;
  final Uint8List bytes;
  final String format;
  const SpkReadResult(this.record, this.bytes, this.format);
}

class SpkArchiveSource {
  static const zstdMagic = [0x28, 0xb5, 0x2f, 0xfd];

  final File file;
  final int fileBytes;
  final SpkIndex index;
  final SpkCryptoProfile profile;
  SpkNameMap names;
  final List<Map<String, Object?>> recentReads = [];
  final List<Map<String, Object?>> failures = [];
  int reads = 0;
  int bytesRead = 0;

  SpkArchiveSource._(
    this.file,
    this.fileBytes,
    this.index,
    this.profile,
    this.names,
  );

  static Future<SpkArchiveSource> open(
    String path,
    SpkCryptoProfile profile, {
    SpkNameMap? names,
    SpkProgress? progress,
  }) async {
    final file = File(path);
    if (!await file.exists()) {
      throw const SpkFailure('SPK_MISSING', 'El archivo DATA.SPK no existe.');
    }
    final size = await file.length();
    if (size < spkHeaderBytes + spkFooterBytes) {
      throw const SpkFailure(
        'SPK_TRUNCATED',
        'El archivo SPK es demasiado pequeño.',
      );
    }

    progress?.call('Leyendo cabecera SPK…', 0, 4);
    final header = SpkHeader.parse(
      await readRange(file, 0, spkHeaderBytes, size),
      size,
    );

    progress?.call('Leyendo índice cifrado por rango…', 1, 4);
    final encrypted = await readRange(
      file,
      header.indexOffset,
      header.indexStoredBytes,
      size,
    );
    final encryptedHash = sha256.convert(encrypted).toString();
    if (profile.indexSha256.isNotEmpty &&
        encryptedHash != profile.indexSha256) {
      throw SpkFailure(
        'SPK_PROFILE_MISMATCH',
        'El perfil criptográfico pertenece a otro DATA.SPK.',
        {
          'expected': profile.indexSha256,
          'actual': encryptedHash,
          'profileId': profile.profileId,
        },
      );
    }

    progress?.call('Descifrando índice AES-GCM…', 2, 4);
    final packed = await decryptGcm(
      encrypted,
      profile.indexSecret,
      header.indexNonce,
      header.indexTag,
    );
    if (!startsWith(packed, zstdMagic)) {
      throw const SpkFailure(
        'SPK_INDEX_CODEC',
        'El índice descifrado no contiene un frame Zstandard.',
      );
    }
    final decoded = await Zstandard().decompress(packed);
    if (decoded == null || decoded.length != header.indexDecodedBytes) {
      throw SpkFailure(
        'SPK_INDEX_DECODE',
        'Zstandard no produjo la longitud declarada.',
        {'expected': header.indexDecodedBytes, 'actual': decoded?.length},
      );
    }
    final records = SpkIndex.parseRecords(decoded, header);

    progress?.call('Validando tabla auxiliar y relaciones…', 3, 4);
    final auxiliary = SpkIndex.parseAuxiliary(
      await readRange(
        file,
        header.auxiliaryOffset,
        header.auxiliaryCount * spkAuxRecordBytes,
        size,
      ),
      header,
    );
    SpkIndex.validateRelationships(records, auxiliary, header);

    final index = SpkIndex(
      header: header,
      records: records,
      auxiliary: auxiliary,
      encryptedIndexSha256: encryptedHash,
      decodedIndexSha256: sha256.convert(decoded).toString(),
    );
    progress?.call('SPK validado: ${index.resources.length} recursos.', 4, 4);
    return SpkArchiveSource._(
      file,
      size,
      index,
      profile,
      names ?? SpkNameMap.empty(),
    );
  }

  static Future<Uint8List> readRange(
    File file,
    int offset,
    int length,
    int expectedFileBytes,
  ) async {
    if (offset < 0 ||
        length < 0 ||
        offset > expectedFileBytes ||
        length > expectedFileBytes - offset) {
      throw const FormatException('Rango SPK fuera del archivo.');
    }
    final handle = await file.open(mode: FileMode.read);
    try {
      if (await handle.length() != expectedFileBytes) {
        throw const FormatException(
          'DATA.SPK cambió de tamaño después de indexarse.',
        );
      }
      await handle.setPosition(offset);
      final out = Uint8List(length);
      var done = 0;
      while (done < length) {
        final n = await handle.readInto(out, done, length);
        if (n == 0) {
          throw const FormatException('Fin prematuro de DATA.SPK.');
        }
        done += n;
      }
      return out;
    } finally {
      await handle.close();
    }
  }

  static Future<Uint8List> decryptGcm(
    Uint8List cipherText,
    Uint8List secret,
    Uint8List nonce,
    Uint8List tag, {
    Uint8List? aad,
  }) async {
    if (secret.length != 16 || nonce.length != 12 || tag.length != 16) {
      throw const FormatException('Parámetros AES-GCM SPK inválidos.');
    }
    final clear = await AesGcm.with128bits().decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(tag)),
      secretKey: SecretKey(secret),
      aad: aad ?? const [],
    );
    return Uint8List.fromList(clear);
  }

  static bool startsWith(List<int> bytes, List<int> prefix) {
    if (bytes.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (bytes[i] != prefix[i]) return false;
    }
    return true;
  }

  String technicalPath(SpkRecord record) {
    final known = names[record.entryId];
    if (known != null) return known;
    final group = record.simple
        ? '_SPK_SinNombre/Simples'
        : '_SPK_SinNombre/Fragmentados';
    return '$group/${record.idHex}.bin';
  }

  String nameConfidence(SpkRecord record) {
    if (names.isConfirmed(record.entryId)) return 'confirmado';
    if (names.isInferred(record.entryId)) return 'inferido';
    return 'sin-resolver';
  }

  String displayType(SpkRecord record) {
    final path = technicalPath(record);
    final ext = p.extension(path).replaceFirst('.', '').toUpperCase();
    if (ext.isNotEmpty && ext != 'BIN') return ext;
    return record.simple ? 'Simple' : 'Fragmentado';
  }

  Future<Map<String, Object?>> inferNamesFromDirectory(
    Directory reference, {
    required SpkProgress progress,
    int maxCompressionBytes = 192 * 1024 * 1024,
  }) async {
    if (!await reference.exists()) {
      throw const FormatException('La carpeta DATA de referencia no existe.');
    }

    final resources = index.resources.toList(growable: false);
    final wantedSizes = <int>{
      for (final record in resources) record.decodedBytes,
    };
    final wantedPairs = <String, List<SpkRecord>>{};
    for (final record in resources) {
      wantedPairs
          .putIfAbsent(
            '${record.decodedBytes}:${record.storedBytes}',
            () => <SpkRecord>[],
          )
          .add(record);
    }

    final pathsBySize = <int, List<String>>{};
    final pathsByPair = <String, List<String>>{};
    var scanned = 0;
    var compressed = 0;
    var skippedLarge = 0;
    final codec = Zstandard();

    await for (final entity in reference.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final size = await entity.length();
      if (!wantedSizes.contains(size)) continue;
      final relative = p
          .relative(entity.path, from: reference.path)
          .replaceAll('\\', '/');
      if (relative.isEmpty || relative.startsWith('../')) continue;
      pathsBySize.putIfAbsent(size, () => <String>[]).add(relative);
      scanned++;

      if (size <= maxCompressionBytes) {
        final packed = await codec.compress(await entity.readAsBytes(), 3);
        if (packed != null) {
          final key = '$size:${packed.length}';
          if (wantedPairs.containsKey(key)) {
            pathsByPair.putIfAbsent(key, () => <String>[]).add(relative);
          }
          compressed++;
        }
      } else {
        skippedLarge++;
      }
      if (scanned % 250 == 0) {
        progress(
          'Correlacionando DATA por tamaño y Zstandard nivel 3…',
          scanned,
          0,
        );
      }
    }

    final strong = <int, String>{};
    final fallback = <int, String>{};
    for (final record in resources) {
      final pair = '${record.decodedBytes}:${record.storedBytes}';
      final exact = pathsByPair[pair];
      if (exact != null && exact.length == 1) {
        strong[record.entryId] = exact.single;
        continue;
      }
      final sameSize = pathsBySize[record.decodedBytes];
      if (sameSize != null && sameSize.length == 1) {
        fallback[record.entryId] = sameSize.single;
      }
    }
    names.mergeHints(
      fallback,
      confidence: 'inferred',
      evidence: 'unique-decoded-size',
    );
    names.mergeHints(
      strong,
      confidence: 'strong-inferred',
      evidence: 'decoded-size+zstd3-size',
    );
    progress(
      'Rutas inferidas: ${strong.length} fuertes + '
      '${fallback.length} por tamaño.',
      resources.length,
      resources.length,
    );
    return {
      'scannedCandidateFiles': scanned,
      'compressedCandidateFiles': compressed,
      'skippedLargeFiles': skippedLarge,
      'strongInferred': strong.length,
      'sizeOnlyInferred': fallback.length,
      'inferredTotal': names.hints.length,
      'confirmed': names.paths.length,
      'unresolved': resources.length - names.paths.length - names.hints.length,
      'method': 'decoded-size+zstd3-size, fallback unique-decoded-size',
    };
  }

  Future<Map<String, Object?>> verifyNamesFromDirectory(
    Directory reference, {
    required SpkExtractControl control,
    required SpkProgress progress,
  }) async {
    if (!canReadSimpleResources) {
      throw const SpkFailure(
        'SPK_RESOURCE_PROFILE_REQUIRED',
        'Se necesita primero el perfil de recursos para confirmar nombres por contenido.',
      );
    }
    if (!await reference.exists()) {
      throw const FormatException('La carpeta DATA de referencia no existe.');
    }
    final bySize = <int, List<File>>{};
    var scanned = 0;
    await for (final entity in reference.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final size = await entity.length();
      bySize.putIfAbsent(size, () => <File>[]).add(entity);
      scanned++;
      if (scanned % 1000 == 0) {
        progress('Indexando archivos para verificación…', scanned, 0);
      }
    }

    final fileHashes = <String, String>{};
    final confirmed = <int, String>{};
    final resources = index.simpleResources.toList(growable: false);
    for (var i = 0; i < resources.length; i++) {
      control.check();
      final record = resources[i];
      final candidates = bySize[record.decodedBytes];
      if (candidates == null || candidates.isEmpty) continue;
      final result = await readEntry(record);
      final digest = sha256.convert(result.bytes).toString();
      for (final candidate in candidates) {
        control.check();
        final candidateHash = fileHashes[candidate.path] ??= sha256
            .convert(await candidate.readAsBytes())
            .toString();
        if (candidateHash != digest) continue;
        final relative = p
            .relative(candidate.path, from: reference.path)
            .replaceAll('\\', '/');
        confirmed[record.entryId] = relative;
        break;
      }
      if ((i + 1) % 100 == 0) {
        progress('Confirmando rutas por SHA-256…', i + 1, resources.length);
      }
    }
    names.mergeConfirmed(confirmed);
    progress(
      'Rutas confirmadas: ${confirmed.length}.',
      resources.length,
      resources.length,
    );
    return {
      'scannedFiles': scanned,
      'confirmed': confirmed.length,
      'remainingHints': names.hints.length,
      'method': 'decoded-sha256-reference',
    };
  }

  List<String> folders() {
    final out = <String>{''};
    for (final record in index.resources) {
      final parts = technicalPath(record).replaceAll('\\', '/').split('/');
      for (var i = 1; i < parts.length; i++) {
        out.add(parts.take(i).join('/'));
      }
    }
    return out.toList()..sort();
  }

  List<SpkRecord> entriesInFolder(
    String folder, {
    String search = '',
    bool recursive = false,
  }) {
    final prefix = folder.isEmpty ? '' : '$folder/';
    final q = search.trim().toLowerCase();
    final out = <SpkRecord>[];
    for (final record in index.resources) {
      final path = technicalPath(record).replaceAll('\\', '/');
      if (!path.startsWith(prefix)) continue;
      final relative = path.substring(prefix.length);
      if (!recursive && relative.contains('/')) continue;
      if (q.isNotEmpty &&
          !path.toLowerCase().contains(q) &&
          !record.idHex.contains(q)) {
        continue;
      }
      out.add(record);
    }
    out.sort((a, b) => technicalPath(a).compareTo(technicalPath(b)));
    return out;
  }

  bool get canReadSimpleResources => profile.effectiveResourceSecret != null;
  bool get canReadFragmentedResources =>
      profile.effectiveResourceSecret != null &&
      profile.chunkNonceRule != 'unsupported';
  bool get canExtractAll =>
      canReadSimpleResources &&
      (index.fragmentedResources.isEmpty || canReadFragmentedResources);

  Future<SpkReadResult> readEntry(
    SpkRecord record, {
    int limit = 128 * 1024 * 1024,
  }) async {
    if (!record.resource) {
      throw const FormatException(
        'El registro SPK seleccionado no es un recurso.',
      );
    }
    if (record.storedBytes > limit || record.decodedBytes > limit) {
      throw FormatException('El recurso supera el límite de $limit bytes.');
    }
    try {
      final bytes = record.simple
          ? await _readSimple(record)
          : await _readFragmented(record);
      final format = detectFormat(bytes);
      reads++;
      bytesRead += bytes.length;
      if (recentReads.length >= 40) recentReads.removeAt(0);
      recentReads.add({
        'entryId': record.idHex,
        'path': technicalPath(record),
        'format': format,
        'storedBytes': record.storedBytes,
        'decodedBytes': bytes.length,
        'sha256': sha256.convert(bytes).toString(),
      });
      return SpkReadResult(record, bytes, format);
    } catch (error) {
      if (failures.length >= 100) failures.removeAt(0);
      failures.add({
        'entryId': record.idHex,
        'offset': record.dataOffset,
        'storedBytes': record.storedBytes,
        'error': error.toString(),
      });
      rethrow;
    }
  }

  Future<Uint8List> _readSimple(SpkRecord record) async {
    final key = profile.effectiveResourceSecret;
    if (key == null) {
      throw const SpkFailure(
        'SPK_RESOURCE_PROFILE_REQUIRED',
        'El índice se puede montar, pero falta un perfil de recursos validado.',
      );
    }
    final cipher = await readRange(
      file,
      record.dataOffset,
      record.storedBytes,
      fileBytes,
    );
    return decodePayload(
      await decryptGcm(cipher, key, record.nonce, record.tag),
      record.decodedBytes,
    );
  }

  Future<Uint8List> _readFragmented(SpkRecord record) async {
    if (!canReadFragmentedResources) {
      throw SpkFailure(
        'SPK_FRAGMENT_PROFILE_REQUIRED',
        'La regla criptográfica de recursos fragmentados todavía no está validada.',
        {
          'entryId': record.idHex,
          'chunks': record.chunkCount,
          'profile': profile.profileId,
        },
      );
    }
    final key = profile.effectiveResourceSecret!;
    final parts = index.auxiliary.sublist(
      record.auxiliaryStart,
      record.auxiliaryStart + record.chunkCount,
    );
    final packed = BytesBuilder(copy: false);
    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      final cipher = await readRange(
        file,
        part.dataOffset,
        part.storedBytes,
        fileBytes,
      );
      packed.add(
        await decryptGcm(
          cipher,
          key,
          _fragmentNonce(record, part, i),
          part.metadata,
        ),
      );
    }
    return decodePayload(packed.takeBytes(), record.decodedBytes);
  }

  static const supportedChunkNonceRules = <String>[
    'offset_le96',
    'entry_id_chunk_le',
    'offset_aux_le96',
    'entry_id_aux_le',
    'offset_chunk1_le96',
    'entry_id_chunk1_le',
  ];

  Uint8List _fragmentNonceForRule(
    String rule,
    SpkRecord record,
    SpkAuxRecord part,
    int ordinal,
  ) {
    final data = ByteData(12);
    switch (rule) {
      case 'offset_le96':
        data.setUint64(0, part.dataOffset, Endian.little);
        data.setUint32(8, ordinal, Endian.little);
        return data.buffer.asUint8List();
      case 'entry_id_chunk_le':
        data.setUint64(0, record.entryId, Endian.little);
        data.setUint32(8, ordinal, Endian.little);
        return data.buffer.asUint8List();
      case 'offset_aux_le96':
        data.setUint64(0, part.dataOffset, Endian.little);
        data.setUint32(8, part.ordinal, Endian.little);
        return data.buffer.asUint8List();
      case 'entry_id_aux_le':
        data.setUint64(0, record.entryId, Endian.little);
        data.setUint32(8, part.ordinal, Endian.little);
        return data.buffer.asUint8List();
      case 'offset_chunk1_le96':
        data.setUint64(0, part.dataOffset, Endian.little);
        data.setUint32(8, ordinal + 1, Endian.little);
        return data.buffer.asUint8List();
      case 'entry_id_chunk1_le':
        data.setUint64(0, record.entryId, Endian.little);
        data.setUint32(8, ordinal + 1, Endian.little);
        return data.buffer.asUint8List();
      default:
        throw const SpkFailure(
          'SPK_FRAGMENT_NONCE',
          'Regla de nonce fragmentado no implementada.',
        );
    }
  }

  Uint8List _fragmentNonce(SpkRecord record, SpkAuxRecord part, int ordinal) =>
      _fragmentNonceForRule(profile.chunkNonceRule, record, part, ordinal);

  String identifyChunkNonceRule({
    required int parentOrdinal,
    required int auxiliaryOrdinal,
    required Uint8List observedNonce,
  }) {
    if (observedNonce.length != 12 ||
        parentOrdinal < 0 ||
        parentOrdinal >= index.records.length ||
        auxiliaryOrdinal < 0 ||
        auxiliaryOrdinal >= index.auxiliary.length) {
      return 'unsupported';
    }
    final record = index.records[parentOrdinal];
    if (!record.fragmented ||
        auxiliaryOrdinal < record.auxiliaryStart ||
        auxiliaryOrdinal >= record.auxiliaryStart + record.chunkCount) {
      return 'unsupported';
    }
    final part = index.auxiliary[auxiliaryOrdinal];
    final local = auxiliaryOrdinal - record.auxiliaryStart;
    for (final rule in supportedChunkNonceRules) {
      final candidate = _fragmentNonceForRule(rule, record, part, local);
      if (candidate.length == observedNonce.length) {
        var same = true;
        for (var i = 0; i < candidate.length; i++) {
          if (candidate[i] != observedNonce[i]) {
            same = false;
            break;
          }
        }
        if (same) return rule;
      }
    }
    return 'unsupported';
  }

  static Future<Uint8List> decodePayload(
    Uint8List plain,
    int expectedBytes,
  ) async {
    if (startsWith(plain, zstdMagic)) {
      final decoded = await Zstandard().decompress(plain);
      if (decoded == null ||
          (expectedBytes > 0 && decoded.length != expectedBytes)) {
        throw const FormatException(
          'Zstandard no produjo el tamaño esperado del recurso.',
        );
      }
      return decoded;
    }
    if (expectedBytes == 0 || plain.length == expectedBytes) return plain;
    throw FormatException(
      'El recurso fue descifrado, pero usa una compresión aún no identificada.',
    );
  }

  static String detectFormat(Uint8List bytes) {
    if (startsWith(bytes, [0x44, 0x44, 0x53, 0x20])) return 'DDS';
    if (startsWith(bytes, [0x89, 0x50, 0x4e, 0x47])) return 'PNG';
    if (startsWith(bytes, [0x42, 0x4d])) return 'BMP';
    if (startsWith(bytes, [0xff, 0xd8, 0xff])) return 'JPEG';
    if (startsWith(bytes, [0x47, 0x49, 0x46, 0x38])) return 'GIF';
    if (startsWith(bytes, [0x4f, 0x67, 0x67, 0x53])) return 'OGG';
    if (startsWith(bytes, [0x52, 0x49, 0x46, 0x46])) return 'RIFF';
    if (startsWith(bytes, [0x50, 0x4b, 0x03, 0x04])) return 'ZIP';
    if (startsWith(bytes, [0x4d, 0x5a])) return 'PE';
    if (bytes.length >= 18) {
      final type = bytes[2];
      final depth = bytes[16];
      if ((type == 1 ||
              type == 2 ||
              type == 3 ||
              type == 9 ||
              type == 10 ||
              type == 11) &&
          (depth == 8 || depth == 16 || depth == 24 || depth == 32)) {
        return 'TGA';
      }
    }
    if (bytes.length >= 4) {
      final head = latin1.decode(bytes.take(4).toList(), allowInvalid: true);
      if (RegExp(r'^[A-Z0-9]{3,4}$').hasMatch(head)) return head;
    }
    final probe = latin1
        .decode(
          bytes.take(bytes.length > 512 ? 512 : bytes.length).toList(),
          allowInvalid: true,
        )
        .trimLeft();
    if (probe.startsWith('<?xml') || probe.startsWith('<')) return 'XML/TEXT';
    return 'BIN';
  }

  static String extensionFor(String format) {
    switch (format) {
      case 'DDS':
        return '.dds';
      case 'PNG':
        return '.png';
      case 'BMP':
        return '.bmp';
      case 'JPEG':
        return '.jpg';
      case 'GIF':
        return '.gif';
      case 'TGA':
        return '.tga';
      case 'OGG':
        return '.ogg';
      case 'RIFF':
        return '.wav';
      case 'ZIP':
        return '.zip';
      case 'XML/TEXT':
        return '.txt';
      default:
        return '.bin';
    }
  }

  Future<void> importNameMap(String text) async {
    final incoming = SpkNameMap.fromJson(jsonDecode(text));
    names.mergeHintRecords(incoming.hints);
    names.mergeConfirmed(incoming.paths);
  }

  Future<Map<String, Object?>> extract(
    Directory parent, {
    Iterable<SpkRecord>? selection,
    required SpkExtractControl control,
    required SpkProgress progress,
    bool requireComplete = true,
  }) async {
    if (!await parent.exists()) {
      throw const FormatException('La carpeta de destino no existe.');
    }
    final list = (selection ?? index.resources)
        .where((e) => e.resource)
        .toList();
    if (requireComplete &&
        list.any((e) => e.fragmented) &&
        !canReadFragmentedResources) {
      throw SpkFailure(
        'SPK_EXTRACT_INCOMPLETE',
        'Extraer todo permanece bloqueado hasta validar los recursos fragmentados.',
        {'fragmentedResources': index.fragmentedResources.length},
      );
    }

    final stamp = DateTime.now().millisecondsSinceEpoch.toString();
    final stage = Directory('${parent.path}/.shaiya-spk-$stamp.partial');
    final published = Directory('${parent.path}/DATA_SPK_$stamp');
    if (await stage.exists() || await published.exists()) {
      throw const FileSystemException('La carpeta de salida ya existe.');
    }
    await stage.create();
    final manifest = <Map<String, Object?>>[];
    var bytes = 0;
    try {
      for (var i = 0; i < list.length; i++) {
        control.check();
        final record = list[i];
        final result = await readEntry(record);
        var relative = names[record.entryId];
        relative ??=
            '_SPK_SinNombre/${record.idHex}${extensionFor(result.format)}';
        final safe = safeRelative(relative);
        final target = File('${stage.path}/$safe');
        await target.parent.create(recursive: true);
        await target.writeAsBytes(result.bytes, flush: true);
        manifest.add({
          'entryId': record.idHex,
          'path': relative.replaceAll('\\', '/'),
          'format': result.format,
          'storedBytes': record.storedBytes,
          'decodedBytes': result.bytes.length,
          'sha256': sha256.convert(result.bytes).toString(),
          'resolvedName': names.isConfirmed(record.entryId),
          'inferredName': names.isInferred(record.entryId),
          'nameConfidence': nameConfidence(record),
        });
        bytes += result.bytes.length;
        progress('Extrayendo $relative', i + 1, list.length);
      }
      await File('${stage.path}/_SPK_MANIFEST.json').writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'schema': 1,
          'source': file.path,
          'index': index.summary(),
          'profile': profile.publicJson(),
          'files': manifest,
        }),
        flush: true,
      );
      await stage.rename(published.path);
      return {
        'folder': published.path,
        'files': manifest.length,
        'bytes': bytes,
      };
    } catch (_) {
      if (await stage.exists()) await stage.delete(recursive: true);
      rethrow;
    }
  }

  static String safeRelative(String path) {
    final value = path.replaceAll('\\', '/');
    if (value.startsWith('/') || value.contains(':') || value.length > 4096) {
      throw FormatException('Ruta no extraíble: $path');
    }
    final parts = value.split('/');
    for (final p in parts) {
      if (p.isEmpty ||
          p == '.' ||
          p == '..' ||
          p.endsWith('.') ||
          p.endsWith(' ') ||
          RegExp(r'[<>:"|?*\x00-\x1f\x7f]').hasMatch(p) ||
          RegExp(
            r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|$)',
            caseSensitive: false,
          ).hasMatch(p)) {
        throw FormatException('Ruta no segura: $path');
      }
    }
    return parts.join(Platform.pathSeparator);
  }

  Map<String, Object?> diagnostics() => {
    'sourceMode': 'spk-v3',
    'file': file.path,
    'fileBytes': fileBytes,
    'profile': profile.publicJson(),
    'index': index.summary(),
    'resolvedNames': names.paths.length,
    'inferredNames': names.hints.length,
    'unresolvedNames':
        index.resources.length - names.paths.length - names.hints.length,
    'canReadSimpleResources': canReadSimpleResources,
    'canReadFragmentedResources': canReadFragmentedResources,
    'canExtractAll': canExtractAll,
    'reads': reads,
    'bytesRead': bytesRead,
    'recentReads': recentReads,
    'failures': failures,
  };
}
