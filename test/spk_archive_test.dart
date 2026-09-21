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
      expect(() => SpkHeader.parse(bad, 1024), throwsA(isA<SpkFailure>()));

      final b = Uint8List(spkHeaderBytes);
      put32(b, 0, spkMagic);
      put32(b, 4, spkVersion3);
      put64(b, 8, 1000);
      put64(b, 16, 200);
      put64(b, 24, 95);
      put32(b, 32, 1);
      put32(b, 36, 262144);
      put64(b, 100, 900);
      expect(() => SpkHeader.parse(b, 1264), throwsA(isA<SpkFailure>()));
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
      expect(() => SpkIndex.parseRecords(b, h), throwsA(isA<SpkFailure>()));
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
        () => SpkIndex.validateRelationships([simple, fragmented], aux, h),
        returnsNormally,
      );
    });
  });

  group('SPK local profiles', () {
    test('unsigned 64-bit IDs round-trip through signed Dart int', () {
      expect(spkParseU64Hex('ffffffffffffffff'), -1);
      expect(spkParseU64Hex('8000000000000000'), -9223372036854775808);
      expect(spkU64Hex(-1), 'ffffffffffffffff');
      expect(spkU64Hex(-9223372036854775808), '8000000000000000');
    });

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

    test('name map keeps inferred names separate from confirmed paths', () {
      final map = SpkNameMap.fromJson({
        'schema': 2,
        'paths': {'0000000000000001': 'Character/Human/body.dds'},
        'hints': {
          '0000000000000002': {
            'path': 'Monster/3DC/monster.3DC',
            'confidence': 'inferred',
          },
          '-7ffe15b9c5fb90a0': 'Item/negative-id.dds',
        },
      });
      expect(map.confirmedPath(1), 'Character/Human/body.dds');
      expect(map.inferredPath(2), 'Monster/3DC/monster.3DC');
      expect(map.isConfirmed(1), isTrue);
      expect(map.isInferred(2), isTrue);
      expect(map.paths.length, 1);
      expect(map.hints.length, 2);
    });

    test('confirmed names replace inference for the same resource', () {
      final map = SpkNameMap({}, {7: 'Guess/a.bin'});
      map.mergeConfirmed({7: 'Character/Human/a.dds'});
      expect(map[7], 'Character/Human/a.dds');
      expect(map.isConfirmed(7), isTrue);
      expect(map.isInferred(7), isFalse);
    });

    test('index and resource secrets remain separate', () {
      final p = SpkCryptoProfile.fromJson({
        'profileId': 'fixture',
        'indexSha256': 'abc',
        'index': {'secretHex': '00000000000000000000000000000000'},
        'resources': {
          'secretHex': '11111111111111111111111111111111',
          'chunkNonceRule': 'unsupported',
        },
      });
      expect(p.indexSecret.length, 16);
      expect(p.effectiveResourceSecret, isNotNull);
      expect(p.chunkNonceRule, 'unsupported');
    });

    test('V7 resource summary accepts AES-256 and canonicalizes nonce rule', () {
      final base = SpkCryptoProfile.fromJson({
        'profileId': 'fixture-index',
        'indexSha256': 'abc',
        'index': {'secretHex': '00000000000000000000000000000000'},
      });
      final merged = base.mergeResourceProbe({
        'schema': 2,
        'readyForSimple': true,
        'readyForFragmented': true,
        'resourceSecretHex':
            '1111111111111111111111111111111111111111111111111111111111111111',
        'chunkNonceRule': 'offset_chunk0_le96',
      });
      expect(merged.effectiveResourceSecret, isNotNull);
      expect(merged.effectiveResourceSecret!.length, 32);
      expect(merged.chunkNonceRule, 'offset_le96');
      expect(merged.indexSecret.length, 16);
    });

    test('V7 resource summary rejects unvalidated simple resources', () {
      final base = SpkCryptoProfile.fromJson({
        'index': {'secretHex': '00000000000000000000000000000000'},
      });
      expect(
        () => base.mergeResourceProbe({
          'readyForSimple': false,
          'resourceSecretHex': '11111111111111111111111111111111',
        }),
        throwsFormatException,
      );
    });

    test('resource secret accepts 128 or 256 bits only', () {
      expect(spkResourceSecret('00000000000000000000000000000000').length, 16);
      expect(spkResourceSecret('1111111111111111111111111111111111111111111111111111111111111111').length, 32);
      expect(() => spkResourceSecret('222222222222222222222222222222222222222222222222'), throwsFormatException);
    });

    test('invalid secret size fails closed', () {
      expect(
        () => SpkCryptoProfile.fromJson({
          'index': {'secretHex': '00'},
        }),
        throwsFormatException,
      );
    });

    test('confirmed names override inferred hints and preserve evidence', () {
      final map = SpkNameMap.fromJson({
        'schema': 5,
        'paths': {'0000000000000001': 'Character/confirmed.dds'},
        'hints': {
          '0000000000000001': {
            'path': 'Character/wrong.dds',
            'confidence': 'strong-inferred',
            'evidence': 'size+zstd',
          },
          '0000000000000002': {
            'path': 'Item/3DO/01201.3do',
            'confidence': 'strong-inferred',
            'evidence': 'decoded-size+zstd3-size',
          },
        },
      });
      expect(map[1], 'Character/confirmed.dds');
      expect(map.isConfirmed(1), isTrue);
      expect(map.isInferred(1), isFalse);
      expect(map[2], 'Item/3DO/01201.3do');
      expect(map.isInferred(2), isTrue);
      expect(map.confidence(2), 'strong-inferred');
      expect(map.evidence(2), 'decoded-size+zstd3-size');
    });

    test('name map merge keeps confirmed paths authoritative', () {
      final map = SpkNameMap.empty();
      map.mergeHints(
        {7: 'Monster/ANI/mob.ANI'},
        confidence: 'strong-inferred',
        evidence: 'decoded-size+zstd3-size',
      );
      expect(map.isInferred(7), isTrue);
      map.mergeConfirmed({7: 'Monster/ANI/Mob_Guard04_Idle.ANI'});
      expect(map.isConfirmed(7), isTrue);
      expect(map.isInferred(7), isFalse);
      expect(map[7], 'Monster/ANI/Mob_Guard04_Idle.ANI');
    });
  });
}
