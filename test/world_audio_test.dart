import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/formats.dart';

void main() {
  test('decodes WLD music zones and ambient sound effects exactly', () {
    final w = WorldData.parse(_wldAudioFixture(), 'audio.wld');

    expect(w.musicNames, ['music/test.wav']);
    expect(w.musicZones, hasLength(1));
    expect(w.musicZones.single.soundId, 0);
    expect(w.musicZones.single.contains(5, 1, 5), isTrue);
    expect(w.musicZones.single.contains(15, 1, 5), isFalse);

    expect(w.soundEffectNames, ['ambient/test.wav']);
    expect(w.soundZones, hasLength(1));
    expect(w.soundZones.single.identifiers, [7]);
    expect(w.soundZones.single.contains(2, 1, 2), isTrue);

    expect(w.soundEffects, hasLength(1));
    expect(w.soundEffects.single.soundId, 0);
    expect(w.soundEffects.single.center.x, closeTo(4, 1e-6));
    expect(w.soundEffects.single.radius, closeTo(6, 1e-6));
    expect(w.soundEffects.single.contains(7, 1, 4), isTrue);
    expect(w.soundEffects.single.contains(20, 1, 4), isFalse);
  });
}

Uint8List _wldAudioFixture() {
  final out = BytesBuilder(copy: false);

  void u32(int value) {
    final b = ByteData(4)..setUint32(0, value, Endian.little);
    out.add(b.buffer.asUint8List());
  }

  void i32(int value) {
    final b = ByteData(4)..setInt32(0, value, Endian.little);
    out.add(b.buffer.asUint8List());
  }

  void f32(double value) {
    final b = ByteData(4)..setFloat32(0, value, Endian.little);
    out.add(b.buffer.asUint8List());
  }

  void vec(double x, double y, double z) {
    f32(x);
    f32(y);
    f32(z);
  }

  void fixed(String value, int length) {
    final b = Uint8List(length);
    final raw = utf8.encode(value);
    final n=raw.length<length?raw.length:length-1;
    b.setRange(0, n, raw);
    out.add(b);
  }

  void namesAndCoordinatesEmpty() {
    u32(0);
    u32(0);
  }

  out.add([0x46, 0x4c, 0x44, 0x00]); // FLD\0
  u32(2); // minimum valid map size
  out.add(Uint8List(8)); // 4 height samples
  out.add(Uint8List(4)); // 4 texture-map samples
  u32(0); // terrain layers
  fixed('', 256); // inner layout

  for (var i = 0; i < 7; i++) {
    namesAndCoordinatesEmpty();
  }

  u32(0); // MAni names
  u32(0); // MAni coordinates
  fixed('', 256); // effect file
  u32(0); // effects
  i32(0);
  i32(0);
  i32(0);

  namesAndCoordinatesEmpty(); // Object

  u32(1);
  fixed('music/test.wav', 256);
  u32(1);
  vec(0, -2, 0);
  vec(10, 4, 10);
  f32(9);
  i32(0);
  i32(0);

  u32(1);
  fixed('ambient/test.wav', 256);

  u32(1);
  vec(0, -2, 0);
  vec(8, 4, 8);
  u32(1);
  i32(7);

  u32(1);
  i32(0);
  vec(4, 1, 4);
  f32(6);

  u32(0); // unknown bounding boxes
  u32(0); // portals
  u32(0); // spawns
  u32(0); // named areas
  i32(0); // NPC rows

  fixed('', 256); // sky
  fixed('', 256); // clouds 1
  fixed('', 256); // clouds 2

  vec(0, 0, 0);
  vec(0, 0, 0);
  vec(.1, .2, .3);
  f32(50);
  f32(500);

  return out.takeBytes();
}
