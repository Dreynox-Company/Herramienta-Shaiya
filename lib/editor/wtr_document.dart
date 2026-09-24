import 'dart:typed_data';

import '../core/formats.dart';
import '../core/game_text_codec.dart';
import 'document.dart';

class WtrDocument extends EditDocument {
  WtrDocument._({
    required super.path,
    required super.original,
    required super.payload,
    required super.rows,
    required super.codec,
  }) : super(
         profile: 'wtr',
         warnings: const [
           'WTR real: TileSize + dos enteros de cabecera + tabla de texturas fijas de 256 bytes. '
               'Solo TileSize y rutas de textura tienen semántica de escritura confirmada; '
               'los enteros desconocidos y el recuento permanecen protegidos.',
         ],
         parsedBytes: payload.length,
       );

  static WtrDocument open(
    Uint8List input,
    String path,
    GameTextEncoding encoding,
  ) {
    final parsed = WtrData.parse(input, path);
    final effectiveEncoding = encoding == GameTextEncoding.automatic
        ? GameTextEncoding.windows1252
        : encoding;
    final codec = GameTextCodec(effectiveEncoding);
    if (input.length != 16 + parsed.textures.length * 256) {
      throw FormatException(
        '$path: longitud WTR inesperada; Studio no escribirá una variante no autenticada.',
      );
    }

    final rows = <RecordRef>[
      RecordRef(
        0,
        16,
        const [],
        kind: 'Cabecera WTR',
        ordinal: 0,
        dynamicSpans: const [
          FieldSpan(FieldSpec('TileSize', 'f32'), 0, 4),
          FieldSpan(
            FieldSpec('Unknown2', 'u32', editable: false),
            4,
            4,
          ),
          FieldSpan(
            FieldSpec('Unknown3', 'i32', editable: false),
            8,
            4,
          ),
          FieldSpan(FieldSpec('TextureCount', 'u32', editable: false), 12, 4),
        ],
      ),
    ];

    for (var i = 0; i < parsed.textures.length; i++) {
      final start = 16 + i * 256;
      rows.add(
        RecordRef(
          start,
          start + 256,
          const [],
          kind: 'Textura WTR',
          ordinal: i,
          dynamicSpans: [
            FieldSpan(FieldSpec('Texture', 'text256'), start, 256),
          ],
        ),
      );
    }

    return WtrDocument._(
      path: path,
      original: Uint8List.fromList(input),
      payload: Uint8List.fromList(input),
      rows: List.unmodifiable(rows),
      codec: codec,
    );
  }

  @override
  Uint8List validate(FieldSpan field, String text) {
    if (field.spec.name == 'TileSize') {
      final value = double.tryParse(text.trim().replaceAll(',', '.'));
      if (value == null || !value.isFinite || value <= 0 || value > 100000) {
        throw const FormatException(
          'TileSize WTR debe ser finito, mayor que 0 y menor o igual a 100000.',
        );
      }
    }
    if (field.spec.name == 'Texture') {
      final normalized = text.trim().replaceAll('\\', '/');
      if (normalized.isEmpty ||
          normalized.startsWith('/') ||
          normalized.contains(':') ||
          RegExp(r'(^|/)\.\.(/|$)').hasMatch(normalized)) {
        throw const FormatException(
          'La textura WTR debe ser una ruta relativa segura dentro de DATA.',
        );
      }
      final lower = normalized.toLowerCase();
      if (!const ['.dds', '.tga', '.bmp', '.png'].any(lower.endsWith)) {
        throw const FormatException(
          'WTR solo admite referencias de textura DDS/TGA/BMP/PNG.',
        );
      }
      return super.validate(field, normalized);
    }
    return super.validate(field, text);
  }

  @override
  Uint8List exportBytes() {
    final out = super.exportBytes();
    final reparsed = WtrData.parse(out, path);
    if (out.length != 16 + reparsed.textures.length * 256) {
      throw FormatException('$path: el WTR editado no conservó su layout.');
    }
    return out;
  }
}
