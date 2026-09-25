import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' as v;
import 'package:herramienta_shaiya/core/formats.dart';
import 'package:herramienta_shaiya/core/extra_motion.dart';
import 'package:herramienta_shaiya/core/mounted_motion.dart';

import '../tool/prepare_mounted_supplement.dart' as gen;
import 'extra_motion_test.dart' as fixture;

ClipData synthetic(List<int> parents, {bool attack = false}) => ClipData(
  'synthetic',
  1,
  List.generate(
    parents.length,
    (i) => BoneTrack(
      parents[i],
      v.Matrix4.identity(),
      [0, .5, 1],
      [
        v.Quaternion.identity(),
        v.Quaternion.axisAngle(v.Vector3(0, 1, 0), attack ? .8 : 0),
        v.Quaternion.identity(),
      ],
      [0],
      [v.Vector3(0, i * .2 + (attack ? 10 : 0), 0)],
    ),
  ),
);

void main() {
  test(
    'mounted families do not confuse claws, dual weapons or daggers with swords',
    () {
      final expected = <int, String>{
        1: 'mounted_sword',
        3: 'mounted_sword',
        7: 'mounted_sword',
        2: 'mounted_twohand',
        4: 'mounted_twohand',
        8: 'mounted_twohand',
        5: 'mounted_dual',
        6: 'mounted_spear',
        9: 'mounted_reverse_dagger',
        10: 'mounted_dagger',
        11: 'mounted_javelin',
        12: 'mounted_staff',
        13: 'mounted_bow',
        14: 'mounted_crossbow',
        15: 'mounted_claws',
      };
      for (final e in expected.entries) {
        expect(mountedMotionKey(e.key), e.value);
        expect(mountedMotionKeys, contains(e.value));
      }
      for (final family in [0, 19, 34, 99]) {
        expect(mountedMotionKey(family), isNull);
      }
    },
  );
  test(
    'every supported mounted key receives the same integrity validation',
    () {
      final m = fixture.manifest();
      final clips = (m['profiles'] as List).first['clips'] as Map;
      for (final key in mountedMotionKeys) {
        clips[key] = Map<String, String>.from(clips['hover'] as Map);
      }
      final data = ExtraMotionLibrary.decode(fixture.encode(m));
      expect(data.profiles['humf']!.mounted.length, mountedMotionKeys.length);
      (clips['mounted_claws'] as Map)['sha256'] = '0' * 64;
      expect(
        () => ExtraMotionLibrary.decode(fixture.encode(m)),
        throwsFormatException,
      );
    },
  );
  test(
    'body normalization only removes proven independent trailing hierarchies',
    () {
      final body = [-1, 0, 1, 2, 1];
      expect(gen.bodyClip(synthetic([...body, -1, 5]), body)!.bones.length, 5);
      expect(gen.bodyClip(synthetic([...body, 2]), body), isNull);
      expect(gen.bodyClip(synthetic([-1, 0, 0, 2, 1]), body), isNull);
      expect(gen.bodyClip(synthetic([-1, 0]), body), isNull);
    },
  );
  test(
    'mounted composition freezes lower-body, rejects ground root motion and closes its seam',
    () {
      final parents = [-1, 0, 1, 2, 1];
      final seat = synthetic(parents),
          attack = synthetic(parents, attack: true);
      final result = ClipData.parse(gen.compose(seat, attack, 2), 'composed');
      final initial = seat.pose(0);
      double movement = 0;
      for (var k = 0; k <= 60; k++) {
        final pose = result.pose(k / 60, loop: false);
        for (final b in [0, 1, 4]) {
          for (var n = 0; n < 16; n++) {
            expect(pose[b].storage[n], closeTo(initial[b].storage[n], 1e-6));
          }
        }
        if (k == 0 || k == 60) {
          for (var b = 0; b < parents.length; b++) {
            for (var n = 0; n < 16; n++) {
              expect(pose[b].storage[n], closeTo(initial[b].storage[n], 1e-6));
            }
          }
        }
        movement = math.max(
          movement,
          (pose[3].storage[0] - initial[3].storage[0]).abs(),
        );
      }
      expect(movement, greaterThan(.1));
    },
  );
}
