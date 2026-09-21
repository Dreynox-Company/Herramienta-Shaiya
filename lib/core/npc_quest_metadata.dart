import 'dart:typed_data';

import '../data/library.dart';
import 'formats.dart';
import 'seed_data.dart';

class NpcDefinition {
  final int type, typeId, model, faction, moveDistance, moveSpeed;
  final List<int> startQuestIds, endQuestIds;
  final String name, welcome;
  const NpcDefinition({
    required this.type,
    required this.typeId,
    required this.model,
    required this.faction,
    required this.moveDistance,
    required this.moveSpeed,
    required this.startQuestIds,
    required this.endQuestIds,
    this.name = '',
    this.welcome = '',
  });

  String get key => '$type:$typeId';

  NpcDefinition translated(String nextName, String nextWelcome) => NpcDefinition(
    type: type,
    typeId: typeId,
    model: model,
    faction: faction,
    moveDistance: moveDistance,
    moveSpeed: moveSpeed,
    startQuestIds: startQuestIds,
    endQuestIds: endQuestIds,
    name: nextName,
    welcome: nextWelcome,
  );
}

class QuestDefinition {
  final int id, minLevel, maxLevel, faction, mode;
  final int startNpcType, startNpcId, endNpcType, endNpcId;
  final int requiredMobId1, requiredMobCount1, requiredMobId2, requiredMobCount2;
  final int resultType, resultUserSelect;
  final String name, summary, initialDescription, welcome, reminder, alternateResponse;
  const QuestDefinition({
    required this.id,
    required this.minLevel,
    required this.maxLevel,
    required this.faction,
    required this.mode,
    required this.startNpcType,
    required this.startNpcId,
    required this.endNpcType,
    required this.endNpcId,
    required this.requiredMobId1,
    required this.requiredMobCount1,
    required this.requiredMobId2,
    required this.requiredMobCount2,
    required this.resultType,
    required this.resultUserSelect,
    this.name = '',
    this.summary = '',
    this.initialDescription = '',
    this.welcome = '',
    this.reminder = '',
    this.alternateResponse = '',
  });

  QuestDefinition translated(List<String> text) => QuestDefinition(
    id: id,
    minLevel: minLevel,
    maxLevel: maxLevel,
    faction: faction,
    mode: mode,
    startNpcType: startNpcType,
    startNpcId: startNpcId,
    endNpcType: endNpcType,
    endNpcId: endNpcId,
    requiredMobId1: requiredMobId1,
    requiredMobCount1: requiredMobCount1,
    requiredMobId2: requiredMobId2,
    requiredMobCount2: requiredMobCount2,
    resultType: resultType,
    resultUserSelect: resultUserSelect,
    name: text.isNotEmpty ? text[0] : '',
    summary: text.length > 1 ? text[1] : '',
    initialDescription: text.length > 8 ? text[8] : '',
    welcome: text.length > 9 ? text[9] : '',
    reminder: text.length > 10 ? text[10] : '',
    alternateResponse: text.length > 11 ? text[11] : '',
  );
}

class NpcQuestDatabase {
  final Map<String, NpcDefinition> npcs;
  final Map<int, QuestDefinition> quests;
  final String source, translationSource;
  const NpcQuestDatabase(this.npcs, this.quests, this.source, this.translationSource);

  NpcDefinition? npc(int type, int typeId) => npcs['$type:$typeId'];
  QuestDefinition? quest(int id) => quests[id];

  static Future<NpcQuestDatabase?> load(Library library) async {
    final base = library.resolve('npcquest.sdata', ['npc'], uniqueFallback: true);
    if (base == null) return null;
    final translations = library.files.keys
        .where((p) => p.startsWith('npc/npcquesttrans_') && p.endsWith('.sdata'))
        .toList()
      ..sort((a, b) {
        int rank(String p) {
          if (p.contains('spain')) return 0;
          if (p.contains('usa')) return 1;
          return 2;
        }
        final r = rank(a).compareTo(rank(b));
        return r != 0 ? r : a.compareTo(b);
      });
    final parser = _NpcQuestParser(SeedData.decode(await library.read(base)), base);
    final raw = parser.read();
    if (translations.isEmpty) return NpcQuestDatabase(raw.$1, raw.$2, base, '');
    final path = translations.first;
    try {
      final trans = _NpcQuestTranslationParser(
        SeedData.decode(await library.read(path)),
        path,
      ).read();
      final translatedNpcs = <String, NpcDefinition>{...raw.$1};
      for (final e in trans.$1.entries) {
        final current = translatedNpcs[e.key];
        if (current != null) {
          translatedNpcs[e.key] = current.translated(e.value.$1, e.value.$2);
        }
      }
      final translatedQuests = <int, QuestDefinition>{...raw.$2};
      final ids = translatedQuests.keys.toList()..sort();
      for (var i = 0; i < ids.length && i < trans.$2.length; i++) {
        translatedQuests[ids[i]] = translatedQuests[ids[i]]!.translated(trans.$2[i]);
      }
      return NpcQuestDatabase(translatedNpcs, translatedQuests, base, path);
    } catch (_) {
      return NpcQuestDatabase(raw.$1, raw.$2, base, path);
    }
  }
}

int _i16(Bin r) {
  final value = r.u16();
  return value >= 0x8000 ? value - 0x10000 : value;
}

class _NpcQuestParser {
  final Bin r;
  _NpcQuestParser(Uint8List bytes, String source) : r = Bin(bytes, source);

  (Map<String, NpcDefinition>, Map<int, QuestDefinition>) read() {
    final byCategory = <List<NpcDefinition>>[];
    for (var category = 1; category <= 13; category++) {
      final count = r.count(100000);
      final rows = <NpcDefinition>[];
      for (var i = 0; i < count; i++) {
        rows.add(_npc(category));
      }
      byCategory.add(rows);
    }
    // EP8 NpcQuest stores a 256 x 256 item-to-quest lookup table.
    for (var i = 0; i < 65536; i++) {
      final before = r.count(10000);
      r.skip(before * 2);
      final after = r.count(10000);
      r.skip(after * 2);
    }
    final questCount = r.count(100000);
    final quests = <int, QuestDefinition>{};
    for (var i = 0; i < questCount; i++) {
      final q = _quest();
      quests[q.id] = q;
    }
    final npcs = <String, NpcDefinition>{};
    for (final rows in byCategory) {
      for (final n in rows) {
        npcs[n.key] = n;
      }
    }
    return (npcs, quests);
  }

  NpcDefinition _npc(int expectedCategory) {
    final type = r.u8(), typeId = _i16(r);
    if (type != expectedCategory) {
      r.fail('Categoría NPC inesperada: $type, esperaba $expectedCategory.');
    }
    if (type == 1) r.u8(); // MerchantType.
    final model = r.i32(),
        moveDistance = r.i32(),
        moveSpeed = r.i32(),
        faction = r.i32();
    if (type == 1) {
      final items = r.count(10000);
      r.skip(items * 2);
    } else if (type == 2) {
      // Exactly three gate targets in EP8.
      for (var i = 0; i < 3; i++) {
        r.u16();
        r.vec();
        r.u32();
      }
    }
    final startCount = r.count(10000),
        start = List.generate(startCount, (_) => _i16(r)),
        endCount = r.count(10000),
        end = List.generate(endCount, (_) => _i16(r));
    return NpcDefinition(
      type: type,
      typeId: typeId,
      model: model,
      faction: faction,
      moveDistance: moveDistance,
      moveSpeed: moveSpeed,
      startQuestIds: start,
      endQuestIds: end,
    );
  }

  QuestDefinition _quest() {
    final id = r.u16(),
        minLevel = r.u16(),
        maxLevel = r.u16(),
        faction = r.u8(),
        mode = r.u8();
    r.skip(2); // Male/Female bool.
    r.skip(6); // Six jobs.
    r.u16(); // HG
    _i16(r); // VG
    r.skip(3); // CG / OG / IG
    r.u16(); // Previous quest.
    r.u8(); // Require party.
    r.skip(6); // Party job requirements.
    r.skip(20); // Five uint timing values.
    r.u8(); // StartType
    final startNpcType = r.u8(), startNpcId = r.u16();
    r.skip(2); // Start item type/id.
    r.skip(9); // Three QuestItem entries.
    r.u8(); // EndType
    final endNpcType = r.u8(), endNpcId = _i16(r);
    r.skip(9); // Three farm QuestItem entries.
    r.u8(); // PvP kill count
    final mob1 = r.u16(), mobCount1 = r.u8(), mob2 = r.u16(), mobCount2 = r.u8(),
        resultType = r.u8(), resultUserSelect = r.u8();
    // EP8 always has six QuestResult entries. Each record is 33 bytes.
    r.skip(6 * 33);
    return QuestDefinition(
      id: id,
      minLevel: minLevel,
      maxLevel: maxLevel,
      faction: faction,
      mode: mode,
      startNpcType: startNpcType,
      startNpcId: startNpcId,
      endNpcType: endNpcType,
      endNpcId: endNpcId,
      requiredMobId1: mob1,
      requiredMobCount1: mobCount1,
      requiredMobId2: mob2,
      requiredMobCount2: mobCount2,
      resultType: resultType,
      resultUserSelect: resultUserSelect,
    );
  }
}

class _NpcQuestTranslationParser {
  final Bin r;
  _NpcQuestTranslationParser(Uint8List bytes, String source) : r = Bin(bytes, source);

  (Map<String, (String, String)>, List<List<String>>) read() {
    final names = <String, (String, String)>{};
    for (var category = 1; category <= 13; category++) {
      final count = r.count(100000);
      for (var i = 0; i < count; i++) {
        final name = r.str(), welcome = r.str();
        if (category == 2) {
          r.str();
          r.str();
          r.str();
        }
        names['$category:$i'] = (name, welcome);
      }
    }
    final count = r.count(100000), quests = <List<String>>[];
    for (var i = 0; i < count; i++) {
      quests.add(List.generate(12, (_) => r.str()));
    }
    return (names, quests);
  }
}
