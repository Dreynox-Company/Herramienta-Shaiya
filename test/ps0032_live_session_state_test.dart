import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/game/ps0032_protocol.dart';

Uint8List bytes(int length,void Function(ByteData d,Uint8List b) fill){
  final b=Uint8List(length),d=ByteData.sublistView(b);fill(d,b);return b;
}

void main(){
  test('parses BLESS_INIT and BLESS_UPDATE preserving timer',(){
    final init=bytes(9,(d,b){
      b[0]=0;d.setInt32(1,777,Endian.little);d.setUint32(5,1234,Endian.little);
    });
    final a=PsBlessState.parse(PsPacket(PsPacketType.blessInit,init));
    expect((a.country,a.amount,a.remainingTime),(0,777,1234));

    final update=bytes(5,(d,b){b[0]=0;d.setInt32(1,888,Endian.little);});
    final b=PsBlessState.parse(PsPacket(PsPacketType.blessUpdate,update),previous:a);
    expect((b.country,b.amount,b.remainingTime),(0,888,1234));
  });

  test('parses bank list and bank claim',(){
    final body=Uint8List.fromList([
      2,
      1,30,7,3,
      5,42,9,1,
    ]);
    final items=parseBankItems(PsPacket(PsPacketType.bankItemList,body));
    expect(items.length,2);
    expect((items[0].slot,items[0].type,items[0].typeId,items[0].count),(1,30,7,3));
    expect((items[1].slot,items[1].type,items[1].typeId,items[1].count),(5,42,9,1));

    final claim=PsBankClaim.parse(PsPacket(
      PsPacketType.bankClaimItem,Uint8List.fromList([5,2,11,1]),
    ));
    expect((claim.bankSlot,claim.bag,claim.slot,claim.count),(5,2,11,1));
  });

  test('parses saved teleport positions and result',(){
    final body=bytes(31,(d,b){
      b[0]=2;
      b[1]=0;d.setUint16(2,1,Endian.little);
      d.setFloat32(4,10,Endian.little);d.setFloat32(8,20,Endian.little);d.setFloat32(12,30,Endian.little);
      b[16]=3;d.setUint16(17,42,Endian.little);
      d.setFloat32(19,40,Endian.little);d.setFloat32(23,50,Endian.little);d.setFloat32(27,60,Endian.little);
    });
    final positions=parseTeleportSavedPositions(PsPacket(PsPacketType.teleportSavePositionList,body));
    expect(positions.length,2);
    expect((positions[0].index,positions[0].mapId),(0,1));
    expect((positions[1].index,positions[1].mapId),(3,42));
    expect(positions[1].z,closeTo(60,1e-6));

    final resultBody=bytes(16,(d,b){
      b[0]=0;b[1]=3;d.setUint16(2,42,Endian.little);
      d.setFloat32(4,40,Endian.little);d.setFloat32(8,50,Endian.little);d.setFloat32(12,60,Endian.little);
    });
    final result=PsTeleportSavedPositionResult.parse(
      PsPacket(PsPacketType.teleportSavePosition,resultBody),
    );
    expect(result.success,isTrue);
    expect((result.position.index,result.position.mapId),(3,42));
  });

  test('parses account points',(){
    final body=bytes(5,(d,b){d.setUint32(0,3456,Endian.little);b[4]=0;});
    final p=PsAccountPoints.parse(PsPacket(PsPacketType.accountPoints,body));
    expect((p.points,p.unknown),(3456,0));
  });

  test('parses obelisk list and ownership change',(){
    final body=bytes(27,(d,b){
      b[0]=2;
      d.setUint32(1,100,Endian.little);b[5]=1;
      d.setFloat32(6,11.5,Endian.little);d.setFloat32(10,22.5,Endian.little);
      d.setUint32(14,101,Endian.little);b[18]=2;
      d.setFloat32(19,33.5,Endian.little);d.setFloat32(23,44.5,Endian.little);
    });
    final list=parseObeliskList(PsPacket(PsPacketType.obeliskList,body));
    expect(list.length,2);
    expect((list[0].id,list[0].country),(100,1));
    expect((list[1].id,list[1].country),(101,2));
    expect(list[1].z,closeTo(44.5,1e-6));

    final change=bytes(5,(d,b){d.setUint32(0,101,Endian.little);b[4]=1;});
    final x=PsObeliskChange.parse(PsPacket(PsPacketType.obeliskChange,change));
    expect((x.id,x.country),(101,1));
  });

  test('parses UTF-16 and single-byte notices',(){
    const message='Bienvenido';
    final utf16=Uint8List(1+message.length*2),d=ByteData.sublistView(utf16);
    utf16[0]=message.length;
    for(var i=0;i<message.length;i++)d.setUint16(1+i*2,message.codeUnitAt(i),Endian.little);
    final a=PsNotice.parse(PsPacket(PsPacketType.noticePlayer,utf16));
    expect(a.message,message);

    final latin=Uint8List.fromList([4,...'Hola'.codeUnits]);
    final b=PsNotice.parse(PsPacket(PsPacketType.noticeWorld,latin));
    expect(b.message,'Hola');
  });

  test('live-session parsers reject truncation',(){
    expect(()=>PsBlessState.parse(PsPacket(PsPacketType.blessInit,Uint8List(8))),throwsFormatException);
    expect(()=>parseBankItems(PsPacket(PsPacketType.bankItemList,Uint8List.fromList([1,1,2]))),throwsFormatException);
    expect(()=>parseTeleportSavedPositions(PsPacket(PsPacketType.teleportSavePositionList,Uint8List.fromList([1]))),throwsFormatException);
    expect(()=>PsAccountPoints.parse(PsPacket(PsPacketType.accountPoints,Uint8List(4))),throwsFormatException);
    expect(()=>parseObeliskList(PsPacket(PsPacketType.obeliskList,Uint8List.fromList([1]))),throwsFormatException);
    expect(()=>PsNotice.parse(PsPacket(PsPacketType.noticePlayer,Uint8List.fromList([8,65]))),throwsFormatException);
  });
}
