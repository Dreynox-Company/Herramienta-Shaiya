import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/spk_archive.dart';
import 'package:herramienta_shaiya/data/catalog.dart';
import 'package:herramienta_shaiya/data/library.dart';
import 'package:herramienta_shaiya/data/spk_source.dart';

Future<SpkArchiveSource> _emptySpkSource(Directory root) async {
  final file = File('${root.path}/fixture.spk');
  await file.writeAsBytes(const <int>[], flush: true);
  final header = SpkHeader(
    version: spkVersion3,
    indexOffset: 0,
    indexStoredBytes: 0,
    indexDecodedBytes: 0,
    recordCount: 0,
    blockBytes: 262144,
    auxiliaryOffset: 0,
    auxiliaryCount: 0,
    indexNonce: Uint8List(12),
    indexTag: Uint8List(16),
  );
  final index = SpkIndex(
    header: header,
    records: const <SpkRecord>[],
    auxiliary: const <SpkAuxRecord>[],
    encryptedIndexSha256: 'fixture',
    decodedIndexSha256: 'fixture',
  );
  final key = Uint8List(16);
  final profile = SpkCryptoProfile(
    profileId: 'fixture',
    indexSha256: 'fixture',
    indexSecret: key,
    resourceSecret: key,
    resourceAad: Uint8List(0),
    resourceKeyIsIndexKey: false,
    chunkNonceRule: 'unsupported',
  );
  return SpkArchiveSource.fromValidatedIndexForTesting(
    file: file,
    index: index,
    profile: profile,
  );
}

void main() {
  test('SPK Catalog reconstructs a character from exact strong 3DC/DDS pairs',
      () async {
    final root = await Directory.systemTemp.createTemp('spk-catalog-');
    try {
      final source = await _emptySpkSource(root);
      final files = <String, String>{
        'character/human/3dc/humm_torso001.3dc': '0',
        'character/human/dds/humm_torso001.dds': '1',
        'character/human/3dc/humm_lower001.3dc': '2',
        'character/human/dds/humm_lower001.dds': '3',
        'character/human/3dc/humm_hand001.3dc': '4',
        'character/human/dds/humm_hand001.dds': '5',
        'character/human/3dc/humm_foot001.3dc': '6',
        'character/human/dds/humm_foot001.dds': '7',
        'character/human/ani/humm_001_stand.ani': '8',
      };
      final library = Library(
        'fixture',
        false,
        files,
        spkArchive: source,
      );
      final catalog = Catalog(library);
      await catalog.load((_) {});

      final humm = catalog.archetypes.singleWhere((a) => a.id == 'humm');
      expect(humm.parts[Slot.upper], isNotEmpty);
      expect(humm.parts[Slot.lower], isNotEmpty);
      expect(humm.parts[Slot.hand], isNotEmpty);
      expect(humm.parts[Slot.foot], isNotEmpty);
      expect(humm.animations, contains('character/human/ani/humm_001_stand.ani'));
      expect(humm.parts[Slot.upper]!.first.raw.id, 0);
      expect(
        humm.parts[Slot.upper]!.first.association,
        contains('3DC/DDS'),
      );
      expect(
        catalog.warnings.any((w) => w.contains('arquetipos reconstruidos')),
        isTrue,
      );
    } finally {
      await root.delete(recursive: true);
    }
  });
}
