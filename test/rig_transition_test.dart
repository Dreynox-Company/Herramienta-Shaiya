import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' as v;
import 'package:herramienta_shaiya/core/formats.dart';
import 'package:herramienta_shaiya/core/rig_anchors.dart';
import 'package:herramienta_shaiya/core/flight_transition.dart';

void main() {
  test(
    'surface socket follows original weighted vertices, not bounding height',
    () {
      final mesh = MeshData(
        Float32List.fromList([-1, 1, -1, 1, 1, -1, 0, 1, 1]),
        Float32List(9),
        Float32List(6),
        Uint16List.fromList([0, 1, 2]),
        Uint8List.fromList([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        Float32List.fromList([1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]),
        [v.Matrix4.identity()],
        'synthetic',
      );
      final seat = SurfaceAnchor(
        mesh,
        [0, 1, 2],
        [.25, .25, .5],
        0,
        v.Quaternion.identity(),
      );
      expect(seat.position([v.Matrix4.identity()]).storage, [0, 1, 0]);
      final breath = v.Matrix4.identity()
        ..translateByVector3(v.Vector3(.03, .11, -.04));
      expect(
        (seat.position([breath]) - v.Vector3(.03, 1.11, -.04)).length,
        lessThan(1e-6),
      );
    },
  );
  test(
    'rider pelvis equals the animated saddle under pitch, roll and breathing',
    () {
      for (var i = 0; i < 200; i++) {
        final seat = v.Vector3(.03 * i, .2 + i * .002, -.08);
        final q = v.Quaternion.euler(.04, .02 * i, .13);
        final pelvis = v.Vector3(.05, 1.3 + i * .001, -.04);
        final m = seatedTransform(seat, q, pelvis, height: .06, forward: .1);
        expect(
          (m.transformed3(pelvis) - (seat + v.Vector3(0, .06, .1))).length,
          lessThan(1e-9),
        );
      }
    },
  );
  for (final fps in [30, 60, 144]) {
    test(
      'flight descent is continuous and grounded before queued attack at $fps Hz',
      () {
        final f = FlightTransition();
        for (var i = 0; i < fps * 3; i++) {
          f.step(1 / fps, eligible: true, inCombat: false, hoverHeight: .38);
        }
        expect(f.height, closeTo(.38, .005));
        f.queue('mob-2');
        final before = f.height;
        expect(f.height, before);
        var last = f.height;
        for (var i = 0; i < fps * 2; i++) {
          f.step(1 / fps, eligible: true, inCombat: false, hoverHeight: .38);
          expect((f.height - last).abs(), lessThanOrEqualTo(1.5 / fps + .0001));
          last = f.height;
          expect(f.wantsFlight, false);
        }
        expect(f.grounded, true);
        expect(f.pendingTarget, 'mob-2');
        f.cancel();
        for (var i = 0; i < fps * 2; i++) {
          f.step(1 / fps, eligible: true, inCombat: true, hoverHeight: .38);
        }
        expect(f.height, 0);
        expect(f.wantsFlight, false);
      },
    );
  }
  test(
    'stale landing request expires and disabling wings lands without a snap',
    () {
      final f = FlightTransition();
      for (var i = 0; i < 180; i++) {
        f.step(1 / 60, eligible: true, inCombat: false, hoverHeight: .6);
      }
      f.queue('removed');
      for (var i = 0; i < 200; i++) {
        f.step(1 / 60, eligible: false, inCombat: false, hoverHeight: .6);
      }
      expect(f.pendingTarget, null);
      expect(f.grounded, true);
      f.step(double.nan, eligible: true, inCombat: false, hoverHeight: 1);
      expect(f.height, 0);
    },
  );
}
