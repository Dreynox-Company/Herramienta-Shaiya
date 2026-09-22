import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/formats.dart';

void main(){
  test('decodes native MAni rotation controls',(){
    final mani=readMani(_maniFixture(),'rotate.mani');
    expect(mani.version,0x21);
    expect(mani.rotationEnabled,isTrue);
    expect(mani.rotationAxis.x,closeTo(0,1e-6));
    expect(mani.rotationAxis.y,closeTo(1,1e-6));
    expect(mani.rotationAxis.z,closeTo(0,1e-6));
    expect(mani.animationSpeed,closeTo(.75,1e-6));
  });

  test('WLD preserves MAni building bindings',(){
    final w=WorldData.parse(_wldFixture(),'mani.wld');
    expect(w.maniBindings,hasLength(1));
    final binding=w.maniBindings.single;
    expect(binding.buildingIndex,0);
    expect(binding.asset,'windmill.mani');
    expect(binding.position.x,closeTo(10,1e-6));
    expect(binding.forward.z,closeTo(1,1e-6));
    expect(binding.up.y,closeTo(1,1e-6));
  });
}

Uint8List _maniFixture(){
  final out=BytesBuilder(copy:false);
  void i32(int v){final b=ByteData(4)..setInt32(0,v,Endian.little);out.add(b.buffer.asUint8List());}
  void u16(int v){final b=ByteData(2)..setUint16(0,v,Endian.little);out.add(b.buffer.asUint8List());}
  void f32(double v){final b=ByteData(4)..setFloat32(0,v,Endian.little);out.add(b.buffer.asUint8List());}
  void vec(double x,double y,double z){f32(x);f32(y);f32(z);}

  i32(0x21);i32(0);
  vec(0,0,0);
  f32(0);f32(0);f32(0);
  i32(0);i32(0);
  vec(0,0,0);
  f32(0);f32(0);
  i32(1);
  vec(0,1,0);
  f32(.75);
  u16(0);u16(0);
  vec(0,0,0);
  f32(0);f32(0);
  i32(0);
  return out.takeBytes();
}

Uint8List _wldFixture(){
  final out=BytesBuilder(copy:false);
  void u32(int v){final b=ByteData(4)..setUint32(0,v,Endian.little);out.add(b.buffer.asUint8List());}
  void i32(int v){final b=ByteData(4)..setInt32(0,v,Endian.little);out.add(b.buffer.asUint8List());}
  void f32(double v){final b=ByteData(4)..setFloat32(0,v,Endian.little);out.add(b.buffer.asUint8List());}
  void vec(double x,double y,double z){f32(x);f32(y);f32(z);}
  void fixed(String value,int length){
    final b=Uint8List(length),raw=utf8.encode(value);
    final n=raw.length<length?raw.length:length-1;
    b.setRange(0,n,raw);out.add(b);
  }
  void emptyCategory(){u32(0);u32(0);}

  out.add([0x46,0x4c,0x44,0x00]);
  u32(2);
  out.add(Uint8List(8));
  out.add(Uint8List(4));
  u32(0);
  fixed('',256);
  for(var i=0;i<7;i++)emptyCategory();

  u32(1);fixed('windmill.mani',256);
  u32(1);
  i32(0);i32(0);
  vec(10,2,20);vec(0,0,1);vec(0,1,0);

  fixed('',256);
  u32(0);
  i32(0);i32(0);i32(0);
  emptyCategory();

  u32(0);u32(0);
  u32(0);u32(0);
  u32(0);
  u32(0);
  u32(0);
  u32(0);
  u32(0);
  i32(0);

  fixed('',256);fixed('',256);fixed('',256);
  vec(0,0,0);vec(0,0,0);vec(0,0,0);
  f32(0);f32(0);
  return out.takeBytes();
}
