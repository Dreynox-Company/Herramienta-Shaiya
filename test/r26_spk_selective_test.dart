import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/spk_archive.dart';
import 'package:herramienta_shaiya/data/library.dart';
import 'package:herramienta_shaiya/data/spk_source.dart';

Future<SpkArchiveSource> selectiveFixture(Directory root) async {
  final key = Uint8List.fromList(List.generate(16, (i) => i + 71));
  final file = File('${root.path}/fixture.spk');
  final bytes = BytesBuilder()..add(Uint8List(spkHeaderBytes));
  final records = <SpkRecord>[];
  for (var i = 0; i < 3; i++) {
    final clear = Uint8List(4096 + i * 17)..setRange(0, 4, [68, 68, 83, 32]);
    for (var n = 4; n < clear.length; n++) {
      clear[n] = (n + i * 13) & 31;
    }
    final nonce = Uint8List.fromList(List.generate(12, (j) => i * 16 + j + 32));
    final box = await AesGcm.with128bits().encrypt(
      clear,
      secretKey: SecretKey(key),
      nonce: nonce,
    );
    final metadata = Uint8List(32)
      ..setRange(0, 12, nonce)
      ..setRange(12, 28, box.mac.bytes);
    records.add(
      SpkRecord(
        ordinal: i,
        entryId: 0x1000 + i,
        dataOffset: bytes.length,
        storedBytes: box.cipherText.length,
        decodedBytes: clear.length,
        recordType: 1,
        auxiliaryStart: 0xffffffff,
        chunkCount: 0,
        metadata: metadata,
      ),
    );
    bytes.add(box.cipherText);
  }
  final fragmentOffset = bytes.length;
  bytes.add(Uint8List(32));
  records.add(
    SpkRecord(
      ordinal: 3,
      entryId: 0x2000,
      dataOffset: fragmentOffset,
      storedBytes: 32,
      decodedBytes: 262145,
      recordType: 3,
      auxiliaryStart: 0,
      chunkCount: 1,
      metadata: Uint8List(32),
    ),
  );
  final indexOffset = bytes.length;
  await file.writeAsBytes(bytes.takeBytes());
  final index = SpkIndex(
    header: SpkHeader(
      version: spkVersion3,
      indexOffset: indexOffset,
      indexStoredBytes: 1,
      indexDecodedBytes: records.length * spkRecordBytes,
      recordCount: records.length,
      blockBytes: 262144,
      auxiliaryOffset: indexOffset,
      auxiliaryCount: 1,
      indexNonce: Uint8List(12),
      indexTag: Uint8List(16),
    ),
    records: records,
    auxiliary: [
      SpkAuxRecord(
        ordinal: 0,
        dataOffset: fragmentOffset,
        storedBytes: 32,
        metadata: Uint8List(16),
      ),
    ],
    encryptedIndexSha256: 'synthetic-selective',
    decodedIndexSha256: 'synthetic-selective-clear',
  );
  return SpkArchiveSource.fromValidatedIndexForTesting(
    file: file,
    index: index,
    profile: SpkCryptoProfile(
      profileId: 'synthetic-selective',
      indexSha256: 'synthetic-selective',
      indexSecret: key,
      resourceSecret: key,
      resourceAad: Uint8List(0),
      resourceKeyIsIndexKey: false,
      chunkNonceRule: 'unsupported',
    ),
  );
}

void main() {
  test(
    'partial SPK mount requires authenticated profile and never reads blocked fragments',
    () async {
      final root = await Directory.systemTemp.createTemp('r26-partial-');
      addTearDown(() => root.delete(recursive: true));
      final source = await selectiveFixture(root);
      await expectLater(
        Library.fromSpkEditable(source),
        throwsA(isA<SpkFailure>()),
      );
      await source.validateSimpleResourceProfile();
      source.names.mergeConfirmed({
        0x1000: 'Character/Human/DDS/upper016.dds',
        0x2000: 'Character/Human/3DC/blocked.3dc',
      });
      source.names.mergeHints(
        {0x1001: 'Character/Human/humf_upper.mlt'},
        confidence: 'strong-inferred',
        evidence: 'fixture-not-identity',
      );
      final before = source.reads;
      final lib = await Library.fromSpkEditable(source);
      addTearDown(lib.dispose);
      expect(
        source.reads,
        before,
        reason: 'Mounting is lazy, not a full extraction.',
      );
      expect(source.canReadSimpleResources, isTrue);
      expect(source.canReadFragmentedResources, isFalse);
      expect(source.canExtractAll, isFalse);
      expect(source.fullyValidatedResources, isFalse);
      expect(lib.files, hasLength(3));
      expect(lib.files, contains('character/human/dds/upper016.dds'));
      expect(lib.files, isNot(contains('character/human/humf_upper.mlt')));
      expect(lib.files, isNot(contains('character/human/3dc/blocked.3dc')));
      final technical = lib.files.entries
          .firstWhere((e) => e.value == '0000000000001001')
          .key;
      expect(technical, startsWith('_spk_sinnombre/'));
      expect(source.names.isConfirmed(0x1001), isFalse);
      expect((await lib.read(technical)).sublist(0, 4), [68, 68, 83, 32]);
      expect(lib.sourceLabel, contains('parcial'));
    },
  );

  test(
    'Entry ID overlay accepts only a current authenticated resource hash, never changes SPK',
    () async {
      final root = await Directory.systemTemp.createTemp('r26-overlay-');
      addTearDown(() => root.delete(recursive: true));
      final source = await selectiveFixture(root);
      await source.validateSimpleResourceProfile();
      final lib = await Library.fromSpkEditable(source);
      addTearDown(lib.dispose);
      final path = lib.files.entries
          .firstWhere((e) => e.value == '0000000000001002')
          .key;
      final originalSpk = await source.file.readAsBytes();
      final original = await lib.read(path),
          edited = Uint8List.fromList(original);
      edited[64] ^= 1;
      await expectLater(
        lib.writeSpkOverlay({path: edited}, expectedHashes: {path: 'wrong'}),
        throwsFormatException,
      );
      await lib.writeSpkOverlay(
        {path: edited},
        expectedHashes: {path: sha256.convert(original).toString()},
      );
      expect(await lib.read(path), edited);
      expect(await source.file.readAsBytes(), originalSpk);
      expect(source.canExtractAll, isFalse);
      expect(source.fullResourceValidation, isNull);
      await expectLater(
        lib.writeSpkOverlay(
          {'character/human/blocked.3dc': edited},
          expectedHashes: {
            'character/human/blocked.3dc': sha256.convert(original).toString(),
          },
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'lazy SPK mount does not bypass per-resource AES-GCM authentication',
    () async {
      final root = await Directory.systemTemp.createTemp('r26-auth-');
      addTearDown(() => root.delete(recursive: true));
      final source = await selectiveFixture(root);
      await source.validateSimpleResourceProfile();
      final lib = await Library.fromSpkEditable(source);
      addTearDown(lib.dispose);
      final record = source.index.simpleResources.first;
      final path = lib.files.entries
          .firstWhere((e) => e.value == record.idHex)
          .key;
      await source.readEntry(record);
      expect(source.validatedFormat(record.entryId), isNotNull);
      final readsBeforeCorruption = source.reads;
      final changed = await source.file.readAsBytes();
      changed[record.dataOffset + 50] ^= 1;
      await source.file.writeAsBytes(changed);
      await expectLater(
        lib.read(path),
        throwsA(
          isA<SpkFailure>().having(
            (error) => error.code,
            'code',
            'SPK_RESOURCE_AUTHENTICATION',
          ),
        ),
      );
      expect(source.fullResourceValidation, isNull);
      expect(source.validatedFormat(record.entryId), isNull);
      expect(source.reads, readsBeforeCorruption);
      expect(source.failures.last['entryId'], record.idHex);
      expect(source.canReadFragmentedResources, isFalse);
      await source.readEntry(source.index.simpleResources.last);
      expect(source.reads, readsBeforeCorruption + 1);
    },
  );
}
