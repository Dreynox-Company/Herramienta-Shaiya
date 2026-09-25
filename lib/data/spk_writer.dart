import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:zstandard/zstandard.dart';

import '../core/spk_archive.dart';
import 'spk_source.dart';

class SpkWriterResult {
  final String file;
  final String profileFile;
  final String namesFile;
  final String auditFile;
  final int resources;
  final int replaced;
  final int bytes;
  final String indexSha256;
  final String footerSha256;
  final Map<String, Object?> validation;

  const SpkWriterResult({
    required this.file,
    required this.profileFile,
    required this.namesFile,
    required this.auditFile,
    required this.resources,
    required this.replaced,
    required this.bytes,
    required this.indexSha256,
    required this.footerSha256,
    required this.validation,
  });

  Map<String, Object?> toJson() => {
    'file': file,
    'profileFile': profileFile,
    'namesFile': namesFile,
    'auditFile': auditFile,
    'resources': resources,
    'replaced': replaced,
    'bytes': bytes,
    'indexSha256': indexSha256,
    'footerSha256': footerSha256,
    'validation': validation,
  };
}

class SpkWriter {
  static final Random _random = Random.secure();

  static int _u64(int value) => value.toUnsigned(64);

  static Uint8List _nonce() =>
      Uint8List.fromList(List<int>.generate(12, (_) => _random.nextInt(256)));

  static Future<SecretBox> _encrypt(
    Uint8List plain,
    Uint8List key,
    Uint8List nonce, {
    Uint8List? aad,
  }) {
    final algorithm = key.length == 16
        ? AesGcm.with128bits()
        : key.length == 32
        ? AesGcm.with256bits()
        : throw const FormatException('Clave AES-GCM SPK inválida.');
    return algorithm.encrypt(
      plain,
      secretKey: SecretKey(key),
      nonce: nonce,
      aad: aad ?? const <int>[],
    );
  }

  static Future<Uint8List> _simplePacked(
    SpkArchiveSource source,
    SpkRecord record,
  ) async {
    final key = source.profile.effectiveResourceSecret;
    if (key == null) {
      throw const SpkFailure(
        'SPK_WRITER_PROFILE',
        'Falta la clave de recursos para reconstruir DATA.SPK.',
      );
    }
    final cipher = await SpkArchiveSource.readRange(
      source.file,
      record.dataOffset,
      record.storedBytes,
      source.fileBytes,
    );
    return SpkArchiveSource.decryptGcm(
      cipher,
      key,
      record.nonce,
      record.tag,
      aad: source.profile.resourceAad.isEmpty
          ? null
          : source.profile.resourceAad,
    );
  }

  static Future<List<Uint8List>> _fragmentPackedParts(
    SpkArchiveSource source,
    SpkRecord record,
  ) async {
    final key = source.profile.effectiveResourceSecret;
    if (key == null || source.profile.chunkNonceRule == 'unsupported') {
      throw const SpkFailure(
        'SPK_WRITER_FRAGMENT_PROFILE',
        'Falta un perfil fragmentado reproducible para reconstruir DATA.SPK.',
      );
    }
    final rows = source.index.auxiliary.sublist(
      record.auxiliaryStart,
      record.auxiliaryStart + record.chunkCount,
    );
    final out = <Uint8List>[];
    for (var i = 0; i < rows.length; i++) {
      final part = rows[i];
      final cipher = await SpkArchiveSource.readRange(
        source.file,
        part.dataOffset,
        part.storedBytes,
        source.fileBytes,
      );
      out.add(
        await SpkArchiveSource.decryptGcm(
          cipher,
          key,
          SpkArchiveSource.fragmentNonceForRule(
            source.profile.chunkNonceRule,
            record,
            part,
            i,
          ),
          part.metadata,
          aad: source.profile.resourceAad.isEmpty
              ? null
              : source.profile.resourceAad,
        ),
      );
    }
    return out;
  }

  static Future<Uint8List> _packReplacement(
    Uint8List decoded,
    Uint8List originalPacked,
  ) async {
    if (!SpkArchiveSource.startsWith(
      originalPacked,
      SpkArchiveSource.zstdMagic,
    )) {
      return Uint8List.fromList(decoded);
    }
    final packed = await Zstandard().compress(decoded, 3);
    if (packed == null ||
        !SpkArchiveSource.startsWith(packed, SpkArchiveSource.zstdMagic)) {
      throw const SpkFailure(
        'SPK_WRITER_ZSTD',
        'Zstandard no pudo empaquetar el recurso editado.',
      );
    }
    return packed;
  }

  static List<Uint8List> _splitPacked(Uint8List packed, int blockBytes) {
    if (packed.isEmpty) {
      throw const SpkFailure(
        'SPK_WRITER_FRAGMENT_EMPTY',
        'Un recurso fragmentado no puede reconstruirse con payload vacío.',
      );
    }
    final block = blockBytes > 0 ? blockBytes : 262144;
    final out = <Uint8List>[];
    for (var at = 0; at < packed.length; at += block) {
      final end = at + block < packed.length ? at + block : packed.length;
      out.add(Uint8List.fromList(packed.sublist(at, end)));
    }
    return out;
  }

  static Uint8List _simpleMetadata(Uint8List nonce, Uint8List tag, int flags) {
    final out = Uint8List(32)
      ..setRange(0, 12, nonce)
      ..setRange(12, 28, tag);
    ByteData.sublistView(out).setUint32(28, flags, Endian.little);
    return out;
  }

  static Uint8List _fragmentMetadata(SpkRecord original, int chunks) {
    final out = Uint8List.fromList(original.metadata);
    ByteData.sublistView(out).setUint32(28, chunks, Endian.little);
    return out;
  }

  static Uint8List _serializeRecords(List<SpkRecord> records) {
    final out = Uint8List(records.length * spkRecordBytes);
    final data = ByteData.sublistView(out);
    for (var i = 0; i < records.length; i++) {
      final row = records[i];
      final o = i * spkRecordBytes;
      data.setUint64(o, _u64(row.entryId), Endian.little);
      data.setUint64(o + 8, row.dataOffset, Endian.little);
      data.setUint64(o + 16, row.storedBytes, Endian.little);
      data.setUint64(o + 24, row.storedBytes, Endian.little);
      data.setUint64(o + 32, row.decodedBytes, Endian.little);
      data.setUint32(o + 40, row.recordType, Endian.little);
      data.setUint32(o + 44, row.auxiliaryStart, Endian.little);
      out.setRange(o + 48, o + 80, row.metadata);
    }
    return out;
  }

  static Uint8List _serializeAux(List<SpkAuxRecord> rows) {
    final out = Uint8List(rows.length * spkAuxRecordBytes);
    final data = ByteData.sublistView(out);
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final o = i * spkAuxRecordBytes;
      data.setUint64(o, row.dataOffset, Endian.little);
      data.setUint32(o + 8, row.storedBytes, Endian.little);
      data.setUint32(o + 12, row.storedBytes, Endian.little);
      out.setRange(o + 16, o + 32, row.metadata);
    }
    return out;
  }

  static Uint8List _buildHeader(
    Uint8List template, {
    required int indexOffset,
    required int indexStoredBytes,
    required int indexDecodedBytes,
    required int recordCount,
    required int blockBytes,
    required int auxiliaryOffset,
    required int auxiliaryCount,
    required Uint8List indexNonce,
    required Uint8List indexTag,
  }) {
    if (template.length != spkHeaderBytes) {
      throw const FormatException('Cabecera SPK base inválida.');
    }
    final out = Uint8List.fromList(template);
    final data = ByteData.sublistView(out);
    data.setUint32(0, spkMagic, Endian.little);
    data.setUint32(4, spkVersion3, Endian.little);
    data.setUint64(8, indexOffset, Endian.little);
    data.setUint64(16, indexStoredBytes, Endian.little);
    data.setUint64(24, indexDecodedBytes, Endian.little);
    data.setUint32(32, recordCount, Endian.little);
    data.setUint32(36, blockBytes, Endian.little);
    out.setRange(40, 52, indexNonce);
    out.setRange(52, 68, indexTag);
    data.setUint64(100, auxiliaryOffset, Endian.little);
    data.setUint32(108, auxiliaryCount, Endian.little);
    return out;
  }

  static Future<void> _copyCipher(
    RandomAccessFile input,
    RandomAccessFile output,
    int offset,
    int bytes,
  ) async {
    await input.setPosition(offset);
    var remaining = bytes;
    final buffer = Uint8List(1024 * 1024);
    while (remaining > 0) {
      final wanted = remaining < buffer.length ? remaining : buffer.length;
      final read = await input.readInto(buffer, 0, wanted);
      if (read <= 0) {
        throw const FileSystemException(
          'El DATA.SPK terminó durante una copia de payload.',
        );
      }
      await output.writeFrom(buffer, 0, read);
      remaining -= read;
    }
  }

  static Future<SpkWriterResult> rebuild(
    SpkArchiveSource source,
    File target, {
    Map<int, Uint8List> replacements = const <int, Uint8List>{},
    required SpkExtractControl control,
    required SpkProgress progress,
  }) async {
    if (!source.fullyValidatedResources) {
      throw const SpkFailure(
        'SPK_WRITER_AUDIT',
        'Reempacar DATA.SPK exige una auditoría completa previa.',
      );
    }
    final resourceKey = source.profile.effectiveResourceSecret;
    if (resourceKey == null) {
      throw const SpkFailure(
        'SPK_WRITER_PROFILE',
        'Falta la clave autenticada de recursos.',
      );
    }
    if (source.index.fragmentedResources.isNotEmpty &&
        source.profile.chunkNonceRule == 'unsupported') {
      throw const SpkFailure(
        'SPK_WRITER_FRAGMENT_RULE',
        'La regla de nonce fragmentado no está validada.',
      );
    }
    if (target.absolute.path.toLowerCase() ==
        source.file.absolute.path.toLowerCase()) {
      throw const FileSystemException(
        'El escritor nunca sobrescribe el DATA.SPK original.',
      );
    }
    if (await target.exists()) {
      throw const FileSystemException(
        'El destino DATA.SPK ya existe. Usa un nombre nuevo.',
      );
    }

    final knownIds = source.index.resources.map((e) => e.entryId).toSet();
    for (final id in replacements.keys) {
      if (!knownIds.contains(id)) {
        throw FormatException(
          'El reemplazo ${spkU64Hex(id)} no pertenece a este SPK.',
        );
      }
    }

    final headerTemplate = await SpkArchiveSource.readRange(
      source.file,
      0,
      spkHeaderBytes,
      source.fileBytes,
    );
    final footer = await SpkArchiveSource.readRange(
      source.file,
      source.fileBytes - spkFooterBytes,
      spkFooterBytes,
      source.fileBytes,
    );
    final temp = File(
      '${target.path}.${DateTime.now().microsecondsSinceEpoch}.partial',
    );
    final profileFile = File('${target.path}.profile.json');
    final namesFile = File('${target.path}.names.json');
    final auditFile = File('${target.path}.audit.json');
    if (await temp.exists()) await temp.delete();

    RandomAccessFile? input;
    RandomAccessFile? output;
    try {
      input = await source.file.open();
      output = await temp.open(mode: FileMode.write);
      await output.writeFrom(headerTemplate);
      var dataOffset = spkHeaderBytes;
      final rewritten = <int, SpkRecord>{};
      final resources = source.index.resources.toList()
        ..sort((a, b) => a.dataOffset.compareTo(b.dataOffset));

      final fragmentPlans = <int, List<Uint8List>>{};
      for (final row in source.index.records.where((row) => row.fragmented)) {
        final replacement = replacements[row.entryId];
        if (replacement == null) continue;
        control.check();
        final originalParts = await _fragmentPackedParts(source, row);
        final originalPacked = BytesBuilder(copy: false);
        for (final part in originalParts) {
          originalPacked.add(part);
        }
        final packed = await _packReplacement(
          replacement,
          originalPacked.takeBytes(),
        );
        fragmentPlans[row.ordinal] = _splitPacked(
          packed,
          source.index.header.blockBytes,
        );
      }

      final fragmentStarts = <int, int>{};
      var auxiliaryCount = 0;
      for (final row in source.index.records.where((row) => row.fragmented)) {
        fragmentStarts[row.ordinal] = auxiliaryCount;
        auxiliaryCount += fragmentPlans[row.ordinal]?.length ?? row.chunkCount;
      }
      final auxiliary = List<SpkAuxRecord?>.filled(auxiliaryCount, null);

      for (var i = 0; i < resources.length; i++) {
        control.check();
        final row = resources[i];
        final replacement = replacements[row.entryId];

        if (row.simple && replacement == null) {
          await _copyCipher(input, output, row.dataOffset, row.storedBytes);
          rewritten[row.ordinal] = SpkRecord(
            ordinal: row.ordinal,
            entryId: row.entryId,
            dataOffset: dataOffset,
            storedBytes: row.storedBytes,
            decodedBytes: row.decodedBytes,
            recordType: row.recordType,
            auxiliaryStart: row.auxiliaryStart,
            chunkCount: 0,
            metadata: Uint8List.fromList(row.metadata),
          );
          dataOffset += row.storedBytes;
        } else if (row.simple) {
          final originalPacked = await _simplePacked(source, row);
          final packed = await _packReplacement(replacement!, originalPacked);
          final nonce = _nonce();
          final box = await _encrypt(
            packed,
            resourceKey,
            nonce,
            aad: source.profile.resourceAad.isEmpty
                ? null
                : source.profile.resourceAad,
          );
          final cipher = Uint8List.fromList(box.cipherText);
          await output.writeFrom(cipher);
          rewritten[row.ordinal] = SpkRecord(
            ordinal: row.ordinal,
            entryId: row.entryId,
            dataOffset: dataOffset,
            storedBytes: cipher.length,
            decodedBytes: replacement.length,
            recordType: row.recordType,
            auxiliaryStart: row.auxiliaryStart,
            chunkCount: 0,
            metadata: _simpleMetadata(
              nonce,
              Uint8List.fromList(box.mac.bytes),
              row.flags,
            ),
          );
          dataOffset += cipher.length;
        } else if (row.fragmented) {
          final planned = fragmentPlans[row.ordinal];
          final clearParts = planned ?? await _fragmentPackedParts(source, row);
          final decodedBytes = replacement == null
              ? row.decodedBytes
              : replacement.length;
          final auxiliaryStart = fragmentStarts[row.ordinal];
          if (auxiliaryStart == null) {
            throw const SpkFailure(
              'SPK_WRITER_FRAGMENT_PLAN',
              'No se planificó la cadena auxiliar del recurso.',
            );
          }
          final resourceOffset = dataOffset;
          var totalStored = 0;
          for (var local = 0; local < clearParts.length; local++) {
            final clear = clearParts[local];
            final partOrdinal = auxiliaryStart + local;
            final placeholderRecord = SpkRecord(
              ordinal: row.ordinal,
              entryId: row.entryId,
              dataOffset: resourceOffset,
              storedBytes: 0,
              decodedBytes: decodedBytes,
              recordType: row.recordType,
              auxiliaryStart: auxiliaryStart,
              chunkCount: clearParts.length,
              metadata: _fragmentMetadata(row, clearParts.length),
            );
            final placeholderPart = SpkAuxRecord(
              ordinal: partOrdinal,
              dataOffset: dataOffset,
              storedBytes: clear.length,
              metadata: Uint8List(16),
            );
            final nonce = SpkArchiveSource.fragmentNonceForRule(
              source.profile.chunkNonceRule,
              placeholderRecord,
              placeholderPart,
              local,
            );
            final box = await _encrypt(
              clear,
              resourceKey,
              nonce,
              aad: source.profile.resourceAad.isEmpty
                  ? null
                  : source.profile.resourceAad,
            );
            final cipher = Uint8List.fromList(box.cipherText);
            await output.writeFrom(cipher);
            auxiliary[partOrdinal] = SpkAuxRecord(
              ordinal: partOrdinal,
              dataOffset: dataOffset,
              storedBytes: cipher.length,
              metadata: Uint8List.fromList(box.mac.bytes),
            );
            dataOffset += cipher.length;
            totalStored += cipher.length;
          }
          rewritten[row.ordinal] = SpkRecord(
            ordinal: row.ordinal,
            entryId: row.entryId,
            dataOffset: resourceOffset,
            storedBytes: totalStored,
            decodedBytes: decodedBytes,
            recordType: row.recordType,
            auxiliaryStart: auxiliaryStart,
            chunkCount: clearParts.length,
            metadata: _fragmentMetadata(row, clearParts.length),
          );
        }

        progress(
          'Reempacando DATA.SPK · ${i + 1}/${resources.length}',
          i + 1,
          resources.length,
        );
      }

      if (auxiliary.any((row) => row == null)) {
        throw const SpkFailure(
          'SPK_WRITER_AUX_INCOMPLETE',
          'No se reconstruyó toda la tabla auxiliar del SPK.',
        );
      }
      final finalAuxiliary = auxiliary.cast<SpkAuxRecord>();
      final auxiliaryOffset = dataOffset;
      final auxiliaryBytes = _serializeAux(finalAuxiliary);
      await output.writeFrom(auxiliaryBytes);
      final indexOffset = auxiliaryOffset + auxiliaryBytes.length;

      final records = <SpkRecord>[
        for (final original in source.index.records)
          rewritten[original.ordinal] ?? original,
      ];
      final provisionalHeader = SpkHeader(
        version: spkVersion3,
        indexOffset: indexOffset,
        indexStoredBytes: 1,
        indexDecodedBytes: records.length * spkRecordBytes,
        recordCount: records.length,
        blockBytes: source.index.header.blockBytes,
        auxiliaryOffset: auxiliaryOffset,
        auxiliaryCount: finalAuxiliary.length,
        indexNonce: Uint8List(12),
        indexTag: Uint8List(16),
      );
      SpkIndex.validateRelationships(
        records,
        finalAuxiliary,
        provisionalHeader,
      );

      final decodedIndex = _serializeRecords(records);
      final packedIndex = await Zstandard().compress(decodedIndex, 3);
      if (packedIndex == null ||
          !SpkArchiveSource.startsWith(
            packedIndex,
            SpkArchiveSource.zstdMagic,
          )) {
        throw const SpkFailure(
          'SPK_WRITER_INDEX_ZSTD',
          'No se pudo comprimir el índice reconstruido.',
        );
      }
      final indexNonce = _nonce();
      final indexBox = await _encrypt(
        packedIndex,
        source.profile.indexSecret,
        indexNonce,
      );
      final indexCipher = Uint8List.fromList(indexBox.cipherText);
      await output.writeFrom(indexCipher);
      await output.writeFrom(footer);

      final header = _buildHeader(
        headerTemplate,
        indexOffset: indexOffset,
        indexStoredBytes: indexCipher.length,
        indexDecodedBytes: decodedIndex.length,
        recordCount: records.length,
        blockBytes: source.index.header.blockBytes,
        auxiliaryOffset: auxiliaryOffset,
        auxiliaryCount: finalAuxiliary.length,
        indexNonce: indexNonce,
        indexTag: Uint8List.fromList(indexBox.mac.bytes),
      );
      await output.setPosition(0);
      await output.writeFrom(header);
      await output.flush();
      await output.close();
      output = null;
      await input.close();
      input = null;

      final indexHash = sha256.convert(indexCipher).toString();
      final candidateProfile = SpkCryptoProfile(
        profileId: '${source.profile.profileId}-repacked',
        indexSha256: indexHash,
        indexSecret: Uint8List.fromList(source.profile.indexSecret),
        resourceSecret: source.profile.resourceSecret == null
            ? null
            : Uint8List.fromList(source.profile.resourceSecret!),
        resourceAad: Uint8List.fromList(source.profile.resourceAad),
        resourceKeyIsIndexKey: source.profile.resourceKeyIsIndexKey,
        chunkNonceRule: source.profile.chunkNonceRule,
      );

      final candidate = await SpkArchiveSource.open(
        temp.path,
        candidateProfile,
        names: source.names,
      );
      await candidate.validateSimpleResourceProfile();
      if (candidate.index.fragmentedResources.isNotEmpty) {
        await candidate.validateFragmentedResourceProfile();
      }
      final validation = await candidate.validateAllResources(
        control: control,
        progress: (message, done, total) =>
            progress('Validando SPK reconstruido · $done/$total', done, total),
      );
      if (!candidate.fullyValidatedResources) {
        throw const SpkFailure(
          'SPK_WRITER_SELF_CHECK',
          'El SPK reconstruido no superó la auditoría integral.',
        );
      }

      await temp.rename(target.path);
      await profileFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'profileId': candidateProfile.profileId,
          'indexSha256': indexHash,
          'index': {
            'algorithm': 'AES-GCM',
            'secretHex': spkHex(candidateProfile.indexSecret),
          },
          'resources': {
            'algorithm': 'AES-GCM',
            'secretHex': spkHex(resourceKey),
            'useIndexKey': candidateProfile.resourceKeyIsIndexKey,
            if (candidateProfile.resourceAad.isNotEmpty)
              'aadHex': spkHex(candidateProfile.resourceAad),
            'chunkNonceRule': candidateProfile.chunkNonceRule,
          },
        }),
        flush: true,
      );

      await namesFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          ...source.names.toJson(),
          'spkIndexSha256': indexHash,
          'sourceRepackedFrom': source.index.encryptedIndexSha256,
        }),
        flush: true,
      );
      await auditFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'schema': 1,
          'source': target.path,
          'indexSha256': indexHash,
          'profileId': candidateProfile.profileId,
          'resourceKeySha256': sha256.convert(resourceKey).toString(),
          'chunkNonceRule': candidateProfile.chunkNonceRule,
          'validation': validation,
          'resourceFormats': candidate.validatedFormatsJson,
          'diagnostics': candidate.diagnostics(),
          'footerPreservedSha256': sha256.convert(footer).toString(),
        }),
        flush: true,
      );

      return SpkWriterResult(
        file: target.path,
        profileFile: profileFile.path,
        namesFile: namesFile.path,
        auditFile: auditFile.path,
        resources: resources.length,
        replaced: replacements.length,
        bytes: await target.length(),
        indexSha256: indexHash,
        footerSha256: sha256.convert(footer).toString(),
        validation: validation,
      );
    } catch (_) {
      if (output != null) {
        try {
          await output.close();
        } catch (_) {}
      }
      if (input != null) {
        try {
          await input.close();
        } catch (_) {}
      }
      if (await temp.exists()) await temp.delete();
      if (await target.exists()) await target.delete();
      if (await profileFile.exists()) await profileFile.delete();
      if (await namesFile.exists()) await namesFile.delete();
      if (await auditFile.exists()) await auditFile.delete();
      rethrow;
    }
  }
}
