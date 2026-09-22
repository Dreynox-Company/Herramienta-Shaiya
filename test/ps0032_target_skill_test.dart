import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/game/ps0032_protocol.dart';

Uint8List bytes(int length, void Function(ByteData d, Uint8List b) fill) {
  final b=Uint8List(length),d=ByteData.sublistView(b);
  fill(d,b);
  return b;
}

void main(){
  test('parses authoritative target mob state',(){
    final b=bytes(10,(d,b){
      d.setUint32(0,77,Endian.little);
      d.setInt32(4,3456,Endian.little);
      b[8]=4;b[9]=6;
    });
    final state=PsTargetMobState.parse(PsPacket(PsPacketType.targetMobGetState,b));
    expect((state.targetId,state.currentHp,state.attackSpeed,state.moveSpeed),(77,3456,4,6));
  });

  test('parses authoritative target buff list',(){
    final b=bytes(20,(d,b){
      b[0]=2;d.setUint32(1,91,Endian.little);b[5]=2;
      d.setUint16(6,1100,Endian.little);b[8]=3;d.setInt32(9,25,Endian.little);
      d.setUint16(13,1200,Endian.little);b[15]=2;d.setInt32(16,-1,Endian.little);
    });
    final state=PsTargetBuffs.parse(PsPacket(PsPacketType.targetBuffs,b));
    expect(state.mob,isTrue);
    expect(state.targetId,91);
    expect(state.buffs.length,2);
    expect((state.buffs[0].skillId,state.buffs[0].skillLevel,state.buffs[0].countdownSeconds),(1100,3,25));
    expect((state.buffs[1].skillId,state.buffs[1].skillLevel,state.buffs[1].countdownSeconds),(1200,2,-1));
  });

  test('parses target buff add and remove layout',(){
    PsTargetBuffChange parse(int type){
      final b=bytes(8,(d,b){
        b[0]=1;d.setUint32(1,42,Endian.little);d.setUint16(5,333,Endian.little);b[7]=4;
      });
      return PsTargetBuffChange.parse(PsPacket(type,b));
    }
    final added=parse(PsPacketType.targetBuffAdd),removed=parse(PsPacketType.targetBuffRemove);
    expect((added.targetType,added.targetId,added.skillId,added.skillLevel),(1,42,333,4));
    expect((removed.targetType,removed.targetId,removed.skillId,removed.skillLevel),(1,42,333,4));
  });

  test('parses exact casting and skill keep layouts',(){
    final castingBytes=bytes(11,(d,b){
      d.setUint32(0,101,Endian.little);d.setUint32(4,202,Endian.little);
      d.setUint16(8,303,Endian.little);b[10]=4;
    });
    final casting=PsSkillCasting.parse(PsPacket(PsPacketType.characterSkillCasting,castingBytes));
    expect((casting.casterId,casting.targetId,casting.skillId,casting.skillLevel),(101,202,303,4));

    final keepBytes=bytes(13,(d,b){
      d.setUint32(0,101,Endian.little);d.setUint16(4,303,Endian.little);b[6]=4;
      d.setUint16(7,50,Endian.little);d.setUint16(9,6,Endian.little);d.setUint16(11,7,Endian.little);
    });
    final keep=PsSkillKeep.parse(PsPacket(PsPacketType.characterSkillKeep,keepBytes));
    expect((keep.sourceId,keep.skillId,keep.skillLevel,keep.hpDamage,keep.spDamage,keep.mpDamage),(101,303,4,50,6,7));
  });

  test('range-skill packet uses same authoritative SkillRange layout',(){
    final b=bytes(19,(d,b){
      b[0]=1;d.setUint32(1,11,Endian.little);d.setUint32(5,22,Endian.little);
      d.setUint16(9,900,Endian.little);b[11]=5;
      d.setUint16(12,321,Endian.little);d.setUint16(14,12,Endian.little);d.setUint16(16,34,Endian.little);
      b[18]=1;
    });
    final character=PsCharacterSkillHit.parse(PsPacket(PsPacketType.useCharacterRangeSkill,b));
    final mob=PsSkillHit.parse(PsPacket(PsPacketType.useMobRangeSkill,b));
    expect((character.attackerId,character.targetId,character.skillId,character.skillLevel,character.hpDamage,character.keepActivated),(11,22,900,5,321,true));
    expect((mob.attackerId,mob.targetId,mob.skillId,mob.skillLevel,mob.hpDamage,mob.keepActivated),(11,22,900,5,321,true));
  });

  test('parses current recovery and max-hitpoint update',(){
    final recoverBytes=bytes(16,(d,b){
      d.setUint32(0,44,Endian.little);d.setInt32(4,5000,Endian.little);d.setInt32(8,800,Endian.little);d.setInt32(12,900,Endian.little);
    });
    final recovery=PsCharacterRecovery.parse(PsPacket(PsPacketType.characterRecover,recoverBytes));
    expect((recovery.characterId,recovery.hp,recovery.mp,recovery.sp),(44,5000,800,900));

    final maxBytes=bytes(9,(d,b){
      d.setUint32(0,44,Endian.little);b[4]=0;d.setInt32(5,7000,Endian.little);
    });
    final max=PsMaxHitpointUpdate.parse(PsPacket(PsPacketType.characterMaxHitpoints,maxBytes));
    expect((max.characterId,max.hitpointType,max.value),(44,0,7000));
  });

  test('rejects truncated authoritative layouts',(){
    expect(
      ()=>PsTargetBuffs.parse(PsPacket(PsPacketType.targetBuffs,Uint8List.fromList([1,1,0,0,0,1]))),
      throwsFormatException,
    );
    expect(
      ()=>PsSkillCasting.parse(PsPacket(PsPacketType.characterSkillCasting,Uint8List(10))),
      throwsFormatException,
    );
  });
}
