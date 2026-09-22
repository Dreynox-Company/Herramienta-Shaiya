using System.Text.Json;
using Parsec;
using Parsec.Common;
using Parsec.Shaiya.NpcQuest;
using Parsec.Shaiya.Monster;
using Parsec.Shaiya.Item;
using Parsec.Shaiya.Skill;

if (args.Length != 2)
    throw new ArgumentException("usage: metadata_exporter <NpcQuest.SData> <out.json>");

var parsed = Reader.ReadFromFile<NpcQuest>(args[0], Episode.EP8);
var monsterPath = Path.Combine(Path.GetDirectoryName(Path.GetFullPath(args[0]))!, "DBMonsterData.SData");
var monsterData = File.Exists(monsterPath)
    ? Reader.ReadFromFile<DBMonsterData>(monsterPath, Episode.EP8)
    : null;
var itemPath = Path.Combine(Path.GetDirectoryName(Path.GetFullPath(args[0]))!, "DBItemData.SData");
var itemData = File.Exists(itemPath)
    ? Reader.ReadFromFile<DBItemData>(itemPath, Episode.EP8)
    : null;
var skillPath = Path.Combine(Path.GetDirectoryName(Path.GetFullPath(args[0]))!, "DBSkillData.SData");
var skillData = File.Exists(skillPath)
    ? Reader.ReadFromFile<DBSkillData>(skillPath, Episode.EP8)
    : null;

var npc = new List<object>();
void Add(int type, IEnumerable<BaseNpc> rows)
{
    foreach (var n in rows)
        npc.Add(new {
            type,
            typeId = (int)n.TypeId,
            model = n.Model,
            moveDistance = n.MoveDistance,
            moveSpeed = n.MoveSpeed,
            faction = (int)n.Faction,
            inQuests = n.InQuestIds.Select(x => (int)x).ToArray(),
            outQuests = n.OutQuestIds.Select(x => (int)x).ToArray(),
        });
}

Add(1, parsed.Merchants);
Add(2, parsed.Gatekeepers);
Add(3, parsed.Blacksmiths);
Add(4, parsed.PvpManagers);
Add(5, parsed.GamblingHouses);
Add(6, parsed.Warehouses);
Add(7, parsed.NormalNpcs);
Add(8, parsed.Guards);
Add(9, parsed.Animals);
Add(10, parsed.Apprentices);
Add(11, parsed.GuildMasters);
Add(12, parsed.DeadNpcs);
Add(13, parsed.CombatCommanders);

var shops = parsed.Merchants.Select(m => new {
    type = 1,
    typeId = (int)m.TypeId,
    merchantType = (int)m.MerchantType,
    products = m.SaleItems.Select((item,index) => new {
        index,
        type = (int)item.Type,
        id = (int)item.TypeId,
    }).ToArray(),
}).ToArray();

var gates = parsed.Gatekeepers.Select(g => new {
    type = 2,
    typeId = (int)g.TypeId,
    targets = g.GateTargets.Select((gate,index) => new {
        index,
        mapId = (int)gate.MapId,
        x = gate.Position.X,
        y = gate.Position.Y,
        z = gate.Position.Z,
        cost = gate.Cost,
    }).ToArray(),
}).ToArray();

var quests = parsed.Quests.Select(q => new {
    id = (int)q.Id,
    minLevel = (int)q.MinLevel,
    maxLevel = (int)q.MaxLevel,
    faction = (int)q.Faction,
    mode = (int)q.Mode,
    male = q.MaleSex,
    female = q.FemaleSex,
    jobs = new[]{q.Fighter,q.Defender,q.Ranger,q.Archer,q.Mage,q.Priest},
    previousQuestId = (int)q.PreviousQuestId,
    requireParty = q.RequireParty,
    startType = (int)q.StartType,
    startNpcType = (int)q.StartNpcType,
    startNpcId = (int)q.StartNpcId,
    startItemType = (int)q.StartItemType,
    startItemId = (int)q.StartItemId,
    endType = (int)q.EndType,
    endNpcType = (int)q.EndNpcType,
    endNpcId = (int)q.EndNpcId,
    pvpKillCount = (int)q.PvpKillCount,
    requiredMobId1 = (int)q.RequiredMobId1,
    requiredMobCount1 = (int)q.RequiredMobCount1,
    requiredMobId2 = (int)q.RequiredMobId2,
    requiredMobCount2 = (int)q.RequiredMobCount2,
    resultType = (int)q.ResultType,
    resultUserSelect = (int)q.ResultUserSelect,
    results = q.Results.Select(x => new {
        needMobId = (int)x.NeedMobId,
        needMobCount = (int)x.NeedMobCount,
        needItemId = (int)x.NeedItemId,
        needItemCount = (int)x.NeedItemCount,
        needTime = x.NeedTime,
        exp = x.Exp,
        money = x.Money,
        item1 = new { type=(int)x.ItemType1,id=(int)x.ItemTypeId1,count=(int)x.ItemCount1 },
        item2 = new { type=(int)x.ItemType2,id=(int)x.ItemTypeId2,count=(int)x.ItemCount2 },
        item3 = new { type=(int)x.ItemType3,id=(int)x.ItemTypeId3,count=(int)x.ItemCount3 },
        nextQuestId = (int)x.NextQuest,
    }).ToArray(),
});

var mobs = monsterData?.Records.Select(m => new {
    id = (int)m.Id,
    image = (int)m.Image,
    level = (int)m.Level,
    size = m.Size,
    hp = m.Hp,
    ai = (int)m.Ai,
}).ToArray() ?? Array.Empty<object>();

var items = itemData?.Records.Select(i => new {
    type = (int)i.ItemType,
    id = (int)i.ItemTypeId,
    image = (int)i.Image,
    icon = (int)i.Icon,
    level = (int)i.Level,
    quality = (int)i.Quality,
    slot = (int)i.Slot,
    count = (int)i.Count,
    duration = (int)i.Duration,
    grade = (int)i.Grade,
    buy = i.Buy,
    sell = i.Sell,
}).ToArray() ?? Array.Empty<object>();

var skills = skillData?.Records.Select(s => new {
    id = (int)s.Id,
    level = (int)s.SkillLevel,
    image = (int)s.Image,
    animation = (int)s.Ani,
    effect = (int)s.Effect,
    sound = (int)s.Sound,
    requiredLevel = (int)s.Level,
    country = (int)s.Country,
    grow = (int)s.Grow,
    point = (int)s.Point,
    previousSkill = (int)s.PrevSkill,
    typeShow = (int)s.TypeShow,
    fighter = (int)s.AttackFighter,
    defender = (int)s.DefenseFighter,
    ranger = (int)s.PatrolRogue,
    archer = (int)s.ShootRogue,
    mage = (int)s.AttackMage,
    priest = (int)s.DefenseMage,
    sp = (int)s.SP,
    mp = (int)s.MP,
    castTime = (int)s.ReadyTime,
    cooldown = (int)s.ResetTime,
    attackRange = (int)s.AttackRange,
    targetType = (int)s.TargetType,
    applyRange = (int)s.ApplyRange,
    typeAttack = (int)s.TypeAttack,
    typeEffect = (int)s.TypeEffect,
}).ToArray() ?? Array.Empty<object>();

var doc = new {
    schema = 2,
    source = "NpcQuest.SData + DBMonsterData.SData parsed with backend Parsec EP8",
    npcCount = npc.Count,
    questCount = parsed.Quests.Count,
    mobCount = mobs.Length,
    itemCount = items.Length,
    skillCount = skills.Length,
    shopCount = shops.Length,
    gatekeeperCount = gates.Length,
    npcs = npc,
    quests,
    mobs,
    items,
    skills,
    shops,
    gates,
};

var json = JsonSerializer.Serialize(doc,new JsonSerializerOptions{WriteIndented=false});
Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(args[1]))!);
File.WriteAllText(args[1],json);
Console.WriteLine("NPC="+npc.Count+" Quests="+parsed.Quests.Count+" Mobs="+mobs.Length+" Items="+items.Length+" Skills="+skills.Length+" Shops="+shops.Length+" Gates="+gates.Length+" -> "+args[1]);
