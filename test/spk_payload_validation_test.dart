import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
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
  final String path;
  final SpkCryptoProfile profile;
  final Uint8List resourceKey;

  const _Fixture(this.path, this.profile, this.resourceKey);
}

Future<_Fixture> _buildSimpleFixture(Directory root) async {
  final indexKey = Uint8List.fromList(
    List<int>.generate(16, (i) => 0x10 + i),
  );
  final resourceKey = Uint8List.fromList(
    List<int>.generate(16, (i) => 0x80 + i),
  );

  final payload = BytesBuilder(copy: false);
  final records = Uint8List(3 * spkRecordBytes);
  var dataOffset = spkHeaderBytes;

  for (var i = 0; i < 3; i++) {
    final clear = Uint8List(4096 + i * 17);
    clear.setRange(0, 4, const <int>[0x44, 0x44, 0x53, 0x20]);
    for (var j = 4; j < clear.length; j++) {
      clear[j] = (j + i * 13) & 0x1f;
    }

    final packed = await Zstandard().compress(clear, 3);
    if (packed == null) {
      throw StateError('No se pudo construir el fixture Zstandard.');
    }
    final nonce = _nonce(0x20 + i * 16);
    final box = await _encrypt(packed, resourceKey, nonce);
    final cipher = Uint8List.fromList(box.cipherText);

    final o = i * spkRecordBytes;
    _put64(records, o, 0x1000 + i);
    _put64(records, o + 8, dataOffset);
    _put64(records, o + 16, cipher.length);
    _put64(records, o + 24, cipher.length);
    _put64(records, o + 32, clear.length);
    _put32(records, o + 40, 1);
    _put32(records, o + 44, 0xffffffff);
    records.setRange(o + 48, o + 60, nonce);
    records.setRange(o + 60, o + 76, box.mac.bytes);
    _put32(records, o + 76, 0);

    payload.add(cipher);
    dataOffset += cipher.length;
  }

  final packedIndex = await Zstandard().compress(records, 3);
  if (packedIndex == null) {
    throw StateError('No se pudo comprimir el índice del fixture.');
  }
  final indexNonce = _nonce(0xd0);
  final indexBox = await _encrypt(packedIndex, indexKey, indexNonce);
  final encryptedIndex = Uint8List.fromList(indexBox.cipherText);

  final header = Uint8List(spkHeaderBytes);
  _put32(header, 0, spkMagic);
  _put32(header, 4, spkVersion3);
  _put64(header, 8, dataOffset);
  _put64(header, 16, encryptedIndex.length);
  _put64(header, 24, records.length);
  _put32(header, 32, 3);
  _put32(header, 36, 262144);
  header.setRange(40, 52, indexNonce);
  header.setRange(52, 68, indexBox.mac.bytes);
  _put64(header, 100, dataOffset);
  _put32(header, 108, 0);

  final bytes = BytesBuilder(copy: false)
    ..add(header)
    ..add(payload.takeBytes())
    ..add(encryptedIndex)
    ..add(Uint8List(spkFooterBytes));

  final file = File('${root.path}/fixture.spk');
  await file.writeAsBytes(bytes.takeBytes(), flush: true);

  final profile = SpkCryptoProfile(
    profileId: 'synthetic-validation',
    indexSha256: sha256.convert(encryptedIndex).toString(),
    indexSecret: indexKey,
    resourceSecret: resourceKey,
    resourceAad: Uint8List(0),
    resourceKeyIsIndexKey: false,
    chunkNonceRule: 'unsupported',
  );
  return _Fixture(file.path, profile, resourceKey);
}

void main() {
  test('SPK simple payload access stays closed until real GCM samples validate',
      () async {
    final root = await Directory.systemTemp.createTemp('spk-validation-');
    try {
      final fixture = await _buildSimpleFixture(root);
      final source = await SpkArchiveSource.open(
        fixture.path,
        fixture.profile,
      );

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

      final result = await source.readEntry(source.index.simpleResources.first);
      expect(result.format, 'DDS');
      expect(result.bytes.length, 4096);
      expect(
        source.diagnostics()['resourceProfileValidation'],
        isA<Map<String, Object?>>(),
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
      final source = await SpkArchiveSource.open(fixture.path, bad);

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
