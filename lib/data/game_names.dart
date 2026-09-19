import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../core/game_metadata.dart';
import '../core/equipment_rules.dart';
import '../core/formats.dart';
import '../core/world_resources.dart';
import '../core/motion_catalog.dart';
import 'library.dart';

class GameNames {
  final Map<String, List<ItemRule>> itemRules = {};
  final Map<String, List<ItemName>> itemByModel = {};
  final Map<int, List<String>> monsters = {};
  final Map<String, WorldResource> maps = {};
  final List<EffectRecipe> weaponEffects = [];
  final List<String> warnings = [];
  int itemCount = 0;
  Future<void> load(Library library, void Function(String) progress) async {
    Future<Uint8List?> read(String path) async =>
        library.files.containsKey(path) ? library.read(path) : null;
    try {
      final data = await read('binarysdata/dbitemdata.sdata');
      if (data != null) itemRules.addAll(await compute(_rules, data));
      final titlePath =
          library.files.keys
              .where(
                (p) =>
                    p.startsWith('binarysdata/dbitemtext_') &&
                    p.endsWith('.sdata'),
              )
              .toList()
            ..sort(
              (a, b) => (a.contains('_esp') ? 0 : 1).compareTo(
                b.contains('_esp') ? 0 : 1,
              ),
            );
      if (data != null && titlePath.isNotEmpty) {
        progress('Relacionando nombres y modelos de equipo…');
        final info = await compute(_itemMetadata, {
          'data': data,
          'text': await library.read(titlePath.first),
        });
        itemByModel.addAll(info);
        itemCount = info.values.fold(0, (n, l) => n + l.length);
      }
    } catch (e) {
      warnings.add('Nombres de equipo: $e');
    }
    try {
      final data = await read('binarysdata/dbmonsterdata.sdata');
      final path = library.files.keys
          .where(
            (p) =>
                p.startsWith('binarysdata/dbmonstertext_') &&
                p.endsWith('.sdata'),
          )
          .firstOrNull;
      if (data != null && path != null) {
        monsters.addAll(
          await compute(_monsterMetadata, {
            'data': data,
            'text': await library.read(path),
          }),
        );
      }
    } catch (e) {
      warnings.add('Nombres de criaturas: $e');
    }
    final seff = await read('effect/weapon.seff');
    if (seff != null) {
      try {
        weaponEffects.addAll(await compute(_effects, seff));
      } catch (e) {
        warnings.add('Efectos de equipo: $e');
      }
    }
    final worldPaths = library.files.keys
        .where((p) => p.startsWith('world/') && p.endsWith('.wld'))
        .toList();
    for (var i = 0; i < worldPaths.length; i++) {
      final path = worldPaths[i];
      try {
        maps[path] = await compute(_world, {
          'bytes': await library.read(path),
          'path': path,
        });
      } catch (e) {
        warnings.add('$path: $e');
      }
      if (i % 8 == 0) {
        progress('Indexando escenarios: ${i + 1}/${worldPaths.length}');
      }
    }
  }

  String weaponTitle(WeaponRecord record) {
    final titles = itemByModel['${weaponFamily(record)}:${record.id}'] ?? [];
    final original =
        titles
            .where((t) => t.name.isNotEmpty && !t.name.contains('???'))
            .firstOrNull
            ?.name ??
        '';
    return spanishItemName(original, weaponLabel(record));
  }

  String weaponDetail(WeaponRecord record) {
    final names = itemByModel['${weaponFamily(record)}:${record.id}'] ?? [];
    return '${names.map((n) => n.name).toSet().take(7).join(' · ')}\n${record.mesh} · ${record.texture}';
  }

  String creatureTitle(CreatureRecord record, String fallback) {
    if (!record.source.startsWith('monster/')) return fallback;
    final titles = monsters[record.id] ?? [];
    return spanishItemName(titles.firstOrNull ?? '', fallback);
  }

  String mapTitle(String path) {
    final w = maps[path],
        id = baseName(path).replaceFirst('.wld', ''),
        layout = w?.terrain.layout.toLowerCase() ?? '';
    if (layout.contains('worldcup') || layout.contains('football')) {
      return 'Cancha de fútbol · $id';
    }
    if (layout.contains('wedding')) return 'Salón de bodas · $id';
    if (layout.contains('guild')) return 'Casa del gremio · $id';
    if (layout.contains('prison')) return 'Prisión · $id';
    if (layout.contains('l_a1_dun2')) {
      return 'Cloron · planta ${RegExp(r'([123])f').firstMatch(layout)?.group(1) ?? id}';
    }
    if (layout.contains('a1_dun1')) {
      return 'Ruinas de Cornwell · planta ${RegExp(r'([123])f').firstMatch(layout)?.group(1) ?? id} · $id';
    }
    final comments = w?.areas.map((a) => a.comment).join(' ') ?? '';
    if (id == '35' && comments.contains('아풀룬')) return 'Apulune';
    if (id == '36' && comments.contains('이리스')) return 'Iris';
    if (id == '43' && comments.contains('판도라')) return 'Pando';
    if (id == '1' &&
        (w?.areas.any((a) => '${a.name} ${a.comment}'.contains('컬로스')) ??
            false)) {
      return 'Erina · Keolloseu';
    }
    if (id == '0') return 'D-Water · frontera';
    if (id.startsWith('select')) {
      return 'Escenario de selección ${id.endsWith('a') ? 'de la Luz' : 'de la Furia'}';
    }
    return '${w?.terrain.size == 0 ? 'Mazmorra' : 'Región'} $id';
  }

  String areaTitle(WorldArea area, int index) {
    final value = area.comment.isNotEmpty ? area.comment : area.name;
    const known = {
      '컬로스': 'Keolloseu',
      '아풀룬': 'Apulune',
      '클로론': 'Cloron',
      '판도라': 'Pando',
      '아르보르': 'Arbar',
      '콘웰': 'Cornwell',
      '이리스': 'Iris',
      '왕성': 'Palacio',
      '광장': 'Plaza',
      '항구': 'Puerto',
      '농장': 'Granja',
      '포탈': 'Portal',
      '길드': 'Gremio',
    };
    final labels = known.entries
        .where((e) => value.contains(e.key))
        .map((e) => e.value)
        .toList();
    if (labels.isNotEmpty) return '${labels.join(' · ')} · ${index + 1}';
    if (value.isNotEmpty &&
        !RegExp(r'[\u3400-\u9fff\uac00-\ud7af\ufffd]|\.tga').hasMatch(value)) {
      return value;
    }
    return 'Punto de interés ${index + 1}';
  }
}

Map<String, List<ItemName>> _itemMetadata(Map<String, Uint8List> input) {
  final rows = DataTable.open(input['data']!, 'DBItemData').integers(),
      names = {
        for (final item in readItemNames(input['text']!, 'DBItemText'))
          item.key: item,
      };
  final output = <String, List<ItemName>>{};
  for (final row in rows) {
    final key = '${row['itemtype']}:${row['itemtypeid']}',
        model = '${row['itemtype']}:${row['image']}';
    final name = names[key];
    if (name != null) output.putIfAbsent(model, () => []).add(name);
  }
  return output;
}

Map<int, List<String>> _monsterMetadata(Map<String, Uint8List> input) {
  final rows = DataTable.open(input['data']!, 'DBMonsterData').integers(),
      names = readMonsterNames(input['text']!, 'DBMonsterText'),
      out = <int, List<String>>{};
  for (final row in rows) {
    final id = row['image'], name = names[row['id']];
    if (id != null && name != null) out.putIfAbsent(id, () => []).add(name);
  }
  return out;
}

List<EffectRecipe> _effects(Uint8List bytes) => readSeff(bytes, 'Weapon.Seff');
WorldResource _world(Map<String, Object> value) {
  final all = WorldResource.parse(
        value['bytes'] as Uint8List,
        value['path'] as String,
      ),
      w = all.terrain;
  // Catalogue metadata must not pin every map's heightfield and scene in RAM.
  final slim = WorldResource(
    WorldData(w.size, Uint16List(0), Uint8List(0), [], [], w.layout),
  );
  slim.areas.addAll(all.areas);
  slim.spawns.addAll(all.spawns);
  slim.portals.addAll(all.portals);
  slim.music.addAll(all.music);
  slim.sky = all.sky;
  slim.cloud = all.cloud;
  slim.secondCloud = all.secondCloud;
  slim.fogColor = all.fogColor;
  slim.fogNear = all.fogNear;
  slim.fogFar = all.fogFar;
  return slim;
}

Map<String, List<ItemRule>> _rules(Uint8List data) {
  final out = <String, List<ItemRule>>{};
  for (final row in DataTable.open(data, 'DBItemData').integers()) {
    final rule = ItemRule.fromRow(row);
    out.putIfAbsent('${rule.type}:${rule.model}', () => []).add(rule);
  }
  return out;
}
