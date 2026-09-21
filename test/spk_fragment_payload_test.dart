import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/spk_archive.dart';
import 'package:herramienta_shaiya/data/spk_source.dart';
import 'package:zstandard/zstandard.dart';

void _put32(Uint8List bytes, int offset, int value) =>
    ByteData.sublistView(bytes, offset, offset + 4)
        .setUint32(0, value, Endian.little);

void _put64(Uint8List bytes, int offset, int value) =>
    ByteData.sublistView(bytes, offset, offset + 8)
        .setUint64(0, value, Endian.little);

Uint8List _offsetChunkNonce(int dataOffset, int localChunk) {
  final bytes = Uint8List(12);
  final data = ByteData.sublistView(bytes);
  data.setUint64(0, dataOffset, Endian.little);
  data.setUint32(8, localChunk, Endian.little);
  return bytes;
}

Future<SecretBox> _encrypt(
  Uint8List clear,
  Uint8List key,
  Uint8List nonce,
) async => AesGcm.with128bits().encrypt(
  clear,
  secretKey: SecretKey(key),
  nonce: nonce,
);

Uint8List _record({
  required int entryId,
  required int dataOffset,
  required int storedBytes,
  required int decodedBytes,
  required int auxiliaryStart,
}) {
  final row = Uint8List(spkRecordBytes);
  _put64(row, 0, entryId);
  _put64(row, 8, dataOffset);
  _put64(row, 16, storedBytes);
  _put64(row, 24, storedBytes);
  _put64(row, 32, decodedBytes);
  _put32(row, 40, 3);
  _put32(row, 44, auxiliaryStart);
  _put32(row, 48 + 28, 1);
  return row;
}

Uint8List _auxiliary({
  required int dataOffset,
  required int storedBytes,
  required List<int> tag,
}) {
  final row = Uint8List(spkAuxRecordBytes);
  _put64(row, 0, dataOffset);
  _put32(row, 8, storedBytes);
  _put32(row, 12, storedBytes);
  row.setRange(16, 32, tag);
  return row;
}

void main() {
  test(
    'SPK payloads derive fragmented nonce rule offline and reconstruct bytes',
    () async {
      final temp = await Directory.systemTemp.createTemp('spk-fragment-test-');
      addTearDown(() async {
        if (await temp.exists()) await temp.delete(recursive: true);
      });

      final indexKey = Uint8List.fromList(
        List<int>.generate(16, (i) => i + 1),
      );
      final resourceKey = Uint8List.fromList(
        List<int>.generate(16, (i) => 0xa0 + i),
      );
      final firstClear = Uint8List.fromList(<int>[
        0x91,
        0x02,
        0x13,
        0x44,
        0x55,
        0x26,
        0x37,
        0x68,
        0x79,
        0x8a,
        0x9b,
        0xac,
        0xbd,
        0xce,
        0xdf,
        0x10,
      ]);
      final secondClear = Uint8List.fromList(<int>[
        0x42,
        0x71,
        0x19,
        0x2a,
        0x3b,
        0x4c,
        0x5d,
        0x6e,
        0x7f,
        0x80,
        0x91,
        0xa2,
        0xb3,
        0xc4,
        0xd5,
        0xe6,
        0xf7,
      ]);

      const firstOffset = spkHeaderBytes;
      final firstBox = await _encrypt(
        firstClear,
        resourceKey,
        _offsetChunkNonce(firstOffset, 0),
      );
      final secondOffset = firstOffset + firstBox.cipherText.length;
      final secondBox = await _encrypt(
        secondClear,
        resourceKey,
        _offsetChunkNonce(secondOffset, 0),
      );
      final auxiliaryOffset = secondOffset + secondBox.cipherText.length;
      const auxiliaryCount = 2;
      final indexOffset = auxiliaryOffset + auxiliaryCount * spkAuxRecordBytes;

      final decodedIndex = Uint8List(spkRecordBytes * 2);
      decodedIndex.setRange(
        0,
        spkRecordBytes,
        _record(
          entryId: 0x112233445566778,
          dataOffset: firstOffset,
          storedBytes: firstBox.cipherText.length,
          decodedBytes: firstClear.length,
          auxiliaryStart: 0,
        ),
      );
      decodedIndex.setRange(
        spkRecordBytes,
        spkRecordBytes * 2,
        _record(
          entryId: 0x223344556677889,
          dataOffset: secondOffset,
          storedBytes: secondBox.cipherText.length,
          decodedBytes: secondClear.length,
          auxiliaryStart: 1,
        ),
      );

      final packedIndex = await Zstandard().compress(decodedIndex, 3);
      expect(packedIndex, isNotNull);
      final indexNonce = Uint8List.fromList(
        List<int>.generate(12, (i) => 0x30 + i),
      );
      final indexBox = await _encrypt(
        Uint8List.fromList(packedIndex!),
        indexKey,
        indexNonce,
      );

      final header = Uint8List(spkHeaderBytes);
      _put32(header, 0, spkMagic);
      _put32(header, 4, spkVersion3);
      _put64(header, 8, indexOffset);
      _put64(header, 16, indexBox.cipherText.length);
      _put64(header, 24, decodedIndex.length);
      _put32(header, 32, 2);
      _put32(header, 36, 262144);
      header.setRange(40, 52, indexNonce);
      header.setRange(52, 68, indexBox.mac.bytes);
      _put64(header, 100, auxiliaryOffset);
      _put32(header, 108, auxiliaryCount);

      final builder = BytesBuilder(copy: false)
        ..add(header)
        ..add(firstBox.cipherText)
        ..add(secondBox.cipherText)
        ..add(
          _auxiliary(
            dataOffset: firstOffset,
            storedBytes: firstBox.cipherText.length,
            tag: firstBox.mac.bytes,
          ),
        )
        ..add(
          _auxiliary(
            dataOffset: secondOffset,
            storedBytes: secondBox.cipherText.length,
            tag: secondBox.mac.bytes,
          ),
        )
        ..add(indexBox.cipherText)
        ..add(Uint8List(spkFooterBytes));
      final spk = File('${temp.path}${Platform.pathSeparator}data.spk');
      await spk.writeAsBytes(builder.takeBytes(), flush: true);

      final baseProfile = SpkCryptoProfile(
        profileId: 'synthetic-fragment-profile',
        indexSha256: '',
        indexSecret: indexKey,
        resourceSecret: resourceKey,
        resourceAad: Uint8List(0),
        resourceKeyIsIndexKey: false,
        chunkNonceRule: 'unsupported',
      );
      final source = await SpkArchiveSource.open(spk.path, baseProfile);
      expect(source.canReadSimpleResources, isTrue);
      expect(source.canReadFragmentedResources, isFalse);

      final rule = await source.deriveChunkNonceRuleOffline(
        maxSamples: 4,
        minimumAuthenticatedSamples: 2,
      );
      expect(rule, 'offset_le96');

      final completed = await SpkArchiveSource.open(
        spk.path,
        baseProfile.withChunkNonceRule(rule),
      );
      expect(completed.canReadFragmentedResources, isTrue);
      expect(completed.canExtractAll, isTrue);

      final resources = completed.index.fragmentedResources.toList();
      expect(resources, hasLength(2));
      expect((await completed.readEntry(resources[0])).bytes, firstClear);
      expect((await completed.readEntry(resources[1])).bytes, secondClear);
    },
  );
}