import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/formats.dart';

void main(){
  test('decodes VAni mesh frames and triangle layout',(){
    final vani=readVani(_fixture(),'test.vani');
    expect(vani.frameCount,2);
    expect(vani.meshes,hasLength(1));
    final mesh=vani.meshes.single;
    expect(mesh.texture,'grass.dds');
    expect(mesh.indices,[0,1,2]);
    expect(mesh.vertices,3);
    expect(mesh.frameCount,2);
    expect(mesh.positions[0][0],closeTo(0,1e-6));
    expect(mesh.positions[1][0],closeTo(.5,1e-6));
    expect(mesh.positions[1][7],closeTo(1,1e-6));
    final frame=mesh.frame(1,'test.vani');
    expect(frame.triangles,1);
    expect(frame.positions[0],closeTo(.5,1e-6));
  });
}

Uint8List _fixture(){
  final out=BytesBuilder(copy:false);
  void u16(int v){final b=ByteData(2)..setUint16(0,v,Endian.little);out.add(b.buffer.asUint8List());}
  void u32(int v){final b=ByteData(4)..setUint32(0,v,Endian.little);out.add(b.buffer.asUint8List());}
  void i32(int v){final b=ByteData(4)..setInt32(0,v,Endian.little);out.add(b.buffer.asUint8List());}
  void f32(double v){final b=ByteData(4)..setFloat32(0,v,Endian.little);out.add(b.buffer.asUint8List());}
  void vec(double x,double y,double z){f32(x);f32(y);f32(z);}
  void str(String s){final raw=utf8.encode(s);u32(raw.length);out.add(raw);}
  void vertex(double x,double y,double z,double u,double v){
    vec(x,y,z);vec(0,1,0);i32(-1);f32(u);f32(v);
  }

  vec(0,0,0);f32(4);
  vec(-1,-1,-1);vec(1,2,1);
  u32(1); // mesh count
  u32(2); // frame count
  i32(0);

  str('grass.dds');
  u32(1);u16(0);u16(1);u16(2);
  u32(3);
  vertex(0,0,0,0,0);
  vertex(1,0,0,1,0);
  vertex(0,1,0,0,1);
  vertex(.5,0,0,0,0);
  vertex(1.5,0,0,1,0);
  vertex(.5,1,0,0,1);

  vec(-1,-1,-1);vec(2,2,1);
  i32(0);
  return out.takeBytes();
}
