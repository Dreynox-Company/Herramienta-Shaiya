import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/game/ps0032_protocol.dart';

void _name(Uint8List b,int offset,String value){
  final raw=utf8.encode(value),n=raw.length>21?21:raw.length;
  b.setRange(offset,offset+n,raw);
}

void main(){
  test('parses RAID_LIST with indexed member and buff',(){
    final b=Uint8List(8+69+7),d=ByteData.sublistView(b);
    b[0]=1;b[1]=6;b[2]=7;d.setUint16(3,2,Endian.little);b[5]=1;b[6]=1;b[7]=1;
    const o=8;
    d.setUint16(o,6,Endian.little);
    d.setUint32(o+2,12345,Endian.little);
    _name(b,o+6,'RaidMember');
    d.setUint16(o+27,55,Endian.little);b[o+29]=3;
    d.setInt32(o+30,5000,Endian.little);d.setInt32(o+34,4500,Endian.little);
    d.setInt32(o+38,800,Endian.little);d.setInt32(o+42,700,Endian.little);
    d.setInt32(o+46,1200,Endian.little);d.setInt32(o+50,1100,Endian.little);
    d.setUint16(o+54,7,Endian.little);
    d.setFloat32(o+56,10.5,Endian.little);d.setFloat32(o+60,20.5,Endian.little);d.setFloat32(o+64,30.5,Endian.little);
    b[o+68]=1;
    const bo=o+69;
    d.setUint16(bo,333,Endian.little);b[bo+2]=2;d.setInt32(bo+3,45,Endian.little);

    final raid=PsRaidState.parse(PsPacket(PsPacketType.raidList,b));
    expect(raid.leaderIndex,6);expect(raid.subLeaderIndex,7);expect(raid.dropType,2);expect(raid.autoJoin,isTrue);
    expect(raid.members.length,1);
    final row=raid.members.single,m=row.member;
    expect(row.index,6);expect(m.id,12345);expect(m.name,'RaidMember');expect(m.level,55);expect(m.profession,3);
    expect((m.maxHp,m.hp,m.maxSp,m.sp,m.maxMp,m.mp),(5000,4500,800,700,1200,1100));
    expect(m.mapId,7);expect(m.x,closeTo(10.5,1e-6));expect(m.buffs.length,1);
    expect((m.buffs.single.skillId,m.buffs.single.skillLevel,m.buffs.single.countdownSeconds),(333,2,45));
  });

  test('parses RAID_ENTER member layout',(){
    final b=Uint8List(69),d=ByteData.sublistView(b);
    d.setUint16(0,12,Endian.little);d.setUint32(2,99,Endian.little);_name(b,6,'Joiner');
    d.setUint16(27,10,Endian.little);b[29]=1;d.setInt32(30,100,Endian.little);d.setInt32(34,90,Endian.little);
    b[68]=0;
    final row=parseRaidEnter(PsPacket(PsPacketType.raidEnter,b));
    expect(row.index,12);expect(row.member.id,99);expect(row.member.name,'Joiner');expect(row.member.hp,90);
  });

  test('parses RAID_MOVE_PLAYER indices',(){
    final b=Uint8List(16),d=ByteData.sublistView(b);
    d.setInt32(0,2,Endian.little);d.setInt32(4,9,Endian.little);d.setInt32(8,0,Endian.little);d.setInt32(12,6,Endian.little);
    final move=PsRaidMove.parse(PsPacket(PsPacketType.raidMovePlayer,b));
    expect((move.sourceIndex,move.destinationIndex,move.leaderIndex,move.subLeaderIndex),(2,9,0,6));
  });
}
