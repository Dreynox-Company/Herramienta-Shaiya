import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/seed_data.dart';
import 'package:herramienta_shaiya/core/spk_archive.dart';
import 'package:herramienta_shaiya/data/spk_source.dart';
import 'package:herramienta_shaiya/data/spk_table_discovery.dart';
import 'package:herramienta_shaiya/editor/primitive_schemas.dart';

import 'editor_document_test.dart' show binaryTable;

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

Future<SpkArchiveSource> _source(Directory root) async {
  final indexKey = Uint8List.fromList(
    List<int>.generate(16, (i) => 0x10 + i),
  );
  final resourceKey = Uint8List.fromList(
    List<int>.generate(16, (i) => 0x80 + i),
  );
  final tables = <String>[
    'DBItemDataRecord',
    'DBMonsterDataRecord',
    'DBSkillDataRecord',
  ];

  final bytes = BytesBuilder(copy: false)..add(Uint8List(spkHeaderBytes));
  final records = <SpkRecord>[];
  var dataOffset = spkHeaderBytes;

  for (var i = 0; i < tables.length; i++) {
    final schema = primitiveSchemas[tables[i]]!;
    final raw = binaryTable(
      schema.map((field) => field.$1).toList(),
      [List<int>.filled(schema.length, i + 1)],
    );
    final clear = SeedData.encode(raw);
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
        entryId: 0x2000 + i,
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

  final file = File('${root.path}/table-discovery-fixture.bin');
  await file.writeAsBytes(bytes.takeBytes(), flush: true);

  final index = SpkIndex(
    header: SpkHeader(
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
    ),
    records: records,
    auxiliary: const <SpkAuxRecord>[],
    encryptedIndexSha256: 'synthetic-index',
    decodedIndexSha256: 'synthetic-decoded-index',
  );

  final source = await SpkArchiveSource.fromValidatedIndexForTesting(
    file: file,
    index: index,
    profile: SpkCryptoProfile(
      profileId: 'synthetic-table-discovery',
      indexSha256: 'synthetic-index',
      indexSecret: indexKey,
      resourceSecret: resourceKey,
      resourceAad: Uint8List(0),
      resourceKeyIsIndexKey: false,
      chunkNonceRule: 'unsupported',
    ),
  );
  await source.validateSimpleResourceProfile();
  return source;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('authenticated SPK payloads identify core DB tables structurally', () async {
    final root = await Directory.systemTemp.createTemp('spk-table-discovery-');
    try {
      final source = await _source(root);
      expect(source.canExtractAll, isTrue);
      expect(source.names.paths, isEmpty);

      final result = await SpkCoreTableDiscovery.discover(
        source,
        control: SpkExtractControl(),
        progress: (_, __, ___) {},
      );

      expect(result['authenticatedResources'], 3);
      expect(result['seedEncodedResources'], 3);
      expect(
        source.names.paths.values,
        containsAll(<String>[
          'BinarySData/DBItemData.SData',
          'BinarySData/DBMonsterData.SData',
          'BinarySData/DBSkillData.SData',
        ]),
      );
      expect(source.names.paths.length, 3);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('table discovery refuses an unvalidated resource profile', () async {
    final root = await Directory.systemTemp.createTemp('spk-table-closed-');
    try {
      final source = await _source(root);
      final closed = await SpkArchiveSource.fromValidatedIndexForTesting(
        file: source.file,
        index: source.index,
        profile: source.profile,
      );
      await expectLater(
        SpkCoreTableDiscovery.discover(
          closed,
          control: SpkExtractControl(),
          progress: (_, __, ___) {},
        ),
        throwsA(
          isA<SpkFailure>().having(
            (error) => error.code,
            'code',
            'SPK_TABLE_DISCOVERY_PROFILE',
          ),
        ),
      );
    } finally {
      await root.delete(recursive: true);
    }
  });
}
