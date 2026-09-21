import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/spk_archive.dart';
import 'package:herramienta_shaiya/data/library.dart';
import 'package:herramienta_shaiya/data/spk_source.dart';

Uint8List _nonce(int seed) =>
    Uint8List.fromList(List<int>.generate(12, (i) => (seed + i) & 0xff));

Future<SpkArchiveSource> _source(
  Directory root, {
  required bool strongName,
}) async {
  final key = Uint8List.fromList(List<int>.generate(16, (i) => 0x40 + i));
  final clear = Uint8List(128)
    ..setRange(0, 4, const <int>[0x44, 0x44, 0x53, 0x20]);
  final nonce = _nonce(0x20);
  final box = await AesGcm.with128bits().encrypt(
    clear,
    secretKey: SecretKey(key),
    nonce: nonce,
  );
  final cipher = Uint8List.fromList(box.cipherText);
  final file = File('${root.path}/payload.bin');
  final bytes = BytesBuilder(copy: false)
    ..add(Uint8List(spkHeaderBytes))
    ..add(cipher);
  await file.writeAsBytes(bytes.takeBytes(), flush: true);

  final metadata = Uint8List(32)
    ..setRange(0, 12, nonce)
    ..setRange(12, 28, box.mac.bytes);
  final record = SpkRecord(
    ordinal: 0,
    entryId: 0x1234,
    dataOffset: spkHeaderBytes,
    storedBytes: cipher.length,
    decodedBytes: clear.length,
    recordType: 1,
    auxiliaryStart: 0xffffffff,
    chunkCount: 0,
    metadata: metadata,
  );
  final header = SpkHeader(
    version: spkVersion3,
    indexOffset: spkHeaderBytes + cipher.length,
    indexStoredBytes: 1,
    indexDecodedBytes: spkRecordBytes,
    recordCount: 1,
    blockBytes: 262144,
    auxiliaryOffset: spkHeaderBytes + cipher.length,
    auxiliaryCount: 0,
    indexNonce: Uint8List(12),
    indexTag: Uint8List(16),
  );
  final index = SpkIndex(
    header: header,
    records: <SpkRecord>[record],
    auxiliary: const <SpkAuxRecord>[],
    encryptedIndexSha256: 'fixture-index',
    decodedIndexSha256: 'fixture-decoded',
  );
  final names = SpkNameMap(
    const <int, String>{},
    <int, Object?>{
      record.entryId: SpkNameHint(
        path: 'Character/Human/DDS/test.dds',
        confidence: strongName ? 'strong-inferred' : 'inferred',
        evidence: 'synthetic-library-adapter',
      ),
    },
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
  return SpkArchiveSource.fromValidatedIndexForTesting(
    file: file,
    index: index,
    profile: profile,
    names: names,
  );
}

void main() {
  test('validated SPK strong routes mount and read through Library', () async {
    final root = await Directory.systemTemp.createTemp('spk-library-');
    try {
      final source = await _source(root, strongName: true);
      expect(source.canExtractAll, isFalse);

      await source.validateSimpleResourceProfile(
        minimumAuthenticatedSamples: 1,
        maxSamples: 1,
      );
      expect(source.canExtractAll, isTrue);

      final library = Library.fromSpkSource(source);
      expect(library.spkArchive, same(source));
      expect(library.sourceLabel, contains('DATA.SPK'));
      expect(
        library.resolve(
          'test.dds',
          const <String>['Character/Human/DDS'],
        ),
        'character/human/dds/test.dds',
      );

      final bytes = await library.read('Character/Human/DDS/test.dds');
      expect(bytes.length, 128);
      expect(bytes.take(4), const <int>[0x44, 0x44, 0x53, 0x20]);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('SPK library mount fails closed before payload validation', () async {
    final root = await Directory.systemTemp.createTemp('spk-library-closed-');
    try {
      final source = await _source(root, strongName: true);
      expect(
        () => Library.fromSpkSource(source),
        throwsA(isA<FormatException>()),
      );
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('approximate SPK hints are excluded by default', () async {
    final root = await Directory.systemTemp.createTemp('spk-library-hints-');
    try {
      final source = await _source(root, strongName: false);
      await source.validateSimpleResourceProfile(
        minimumAuthenticatedSamples: 1,
        maxSamples: 1,
      );
      expect(
        () => Library.fromSpkSource(source),
        throwsA(isA<FormatException>()),
      );
    } finally {
      await root.delete(recursive: true);
    }
  });
}
