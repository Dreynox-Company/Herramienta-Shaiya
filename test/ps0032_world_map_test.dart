import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/game/ps0032_protocol.dart';

int nativeTimeRaw(int year,int month,int day,int hour,int minute,int second){
  var raw=second+((minute+((hour+32*(day+32*(month+16*(year-16))))<<6))<<6);
  raw&=0xffffffff;
  if(raw>=0x80000000)raw-=0x100000000;
  return raw;
}

void main(){
  test('parses dropped map item authoritative layout',(){
    final b=Uint8List(24),d=ByteData.sublistView(b);
    d.setUint32(0,9001,Endian.little);
    b[4]=1;b[5]=30;b[6]=7;b[7]=3;
    d.setFloat32(8,11.5,Endian.little);
    d.setFloat32(12,2.25,Endian.little);
    d.setFloat32(16,99.75,Endian.little);
    d.setUint32(20,1234,Endian.little);
    final item=PsMapItem.parse(PsPacket(PsPacketType.mapAddItem,b));
    expect((item.id,item.kind,item.type,item.typeId,item.count,item.ownerId),(9001,1,30,7,3,1234));
    expect(item.x,closeTo(11.5,1e-6));
    expect(item.y,closeTo(2.25,1e-6));
    expect(item.z,closeTo(99.75,1e-6));
  });

  test('parses map item removal',(){
    final b=ByteData(4)..setUint32(0,9001,Endian.little);
    expect(
      parseMapItemRemove(PsPacket(PsPacketType.mapRemoveItem,b.buffer.asUint8List())),
      9001,
    );
  });

  test('WORLD_DAY decodes native packed calendar/time fields',(){
    final raw=nativeTimeRaw(2020,1,1,12,30,0);
    final b=ByteData(4)..setInt32(0,raw,Endian.little);
    final value=PsWorldDay.parse(PsPacket(PsPacketType.worldDay,b.buffer.asUint8List()));
    expect(value.second,0);
    expect(value.minute,30);
    expect(value.hour,12);
    expect(value.day,1);
    expect(value.month,1);
    expect(value.year,((2020-16)&0x3f)+16);
  });

  test('world snapshot tracks map-item add/remove and day',(){
    Uint8List add(int id){
      final b=Uint8List(24),d=ByteData.sublistView(b);
      d.setUint32(0,id,Endian.little);b[4]=1;b[5]=30;b[6]=1;b[7]=1;
      d.setFloat32(8,1,Endian.little);d.setFloat32(12,2,Endian.little);d.setFloat32(16,3,Endian.little);
      return b;
    }
    final remove=ByteData(4)..setUint32(0,1,Endian.little);
    final day=ByteData(4)..setInt32(0,nativeTimeRaw(2020,2,3,4,5,6),Endian.little);
    final snapshot=PsWorldSnapshot.fromPackets([
      PsPacket(PsPacketType.mapAddItem,add(1)),
      PsPacket(PsPacketType.mapAddItem,add(2)),
      PsPacket(PsPacketType.mapRemoveItem,remove.buffer.asUint8List()),
      PsPacket(PsPacketType.worldDay,day.buffer.asUint8List()),
    ]);
    expect(snapshot.mapItems.map((x)=>x.id),[2]);
    expect((snapshot.worldDay!.month,snapshot.worldDay!.day,snapshot.worldDay!.hour,snapshot.worldDay!.minute,snapshot.worldDay!.second),(2,3,4,5,6));
  });

  test('map item and day parsers reject truncation',(){
    expect(()=>PsMapItem.parse(PsPacket(PsPacketType.mapAddItem,Uint8List(23))),throwsFormatException);
    expect(()=>parseMapItemRemove(PsPacket(PsPacketType.mapRemoveItem,Uint8List(3))),throwsFormatException);
    expect(()=>PsWorldDay.parse(PsPacket(PsPacketType.worldDay,Uint8List(3))),throwsFormatException);
  });
}
