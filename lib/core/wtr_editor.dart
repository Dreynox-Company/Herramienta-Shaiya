import 'dart:convert';
import 'dart:typed_data';

import 'formats.dart';
import 'legacy_text.dart';

class WtrTextureEdit {
  String value;
  final Uint8List originalRaw;
  final String originalValue;
  bool dirty = false;

  WtrTextureEdit(this.value, this.originalRaw, this.originalValue);
}

/// Rebuild-safe editor for the fully known WTR structure.
///
/// Unchanged strings reuse their exact original bytes. Edited texture paths are
/// restricted to portable ASCII so Studio never guesses a legacy code page.
class WtrEditorDocument {
  final String path;
  double tileSize;
  final int unknown2, unknown3;
  final List<WtrTextureEdit> textures;

  WtrEditorDocument._(
    this.path,
    this.tileSize,
    this.unknown2,
    this.unknown3,
    this.textures,
  );

  static WtrEditorDocument parse(Uint8List bytes, String path) {
    final r = _WtrCursor(bytes, path);
    final tileSize = r.f32();
    if (!tileSize.isFinite || tileSize <= 0 || tileSize > 100000) {
      r.fail('Tamaño de celda WTR inválido.');
    }
    final unknown2 = r.u32();
    final unknown3 = r.i32();
    final count = r.count(256);
    if (count == 0) r.fail('WTR sin texturas.');

    final textures = <WtrTextureEdit>[];
    for (var i = 0; i < count; i++) {
      final raw = r.rawString(65536);
      final end = raw.indexOf(0);
      final decoded = LegacyText.decode(
        end < 0 ? raw : raw.sublist(0, end),
      );
      textures.add(
        WtrTextureEdit(decoded, Uint8List.fromList(raw), decoded),
      );
    }
    r.end();

    WtrData.parse(bytes, path);
    return WtrEditorDocument._(
      path,
      tileSize,
      unknown2,
      unknown3,
      textures,
    );
  }

  void setTileSize(double value) {
    if (!value.isFinite || value <= 0 || value > 100000) {
      throw FormatException('$path: tileSize WTR fuera de rango.');
    }
    tileSize = value;
  }

  void setTexture(int index, String value) {
    if (index < 0 || index >= textures.length) {
      throw FormatException('$path: textura WTR fuera de rango: $index.');
    }
    final normalized = value.trim().replaceAll('\\', '/');
    if (normalized.isEmpty ||
        normalized.startsWith('/') ||
        normalized.contains('..') ||
        normalized.contains(':') ||
        !RegExp(r'^[\x20-\x7E]+$').hasMatch(normalized) ||
        !RegExp(
          r'\.(dds|tga|bmp|png)$',
          caseSensitive: false,
        ).hasMatch(normalized)) {
      throw FormatException('$path: referencia de textura WTR inválida.');
    }
    textures[index]
      ..value = normalized
      ..dirty = normalized != textures[index].originalValue;
  }

  Uint8List encode() {
    final out = BytesBuilder(copy: false);

    void u32(int value) {
      final data = ByteData(4)..setUint32(0, value, Endian.little);
      out.add(data.buffer.asUint8List());
    }

    void i32(int value) {
      final data = ByteData(4)..setInt32(0, value, Endian.little);
      out.add(data.buffer.asUint8List());
    }

    void f32(double value) {
      final data = ByteData(4)..setFloat32(0, value, Endian.little);
      out.add(data.buffer.asUint8List());
    }

    f32(tileSize);
    u32(unknown2);
    i32(unknown3);
    u32(textures.length);
    for (final texture in textures) {
      final raw = texture.dirty
          ? Uint8List.fromList(ascii.encode(texture.value))
          : texture.originalRaw;
      u32(raw.length);
      out.add(raw);
    }
    return out.takeBytes();
  }

  void validateEncoded(Uint8List bytes) {
    final semantic = WtrData.parse(bytes, path);
    final parsed = WtrEditorDocument.parse(bytes, path);
    if ((parsed.tileSize - tileSize).abs() > 1e-5 ||
        parsed.unknown2 != unknown2 ||
        parsed.unknown3 != unknown3 ||
        parsed.textures.length != textures.length ||
        semantic.textures.length != textures.length) {
      throw FormatException('$path: la serialización WTR no revalidó.');
    }
    for (var i = 0; i < textures.length; i++) {
      if (parsed.textures[i].value != textures[i].value ||
          semantic.textures[i] != textures[i].value) {
        throw FormatException('$path: textura WTR #$i no revalidó.');
      }
    }
  }
}

class _WtrCursor {
  final Uint8List bytes;
  late final ByteData data = ByteData.sublistView(bytes);
  final String path;
  int offset = 0;

  _WtrCursor(this.bytes, this.path);

  Never fail(String message) =>
      throw FormatException('$path · byte $offset: $message');

  void need(int count) {
    if (count < 0 || offset + count > bytes.length) {
      fail('Archivo truncado ($count bytes).');
    }
  }

  int u32() {
    need(4);
    final value = data.getUint32(offset, Endian.little);
    offset += 4;
    return value;
  }

  int i32() {
    need(4);
    final value = data.getInt32(offset, Endian.little);
    offset += 4;
    return value;
  }

  double f32() {
    need(4);
    final value = data.getFloat32(offset, Endian.little);
    offset += 4;
    if (!value.isFinite) fail('Float no finito.');
    return value;
  }

  int count(int max) {
    final value = u32();
    if (value > max) fail('Recuento fuera de límite: $value.');
    return value;
  }

  Uint8List rawString(int max) {
    final size = count(max);
    need(size);
    final value = Uint8List.fromList(bytes.sublist(offset, offset + size));
    offset += size;
    return value;
  }

  void end() {
    if (offset != bytes.length) {
      fail('Quedan ${bytes.length - offset} bytes sin interpretar.');
    }
  }
}
