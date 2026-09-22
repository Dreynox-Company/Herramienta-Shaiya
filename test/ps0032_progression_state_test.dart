import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/game/ps0032_protocol.dart';

Uint8List data(int length,void Function(ByteData d,Uint8List b) fill){
  final b=Uint8List(length),d=ByteData.sublistView(b);fill(d,b);return b;
}

void main(){
  test('parses SET_MONEY and max vitals',(){
    final money=ByteData(4)..setUint32(0,123456,Endian.little);
    expect(PsMoneyUpdate.parse(PsPacket(PsPacketType.setMoney,money.buffer.asUint8List())).gold,123456);

    final vitals=data(16,(d,b){
      d.setUint32(0,77,Endian.little);
      d.setInt32(4,5000,Endian.little);
      d.setInt32(8,900,Endian.little);
      d.setInt32(12,800,Endian.little);
    });
    final v=PsMaxVitals.parse(PsPacket(PsPacketType.characterMaxHpMpSp,vitals));
    expect((v.characterId,v.maxHp,v.maxMp,v.maxSp),(77,5000,900,800));
  });

  test('parses normalized experience gain and level up',(){
    final exp=data(8,(d,b){
      d.setUint32(0,321,Endian.little);d.setUint32(4,0,Endian.little);
    });
    expect(PsExperienceGain.parse(PsPacket(PsPacketType.experienceGain,exp)).amount,321);

    final level=data(18,(d,b){
      d.setUint32(0,77,Endian.little);
      d.setUint16(4,22,Endian.little);
      d.setUint16(6,15,Endian.little);
      d.setUint16(8,8,Endian.little);
      d.setUint32(10,10000,Endian.little);
      d.setUint32(14,15000,Endian.little);
    });
    for(final type in [PsPacketType.characterLevelUpSelf,PsPacketType.characterLevelUpOther]){
      final up=PsLevelUp.parse(PsPacket(type,level));
      expect((up.characterId,up.level,up.statPoint,up.skillPoint,up.minExp,up.nextExp),(77,22,15,8,10000,15000));
    }
  });

  test('parses item expiration and expired layouts',(){
    final expiration=data(14,(d,b){
      b[0]=2;b[1]=7;
      d.setInt32(2,111,Endian.little);
      d.setInt32(6,222,Endian.little);
      d.setInt32(10,0,Endian.little);
    });
    final e=PsItemExpiration.parse(PsPacket(PsPacketType.itemExpiration,expiration));
    expect((e.bag,e.slot,e.creationTime,e.expirationTime,e.unknown),(2,7,111,222,0));
    expect(e.key,'2:7');

    final expired=data(7,(d,b){
      b[0]=2;b[1]=7;b[2]=30;b[3]=4;b[4]=0;d.setUint16(5,3,Endian.little);
    });
    final x=PsItemExpired.parse(PsPacket(PsPacketType.itemExpired,expired));
    expect((x.bag,x.slot,x.type,x.typeId,x.remainingMinutes,x.expireType),(2,7,30,4,0,3));
  });

  test('character details copyWith preserves authoritative values',(){
    const base=PsCharacterDetails(
      strength:1,dexterity:2,reaction:3,intelligence:4,wisdom:5,luck:6,
      statPoint:7,skillPoint:8,maxHp:100,maxMp:90,maxSp:80,angle:11,
      startExp:1000,endExp:2000,currentExp:1500,gold:300,
      x:1,y:2,z:3,kills:4,deaths:5,victories:6,defeats:7,guildName:'Guild',
    );
    final next=base.copyWith(maxHp:140,currentExp:1750,gold:500,statPoint:9);
    expect((next.maxHp,next.currentExp,next.gold,next.statPoint),(140,1750,500,9));
    expect((next.maxMp,next.guildName,next.x),(90,'Guild',1.0));
  });

  test('new passive packet parsers reject truncation',(){
    expect(()=>PsMoneyUpdate.parse(PsPacket(PsPacketType.setMoney,Uint8List(3))),throwsFormatException);
    expect(()=>PsMaxVitals.parse(PsPacket(PsPacketType.characterMaxHpMpSp,Uint8List(15))),throwsFormatException);
    expect(()=>PsExperienceGain.parse(PsPacket(PsPacketType.experienceGain,Uint8List(7))),throwsFormatException);
    expect(()=>PsLevelUp.parse(PsPacket(PsPacketType.characterLevelUpSelf,Uint8List(17))),throwsFormatException);
    expect(()=>PsItemExpiration.parse(PsPacket(PsPacketType.itemExpiration,Uint8List(13))),throwsFormatException);
    expect(()=>PsItemExpired.parse(PsPacket(PsPacketType.itemExpired,Uint8List(6))),throwsFormatException);
  });
}
