import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/game/ps0032_protocol.dart';

void _fixed(Uint8List b,int offset,int length,String value){
  final raw=utf8.encode(value),n=raw.length<length?raw.length:length;
  b.setRange(offset,offset+n,raw);
}

void main(){
  test('parses exact 79-byte friend units',(){
    final b=Uint8List(1+79*2),d=ByteData.sublistView(b);
    b[0]=2;
    var o=1;
    d.setUint32(o,1001,Endian.little);b[o+4]=4;b[o+5]=1;_fixed(b,o+6,21,'MageOne');b[o+27]=0;
    o+=79;
    d.setUint32(o,1002,Endian.little);b[o+4]=1;b[o+5]=0;_fixed(b,o+6,21,'TankTwo');b[o+27]=0;
    final list=parseFriendList(PsPacket(PsPacketType.friendList,b));
    expect(list.length,2);
    expect((list[0].id,list[0].job,list[0].online,list[0].name),(1001,4,true,'MageOne'));
    expect((list[1].id,list[1].job,list[1].online,list[1].name),(1002,1,false,'TankTwo'));
  });

  test('parses party list with variable buff records',(){
    final b=Uint8List(2+67+7),d=ByteData.sublistView(b);
    b[0]=0;b[1]=1;
    const o=2;
    d.setUint32(o,555,Endian.little);_fixed(b,o+4,21,'PartyMate');
    d.setUint16(o+25,33,Endian.little);b[o+27]=5;
    d.setInt32(o+28,2000,Endian.little);d.setInt32(o+32,1500,Endian.little);
    d.setInt32(o+36,700,Endian.little);d.setInt32(o+40,600,Endian.little);
    d.setInt32(o+44,900,Endian.little);d.setInt32(o+48,800,Endian.little);
    d.setUint16(o+52,1,Endian.little);
    d.setFloat32(o+54,10.5,Endian.little);d.setFloat32(o+58,20.5,Endian.little);d.setFloat32(o+62,30.5,Endian.little);
    b[o+66]=1;
    const bo=o+67;
    d.setUint16(bo,222,Endian.little);b[bo+2]=3;d.setInt32(bo+3,45,Endian.little);
    final party=PsPartyList.parse(PsPacket(PsPacketType.partyList,b));
    expect(party.leaderIndex,0);
    expect(party.members.length,1);
    final m=party.members.single;
    expect((m.id,m.name,m.level,m.profession),(555,'PartyMate',33,5));
    expect((m.maxHp,m.hp,m.maxSp,m.sp,m.maxMp,m.mp),(2000,1500,700,600,900,800));
    expect(m.buffs.length,1);
    expect((m.buffs.single.skillId,m.buffs.single.skillLevel,m.buffs.single.countdownSeconds),(222,3,45));
  });

  test('parses party current and max vitals',(){
    final b=Uint8List(16),d=ByteData.sublistView(b);
    d.setUint32(0,77,Endian.little);d.setInt32(4,111,Endian.little);d.setInt32(8,222,Endian.little);d.setInt32(12,333,Endian.little);
    final current=PsPartyVitals.parse(PsPacket(PsPacketType.partyMemberHpSpMp,b),maximum:false);
    final maximum=PsPartyVitals.parse(PsPacket(PsPacketType.partyMemberMaxHpSpMp,b),maximum:true);
    expect((current.id,current.hp,current.sp,current.mp),(77,111,222,333));
    expect((maximum.id,maximum.hp,maximum.sp,maximum.mp),(77,111,222,333));
  });

  test('parses party partial value and buff change',(){
    final value=Uint8List(9),d=ByteData.sublistView(value);
    d.setUint32(0,88,Endian.little);value[4]=2;d.setInt32(5,444,Endian.little);
    final v=PsPartySingleValue.parse(PsPacket(PsPacketType.partyCharacterSpMp,value));
    expect((v.id,v.type,v.value),(88,2,444));

    final buff=Uint8List(7),bd=ByteData.sublistView(buff);
    bd.setUint32(0,88,Endian.little);bd.setUint16(4,321,Endian.little);buff[6]=2;
    final change=PsPartyBuffChange.parse(PsPacket(PsPacketType.partyAddedBuff,buff));
    expect((change.id,change.skillId,change.skillLevel),(88,321,2));
  });
}
