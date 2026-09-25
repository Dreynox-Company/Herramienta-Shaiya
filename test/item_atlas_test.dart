import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/item_atlas.dart';
import 'package:herramienta_shaiya/core/textures.dart';
import 'package:herramienta_shaiya/data/item_assets.dart';

void main() {
  test('uncompressed DDS round-trips every RGBA component including alpha', () {
    final rgba = Uint8List.fromList(
      List.generate(8 * 16 * 4, (i) => (i * 37) % 256),
    );
    final dds = ItemAtlas.encodeDds(rgba, 8, 16);
    final pixels = Pixels.decode(dds, 'icon.dds');
    expect(pixels.width, 8);
    expect(pixels.height, 16);
    expect(pixels.rgba, rgba);
    expect(ByteData.sublistView(dds).getUint32(76, Endian.little), 32);
  });
  test(
    'only the selected cell is replaced and caller data remains unchanged',
    () {
      final original = Uint8List.fromList(
        List.generate(16 * 16 * 4, (i) => i % 256),
      );
      final backup = Uint8List.fromList(original),
          tile = Uint8List(4 * 4 * 4)..fillRange(0, 64, 255);
      final changed = ItemAtlas.replaceCell(original, 16, 16, 4, 4, 5, tile);
      for (var y = 0; y < 16; y++) {
        for (var x = 0; x < 16; x++) {
          for (var c = 0; c < 4; c++) {
            final i = (y * 16 + x) * 4 + c;
            expect(
              changed[i],
              x >= 4 && x < 8 && y >= 4 && y < 8 ? 255 : original[i],
            );
          }
        }
      }
      expect(original, backup);
    },
  );
  test('mipmap sizes match the declared chain, including narrow sheets', () {
    final rgba = Uint8List(1 * 16 * 4)..fillRange(0, 64, 200);
    final dds = ItemAtlas.encodeDds(rgba, 1, 16, mipLevels: 5);
    expect(dds.length, 128 + (16 + 8 + 4 + 2 + 1) * 4);
    expect(ByteData.sublistView(dds).getUint32(28, Endian.little), 5);
    expect(Pixels.decode(dds, 'narrow.dds').rgba, rgba);
  });
  test(
    'a DDS-named TGA is detected by content and re-exported as real DDS',
    () {
      final tga = Uint8List(18 + 4 * 4 * 4);
      final header = ByteData.sublistView(tga);
      tga[2] = 2;
      header.setUint16(12, 4, Endian.little);
      header.setUint16(14, 4, Endian.little);
      tga[16] = 32;
      tga[17] = 0x28;
      for (var i = 18; i < tga.length; i += 4) {
        tga[i] = 30;
        tga[i + 1] = 20;
        tga[i + 2] = 10;
        tga[i + 3] = 255;
      }
      final rgba = Pixels.decode(tga, 'interface/icon/17.dds');
      expect(rgba.rgba.take(4), [10, 20, 30, 255]);
      final edited = ItemAtlas.encodeDds(rgba.rgba, 4, 4);
      final result = ItemAssetReplacement.validate((
        'interface/icon/17.dds',
        tga,
        edited,
      ));
      expect(
        ByteData.sublistView(result.bytes).getUint32(0, Endian.little),
        0x20534444,
      );
      expect(
        Pixels.decode(result.bytes, 'interface/icon/17.dds').rgba,
        rgba.rgba,
      );
    },
  );
  test('invalid grid, tile, allocation and mip counts fail', () {
    expect(
      () => ItemAtlas.replaceCell(Uint8List(0), 0, 0, 1, 1, 0, Uint8List(0)),
      throwsFormatException,
    );
    expect(
      () => ItemAtlas.replaceCell(Uint8List(16), 2, 2, 3, 1, 0, Uint8List(4)),
      throwsFormatException,
    );
    expect(
      () => ItemAtlas.encodeDds(Uint8List(16), 2, 2, mipLevels: 10),
      throwsFormatException,
    );
    expect(
      () => ItemAtlas.encodeDds(Uint8List(1), 2, 2),
      throwsFormatException,
    );
  });
  test(
    'native texture import validates shape and reopens before publication',
    () {
      final a = ItemAtlas.encodeDds(Uint8List(4 * 4 * 4), 4, 4);
      final b = ItemAtlas.encodeDds(
        Uint8List(4 * 4 * 4)..fillRange(0, 64, 100),
        4,
        4,
      );
      final replacement = ItemAssetReplacement.validate((
        'item/dds/test.dds',
        a,
        b,
      ));
      expect(
        Pixels.decode(replacement.bytes, 'test.dds').rgba,
        Pixels.decode(b, 'test.dds').rgba,
      );
      final other = ItemAtlas.encodeDds(Uint8List(8 * 8 * 4), 8, 8);
      expect(
        () => ItemAssetReplacement.validate(('item/dds/test.dds', a, other)),
        throwsFormatException,
      );
      expect(
        () => ItemAssetReplacement.validate((
          'item/dds/test.dds',
          a,
          Uint8List.fromList([1, 2, 3]),
        )),
        throwsFormatException,
      );
    },
  );
}
