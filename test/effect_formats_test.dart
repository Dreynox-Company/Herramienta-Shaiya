import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/formats.dart';

void main(){
  test('decodes native 3DE effect mesh and animation frames',(){
    final m=read3de(_threeDeFixture(),'impact.3de');
    expect(m.texture,'impact.dds');
    expect(m.vertices,3);
    expect(m.triangles,1);
    expect(m.indices,[0,1,2]);
    expect(m.maxKeyframe,30);
    expect(m.frames,hasLength(1));
    expect(m.frames.single.keyframe,15);
    expect(m.frames.single.positions[0],closeTo(.5,1e-6));
    expect(m.frames.single.uv[5],closeTo(1,1e-6));
  });

  test('decodes EFT mesh texture effect and sequence metadata',(){
    final e=readEft(_eftFixture(),'attack.EFT');
    expect(e.format,EftFormat.ef3);
    expect(e.meshes,['impact.3de']);
    expect(e.textures,['impact.dds']);
    expect(e.effects,hasLength(1));
    final effect=e.effects.single;
    expect(effect.name,'hit');
    expect(effect.meshIndex,0);
    expect(effect.position.x,closeTo(1,1e-6));
    expect(effect.position.y,closeTo(2,1e-6));
    expect(effect.textureIds,[0]);
    expect(effect.rotations,hasLength(1));
    expect(effect.rotations.single.time,closeTo(.25,1e-6));
    expect(effect.opacityFrames.map((f)=>f.opacity),[0.0,1.0]);
    expect(e.sequences,hasLength(1));
    expect(e.sequences.single.name,'attack');
    expect(e.sequences.single.records.single.effectId,0);
    expect(e.sequences.single.records.single.time,closeTo(.1,1e-6));
  });
}

Uint8List _threeDeFixture(){
  final out=BytesBuilder(copy:false);
  void u16(int v){final b=ByteData(2)..setUint16(0,v,Endian.little);out.add(b.buffer.asUint8List());}
  void u32(int v){final b=ByteData(4)..setUint32(0,v,Endian.little);out.add(b.buffer.asUint8List());}
  void i32(int v){final b=ByteData(4)..setInt32(0,v,Endian.little);out.add(b.buffer.asUint8List());}
  void f32(double v){final b=ByteData(4)..setFloat32(0,v,Endian.little);out.add(b.buffer.asUint8List());}
  void vec(double x,double y,double z){f32(x);f32(y);f32(z);}
  void str(String s){final b=utf8.encode(s);u32(b.length);out.add(b);}
  void vertex(double x,double y,double z,double u,double v){
    vec(x,y,z);i32(-1);f32(u);f32(v);
  }
  str('impact.dds');
  u32(3);
  vertex(0,0,0,0,0);vertex(1,0,0,1,0);vertex(0,1,0,0,1);
  u32(1);u16(0);u16(1);u16(2);
  i32(30);
  u32(1);
  i32(15);
  vec(.5,0,0);f32(0);f32(0);
  vec(1.5,0,0);f32(1);f32(0);
  vec(.5,1,0);f32(0);f32(1);
  return out.takeBytes();
}

Uint8List _eftFixture(){
  final out=BytesBuilder(copy:false);
  void u32(int v){final b=ByteData(4)..setUint32(0,v,Endian.little);out.add(b.buffer.asUint8List());}
  void i32(int v){final b=ByteData(4)..setInt32(0,v,Endian.little);out.add(b.buffer.asUint8List());}
  void f32(double v){final b=ByteData(4)..setFloat32(0,v,Endian.little);out.add(b.buffer.asUint8List());}
  void vec(double x,double y,double z){f32(x);f32(y);f32(z);}
  void quat(double x,double y,double z,double w){f32(x);f32(y);f32(z);f32(w);}
  void str(String s){final b=utf8.encode(s);u32(b.length);out.add(b);}

  out.add(utf8.encode('EF3'));
  u32(1);str('impact.3de');
  u32(1);str('impact.dds');

  u32(1);
  str('hit');
  for(var i=0;i<8;i++)i32(0);
  i32(0); // mesh index
  i32(0);
  for(var i=0;i<8;i++)f32(0);
  vec(0,0,0);vec(0,0,0);vec(1,2,3);vec(0,0,0);vec(0,0,0);
  i32(0);i32(0);i32(0);
  vec(0,0,0);
  f32(0);i32(0);i32(0);f32(0);i32(0);
  f32(0);f32(0); // EF3 extras

  u32(1);
  quat(0,0,0,1);f32(.25);

  u32(2);
  f32(0);f32(0);
  f32(1);f32(.5);

  u32(1);
  f32(0);f32(0);f32(.5);

  i32(0);i32(0);i32(0);i32(0);

  u32(1);i32(0);

  u32(1);
  str('attack');
  u32(1);
  i32(0);f32(.1);

  return out.takeBytes();
}
