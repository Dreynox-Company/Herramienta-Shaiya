import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/game/ps0032_protocol.dart';

void _putFixed(Uint8List bytes,int offset,String value){
  final raw=utf8.encode(value);
  bytes.setRange(offset,offset+raw.length,raw);
}

PsPacket _entered(int id,double x){
  final b=Uint8List(27),d=ByteData.sublistView(b);
  d.setUint32(0,id,Endian.little);
  b[4]=0;
  d.setUint16(5,16384,Endian.little);
  d.setFloat32(7,x,Endian.little);
  d.setFloat32(11,2.5,Endian.little);
  d.setFloat32(15,30.5,Endian.little);
  d.setUint32(19,77,Endian.little);
  d.setUint32(23,0,Endian.little);
  return PsPacket(PsPacketType.characterEnteredMap,b);
}

void main(){
  test('parses CHARACTER_SHAPE including equipment, dye and names',(){
    final b=Uint8List(685),d=ByteData.sublistView(b),s=4;
    d.setUint32(0,4242,Endian.little);
    b[s]=0;
    b[s+1]=2;
    b[s+2]=1;
    b[s+3]=0;
    b[s+4]=3;
    b[s+5]=4;
    b[s+6]=5;
    b[s+7]=2;
    b[s+8]=1;
    b[s+9]=6;
    b[s+10]=3;
    d.setUint32(s+11,99,Endian.little);

    final eo=s+15+5*3;
    b[eo]=7;b[eo+1]=8;b[eo+2]=9;
    b[s+66+5]=1;
    final co=s+86+5*4;
    b[co]=200;b[co+1]=10;b[co+2]=20;b[co+3]=30;

    _putFixed(b,s+606,'RemoteHero');
    b[s+627]=12;
    _putFixed(b,s+656,'Dreynox');

    final shape=PsPlayerShape.parse(PsPacket(PsPacketType.characterShape,b));
    expect(shape.characterId,4242);
    expect(shape.motion,2);
    expect(shape.country,1);
    expect(shape.profession,2);
    expect(shape.gender,1);
    expect(shape.kills,99);
    expect(shape.name,'RemoteHero');
    expect(shape.guildFrame,12);
    expect(shape.guildName,'Dreynox');
    expect(shape.equipment.length,17);
    final weapon=shape.equipment[5];
    expect((weapon.type,weapon.typeId,weapon.enhancement),(7,8,9));
    expect(weapon.dyed,isTrue);
    expect((weapon.alpha,weapon.r,weapon.g,weapon.b),(200,10,20,30));
  });

  test('parses PvP target HP and usual hit packets',(){
    final hp=Uint8List(14),hd=ByteData.sublistView(hp);
    hd.setUint32(0,50,Endian.little);
    hd.setInt32(4,1234,Endian.little);
    hd.setInt32(8,4321,Endian.little);
    hp[12]=8;hp[13]=6;
    final target=PsTargetCharacterHp.parse(PsPacket(PsPacketType.targetCharacterHpUpdate,hp));
    expect((target.targetId,target.currentHp,target.maxHp),(50,1234,4321));
    expect((target.attackSpeed,target.moveSpeed),(8,6));

    final hit=Uint8List(15),d=ByteData.sublistView(hit);
    hit[0]=1;
    d.setUint32(1,10,Endian.little);
    d.setUint32(5,50,Endian.little);
    d.setUint16(9,321,Endian.little);
    d.setUint16(11,22,Endian.little);
    d.setUint16(13,11,Endian.little);
    final parsed=PsCharacterUsualHit.parse(PsPacket(PsPacketType.characterCharacterAutoAttack,hit));
    expect(parsed.success,isTrue);
    expect((parsed.attackerId,parsed.targetId),(10,50));
    expect((parsed.hpDamage,parsed.spDamage,parsed.mpDamage),(321,22,11));
  });

  test('parses PvP character-target skill hit',(){
    final b=Uint8List(19),d=ByteData.sublistView(b);
    b[0]=4;
    d.setUint32(1,10,Endian.little);
    d.setUint32(5,50,Endian.little);
    d.setUint16(9,777,Endian.little);
    b[11]=3;
    d.setUint16(12,600,Endian.little);
    d.setUint16(14,25,Endian.little);
    d.setUint16(16,40,Endian.little);
    b[18]=1;
    final parsed=PsCharacterSkillHit.parse(PsPacket(PsPacketType.useCharacterTargetSkill,b));
    expect(parsed.success,isTrue);
    expect((parsed.skillId,parsed.skillLevel),(777,3));
    expect((parsed.hpDamage,parsed.spDamage,parsed.mpDamage),(600,25,40));
    expect(parsed.keepActivated,isTrue);
  });

  test('parses and applies character appearance deltas',(){
    final b=Uint8List(8),d=ByteData.sublistView(b);
    d.setUint32(0,4242,Endian.little);
    b[4]=2;b[5]=3;b[6]=4;b[7]=1;
    final change=PsAppearanceChange.parse(
      PsPacket(PsPacketType.changeAppearance,b),
    );
    expect((change.characterId,change.hair,change.face,change.height,change.gender),(4242,2,3,4,1));

    final shapeBytes=Uint8List(685),sd=ByteData.sublistView(shapeBytes),s=4;
    sd.setUint32(0,4242,Endian.little);
    _putFixed(shapeBytes,s+606,'Hero');
    final shape=PsPlayerShape.parse(PsPacket(PsPacketType.characterShape,shapeBytes));
    final changed=shape.copyWith(
      hair:change.hair,face:change.face,height:change.height,gender:change.gender,
    );
    expect((changed.hair,changed.face,changed.height,changed.gender),(2,3,4,1));
    expect(changed.name,'Hero');
  });

  test('world snapshot keeps the requested local player identity',(){
    final snapshot=PsWorldSnapshot.fromPackets(
      [_entered(200,100),_entered(100,200)],
      selfCharacterId:100,
    );
    expect(snapshot.self,isNotNull);
    expect(snapshot.self!.characterId,100);
    expect(snapshot.self!.x,closeTo(200,1e-6));
  });
  test('parses authoritative PvP selection, remote move and leave',(){
    final selected=Uint8List(12),sd=ByteData.sublistView(selected);
    sd.setUint32(0,50,Endian.little);
    sd.setInt32(4,4321,Endian.little);
    sd.setInt32(8,1234,Endian.little);
    final target=PsTargetCharacterSelection.parse(PsPacket(PsPacketType.targetCharacterMaxHp,selected));
    expect((target.targetId,target.maxHp,target.currentHp),(50,4321,1234));

    final moving=Uint8List(19),md=ByteData.sublistView(moving);
    md.setUint32(0,50,Endian.little);
    md.setUint16(4,32768,Endian.little);
    moving[6]=2;
    md.setFloat32(7,101.25,Endian.little);
    md.setFloat32(11,5.5,Endian.little);
    md.setFloat32(15,202.75,Endian.little);
    final move=PsCharacterMove.parse(PsPacket(PsPacketType.characterMove,moving));
    expect((move.characterId,move.angle,move.motion),(50,32768,2));
    expect(move.running,isFalse);
    expect(move.walking,isFalse);
    expect(move.x,closeTo(101.25,1e-6));
    expect(move.y,closeTo(5.5,1e-6));
    expect(move.z,closeTo(202.75,1e-6));

    final left=Uint8List(4);
    ByteData.sublistView(left).setUint32(0,50,Endian.little);
    expect(
      PsCharacterLeftMap.parse(PsPacket(PsPacketType.characterLeftMap,left)).characterId,
      50,
    );
  });

}
