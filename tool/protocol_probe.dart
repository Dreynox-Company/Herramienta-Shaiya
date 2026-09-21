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

    final entered=await world.enterMap(collect:const Duration(seconds:8));
    final all=<PsPacket>[...selected.packets,...entered];
    int count(int type)=>all.where((p)=>p.type==type).length;

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
      },
      'selectedPacketTypes':selected.packets.map((p)=>hexType(p.type)).toList(),
      'enteredPacketTypes':entered.map((p)=>hexType(p.type)).toList(),
      'npcPackets':count(PsPacketType.mapNpcEnter),
      'mobPackets':count(PsPacketType.mobEnter),
      'questListPackets':count(PsPacketType.questList),
      'questFinishedPackets':count(PsPacketType.questFinishedList),
      'enteredMapPackets':count(PsPacketType.characterEnteredMap),
      'trace':trace,
    };

    final out=Platform.environment['SHAIYA_PROTOCOL_REPORT'];
    final json=const JsonEncoder.withIndent('  ').convert(result);
    stdout.writeln(json);
    if(out!=null&&out.isNotEmpty)await File(out).writeAsString(json);

    if(count(PsPacketType.characterDetails)==0)throw StateError('CHARACTER_DETAILS missing.');
    if(count(PsPacketType.mapNpcEnter)==0)throw StateError('No MAP_NPC_ENTER packets after entered-map.');
    if(count(PsPacketType.mobEnter)==0)throw StateError('No MOB_ENTER packets after entered-map.');
  }finally{
    await world.close();
  }
}
