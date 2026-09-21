import 'dart:convert';
import 'dart:io';

class NpcRule {
  final int type,typeId,model,faction,moveDistance,moveSpeed;
  final List<int> inQuests,outQuests;
  const NpcRule({
    required this.type,
    required this.typeId,
    required this.model,
    required this.faction,
    required this.moveDistance,
    required this.moveSpeed,
    required this.inQuests,
    required this.outQuests,
  });

  String get key=>type.toString()+':'+typeId.toString();

  factory NpcRule.fromJson(Map<String,dynamic> j)=>NpcRule(
    type:j['type'] as int,
    typeId:j['typeId'] as int,
    model:j['model'] as int,
    faction:j['faction'] as int,
    moveDistance:j['moveDistance'] as int,
    moveSpeed:j['moveSpeed'] as int,
    inQuests:(j['inQuests'] as List? ?? const []).map((x)=>(x as num).toInt()).toList(),
    outQuests:(j['outQuests'] as List? ?? const []).map((x)=>(x as num).toInt()).toList(),
  );
}

class MobRule {
  final int id,image,level,ai;
  final int hp;
  final double size;
  const MobRule({required this.id,required this.image,required this.level,required this.ai,required this.hp,required this.size});
  factory MobRule.fromJson(Map<String,dynamic> j)=>MobRule(
    id:(j['id'] as num).toInt(),
    image:(j['image'] as num).toInt(),
    level:(j['level'] as num).toInt(),
    ai:(j['ai'] as num).toInt(),
    hp:(j['hp'] as num).toInt(),
    size:(j['size'] as num).toDouble(),
  );
}

class QuestRule {
  final int id,minLevel,maxLevel,startNpcType,startNpcId,endNpcType,endNpcId;
  final int requiredMobId1,requiredMobCount1,requiredMobId2,requiredMobCount2;
  const QuestRule({
    required this.id,
    required this.minLevel,
    required this.maxLevel,
    required this.startNpcType,
    required this.startNpcId,
    required this.endNpcType,
    required this.endNpcId,
    required this.requiredMobId1,
    required this.requiredMobCount1,
    required this.requiredMobId2,
    required this.requiredMobCount2,
  });

  factory QuestRule.fromJson(Map<String,dynamic> j)=>QuestRule(
    id:(j['id'] as num).toInt(),
    minLevel:(j['minLevel'] as num).toInt(),
    maxLevel:(j['maxLevel'] as num).toInt(),
    startNpcType:(j['startNpcType'] as num).toInt(),
    startNpcId:(j['startNpcId'] as num).toInt(),
    endNpcType:(j['endNpcType'] as num).toInt(),
    endNpcId:(j['endNpcId'] as num).toInt(),
    requiredMobId1:(j['requiredMobId1'] as num).toInt(),
    requiredMobCount1:(j['requiredMobCount1'] as num).toInt(),
    requiredMobId2:(j['requiredMobId2'] as num).toInt(),
    requiredMobCount2:(j['requiredMobCount2'] as num).toInt(),
  );
}

class ServerMetadata {
  final Map<String,NpcRule> npcs;
  final Map<int,QuestRule> quests;
  final Map<int,MobRule> mobs;
  const ServerMetadata(this.npcs,this.quests,this.mobs);

  Map<String,int> get npcModels=>{for(final e in npcs.entries)e.key:e.value.model};
  Map<int,int> get mobModels=>{for(final e in mobs.entries)e.key:e.value.image};

  static Future<ServerMetadata?> load() async {
    final exe=File(Platform.resolvedExecutable).parent.path;
    final candidates=<String>[
      exe+'/server/metadata/npc_quest.json',
      Directory.current.path+'/server/metadata/npc_quest.json',
    ];
    for(final path in candidates){
      final file=File(path);
      if(!await file.exists())continue;
      final raw=jsonDecode(await file.readAsString()) as Map<String,dynamic>;
      final npcList=(raw['npcs'] as List? ?? const [])
        .cast<Map>()
        .map((x)=>NpcRule.fromJson(Map<String,dynamic>.from(x)))
        .toList();
      final questList=(raw['quests'] as List? ?? const [])
        .cast<Map>()
        .map((x)=>QuestRule.fromJson(Map<String,dynamic>.from(x)))
        .toList();
      final mobList=(raw['mobs'] as List? ?? const [])
        .cast<Map>()
        .map((x)=>MobRule.fromJson(Map<String,dynamic>.from(x)))
        .toList();
      return ServerMetadata(
        {for(final n in npcList)n.key:n},
        {for(final q in questList)q.id:q},
        {for(final m in mobList)m.id:m},
      );
    }
    return null;
  }
}
