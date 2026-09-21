import 'dart:typed_data';
import 'formats.dart';
import 'seed_data.dart';
import 'legacy_text.dart';

class DataTable {
  final List<String> fields;
  final int count;
  final Bin reader;
  DataTable(this.fields, this.count, this.reader);
  factory DataTable.open(Uint8List input, String source) {
    final r = Bin(SeedData.decode(input), source);
    r.skip(128);
    final n = r.count(256), fields = <String>[];
    for (var i = 0; i < n; i++) {
      final count = r.u8();
      r.need(count * 2);
      fields.add(
        LegacyText.unicode(
          r.bytes.sublist(r.offset, r.offset + count * 2),
        ).toLowerCase(),
      );
      r.skip(count * 2);
    }
    return DataTable(fields, r.count(200000), r);
  }
  List<Map<String, int>> integers() {
    reader.need(count * fields.length * 8);
    final rows = <Map<String, int>>[];
    for (var i = 0; i < count; i++) {
      rows.add({for (final name in fields) name: reader.i64()});
    }
    // EP8 writers align the entire table to a block; do not accept nonzero payload.
    if (reader.remaining <= 15 &&
        reader.bytes.sublist(reader.offset).every((b) => b == 0)) {
      reader.skip(reader.remaining);
    }
    reader.end();
    return rows;
  }
}

class ItemName {
  final int type, id;
  final String name, description;
  ItemName(this.type, this.id, this.name, this.description);
  String get key => '$type:$id';
}

List<ItemName> readItemNames(Uint8List bytes, String source) {
  final table = DataTable.open(bytes, source), r = table.reader;
  if (!table.fields.contains('itemname')) {
    r.fail('No es una tabla de nombres de equipo.');
  }
  final rows = <ItemName>[];
  for (var i = 0; i < table.count; i++) {
    rows.add(ItemName(r.i64(), r.i64(), r.str(), r.str()));
  }
  if (r.remaining <= 15 && r.bytes.sublist(r.offset).every((b) => b == 0)) {
    r.skip(r.remaining);
  }
  r.end();
  return rows;
}

Map<int, String> readMonsterNames(Uint8List bytes, String source) {
  final table = DataTable.open(bytes, source), r = table.reader;
  if (!table.fields.contains('name')) {
    r.fail('No es una tabla de nombres de criaturas.');
  }
  final rows = <int, String>{};
  for (var i = 0; i < table.count; i++) {
    rows[r.i64()] = r.str();
  }
  if (r.remaining <= 15 && r.bytes.sublist(r.offset).every((b) => b == 0)) {
    r.skip(r.remaining);
  }
  r.end();
  return rows;
}

class ParticleRecipe {
  final int count, blend, emission, lifetime, color;
  final double velocity, size, stretch, speed;
  final String texture;
  final List<double> position;
  final bool visible;
  ParticleRecipe(
    this.count,
    this.blend,
    this.emission,
    this.lifetime,
    this.color,
    this.velocity,
    this.size,
    this.stretch,
    this.speed,
    this.texture,
    this.position,
    this.visible,
  );
}

class EffectRecipe {
  final int id;
  final List<ParticleRecipe> particles;
  EffectRecipe(this.id, this.particles);
}

List<EffectRecipe> readSeff(Uint8List bytes, String source) {
  final r = Bin(bytes, source), format = r.i32();
  if (format < 0 || format > 7) r.fail('Versión SEFF desconocida.');
  r.skip(12);
  final count = r.count(20000), out = <EffectRecipe>[];
  for (var i = 0; i < count; i++) {
    final id = r.i32(), n = r.count(2000), particles = <ParticleRecipe>[];
    for (var j = 0; j < n; j++) {
      final count = r.u32(),
          velocity = r.f32(),
          blend = r.u32(),
          emission = r.u32(),
          life = r.u32();
      r.f32();
      final tex = r.ustr();
      final red = r.u8(), green = r.u8(), blue = r.u8(), position = r.floats(3);
      r.f32();
      final size = r.f32(), visible = r.u8() != 0;
      r.f32();
      final stretch = format > 2 ? r.f32() : 1.0,
          speed = format > 3 ? r.f32() : 1.0;
      if (format > 5) r.u32();
      particles.add(
        ParticleRecipe(
          count,
          blend,
          emission,
          life,
          (red << 16) | (green << 8) | blue,
          velocity,
          size,
          stretch,
          speed,
          tex,
          position,
          visible,
        ),
      );
    }
    out.add(EffectRecipe(id, particles));
  }
  r.end();
  return out;
}

/// Only translated names are presented as translations. Unresolved entries get
/// stable Spanish descriptions, while the original name remains in the inspector.
String spanishItemName(String original, String fallback) {
  if (original.trim().isEmpty || RegExp(r'^[?\s]+$').hasMatch(original)) {
    return fallback;
  }
  if (!RegExp(r'[\u3400-\u9fff\ufffd]').hasMatch(original)) {
    return original.trim();
  }
  const words = {
    '單手長劍': 'espada larga',
    '單手劍': 'espada de una mano',
    '雙手劍': 'espada de dos manos',
    '寬刃劍': 'espada ancha',
    '魔紋劍': 'espada rúnica',
    '銀劍': 'espada de plata',
    '長劍': 'espada larga',
    '短劍': 'espada corta',
    '巨劍': 'mandoble',
    '單手斧': 'hacha de una mano',
    '雙手斧': 'hacha de dos manos',
    '戰斧': 'hacha de batalla',
    '巨斧': 'hacha pesada',
    '雙刃': 'hojas gemelas',
    '雙劍': 'espadas gemelas',
    '長矛': 'lanza',
    '長槍': 'lanza',
    '短槍': 'jabalina',
    '標槍': 'jabalina',
    '法杖': 'bastón',
    '魔杖': 'vara mágica',
    '木杖': 'bastón de madera',
    '弓箭': 'arco',
    '長弓': 'arco largo',
    '短弓': 'arco corto',
    '弩': 'ballesta',
    '匕首': 'daga',
    '短刀': 'daga',
    '盾牌': 'escudo',
    '盾': 'escudo',
    '拳套': 'garras',
    '粗制': 'rudimentaria',
    '粗製': 'rudimentaria',
    '貴重': 'noble',
    '見習': 'de aprendiz',
    '新手': 'de principiante',
    '讚美': 'reforzada',
    '英勇': 'heroica',
    '極限': 'extrema',
    '王者': 'real',
    '傳說': 'legendaria',
    '傳奇': 'legendaria',
    '神秘': 'misteriosa',
    '女神': 'de la diosa',
    '完美': 'perfecta',
    '放逐': 'del exilio',
    '期望': 'de la esperanza',
    '劍': 'espada',
    '斧': 'hacha',
    '槍': 'lanza',
    '杖': 'bastón',
    '弓': 'arco',
    '刀': 'hoja',
    '錘': 'maza',
    '爪': 'garra',
    '（1天）': '(1 día)',
    '（7天）': '(7 días)',
    '（30天）': '(30 días)',
  };
  var text = original;
  for (final e in words.entries) {
    text = text.replaceAll(e.key, ' ${e.value} ');
  }
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (RegExp(r'[\u3400-\u9fff\ufffd]').hasMatch(text)) return fallback;
  return text.isEmpty
      ? fallback
      : '${text[0].toUpperCase()}${text.substring(1)}';
}
