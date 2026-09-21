import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/spk_archive.dart';
import 'package:herramienta_shaiya/data/spk_source.dart';

Uint8List _nonce(int seed) =>
    Uint8List.fromList(List<int>.generate(12, (i) => (seed + i) & 0xff));

Future<SpkArchiveSource> _source(
  Directory root, {
  required String hintedPath,
}) async {
  final key = Uint8List.fromList(List<int>.generate(16, (i) => 0x61 + i));
  final clear = Uint8List(64);
  clear.setRange(0, 4, const <int>[0x44, 0x44, 0x53, 0x20]);
  for (var i = 4; i < clear.length; i++) {
    clear[i] = (i * 3) & 0xff;
  }

  final nonce = _nonce(0x20);
  final box = await AesGcm.with128bits().encrypt(
    clear,
    secretKey: SecretKey(key),
    nonce: nonce,
  );
  final cipher = Uint8List.fromList(box.cipherText);
  final file = File('${root.path}/fixture.spk');
  await file.writeAsBytes(
    <int>[...Uint8List(spkHeaderBytes), ...cipher],
    flush: true,
  );

  final metadata = Uint8List(32)
    ..setRange(0, 12, nonce)
    ..setRange(12, 28, box.mac.bytes);
  final simple = SpkRecord(
    ordinal: 0,
    entryId: 0x1001,
    dataOffset: spkHeaderBytes,
    storedBytes: cipher.length,
    decodedBytes: clear.length,
    recordType: 1,
    auxiliaryStart: 0xffffffff,
    chunkCount: 0,
    metadata: metadata,
  );
  final fragmented = SpkRecord(
    ordinal: 1,
    entryId: 0x2001,
    dataOffset: spkHeaderBytes + cipher.length,
    storedBytes: 32,
    decodedBytes: 777,
    recordType: 3,
    auxiliaryStart: 0,
    chunkCount: 1,
    metadata: Uint8List(32),
  );
  final header = SpkHeader(
    version: spkVersion3,
    indexOffset: await file.length(),
    indexStoredBytes: 0,
    indexDecodedBytes: 2 * spkRecordBytes,
    recordCount: 2,
    blockBytes: 262144,
    auxiliaryOffset: await file.length(),
    auxiliaryCount: 1,
    indexNonce: Uint8List(12),
    indexTag: Uint8List(16),
  );
  final index = SpkIndex(
    header: header,
    records: <SpkRecord>[simple, fragmented],
    auxiliary: <SpkAuxRecord>[
      SpkAuxRecord(
        ordinal: 0,
        dataOffset: fragmented.dataOffset,
        storedBytes: fragmented.storedBytes,
        metadata: Uint8List(16),
      ),
    ],
    encryptedIndexSha256: 'fixture-index',
    decodedIndexSha256: 'fixture-decoded',
  );
  final profile = SpkCryptoProfile(
    profileId: 'fixture',
    indexSha256: 'fixture-index',
    indexSecret: key,
    resourceSecret: key,
    resourceAad: Uint8List(0),
    resourceKeyIsIndexKey: false,
    chunkNonceRule: 'unsupported',
  );
  final names = SpkNameMap(
    const <int, String>{},
    <int, Object?>{
      simple.entryId: SpkNameHint(
        path: hintedPath,
        confidence: 'strong-inferred',
        evidence: 'fixture-hint',
      ),
    },
  );
  return SpkArchiveSource.fromValidatedIndexForTesting(
    file: file,
    index: index,
    profile: profile,
    names: names,
  );
}

Future<File> _referenceFile(
  Directory root,
  String relative,
) async {
  final file = File('${root.path}/$relative');
  await file.parent.create(recursive: true);
  final bytes = Uint8List(64);
  bytes.setRange(0, 4, const <int>[0x44, 0x44, 0x53, 0x20]);
  for (var i = 4; i < bytes.length; i++) {
    bytes[i] = (i * 3) & 0xff;
  }
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

void main() {
  test('name verification confirms hinted path first and reports fragments',
      () async {
    final root = await Directory.systemTemp.createTemp('spk-name-verify-');
    final reference = Directory('${root.path}/DATA');
    try {
      const path = 'Character/Human/DDS/humm_torso001.dds';
      final source = await _source(root, hintedPath: path);
      await _referenceFile(reference, path);
      await source.validateSimpleResourceProfile(
        minimumAuthenticatedSamples: 1,
        maxSamples: 1,
      );

      final report = await source.verifyNamesFromDirectory(
        reference,
        control: SpkExtractControl(),
        progress: (_, __, ___) {},
      );

      expect(report['confirmed'], 1);
      expect(report['simpleVerified'], 1);
      expect(report['fragmentedVerified'], 0);
      expect(report['fragmentedSkipped'], 1);
      expect(report['hintPathMatches'], 1);
      expect(report['sizeScanMatches'], 0);
      expect(source.names.confirmedPath(0x1001), path);
      expect(source.names.isInferred(0x1001), isFalse);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('name verification falls back to same-size hash search', () async {
    final root = await Directory.systemTemp.createTemp('spk-name-search-');
    final reference = Directory('${root.path}/DATA');
    try {
      const actual = 'Character/Human/DDS/humm_torso001.dds';
      final source = await _source(
        root,
        hintedPath: 'Character/Human/DDS/wrong.dds',
      );
      await _referenceFile(reference, actual);
      await source.validateSimpleResourceProfile(
        minimumAuthenticatedSamples: 1,
        maxSamples: 1,
      );

      final report = await source.verifyNamesFromDirectory(
        reference,
        control: SpkExtractControl(),
        progress: (_, __, ___) {},
      );

      expect(report['confirmed'], 1);
      expect(report['hintPathMatches'], 0);
      expect(report['sizeScanMatches'], 1);
      expect(source.names.confirmedPath(0x1001), actual);
    } finally {
      await root.delete(recursive: true);
    }
  });
}
