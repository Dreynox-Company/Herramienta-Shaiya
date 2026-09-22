import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/spk_archive.dart';
import 'package:herramienta_shaiya/data/library.dart';
import 'package:herramienta_shaiya/data/spk_source.dart';

void _put32(Uint8List bytes, int offset, int value) =>
    ByteData.sublistView(
      bytes,
      offset,
      offset + 4,
    ).setUint32(0, value, Endian.little);

Uint8List _nonce(int seed) =>
    Uint8List.fromList(List<int>.generate(12, (i) => (seed + i) & 0xff));

Future<SecretBox> _encrypt(
  Uint8List clear,
  Uint8List key,
  Uint8List nonce,
) =>
    AesGcm.with128bits().encrypt(
      clear,
      secretKey: SecretKey(key),
      nonce: nonce,
    );

class _Fixture {
  final File file;
  final SpkIndex index;
  final SpkCryptoProfile profile;

  const _Fixture(this.file, this.index, this.profile);
}

Future<_Fixture> _buildSimpleFixture(
  Directory root, {
  bool resourceUsesIndexKey = false,
}) async {
  final indexKey = Uint8List.fromList(
    List<int>.generate(16, (i) => 0x10 + i),
  );
  final resourceKey = resourceUsesIndexKey
      ? Uint8List.fromList(indexKey)
      : Uint8List.fromList(
          List<int>.generate(16, (i) => 0x80 + i),
        );

  final bytes = BytesBuilder(copy: false)..add(Uint8List(spkHeaderBytes));
  final records = <SpkRecord>[];
  var dataOffset = spkHeaderBytes;

  for (var i = 0; i < 3; i++) {
    final clear = Uint8List(4096 + i * 17);
    clear.setRange(0, 4, const <int>[0x44, 0x44, 0x53, 0x20]);
    for (var j = 4; j < clear.length; j++) {
      clear[j] = (j + i * 13) & 0x1f;
    }

    final nonce = _nonce(0x20 + i * 16);
    final box = await _encrypt(clear, resourceKey, nonce);
    final cipher = Uint8List.fromList(box.cipherText);
    final metadata = Uint8List(32)
      ..setRange(0, 12, nonce)
      ..setRange(12, 28, box.mac.bytes);
    _put32(metadata, 28, 0);

    records.add(
      SpkRecord(
        ordinal: i,
        entryId: 0x1000 + i,
        dataOffset: dataOffset,
        storedBytes: cipher.length,
        decodedBytes: clear.length,
        recordType: 1,
        auxiliaryStart: 0xffffffff,
        chunkCount: 0,
        metadata: metadata,
      ),
    );
    bytes.add(cipher);
    dataOffset += cipher.length;
  }

  final file = File('${root.path}/payload-fixture.bin');
  await file.writeAsBytes(bytes.takeBytes(), flush: true);

  final header = SpkHeader(
    version: spkVersion3,
    indexOffset: dataOffset,
    indexStoredBytes: 1,
    indexDecodedBytes: records.length * spkRecordBytes,
    recordCount: records.length,
    blockBytes: 262144,
    auxiliaryOffset: dataOffset,
    auxiliaryCount: 0,
    indexNonce: Uint8List(12),
    indexTag: Uint8List(16),
  );
  final index = SpkIndex(
    header: header,
    records: records,
    auxiliary: const <SpkAuxRecord>[],
    encryptedIndexSha256: 'synthetic-index',
    decodedIndexSha256: 'synthetic-decoded-index',
  );
  final profile = SpkCryptoProfile(
    profileId: 'synthetic-validation',
    indexSha256: 'synthetic-index',
    indexSecret: indexKey,
    resourceSecret: resourceKey,
    resourceAad: Uint8List(0),
    resourceKeyIsIndexKey: false,
    chunkNonceRule: 'unsupported',
  );
  return _Fixture(file, index, profile);
}

Future<SpkArchiveSource> _sourceFor(_Fixture fixture, SpkCryptoProfile profile) =>
    SpkArchiveSource.fromValidatedIndexForTesting(
      file: fixture.file,
      index: fixture.index,
      profile: profile,
    );

void main() {
  test('SPK can prove offline that the index key is also the resource key', () async {
    final root = await Directory.systemTemp.createTemp('spk-shared-key-');
    try {
      final fixture = await _buildSimpleFixture(
        root,
        resourceUsesIndexKey: true,
      );
      final indexOnly = SpkCryptoProfile(
        profileId: 'synthetic-index-only',
        indexSha256: fixture.profile.indexSha256,
        indexSecret: fixture.profile.indexSecret,
        resourceSecret: null,
        resourceAad: Uint8List(0),
        resourceKeyIsIndexKey: false,
        chunkNonceRule: 'unsupported',
      );
      final source = await _sourceFor(fixture, indexOnly);
      expect(source.canReadSimpleResources, isFalse);

      final derived = await source.tryIndexKeyAsResourceProfile();
      expect(derived, isNotNull);
      expect(derived!.profile.resourceKeyIsIndexKey, isTrue);
      expect(derived.canReadSimpleResources, isTrue);
      final first = await derived.readEntry(derived.index.simpleResources.first);
      expect(first.format, 'DDS');
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('SPK rejects the index-key hypothesis when resources use another key', () async {
    final root = await Directory.systemTemp.createTemp('spk-separate-key-');
    try {
      final fixture = await _buildSimpleFixture(root);
      final indexOnly = SpkCryptoProfile(
        profileId: 'synthetic-index-only',
        indexSha256: fixture.profile.indexSha256,
        indexSecret: fixture.profile.indexSecret,
        resourceSecret: null,
        resourceAad: Uint8List(0),
        resourceKeyIsIndexKey: false,
        chunkNonceRule: 'unsupported',
      );
      final source = await _sourceFor(fixture, indexOnly);
      expect(await source.tryIndexKeyAsResourceProfile(), isNull);
      expect(source.canReadSimpleResources, isFalse);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test(
    'SPK simple payload access stays closed until real GCM samples validate',
    () async {
      final root = await Directory.systemTemp.createTemp('spk-validation-');
      try {
        final fixture = await _buildSimpleFixture(root);
        final source = await _sourceFor(fixture, fixture.profile);

        expect(source.canReadSimpleResources, isFalse);
        await expectLater(
          source.readEntry(source.index.simpleResources.first),
          throwsA(
            isA<SpkFailure>().having(
              (e) => e.code,
              'code',
              'SPK_RESOURCE_PROFILE_UNVALIDATED',
            ),
          ),
        );

        final validation = await source.validateSimpleResourceProfile();
        expect(validation['status'], 'validated');
        expect(validation['authenticatedSamples'], 3);
        expect(validation['decodedSamples'], 3);
        expect(source.canReadSimpleResources, isTrue);

        final record = source.index.simpleResources.first;
        final result = await source.readEntry(record);
        expect(result.format, 'DDS');
        expect(result.bytes.length, 4096);
        expect(source.validatedFormat(record.entryId), 'DDS');
        expect(source.technicalPath(record), endsWith('.dds'));
        expect(
          source.diagnostics()['resourceProfileValidation'],
          isA<Map<String, Object?>>(),
        );
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test('full SPK audit validates every readable resource', () async {
    final root = await Directory.systemTemp.createTemp('spk-full-audit-');
    try {
      final fixture = await _buildSimpleFixture(root);
      final source = await _sourceFor(fixture, fixture.profile);
      await source.validateSimpleResourceProfile();

      final progress = <int>[];
      final result = await source.validateAllResources(
        control: SpkExtractControl(),
        progress: (_, done, total) {
          expect(total, 3);
          progress.add(done);
        },
      );

      expect(result['status'], 'validated');
      expect(result['validatedResources'], 3);
      expect(result['simpleResources'], 3);
      expect(result['fragmentedResources'], 0);
      expect(
        Map<String, dynamic>.from(result['formats'] as Map)['DDS'],
        3,
      );
      expect(source.fullyValidatedResources, isTrue);
      expect(
        source.diagnostics()['fullyValidatedResources'],
        isTrue,
      );
      expect(progress.last, 3);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('full audit validates inferred extensions and exposes real technical formats', () async {
    final root = await Directory.systemTemp.createTemp('spk-name-format-audit-');
    try {
      final fixture = await _buildSimpleFixture(root);
      final source = await _sourceFor(fixture, fixture.profile);
      source.names.mergeHints(
        {
          0x1000: 'Character/Human/body.dds',
          0x1001: 'Character/Human/wrong.xml',
          0x1002: 'Custom/unknown.asset',
        },
        confidence: 'strong-inferred',
        evidence: 'fixture-name-correlation',
      );
      await source.validateSimpleResourceProfile();
      await source.validateAllResources(
        control: SpkExtractControl(),
        progress: (_, _, _) {},
      );

      final validation = source.validateInferredNamesByFormat();
      expect(validation['validated'], 1);
      expect(validation['rejected'], 1);
      expect(validation['preservedUnknown'], 1);
      expect(source.names.confidence(0x1000), 'validated-inferred');
      expect(source.names[0x1001], isNull);
      expect(source.names[0x1002], 'Custom/unknown.asset');

      final wrong = source.index.resources.firstWhere(
        (record) => record.entryId == 0x1001,
      );
      expect(source.displayType(wrong), 'DDS');
      expect(source.technicalPath(wrong), endsWith('.dds'));
      expect(source.technicalPath(wrong), contains('_SPK_SinNombre/Simples/'));
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('full audit accepts zero decodedBytes as unspecified length', () async {
    final root = await Directory.systemTemp.createTemp('spk-zero-declared-');
    try {
      final fixture = await _buildSimpleFixture(root);
      final original = fixture.index.records.first;
      final records = <SpkRecord>[
        SpkRecord(
          ordinal: original.ordinal,
          entryId: original.entryId,
          dataOffset: original.dataOffset,
          storedBytes: original.storedBytes,
          decodedBytes: 0,
          recordType: original.recordType,
          auxiliaryStart: original.auxiliaryStart,
          chunkCount: original.chunkCount,
          metadata: original.metadata,
        ),
        ...fixture.index.records.skip(1),
      ];
      final index = SpkIndex(
        header: fixture.index.header,
        records: records,
        auxiliary: fixture.index.auxiliary,
        encryptedIndexSha256: fixture.index.encryptedIndexSha256,
        decodedIndexSha256: fixture.index.decodedIndexSha256,
      );
      final source = await SpkArchiveSource.fromValidatedIndexForTesting(
        file: fixture.file,
        index: index,
        profile: fixture.profile,
      );
      await source.validateSimpleResourceProfile();
      final result = await source.validateAllResources(
        control: SpkExtractControl(),
        progress: (_, _, _) {},
      );
      expect(result['validatedResources'], 3);
      expect(source.fullyValidatedResources, isTrue);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('audited SPK can mount a table-only workspace without Character paths', () async {
    final root = await Directory.systemTemp.createTemp('spk-table-only-');
    try {
      final fixture = await _buildSimpleFixture(root);
      final source = await _sourceFor(fixture, fixture.profile);
      await source.validateSimpleResourceProfile();
      await source.validateAllResources(
        control: SpkExtractControl(),
        progress: (_, _, _) {},
      );

      expect(
        () => Library.fromSpk(
          source,
          overlayRoot: '${root.path}/strict-overlay',
        ),
        throwsA(isA<FormatException>()),
      );

      final library = await Library.fromSpk(
        source,
        requireCharacter: false,
        overlayRoot: '${root.path}/table-overlay',
      );
      expect(library.files.length, 3);
      expect(
        library.files.keys.every((path) => path.startsWith('_spk_sinnombre/')),
        isTrue,
      );
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('fully audited SPK exposes unresolved resources by technical Entry ID', () async {
    final root = await Directory.systemTemp.createTemp('spk-technical-mount-');
    try {
      final fixture = await _buildSimpleFixture(root);
      final source = await _sourceFor(fixture, fixture.profile);
      source.names.mergeConfirmed({
        0x1000: 'Character/Human/humf_upper.mlt',
      });
      await source.validateSimpleResourceProfile();
      await source.validateAllResources(
        control: SpkExtractControl(),
        progress: (_, _, _) {},
      );

      final library = await Library.fromSpk(
        source,
        overlayRoot: '${root.path}/overlay',
      );
      expect(library.files.length, 3);
      expect(
        library.files,
        contains('_spk_sinnombre/0000000000001001.dds'),
      );
      expect(
        library.files,
        contains('_spk_sinnombre/0000000000001002.dds'),
      );
      expect(library.sourceDiagnostics['technicalMounted'], 2);

      const technical = '_spk_sinnombre/0000000000001001.dds';
      final original = await library.read(technical);
      final replacement = Uint8List.fromList([
        ...original.take(24),
        0xde,
        0xad,
        0xbe,
        0xef,
      ]);
      await library.writeSpkOverlay(
        {technical: replacement},
        expectedHashes: {
          technical: sha256.convert(original).toString(),
        },
      );
      expect(await library.read(technical), orderedEquals(replacement));
      final manifest = jsonDecode(
        await File(
          '${root.path}/overlay/_SPK_OVERLAY.json',
        ).readAsString(),
      ) as Map<String, dynamic>;
      final entries = Map<String, dynamic>.from(manifest['entries'] as Map);
      expect(
        (entries[technical] as Map)['nameAuthority'],
        'technical-entry-id',
      );
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('audited inferred resources keep a stable editable Entry-ID alias', () async {
    final root = await Directory.systemTemp.createTemp('spk-inferred-alias-');
    try {
      final fixture = await _buildSimpleFixture(root);
      final source = await _sourceFor(fixture, fixture.profile);
      source.names.mergeConfirmed({
        0x1000: 'Character/Human/humf_upper.mlt',
      });
      source.names.mergeHints(
        {
          0x1001: 'Character/Human/DDS/humf_upper001.dds',
        },
        confidence: 'strong-inferred',
        evidence: 'fixture-inferred',
      );
      await source.validateSimpleResourceProfile();
      await source.validateAllResources(
        control: SpkExtractControl(),
        progress: (_, _, _) {},
      );

      final library = await Library.fromSpk(
        source,
        overlayRoot: '${root.path}/overlay',
      );
      expect(
        library.files,
        contains('character/human/dds/humf_upper001.dds'),
      );
      const technical = '_spk_sinnombre/0000000000001001.dds';
      expect(library.files, contains(technical));
      expect(
        library.files['character/human/dds/humf_upper001.dds'],
        library.files[technical],
      );

      final original = await library.read(technical);
      final replacement = Uint8List.fromList([
        ...original.take(32),
        1,
        2,
        3,
        4,
      ]);
      await library.writeSpkOverlay(
        {technical: replacement},
        expectedHashes: {
          technical: sha256.convert(original).toString(),
        },
      );
      expect(await library.read(technical), orderedEquals(replacement));
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('validated SPK mounts as Library and overlay never mutates source', () async {
    final root = await Directory.systemTemp.createTemp('spk-workspace-');
    try {
      final fixture = await _buildSimpleFixture(root);
      final source = await _sourceFor(fixture, fixture.profile);
      source.names.mergeConfirmed({
        0x1000: 'Character/Human/humf_upper.mlt',
        0x1001: 'Item/Item.SData',
        0x1002: 'BinarySData/DBMonsterData.SData',
      });
      await source.validateSimpleResourceProfile();
      expect(source.canExtractAll, isTrue);

      final beforeSource = sha256.convert(await fixture.file.readAsBytes());
      final library = await Library.fromSpk(
        source,
        overlayRoot: '${root.path}/overlay',
      );
      expect(library.isSpkWorkspace, isTrue);
      expect(library.files, contains('item/item.sdata'));
      expect(
        library.sourceDiagnostics['sourceMode'],
        'spk-v3-workspace',
      );

      final original = await library.read('item/item.sdata');
      final originalHash = sha256.convert(original).toString();
      final replacement = Uint8List.fromList(<int>[
        0x44,
        0x44,
        0x53,
        0x20,
        0x7a,
        0x7b,
        0x7c,
        0x7d,
      ]);
      await library.writeSpkOverlay(
        {'item/item.sdata': replacement},
        expectedHashes: {'item/item.sdata': originalHash},
      );

      expect(
        await library.read('item/item.sdata'),
        orderedEquals(replacement),
      );
      expect(
        sha256.convert(await fixture.file.readAsBytes()).toString(),
        beforeSource.toString(),
      );
      expect(
        await File('${root.path}/overlay/_SPK_OVERLAY.json').exists(),
        isTrue,
      );
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('SPK workspace export applies verified overlay to decoded DATA', () async {
    final root = await Directory.systemTemp.createTemp('spk-workspace-export-');
    try {
      final fixture = await _buildSimpleFixture(root);
      final source = await _sourceFor(fixture, fixture.profile);
      source.names.mergeConfirmed({
        0x1000: 'Character/Human/humf_upper.mlt',
        0x1001: 'Item/Item.SData',
        0x1002: 'BinarySData/DBMonsterData.SData',
      });
      await source.validateSimpleResourceProfile();
      await source.validateAllResources(
        control: SpkExtractControl(),
        progress: (_, _, _) {},
      );

      final before = sha256.convert(await fixture.file.readAsBytes()).toString();
      final library = await Library.fromSpk(
        source,
        overlayRoot: '${root.path}/overlay',
      );
      final original = await library.read('item/item.sdata');
      final replacement = Uint8List.fromList([
        ...original.take(16),
        0xaa,
        0xbb,
        0xcc,
        0xdd,
      ]);
      await library.writeSpkOverlay(
        {'item/item.sdata': replacement},
        expectedHashes: {
          'item/item.sdata': sha256.convert(original).toString(),
        },
      );

      final output = Directory('${root.path}/exports')..createSync();
      final result = await library.exportSpkWorkspace(
        output,
        progress: (_, _, _) {},
      );
      expect(result['files'], 3);
      expect(result['overlayFiles'], 1);

      final folder = Directory(result['folder']! as String);
      expect(
        await File(
          '${folder.path}${Platform.pathSeparator}Item'
          '${Platform.pathSeparator}Item.SData',
        ).readAsBytes(),
        orderedEquals(replacement),
      );
      final manifest = jsonDecode(
        await File(
          '${folder.path}${Platform.pathSeparator}_SPK_MANIFEST.json',
        ).readAsString(),
      ) as Map<String, dynamic>;
      expect(manifest['workspaceOverlayApplied'], 1);
      expect(
        manifest['workspaceIndexSha256'],
        source.index.encryptedIndexSha256,
      );
      expect(
        sha256.convert(await fixture.file.readAsBytes()).toString(),
        before,
      );
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('SPK simple payload validation rejects a wrong resource key', () async {
    final root = await Directory.systemTemp.createTemp('spk-bad-key-');
    try {
      final fixture = await _buildSimpleFixture(root);
      final bad = SpkCryptoProfile(
        profileId: 'synthetic-wrong-key',
        indexSha256: fixture.profile.indexSha256,
        indexSecret: fixture.profile.indexSecret,
        resourceSecret: Uint8List.fromList(
          List<int>.generate(16, (i) => 0x40 + i),
        ),
        resourceAad: Uint8List(0),
        resourceKeyIsIndexKey: false,
        chunkNonceRule: 'unsupported',
      );
      final source = await _sourceFor(fixture, bad);

      await expectLater(
        source.validateSimpleResourceProfile(),
        throwsA(
          isA<SpkFailure>().having(
            (e) => e.code,
            'code',
            'SPK_RESOURCE_AUTH_FAILED',
          ),
        ),
      );
      expect(source.canReadSimpleResources, isFalse);
    } finally {
      await root.delete(recursive: true);
    }
  });
}
