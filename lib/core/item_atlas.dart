import 'dart:typed_data';

/// Lossless RGBA -> native DDS A8R8G8B8, including box-filtered mipmaps.
/// Does not relabel a PNG as DDS or change the atlas dimensions/grid.
class ItemAtlas {
  static Uint8List encodeDds(
    Uint8List rgba,
    int width,
    int height, {
    int mipLevels = 1,
  }) {
    if (width <= 0 ||
        height <= 0 ||
        width * height > 4194304 ||
        rgba.length != width * height * 4 ||
        mipLevels < 1) {
      throw const FormatException('Dimensiones RGBA del atlas inválidas.');
    }
    var maximum = 1, maxSize = width > height ? width : height;
    while (maxSize > 1) {
      maxSize >>= 1;
      maximum++;
    }
    if (mipLevels > maximum)
      throw const FormatException('Cadena mip fuera de rango.');
    final out = BytesBuilder(copy: false),
        header = Uint8List(128),
        d = ByteData(128);
    d.setUint32(0, 0x20534444, Endian.little);
    d.setUint32(4, 124, Endian.little);
    d.setUint32(8, 0x100f | (mipLevels > 1 ? 0x20000 : 0), Endian.little);
    d.setUint32(12, height, Endian.little);
    d.setUint32(16, width, Endian.little);
    d.setUint32(20, width * 4, Endian.little);
    d.setUint32(28, mipLevels, Endian.little);
    d.setUint32(76, 32, Endian.little);
    d.setUint32(80, 0x41, Endian.little);
    d.setUint32(88, 32, Endian.little);
    d.setUint32(92, 0x00ff0000, Endian.little);
    d.setUint32(96, 0x0000ff00, Endian.little);
    d.setUint32(100, 0x000000ff, Endian.little);
    d.setUint32(104, 0xff000000, Endian.little);
    d.setUint32(108, 0x1000 | (mipLevels > 1 ? 0x400008 : 0), Endian.little);
    header.setAll(0, d.buffer.asUint8List());
    out.add(header);
    var pixels = rgba, w = width, h = height;
    for (var level = 0; level < mipLevels; level++) {
      final bgra = Uint8List(pixels.length);
      for (var i = 0; i < pixels.length; i += 4) {
        bgra[i] = pixels[i + 2];
        bgra[i + 1] = pixels[i + 1];
        bgra[i + 2] = pixels[i];
        bgra[i + 3] = pixels[i + 3];
      }
      out.add(bgra);
      if (level + 1 == mipLevels) break;
      final nw = w > 1 ? w ~/ 2 : 1, nh = h > 1 ? h ~/ 2 : 1;
      final next = Uint8List(nw * nh * 4);
      for (var y = 0; y < nh; y++) {
        for (var x = 0; x < nw; x++) {
          var n = 0, alpha = 0, red = 0, green = 0, blue = 0;
          for (var dy = 0; dy < (h > 1 ? 2 : 1); dy++) {
            for (var dx = 0; dx < (w > 1 ? 2 : 1); dx++) {
              final i = ((y * 2 + dy) * w + x * 2 + dx) * 4, a = pixels[i + 3];
              alpha += a;
              red += pixels[i] * a;
              green += pixels[i + 1] * a;
              blue += pixels[i + 2] * a;
              n++;
            }
          }
          final i = (y * nw + x) * 4;
          if (alpha > 0) {
            next[i] = (red / alpha).round();
            next[i + 1] = (green / alpha).round();
            next[i + 2] = (blue / alpha).round();
          }
          next[i + 3] = (alpha / n).round();
        }
      }
      pixels = next;
      w = nw;
      h = nh;
    }
    return out.takeBytes();
  }

  static Uint8List replaceCell(
    Uint8List atlas,
    int width,
    int height,
    int columns,
    int rows,
    int index,
    Uint8List tile,
  ) {
    if (width <= 0 ||
        height <= 0 ||
        width * height > 4194304 ||
        columns < 1 ||
        rows < 1 ||
        width % columns != 0 ||
        height % rows != 0 ||
        index < 0 ||
        index >= columns * rows ||
        atlas.length != width * height * 4) {
      throw const FormatException(
        'El atlas no coincide con la cuadrícula nativa.',
      );
    }
    final tw = width ~/ columns, th = height ~/ rows;
    if (tile.length != tw * th * 4)
      throw const FormatException(
        'La miniatura no tiene el tamaño de la celda.',
      );
    final output = Uint8List.fromList(atlas),
        sx = (index % columns) * tw,
        sy = (index ~/ columns) * th;
    for (var y = 0; y < th; y++) {
      output.setRange(
        ((sy + y) * width + sx) * 4,
        ((sy + y) * width + sx + tw) * 4,
        tile,
        y * tw * 4,
      );
    }
    return output;
  }
}
