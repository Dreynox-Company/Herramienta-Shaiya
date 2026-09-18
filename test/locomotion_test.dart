import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' as v;
import 'package:herramienta_shaiya/core/formats.dart';
import 'package:herramienta_shaiya/core/locomotion.dart';
import 'package:herramienta_shaiya/render/studio_scene.dart';

ClipData motion(String name, double lift) => ClipData(name, 1, [
  BoneTrack(
    -1,
    v.Matrix4.identity(),
    [0],
    [v.Quaternion.identity()],
    [0, 1],
    [v.Vector3.zero(), v.Vector3(0, lift, 0)],
  ),
]);
StudioScene exampleScene() {
  final s = StudioScene((_) {}), a = Actor();
  a.normal = motion('humf_000_normal.ANI', .01);
  a.idle = a.normal;
  a.walk = motion('humf_001_walk.ANI', 1);
  a.run = motion('humf_002_run.ANI', 2);
  a.play(a.normal!);
  s.character = a;
  return s;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Ground clip identity', () {
    final paths = [
      'human/humf_006_swnormal.ANI',
      'human/humf_007_swim.ANI',
      'human/humf_021_veh_br.ani',
      'human/humf_016_idle1.ani',
      'human/humf_002_run.ANI',
      'human/humf_001_walk.ANI',
      'human/humf_000_normal.ANI',
    ];
    test('standing never resolves swnormal regardless of catalog order', () {
      for (var k = 0; k < paths.length; k++) {
        expect(
          groundMotionCandidates([
            ...paths.skip(k),
            ...paths.take(k),
          ], GroundMotion.idle),
          [paths.last],
        );
      }
    });
    test('walking and running resolve exact clips', () {
      expect(groundMotionCandidates(paths, GroundMotion.walk), [paths[5]]);
      expect(groundMotionCandidates(paths, GroundMotion.run), [paths[4]]);
    });
    test('accept original Vail typo and female Panda stand', () {
      expect(
        groundMotionCandidates(['Vimm_000_nomal.ANI'], GroundMotion.idle),
        hasLength(1),
      );
      expect(
        groundMotionCandidates(['Pdbwf_000_stand.ANI'], GroundMotion.idle),
        hasLength(1),
      );
    });
    test('missing idle never falls back to water', () {
      expect(groundMotionCandidates(paths.take(2), GroundMotion.idle), isEmpty);
    });
    test('directory names do not affect clip identity', () {
      expect(
        groundMotionCandidates(['normal/humf_007_swim.ani'], GroundMotion.idle),
        isEmpty,
      );
    });
  });
  group('Input transitions', () {
    test('Shift alone stays at rest', () {
      final s = LocomotionTransitions();
      expect(s.update(x: 0, z: 0, running: true, blocked: false), isNull);
      expect(s.requested, GroundMotion.idle);
    });
    test('W, W Shift, W, release', () {
      final s = LocomotionTransitions();
      expect(
        s.update(x: 0, z: -1, running: false, blocked: false),
        GroundMotion.walk,
      );
      expect(
        s.update(x: 0, z: -1, running: true, blocked: false),
        GroundMotion.run,
      );
      expect(
        s.update(x: 0, z: -1, running: false, blocked: false),
        GroundMotion.walk,
      );
      expect(
        s.update(x: 0, z: 0, running: false, blocked: false),
        GroundMotion.idle,
      );
    });
    test('100 repeats do not rewind', () {
      final s = LocomotionTransitions();
      s.update(x: 0, z: -1, running: false, blocked: false);
      for (var i = 0; i < 100; i++) {
        expect(s.update(x: 0, z: -1, running: false, blocked: false), isNull);
      }
    });
    test('unlock and appearance changes reapply held key', () {
      final s = LocomotionTransitions();
      s.update(x: 0, z: -1, running: false, blocked: false);
      s.update(x: 0, z: -1, running: false, blocked: true);
      expect(
        s.update(x: 0, z: -1, running: false, blocked: false),
        GroundMotion.walk,
      );
      s.invalidate();
      expect(
        s.update(x: 0, z: -1, running: false, blocked: false),
        GroundMotion.walk,
      );
    });
    test('release during load returns to rest', () {
      final s = LocomotionTransitions();
      s.update(x: 0, z: -1, running: true, blocked: true);
      s.update(x: 0, z: 0, running: true, blocked: true);
      expect(
        s.update(x: 0, z: 0, running: true, blocked: false),
        GroundMotion.idle,
      );
    });
  });
  group('Scene pose and translation', () {
    late StudioScene s;
    setUp(() => s = exampleScene()..yaw = 0);
    tearDown(() => s.dispose());
    test('W changes bone pose as well as position', () {
      expect(s.character!.clip, same(s.character!.normal));
      s.setMovement(0, -1);
      s.tick(.1);
      expect(s.character!.clip, same(s.character!.walk));
      expect(s.character!.root.position.z, closeTo(-.2, 1e-6));
      expect(
        s.character!.world.first.storage[13],
        closeTo(.1 * (.1 / .18), 1e-6),
      );
      s.tick(.1);
      expect(s.character!.world.first.storage[13], closeTo(.2, 1e-6));
      expect(s.character!.time, closeTo(.2, 1e-6));
    });
    test('Shift runs twice as fast and release walks', () {
      s.setMovement(0, -1, run: true);
      s.tick(.1);
      expect(s.character!.clip, same(s.character!.run));
      expect(s.character!.root.position.z, closeTo(-.4, 1e-6));
      s.setMovement(0, -1);
      s.tick(.1);
      expect(s.character!.clip, same(s.character!.walk));
      expect(s.character!.root.position.z, closeTo(-.6, 1e-6));
    });
    test('releasing W stops even while Shift stays held', () {
      s.setMovement(0, -1, run: true);
      s.tick(.1);
      final z = s.character!.root.position.z;
      s.setMovement(0, 0, run: true);
      s.tick(.1);
      expect(s.character!.clip, same(s.character!.idle));
      expect(s.character!.root.position.z, z);
    });
    test('no walk clip means no invisible skating', () {
      s.character!.walk = null;
      s.setMovement(0, -1);
      s.tick(.1);
      expect(s.character!.root.position.z, 0);
    });
    test('W overrides paused swimming preview', () {
      s.character!.play(motion('humf_007_swim.ani', 5));
      s.character!.playing = false;
      s.setMovement(0, -1);
      s.tick(.1);
      expect(s.character!.clip, same(s.character!.walk));
      expect(s.character!.playing, isTrue);
      s.clearMovement();
      s.tick(.1);
      expect(s.character!.clip, same(s.character!.normal));
    });
    test('manual preview remains available at rest', () {
      final swim = motion('swim.ani', 5);
      s.character!.play(swim);
      s.tick(.1);
      expect(s.character!.clip, same(swim));
    });
    test('load lock blocks translation then resumes', () {
      s.busy = true;
      s.setMovement(0, -1);
      s.tick(.1);
      expect(s.character!.root.position.z, 0);
      s.busy = false;
      s.tick(.1);
      expect(s.character!.root.position.z, lessThan(0));
    });
    test('focus loss clears direction and Shift', () {
      s.setMovement(0, -1, run: true);
      s.clearMovement();
      s.tick(.1);
      expect(s.running, isFalse);
      expect(s.walkZ, 0);
      expect(s.character!.clip, same(s.character!.normal));
    });
    test('diagonals preserve total speed', () {
      s.setMovement(1, -1);
      s.tick(.1);
      final p = s.character!.root.position;
      expect(p.x * p.x + p.z * p.z, closeTo(.04, 1e-6));
    });
    test('held W keeps advancing clip time', () {
      for (var i = 0; i < 100; i++) {
        s.setMovement(0, -1);
        s.tick(.04);
      }
      expect(s.character!.time, closeTo(4, 1e-5));
    });
  });
}
