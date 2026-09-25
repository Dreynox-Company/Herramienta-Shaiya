import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' as v;
import 'package:herramienta_shaiya/core/wing_native_transform.dart';

// Independent scalar evaluation of the native ROW-vector operations recovered
// from ps0032 0x525440, not a second invocation of the implementation helper.
v.Vector3 nativePoint(v.Vector3 point, List<double> angles, v.Vector3 offset) {
  const k = 0.01745329238474369;
  var x = point.x + offset.x;
  var y = point.y + offset.y;
  var z = point.z - offset.z;
  var a = angles[0] * k;
  var nextY = y * math.cos(a) - z * math.sin(a);
  z = y * math.sin(a) + z * math.cos(a);
  y = nextY;
  a = angles[1] * k;
  var nextX = x * math.cos(a) + z * math.sin(a);
  z = -x * math.sin(a) + z * math.cos(a);
  x = nextX;
  a = angles[2] * k;
  nextX = x * math.cos(a) - y * math.sin(a);
  nextY = x * math.sin(a) + y * math.cos(a);
  return v.Vector3(nextX, nextY, z);
}

void main() {
  for (final angles in <List<double>>[
    [170, 0, 90],
    [0, 0, 90],
    [-90, 35, 170],
    [32, -67, 119],
  ]) {
    test('native row-to-column composition $angles', () {
      final offset = v.Vector3(.12, .05, -.18);
      final matrix = nativeWingLocalTransform(
        rotX: angles[0],
        rotY: angles[1],
        rotZ: angles[2],
        leftRight: offset.x,
        upDown: offset.y,
        frontBack: offset.z,
      );
      for (final point in [
        v.Vector3.zero(),
        v.Vector3(1, 0, 0),
        v.Vector3(0, 1, 0),
        v.Vector3(0, 0, 1),
        v.Vector3(.3, -.4, .7),
      ]) {
        final expected = nativePoint(point, angles, offset);
        expect(
          matrix.transformed3(point).distanceTo(expected),
          lessThan(1e-10),
        );
      }
      expect(matrix.determinant(), closeTo(1, 1e-10));
    });
  }
  test('front/back follows native negative Z before bone rotation', () {
    final matrix = nativeWingLocalTransform(
      rotX: 0,
      rotY: 0,
      rotZ: 0,
      leftRight: .1,
      upDown: .2,
      frontBack: .3,
    );
    expect(matrix.getTranslation().storage, orderedEquals([.1, .2, -.3]));
  });
  test(
    'screenshot regression: Human 170/0/90 is not the old Rx Ry Rz order',
    () {
      final matrix = nativeWingLocalTransform(
        rotX: 170,
        rotY: 0,
        rotZ: 90,
        leftRight: 0,
        upDown: 0,
        frontBack: 0,
      );
      final direction = matrix.transformed3(v.Vector3(1, 0, 0));
      expect(direction.y, greaterThan(.999));
      final wrong =
          v.Matrix4.rotationX(170 * math.pi / 180) *
          v.Matrix4.rotationZ(math.pi / 2);
      expect(wrong.transformed3(v.Vector3(1, 0, 0)).y, lessThan(-.98));
    },
  );
  test(
    'local mirror remains separate and never changes translation semantics',
    () {
      final matrix = nativeWingLocalTransform(
        rotX: 0,
        rotY: 0,
        rotZ: 0,
        leftRight: .1,
        upDown: .2,
        frontBack: .3,
        scaleX: -2,
      );
      expect(matrix.transformed3(v.Vector3(1, 0, 0)).x, closeTo(-1.9, 1e-10));
      expect(matrix.getTranslation().y, .2);
      expect(matrix.determinant(), -2);
    },
  );
  test('nonfinite and singular inputs fail explicitly', () {
    expect(
      () => nativeWingLocalTransform(
        rotX: double.nan,
        rotY: 0,
        rotZ: 0,
        leftRight: 0,
        upDown: 0,
        frontBack: 0,
      ),
      throwsFormatException,
    );
    expect(
      () => nativeWingLocalTransform(
        rotX: 0,
        rotY: 0,
        rotZ: 0,
        leftRight: 0,
        upDown: 0,
        frontBack: 0,
        scaleY: 0,
      ),
      throwsFormatException,
    );
  });
}
