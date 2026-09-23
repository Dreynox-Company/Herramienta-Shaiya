import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/game/ps0032_protocol.dart';

void main(){
  test('CHARACTER_ATTRIBUTE_SET decodes enum byte and uint value',(){
    final b=Uint8List(5),d=ByteData.sublistView(b);
    b[0]=PsCharacterAttribute.experience;
    d.setUint32(1,1234567,Endian.little);
    final value=PsCharacterAttribute.parse(PsPacket(PsPacketType.characterAttributeSet,b));
    expect((value.attribute,value.value),(PsCharacterAttribute.experience,1234567));
  });

  test('AUTO_STATS_LIST keeps server response order STR DEX REC INT WIS LUC',(){
    final value=PsAutoStats.parse(PsPacket(
      PsPacketType.autoStatsList,
      Uint8List.fromList([1,2,3,4,5,6]),
    ));
    expect(value.values,[1,2,3,4,5,6]);
    expect(value.total,21);
  });

  test('STATS_RESET uses native response order and ushort widths',(){
    final b=Uint8List(15),d=ByteData.sublistView(b);
    b[0]=1;
    d.setUint16(1,77,Endian.little);
    d.setUint16(3,11,Endian.little);
    d.setUint16(5,22,Endian.little);
    d.setUint16(7,33,Endian.little);
    d.setUint16(9,44,Endian.little);
    d.setUint16(11,55,Endian.little);
    d.setUint16(13,66,Endian.little);
    final value=PsStatsReset.parse(PsPacket(PsPacketType.statsReset,b));
    expect(value.success,isTrue);
    expect(
      (
        value.statPoint,value.strength,value.reaction,value.intelligence,
        value.wisdom,value.dexterity,value.luck,
      ),
      (77,11,22,33,44,55,66),
    );
  });

  test('RESET_SKILLS returns authoritative skill points',(){
    final b=Uint8List(3),d=ByteData.sublistView(b);
    b[0]=1;d.setUint16(1,123,Endian.little);
    final value=PsSkillsReset.parse(PsPacket(PsPacketType.resetSkills,b));
    expect(value.success,isTrue);
    expect(value.skillPoint,123);
  });

  test('USER_KILLCOUNT_UPDATE decodes index and uint count',(){
    final b=Uint8List(5),d=ByteData.sublistView(b);
    b[0]=2;d.setUint32(1,987654,Endian.little);
    final value=PsKillCountUpdate.parse(PsPacket(PsPacketType.userKillCountUpdate,b));
    expect((value.index,value.count),(2,987654));
  });

  test('progression parsers reject truncation',(){
    expect(
      ()=>PsCharacterAttribute.parse(PsPacket(PsPacketType.characterAttributeSet,Uint8List(4))),
      throwsFormatException,
    );
    expect(
      ()=>PsAutoStats.parse(PsPacket(PsPacketType.autoStatsList,Uint8List(5))),
      throwsFormatException,
    );
    expect(
      ()=>PsStatsReset.parse(PsPacket(PsPacketType.statsReset,Uint8List(14))),
      throwsFormatException,
    );
    expect(
      ()=>PsSkillsReset.parse(PsPacket(PsPacketType.resetSkills,Uint8List(2))),
      throwsFormatException,
    );
    expect(
      ()=>PsKillCountUpdate.parse(PsPacket(PsPacketType.userKillCountUpdate,Uint8List(4))),
      throwsFormatException,
    );
  });
}
