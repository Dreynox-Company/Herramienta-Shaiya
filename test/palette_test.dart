import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/textures.dart';

void main() {
  test('DDS P8 interpreta la paleta RGBA y conserva su transparencia', () {
    final b = Uint8List(1154), d = ByteData.sublistView(b);
    d.setUint32(0, 0x20534444, Endian.little);
    d.setUint32(4, 124, Endian.little);
    d.setUint32(12, 1, Endian.little);
    d.setUint32(16, 2, Endian.little);
    d.setUint32(80, 32, Endian.little);
    d.setUint32(88, 8, Endian.little);
    b.setRange(128 + 4, 128 + 8, [245, 120, 80, 255]);
    b.setRange(128 + 8, 128 + 12, [20, 40, 200, 64]);
    b[1152] = 1;
    b[1153] = 2;
    final p = Pixels.dds(b, 'paleta.dds');
    expect(p.rgba, [245, 120, 80, 255, 20, 40, 200, 64]);
    expect(
      () => Pixels.dds(b.sublist(0, 1140), 'truncada.dds'),
      throwsFormatException,
    );
  });
  test('el cambio de alfa no modifica los colores de piel', () {
    final p = Pixels(1, 1, Uint8List.fromList([224, 171, 145, 0]));
    final decoded = Pixels.decode(p.png(opaque: true), 'piel.png');
    expect(decoded.rgba, [224, 171, 145, 255]);
  });
}
