import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/seed_data.dart';
import 'package:herramienta_shaiya/core/spk_archive.dart';
import 'package:herramienta_shaiya/data/spk_source.dart';
import 'package:herramienta_shaiya/data/spk_table_discovery.dart';
import 'package:herramienta_shaiya/editor/primitive_schemas.dart';
import 'package:herramienta_shaiya/editor/schema_reader.dart';

import 'archive_test.dart' show SahWriter;
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

Future<SpkArchiveSource> _source(
  Directory root, {
  List<String> tables = const <String>[
    'DBItemDataRecord',
    'DBMonsterDataRecord',
    'DBSkillDataRecord',
  ],
  Map<String, Uint8List> manifestFiles = const <String, Uint8List>{},
}) async {
  final indexKey = Uint8List.fromList(
    List<int>.generate(16, (i) => 0x10 + i),
  );
  final resourceKey = Uint8List.fromList(
    List<int>.generate(16, (i) => 0x80 + i),
  );
  final bytes = BytesBuilder(copy: false)..add(Uint8List(spkHeaderBytes));
  final records = <SpkRecord>[];
  var dataOffset = spkHeaderBytes;

  final payloads = <({Uint8List bytes, String? hint})>[];
  for (var i = 0; i < tables.length; i++) {
    final schema = primitiveSchemas[tables[i]]!;
    final raw = binaryTable(
      schema.map((field) => field.$1).toList(),
      [List<int>.filled(schema.length, i + 1)],
    );
    payloads.add((bytes: SeedData.encode(raw), hint: null));
  }
  for (final entry in manifestFiles.entries) {
    payloads.add((bytes: entry.value, hint: entry.key));
  }

  for (var i = 0; i < payloads.length; i++) {
    final clear = payloads[i].bytes;
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
  for (var i = 0; i < payloads.length; i++) {
    final hint = payloads[i].hint;
    if (hint != null) {
      source.names.mergeHints(
        {0x2000 + i: hint},
        confidence: 'inferred',
        evidence: 'synthetic-hint',
      );
    }
  }
  await source.validateSimpleResourceProfile();
  await source.validateAllResources(
    control: SpkExtractControl(),
    progress: (_, _, _) {},
  );
  return source;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('SPK format detection validates native MLT and ITM structures', () {
    final mlt = SahWriter();
    mlt.out.add(ascii.encode('MLT'));
    mlt.u(1);
    mlt.str('body.3dc');
    mlt.u(1);
    mlt.str('body.dds');
    mlt.u(1);
    mlt.u(0);
    mlt.u(0);
    mlt.u(0);
    final mltBytes = mlt.out.takeBytes();
    expect(SpkArchiveSource.detectFormat(mltBytes), 'MLT');
    expect(SpkArchiveSource.extensionFor('MLT'), '.mlt');

    final itm = SahWriter();
    itm.out.add(ascii.encode('ITM'));
    itm.u(1);
    itm.str('blade.3do');
    itm.u(1);
    itm.str('blade.dds');
    itm.u(1);
    itm.u(0);
    itm.u(0);
    itm.i(0);
    itm.i(0);
    itm.i(0);
    itm.i(0);
    final itmBytes = itm.out.takeBytes();
    expect(SpkArchiveSource.detectFormat(itmBytes), 'ITM');
    expect(SpkArchiveSource.extensionFor('ITM'), '.itm');

    final table = SeedData.encode(
      binaryTable(
        const ['Id', 'Value'],
        const [
          [1, 2],
        ],
      ),
    );
    expect(SpkArchiveSource.detectFormat(table), 'SDATA');
    expect(SpkArchiveSource.extensionFor('SDATA'), '.sdata');
  });

  test('unresolved audited SData can open through its binary header', () {
    final bytes = SeedData.encode(
      binaryTable(
        const ['Id', 'Value'],
        const [
          [7, 42],
        ],
      ),
    );
    final document = EditorReader.open(
      bytes,
      '_SPK_SinNombre/0123456789abcdef.sdata',
    );
    expect(document.profile, 'binary');
    expect(document.complete, isTrue);
    expect(document.rows.length, 1);
    expect(document.read(document.fields(0)[0]), '7');
    expect(document.read(document.fields(0)[1]), '42');
  });

  test('authenticated SPK payloads identify core DB tables structurally', () async {
    final root = await Directory.systemTemp.createTemp('spk-table-discovery-');
    try {
      final source = await _source(root);
      expect(source.canExtractAll, isTrue);
      expect(source.names.paths, isEmpty);

      final result = await SpkCoreTableDiscovery.discover(
        source,
        control: SpkExtractControl(),
        progress: (_, _, _) {},
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

  test('duplicate structural matches stay ambiguous and unconfirmed', () async {
    final root = await Directory.systemTemp.createTemp('spk-table-ambiguous-');
    try {
      final source = await _source(
        root,
        tables: const <String>[
          'DBItemDataRecord',
          'DBItemDataRecord',
          'DBMonsterDataRecord',
        ],
      );
      final result = await SpkCoreTableDiscovery.discover(
        source,
        control: SpkExtractControl(),
        progress: (_, _, _) {},
      );

      expect(
        (result['ambiguousBinaryTables'] as List<Object?>),
        contains('BinarySData/DBItemData.SData'),
      );
      expect(
        source.names.paths.values,
        isNot(contains('BinarySData/DBItemData.SData')),
      );
      expect(
        source.names.paths.values,
        contains('BinarySData/DBMonsterData.SData'),
      );
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('manifest hints are structurally validated without becoming confirmed', () async {
    final root = await Directory.systemTemp.createTemp('spk-manifest-hints-');
    try {
      final writer = SahWriter();
      writer.out.add(ascii.encode('MLT'));
      writer.u(1);
      writer.str('elmm_hand001.3DC');
      writer.u(1);
      writer.str('elmm_hand001.dds');
      writer.u(1);
      writer.u(0);
      writer.u(0);
      writer.u(0);

      final source = await _source(
        root,
        manifestFiles: {
          'Character/Elf/elmm_hand.MLT': writer.out.takeBytes(),
          'Item/99.itm': Uint8List.fromList([1, 2, 3, 4]),
          'BinarySData/LegacyUnknown.SData': Uint8List.fromList([
            1,
            2,
            3,
            4,
          ]),
        },
      );
      final mltId = 0x2000 + 3;
      final badItmId = 0x2000 + 4;
      final legacySDataId = 0x2000 + 5;

      final result = await SpkCoreTableDiscovery.discover(
        source,
        control: SpkExtractControl(),
        progress: (_, _, _) {},
      );

      expect(result['validatedManifestHints'], 1);
      expect(result['rejectedManifestHints'], 1);
      expect(result['unverifiedManifestHints'], 1);
      expect(source.names.isConfirmed(mltId), isFalse);
      expect(source.names.confidence(mltId), 'validated-inferred');
      expect(source.names.evidence(mltId), contains('payload-structure'));
      expect(source.names[mltId], 'Character/Elf/elmm_hand.MLT');
      expect(source.names[badItmId], isNull);
      expect(
        source.names[legacySDataId],
        'BinarySData/LegacyUnknown.SData',
      );
      expect(source.names.confidence(legacySDataId), 'inferred');
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
          progress: (_, _, _) {},
        ),
        throwsA(
          isA<SpkFailure>().having(
            (error) => error.code,
            'code',
            'SPK_TABLE_DISCOVERY_AUDIT',
          ),
        ),
      );
    } finally {
      await root.delete(recursive: true);
    }
  });
}
