import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/spk_archive.dart';
import 'package:herramienta_shaiya/data/spk_source.dart';
import 'package:herramienta_shaiya/data/spk_writer.dart';
import 'package:zstandard/zstandard.dart';

class _Fixture {
  final File file;
  final SpkCryptoProfile profile;
  final Uint8List footer;

  const _Fixture(this.file, this.profile, this.footer);
}

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

int _u64(int value) => value.toUnsigned(64);

Uint8List _metadata(
  Uint8List nonce,
  Uint8List tag, {
  int flags = 0,
}) {
  final out = Uint8List(32)
    ..setRange(0, 12, nonce)
    ..setRange(12, 28, tag);
  ByteData.sublistView(out).setUint32(28, flags, Endian.little);
  return out;
}

Uint8List _fragmentMetadata(int chunks) {
  final out = Uint8List(32);
  for (var i = 0; i < 28; i++) {
    out[i] = (0x30 + i) & 0xff;
  }
  ByteData.sublistView(out).setUint32(28, chunks, Endian.little);
  return out;
}

Uint8List _records(List<SpkRecord> records) {
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

Uint8List _auxiliary(List<SpkAuxRecord> rows) {
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

Uint8List _header({
  required int indexOffset,
  required int indexStored,
  required int indexDecoded,
  required int records,
  required int blockBytes,
  required int auxiliaryOffset,
  required int auxiliaryCount,
  required Uint8List nonce,
  required Uint8List tag,
}) {
  final out = Uint8List(spkHeaderBytes);
  out.fillRange(68, 100, 0xa5);
  out.fillRange(112, 128, 0xb6);
  final data = ByteData.sublistView(out);
  data.setUint32(0, spkMagic, Endian.little);
  data.setUint32(4, spkVersion3, Endian.little);
  data.setUint64(8, indexOffset, Endian.little);
  data.setUint64(16, indexStored, Endian.little);
  data.setUint64(24, indexDecoded, Endian.little);
  data.setUint32(32, records, Endian.little);
  data.setUint32(36, blockBytes, Endian.little);
  out.setRange(40, 52, nonce);
  out.setRange(52, 68, tag);
  data.setUint64(100, auxiliaryOffset, Endian.little);
  data.setUint32(108, auxiliaryCount, Endian.little);
  return out;
}

Uint8List _dds(int seed, int bytes) {
  final out = Uint8List(bytes);
  out.setRange(0, 4, const [0x44, 0x44, 0x53, 0x20]);
  for (var i = 4; i < out.length; i++) {
    out[i] = (seed + i * 13) & 0xff;
  }
  return out;
}

Future<_Fixture> _fixture(Directory root) async {
  final indexKey = Uint8List.fromList(
    List<int>.generate(16, (i) => 0x10 + i),
  );
  final resourceKey = Uint8List.fromList(
    List<int>.generate(16, (i) => 0x80 + i),
  );
  const blockBytes = 64;
  const rule = 'entry_id_chunk_le';

  final output = BytesBuilder(copy: false)..add(Uint8List(spkHeaderBytes));
  var dataOffset = spkHeaderBytes;
  final records = <SpkRecord>[];
  final auxiliary = <SpkAuxRecord>[];

  for (var i = 0; i < 3; i++) {
    final decoded = _dds(0x20 + i * 9, 128 + i * 8);
    final packed = await Zstandard().compress(decoded, 3);
    expect(packed, isNotNull);
    final nonce = _nonce(0x10 + i * 16);
    final box = await _encrypt(packed!, resourceKey, nonce);
    final cipher = Uint8List.fromList(box.cipherText);
    final ordinal = records.length;
    records.add(
      SpkRecord(
        ordinal: ordinal,
        entryId: 0x1100 + i,
        dataOffset: dataOffset,
        storedBytes: cipher.length,
        decodedBytes: decoded.length,
        recordType: 1,
        auxiliaryStart: 0xffffffff,
        chunkCount: 0,
        metadata: _metadata(
          nonce,
          Uint8List.fromList(box.mac.bytes),
          flags: i,
        ),
      ),
    );
    output.add(cipher);
    dataOffset += cipher.length;
  }

  for (var r = 0; r < 2; r++) {
    final decoded = _dds(0x60 + r * 17, 180 + r * 12);
    final packed = await Zstandard().compress(decoded, 3);
    expect(packed, isNotNull);
    expect(packed!.length, greaterThan(2));

    final ordinal = records.length;
    final entryId = 0x2200 + r;
    final auxStart = auxiliary.length;
    final resourceOffset = dataOffset;
    final cut = packed.length ~/ 2;
    final parts = <Uint8List>[
      Uint8List.fromList(packed.sublist(0, cut)),
      Uint8List.fromList(packed.sublist(cut)),
    ];
    var storedTotal = 0;
    final parent = SpkRecord(
      ordinal: ordinal,
      entryId: entryId,
      dataOffset: resourceOffset,
      storedBytes: packed.length,
      decodedBytes: decoded.length,
      recordType: 3,
      auxiliaryStart: auxStart,
      chunkCount: parts.length,
      metadata: _fragmentMetadata(parts.length),
    );

    for (var local = 0; local < parts.length; local++) {
      final partOrdinal = auxiliary.length;
      final placeholder = SpkAuxRecord(
        ordinal: partOrdinal,
        dataOffset: dataOffset,
        storedBytes: parts[local].length,
        metadata: Uint8List(16),
      );
      final nonce = SpkArchiveSource.fragmentNonceForRule(
        rule,
        parent,
        placeholder,
        local,
      );
      final box = await _encrypt(parts[local], resourceKey, nonce);
      final cipher = Uint8List.fromList(box.cipherText);
      output.add(cipher);
      auxiliary.add(
        SpkAuxRecord(
          ordinal: partOrdinal,
          dataOffset: dataOffset,
          storedBytes: cipher.length,
          metadata: Uint8List.fromList(box.mac.bytes),
        ),
      );
      storedTotal += cipher.length;
      dataOffset += cipher.length;
    }

    records.add(
      SpkRecord(
        ordinal: ordinal,
        entryId: entryId,
        dataOffset: resourceOffset,
        storedBytes: storedTotal,
        decodedBytes: decoded.length,
        recordType: 3,
        auxiliaryStart: auxStart,
        chunkCount: parts.length,
        metadata: _fragmentMetadata(parts.length),
      ),
    );
  }

  records.add(
    SpkRecord(
      ordinal: records.length,
      entryId: 0x3300,
      dataOffset: 0,
      storedBytes: 256,
      decodedBytes: 256,
      recordType: 32768,
      auxiliaryStart: 0xffffffff,
      chunkCount: 0,
      metadata: Uint8List.fromList(
        List<int>.generate(32, (i) => (0xc0 + i) & 0xff),
      ),
    ),
  );

  final auxiliaryOffset = dataOffset;
  final auxiliaryBytes = _auxiliary(auxiliary);
  output.add(auxiliaryBytes);
  final indexOffset = auxiliaryOffset + auxiliaryBytes.length;
  final decodedIndex = _records(records);
  final packedIndex = await Zstandard().compress(decodedIndex, 3);
  expect(packedIndex, isNotNull);
  final indexNonce = _nonce(0xd0);
  final indexBox = await _encrypt(packedIndex!, indexKey, indexNonce);
  final indexCipher = Uint8List.fromList(indexBox.cipherText);
  output.add(indexCipher);

  final footer = Uint8List.fromList(
    List<int>.generate(spkFooterBytes, (i) => (0x55 + i) & 0xff),
  );
  output.add(footer);

  final header = _header(
    indexOffset: indexOffset,
    indexStored: indexCipher.length,
    indexDecoded: decodedIndex.length,
    records: records.length,
    blockBytes: blockBytes,
    auxiliaryOffset: auxiliaryOffset,
    auxiliaryCount: auxiliary.length,
    nonce: indexNonce,
    tag: Uint8List.fromList(indexBox.mac.bytes),
  );
  final all = output.takeBytes();
  all.setRange(0, spkHeaderBytes, header);

  final file = File('${root.path}/source.spk');
  await file.writeAsBytes(all, flush: true);
  final profile = SpkCryptoProfile(
    profileId: 'writer-fixture',
    indexSha256: sha256.convert(indexCipher).toString(),
    indexSecret: indexKey,
    resourceSecret: resourceKey,
    resourceAad: Uint8List(0),
    resourceKeyIsIndexKey: false,
    chunkNonceRule: rule,
  );

  final source = await SpkArchiveSource.open(file.path, profile);
  await source.validateSimpleResourceProfile();
  await source.validateFragmentedResourceProfile();
  await source.validateAllResources(
    control: SpkExtractControl(),
    progress: (_, _, _) {},
  );
  expect(source.fullyValidatedResources, isTrue);

  return _Fixture(file, profile, footer);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'SPK writer rebuilds, edits and self-validates simple + fragmented payloads',
    () async {
    final root = await Directory.systemTemp.createTemp('spk-writer-');
    try {
      final fixture = await _fixture(root);
      final originalHash = sha256.convert(await fixture.file.readAsBytes()).toString();
      final source = await SpkArchiveSource.open(
        fixture.file.path,
        fixture.profile,
      );
      await source.validateSimpleResourceProfile();
      await source.validateFragmentedResourceProfile();
      await source.validateAllResources(
        control: SpkExtractControl(),
        progress: (_, _, _) {},
      );

      final simpleReplacement = _dds(0x91, 116);
      final fragmentedReplacement = _dds(0xa7, 164);
      final target = File('${root.path}/edited.spk');
      final result = await SpkWriter.rebuild(
        source,
        target,
        replacements: {
          0x1101: simpleReplacement,
          0x2200: fragmentedReplacement,
        },
        control: SpkExtractControl(),
        progress: (_, _, _) {},
      );

      expect(result.replaced, 2);
      expect(result.resources, 5);
      expect(result.validation['status'], 'validated');
      expect(await target.exists(), isTrue);
      expect(await File(result.profileFile).exists(), isTrue);
      expect(await File(result.namesFile).exists(), isTrue);
      expect(await File(result.auditFile).exists(), isTrue);
      expect(
        sha256.convert(await fixture.file.readAsBytes()).toString(),
        originalHash,
      );

      final profileJson = jsonDecode(
        await File(result.profileFile).readAsString(),
      ) as Map<String, dynamic>;
      final profile = SpkCryptoProfile.fromJson(profileJson);
      final rebuilt = await SpkArchiveSource.open(target.path, profile);
      await rebuilt.validateSimpleResourceProfile();
      await rebuilt.validateFragmentedResourceProfile();
      await rebuilt.validateAllResources(
        control: SpkExtractControl(),
        progress: (_, _, _) {},
      );
      expect(rebuilt.fullyValidatedResources, isTrue);

      final simple = rebuilt.index.resources.singleWhere(
        (row) => row.entryId == 0x1101,
      );
      final fragmented = rebuilt.index.resources.singleWhere(
        (row) => row.entryId == 0x2200,
      );
      expect(fragmented.chunkCount, greaterThan(2));
      expect(
        (await rebuilt.readEntry(simple)).bytes,
        orderedEquals(simpleReplacement),
      );
      expect(
        (await rebuilt.readEntry(fragmented)).bytes,
        orderedEquals(fragmentedReplacement),
      );

      final auditJson = jsonDecode(
        await File(result.auditFile).readAsString(),
      ) as Map<String, dynamic>;
      final restored = await SpkArchiveSource.open(target.path, profile);
      await restored.validateSimpleResourceProfile();
      await restored.validateFragmentedResourceProfile();
      expect(restored.restoreFullResourceValidation(auditJson), isTrue);
      expect(restored.fullyValidatedResources, isTrue);

      final special = rebuilt.index.specialRecords.single;
      expect(special.entryId, 0x3300);
      expect(special.recordType, 32768);
      expect(special.storedBytes, 256);

      final bytes = await target.readAsBytes();
      expect(
        bytes.sublist(bytes.length - spkFooterBytes),
        orderedEquals(fixture.footer),
      );
      expect(bytes.sublist(68, 100), everyElement(0xa5));
      expect(bytes.sublist(112, 128), everyElement(0xb6));
    } finally {
      await root.delete(recursive: true);
    }
  },
    skip: !Platform.isWindows
        ? 'Requiere zstandard_windows.dll; se ejecuta en el gate nativo Windows.'
        : false,
  );

  test(
    'SPK writer refuses unknown replacement IDs and never overwrites source',
    () async {
    final root = await Directory.systemTemp.createTemp('spk-writer-guards-');
    try {
      final fixture = await _fixture(root);
      final source = await SpkArchiveSource.open(
        fixture.file.path,
        fixture.profile,
      );
      await source.validateSimpleResourceProfile();
      await source.validateFragmentedResourceProfile();
      await source.validateAllResources(
        control: SpkExtractControl(),
        progress: (_, _, _) {},
      );

      await expectLater(
        SpkWriter.rebuild(
          source,
          File('${root.path}/bad.spk'),
          replacements: {0x9999: _dds(1, 80)},
          control: SpkExtractControl(),
          progress: (_, _, _) {},
        ),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        SpkWriter.rebuild(
          source,
          fixture.file,
          control: SpkExtractControl(),
          progress: (_, _, _) {},
        ),
        throwsA(isA<FileSystemException>()),
      );
    } finally {
      await root.delete(recursive: true);
    }
  },
    skip: !Platform.isWindows
        ? 'Requiere zstandard_windows.dll; se ejecuta en el gate nativo Windows.'
        : false,
  );
}
