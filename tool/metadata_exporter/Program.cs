using System.Text.Json;
using Parsec;
using Parsec.Common;
using Parsec.Shaiya.NpcQuest;

if (args.Length != 2) throw new ArgumentException("usage: metadata_exporter <NpcQuest.SData> <out.json>");
Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
var parsed = ParsecReader.FromFile<NpcQuest>(args[0], Episode.EP8);

var npc = new List<object>();
void Add(int type, IEnumerable<NpcQuestBaseNpc> rows)
{
    foreach (var n in rows)
        npc.Add(new {
            type,
            typeId = n.NpcTypeId,
            model = n.Model,
            moveDistance = n.MoveDistance,
            moveSpeed = n.MoveSpeed,
            faction = (int)n.Faction,
            inQuests = n.InQuestIds,
            outQuests = n.OutQuestIds,
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

var quests = parsed.Quests.Select(q => new {
    id=q.Id, minLevel=q.MinLevel, maxLevel=q.MaxLevel, faction=(int)q.Faction, mode=(int)q.Mode,
    male=q.MaleSex, female=q.FemaleSex,
    jobs=new[]{q.Fighter,q.Defender,q.Ranger,q.Archer,q.Mage,q.Priest},
    previousQuestId=q.PreviousQuestId, requireParty=q.RequireParty,
    startType=q.StartType, startNpcType=q.StartNpcType, startNpcId=q.StartNpcId,
    startItemType=q.StartItemType, startItemId=q.StartItemId,
    requiredItems=q.RequiredItems.Select(x=>new{type=x.Type,id=x.TypeId,count=x.Count}),
    endType=q.EndType, endNpcType=q.EndNpcType, endNpcId=q.EndNpcId,
    farmItems=q.FarmItems.Select(x=>new{type=x.Type,id=x.TypeId,count=x.Count}),
    pvpKillCount=q.PvpKillCount,
    requiredMobId1=q.RequiredMobId1, requiredMobCount1=q.RequiredMobCount1,
    requiredMobId2=q.RequiredMobId2, requiredMobCount2=q.RequiredMobCount2,
    resultType=q.ResultType, resultUserSelect=q.ResultUserSelect,
    results=q.Results.Select(x=>new{
        needMobId=x.NeedMobId,needMobCount=x.NeedMobCount,needItemId=x.NeedItemId,needItemCount=x.NeedItemCount,
        needTime=x.NeedTime,exp=x.Exp,money=x.Money,
        item1=new{type=x.ItemType1,id=x.ItemTypeId1,count=x.ItemCount1},
        item2=new{type=x.ItemType2,id=x.ItemTypeId2,count=x.ItemCount2},
        item3=new{type=x.ItemType3,id=x.ItemTypeId3,count=x.ItemCount3},
        nextQuestId=x.NextQuestId
    })
});

var doc = new {
    schema=1,
    source="NpcQuest.SData parsed with Parsec EP8",
    npcCount=npc.Count,
    questCount=parsed.Quests.Count,
    npcs=npc,
    quests
};
var json=JsonSerializer.Serialize(doc,new JsonSerializerOptions{WriteIndented=false});
Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(args[1]))!);
File.WriteAllText(args[1],json);
Console.WriteLine($"NPC={npc.Count} Quests={parsed.Quests.Count} -> {args[1]}");
