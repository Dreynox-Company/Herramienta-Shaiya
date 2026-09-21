import 'dart:convert';
import 'dart:io';

import 'package:herramienta_shaiya/game/ps0032_protocol.dart';

String hexType(int type)=>'0x${type.toRadixString(16).padLeft(4,'0')}';

Future<void> main() async {
  final password=Platform.environment['SHAIYA_OFFLINE_PASSWORD'];
  if(password==null||password.isEmpty){
    stderr.writeln('SHAIYA_OFFLINE_PASSWORD missing');
    exitCode=2;
    return;
  }

  final trace=<String>[];
  final client=Ps0032Client(trace:(s){trace.add(s);stdout.writeln(s);});
  final login=await client.loginOffline(password);
  final world=await client.openWorld(login);

  try{
    var slots=world.characters;
    var character=slots.where((s)=>s.exists).firstOrNull;
    if(character==null){
      stdout.writeln('Creating FlutterLocal through 0x0102...');
      slots=await world.createCharacter(
        slot:0,race:0,mode:2,hair:0,face:0,height:2,
        profession:0,gender:0,name:'FlutterLocal',
      );
      character=slots.where((s)=>s.exists).firstOrNull;
    }
    if(character==null)throw StateError('No character exists after CREATE_CHARACTER.');

    stdout.writeln('Selecting char id=${character.id} map=${character.mapId}');
    final selected=await world.selectCharacter(character.id);
    stdout.writeln(
      'Details x=${selected.details.x} y=${selected.details.y} z=${selected.details.z} angle=${selected.details.angle}'
    );
    final hpPacket=selected.packets.where((p)=>p.type==PsPacketType.characterCurrentHitpoints).firstOrNull;
    final currentHp=hpPacket==null?null:PsHitpoints.parse(hpPacket);
    final skillsPacket=selected.packets.where((p)=>p.type==PsPacketType.characterSkills).firstOrNull;
    final barPacket=selected.packets.where((p)=>p.type==PsPacketType.characterSkillBar).firstOrNull;
    final skillBook=skillsPacket==null?null:PsSkillBook.parse(skillsPacket);
    final quickbar=barPacket==null?null:PsSkillBar.parse(barPacket);
    stdout.writeln(
      'Vitals hp=${currentHp?.hp}/${selected.details.maxHp} '
      'mp=${currentHp?.mp}/${selected.details.maxMp} '
      'sp=${currentHp?.sp}/${selected.details.maxSp} '
      'exp=${selected.details.currentExp}/${selected.details.endExp}'
    );

    final entered=await world.enterMap(collect:const Duration(seconds:8));
    final all=<PsPacket>[...selected.packets,...entered];
    final snapshot=PsWorldSnapshot.fromPackets(all);
    int count(int type)=>all.where((p)=>p.type==type).length;

    if(snapshot.self==null)throw StateError('No CHARACTER_ENTERED_MAP snapshot.');
    final moveX=snapshot.self!.x+.25;
    final moveY=snapshot.self!.y;
    final moveZ=snapshot.self!.z;
    await world.moveCharacter(x:moveX,y:moveY,z:moveZ,yawRadians:0,run:false);
    stdout.writeln('Movement 0x0501 -> x='+moveX.toString()+' y='+moveY.toString()+' z='+moveZ.toString());

    final tutorialNpc=snapshot.npcs.where((n)=>n.type==7&&n.typeId==1167).firstOrNull;
    var questStartOk=false;
    if(tutorialNpc!=null&&!snapshot.quests.any((q)=>q.questId==3781)&&!snapshot.finishedQuests.any((q)=>q.questId==3781)){
      await world.startQuest(tutorialNpc.globalId,3781);
      questStartOk=true;
      stdout.writeln('QUEST_START 3781 confirmed by World via NPC globalId='+tutorialNpc.globalId.toString());
      await world.quitQuest(3781);
    }

    final result={
      'ok':true,
      'userId':login.userId,
      'worldId':login.worldId,
      'sessionBytes':login.sessionId.length,
      'keyBytes':login.key.length,
      'ivBytes':login.iv.length,
      'faction':world.faction,
      'maxMode':world.maxMode,
      'characterId':character.id,
      'characterMap':character.mapId,
      'characterLevel':character.level,
      'characterMode':character.mode,
      'details':{
        'x':selected.details.x,'y':selected.details.y,'z':selected.details.z,'angle':selected.details.angle,
        'maxHp':selected.details.maxHp,'maxMp':selected.details.maxMp,'maxSp':selected.details.maxSp,
        'currentExp':selected.details.currentExp,'startExp':selected.details.startExp,'endExp':selected.details.endExp,
        'gold':selected.details.gold,'statPoint':selected.details.statPoint,'skillPoint':selected.details.skillPoint,
      },
      'hitpoints':currentHp==null?null:{
        'hp':currentHp.hp,'mp':currentHp.mp,'sp':currentHp.sp,
      },
      'selectedPacketTypes':selected.packets.map((p)=>hexType(p.type)).toList(),
      'enteredPacketTypes':entered.map((p)=>hexType(p.type)).toList(),
      'npcPackets':count(PsPacketType.mapNpcEnter),
      'mobPackets':count(PsPacketType.mobEnter),
      'questListPackets':count(PsPacketType.questList),
      'questFinishedPackets':count(PsPacketType.questFinishedList),
      'enteredMapPackets':count(PsPacketType.characterEnteredMap),
      'movement':{'sent':true,'x':moveX,'y':moveY,'z':moveZ},
      'tutorialQuest':{
        'id':3781,'npcFound':tutorialNpc!=null,
        'npcGlobalId':tutorialNpc?.globalId,'startConfirmed':questStartOk,
      },
      'snapshot':{
        'self':snapshot.self==null?null:{
          'id':snapshot.self!.characterId,
          'x':snapshot.self!.x,'y':snapshot.self!.y,'z':snapshot.self!.z,
          'angle':snapshot.self!.angle,
        },
        'npcCount':snapshot.npcs.length,
        'mobCount':snapshot.mobs.length,
        'openQuests':snapshot.quests.map((q)=>q.questId).toList(),
        'finishedQuests':snapshot.finishedQuests.map((q)=>q.questId).toList(),
        'firstNpc':snapshot.npcs.isEmpty?null:{
          'globalId':snapshot.npcs.first.globalId,
          'type':snapshot.npcs.first.type,
          'typeId':snapshot.npcs.first.typeId,
          'x':snapshot.npcs.first.x,'y':snapshot.npcs.first.y,'z':snapshot.npcs.first.z,
        },
        'firstMob':snapshot.mobs.isEmpty?null:{
          'globalId':snapshot.mobs.first.globalId,
          'mobId':snapshot.mobs.first.mobId,
          'x':snapshot.mobs.first.x,'z':snapshot.mobs.first.z,
        },
      },
      'trace':trace,
    };

    final out=Platform.environment['SHAIYA_PROTOCOL_REPORT'];
    final json=const JsonEncoder.withIndent('  ').convert(result);
    stdout.writeln(json);
    if(out!=null&&out.isNotEmpty)await File(out).writeAsString(json);

    if(count(PsPacketType.characterDetails)==0)throw StateError('CHARACTER_DETAILS missing.');
    if(selected.details.maxHp<=0||selected.details.maxMp<=0||selected.details.maxSp<=0){
      throw StateError('CHARACTER_DETAILS max hitpoints invalid.');
    }
    if(currentHp==null)throw StateError('CHARACTER_CURRENT_HITPOINTS missing.');
    if(currentHp.hp<=0||currentHp.mp<0||currentHp.sp<0)throw StateError('Current hitpoints invalid.');
    if(skillBook==null)throw StateError('CHARACTER_SKILLS missing.');
    if(quickbar==null)throw StateError('CHARACTER_SKILL_BAR missing.');
    if(snapshot.self!.characterId!=character.id)throw StateError('Entered-map character id mismatch.');
    if(snapshot.npcs.isEmpty)throw StateError('No parsed MAP_NPC_ENTER actors.');
    if(snapshot.mobs.isEmpty)throw StateError('No parsed MOB_ENTER actors.');
    if(tutorialNpc==null)throw StateError('Tutorial NPC 7:1167 is not present near map-1 spawn.');
    if(!questStartOk)throw StateError('Tutorial QUEST_START 3781 was not confirmed.');
  }finally{
    await world.close();
  }
}
