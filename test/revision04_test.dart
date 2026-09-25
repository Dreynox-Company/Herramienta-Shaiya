import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' as v;
import 'package:herramienta_shaiya/core/pose_layers.dart';
import 'package:herramienta_shaiya/core/combat.dart';
import 'package:herramienta_shaiya/core/locomotion.dart';
import 'package:herramienta_shaiya/core/equipment_rules.dart';
import 'package:herramienta_shaiya/core/formats.dart';
import 'package:herramienta_shaiya/core/attachment_pose.dart';
import 'package:herramienta_shaiya/core/spatial_window.dart';
import 'package:herramienta_shaiya/core/world_resources.dart';
import 'package:herramienta_shaiya/core/body_coverage.dart';
import 'package:herramienta_shaiya/data/catalog.dart';

import 'body_coverage_test.dart' as body;
import 'core_test.dart' as core;
import 'locomotion_test.dart' as locomotion;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Combat guard state', () {
    test('equipping alone cannot activate combat guard', () {
      final c = Combat();
      expect(c.inGuard, false);
      expect(c.guardRemaining, 0);
    });
    test('returns from guard eight seconds after the last landed hit', () {
      final c = Combat()..counterattack = false;
      c.attack(1);
      for (var i = 0; i < 2; i++) {
        c.step(.25, 1);
      }
      expect(c.inGuard, true);
      for (var i = 0; i < 31; i++) {
        c.step(.25, 1);
      }
      expect(c.inGuard, true);
      c.step(.25, 1);
      expect(c.inGuard, false);
      expect(c.active, false);
    });
    test('new attack refreshes the activity window', () {
      final c = Combat()..counterattack = false;
      c.attack(1);
      for (var i = 0; i < 20; i++) {
        c.step(.25, 1);
      }
      c.attack(1);
      for (var i = 0; i < 20; i++) {
        c.step(.25, 1);
      }
      expect(c.inGuard, true);
    });
    test('reset and cancellation leave normal idle', () {
      final c = Combat();
      c.attack(1);
      expect(c.inGuard, true);
      c.cancelActions();
      expect(c.inGuard, false);
    });
    test('scene returns to normal rather than permanent weapon guard', () {
      final s = locomotion.exampleScene();
      s.character!.guard = locomotion.motion('guard', .01);
      s.refreshIdle();
      expect(s.character!.idle, s.character!.normal);
      s.combat.counterattack = false;
      s.combat.attack(1);
      s.refreshIdle();
      expect(s.character!.idle, s.character!.guard);
      s.combat.cancelActions();
      s.refreshIdle();
      expect(s.character!.idle, s.character!.normal);
      s.dispose();
    });
  });
  group('Class and weapon routing', () {
    test('archetype is not mistaken for a single class', () {
      expect(classesFor('humf').map((c) => c.id), ['fighter', 'defender']);
      expect(classesFor('humm').single, priest);
      expect(classesFor('vimm'), [pagan, oracle]);
      expect(classesFor('elmr'), [ranger, archer]);
    });
    test('metadata class flags override fallback families', () {
      const rule = ItemRule(2, 1, 0, {'defensefighter'});
      expect(rule.allows('human', fighter), false);
      expect(rule.allows('human', defender), true);
      expect(rule.allows('vile', guardian), false);
    });
    test('neutral and faction-specific records remain distinct', () {
      expect(
        const ItemRule(6, 12, 0, {'defensemage'}).allows('human', priest),
        true,
      );
      expect(
        const ItemRule(5, 12, 0, {'defensemage'}).allows('human', priest),
        false,
      );
      expect(
        const ItemRule(5, 12, 0, {'defensemage'}).allows('vile', oracle),
        true,
      );
    });
    test('all original running families use their dedicated action index', () {
      expect([1, 2, 5, 6, 9, 10, 11, 12, 13, 15].map(runningMotion), [
        40,
        29,
        47,
        54,
        70,
        84,
        58,
        63,
        33,
        77,
      ]);
    });
    test('scene selects weapon running without changing ordinary walk', () {
      final s = locomotion.exampleScene();
      final spear = locomotion.motion('humf_054_spear_run.ani', .4);
      s.character!.weaponRun = spear;
      expect(s.movementClip(GroundMotion.run), spear);
      expect(s.movementClip(GroundMotion.walk), s.character!.walk);
      s.dispose();
    });
    test('one handed weapons permit shields, dual and two-handed do not', () {
      WeaponRecord w(int f) => WeaponRecord(0, 'm', 't', 1, 'item/$f.itm', []);
      for (final f in [1, 3, 7, 9, 10]) {
        expect(permitsShield(w(f)), true);
      }
      for (final f in [2, 4, 5, 6, 8, 11, 12, 13, 14, 15]) {
        expect(permitsShield(w(f)), false);
      }
    });
  });
  group('Appearance and masks', () {
    test('matching helmet is selected while the chosen hair is retained, not rendered', () {
      final a = core.archetype(),
          hat = core.part(Slot.helmet, 52, 'humf_helmet016.dds'),
          hair = core.part(Slot.hair, 4, 'hum_hair004.dds');
      a.parts[Slot.helmet]!.add(hat);
      a.parts[Slot.hair]!.add(hair);
      final look = Appearance.forSet(a, '016');
      expect(look.selected[Slot.helmet], hat);
      expect(look.selected[Slot.hair], hair);
      expect(look.effective.any((p) => p.slot == Slot.hair), false);
      expect(
        look
            .withPart(Slot.helmet, null)
            .effective
            .any((p) => identical(p, hair)),
        true,
      );
    });
    test(
      'combined garment parts can cover the lower body without base leggings',
      () {
        final base = body.legs('base'),
            one = body.legs('one', oneLeg: true),
            two = body.legs('two');
        // Complementary triangles in two independently selected pieces.
        final right = MeshData(
          two.positions,
          two.normals,
          two.uv,
          two.indices.sublist(6),
          two.joints,
          two.weights,
          two.inverses,
          'right',
        );
        expect(bodyRegionCoveredBy([one], base), false);
        expect(bodyRegionCoveredBy([one, right], base), true);
      },
    );
    test(
      'auxiliary red masks are catalogued as material, not wearable armor',
      () {
        expect(
          textureRole('character/human/dds/humf_torso0092_3_m.dds'),
          'máscara/material auxiliar',
        );
        expect(recolorOf('humf_torso0092_3', 'humf_torso009'), true);
      },
    );
  });
  group('Additive pose quality', () {
    List<BoneTrack> bones() => [
      BoneTrack(
        -1,
        v.Matrix4.identity(),
        [0],
        [v.Quaternion.identity()],
        [0],
        [v.Vector3.zero()],
      ),
      BoneTrack(
        0,
        v.Matrix4.identity(),
        [0],
        [v.Quaternion.identity()],
        [0],
        [v.Vector3(0, 1, 0)],
      ),
      BoneTrack(
        1,
        v.Matrix4.identity(),
        [0],
        [v.Quaternion.identity()],
        [0],
        [v.Vector3(0, .2, 0)],
      ),
    ];
    test('head follows smoothly within anatomical yaw/pitch bounds', () {
      final head = HeadLookController(1, bones());
      var previous = 0.0;
      for (var i = 0; i < 120; i++) {
        head.step(1 / 60, cameraYaw: -math.pi / 2, cameraPitch: 1, bodyYaw: 0);
        expect(
          (head.yaw - previous).abs(),
          lessThanOrEqualTo(head.maxSpeed / 60 + 1e-9),
        );
        previous = head.yaw;
        expect(head.yaw.abs(), lessThanOrEqualTo(head.maxYaw));
        expect(head.pitch.abs(), lessThanOrEqualTo(head.maxPitch));
      }
      expect(head.yaw, greaterThan(.6));
    });
    test('camera behind the body relaxes rather than spinning the neck', () {
      final h = HeadLookController(1, bones());
      for (var i = 0; i < 120; i++) {
        h.step(.05, cameraYaw: 0, cameraPitch: 0, bodyYaw: 0);
      }
      expect(h.yaw.abs(), lessThan(1e-9));
    });
    test('head layer changes only its subtree and retains joint lengths', () {
      final original = [
        v.Matrix4.identity(),
        v.Matrix4.translationValues(0, 1, 0),
        v.Matrix4.translationValues(0, 1.2, 0),
      ];
      final changed = original.map((m) => m.clone()).toList(),
          h = HeadLookController(1, bones())
            ..yaw = .6
            ..pitch = .3;
      h.apply(changed);
      expect(changed.first.storage, original.first.storage);
      expect(
        (changed[2].getTranslation() - changed[1].getTranslation()).length,
        closeTo(.2, 1e-6),
      );
      expect(original[2].storage[13], 1.2);
    });
    test('wing horizontal rotation does not shift the socket position', () {
      v.Matrix4 make(double yaw) => backAttachmentPose(
        position: v.Vector3(2, 4, 6),
        yaw: .4,
        bone: v.Matrix4.identity(),
        referenceInverse: v.Matrix4.identity(),
        offset: v.Vector3(0, 1.3, .2),
        scale: 1,
        localYaw: yaw,
      );
      final a = make(0), b = make(.8);
      expect(a.getTranslation().distanceTo(b.getTranslation()), lessThan(1e-8));
      expect(a.storage.sublist(0, 12), isNot(b.storage.sublist(0, 12)));
    });
  });
  group('Streaming window and collision lifetime', () {
    test('window is distance bounded and deterministically capped', () {
      final w = SpatialWindow(radius: 320, maxCells: 64);
      final cells = w.select(500, 500);
      expect(cells.length, lessThanOrEqualTo(64));
      expect(cells.toSet().length, cells.length);
      expect(cells.every((c) => w.distance2(c, 500, 500) <= 320 * 320), true);
    });
    test('hysteresis retains nearby sectors and releases remote ones', () {
      final w = SpatialWindow(radius: 176, margin: 80), c = w.at(200, 200);
      expect(w.retain(c, 200, 200), true);
      expect(w.retain(c, 450, 200), true);
      expect(w.retain(c, 800, 800), false);
    });
    test(
      'collision resources are removed by owner without disturbing neighbours',
      () {
        final f = SurfaceIndex(), m = body.legs('walls');
        f.add(m, owner: 'a');
        f.add(m, owner: 'b');
        expect(f.ownedGroups, 2);
        final cells = f.residentCells;
        f.removeOwner('a');
        expect(f.residentCells, cells);
        expect(f.ownedGroups, 1);
        f.removeOwner('b');
        expect(f.residentCells, 0);
      },
    );
  });
}
