import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:zstandard/zstandard.dart';
import 'package:path/path.dart' as p;

import '../core/formats.dart';
import '../core/seed_data.dart';
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

class SpkFragmentAuthSample {
  final SpkRecord record;
  final SpkAuxRecord part;
  final int localOrdinal;
  final Uint8List cipherText;

  const SpkFragmentAuthSample({
    required this.record,
    required this.part,
    required this.localOrdinal,
    required this.cipherText,
  });
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
  Map<String, Object?>? resourceProfileValidation;
  Map<String, Object?>? fragmentProfileValidation;
  Map<String, Object?>? fullResourceValidation;
  final Map<int, String> _validatedFormats = <int, String>{};
  bool _simpleProfileValidated = false;
  bool _fragmentProfileValidated = false;
  int reads = 0;
  int bytesRead = 0;

  SpkArchiveSource._(
    this.file,
    this.fileBytes,
    this.index,
    this.profile,
    this.names,
  );

  @visibleForTesting
  static Future<SpkArchiveSource> fromValidatedIndexForTesting({
    required File file,
    required SpkIndex index,
    required SpkCryptoProfile profile,
    SpkNameMap? names,
  }) async {
    if (!await file.exists()) {
      throw const FileSystemException('El fixture SPK de pruebas no existe.');
    }
    return SpkArchiveSource._(
      file,
      await file.length(),
      index,
      profile,
      names ?? SpkNameMap.empty(),
    );
  }

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
    if ((secret.length != 16 && secret.length != 32) ||
        nonce.length != 12 ||
        tag.length != 16) {
      throw const FormatException('Parámetros AES-GCM SPK inválidos.');
    }
    final algorithm = secret.length == 16
        ? AesGcm.with128bits()
        : AesGcm.with256bits();
    final clear = await algorithm.decrypt(
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
    if (!record.resource) {
      return '_SPK_Tecnico/Registros/${record.idHex}.record';
    }
    final group = record.simple
        ? '_SPK_SinNombre/Simples'
        : '_SPK_SinNombre/Fragmentados';
    final format = validatedFormat(record.entryId);
    final extension = format == null ? '.bin' : extensionFor(format);
    return '$group/${record.idHex}$extension';
  }

  String nameConfidence(SpkRecord record) {
    if (names.isConfirmed(record.entryId)) return 'confirmado';
    if (names.isInferred(record.entryId)) {
      return names.confidence(record.entryId);
    }
    return 'sin-resolver';
  }

  String nameEvidence(SpkRecord record) => names.evidence(record.entryId);

  String displayType(SpkRecord record) {
    final verified = validatedFormat(record.entryId);
    if (verified != null && verified.isNotEmpty) return verified;
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
    final wantedByDecodedSize = <int, List<SpkRecord>>{};
    for (final record in resources) {
      wantedPairs
          .putIfAbsent(
            '${record.decodedBytes}:${record.storedBytes}',
            () => <SpkRecord>[],
          )
          .add(record);
      wantedByDecodedSize
          .putIfAbsent(record.decodedBytes, () => <SpkRecord>[])
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
      final spkPair = wantedPairs[pair];
      if (exact != null &&
          exact.length == 1 &&
          spkPair != null &&
          spkPair.length == 1) {
        strong[record.entryId] = exact.single;
        continue;
      }
      final sameSize = pathsBySize[record.decodedBytes];
      final spkSameSize = wantedByDecodedSize[record.decodedBytes];
      if (sameSize != null &&
          sameSize.length == 1 &&
          spkSameSize != null &&
          spkSameSize.length == 1) {
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
    final ambiguousRemoved = names.removeAmbiguousHints();
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
      'ambiguousRemoved': ambiguousRemoved,
      'confirmed': names.paths.length,
      'unresolved': resources.length - names.paths.length - names.hints.length,
      'method':
          'one-to-one decoded-size+zstd3-size, fallback one-to-one decoded-size',
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

  bool get _hasSimpleCryptoMaterial =>
      profile.effectiveResourceSecret != null;

  bool get _hasFragmentCryptoMaterial =>
      _hasSimpleCryptoMaterial && profile.chunkNonceRule != 'unsupported';

  bool get canReadSimpleResources =>
      _hasSimpleCryptoMaterial && _simpleProfileValidated;

  bool get canReadFragmentedResources =>
      _hasFragmentCryptoMaterial && _fragmentProfileValidated;

  bool get canExtractAll =>
      canReadSimpleResources &&
      (index.fragmentedResources.isEmpty || canReadFragmentedResources);

  bool canReadRecord(SpkRecord record) {
    if (!record.resource) return false;
    if (record.simple) return canReadSimpleResources;
    if (record.fragmented) return canReadFragmentedResources;
    return false;
  }

  bool get fullyValidatedResources =>
      canExtractAll &&
      fullResourceValidation?['status'] == 'validated' &&
      fullResourceValidation?['validatedResources'] == index.resources.length &&
      _validatedFormats.length == index.resources.length;

  String? validatedFormat(int entryId) => _validatedFormats[entryId];

  Map<String, String> get validatedFormatsJson => {
    for (final entry in _validatedFormats.entries)
      spkU64Hex(entry.key): entry.value,
  };

  Map<String, Object?> validateInferredNamesByFormat() {
    if (!fullyValidatedResources) {
      throw const SpkFailure(
        'SPK_NAME_FORMAT_AUDIT_REQUIRED',
        'Primero debe completarse la auditoría integral de payloads.',
      );
    }

    final knownExtensions = <String, Set<String>>{
      '.dds': {'DDS'},
      '.png': {'PNG'},
      '.bmp': {'BMP'},
      '.jpg': {'JPEG'},
      '.jpeg': {'JPEG'},
      '.gif': {'GIF'},
      '.tga': {'TGA'},
      '.ogg': {'OGG'},
      '.wav': {'RIFF'},
      '.zip': {'ZIP'},
      '.exe': {'PE'},
      '.eft': {'EFT'},
      '.wld': {'WLD'},
      '.3dc': {'3DC'},
      '.3do': {'3DO'},
      '.ani': {'ANI'},
      '.mlt': {'MLT'},
      '.itm': {'ITM'},
      '.mon': {'MON'},
      '.sdata': {'SDATA'},
      '.xml': {'XML'},
      '.json': {'JSON'},
      '.ini': {'INI'},
      '.txt': {'TXT'},
    };

    var validated = 0;
    var rejected = 0;
    var preservedUnknown = 0;
    final updates = <int, SpkNameHint>{};
    final removals = <int>[];

    for (final entry in names.hints.entries.toList(growable: false)) {
      final extension = p.extension(entry.value.path).toLowerCase();
      final expected = knownExtensions[extension];
      if (expected == null) {
        preservedUnknown++;
        continue;
      }
      final actual = _validatedFormats[entry.key];
      if (actual == null || actual == 'BIN') {
        preservedUnknown++;
        continue;
      }
      if (expected.contains(actual)) {
        updates[entry.key] = SpkNameHint(
          path: entry.value.path,
          confidence: 'validated-inferred',
          evidence: '${entry.value.evidence}+payload-format:$actual',
        );
        validated++;
      } else {
        removals.add(entry.key);
        rejected++;
      }
    }

    names.mergeHintRecords(updates);
    for (final id in removals) {
      names.hints.remove(id);
    }
    final ambiguousRemoved = names.removeAmbiguousHints();

    return {
      'validated': validated,
      'rejected': rejected,
      'preservedUnknown': preservedUnknown,
      'ambiguousRemoved': ambiguousRemoved,
      'remainingHints': names.hints.length,
      'method': 'full-payload-audit+extension-format-match',
    };
  }

  bool restoreFullResourceValidation(Map<String, dynamic> evidence) {
    if (!canExtractAll) return false;
    final declaredIndex = evidence['indexSha256']?.toString().toLowerCase();
    if (declaredIndex != index.encryptedIndexSha256.toLowerCase()) return false;

    final key = profile.effectiveResourceSecret;
    final expectedKeyHash = evidence['resourceKeySha256']?.toString().toLowerCase();
    if (key == null ||
        expectedKeyHash == null ||
        expectedKeyHash != sha256.convert(key).toString().toLowerCase()) {
      return false;
    }

    final declaredRule = evidence['chunkNonceRule']?.toString();
    if (declaredRule != null &&
        declaredRule.isNotEmpty &&
        declaredRule != profile.chunkNonceRule) {
      return false;
    }

    final raw = evidence['validation'];
    final rawFormats = evidence['resourceFormats'];
    if (raw is! Map || rawFormats is! Map) return false;
    final validation = Map<String, Object?>.from(raw);
    if (validation['status'] != 'validated' ||
        validation['validatedResources'] != index.resources.length ||
        validation['totalResources'] != index.resources.length ||
        validation['failures'] != 0) {
      return false;
    }

    final knownIds = index.resources.map((record) => record.entryId).toSet();
    final restored = <int, String>{};
    for (final entry in rawFormats.entries) {
      final id = spkParseU64Hex(entry.key);
      final format = entry.value?.toString().trim();
      if (id == null ||
          format == null ||
          format.isEmpty ||
          !knownIds.contains(id) ||
          restored.containsKey(id)) {
        return false;
      }
      restored[id] = format;
    }
    if (restored.length != index.resources.length) return false;

    _validatedFormats
      ..clear()
      ..addAll(restored);
    fullResourceValidation = validation;
    return true;
  }

  static List<SpkRecord> _spreadValidationRecords(
    List<SpkRecord> records,
    int maxSamples,
  ) {
    if (records.isEmpty || maxSamples <= 0) return const <SpkRecord>[];
    final count = records.length < maxSamples ? records.length : maxSamples;
    if (count == 1) return <SpkRecord>[records.first];
    final out = <SpkRecord>[];
    final seen = <int>{};
    for (var i = 0; i < count; i++) {
      final index = ((records.length - 1) * i) ~/ (count - 1);
      final record = records[index];
      if (seen.add(record.ordinal)) out.add(record);
    }
    return out;
  }

  Future<SpkArchiveSource?> tryIndexKeyAsResourceProfile() async {
    if (profile.effectiveResourceSecret != null) return null;

    final candidateProfile = SpkCryptoProfile(
      profileId: '${profile.profileId}-index-key-resources',
      indexSha256: profile.indexSha256,
      indexSecret: Uint8List.fromList(profile.indexSecret),
      resourceSecret: null,
      resourceAad: Uint8List(0),
      resourceKeyIsIndexKey: true,
      chunkNonceRule: 'unsupported',
    );

    final candidate = SpkArchiveSource._(
      file,
      fileBytes,
      index,
      candidateProfile,
      names,
    );
    try {
      await candidate.validateSimpleResourceProfile();
    } catch (_) {
      return null;
    }
    return candidate;
  }

  Future<Map<String, Object?>> validateSimpleResourceProfile({
    int minimumAuthenticatedSamples = 3,
    int maxSamples = 8,
  }) async {
    final key = profile.effectiveResourceSecret;
    if (key == null) {
      throw const SpkFailure(
        'SPK_RESOURCE_PROFILE_REQUIRED',
        'Falta material criptográfico para validar recursos simples.',
      );
    }
    if (minimumAuthenticatedSamples < 1 ||
        maxSamples < minimumAuthenticatedSamples) {
      throw ArgumentError(
        'La validación SPK requiere límites de muestras coherentes.',
      );
    }

    final resources = index.simpleResources.toList(growable: false);
    if (resources.length < minimumAuthenticatedSamples) {
      throw const SpkFailure(
        'SPK_RESOURCE_VALIDATION_SAMPLES',
        'No hay suficientes recursos simples para validar el perfil.',
      );
    }

    final samples = <Map<String, Object?>>[];
    var authenticated = 0;
    var decoded = 0;
    for (final record in _spreadValidationRecords(resources, maxSamples)) {
      final cipher = await readRange(
        file,
        record.dataOffset,
        record.storedBytes,
        fileBytes,
      );
      Uint8List plain;
      try {
        plain = await decryptGcm(
          cipher,
          key,
          record.nonce,
          record.tag,
          aad: profile.resourceAad.isEmpty ? null : profile.resourceAad,
        );
      } catch (error) {
        _simpleProfileValidated = false;
        resourceProfileValidation = {
          'status': 'failed',
          'entryId': record.idHex,
          'authenticatedSamples': authenticated,
          'error': error.toString(),
        };
        throw SpkFailure(
          'SPK_RESOURCE_AUTH_FAILED',
          'El perfil de payloads no autentica un recurso simple del SPK.',
          Map<String, Object?>.from(resourceProfileValidation!),
        );
      }
      authenticated++;

      String format = 'PACKED';
      String? decodeError;
      try {
        final bytes = await decodePayload(plain, record.decodedBytes);
        format = detectFormat(bytes);
        decoded++;
      } catch (error) {
        decodeError = error.toString();
      }
      samples.add({
        'entryId': record.idHex,
        'storedBytes': record.storedBytes,
        'declaredDecodedBytes': record.decodedBytes,
        'plainBytes': plain.length,
        'format': format,
        'decodeError': ?decodeError,
      });
    }

    if (authenticated < minimumAuthenticatedSamples) {
      throw const SpkFailure(
        'SPK_RESOURCE_VALIDATION_SAMPLES',
        'No se autenticaron suficientes muestras de recursos simples.',
      );
    }
    if (decoded == 0) {
      throw SpkFailure(
        'SPK_RESOURCE_CODEC_VALIDATION',
        'AES-GCM autentica, pero ninguna muestra pudo reconstruirse con los codecs soportados.',
        {'authenticatedSamples': authenticated, 'samples': samples},
      );
    }

    _simpleProfileValidated = true;
    resourceProfileValidation = {
      'status': 'validated',
      'authenticatedSamples': authenticated,
      'decodedSamples': decoded,
      'minimumRequired': minimumAuthenticatedSamples,
      'sampleCount': samples.length,
      'samples': samples,
    };
    return Map<String, Object?>.from(resourceProfileValidation!);
  }

  Future<Map<String, Object?>> validateFragmentedResourceProfile({
    int minimumDecodedSamples = 2,
    int maxSamples = 3,
  }) async {
    if (!_hasFragmentCryptoMaterial) {
      throw const SpkFailure(
        'SPK_FRAGMENT_PROFILE_REQUIRED',
        'Falta una regla criptográfica reproducible para validar fragmentos.',
      );
    }
    if (!_simpleProfileValidated) {
      await validateSimpleResourceProfile();
    }
    if (minimumDecodedSamples < 1 || maxSamples < minimumDecodedSamples) {
      throw ArgumentError(
        'La validación de fragmentos requiere límites de muestras coherentes.',
      );
    }

    final resources = index.fragmentedResources.toList(growable: false);
    if (resources.length < minimumDecodedSamples) {
      throw const SpkFailure(
        'SPK_FRAGMENT_VALIDATION_SAMPLES',
        'No hay suficientes recursos fragmentados para validar la reconstrucción.',
      );
    }

    final samples = <Map<String, Object?>>[];
    var decoded = 0;
    for (final record in _spreadValidationRecords(resources, maxSamples)) {
      try {
        final bytes = await _readFragmented(record);
        samples.add({
          'entryId': record.idHex,
          'chunks': record.chunkCount,
          'decodedBytes': bytes.length,
          'format': detectFormat(bytes),
          'sha256': sha256.convert(bytes).toString(),
        });
        decoded++;
      } catch (error) {
        _fragmentProfileValidated = false;
        fragmentProfileValidation = {
          'status': 'failed',
          'entryId': record.idHex,
          'decodedSamples': decoded,
          'error': error.toString(),
        };
        throw SpkFailure(
          'SPK_FRAGMENT_VALIDATION_FAILED',
          'La regla de fragmentación no reconstruye un recurso completo válido.',
          Map<String, Object?>.from(fragmentProfileValidation!),
        );
      }
    }

    if (decoded < minimumDecodedSamples) {
      throw const SpkFailure(
        'SPK_FRAGMENT_VALIDATION_SAMPLES',
        'No se reconstruyeron suficientes muestras fragmentadas.',
      );
    }
    _fragmentProfileValidated = true;
    fragmentProfileValidation = {
      'status': 'validated',
      'decodedSamples': decoded,
      'minimumRequired': minimumDecodedSamples,
      'sampleCount': samples.length,
      'chunkNonceRule': profile.chunkNonceRule,
      'samples': samples,
    };
    return Map<String, Object?>.from(fragmentProfileValidation!);
  }

  Future<Map<String, Object?>> validateAllResources({
    required SpkExtractControl control,
    required SpkProgress progress,
    int limit = 128 * 1024 * 1024,
  }) async {
    if (!canExtractAll) {
      throw const SpkFailure(
        'SPK_FULL_VALIDATION_PROFILE',
        'La auditoría completa requiere simples y fragmentados autenticados.',
      );
    }
    if (limit < 1) {
      throw ArgumentError.value(limit, 'limit', 'Debe ser positivo.');
    }

    final resources = index.resources.toList(growable: false);
    _validatedFormats.clear();
    final formats = <String, int>{};
    var decodedBytes = 0;
    var simple = 0;
    var fragmented = 0;

    for (var i = 0; i < resources.length; i++) {
      control.check();
      final record = resources[i];
      try {
        final result = await readEntry(record, limit: limit);
        if (record.decodedBytes > 0 &&
            result.bytes.length != record.decodedBytes) {
          throw FormatException(
            'Longitud decodificada inesperada: '
            '${result.bytes.length} != ${record.decodedBytes}.',
          );
        }
        decodedBytes += result.bytes.length;
        formats[result.format] = (formats[result.format] ?? 0) + 1;
        _validatedFormats[record.entryId] = result.format;
        if (record.simple) {
          simple++;
        } else if (record.fragmented) {
          fragmented++;
        }
      } catch (error) {
        _validatedFormats.clear();
        fullResourceValidation = {
          'status': 'failed',
          'validatedResources': i,
          'totalResources': resources.length,
          'entryId': record.idHex,
          'path': technicalPath(record),
          'recordType': record.recordType,
          'error': error.toString(),
        };
        throw SpkFailure(
          'SPK_FULL_VALIDATION_FAILED',
          'La auditoría completa encontró un recurso que no puede '
              'autenticarse y decodificarse.',
          Map<String, Object?>.from(fullResourceValidation!),
        );
      }
      if ((i + 1) % 25 == 0 || i + 1 == resources.length) {
        progress(
          'Auditando payloads SPK · ${i + 1}/${resources.length}',
          i + 1,
          resources.length,
        );
      }
    }

    final sortedFormats = formats.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    fullResourceValidation = {
      'status': 'validated',
      'validatedResources': resources.length,
      'totalResources': resources.length,
      'simpleResources': simple,
      'fragmentedResources': fragmented,
      'decodedBytes': decodedBytes,
      'formats': {
        for (final entry in sortedFormats) entry.key: entry.value,
      },
      'failures': 0,
    };
    return Map<String, Object?>.from(fullResourceValidation!);
  }

  Future<SpkReadResult> readEntry(
    SpkRecord record, {
    int limit = 128 * 1024 * 1024,
  }) async {
    if (!record.resource) {
      throw const FormatException(
        'El registro SPK seleccionado no es un recurso.',
      );
    }
    if (record.simple && !canReadSimpleResources) {
      throw const SpkFailure(
        'SPK_RESOURCE_PROFILE_UNVALIDATED',
        'El perfil de recursos simples todavía no fue autenticado contra muestras reales del SPK.',
      );
    }
    if (record.fragmented && !canReadFragmentedResources) {
      throw const SpkFailure(
        'SPK_FRAGMENT_PROFILE_UNVALIDATED',
        'La reconstrucción fragmentada todavía no fue validada extremo a extremo.',
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
      _validatedFormats[record.entryId] = format;
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
      await decryptGcm(
        cipher,
        key,
        record.nonce,
        record.tag,
        aad: profile.resourceAad.isEmpty ? null : profile.resourceAad,
      ),
      record.decodedBytes,
    );
  }

  Future<Uint8List> _readFragmented(SpkRecord record) async {
    if (!_hasFragmentCryptoMaterial) {
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
          aad: profile.resourceAad.isEmpty ? null : profile.resourceAad,
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
    'record_ordinal_chunk_le96',
    'record_ordinal_aux_le96',
    'record_ordinal_chunk1_le96',
    'aux_ordinal_chunk_le96',
    'aux_ordinal_zero_le96',
  ];

  static Uint8List fragmentNonceForRule(
    String rule,
    SpkRecord record,
    SpkAuxRecord part,
    int ordinal,
  ) {
    final data = ByteData(12);
    switch (rule) {
      case 'offset_le96':
      case 'offset_chunk0_le96':
        data.setUint64(0, part.dataOffset, Endian.little);
        data.setUint32(8, ordinal, Endian.little);
        return data.buffer.asUint8List();
      case 'entry_id_chunk_le':
      case 'entry_id_chunk0_le':
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
      case 'record_ordinal_chunk_le96':
        data.setUint64(0, record.ordinal, Endian.little);
        data.setUint32(8, ordinal, Endian.little);
        return data.buffer.asUint8List();
      case 'record_ordinal_aux_le96':
        data.setUint64(0, record.ordinal, Endian.little);
        data.setUint32(8, part.ordinal, Endian.little);
        return data.buffer.asUint8List();
      case 'record_ordinal_chunk1_le96':
        data.setUint64(0, record.ordinal, Endian.little);
        data.setUint32(8, ordinal + 1, Endian.little);
        return data.buffer.asUint8List();
      case 'aux_ordinal_chunk_le96':
        data.setUint64(0, part.ordinal, Endian.little);
        data.setUint32(8, ordinal, Endian.little);
        return data.buffer.asUint8List();
      case 'aux_ordinal_zero_le96':
        data.setUint64(0, part.ordinal, Endian.little);
        data.setUint32(8, 0, Endian.little);
        return data.buffer.asUint8List();
      default:
        throw const SpkFailure(
          'SPK_FRAGMENT_NONCE',
          'Regla de nonce fragmentado no implementada.',
        );
    }
  }

  Uint8List _fragmentNonce(SpkRecord record, SpkAuxRecord part, int ordinal) =>
      fragmentNonceForRule(profile.chunkNonceRule, record, part, ordinal);

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
      final candidate = fragmentNonceForRule(rule, record, part, local);
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

  static Future<String> deriveChunkNonceRuleFromSamples({
    required Iterable<SpkFragmentAuthSample> samples,
    required Uint8List key,
    Uint8List? aad,
    int minimumAuthenticatedSamples = 2,
  }) async {
    if ((key.length != 16 && key.length != 32) ||
        minimumAuthenticatedSamples < 1) {
      throw ArgumentError('Parámetros de derivación AES-GCM inválidos.');
    }
    var candidates = supportedChunkNonceRules.toSet();
    final successes = <String, int>{
      for (final rule in supportedChunkNonceRules) rule: 0,
    };
    for (final sample in samples) {
      final surviving = <String>{};
      for (final rule in candidates) {
        try {
          await decryptGcm(
            sample.cipherText,
            key,
            fragmentNonceForRule(
              rule,
              sample.record,
              sample.part,
              sample.localOrdinal,
            ),
            sample.part.metadata,
            aad: aad,
          );
          surviving.add(rule);
          successes[rule] = (successes[rule] ?? 0) + 1;
        } catch (_) {
          // Una combinación incorrecta falla la autenticación GCM.
        }
      }
      candidates = surviving;
      if (candidates.isEmpty) return 'unsupported';
      if (candidates.length == 1) {
        final rule = candidates.single;
        if ((successes[rule] ?? 0) >= minimumAuthenticatedSamples) {
          return rule;
        }
      }
    }
    if (candidates.length == 1) {
      final rule = candidates.single;
      if ((successes[rule] ?? 0) >= minimumAuthenticatedSamples) return rule;
    }
    return 'unsupported';
  }

  Future<String> deriveChunkNonceRuleOffline({
    int maxSamples = 12,
    int minimumAuthenticatedSamples = 2,
  }) async {
    final key = profile.effectiveResourceSecret;
    if (key == null || index.fragmentedResources.isEmpty) {
      return 'unsupported';
    }
    if (maxSamples < 1 || minimumAuthenticatedSamples < 1) {
      throw ArgumentError('Los límites de derivación deben ser positivos.');
    }

    final samples = <SpkFragmentAuthSample>[];
    for (final record in index.fragmentedResources) {
      final parts = index.auxiliary.sublist(
        record.auxiliaryStart,
        record.auxiliaryStart + record.chunkCount,
      );
      for (var local = 0; local < parts.length; local++) {
        if (samples.length >= maxSamples) break;
        final part = parts[local];
        samples.add(
          SpkFragmentAuthSample(
            record: record,
            part: part,
            localOrdinal: local,
            cipherText: await readRange(
              file,
              part.dataOffset,
              part.storedBytes,
              fileBytes,
            ),
          ),
        );
      }
      if (samples.length >= maxSamples) break;
    }
    return deriveChunkNonceRuleFromSamples(
      samples: samples,
      key: key,
      aad: profile.resourceAad.isEmpty ? null : profile.resourceAad,
      minimumAuthenticatedSamples: minimumAuthenticatedSamples,
    );
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
    if (startsWith(bytes, [0x45, 0x46, 0x54])) return 'EFT';
    if (startsWith(bytes, [0x46, 0x4c, 0x44]) ||
        startsWith(bytes, [0x44, 0x55, 0x4e])) {
      return 'WLD';
    }
    if (_looksLikeTga(bytes)) return 'TGA';

    if (SeedData.isEncoded(bytes)) {
      try {
        SeedData.decode(bytes, verifyChecksum: true);
        return 'SDATA';
      } catch (_) {}
    }

    if (bytes.length >= 3) {
      final signature = ascii.decode(
        bytes.sublist(0, bytes.length < 8 ? bytes.length : 8),
        allowInvalid: true,
      );
      if (signature.startsWith('ML')) {
        try {
          readMlt(bytes, 'SPK:MLT');
          return 'MLT';
        } catch (_) {}
      }
      if (signature.startsWith('ITM') ||
          signature.startsWith('IT2') ||
          signature.startsWith('pandaIT2')) {
        try {
          readItm(bytes, 'SPK:ITM');
          return 'ITM';
        } catch (_) {}
      }
      if (signature.startsWith('MO2') || signature.startsWith('MO4')) {
        try {
          readMon(bytes, 'SPK:MON');
          return 'MON';
        } catch (_) {}
      }
    }

    if (bytes.length >= 8) {
      final first = ByteData.sublistView(bytes, 0, 4).getUint32(
        0,
        Endian.little,
      );
      if (first == 0 || first == 444) {
        try {
          MeshData.skinned(bytes, 'SPK:3DC');
          return '3DC';
        } catch (_) {}
        try {
          ClipData.parse(bytes, 'SPK:ANI');
          return 'ANI';
        } catch (_) {}
      }
      if (first > 0 && first <= 260 && bytes.length >= 4 + first) {
        try {
          MeshData.object(bytes, 'SPK:3DO');
          return '3DO';
        } catch (_) {}
      }
    }

    final text = _textFormat(bytes);
    if (text != null) return text;
    return 'BIN';
  }

  static bool _looksLikeTga(Uint8List bytes) {
    if (bytes.length < 18) return false;
    final colorMap = bytes[1];
    final imageType = bytes[2];
    final width = bytes[12] | (bytes[13] << 8);
    final height = bytes[14] | (bytes[15] << 8);
    final bits = bytes[16];
    return (colorMap == 0 || colorMap == 1) &&
        const {1, 2, 3, 9, 10, 11}.contains(imageType) &&
        width > 0 &&
        height > 0 &&
        const {8, 16, 24, 32}.contains(bits);
  }

  static String? _textFormat(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > 8 * 1024 * 1024) return null;
    final sampleLength = bytes.length < 4096 ? bytes.length : 4096;
    final sample = bytes.take(sampleLength).toList();
    var printable = 0;
    for (final value in sample) {
      if (value == 9 ||
          value == 10 ||
          value == 13 ||
          (value >= 32 && value <= 126) ||
          value >= 0x80) {
        printable++;
      }
    }
    if (sample.isEmpty || printable / sample.length < 0.92) return null;
    final text = utf8.decode(sample, allowMalformed: true).trimLeft();
    if (text.startsWith('<?xml') || text.startsWith('<')) return 'XML';
    if (text.startsWith('{') || text.startsWith('[')) return 'JSON';
    if (RegExp(r'^\s*\[[^\]]+\]', multiLine: true).hasMatch(text)) {
      return 'INI';
    }
    return 'TXT';
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
      case 'MLT':
        return '.mlt';
      case 'ITM':
        return '.itm';
      case 'MON':
        return '.mon';
      case 'SDATA':
        return '.sdata';
      case 'OGG':
        return '.ogg';
      case 'RIFF':
        return '.wav';
      case 'ZIP':
        return '.zip';
      case 'PE':
        return '.exe';
      case 'EFT':
        return '.eft';
      case 'WLD':
        return '.wld';
      case '3DC':
        return '.3dc';
      case '3DO':
        return '.3do';
      case 'ANI':
        return '.ani';
      case 'XML':
        return '.xml';
      case 'JSON':
        return '.json';
      case 'INI':
        return '.ini';
      case 'TXT':
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
    bool continueOnError = false,
  }) async {
    if (!await parent.exists()) {
      throw const FormatException('La carpeta de destino no existe.');
    }
    final list = (selection ?? index.resources)
        .where((e) => e.resource)
        .toList();
    if (list.any((e) => e.simple) && !canReadSimpleResources) {
      throw const SpkFailure(
        'SPK_RESOURCE_PROFILE_UNVALIDATED',
        'La extracción permanece bloqueada hasta autenticar el perfil de recursos simples.',
      );
    }
    if (list.any((e) => e.fragmented) && !canReadFragmentedResources) {
      throw const SpkFailure(
        'SPK_FRAGMENT_PROFILE_UNVALIDATED',
        'La extracción fragmentada permanece bloqueada hasta validar reconstrucciones completas.',
      );
    }
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
    final exportFailures = <Map<String, Object?>>[];
    var bytes = 0;
    try {
      for (var i = 0; i < list.length; i++) {
        control.check();
        final record = list[i];
        try {
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
        } catch (error) {
          if (!continueOnError) rethrow;
          exportFailures.add({
            'entryId': record.idHex,
            'path': technicalPath(record),
            'storedBytes': record.storedBytes,
            'decodedBytes': record.decodedBytes,
            'error': error.toString(),
          });
          progress(
            'Omitido ${technicalPath(record)}: no pudo decodificarse',
            i + 1,
            list.length,
          );
        }
      }      await File('${stage.path}/_SPK_MANIFEST.json').writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'schema': 1,
          'source': file.path,
          'index': index.summary(),
          'profile': profile.publicJson(),
          'files': manifest,
          'failures': exportFailures,
          'complete': exportFailures.isEmpty,
        }),
        flush: true,
      );
      await stage.rename(published.path);
      return {
        'folder': published.path,
        'files': manifest.length,
        'failures': exportFailures.length,
        'bytes': bytes,
        'complete': exportFailures.isEmpty,
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
    'resourceProfileValidation': resourceProfileValidation,
    'fragmentProfileValidation': fragmentProfileValidation,
    'fullResourceValidation': fullResourceValidation,
    'fullyValidatedResources': fullyValidatedResources,
    'reads': reads,
    'bytesRead': bytesRead,
    'recentReads': recentReads,
    'failures': failures,
  };
}