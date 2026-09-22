import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/game/ps0032_protocol.dart';

void main(){
  test('parses server-confirmed equipment change',(){
    final b=Uint8List(13),d=ByteData.sublistView(b);
    d.setUint32(0,12345,Endian.little);
    b[4]=5;
    b[5]=1;
    b[6]=77;
    b[7]=12;
    b[8]=1;
    b[9]=255;
    b[10]=20;
    b[11]=40;
    b[12]=60;
    final e=PsEquipmentChange.parse(PsPacket(PsPacketType.sendEquipment,b));
    expect(e.characterId,12345);
    expect(e.slot,5);
    expect(e.type,1);
    expect(e.typeId,77);
    expect(e.enchant,12);
    expect(e.hasColor,isTrue);
    expect((e.alpha,e.r,e.g,e.b),(255,20,40,60));
  });

  test('parses used-item inventory echo',(){
    final b=Uint8List(9),d=ByteData.sublistView(b);
    d.setUint32(0,222,Endian.little);
    b[4]=2;
    b[5]=7;
    b[6]=25;
    b[7]=9;
    b[8]=3;
    final u=PsUsedItem.parse(PsPacket(PsPacketType.useItem,b));
    expect(u.characterId,222);
    expect((u.bag,u.slot,u.type,u.typeId,u.count),(2,7,25,9,3));
  });
}
