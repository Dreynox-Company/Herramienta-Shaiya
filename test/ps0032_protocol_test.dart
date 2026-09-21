import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/game/ps0032_protocol.dart';

Uint8List body(int size,void Function(ByteData d,Uint8List b) fill){
  final bytes=Uint8List(size),data=ByteData.sublistView(bytes);
  fill(data,bytes);
  return bytes;
}

void main(){
  group('ps0032 movement',(){
    test('encodes client CHARACTER_MOVE exactly',(){
      final bytes=encodeCharacterMoveBody(
        angle:3,run:true,x:580.25,y:78.5,z:1761.75,
      );
      expect(bytes.length,15);
      final d=ByteData.sublistView(bytes);
      expect(d.getUint16(0,Endian.little),3);
      expect(bytes[2],1);
      expect(d.getFloat32(3,Endian.little),closeTo(580.25,1e-5));
      expect(d.getFloat32(7,Endian.little),closeTo(78.5,1e-5));
      expect(d.getFloat32(11,Endian.little),closeTo(1761.75,1e-5));
    });

    test('parses server CHARACTER_MOVE',(){
      final bytes=body(19,(d,b){
        d.setUint32(0,42,Endian.little);
        d.setUint16(4,5,Endian.little);
        b[6]=0;
        d.setFloat32(7,10.5,Endian.little);
        d.setFloat32(11,20.25,Endian.little);
        d.setFloat32(15,30.75,Endian.little);
      });
      final p=PsCharacterMove.parse(PsPacket(PsPacketType.characterMove,bytes));
      expect(p.globalId,42);expect(p.angle,5);expect(p.motion,0);
      expect(p.x,closeTo(10.5,1e-5));expect(p.y,closeTo(20.25,1e-5));expect(p.z,closeTo(30.75,1e-5));
    });

    test('parses NPC move and leave',(){
      final bytes=body(17,(d,b){
        d.setUint32(0,111,Endian.little);b[4]=1;
        d.setFloat32(5,563.8,Endian.little);
        d.setFloat32(9,77.8,Endian.little);
        d.setFloat32(13,1759.4,Endian.little);
      });
      final p=PsNpcMove.parse(PsPacket(PsPacketType.mapNpcMove,bytes));
      expect(p.globalId,111);expect(p.motion,1);
      expect(p.x,closeTo(563.8,1e-3));expect(p.z,closeTo(1759.4,1e-3));
      final leave=body(4,(d,b)=>d.setUint32(0,111,Endian.little));
      expect(parseActorLeave(PsPacket(PsPacketType.mapNpcLeave,leave)),111);
    });

    test('parses mob move and leave',(){
      final bytes=body(13,(d,b){
        d.setUint32(0,375,Endian.little);b[4]=0;
        d.setFloat32(5,639.29,Endian.little);
        d.setFloat32(9,1712.02,Endian.little);
      });
      final p=PsMobMove.parse(PsPacket(PsPacketType.mobMove,bytes));
      expect(p.globalId,375);expect(p.motion,0);
      expect(p.x,closeTo(639.29,1e-3));expect(p.z,closeTo(1712.02,1e-3));
      final leave=body(4,(d,b)=>d.setUint32(0,375,Endian.little));
      expect(parseActorLeave(PsPacket(PsPacketType.mobLeave,leave)),375);
    });
  });
}
