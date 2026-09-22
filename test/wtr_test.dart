import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/formats.dart';

void main(){
  test('decodes native WTR header and fixed texture list',(){
    final w=readWtr(_fixture(),'water.wtr');
    expect(w.unknown1,closeTo(12.5,1e-6));
    expect(w.unknown2,7);
    expect(w.unknown3,-3);
    expect(w.textures,['water01.dds','water02.tga']);
  });
}

Uint8List _fixture(){
  final out=BytesBuilder(copy:false);
  void u32(int v){final b=ByteData(4)..setUint32(0,v,Endian.little);out.add(b.buffer.asUint8List());}
  void i32(int v){final b=ByteData(4)..setInt32(0,v,Endian.little);out.add(b.buffer.asUint8List());}
  void f32(double v){final b=ByteData(4)..setFloat32(0,v,Endian.little);out.add(b.buffer.asUint8List());}
  void fixed(String value){
    final b=Uint8List(256),raw=utf8.encode(value);
    final n=raw.length<256?raw.length:255;
    b.setRange(0,n,raw);
    out.add(b);
  }
  f32(12.5);u32(7);i32(-3);u32(2);
  fixed('water01.dds');fixed('water02.tga');
  return out.takeBytes();
}
