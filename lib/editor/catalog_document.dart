import 'dart:convert';
import 'dart:typed_data';
import '../core/formats.dart';
import '../core/game_text_codec.dart';
import 'document.dart';

/// Original catalogs, not filename guesses. Structural counts are read-only;
/// scalar parameters and length-prefixed paths round-trip through their spans.
class CatalogDocument extends EditDocument {
  final List<FieldSpan> meshes, textures;
  final Map<int, int> indexLimits;
  CatalogDocument._({
    required super.path,
    required super.original,
    required super.payload,
    required super.rows,
    required super.codec,
    required super.profile,
    required this.meshes,
    required this.textures,
    required this.indexLimits,
  }) : super(
         parsedBytes: payload.length,
         warnings: const [
           'Catálogo original. Los índices y rutas se conservan por identidad. Editar una tabla del cliente no modifica automáticamente el servidor.',
         ],
       );
  @override
  Uint8List validate(FieldSpan field, String text) {
    final bytes = super.validate(field, text), limit = indexLimits[field.start];
    if (limit != null &&
        (int.parse(text.trim()) < 0 || int.parse(text.trim()) >= limit)) {
      throw FormatException(
        '${field.spec.name}: referencia fuera del catálogo (0 … ${limit - 1}).',
      );
    }
    if (field.spec.text &&
        field.spec.name != 'Name' &&
        RegExp(r'(^|[\\/])\.\.([\\/]|$)').hasMatch(text)) {
      throw const FormatException('No se permiten rutas que salgan de DATA.');
    }
    return bytes;
  }

  List<(String, String, int)> materials(int row) {
    final values = {for (final f in fields(row)) f.spec.name: read(f)};
    if (values.containsKey('MeshIndex')) {
      final m = int.tryParse(values['MeshIndex']!),
          t = int.tryParse(values['TextureIndex'] ?? '');
      if (m != null &&
          t != null &&
          m >= 0 &&
          m < meshes.length &&
          t >= 0 &&
          t < textures.length) {
        return [
          (
            read(meshes[m]),
            read(textures[t]),
            int.tryParse(values['Alpha'] ?? '') ?? 0,
          ),
        ];
      }
    }
    return [
      for (var i = 0; values.containsKey('Parts[$i].Mesh'); i++)
        (values['Parts[$i].Mesh']!, values['Parts[$i].Texture'] ?? '', 0),
    ];
  }

  static CatalogDocument open(
    Uint8List input,
    String path,
    GameTextEncoding encoding,
  ) {
    if (input.length > 64 * 1024 * 1024) {
      throw const FormatException('Catálogo mayor de 64 MiB.');
    }
    // Runtime format validators verify all names, bounds and attachment layouts.
    final p = path.toLowerCase(), codec = GameTextCodec(encoding);
    if (p.endsWith('.mlt')) {
      readMlt(input, path);
    } else if (p.endsWith('.itm')) {
      readItm(input, path);
    } else if (p.endsWith('.mon')) {
      readMon(input, path);
    } else {
      throw const FormatException('Catálogo no reconocido.');
    }
    final c = _CatalogCursor(input, codec),
        meshes = <FieldSpan>[],
        textures = <FieldSpan>[];
    final limits = <int, int>{};
    String profile;
    final panda =
        input.length >= 8 &&
        ascii.decode(input.sublist(0, 8), allowInvalid: true) == 'pandaIT2';
    if (panda) c.r.skip(5);
    final sig = c.r.str(3);
    if (sig == 'MLT' || sig == 'ITM' || sig == 'IT2') {
      profile = sig.toLowerCase();
      for (var i = 0, n = c.r.count(20000); i < n; i++) {
        c.begin('Geometría', i);
        meshes.add(c.text('Mesh'));
        c.end();
      }
      for (var i = 0, n = c.r.count(20000); i < n; i++) {
        c.begin('Textura', i);
        textures.add(c.text('Texture'));
        c.end();
      }
      for (var i = 0, n = c.r.count(30000); i < n; i++) {
        c.begin(sig == 'MLT' ? 'Material' : 'Equipo', i);
        final m = c.number('MeshIndex', 'u32'),
            t = c.number('TextureIndex', 'u32');
        limits[m.start] = meshes.length;
        limits[t.start] = textures.length;
        c.number('Alpha', sig == 'MLT' ? 'u32' : 'i32');
        if (sig != 'MLT') {
          c.number('Reserved0', 'i32', edit: false);
          final ext = c.r.data.getInt32(c.r.offset, Endian.little);
          c.number('Extended', 'i32', edit: false);
          c.number('Reserved1', 'i32', edit: false);
          if (ext == 1) c.opaque('Extension', 16);
          if (sig == 'IT2') {
            for (var a = 0; a < (panda ? 24 : 16); a++) {
              for (var hand = 0; hand < 2; hand++) {
                c.number('Attachment[$a][$hand].Bone', 'i32');
                for (final axis in ['X', 'Y', 'Z']) {
                  c.number('Attachment[$a][$hand].Position.$axis', 'f32');
                }
                for (final axis in ['X', 'Y', 'Z', 'W']) {
                  c.number('Attachment[$a][$hand].Rotation.$axis', 'f32');
                }
              }
            }
          }
        }
        c.end();
      }
    } else if (sig == 'MO2' || sig == 'MO4') {
      profile = sig.toLowerCase();
      for (var i = 0, n = c.r.count(10000); i < n; i++) {
        c.begin('Modelo animado', i);
        c.text('Name');
        c.number('Flag', 'u8');
        for (final k in [
          'Walk',
          'Run',
          'Attack1',
          'Attack2',
          'Attack3',
          'Death',
          'Breathe',
          'Damage',
          'Idle',
        ]) {
          c.text('Animation.$k');
        }
        for (final k in ['Attack1', 'Attack2', 'Attack3', 'Death']) {
          c.text('Sound.$k');
        }
        for (final k in ['Attack1', 'Attack2', 'Attack3', 'Death']) {
          c.text('Effect.$k');
        }
        if (sig == 'MO4') c.text('Effect.Attached');
        final count = c.r.data.getUint32(c.r.offset, Endian.little);
        c.number('PartCount', 'u32', edit: false);
        for (var j = 0; j < count; j++) {
          c.text('Parts[$j].Mesh');
          c.text('Parts[$j].Texture');
        }
        c.number('Height', 'f32');
        final extensions = c.r.data.getUint32(c.r.offset, Endian.little);
        c.number('ExtensionCount', 'u32', edit: false);
        if (extensions > 0) c.opaque('Extension', extensions * 8);
        c.end();
      }
    } else {
      throw const FormatException('Perfil de catálogo desconocido.');
    }
    c.r.end();
    return CatalogDocument._(
      path: path,
      original: Uint8List.fromList(input),
      payload: Uint8List.fromList(input),
      rows: c.rows,
      codec: codec,
      profile: profile,
      meshes: meshes,
      textures: textures,
      indexLimits: limits,
    );
  }
}

class _CatalogCursor {
  final Bin r;
  final GameTextCodec codec;
  final rows = <RecordRef>[];
  List<FieldSpan> spans = [];
  int start = 0, ordinal = 0;
  String kind = '';
  _CatalogCursor(Uint8List b, this.codec) : r = Bin(b, 'Catálogo');
  void begin(String k, int i) {
    start = r.offset;
    kind = k;
    ordinal = i;
    spans = [];
  }

  void end() {
    rows.add(
      RecordRef(
        start,
        r.offset,
        const [],
        kind: kind,
        ordinal: ordinal,
        dynamicSpans: spans,
      ),
    );
  }

  FieldSpan number(String name, String type, {bool edit = true}) {
    final spec = FieldSpec(name, type, editable: edit),
        f = FieldSpan(spec, r.offset, spec.width);
    r.skip(spec.width);
    spans.add(f);
    return f;
  }

  void opaque(String name, int length) {
    final f = FieldSpan(
      FieldSpec(name, 'opaque', editable: false),
      r.offset,
      length,
    );
    r.skip(length);
    spans.add(f);
  }

  FieldSpan text(String name) {
    final at = r.offset, n = r.count(1048576);
    r.need(n);
    int zeros = 0;
    while (zeros < n && r.bytes[at + 4 + n - 1 - zeros] == 0) {
      zeros++;
    }
    codec.decode(Uint8List.sublistView(r.bytes, at + 4, at + 4 + n - zeros));
    r.skip(n);
    final f = FieldSpan(
      FieldSpec(name, 'text32'),
      at,
      4 + n,
      prefix: 4,
      terminators: zeros,
    );
    spans.add(f);
    return f;
  }
}
