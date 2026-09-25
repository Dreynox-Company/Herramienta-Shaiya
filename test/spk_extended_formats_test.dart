import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/data/spk_source.dart';

class Writer {
  final BytesBuilder _b = BytesBuilder(copy: false);

  void u16(int v) {
    final d = ByteData(2)..setUint16(0, v, Endian.little);
    _b.add(d.buffer.asUint8List());
  }

  void u32(int v) {
    final d = ByteData(4)..setUint32(0, v, Endian.little);
    _b.add(d.buffer.asUint8List());
  }

  void i32(int v) {
    final d = ByteData(4)..setInt32(0, v, Endian.little);
    _b.add(d.buffer.asUint8List());
  }

  void i16(int v) {
    final d = ByteData(2)..setInt16(0, v, Endian.little);
    _b.add(d.buffer.asUint8List());
  }

  void f32(double v) {
    final d = ByteData(4)..setFloat32(0, v, Endian.little);
    _b.add(d.buffer.asUint8List());
  }

  void vec([double x = 0, double y = 0, double z = 0]) {
    f32(x);
    f32(y);
    f32(z);
  }

  void str(String value) {
    final raw = latin1.encode(value);
    u32(raw.length);
    _b.add(raw);
  }

  void strFixed(String value, int length) {
    final raw = latin1.encode(value);
    if (raw.length > length) {
      throw ArgumentError.value(value, 'value', 'Cadena fija demasiado larga.');
    }
    final out = Uint8List(length);
    out.setRange(0, raw.length, raw);
    _b.add(out);
  }

  void zeros(int n) => _b.add(Uint8List(n));
  Uint8List take() => _b.takeBytes();
}

Uint8List mani() {
  final w = Writer();
  w.i32(0x21);
  w.i32(0);
  w.vec();
  w.f32(0);
  w.f32(0);
  w.f32(0);
  w.i32(0);
  w.i32(0);
  w.vec();
  w.f32(0);
  w.f32(0);
  w.i32(0);
  w.vec();
  w.f32(1);
  w.i16(0);
  w.i16(0);
  w.vec();
  w.f32(0);
  w.f32(0);
  w.i32(0);
  return w.take();
}

Uint8List wtr() {
  final w = Writer();
  w.f32(4);
  w.u32(0);
  w.i32(0);
  w.u32(1);
  // WTR stores each texture name in a fixed 256-byte legacy field.
  w.strFixed('water.dds', 256);
  return w.take();
}

Uint8List svmap() {
  final w = Writer();
  w.i32(8);
  w.zeros(8);
  w.i32(1);
  for (var i = 0; i < 6; i++) {
    w.u32(0);
  }
  return w.take();
}

void rigid(Writer w) {
  w.u32(3);
  for (var i = 0; i < 3; i++) {
    w.vec(i.toDouble(), 0, 0);
    w.vec(0, 1, 0);
    w.i32(0);
    w.f32(0);
    w.f32(0);
  }
  w.u32(1);
  w.u16(0);
  w.u16(1);
  w.u16(2);
}

Uint8List smod() {
  final w = Writer();
  w.vec();
  w.f32(1);
  w.vec(-1, -1, -1);
  w.vec(1, 1, 1);
  w.u32(1);
  w.str('stone.dds');
  rigid(w);
  w.vec(-1, -1, -1);
  w.vec(1, 1, 1);
  w.u32(0);
  return w.take();
}

Uint8List dg() {
  final w = Writer();
  w.vec(-1, -1, -1);
  w.vec(1, 1, 1);
  w.u32(1);
  // DG texture table uses fixed 256-byte legacy names.
  w.strFixed('dungeon.dds', 256);
  w.u32(0);
  w.i32(0);
  return w.take();
}

Uint8List vani() {
  final w = Writer();
  w.vec();
  w.f32(1);
  w.vec(-1, -1, -1);
  w.vec(1, 1, 1);
  w.u32(1);
  w.u32(1);
  w.i32(0);
  w.str('wing.dds');
  w.u32(1);
  w.u16(0);
  w.u16(1);
  w.u16(2);
  w.u32(3);
  for (var i = 0; i < 3; i++) {
    w.vec(i.toDouble(), 0, 0);
    w.vec(0, 1, 0);
    w.i32(-1);
    w.f32(0);
    w.f32(0);
  }
  w.vec(-1, -1, -1);
  w.vec(1, 1, 1);
  w.i32(0);
  return w.take();
}

void main() {
  test(
    'SPK extended detector recognizes formats learned from Flutter game work',
    () {
      expect(mani().length, 108);
      expect(SpkArchiveSource.detectFormat(mani()), 'MANI');
      expect(SpkArchiveSource.detectFormat(wtr()), 'WTR');
      expect(SpkArchiveSource.detectFormat(svmap()), 'SVMAP');
      expect(SpkArchiveSource.detectFormat(vani()), 'VANI');
      expect(SpkArchiveSource.detectFormat(smod()), 'SMOD');
      expect(SpkArchiveSource.detectFormat(dg()), 'DG');
    },
  );

  test('extended formats receive stable extraction extensions', () {
    expect(SpkArchiveSource.extensionFor('MANI'), '.mani');
    expect(SpkArchiveSource.extensionFor('WTR'), '.wtr');
    expect(SpkArchiveSource.extensionFor('VANI'), '.vani');
    expect(SpkArchiveSource.extensionFor('SMOD'), '.smod');
    expect(SpkArchiveSource.extensionFor('DG'), '.dg');
    expect(SpkArchiveSource.extensionFor('SVMAP'), '.svmap');
  });

  test('nearby garbage does not become an extended Shaiya format', () {
    final garbage = Uint8List.fromList(
      List<int>.generate(160, (i) => i & 0xff),
    );
    expect(const {
      'MANI',
      'WTR',
      'VANI',
      'SMOD',
      'DG',
      'SVMAP',
    }, isNot(contains(SpkArchiveSource.detectFormat(garbage))));
  });
}
