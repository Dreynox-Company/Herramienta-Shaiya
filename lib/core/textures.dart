import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'formats.dart';

/// Texturas de color original. El modo Glow de MLT no usa alfa como opacidad.
class Pixels {
  final int width, height;
  final Uint8List rgba;
  Pixels(this.width, this.height, this.rgba);
  Uint8List png({bool opaque = false}) {
    final bytes = Uint8List.fromList(rgba);
    if (opaque) {
      for (var i = 3; i < bytes.length; i += 4) {
        bytes[i] = 255;
      }
    }
    return Uint8List.fromList(
      img.encodePng(
        img.Image.fromBytes(
          width: width,
          height: height,
          bytes: bytes.buffer,
          numChannels: 4,
          order: img.ChannelOrder.rgba,
        ),
      ),
    );
  }

  static Pixels decode(Uint8List bytes, String source) {
    if (bytes.length >= 4 &&
        ByteData.sublistView(bytes).getUint32(0, Endian.little) == 0x20534444) {
      return dds(bytes, source);
    }
    final im = img.decodeImage(bytes);
    if (im == null) {
      throw FormatException('No se pudo decodificar la textura: $source');
    }
    return Pixels(
      im.width,
      im.height,
      im.convert(numChannels: 4).getBytes(order: img.ChannelOrder.rgba),
    );
  }

  static Pixels dds(Uint8List bytes, String source) {
    final r = Bin(bytes, source);
    r.need(128);
    final d = r.data;
    if (d.getUint32(0, Endian.little) != 0x20534444 ||
        d.getUint32(4, Endian.little) != 124) {
      r.fail('Cabecera DDS inválida.');
    }
    final h = d.getUint32(12, Endian.little),
        w = d.getUint32(16, Endian.little);
    if (w == 0 || h == 0 || w * h > 16777216) {
      r.fail('Tamaño DDS fuera de límite.');
    }
    var code = String.fromCharCodes(bytes.sublist(84, 88)), offset = 128;
    var bits = d.getUint32(88, Endian.little),
        masks = List.generate(4, (i) => d.getUint32(92 + i * 4, Endian.little));
    final pixelFlags = d.getUint32(80, Endian.little);
    final out = Uint8List(w * h * 4);
    // DDPF_PALETTEINDEXED8: tabla RGBA de 256 entradas seguida de índices.
    // Utilizada por varias alas originales; no es una imagen RGB de 8 bits.
    if ((pixelFlags & 0x20) != 0) {
      if (bits != 8) r.fail('La paleta DDS requiere índices de 8 bits.');
      r.offset = 128;
      r.need(1024);
      final palette = bytes.sublist(128, 1152);
      final flags = d.getUint32(8, Endian.little),
          pitch = d.getUint32(20, Endian.little);
      final stride = (flags & 8) != 0 && pitch >= w ? pitch : w;
      r.offset = 1152;
      r.need(stride * h);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final index = bytes[1152 + y * stride + x] * 4, k = (y * w + x) * 4;
          for (var c = 0; c < 4; c++) {
            out[k + c] = palette[index + c];
          }
        }
      }
      return Pixels(w, h, out);
    }
    if ((pixelFlags & 0x20000) != 0 && [8, 16].contains(bits)) {
      final step = bits ~/ 8;
      r.offset = 128;
      r.need(w * h * step);
      for (var i = 0; i < w * h; i++) {
        final luminance = bytes[128 + i * step];
        out[i * 4] = out[i * 4 + 1] = out[i * 4 + 2] = luminance;
        out[i * 4 + 3] = step == 2 ? bytes[128 + i * step + 1] : 255;
      }
      return Pixels(w, h, out);
    }
    if (code == 'DX10') {
      r.offset = 128;
      r.need(20);
      final format = r.u32();
      r.skip(16);
      offset = 148;
      if ([71, 72].contains(format)) {
        code = 'DXT1';
      } else if ([74, 75].contains(format)) {
        code = 'DXT3';
      } else if ([77, 78].contains(format)) {
        code = 'DXT5';
      } else if ([28, 29].contains(format)) {
        code = '';
        bits = 32;
        masks = [255, 65280, 16711680, 4278190080];
      } else if ([87, 91].contains(format)) {
        code = '';
        bits = 32;
        masks = [16711680, 65280, 255, 4278190080];
      } else {
        r.fail('DDS DX10 $format no soportado. No se sustituye por negro.');
      }
    }
    final premultiplied = code == 'DXT2' || code == 'DXT4';
    if (code == 'DXT2') code = 'DXT3';
    if (code == 'DXT4') code = 'DXT5';
    void put(int x, int y, List<int> c, int a) {
      if (x >= w || y >= h) return;
      final k = (y * w + x) * 4;
      for (var j = 0; j < 3; j++) {
        out[k + j] = premultiplied && a > 0
            ? (c[j] * 255 ~/ a).clamp(0, 255)
            : c[j];
      }
      out[k + 3] = a;
    }

    List<int> rgb(int x) => [
      ((x >> 11) & 31) * 255 ~/ 31,
      ((x >> 5) & 63) * 255 ~/ 63,
      (x & 31) * 255 ~/ 31,
    ];
    if (['DXT1', 'DXT3', 'DXT5'].contains(code)) {
      final blockSize = code == 'DXT1' ? 8 : 16;
      r.offset = offset;
      r.need(((w + 3) ~/ 4) * ((h + 3) ~/ 4) * blockSize);
      for (var y = 0; y < h; y += 4) {
        for (var x = 0; x < w; x += 4) {
          final alpha = List<int>.filled(16, 255), start = offset;
          if (code == 'DXT3') {
            for (var i = 0; i < 16; i++) {
              alpha[i] = ((bytes[offset + i ~/ 2] >> ((i % 2) * 4)) & 15) * 17;
            }
            offset += 8;
          }
          if (code == 'DXT5') {
            final a0 = bytes[offset],
                a1 = bytes[offset + 1],
                palette = <int>[a0, a1];
            if (a0 > a1) {
              for (var i = 1; i <= 6; i++) {
                palette.add(((7 - i) * a0 + i * a1) ~/ 7);
              }
            } else {
              for (var i = 1; i <= 4; i++) {
                palette.add(((5 - i) * a0 + i * a1) ~/ 5);
              }
              palette.addAll([0, 255]);
            }
            var packed = 0;
            for (var i = 0; i < 6; i++) {
              packed |= bytes[offset + 2 + i] << (8 * i);
            }
            for (var i = 0; i < 16; i++) {
              alpha[i] = palette[(packed >> (3 * i)) & 7];
            }
            offset += 8;
          }
          final c0 = d.getUint16(offset, Endian.little),
              c1 = d.getUint16(offset + 2, Endian.little),
              colors = [
                rgb(d.getUint16(offset, Endian.little)),
                rgb(d.getUint16(offset + 2, Endian.little)),
              ];
          if (c0 > c1 || code != 'DXT1') {
            colors.add(
              List.generate(3, (k) => (2 * colors[0][k] + colors[1][k]) ~/ 3),
            );
            colors.add(
              List.generate(3, (k) => (colors[0][k] + 2 * colors[1][k]) ~/ 3),
            );
          } else {
            colors.add(
              List.generate(3, (k) => (colors[0][k] + colors[1][k]) ~/ 2),
            );
            colors.add([0, 0, 0]);
          }
          final packed = d.getUint32(offset + 4, Endian.little);
          for (var i = 0; i < 16; i++) {
            final c = (packed >> (i * 2)) & 3;
            put(
              x + i % 4,
              y + i ~/ 4,
              colors[c],
              code == 'DXT1' && c0 <= c1 && c == 3 ? 0 : alpha[i],
            );
          }
          offset = start + blockSize;
        }
      }
    } else {
      if (code.replaceAll('\u0000', '').isNotEmpty) {
        r.fail('Compresión DDS desconocida: $code.');
      }
      if (![16, 24, 32].contains(bits)) {
        r.fail('DDS RGB de $bits bits no soportado.');
      }
      final step = bits ~/ 8,
          pitch = d.getUint32(20, Endian.little),
          flags = d.getUint32(8, Endian.little);
      final stride = (flags & 8) != 0 && pitch >= w * step ? pitch : w * step;
      r.offset = offset;
      r.need(stride * h);
      int channel(int value, int mask, int fallback) {
        if (mask == 0) return fallback;
        var shift = 0;
        while (((mask >> shift) & 1) == 0) {
          shift++;
        }
        final max = mask >> shift;
        return (((value & mask) >> shift) * 255 / max).round().clamp(0, 255);
      }

      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          var value = 0;
          for (var k = 0; k < step; k++) {
            value |= bytes[offset + y * stride + x * step + k] << (8 * k);
          }
          put(x, y, [
            channel(value, masks[0], 0),
            channel(value, masks[1], 0),
            channel(value, masks[2], 0),
          ], channel(value, masks[3], 255));
        }
      }
    }
    return Pixels(w, h, out);
  }
}
