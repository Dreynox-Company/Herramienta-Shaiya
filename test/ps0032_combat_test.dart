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
}
