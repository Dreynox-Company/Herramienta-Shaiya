import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/game_text_codec.dart';
import 'package:herramienta_shaiya/core/world_resources.dart';
import 'package:herramienta_shaiya/editor/wld_layer_document.dart';

Uint8List fldFixture() {
  const size = 2;
  const terrainCells = 4;
  const layers = 1;
  const total = 4 + 4 + terrainCells * 2 + terrainCells + 4 + 516 + 256 + 56;
  final out = Uint8List(total);
  final data = ByteData.sublistView(out);
  var at = 0;

  void fixed(String value, int length) {
    final bytes = value.codeUnits;
    out.setRange(at, at + bytes.length, bytes);
    at += length;
  }

  fixed('FLD', 4);
  data.setUint32(at, size, Endian.little);
  at += 4;

  for (var i = 0; i < terrainCells; i++) {
    data.setUint16(at, 100 + i, Endian.little);
    at += 2;
  }
  for (var i = 0; i < terrainCells; i++) {
    out[at++] = i;
  }

  data.setUint32(at, layers, Endian.little);
  at += 4;
  fixed('world/terrain/grass.dds', 256);
  data.setFloat32(at, 2.5, Endian.little);
  at += 4;
  fixed('sound/step_grass.wav', 256);
  fixed('world/layout/test_layout.smod', 256);

  // Seven object categories, each with name-count=0 and instance-count=0.
  for (var i = 0; i < 7; i++) {
    data.setUint32(at, 0, Endian.little);
    at += 4;
    data.setUint32(at, 0, Endian.little);
    at += 4;
  }
  expect(at, total);
  return out;
}

void main() {
  test('WLD layer editor exposes only confirmed writable spans', () {
    final doc = WldLayerDocument.open(
      fldFixture(),
      'world/test.wld',
      GameTextEncoding.automatic,
    );

    expect(doc.profile, 'wld_layers');
    expect(doc.rows, hasLength(3));
    expect(doc.read(doc.fields(0)[0]), '2');
    expect(doc.read(doc.fields(0)[1]), '1');
    expect(doc.fields(0)[0].spec.editable, isFalse);
    expect(doc.fields(0)[1].spec.editable, isFalse);

    expect(doc.read(doc.fields(1)[0]), 'world/terrain/grass.dds');
    expect(doc.read(doc.fields(1)[1]), '2.5');
    expect(doc.read(doc.fields(1)[2]), 'sound/step_grass.wav');
    expect(doc.read(doc.fields(2).single), 'world/layout/test_layout.smod');
  });

  test('WLD layer edits round-trip without touching geometry or counts', () {
    final original = fldFixture();
    final doc = WldLayerDocument.open(
      original,
      'world/test.wld',
      GameTextEncoding.windows1252,
    );
    final layer = doc.fields(1);
    doc.edit(1, layer[0], r'world\terrain\stone.dds');
    doc.edit(1, layer[1], '3.75');
    doc.edit(1, layer[2], 'sound/step_stone.wav');
    doc.edit(2, doc.fields(2).single, 'world/layout/stone.smod');

    final encoded = doc.exportBytes();
    expect(encoded.length, original.length);

    final parsed = WorldResource.parse(encoded, 'world/test.wld');
    expect(parsed.terrain.size, 2);
    expect(parsed.terrain.layers, hasLength(1));
    expect(parsed.terrain.layers.single.texture, 'world/terrain/stone.dds');
    expect(parsed.terrain.layers.single.tile, closeTo(3.75, 1e-6));
    expect(parsed.terrain.layers.single.sound, 'sound/step_stone.wav');
    expect(parsed.terrain.layout, 'world/layout/stone.smod');

    // Height/type raster is outside editable spans and remains byte-identical.
    expect(encoded.sublist(8, 20), orderedEquals(original.sublist(8, 20)));
  });

  test('WLD layer editor rejects unsafe DATA paths', () {
    final doc = WldLayerDocument.open(
      fldFixture(),
      'world/test.wld',
      GameTextEncoding.korean,
    );
    expect(
      () => doc.edit(1, doc.fields(1)[0], '../escape.dds'),
      throwsFormatException,
    );
    expect(
      () => doc.edit(2, doc.fields(2).single, r'C:\absolute.smod'),
      throwsFormatException,
    );
  });

  test('DUN variant stays fail-closed in terrain-layer writer', () {
    final bytes = fldFixture();
    bytes[0] = 'D'.codeUnitAt(0);
    bytes[1] = 'U'.codeUnitAt(0);
    bytes[2] = 'N'.codeUnitAt(0);
    expect(
      () => WldLayerDocument.open(
        bytes,
        'world/test.wld',
        GameTextEncoding.korean,
      ),
      throwsFormatException,
    );
  });
}
