import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/formats.dart';
import 'package:herramienta_shaiya/core/game_text_codec.dart';
import 'package:herramienta_shaiya/editor/wtr_document.dart';

Uint8List fixture() {
  final out = Uint8List(16 + 2 * 256);
  final data = ByteData.sublistView(out);
  data.setFloat32(0, 4.0, Endian.little);
  data.setUint32(4, 7, Endian.little);
  data.setInt32(8, -2, Endian.little);
  data.setUint32(12, 2, Endian.little);

  void string(int offset, String value) {
    final bytes = value.codeUnits;
    out.setRange(offset, offset + bytes.length, bytes);
  }

  string(16, 'world/grass.dds');
  string(16 + 256, 'world/rock.tga');
  return out;
}

void main() {
  test('WTR editor exposes validated header and fixed texture rows', () {
    final bytes = fixture();
    final doc = WtrDocument.open(
      bytes,
      'world/test.wtr',
      GameTextEncoding.windows1252,
    );

    expect(doc.profile, 'wtr');
    expect(doc.rows, hasLength(3));
    expect(doc.read(doc.fields(0)[0]), '4.0');
    expect(doc.read(doc.fields(0)[1]), '7');
    expect(doc.read(doc.fields(0)[2]), '-2');
    expect(doc.read(doc.fields(0)[3]), '2');
    expect(doc.read(doc.fields(1).single), 'world/grass.dds');
    expect(doc.read(doc.fields(2).single), 'world/rock.tga');
  });

  test('WTR edits texture and tile size with fixed-size round trip', () {
    final original = fixture();
    final doc = WtrDocument.open(
      original,
      'world/test.wtr',
      GameTextEncoding.windows1252,
    );

    doc.edit(0, doc.fields(0).first, '8.5');
    doc.edit(1, doc.fields(1).single, r'world\grass_new.png');

    final encoded = doc.exportBytes();
    expect(encoded.length, original.length);

    final parsed = WtrData.parse(encoded, 'world/test.wtr');
    expect(parsed.tileSize, closeTo(8.5, 1e-6));
    expect(parsed.textures[0], 'world/grass_new.png');
    expect(parsed.textures[1], 'world/rock.tga');

    // Structural count and untouched second texture remain byte-identical.
    expect(encoded.sublist(12, 16), orderedEquals(original.sublist(12, 16)));
    expect(
      encoded.sublist(16 + 256, 16 + 512),
      orderedEquals(original.sublist(16 + 256, 16 + 512)),
    );
  });

  test(
    'WTR rejects traversal unsupported extensions and invalid tile sizes',
    () {
      final doc = WtrDocument.open(
        fixture(),
        'world/test.wtr',
        GameTextEncoding.windows1252,
      );
      final texture = doc.fields(1).single;
      final tile = doc.fields(0).first;

      expect(
        () => doc.edit(1, texture, '../outside.dds'),
        throwsFormatException,
      );
      expect(
        () => doc.edit(1, texture, 'world/terrain.exe'),
        throwsFormatException,
      );
      expect(() => doc.edit(0, tile, '0'), throwsFormatException);
      expect(() => doc.edit(0, tile, '100001'), throwsFormatException);
    },
  );

  test('WTR fixed text field cannot overflow 256-byte native slot', () {
    final doc = WtrDocument.open(
      fixture(),
      'world/test.wtr',
      GameTextEncoding.windows1252,
    );
    final tooLong = '${'a' * 252}.dds';
    expect(
      () => doc.edit(1, doc.fields(1).single, tooLong),
      throwsFormatException,
    );
  });
}
