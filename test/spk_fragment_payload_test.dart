import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/spk_archive.dart';
import 'package:herramienta_shaiya/data/spk_source.dart';

Uint8List _recordOrdinalNonce(int recordOrdinal, int localChunk) {
  final bytes = Uint8List(12);
  final data = ByteData.sublistView(bytes);
  data.setUint64(0, recordOrdinal, Endian.little);
  data.setUint32(8, localChunk, Endian.little);
  return bytes;
}

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
) => AesGcm.with128bits().encrypt(
  clear,
  secretKey: SecretKey(key),
  nonce: nonce,
);

void main() {
  test(
    'SPK payloads derive fragmented nonce rule and authenticate reconstruction',
    () async {
      final key = Uint8List.fromList(
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

      const firstOffset = 128;
      final firstBox = await _encrypt(
        firstClear,
        key,
        _offsetChunkNonce(firstOffset, 0),
      );
      final secondOffset = firstOffset + firstBox.cipherText.length;
      final secondBox = await _encrypt(
        secondClear,
        key,
        _offsetChunkNonce(secondOffset, 0),
      );

      final firstRecord = SpkRecord(
        ordinal: 0,
        entryId: 0x112233445566778,
        dataOffset: firstOffset,
        storedBytes: firstBox.cipherText.length,
        decodedBytes: firstClear.length,
        recordType: 3,
        auxiliaryStart: 0,
        chunkCount: 1,
        metadata: Uint8List(32),
      );
      final secondRecord = SpkRecord(
        ordinal: 1,
        entryId: 0x223344556677889,
        dataOffset: secondOffset,
        storedBytes: secondBox.cipherText.length,
        decodedBytes: secondClear.length,
        recordType: 3,
        auxiliaryStart: 1,
        chunkCount: 1,
        metadata: Uint8List(32),
      );
      final firstPart = SpkAuxRecord(
        ordinal: 0,
        dataOffset: firstOffset,
        storedBytes: firstBox.cipherText.length,
        metadata: Uint8List.fromList(firstBox.mac.bytes),
      );
      final secondPart = SpkAuxRecord(
        ordinal: 1,
        dataOffset: secondOffset,
        storedBytes: secondBox.cipherText.length,
        metadata: Uint8List.fromList(secondBox.mac.bytes),
      );
      final samples = <SpkFragmentAuthSample>[
        SpkFragmentAuthSample(
          record: firstRecord,
          part: firstPart,
          localOrdinal: 0,
          cipherText: Uint8List.fromList(firstBox.cipherText),
        ),
        SpkFragmentAuthSample(
          record: secondRecord,
          part: secondPart,
          localOrdinal: 0,
          cipherText: Uint8List.fromList(secondBox.cipherText),
        ),
      ];

      final rule = await SpkArchiveSource.deriveChunkNonceRuleFromSamples(
        samples: samples,
        key: key,
        minimumAuthenticatedSamples: 2,
      );
      expect(rule, 'offset_le96');

      final reconstructed = BytesBuilder(copy: false);
      for (final sample in samples) {
        reconstructed.add(
          await SpkArchiveSource.decryptGcm(
            sample.cipherText,
            key,
            SpkArchiveSource.fragmentNonceForRule(
              rule,
              sample.record,
              sample.part,
              sample.localOrdinal,
            ),
            sample.part.metadata,
          ),
        );
      }
      expect(
        reconstructed.takeBytes(),
        Uint8List.fromList(<int>[...firstClear, ...secondClear]),
      );
    },
  );

  test('SPK nonce derivation can prove record-ordinal chunk nonces', () async {
    final key = Uint8List.fromList(
      List<int>.generate(16, (i) => 0x30 + i),
    );
    final samples = <SpkFragmentAuthSample>[];
    var offset = 4096;
    for (final tuple in <(int, int)>[(7, 31), (12, 44)]) {
      final clear = Uint8List.fromList(
        List<int>.generate(
          41 + tuple.$1,
          (i) => (i * 7 + tuple.$1) & 0xff,
        ),
      );
      final box = await _encrypt(
        clear,
        key,
        _recordOrdinalNonce(tuple.$1, 0),
      );
      final record = SpkRecord(
        ordinal: tuple.$1,
        entryId: 0x100000000000000 + tuple.$1,
        dataOffset: offset,
        storedBytes: box.cipherText.length,
        decodedBytes: clear.length,
        recordType: 3,
        auxiliaryStart: tuple.$2,
        chunkCount: 1,
        metadata: Uint8List(32),
      );
      final part = SpkAuxRecord(
        ordinal: tuple.$2,
        dataOffset: offset,
        storedBytes: box.cipherText.length,
        metadata: Uint8List.fromList(box.mac.bytes),
      );
      samples.add(
        SpkFragmentAuthSample(
          record: record,
          part: part,
          localOrdinal: 0,
          cipherText: Uint8List.fromList(box.cipherText),
        ),
      );
      offset += box.cipherText.length;
    }

    final rule = await SpkArchiveSource.deriveChunkNonceRuleFromSamples(
      samples: samples,
      key: key,
      minimumAuthenticatedSamples: 2,
    );
    expect(rule, 'record_ordinal_chunk_le96');
  });
}