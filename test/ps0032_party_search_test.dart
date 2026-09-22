import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/game/ps0032_protocol.dart';

void main(){
  test('parses party-search registration acknowledgement',(){
    expect(
      PsPartySearchRegistration.parse(
        PsPacket(PsPacketType.partySearchRegistration,Uint8List.fromList([1])),
      ).success,
      isTrue,
    );
    expect(
      PsPartySearchRegistration.parse(
        PsPacket(PsPacketType.partySearchRegistration,Uint8List.fromList([0])),
      ).success,
      isFalse,
    );
  });

  test('parses exact 23-byte party-search units',(){
    final body=Uint8List(1+23*2);
    body[0]=2;
    body[1]=35;body[2]=4;
    final one='DreynoxMage'.codeUnits;body.setRange(3,3+one.length,one);
    final o=24;body[o]=27;body[o+1]=1;
    final two='TankLight'.codeUnits;body.setRange(o+2,o+2+two.length,two);
    final list=parsePartySearchList(PsPacket(PsPacketType.partySearchList,body));
    expect(list.length,2);
    expect((list[0].level,list[0].profession,list[0].name),(35,4,'DreynoxMage'));
    expect((list[1].level,list[1].profession,list[1].name),(27,1,'TankLight'));
  });

  test('party-search list rejects truncation',(){
    final body=Uint8List(23)..[0]=1;
    expect(
      ()=>parsePartySearchList(PsPacket(PsPacketType.partySearchList,body)),
      throwsFormatException,
    );
  });
}
