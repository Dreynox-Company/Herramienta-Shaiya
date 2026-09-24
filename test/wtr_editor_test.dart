import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/formats.dart';
import 'package:herramienta_shaiya/core/wtr_editor.dart';

Uint8List fixture() {
  final out = BytesBuilder(copy: false);

  void u32(int value) {
    final b = ByteData(4)..setUint32(0, value, Endian.little);
    out.add(b.buffer.asUint8List());
  }

  void i32(int value) {
    final b = ByteData(4)..setInt32(0, value, Endian.little);
    out.add(b.buffer.asUint8List());
  }

  void f32(double value) {
    final b = ByteData(4)..setFloat32(0, value, Endian.little);
    out.add(b.buffer.asUint8List());
  }

  void str(List<int> bytes) {
    u32(bytes.length);
    out.add(bytes);
  }

  f32(32);
  u32(0x11223344);
  i32(-123);
  u32(3);
  str(ascii.encode('grass.dds'));
  str([...ascii.encode('rock.tga'), 0]);
  str(ascii.encode('road.bmp'));
  return out.takeBytes();
}

void main() {
  test('WTR unchanged data round-trips byte-for-byte', () {
    final original = fixture();
    final doc = WtrEditorDocument.parse(original, 'world/test.wtr');
    expect(doc.tileSize, 32);
    expect(doc.unknown2, 0x11223344);
    expect(doc.unknown3, -123);
    expect(doc.textures.map((e) => e.value), [
      'grass.dds',
      'rock.tga',
      'road.bmp',
    ]);
    expect(doc.encode(), orderedEquals(original));
  });

  test('WTR edits tile size and one texture without touching unknown fields', () {
    final doc = WtrEditorDocument.parse(fixture(), 'world/test.wtr');
    doc.setTileSize(48.5);
    doc.setTexture(1, 'terrain/rock_new.dds');

    final encoded = doc.encode();
    doc.validateEncoded(encoded);

    final parsed = WtrEditorDocument.parse(encoded, 'world/test.wtr');
    expect(parsed.tileSize, closeTo(48.5, 1e-6));
    expect(parsed.unknown2, 0x11223344);
    expect(parsed.unknown3, -123);
    expect(parsed.textures[0].value, 'grass.dds');
    expect(parsed.textures[1].value, 'terrain/rock_new.dds');
    expect(parsed.textures[2].value, 'road.bmp');

    final semantic = WtrData.parse(encoded, 'world/test.wtr');
    expect(semantic.textures[1], 'terrain/rock_new.dds');
  });

  test('WTR path editing fails closed on unsafe or unsupported values', () {
    final doc = WtrEditorDocument.parse(fixture(), 'world/test.wtr');
    for (final value in [
      '',
      '../evil.dds',
      'C:/evil.dds',
      '/absolute.dds',
      'texture.exe',
      'textura_ñ.dds',
    ]) {
      expect(() => doc.setTexture(0, value), throwsFormatException);
    }
    expect(() => doc.setTileSize(double.nan), throwsFormatException);
    expect(() => doc.setTileSize(0), throwsFormatException);
  });
}
