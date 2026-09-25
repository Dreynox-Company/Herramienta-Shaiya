import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' as v;
import 'package:herramienta_shaiya/core/formats.dart';
import 'package:herramienta_shaiya/core/motion_catalog.dart';

class Writer {
  final BytesBuilder data = BytesBuilder();
  void u(int n) {
    final b = ByteData(4)..setUint32(0, n, Endian.little);
    data.add(b.buffer.asUint8List());
  }

  void i(int n) {
    final b = ByteData(4)..setInt32(0, n, Endian.little);
    data.add(b.buffer.asUint8List());
  }

  void f(double n) {
    final b = ByteData(4)..setFloat32(0, n, Endian.little);
    data.add(b.buffer.asUint8List());
  }

  void short(int n) {
    final b = ByteData(2)..setUint16(0, n, Endian.little);
    data.add(b.buffer.asUint8List());
  }

  void mat({bool bad = false}) {
    for (var k = 0; k < 16; k++) {
      f(bad ? double.nan : (k % 5 == 0 ? 1 : 0));
    }
  }
}

Uint8List mesh({bool usedInvalid = false, bool invalidPosition = false}) {
  final b = Writer();
  b.u(0);
  b.u(2);
  b.mat(bad: usedInvalid);
  b.mat(bad: true);
  b.u(3);
  for (final p in [
    [0.0, 0.0, 0.0],
    [1.0, 0.0, 0.0],
    [0.0, 1.0, 0.0],
  ]) {
    b.f(invalidPosition ? double.nan : p[0]);
    b.f(p[1]);
    b.f(p[2]);
    b.f(1);
    b.data.add([0, 1, 0, 0]);
    b.f(double.nan);
    b.f(0);
    b.f(1);
    b.f(0);
    b.f(0);
  }
  b.u(1);
  b.short(0);
  b.short(1);
  b.short(2);
  return b.data.toBytes();
}

void main() {
  test(
    'normales dañadas se derivan de geometría válida, sin inventar posiciones',
    () {
      final m = MeshData.skinned(mesh(), 'prueba.3dc');
      expect(m.positions, [0, 0, 0, 1, 0, 0, 0, 1, 0]);
      expect(m.normals, [0, 0, 1, 0, 0, 1, 0, 0, 1]);
      expect(m.repairs.length, 2);
    },
  );
  test('una matriz inválida utilizada por vértices no se acepta', () {
    expect(
      () => MeshData.skinned(mesh(usedInvalid: true), 'mala.3dc'),
      throwsFormatException,
    );
  });
  test('las posiciones inválidas no se reparan arbitrariamente', () {
    expect(
      () => MeshData.skinned(mesh(invalidPosition: true), 'mala.3dc'),
      throwsFormatException,
    );
  });
  test(
    'ANI con claves completas no depende de una matriz auxiliar singular',
    () {
      final b = Writer();
      b.i(0);
      b.i(30);
      b.short(1);
      b.i(-1);
      for (var i = 0; i < 16; i++) {
        b.f(0);
      }
      b.u(1);
      b.i(0);
      b.f(0);
      b.f(0);
      b.f(0);
      b.f(1);
      b.u(1);
      b.i(0);
      b.f(0);
      b.f(2);
      b.f(0);
      final clip = ClipData.parse(b.data.toBytes(), 'con_claves.ani');
      expect(clip.pose(0).first.storage[13], 2);
    },
  );
  test('el anclaje vacío no se coloca en la raíz del personaje', () {
    expect(
      Attachment(0, v.Vector3.zero(), v.Quaternion.identity()).defined,
      isFalse,
    );
    expect(
      Attachment(21, v.Vector3.zero(), v.Quaternion.identity()).defined,
      isTrue,
    );
  });
  test(
    'las familias eligen ataques propios, no el primer ANI del catálogo',
    () {
      expect(attackMotions(1), [35, 36, 37, 38]);
      expect(attackMotions(5), [42, 43, 44, 45]);
      expect(attackMotions(13), [31]);
      expect(attackMotions(12), [60, 61]);
      expect(damageMotion(5), 46);
      expect(attackMotions(9), [65, 66, 67, 68]);
      expect(attackMotions(10), [79, 80, 81, 82]);
      expect(attackMotions(15), [72, 73, 74, 75]);
      expect(motionIndex('humf_001_walk.ani'), 1);
    },
  );
}
