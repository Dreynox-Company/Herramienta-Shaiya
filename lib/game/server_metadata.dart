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

class ItemRule {
  final int type,id,image,icon,level,quality,slot,count,duration,grade;
  final int special,hp,sp,mp,itemSkill,buy,sell;
  const ItemRule({
    required this.type,required this.id,required this.image,required this.icon,
    required this.level,required this.quality,required this.slot,required this.count,
    required this.duration,required this.grade,required this.special,required this.hp,
    required this.sp,required this.mp,required this.itemSkill,required this.buy,required this.sell,
  });
  String get key=>'$type:$id';
  String? get iconPath=>icon<=0?null:'interface/icon/${icon.toString().padLeft(2,'0')}.tga';
  factory ItemRule.fromJson(Map<String,dynamic> j)=>ItemRule(
    type:(j['type'] as num).toInt(),id:(j['id'] as num).toInt(),
    image:(j['image'] as num).toInt(),icon:(j['icon'] as num).toInt(),
    level:(j['level'] as num).toInt(),quality:(j['quality'] as num).toInt(),
    slot:(j['slot'] as num).toInt(),count:(j['count'] as num).toInt(),
    duration:(j['duration'] as num).toInt(),grade:(j['grade'] as num).toInt(),
    special:(j['special'] as num? ?? 0).toInt(),hp:(j['hp'] as num? ?? 0).toInt(),
    sp:(j['sp'] as num? ?? 0).toInt(),mp:(j['mp'] as num? ?? 0).toInt(),
    itemSkill:(j['itemSkill'] as num? ?? 0).toInt(),
    buy:(j['buy'] as num).toInt(),sell:(j['sell'] as num).toInt(),
  );
}

int weaponFamilyForItemType(int type){
  if(type>=1&&type<=15)return type;
  return switch(type){
    45=>1,46=>2,47=>3,48=>4,
    49||50=>5,51||52=>6,53||54=>7,55||56=>8,
    57=>9,58=>10,59=>11,60||61=>12,62||63=>13,64=>14,65=>15,
    _=>0,
  };
}

List<int> equipmentSlotsForItemType(int type){
  if((type>=1&&type<=15)||(type>=45&&type<=65))return const [5];
  if(const {16,31,66,72,81,87}.contains(type))return const [0];
  if(const {17,32,67,73,82,88}.contains(type))return const [1];
  if(const {18,33,68,74,83,89}.contains(type))return const [2];
  if(const {20,35,70,76,85,91}.contains(type))return const [3];
  if(const {21,36,71,77,86,92}.contains(type))return const [4];
  if(const {19,34,69,75,84,90}.contains(type))return const [6];
  if(const {24,39}.contains(type))return const [7];
  if(const {23,96}.contains(type))return const [8];
  if(const {22,37}.contains(type))return const [9,10];
  if(const {40,97}.contains(type))return const [11,12];
  if(type==42)return const [13];
  if(type==120)return const [14];
  if(type==150)return const [15];
  if(type==121)return const [16];
  return const [];
}

class SkillRule {
  final int id,level,image,animation,effect,sound,requiredLevel,country,grow,point,previousSkill,typeShow;
  final int fighter,defender,ranger,archer,mage,priest,sp,mp;
  final int castTime,cooldown,attackRange,targetType,applyRange,typeAttack,typeEffect;
  const SkillRule({
    required this.id,required this.level,required this.image,required this.animation,
    required this.effect,required this.sound,required this.requiredLevel,required this.country,
    required this.grow,required this.point,required this.previousSkill,required this.typeShow,
    required this.fighter,required this.defender,required this.ranger,required this.archer,
    required this.mage,required this.priest,required this.sp,required this.mp,
    required this.castTime,required this.cooldown,required this.attackRange,
    required this.targetType,required this.applyRange,required this.typeAttack,required this.typeEffect,
  });
  String get key=>'$id:$level';
  String? get iconPath=>image<=0?null:'interface/icon/${image.toString().padLeft(2,'0')}.tga';
  bool professionAllowed(int profession){
    final flags=[fighter,defender,ranger,archer,mage,priest];
    return profession>=0&&profession<flags.length&&flags[profession]!=0;
  }
  bool familyAllowed(int race){
    switch(country){
      case 0:return race==0; // Human
      case 1:return race==1; // Elf
      case 2:return race==0||race==1; // Alliance of Light
      case 3:return race==3; // DeathEater
      case 4:return race==2; // Vail
      case 5:return race==2||race==3; // Union of Fury
      case 6:return true; // All factions
      default:return false;
    }
  }
  factory SkillRule.fromJson(Map<String,dynamic> j)=>SkillRule(
    id:(j['id'] as num).toInt(),level:(j['level'] as num).toInt(),
    image:(j['image'] as num).toInt(),animation:(j['animation'] as num).toInt(),
    effect:(j['effect'] as num).toInt(),sound:(j['sound'] as num).toInt(),
    requiredLevel:(j['requiredLevel'] as num).toInt(),
    country:(j['country'] as num? ?? 6).toInt(),grow:(j['grow'] as num? ?? 0).toInt(),
    point:(j['point'] as num? ?? 0).toInt(),previousSkill:(j['previousSkill'] as num? ?? 0).toInt(),
    typeShow:(j['typeShow'] as num? ?? 0).toInt(),
    fighter:(j['fighter'] as num? ?? 1).toInt(),defender:(j['defender'] as num? ?? 1).toInt(),
    ranger:(j['ranger'] as num? ?? 1).toInt(),archer:(j['archer'] as num? ?? 1).toInt(),
    mage:(j['mage'] as num? ?? 1).toInt(),priest:(j['priest'] as num? ?? 1).toInt(),
    sp:(j['sp'] as num).toInt(),mp:(j['mp'] as num).toInt(),
    castTime:(j['castTime'] as num).toInt(),cooldown:(j['cooldown'] as num).toInt(),
    attackRange:(j['attackRange'] as num).toInt(),targetType:(j['targetType'] as num).toInt(),
    applyRange:(j['applyRange'] as num).toInt(),typeAttack:(j['typeAttack'] as num).toInt(),
    typeEffect:(j['typeEffect'] as num).toInt(),
  );
}
class ShopProductRule {
  final int index,type,id;
  const ShopProductRule(this.index,this.type,this.id);
  String get itemKey=>'$type:$id';
  factory ShopProductRule.fromJson(Map<String,dynamic> j)=>ShopProductRule(
    (j['index'] as num).toInt(),
    (j['type'] as num).toInt(),
    (j['id'] as num).toInt(),
  );
}

class NpcShopRule {
  final int type,typeId,merchantType;
  final List<ShopProductRule> products;
  const NpcShopRule(this.type,this.typeId,this.merchantType,this.products);
  String get key=>'$type:$typeId';
  factory NpcShopRule.fromJson(Map<String,dynamic> j)=>NpcShopRule(
    (j['type'] as num).toInt(),
    (j['typeId'] as num).toInt(),
    (j['merchantType'] as num).toInt(),
    List.unmodifiable((j['products'] as List? ?? const [])
      .cast<Map>()
      .map((x)=>ShopProductRule.fromJson(Map<String,dynamic>.from(x)))),
  );
}

class GateTargetRule {
  final int index,mapId,cost;
  final double x,y,z;
  const GateTargetRule(this.index,this.mapId,this.x,this.y,this.z,this.cost);
  factory GateTargetRule.fromJson(Map<String,dynamic> j)=>GateTargetRule(
    (j['index'] as num).toInt(),
    (j['mapId'] as num).toInt(),
    (j['x'] as num).toDouble(),
    (j['y'] as num).toDouble(),
    (j['z'] as num).toDouble(),
    (j['cost'] as num).toInt(),
  );
}

class NpcGateRule {
  final int type,typeId;
  final List<GateTargetRule> targets;
  const NpcGateRule(this.type,this.typeId,this.targets);
  String get key=>'$type:$typeId';
  factory NpcGateRule.fromJson(Map<String,dynamic> j)=>NpcGateRule(
    (j['type'] as num).toInt(),
    (j['typeId'] as num).toInt(),
    List.unmodifiable((j['targets'] as List? ?? const [])
      .cast<Map>()
      .map((x)=>GateTargetRule.fromJson(Map<String,dynamic>.from(x)))),
  );
}

class CharacterCreateRule {
  final int country,job,mapId;
  final double x,y,z;
  const CharacterCreateRule({
    required this.country,required this.job,required this.mapId,
    required this.x,required this.y,required this.z,
  });
  factory CharacterCreateRule.fromJson(Map<String,dynamic> j)=>CharacterCreateRule(
    country:(j['Country'] as num).toInt(),
    job:(j['Job'] as num).toInt(),
    mapId:(j['MapId'] as num).toInt(),
    x:(j['X'] as num).toDouble(),
    y:(j['Y'] as num).toDouble(),
    z:(j['Z'] as num).toDouble(),
  );
  String get key=>country.toString()+':'+job.toString();
}
class QuestRewardItem {
  final int type,id,count;
  const QuestRewardItem(this.type,this.id,this.count);
  String get key=>'$type:$id';
}

class QuestRule {
  final int id,minLevel,maxLevel,startType,startNpcType,startNpcId,endType,endNpcType,endNpcId;
  final int requiredMobId1,requiredMobCount1,requiredMobId2,requiredMobCount2;
  final int resultType,resultUserSelect,xp,money,nextQuestId;
  final List<QuestRewardItem> rewards;
  const QuestRule({
    required this.id,
    required this.minLevel,
    required this.maxLevel,
    required this.startType,
    required this.startNpcType,
    required this.startNpcId,
    required this.endType,
    required this.endNpcType,
    required this.endNpcId,
    required this.requiredMobId1,
    required this.requiredMobCount1,
    required this.requiredMobId2,
    required this.requiredMobCount2,
    required this.resultType,
    required this.resultUserSelect,
    required this.xp,
    required this.money,
    required this.nextQuestId,
    required this.rewards,
  });

  bool get chooseReward=>resultUserSelect>0;

  factory QuestRule.fromJson(Map<String,dynamic> j){
    final rewards=<QuestRewardItem>[];
    var xp=0,money=0,next=0;
    for(final raw in (j['results'] as List? ?? const [])){
      final result=Map<String,dynamic>.from(raw as Map);
      xp+=(result['exp'] as num? ?? 0).toInt();
      money+=(result['money'] as num? ?? 0).toInt();
      final n=(result['nextQuestId'] as num? ?? 0).toInt();
      if(next==0&&n>0)next=n;
      for(final key in const ['item1','item2','item3']){
        final item=Map<String,dynamic>.from(result[key] as Map? ?? const {});
        final type=(item['type'] as num? ?? 0).toInt();
        final id=(item['id'] as num? ?? 0).toInt();
        final count=(item['count'] as num? ?? 0).toInt();
        if(type>0&&id>0&&count>0)rewards.add(QuestRewardItem(type,id,count));
      }
    }
    return QuestRule(
      id:(j['id'] as num).toInt(),
      minLevel:(j['minLevel'] as num).toInt(),
      maxLevel:(j['maxLevel'] as num).toInt(),
      startType:(j['startType'] as num? ?? 0).toInt(),
      startNpcType:(j['startNpcType'] as num).toInt(),
      startNpcId:(j['startNpcId'] as num).toInt(),
      endType:(j['endType'] as num? ?? 0).toInt(),
      endNpcType:(j['endNpcType'] as num).toInt(),
      endNpcId:(j['endNpcId'] as num).toInt(),
      requiredMobId1:(j['requiredMobId1'] as num).toInt(),
      requiredMobCount1:(j['requiredMobCount1'] as num).toInt(),
      requiredMobId2:(j['requiredMobId2'] as num).toInt(),
      requiredMobCount2:(j['requiredMobCount2'] as num).toInt(),
      resultType:(j['resultType'] as num? ?? 0).toInt(),
      resultUserSelect:(j['resultUserSelect'] as num? ?? 0).toInt(),
      xp:xp,money:money,nextQuestId:next,
      rewards:List.unmodifiable(rewards),
    );
  }
}

class ServerMetadata {
  final Map<String,NpcRule> npcs;
  final Map<int,QuestRule> quests;
  final Map<int,MobRule> mobs;
  final Map<String,ItemRule> items;
  final Map<String,SkillRule> skills;
  final Map<String,NpcShopRule> shops;
  final Map<String,NpcGateRule> gates;
  final Map<String,CharacterCreateRule> createRules;
  const ServerMetadata(this.npcs,this.quests,this.mobs,this.items,this.skills,this.shops,this.gates,this.createRules);

  Map<String,int> get npcModels=>{for(final e in npcs.entries)e.key:e.value.model};
  Map<int,int> get mobModels=>{for(final e in mobs.entries)e.key:e.value.image};
  CharacterCreateRule? createRule(int country,int job)=>createRules[country.toString()+':'+job.toString()];
  ItemRule? item(int type,int id)=>items['$type:$id'];
  SkillRule? skill(int id,int level)=>skills['$id:$level']??skills['$id:1'];
  NpcShopRule? shop(int type,int typeId)=>shops['$type:$typeId'];
  NpcGateRule? gatekeeper(int type,int typeId)=>gates['$type:$typeId'];

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
      final itemList=(raw['items'] as List? ?? const [])
        .cast<Map>()
        .map((x)=>ItemRule.fromJson(Map<String,dynamic>.from(x)))
        .toList();
      final skillList=(raw['skills'] as List? ?? const [])
        .cast<Map>()
        .map((x)=>SkillRule.fromJson(Map<String,dynamic>.from(x)))
        .toList();
      final shopList=(raw['shops'] as List? ?? const [])
        .cast<Map>()
        .map((x)=>NpcShopRule.fromJson(Map<String,dynamic>.from(x)))
        .toList();
      final gateList=(raw['gates'] as List? ?? const [])
        .cast<Map>()
        .map((x)=>NpcGateRule.fromJson(Map<String,dynamic>.from(x)))
        .toList();
      final root=File(Platform.resolvedExecutable).parent.path;
      final configCandidates=<String>[
        root+'/server/metadata/character.json',
        root+'/servicios/world/config/character.json',
        Directory.current.path+'/server/metadata/character.json',
        Directory.current.path+'/servicios/world/config/character.json',
      ];
      final createRules=<String,CharacterCreateRule>{};
      for(final configPath in configCandidates){
        final configFile=File(configPath);
        if(!await configFile.exists())continue;
        final character=jsonDecode(await configFile.readAsString()) as Map<String,dynamic>;
        for(final row in (character['CreateConfigs'] as List? ?? const [])){
          final rule=CharacterCreateRule.fromJson(Map<String,dynamic>.from(row as Map));
          createRules[rule.key]=rule;
        }
        break;
      }
      return ServerMetadata(
        {for(final n in npcList)n.key:n},
        {for(final q in questList)q.id:q},
        {for(final m in mobList)m.id:m},
        {for(final i in itemList)i.key:i},
        {for(final s in skillList)s.key:s},
        {for(final s in shopList)s.key:s},
        {for(final g in gateList)g.key:g},
        createRules,
      );
    }
    return null;
  }
}
