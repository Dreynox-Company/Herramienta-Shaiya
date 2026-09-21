import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/game/ps0032_protocol.dart';

void main(){
  test('parsea CHARACTER_DETAILS ps0032 con stats y posicion reales',(){
    final body=Uint8List(58);
    final d=ByteData.sublistView(body);
    var o=0;
    for(final v in [12,13,14,15,16,17,3,4]){
      d.setUint16(o,v,Endian.little);o+=2;
    }
    d.setUint32(16,255,Endian.little);
    d.setUint32(20,95,Endian.little);
    d.setUint32(24,180,Endian.little);
    d.setUint16(28,90,Endian.little);
    d.setUint32(30,1000,Endian.little);
    d.setUint32(34,2000,Endian.little);
    d.setUint32(38,1250,Endian.little);
    d.setUint32(42,777,Endian.little);
    d.setFloat32(46,580.0,Endian.little);
    d.setFloat32(50,78.68,Endian.little);
    d.setFloat32(54,1769.8774,Endian.little);

    final x=PsCharacterDetails.parse(PsPacket(PsPacketType.characterDetails,body));
    expect(x.strength,12);
    expect(x.luck,17);
    expect(x.statPoints,3);
    expect(x.skillPoints,4);
    expect(x.maxHp,255);
    expect(x.maxMp,95);
    expect(x.maxSp,180);
    expect(x.angle,90);
    expect(x.currentExp,1250);
    expect(x.gold,777);
    expect(x.x,closeTo(580,1e-4));
    expect(x.y,closeTo(78.68,1e-3));
    expect(x.z,closeTo(1769.8774,1e-3));
  });

  test('parsea CHARACTER_CURRENT_HITPOINTS reales',(){
    final body=Uint8List(12);
    final d=ByteData.sublistView(body)
      ..setInt32(0,200,Endian.little)
      ..setInt32(4,75,Endian.little)
      ..setInt32(8,150,Endian.little);
    final x=PsCharacterHitpoints.parse(
      PsPacket(PsPacketType.characterCurrentHitpoints,body),
    );
    expect(x.hp,200);
    expect(x.mp,75);
    expect(x.sp,150);
  });

  test('parsea skills buffs y quickbar del bootstrap real',(){
    final skillBody=Uint8List(11);
    final sd=ByteData.sublistView(skillBody)
      ..setUint16(0,7,Endian.little)
      ..setUint16(3,321,Endian.little)
      ..setInt32(7,12,Endian.little);
    skillBody[2]=1;
    skillBody[5]=3;
    skillBody[6]=4;
    final skills=PsCharacterSkills.parse(
      PsPacket(PsPacketType.characterSkills,skillBody),
    );
    expect(skills.skillPoints,7);
    expect(skills.skills.single.skillId,321);
    expect(skills.skills.single.level,3);
    expect(skills.skills.single.number,4);
    expect(skills.skills.single.cooldownSeconds,12);

    final buffBody=Uint8List(12);
    buffBody[0]=1;
    final bd=ByteData.sublistView(buffBody)
      ..setUint32(1,88,Endian.little)
      ..setUint16(5,444,Endian.little)
      ..setInt32(8,30,Endian.little);
    buffBody[7]=2;
    final buffs=parseActiveBuffs(
      PsPacket(PsPacketType.characterActiveBuffs,buffBody),
    );
    expect(buffs.single.id,88);
    expect(buffs.single.skillId,444);
    expect(buffs.single.level,2);
    expect(buffs.single.countdownSeconds,30);

    final barBody=Uint8List(14);
    barBody[0]=1;
    final qd=ByteData.sublistView(barBody);
    barBody[5]=0;
    barBody[6]=3;
    barBody[7]=100;
    qd.setUint16(8,321,Endian.little);
    qd.setInt32(10,0,Endian.little);
    final bar=parseQuickBar(
      PsPacket(PsPacketType.characterSkillBar,barBody),
    );
    expect(bar.single.slot,3);
    expect(bar.single.bag,100);
    expect(bar.single.number,321);
  });

  test('parsea chunks CHARACTER_ITEMS de 102 bytes por objeto',(){
    const record=102;
    final body=Uint8List(1+record)..[0]=1;
    final d=ByteData.sublistView(body);
    final o=1;
    body[o]=2;
    body[o+1]=7;
    body[o+2]=5;
    body[o+3]=44;
    d.setUint16(o+4,1234,Endian.little);
    for(var i=0;i<6;i++)d.setInt32(o+6+i*4,100+i,Endian.little);
    body[o+30]=3;
    final name=latin1.encode('ABCD');
    body.setRange(o+31,o+31+name.length,name);
    body[o+51]=0;
    body[o+75]=1;
    final items=parseInventoryItems(
      PsPacket(PsPacketType.characterItems,body),
    );
    expect(items.length,1);
    final item=items.single;
    expect(item.bag,2);
    expect(item.slot,7);
    expect(item.type,5);
    expect(item.typeId,44);
    expect(item.quality,1234);
    expect(item.gems,[100,101,102,103,104,105]);
    expect(item.count,3);
    expect(item.craftName,'ABCD');
    expect(item.craftDisabled,isFalse);
    expect(item.isDyed,isTrue);
  });
}
