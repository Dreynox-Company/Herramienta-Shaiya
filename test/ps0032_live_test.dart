import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/protocol/ps0032_client.dart';
import 'package:herramienta_shaiya/protocol/ps0032_packet.dart';

void main(){
  final oauth=Platform.environment['SHAIYA_PROTOCOL_OAUTH'];

  test(
    'bootstrap real Login -> World 0.1.2',
    () async {
      final session=await const Ps0032Client().connect(oauthKey:oauth!);
      try{
        expect(session.bootstrap.identity.userId,greaterThan(0));
        expect(session.bootstrap.identity.sessionIdBytes.length,16);
        expect(session.bootstrap.worlds,isNotEmpty);
        expect(session.bootstrap.worlds.first.name,isNotEmpty);
        expect(session.bootstrap.initialWorldPackets.any((p)=>p.type==Ps0032Types.gameHandshake),isTrue);
        expect(session.bootstrap.initialWorldPackets.any((p)=>p.type==Ps0032Types.accountFaction),isTrue);
      }finally{
        await session.close();
      }
    },
    skip:oauth==null?'SHAIYA_PROTOCOL_OAUTH no configurado':false,
    timeout:const Timeout(Duration(seconds:40)),
  );
}
