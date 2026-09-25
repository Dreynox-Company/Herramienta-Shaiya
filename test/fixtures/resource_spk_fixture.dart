import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:zstandard/zstandard.dart';
import 'package:herramienta_shaiya/core/spk_archive.dart';
import 'package:herramienta_shaiya/data/spk_source.dart';

/// Own fixture only. Native mode packs a real Zstandard + AES-GCM index and
/// opens it through the production parser. Linux mode tests resource operations
/// without requiring a Windows Zstandard plugin. No game keys/assets involved.
Future<SpkArchiveSource> resourceSpkFixture(
  Directory root,
  Map<String, Uint8List> inputs, {
  bool nativeIndex = false,
}) async {
  if (inputs.length < 3) {
    throw ArgumentError('At least three samples required.');
  }
  final key = Uint8List.fromList(List.generate(16, (i) => i + 71));
  final file = File('${root.path}/resources.spk');
  final bytes = BytesBuilder()..add(Uint8List(spkHeaderBytes));
  final records = <SpkRecord>[];
  final names = SpkNameMap.empty();
  var i = 0;
  for (final input in inputs.entries) {
    final nonce = Uint8List.fromList(
      List.generate(12, (j) => (i * 16 + j + 32) & 255),
    );
    final box = await AesGcm.with128bits().encrypt(
      input.value,
      secretKey: SecretKey(key),
      nonce: nonce,
    );
    final metadata = Uint8List(32)
      ..setRange(0, 12, nonce)
      ..setRange(12, 28, box.mac.bytes);
    records.add(
      SpkRecord(
        ordinal: i,
        entryId: 0x1000 + i,
        dataOffset: bytes.length,
        storedBytes: box.cipherText.length,
        decodedBytes: input.value.length,
        recordType: 1,
        auxiliaryStart: 0xffffffff,
        chunkCount: 0,
        metadata: metadata,
      ),
    );
    names.mergeHints(
      {0x1000 + i: input.key},
      confidence: 'inferred',
      evidence: 'fixture-hint-not-identity',
    );
    bytes.add(box.cipherText);
    i++;
  }
  final fragmentOffset = bytes.length;
  bytes.add(Uint8List(32));
  final fragmentMeta = Uint8List(32);
  ByteData.sublistView(fragmentMeta).setUint32(28, 1, Endian.little);
  records.add(
    SpkRecord(
      ordinal: i,
      entryId: 0x2000,
      dataOffset: fragmentOffset,
      storedBytes: 32,
      decodedBytes: 262145,
      recordType: 3,
      auxiliaryStart: 0,
      chunkCount: 1,
      metadata: fragmentMeta,
    ),
  );
  names.mergeHints(
    {0x2000: 'Character/Wing/3dc/locked.3dc'},
    confidence: 'inferred',
    evidence: 'fixture-only',
  );
  final aux = [
    SpkAuxRecord(
      ordinal: 0,
      dataOffset: fragmentOffset,
      storedBytes: 32,
      metadata: Uint8List(16),
    ),
  ];
  final auxOffset = bytes.length;
  final auxBytes = Uint8List(spkAuxRecordBytes);
  ByteData.sublistView(auxBytes)
    ..setUint64(0, fragmentOffset, Endian.little)
    ..setUint32(8, 32, Endian.little)
    ..setUint32(12, 32, Endian.little);
  bytes.add(auxBytes);
  final indexOffset = bytes.length;
  final decodedIndex = Uint8List(records.length * spkRecordBytes);
  final data = ByteData.sublistView(decodedIndex);
  for (final r in records) {
    final o = r.ordinal * spkRecordBytes;
    data
      ..setUint64(o, r.entryId, Endian.little)
      ..setUint64(o + 8, r.dataOffset, Endian.little)
      ..setUint64(o + 16, r.storedBytes, Endian.little)
      ..setUint64(o + 24, r.storedBytes, Endian.little)
      ..setUint64(o + 32, r.decodedBytes, Endian.little)
      ..setUint32(o + 40, r.recordType, Endian.little)
      ..setUint32(o + 44, r.auxiliaryStart, Endian.little);
    decodedIndex.setRange(o + 48, o + 80, r.metadata);
  }
  final indexNonce = Uint8List.fromList(List.generate(12, (j) => 220 + j));
  final packed = nativeIndex
      ? await Zstandard().compress(decodedIndex, 3)
      : decodedIndex;
  if (packed == null) {
    throw StateError('Zstandard could not encode the native fixture.');
  }
  final indexBox = await AesGcm.with128bits().encrypt(
    packed,
    secretKey: SecretKey(key),
    nonce: indexNonce,
  );
  bytes.add(indexBox.cipherText);
  bytes.add(Uint8List(spkFooterBytes));
  final header = SpkHeader(
    version: spkVersion3,
    indexOffset: indexOffset,
    indexStoredBytes: indexBox.cipherText.length,
    indexDecodedBytes: decodedIndex.length,
    recordCount: records.length,
    blockBytes: 262144,
    auxiliaryOffset: auxOffset,
    auxiliaryCount: 1,
    indexNonce: indexNonce,
    indexTag: Uint8List.fromList(indexBox.mac.bytes),
  );
  final all = bytes.takeBytes(), h = ByteData(128);
  h
    ..setUint32(0, spkMagic, Endian.little)
    ..setUint32(4, spkVersion3, Endian.little)
    ..setUint64(8, indexOffset, Endian.little)
    ..setUint64(16, indexBox.cipherText.length, Endian.little)
    ..setUint64(24, decodedIndex.length, Endian.little)
    ..setUint32(32, records.length, Endian.little)
    ..setUint32(36, 262144, Endian.little)
    ..setUint64(100, auxOffset, Endian.little)
    ..setUint32(108, 1, Endian.little);
  all.setRange(0, 128, h.buffer.asUint8List());
  all.setRange(40, 52, indexNonce);
  all.setRange(52, 68, indexBox.mac.bytes);
  await file.writeAsBytes(all, flush: true);
  final profile = SpkCryptoProfile(
    profileId: 'r27-own-fixture',
    indexSha256: sha256.convert(indexBox.cipherText).toString(),
    indexSecret: key,
    resourceSecret: key,
    resourceAad: Uint8List(0),
    resourceKeyIsIndexKey: false,
    chunkNonceRule: 'unsupported',
  );
  if (nativeIndex) {
    return SpkArchiveSource.open(file.path, profile, names: names);
  }
  SpkIndex.validateRelationships(records, aux, header);
  final source = await SpkArchiveSource.fromValidatedIndexForTesting(
    file: file,
    index: SpkIndex(
      header: header,
      records: records,
      auxiliary: aux,
      encryptedIndexSha256: profile.indexSha256,
      decodedIndexSha256: sha256.convert(decodedIndex).toString(),
    ),
    profile: profile,
  );
  source.names.mergeHints(
    {for (final r in records) r.entryId: names[r.entryId]!},
    confidence: 'inferred',
    evidence: 'fixture-only',
  );
  return source;
}
