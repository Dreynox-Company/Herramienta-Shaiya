import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';
import 'package:zstandard/zstandard.dart';
import 'package:herramienta_shaiya/data/spk_source.dart';

void main() {
  test('SPK synthetic authenticated index and resource round-trip', () async {
    final temp = await Directory.systemTemp.createTemp('spk-source-test-');
    try {
      final original = Uint8List.fromList('hola SPK reciente'.codeUnits);
      final spk = await _buildSyntheticSpk(original);
      final path = '${temp.path}/data.spk';
      await File(path).writeAsBytes(spk, flush: true);

      final source = await SpkSource.open(path);
      expect(source.records, hasLength(1));
      expect(source.simpleCount, 1);
      expect(source.chunkedCount, 0);
      expect(source.validation['indexAuthenticated'], true);

      final decoded = await source.read(source.records.single.entryId);
      expect(decoded, original);
      expect(detectSpkExtension(decoded), '.txt');

      final out = Directory('${temp.path}/out');
      final report = await source.extractAll(out);
      expect((report['result'] as Map)['extracted'], 1);
      expect(File('${out.path}/SPK_MANIFEST.json').existsSync(), true);
      final extracted = out
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => !f.path.endsWith('SPK_MANIFEST.json'))
          .single;
      expect(await extracted.readAsBytes(), original);
    } finally {
      await temp.delete(recursive: true);
    }
  });

  test('SPK refuses an authenticated index with a damaged tag', () async {
    final temp = await Directory.systemTemp.createTemp('spk-auth-test-');
    try {
      final bytes = await _buildSyntheticSpk(
        Uint8List.fromList('integridad'.codeUnits),
      );
      // Header index tag starts at byte 52.
      bytes[52] ^= 0x01;
      final path = '${temp.path}/broken.spk';
      await File(path).writeAsBytes(bytes, flush: true);
      await expectLater(
        SpkSource.open(path),
        throwsA(
          isA<SpkFailure>().having(
            (e) => e.code,
            'code',
            'SPK_PROFILE_UNKNOWN',
          ),
        ),
      );
    } finally {
      await temp.delete(recursive: true);
    }
  });
}

Future<Uint8List> _buildSyntheticSpk(Uint8List decodedResource) async {
  final profile = spkCryptoProfiles.single;
  final z = Zstandard();

  final packedResource = await z.compress(decodedResource, 3);
  if (packedResource == null) throw StateError('zstd resource');

  final resourceNonce = Uint8List.fromList(
    List<int>.generate(12, (i) => 0x20 + i),
  );
  final encryptedResource = _encrypt(
    profile.resourceKey,
    resourceNonce,
    packedResource,
  );
  final resourceCipher = encryptedResource.$1;
  final resourceTag = encryptedResource.$2;

  final record = Uint8List(96);
  final rd = ByteData.sublistView(record);
  rd.setUint64(0, 0x0123456789abcdef, Endian.little);
  rd.setUint64(8, 128, Endian.little);
  rd.setUint64(16, resourceCipher.length, Endian.little);
  rd.setUint64(24, resourceCipher.length, Endian.little);
  rd.setUint64(32, decodedResource.length, Endian.little);
  rd.setUint32(40, 1, Endian.little);
  rd.setUint32(44, 0xffffffff, Endian.little);
  record.setRange(48, 60, resourceNonce);
  record.setRange(60, 76, resourceTag);
  rd.setUint32(76, 0, Endian.little);

  final packedIndex = await z.compress(record, 3);
  if (packedIndex == null) throw StateError('zstd index');
  final indexNonce = Uint8List.fromList(
    List<int>.generate(12, (i) => 0x40 + i),
  );
  final encryptedIndex = _encrypt(profile.indexKey, indexNonce, packedIndex);
  final indexCipher = encryptedIndex.$1;
  final indexTag = encryptedIndex.$2;

  final indexOffset = 128 + resourceCipher.length;
  final out = Uint8List(indexOffset + indexCipher.length);
  final hd = ByteData.sublistView(out);
  hd.setUint32(0, 0x9e7bd34c, Endian.little);
  hd.setUint32(4, 0x00030000, Endian.little);
  hd.setUint64(8, indexOffset, Endian.little);
  hd.setUint64(16, indexCipher.length, Endian.little);
  hd.setUint64(24, record.length, Endian.little);
  hd.setUint32(32, 1, Endian.little);
  hd.setUint32(36, 262144, Endian.little);
  out.setRange(40, 52, indexNonce);
  out.setRange(52, 68, indexTag);
  hd.setUint32(100, indexOffset, Endian.little);
  hd.setUint32(108, 0, Endian.little);
  out.setRange(128, 128 + resourceCipher.length, resourceCipher);
  out.setRange(indexOffset, out.length, indexCipher);
  return out;
}

(Uint8List, Uint8List) _encrypt(
  Uint8List key,
  Uint8List nonce,
  Uint8List plain,
) {
  final cipher = GCMBlockCipher(AESEngine());
  cipher.init(
    true,
    AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)),
  );
  final result = cipher.process(plain);
  if (result.length < 16) throw StateError('GCM output');
  return (
    Uint8List.fromList(result.sublist(0, result.length - 16)),
    Uint8List.fromList(result.sublist(result.length - 16)),
  );
}
