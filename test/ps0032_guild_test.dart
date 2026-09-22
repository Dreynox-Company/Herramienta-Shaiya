import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/game/ps0032_protocol.dart';

void fixed(Uint8List b,int offset,int length,String value){
  final raw=utf8.encode(value),n=raw.length<length?raw.length:length;
  b.setRange(offset,offset+n,raw);
}

void fixed16(Uint8List b,int offset,int byteLength,String value){
  final d=ByteData.sublistView(b),codes=value.runes.take(byteLength~/2).toList();
  for(var i=0;i<codes.length;i++)d.setUint16(offset+i*2,codes[i],Endian.little);
}

void main(){
  test('parses SHAIYA_US 185-byte guild directory unit',(){
    final b=Uint8List(1+185),d=ByteData.sublistView(b);b[0]=1;const o=1;
    d.setUint32(o,77,Endian.little);fixed(b,o+4,25,'Dreynox');fixed(b,o+29,21,'GuildMaster');
    fixed16(b,o+50,130,'Mensaje de Guild');b[o+180]=4;d.setInt32(o+181,987654,Endian.little);
    final list=parseGuildList(PsPacket(PsPacketType.guildList,b));
    expect(list.length,1);
    final g=list.single;
    expect((g.id,g.name,g.masterName,g.rank,g.points),(77,'Dreynox','GuildMaster',4,987654));
    expect(g.message,'Mensaje de Guild');
  });

  test('parses guild online member list and member add',(){
    final b=Uint8List(1+29),d=ByteData.sublistView(b);b[0]=1;const o=1;
    d.setUint32(o,123,Endian.little);b[o+4]=2;d.setUint16(o+5,60,Endian.little);b[o+7]=5;fixed(b,o+8,21,'PriestOne');
    final list=parseGuildMembers(PsPacket(PsPacketType.guildUserListOnline,b),online:true);
    expect(list.length,1);
    expect((list.single.id,list.single.rank,list.single.level,list.single.job,list.single.name,list.single.online),(123,2,60,5,'PriestOne',true));

    final add=Uint8List(30),ad=ByteData.sublistView(add);add[0]=0;
    ad.setUint32(1,456,Endian.little);add[5]=7;ad.setUint16(6,44,Endian.little);add[8]=3;fixed(add,9,21,'ArcherTwo');
    final member=parseGuildMemberAdd(PsPacket(PsPacketType.guildUserListAdd,add));
    expect((member.id,member.rank,member.level,member.job,member.name,member.online),(456,7,44,3,'ArcherTwo',false));
  });

  test('parses guild join applicant and join result',(){
    final applicant=Uint8List(28),d=ByteData.sublistView(applicant);
    d.setUint32(0,999,Endian.little);d.setUint16(4,31,Endian.little);applicant[6]=2;fixed(applicant,7,21,'RangerJoin');
    final a=PsGuildJoinApplicant.parseUnit(applicant,0);
    expect((a.id,a.level,a.job,a.name),(999,31,2,'RangerJoin'));

    final result=Uint8List(31),rd=ByteData.sublistView(result);
    result[0]=1;rd.setUint32(1,88,Endian.little);result[5]=9;fixed(result,6,25,'AcceptedGuild');
    final j=PsGuildJoinResult.parse(PsPacket(PsPacketType.guildJoinResultUser,result));
    expect(j.ok,isTrue);
    expect((j.guildId,j.rank,j.name),(88,9,'AcceptedGuild'));
  });

  test('parses guild create failure success and agreement invite',(){
    final fail=PsGuildCreateResult.parse(PsPacket(PsPacketType.guildCreate,Uint8List.fromList([3])));
    expect(fail.success,isFalse);expect(fail.reason,3);

    final success=Uint8List(96),d=ByteData.sublistView(success);
    success[0]=0;d.setUint32(1,777,Endian.little);success[5]=1;fixed(success,6,25,'NewGuild');fixed(success,31,65,'Guild message');
    final created=PsGuildCreateResult.parse(PsPacket(PsPacketType.guildCreate,success));
    expect(created.success,isTrue);
    expect((created.guildId,created.rank,created.name,created.message),(777,1,'NewGuild','Guild message'));

    final invite=Uint8List(94),id=ByteData.sublistView(invite);
    id.setUint32(0,42,Endian.little);fixed(invite,4,25,'NewGuild');fixed(invite,29,65,'Join us');
    final ci=PsGuildCreateInvite.parse(PsPacket(PsPacketType.guildCreateAgree,invite));
    expect((ci.creatorId,ci.name,ci.message),(42,'NewGuild','Join us'));
  });
}
