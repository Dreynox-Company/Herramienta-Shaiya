import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../core/game_metadata.dart';
import '../core/equipment_rules.dart';
import '../core/formats.dart';
import '../core/world_resources.dart';
import '../core/motion_catalog.dart';
import 'library.dart';
import '../core/client_locale.dart';

class GameNames {
  final Map<String, List<ItemRule>> itemRules = {};
  final Map<String, List<ItemName>> itemByModel = {};
  final Map<int, List<String>> monsters = {};
  final Map<String, WorldResource> maps = {};
  final List<EffectRecipe> weaponEffects = [];
  final List<String> warnings = [];
  final Map<String, String> localeSources = {};
  final Map<String, SkillName> skills = {}, npcSkills = {};
  final Map<String, Map<int, String>> worldTexts = {};
  final Map<int, String> systemMessages = {}, secondarySystemMessages = {};
  final Map<String, Map<int, List<String>>> localeConflicts = {};
  int itemCount = 0;
  Future<void> load(Library library, void Function(String) progress) async {
    Future<Uint8List?> read(String path) async =>
        library.files.containsKey(path) ? library.read(path) : null;
    try {
      final data = await read('binarysdata/dbitemdata.sdata');
      if (data != null) itemRules.addAll(await compute(_rules, data));
      final titlePath = ClientLocale.tableCandidates(
        library.files.keys,
        'dbitemtext',
        beside: 'binarysdata/dbitemdata.sdata',
      );
      if (data != null && titlePath.isNotEmpty) {
        progress('Relacionando nombres y modelos de equipo…');
        final info = await compute(_itemMetadata, {
          'data': data,
          'text': await library.read(titlePath.first),
          'textPath': titlePath.first,
        });
        localeSources['items'] = titlePath.first;
        itemByModel.addAll(info);
        if (library.files.containsKey('dbitemdata.sdata')) {
          warnings.add(
            'Hay DBItemData en la raíz y en BinarySData. Se utiliza BinarySData con su tabla de nombres de la misma carpeta, sin fusionarlos.',
          );
        }
        itemCount = info.values.fold(0, (n, l) => n + l.length);
      }
    } catch (e) {
      warnings.add('Nombres de equipo: $e');
    }
    try {
      final data = await read('binarysdata/dbmonsterdata.sdata');
      final path = ClientLocale.tableCandidates(
        library.files.keys,
        'dbmonstertext',
        beside: 'binarysdata/dbmonsterdata.sdata',
      ).firstOrNull;
      if (data != null && path != null) {
        localeSources['monsters'] = path;
        monsters.addAll(
          await compute(_monsterMetadata, {
            'data': data,
            'text': await library.read(path),
            'textPath': path,
          }),
        );
      }
    } catch (e) {
      warnings.add('Nombres de criaturas: $e');
    }
    for (final kind in ['skill', 'npcskill']) {
      final path = ClientLocale.tableCandidates(
        library.files.keys,
        'db${kind}text',
        beside: 'binarysdata/db${kind}data.sdata',
      ).firstOrNull;
      if (path == null) continue;
      try {
        final rows = await compute(_skillText, {
          'bytes': await library.read(path),
          'path': path,
        });
        final target = kind == 'skill' ? skills : npcSkills;
        for (final row in rows) {
          if (target.containsKey(row.key)) {
            throw FormatException('Clave de habilidad duplicada: ${row.key}');
          }
          target[row.key] = row;
        }
        localeSources[kind] = path;
      } catch (e) {
        warnings.add('Texto de $kind: $e');
      }
    }
    for (final path in library.files.keys.where(
      (p) => p.startsWith('world/') && p.endsWith('_spn.txt'),
    )) {
      try {
        final key = path.replaceFirst('_spn.txt', '.wld');
        worldTexts[key] = ClientLocale.indexedText(
          await library.read(path),
          path,
        );
        localeSources[key] = path;
      } catch (e) {
        warnings.add('Texto de mapa $path: $e');
      }
    }
    for (final folder in ['systemmessage', 'systemmessage2']) {
      final path = '$folder/spn.txt';
      if (!library.files.containsKey(path)) continue;
      try {
        final catalogue = ClientLocale.indexedCatalogue(
          await library.read(path),
          path,
        );
        (folder == 'systemmessage' ? systemMessages : secondarySystemMessages)
            .addAll(catalogue.resolved);
        localeSources[folder] = path;
        if (catalogue.conflicts.isNotEmpty) {
          localeConflicts[path] = catalogue.conflicts;
          warnings.add(
            '${catalogue.conflicts.length} IDs tienen textos distintos en $path. Se conservan todas las variantes; no se selecciona una arbitrariamente.',
          );
        }
      } catch (e) {
        warnings.add('Mensajes en español $path: $e');
      }
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

  /// Shaiya's live client equips wings in equipment slot 16. DBItemData
  /// ItemType 121 stores the visual MON row in Image; the game client maps
  /// that Image directly to Character/Wing/*.MON record IDs.
  String wingTitle(CreatureRecord record, String fallback) {
    final titles = itemByModel['121:${record.id}'] ?? const <ItemName>[];
    final original = titles
            .where((t) => t.name.isNotEmpty && !t.name.contains('???'))
            .firstOrNull
            ?.name ??
        '';
    return spanishItemName(original, fallback);
  }

  String wingDetail(CreatureRecord record) {
    final names = itemByModel['121:${record.id}'] ?? const <ItemName>[];
    final itemNames = names.map((n) => n.name).where((n) => n.isNotEmpty).toSet();
    final model = record.parts.isEmpty
        ? 'MON #${record.id}'
        : '${record.parts.first.mesh} · ${record.parts.first.texture}';
    return [
      if (itemNames.isNotEmpty) itemNames.take(6).join(' · '),
      'ItemType 121 · Image ${record.id} · slot de equipo 16',
      model,
    ].join('\n');
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

  String areaTitle(WorldArea area, int index, {String? worldPath}) {
    final local = worldPath == null
        ? null
        : worldTexts[ClientLocale.canonicalPath(worldPath)]?[index];
    if (local != null && local.isNotEmpty) return local;
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

Map<String, List<ItemName>> _itemMetadata(Map<String, Object> input) {
  final rows = DataTable.open(
        input['data']! as Uint8List,
        'DBItemData',
      ).integers(),
      names = {
        for (final item in readItemNames(
          input['text']! as Uint8List,
          input['textPath']! as String,
        ))
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

Map<int, List<String>> _monsterMetadata(Map<String, Object> input) {
  final rows = DataTable.open(
        input['data']! as Uint8List,
        'DBMonsterData',
      ).integers(),
      names = readMonsterNames(
        input['text']! as Uint8List,
        input['textPath']! as String,
      ),
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

List<SkillName> _skillText(Map<String, Object> input) =>
    readSkillNames(input['bytes'] as Uint8List, input['path'] as String);
