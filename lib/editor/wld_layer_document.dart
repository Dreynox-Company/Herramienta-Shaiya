import 'dart:convert';
import 'dart:typed_data';

import '../core/game_text_codec.dart';
import '../core/world_resources.dart';
import 'document.dart';

/// Lossless editor for the authenticated exterior FLD/WLD terrain-layer header.
///
/// The complete WLD is parsed first by [WorldResource.parse]. Studio then
/// exposes only spans whose layout is confirmed by the reader: map size and
/// layer count remain read-only, while each layer's fixed texture/sound path,
/// tile scalar and the fixed layout path can be edited. Geometry, heights,
/// object instances and all later metadata remain byte-identical.
class WldLayerDocument extends EditDocument {
  WldLayerDocument._({
    required super.path,
    required super.original,
    required super.payload,
    required super.rows,
    required super.codec,
  }) : super(
         profile: 'wld_layers',
         warnings: const [
           'WLD exterior: solo capas de terreno y layout confirmado. '
               'Dimensión, recuentos, alturas, tipos, objetos y metadatos '
               'posteriores permanecen protegidos.',
           'Las cadenas WLD se escriben con la codificación coreana CP949 '
               'usada por el lector clásico; rutas ASCII conservan identidad.',
         ],
         parsedBytes: payload.length,
       );

  static WldLayerDocument open(
    Uint8List input,
    String path,
    GameTextEncoding _,
  ) {
    if (input.length > 128 * 1024 * 1024) {
      throw const FormatException('WLD mayor de 128 MiB.');
    }
    final parsed = WorldResource.parse(input, path);
    if (input.length < 8) {
      throw FormatException('$path: cabecera WLD truncada.');
    }
    final signature = ascii.decode(
      input.sublist(0, 4).takeWhile((b) => b != 0).toList(),
      allowInvalid: false,
    );
    if (signature != 'FLD') {
      throw FormatException(
        '$path: el editor de capas WLD solo escribe mapas exteriores FLD. '
        'DUN permanece de solo lectura hasta autenticar su contrato de autoría.',
      );
    }

    final data = ByteData.sublistView(input);
    final size = data.getUint32(4, Endian.little);
    if (size != parsed.terrain.size || size < 2 || size.isOdd) {
      throw FormatException('$path: dimensión FLD incoherente.');
    }
    final terrainCells = (size ~/ 2 + 1) * (size ~/ 2 + 1);
    final countOffset = 8 + terrainCells * 3;
    if (countOffset + 4 > input.length) {
      throw FormatException('$path: tabla de capas WLD truncada.');
    }
    final count = data.getUint32(countOffset, Endian.little);
    if (count != parsed.terrain.layers.length || count > 256) {
      throw FormatException('$path: recuento de capas WLD incoherente.');
    }
    final layersOffset = countOffset + 4;
    final layoutOffset = layersOffset + count * 516;
    if (layoutOffset + 256 > input.length) {
      throw FormatException('$path: layout WLD fuera del archivo.');
    }

    final rows = <RecordRef>[
      RecordRef(
        4,
        countOffset + 4,
        const [],
        kind: 'Cabecera WLD',
        ordinal: 0,
        dynamicSpans: [
          const FieldSpan(FieldSpec('MapSize', 'u32', editable: false), 4, 4),
          FieldSpan(
            const FieldSpec('LayerCount', 'u32', editable: false),
            countOffset,
            4,
          ),
        ],
      ),
    ];

    for (var i = 0; i < count; i++) {
      final start = layersOffset + i * 516;
      rows.add(
        RecordRef(
          start,
          start + 516,
          const [],
          kind: 'Capa de terreno WLD',
          ordinal: i,
          dynamicSpans: [
            FieldSpan(const FieldSpec('Texture', 'text256'), start, 256),
            FieldSpan(const FieldSpec('Tile', 'f32'), start + 256, 4),
            FieldSpan(const FieldSpec('Sound', 'text256'), start + 260, 256),
          ],
        ),
      );
    }
    rows.add(
      RecordRef(
        layoutOffset,
        layoutOffset + 256,
        const [],
        kind: 'Layout WLD',
        ordinal: 0,
        dynamicSpans: [
          FieldSpan(const FieldSpec('Layout', 'text256'), layoutOffset, 256),
        ],
      ),
    );

    return WldLayerDocument._(
      path: path,
      original: Uint8List.fromList(input),
      payload: Uint8List.fromList(input),
      rows: List.unmodifiable(rows),
      codec: const GameTextCodec(GameTextEncoding.korean),
    );
  }

  @override
  Uint8List validate(FieldSpan field, String text) {
    if (field.spec.type == 'text256') {
      final normalized = text.trim().replaceAll('\\', '/');
      final optional = field.spec.name == 'Sound';
      if ((!optional && normalized.isEmpty) ||
          normalized.startsWith('/') ||
          normalized.contains(':') ||
          RegExp(r'(^|/)\.\.(/|$)').hasMatch(normalized)) {
        throw FormatException(
          '${field.spec.name}: usa una ruta relativa segura dentro de DATA.',
        );
      }
      return super.validate(field, normalized);
    }
    return super.validate(field, text);
  }

  @override
  Uint8List exportBytes() {
    final out = super.exportBytes();
    final reparsed = WorldResource.parse(out, path);
    final originalParsed = WorldResource.parse(original, path);
    if (reparsed.terrain.size != originalParsed.terrain.size ||
        reparsed.terrain.layers.length !=
            originalParsed.terrain.layers.length ||
        reparsed.terrain.heights.length !=
            originalParsed.terrain.heights.length ||
        reparsed.terrain.types.length != originalParsed.terrain.types.length ||
        reparsed.terrain.objects.length !=
            originalParsed.terrain.objects.length) {
      throw FormatException(
        '$path: el WLD editado alteró estructura fuera de las capas permitidas.',
      );
    }
    return out;
  }
}
