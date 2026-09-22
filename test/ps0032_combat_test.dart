import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/game/ps0032_protocol.dart';

Uint8List _body(int n)=>Uint8List(n);

void main(){
  test('parses ps0032 target mob hp update',(){
    final b=_body(10),d=ByteData.sublistView(b);
    d.setUint32(0,1234,Endian.little);
    d.setInt32(4,9876,Endian.little);
    b[8]=3;b[9]=5;
    final p=PsTargetMobHp.parse(PsPacket(PsPacketType.targetMobHpUpdate,b));
    expect(p.targetId,1234);
    expect(p.currentHp,9876);
    expect(p.attackSpeed,3);
    expect(p.moveSpeed,5);
  });

  test('parses character skill hit against mob',(){
    final b=_body(19),d=ByteData.sublistView(b);
    b[0]=1;
    d.setUint32(1,10,Endian.little);
    d.setUint32(5,20,Endian.little);
    d.setUint16(9,300,Endian.little);
    b[11]=4;
    d.setUint16(12,111,Endian.little);
    d.setUint16(14,22,Endian.little);
    d.setUint16(16,33,Endian.little);
    b[18]=1;
    final p=PsSkillHit.parse(PsPacket(PsPacketType.useMobTargetSkill,b));
    expect(p.success,isTrue);
    expect(p.attackerId,10);
    expect(p.targetId,20);
    expect(p.skillId,300);
    expect(p.skillLevel,4);
    expect(p.hpDamage,111);
    expect(p.spDamage,22);
    expect(p.mpDamage,33);
    expect(p.keepActivated,isTrue);
  });

  test('parses ps0032 cast range keep and mirror skill packets',(){
    final cast=Uint8List(11),cd=ByteData.sublistView(cast);
    cd.setUint32(0,101,Endian.little);
    cd.setUint32(4,202,Endian.little);
    cd.setUint16(8,303,Endian.little);
    cast[10]=4;
    final casting=PsSkillCasting.parse(
      PsPacket(PsPacketType.characterSkillCasting,cast),
    );
    expect((casting.casterId,casting.targetId,casting.skillId,casting.skillLevel),(101,202,303,4));

    final range=Uint8List(19),rd=ByteData.sublistView(range);
    range[0]=1;
    rd.setUint32(1,101,Endian.little);
    rd.setUint32(5,202,Endian.little);
    rd.setUint16(9,303,Endian.little);
    range[11]=4;
    rd.setUint16(12,40,Endian.little);
    rd.setUint16(14,5,Endian.little);
    rd.setUint16(16,6,Endian.little);
    range[18]=0;
    final ranged=PsCharacterSkillHit.parse(
      PsPacket(PsPacketType.useCharacterRangeSkill,range),
    );
    expect(ranged.hpDamage,40);
    expect(ranged.targetId,202);

    final keep=Uint8List(13),kd=ByteData.sublistView(keep);
    kd.setUint32(0,101,Endian.little);
    kd.setUint16(4,303,Endian.little);
    keep[6]=4;
    kd.setUint16(7,11,Endian.little);
    kd.setUint16(9,12,Endian.little);
    kd.setUint16(11,13,Endian.little);
    final periodic=PsSkillKeep.parse(
      PsPacket(PsPacketType.characterSkillKeep,keep),
    );
    expect((periodic.hpDamage,periodic.spDamage,periodic.mpDamage),(11,12,13));

    final mirror=Uint8List(14),md=ByteData.sublistView(mirror);
    md.setUint32(0,202,Endian.little);
    md.setUint32(4,101,Endian.little);
    md.setUint16(8,7,Endian.little);
    md.setUint16(10,8,Endian.little);
    md.setUint16(12,9,Endian.little);
    final reflected=PsSkillMirror.parse(
      PsPacket(PsPacketType.characterSkillMirror,mirror),
    );
    expect((reflected.targetId,reflected.senderId,reflected.hpDamage),(202,101,7));
  });

  test('parses character auto attack against mob',(){
    final b=_body(15),d=ByteData.sublistView(b);
    b[0]=0;
    d.setUint32(1,41,Endian.little);
    d.setUint32(5,42,Endian.little);
    d.setUint16(9,77,Endian.little);
    d.setUint16(11,8,Endian.little);
    d.setUint16(13,9,Endian.little);
    final p=PsUsualHit.parse(PsPacket(PsPacketType.characterMobAutoAttack,b));
    expect(p.success,isTrue);
    expect(p.attackerId,41);
    expect(p.targetId,42);
    expect(p.hpDamage,77);
    expect(p.spDamage,8);
    expect(p.mpDamage,9);
  });
  test('parses mob range and persistent skill layouts',(){
    final range=Uint8List(19),rd=ByteData.sublistView(range);
    range[0]=1;
    rd.setUint32(1,501,Endian.little);
    rd.setUint32(5,601,Endian.little);
    rd.setUint16(9,701,Endian.little);
    range[11]=2;
    rd.setUint16(12,80,Endian.little);
    rd.setUint16(14,9,Endian.little);
    rd.setUint16(16,10,Endian.little);
    range[18]=0;
    final area=PsMobRangeSkillHit.parse(
      PsPacket(PsPacketType.mobRangeSkillUse,range),
    );
    expect((area.mobId,area.targetId,area.skillId),(501,601,701));
    expect((area.hpDamage,area.spDamage,area.mpDamage),(80,9,10));

    final keep=Uint8List(13),kd=ByteData.sublistView(keep);
    kd.setUint32(0,501,Endian.little);
    kd.setUint16(4,701,Endian.little);
    keep[6]=2;
    kd.setUint16(7,12,Endian.little);
    kd.setUint16(9,3,Endian.little);
    kd.setUint16(11,4,Endian.little);
    final periodic=PsSkillKeep.parse(
      PsPacket(PsPacketType.mobSkillKeep,keep),
    );
    expect(periodic.senderId,501);
    expect(periodic.skillId,701);
    expect(periodic.hpDamage,12);
  });

  test('parses mob normal attack',(){
    final b=_body(15),d=ByteData.sublistView(b);
    b[0]=0;
    d.setUint32(1,77,Endian.little);
    d.setUint32(5,88,Endian.little);
    d.setUint16(9,55,Endian.little);
    d.setUint16(11,6,Endian.little);
    d.setUint16(13,7,Endian.little);
    final p=PsMobAttack.parse(PsPacket(PsPacketType.mobAttack,b));
    expect(p.success,isTrue);
    expect(p.mobId,77);
    expect(p.targetId,88);
    expect(p.hpDamage,55);
    expect(p.spDamage,6);
    expect(p.mpDamage,7);
  });

  test('parses mob skill attack',(){
    final b=_body(19),d=ByteData.sublistView(b);
    b[0]=1;
    d.setUint32(1,90,Endian.little);
    d.setUint32(5,91,Endian.little);
    b[9]=2;
    d.setUint16(10,444,Endian.little);
    b[12]=3;
    d.setUint16(13,100,Endian.little);
    d.setUint16(15,8,Endian.little);
    d.setUint16(17,9,Endian.little);
    final p=PsMobSkillHit.parse(PsPacket(PsPacketType.mobSkillUse,b));
    expect(p.success,isTrue);
    expect(p.mobId,90);
    expect(p.targetId,91);
    expect(p.attackType,2);
    expect(p.skillId,444);
    expect(p.skillLevel,3);
    expect(p.hpDamage,100);
    expect(p.spDamage,8);
    expect(p.mpDamage,9);
  });

  test('parses character death and dead rebirth',(){
    final death=Uint8List(9),dd=ByteData.sublistView(death);
    dd.setUint32(0,123,Endian.little);
    death[4]=2;
    dd.setUint32(5,456,Endian.little);
    final d=PsCharacterDeath.parse(PsPacket(PsPacketType.characterDeath,death));
    expect((d.characterId,d.killerType,d.killerId),(123,2,456));

    final rebirth=Uint8List(21),rd=ByteData.sublistView(rebirth);
    rd.setUint32(0,123,Endian.little);
    rebirth[4]=4;
    rd.setUint32(5,7890,Endian.little);
    rd.setFloat32(9,10.5,Endian.little);
    rd.setFloat32(13,20.25,Endian.little);
    rd.setFloat32(17,30.75,Endian.little);
    final r=PsDeadRebirth.parse(PsPacket(PsPacketType.deadRebirth,rebirth));
    expect((r.characterId,r.rebirthType,r.expLoss),(123,4,7890));
    expect(r.x,closeTo(10.5,1e-6));
    expect(r.y,closeTo(20.25,1e-6));
    expect(r.z,closeTo(30.75,1e-6));
  });

}
