import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/spk_archive.dart';

void put32(Uint8List b, int o, int v) =>
    ByteData.sublistView(b, o, o + 4).setUint32(0, v, Endian.little);
void put64(Uint8List b, int o, int v) =>
    ByteData.sublistView(b, o, o + 8).setUint64(0, v, Endian.little);

void main() {
  group('SPK v3 format', () {
    test('header validates coherent geometry', () {
      final b = Uint8List(spkHeaderBytes);
      put32(b, 0, spkMagic);
      put32(b, 4, spkVersion3);
      put64(b, 8, 1000);
      put64(b, 16, 200);
      put64(b, 24, 96);
      put32(b, 32, 1);
      put32(b, 36, 262144);
      put64(b, 100, 900);
      put32(b, 108, 1);
      final h = SpkHeader.parse(b, 1264);
      expect(h.recordCount, 1);
      expect(h.indexNonce.length, 12);
      expect(h.indexTag.length, 16);
      expect(h.auxiliaryCount, 1);
    });

    test('unknown magic and impossible geometry are rejected', () {
      final bad = Uint8List(spkHeaderBytes);
      expect(
        () => SpkHeader.parse(bad, 1024),
        throwsA(isA<SpkFailure>()),
      );

      final b = Uint8List(spkHeaderBytes);
      put32(b, 0, spkMagic);
      put32(b, 4, spkVersion3);
      put64(b, 8, 1000);
      put64(b, 16, 200);
      put64(b, 24, 95);
      put32(b, 32, 1);
      put32(b, 36, 262144);
      put64(b, 100, 900);
      expect(
        () => SpkHeader.parse(b, 1264),
        throwsA(isA<SpkFailure>()),
      );
    });

    test('record mirror mismatch is never accepted', () {
      final h = SpkHeader(
        version: spkVersion3,
        indexOffset: 1000,
        indexStoredBytes: 100,
        indexDecodedBytes: 96,
        recordCount: 1,
        blockBytes: 262144,
        auxiliaryOffset: 900,
        auxiliaryCount: 0,
        indexNonce: Uint8List(12),
        indexTag: Uint8List(16),
      );
      final b = Uint8List(96);
      put64(b, 0, 7);
      put64(b, 8, 128);
      put64(b, 16, 10);
      put64(b, 24, 11);
      expect(
        () => SpkIndex.parseRecords(b, h),
        throwsA(isA<SpkFailure>()),
      );
    });

    test('resource relationships cover the data area exactly', () {
      final h = SpkHeader(
        version: spkVersion3,
        indexOffset: 500,
        indexStoredBytes: 100,
        indexDecodedBytes: 192,
        recordCount: 2,
        blockBytes: 262144,
        auxiliaryOffset: 158,
        auxiliaryCount: 1,
        indexNonce: Uint8List(12),
        indexTag: Uint8List(16),
      );
      final simple = SpkRecord(
        ordinal: 0,
        entryId: 1,
        dataOffset: 128,
        storedBytes: 10,
        decodedBytes: 10,
        recordType: 1,
        auxiliaryStart: 0xffffffff,
        chunkCount: 0,
        metadata: Uint8List(32),
      );
      final fragmentedMetadata = Uint8List(32);
      put32(fragmentedMetadata, 28, 1);
      final fragmented = SpkRecord(
        ordinal: 1,
        entryId: 2,
        dataOffset: 138,
        storedBytes: 20,
        decodedBytes: 25,
        recordType: 3,
        auxiliaryStart: 0,
        chunkCount: 1,
        metadata: fragmentedMetadata,
      );
      final aux = [
        SpkAuxRecord(
          ordinal: 0,
          dataOffset: 138,
          storedBytes: 20,
          metadata: Uint8List(16),
        ),
      ];
      expect(
        () => SpkIndex.validateRelationships(
          [simple, fragmented],
          aux,
          h,
        ),
        returnsNormally,
      );
    });
  });

  group('SPK local profiles', () {
    test('name map preserves valid folders and rejects traversal', () {
      final map = SpkNameMap.fromJson({
        'paths': {
          '0000000000000001': 'Character/Human/body.dds',
          '0000000000000002': '../outside.bin',
          '0000000000000003': 'Item/niño.dds',
        },
      });
      expect(map[1], 'Character/Human/body.dds');
      expect(map[2], isNull);
      expect(map[3], 'Item/niño.dds');
    });

    test('index and resource secrets remain separate', () {
      final p = SpkCryptoProfile.fromJson({
        'profileId': 'fixture',
        'indexSha256': 'abc',
        'index': {
          'secretHex': '00000000000000000000000000000000',
        },
        'resources': {
          'secretHex': '11111111111111111111111111111111',
          'chunkNonceRule': 'unsupported',
        },
      });
      expect(p.indexSecret.length, 16);
      expect(p.effectiveResourceSecret, isNotNull);
      expect(p.chunkNonceRule, 'unsupported');
    });

    test('invalid secret size fails closed', () {
      expect(
        () => SpkCryptoProfile.fromJson({
          'index': {'secretHex': '00'},
        }),
        throwsFormatException,
      );
    });
  });
}
