import 'dart:convert';
import 'dart:io';

import 'package:herramienta_shaiya/game/ps0032_protocol.dart';

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
  final world=await client.bootstrapWorld(login);
  final result={
    'ok':true,
    'userId':login.userId,
    'worldId':login.worldId,
    'sessionBytes':login.sessionId.length,
    'keyBytes':login.key.length,
    'ivBytes':login.iv.length,
    'faction':world.faction,
    'maxMode':world.maxMode,
    'characterListPackets':world.characterListPackets,
    'packetTypes':world.packets.map((p)=>'0x${p.type.toRadixString(16).padLeft(4,'0')}').toList(),
    'trace':trace,
  };
  final out=Platform.environment['SHAIYA_PROTOCOL_REPORT'];
  final json=const JsonEncoder.withIndent('  ').convert(result);
  stdout.writeln(json);
  if(out!=null&&out.isNotEmpty)await File(out).writeAsString(json);
}
