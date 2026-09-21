import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/formats.dart';

class W {
  final BytesBuilder b=BytesBuilder();
  void i32(int v){final d=ByteData(4)..setInt32(0,v,Endian.little);b.add(d.buffer.asUint8List());}
  void u32(int v){final d=ByteData(4)..setUint32(0,v,Endian.little);b.add(d.buffer.asUint8List());}
  void u16(int v){final d=ByteData(2)..setUint16(0,v,Endian.little);b.add(d.buffer.asUint8List());}
  void f(double v){final d=ByteData(4)..setFloat32(0,v,Endian.little);b.add(d.buffer.asUint8List());}
  void v(double x,double y,double z){f(x);f(y);f(z);}
  Uint8List done()=>b.takeBytes();
}

void main(){
  test('SVMAP parser exposes NPC, mobs, portal and light spawn',(){
    final w=W();
    w.i32(8);w.b.add(Uint8List(8));w.i32(4);
    w.i32(0);
    w.i32(1);
    w.v(0,0,0);w.v(10,2,10);w.i32(1);w.u32(44);w.u32(3);
    w.i32(1);w.i32(8);w.i32(12);w.i32(1);w.v(5,1,6);w.f(1.5);
    w.i32(1);w.v(7,0,8);w.i32(0);w.u16(1);w.u16(80);w.u32(2);w.v(100,3,120);
    w.i32(1);w.i32(1);w.i32(0);w.i32(0);w.v(570,70,1760);w.v(590,80,1780);
    w.i32(1);w.v(0,0,0);w.v(20,5,20);w.i32(10);w.i32(11);
    final map=SvmapData.parse(w.done(),'fixture');
    expect(map.npcs.single.type,8);
    expect(map.npcs.single.id,12);
    expect(map.mobAreas.single.mobs.single.id,44);
    expect(map.portals.single.targetMap,2);
    expect(map.spawns.single.faction,0);
    expect(map.spawns.single.center.x,580);
    expect(map.namedAreas.single.name1,10);
  });
}
