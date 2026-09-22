import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/game/ps0032_protocol.dart';

void main(){
  test('parses experience level money recovery and max vitals',(){
    final exp=Uint8List(8),ed=ByteData.sublistView(exp);
    ed.setUint32(0,1234,Endian.little);
    ed.setUint32(4,0,Endian.little);
    expect(PsExperienceGain.parse(PsPacket(PsPacketType.experienceGain,exp)).exp,1234);

    final level=Uint8List(18),ld=ByteData.sublistView(level);
    ld.setUint32(0,77,Endian.little);
    ld.setUint16(4,42,Endian.little);
    ld.setUint16(6,5,Endian.little);
    ld.setUint16(8,3,Endian.little);
    ld.setUint32(10,10000,Endian.little);
    ld.setUint32(14,15000,Endian.little);
    final up=PsCharacterLevelUp.parse(PsPacket(PsPacketType.characterLevelUpMyself,level));
    expect((up.characterId,up.level,up.statPoint,up.skillPoint),(77,42,5,3));
    expect((up.minLevelExp,up.nextLevelExp),(10000,15000));

    final recover=Uint8List(16),rd=ByteData.sublistView(recover);
    rd.setUint32(0,77,Endian.little);
    rd.setInt32(4,900,Endian.little);
    rd.setInt32(8,800,Endian.little);
    rd.setInt32(12,700,Endian.little);
    final hp=PsCharacterRecover.parse(PsPacket(PsPacketType.characterRecover,recover));
    expect((hp.hp,hp.mp,hp.sp),(900,800,700));

    final maximum=Uint8List(16),md=ByteData.sublistView(maximum);
    md.setUint32(0,77,Endian.little);
    md.setInt32(4,1900,Endian.little);
    md.setInt32(8,1800,Endian.little);
    md.setInt32(12,1700,Endian.little);
    final max=PsCharacterMaxVitals.parse(PsPacket(PsPacketType.characterMaxHpMpSp,maximum));
    expect((max.maxHp,max.maxMp,max.maxSp),(1900,1800,1700));

    final single=Uint8List(9),sd=ByteData.sublistView(single);
    sd.setUint32(0,77,Endian.little);
    single[4]=2;
    sd.setInt32(5,2000,Endian.little);
    final one=PsCharacterMaxHitpoint.parse(PsPacket(PsPacketType.characterMaxHitpoints,single));
    expect((one.characterId,one.type,one.value),(77,2,2000));

    final money=Uint8List(4);
    ByteData.sublistView(money).setUint32(0,987654,Endian.little);
    expect(PsMoneyUpdate.parse(PsPacket(PsPacketType.setMoney,money)).gold,987654);
  });

  test('parses target buffs map drops and NPC attacks',(){
    final buffs=Uint8List(20),bd=ByteData.sublistView(buffs);
    buffs[0]=2;
    bd.setUint32(1,555,Endian.little);
    buffs[5]=2;
    bd.setUint16(6,100,Endian.little);buffs[8]=2;bd.setInt32(9,30,Endian.little);
    bd.setUint16(13,200,Endian.little);buffs[15]=3;bd.setInt32(16,45,Endian.little);
    final target=PsTargetBuffState.parse(PsPacket(PsPacketType.targetBuffs,buffs));
    expect((target.targetType,target.targetId),(2,555));
    expect(target.buffs.map((b)=>b.skillId).toList(),[100,200]);

    final change=Uint8List(8),cd=ByteData.sublistView(change);
    change[0]=1;cd.setUint32(1,777,Endian.little);cd.setUint16(5,333,Endian.little);change[7]=4;
    final added=PsTargetBuffChange.parse(PsPacket(PsPacketType.targetBuffAdd,change));
    expect((added.targetId,added.skillId,added.skillLevel),(777,333,4));

    final drop=Uint8List(24),dd=ByteData.sublistView(drop);
    dd.setUint32(0,9001,Endian.little);
    drop[4]=1;drop[5]=12;drop[6]=34;drop[7]=2;
    dd.setFloat32(8,10.5,Endian.little);dd.setFloat32(12,2.25,Endian.little);dd.setFloat32(16,30.75,Endian.little);
    dd.setUint32(20,77,Endian.little);
    final item=PsMapItem.parse(PsPacket(PsPacketType.mapAddItem,drop));
    expect((item.globalId,item.type,item.typeId,item.count,item.ownerId),(9001,12,34,2,77));
    expect(item.x,closeTo(10.5,1e-6));

    final npc=Uint8List(11),nd=ByteData.sublistView(npc);
    npc[0]=1;nd.setUint32(1,444,Endian.little);nd.setUint32(5,77,Endian.little);nd.setUint16(9,123,Endian.little);
    final hit=PsNpcAttack.parse(PsPacket(PsPacketType.mapNpcAttackPlayer,npc));
    expect(hit.success,isTrue);
    expect((hit.npcId,hit.targetId,hit.hpDamage),(444,77,123));
  });
}
