import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' as v;
import 'package:three_js/three_js.dart' as t;
import 'package:herramienta_shaiya/core/formats.dart';
import 'package:herramienta_shaiya/core/navigation.dart';
import 'package:herramienta_shaiya/core/identity_mask.dart';
import 'package:herramienta_shaiya/core/world_resources.dart';
import 'package:herramienta_shaiya/render/studio_scene.dart';
import 'package:herramienta_shaiya/core/combat.dart';
import 'package:herramienta_shaiya/data/catalog.dart';
import 'package:herramienta_shaiya/render/world_builder.dart';
import 'locomotion_test.dart' show exampleScene, motion;
import 'core_test.dart' as fixture;

class Bytes {
  final out = BytesBuilder();
  void u(int x) {
    final b = ByteData(4)..setUint32(0, x, Endian.little);
    out.add(b.buffer.asUint8List());
  }

  void f(double x) {
    final b = ByteData(4)..setFloat32(0, x, Endian.little);
    out.add(b.buffer.asUint8List());
  }

  void short(int x) {
    final b = ByteData(2)..setUint16(0, x, Endian.little);
    out.add(b.buffer.asUint8List());
  }

  Uint8List data() => out.toBytes();
}

Uint8List object({
  bool badFooter = false,
  bool deadUv = false,
  bool usedBadUv = false,
}) {
  final b = Bytes()
    ..u(0)
    ..u(deadUv ? 4 : 3);
  for (var i = 0; i < (deadUv ? 4 : 3); i++) {
    for (final c in [
      [0.0, 0.0, 0.0],
      [1.0, 0.0, 0.0],
      [0.0, 1.0, 0.0],
      [0.0, 0.0, 0.0],
    ][i]) {
      b.f(c);
    }
    b.f(0);
    b.f(0);
    b.f(1);
    b.f(0);
    b.f((i == 3 || usedBadUv && i == 0) ? double.nan : 0);
  }
  b.u(1);
  b.short(0);
  b.short(1);
  b.short(2);
  b.u(0);
  b.u(badFooter ? 1 : 0);
  return b.data();
}

MeshData plane(List<double> vertices, List<int> triangles) => MeshData(
  Float32List.fromList(vertices),
  Float32List(vertices.length),
  Float32List(vertices.length ~/ 3 * 2),
  Uint16List.fromList(triangles),
  Uint8List(0),
  Float32List(0),
  [],
  'test',
);
void main() {
  group('Original rigid format variants', () {
    test('eight zero footer is supported for both weapons and sky', () {
      final m = MeshData.object(object(), '06041.3do');
      expect(m.triangles, 1);
      expect(m.vertices, 3);
    });
    test('nonzero unknown footer is never silently ignored', () {
      expect(
        () => MeshData.object(object(badFooter: true), 'unknown.3do'),
        throwsFormatException,
      );
    });
    test('dead UVs do not discard the complete building', () {
      final m = MeshData.object(object(deadUv: true), 'roof.3do');
      expect(m.indices, [0, 1, 2]);
      expect(m.uv.every((v) => v.isFinite), isTrue);
      expect(m.repairs, isNotEmpty);
    });
    test('a referenced invalid UV still produces a useful diagnostic', () {
      expect(
        () => MeshData.object(object(usedBadUv: true), 'bad.3do'),
        throwsFormatException,
      );
    });
    test('truncated object is rejected before GPU upload', () {
      expect(
        () => MeshData.object(object().sublist(0, 38), 'bad.3do'),
        throwsFormatException,
      );
    });
  });
  group('Camera-relative navigation', () {
    test('front follows camera at 0, 90 and 180 degrees', () {
      expect(cameraRelative(0, -1, 0).z, -1);
      expect(cameraRelative(0, -1, math.pi / 2).x, closeTo(-1, 1e-9));
      expect(cameraRelative(0, -1, math.pi).z, closeTo(1, 1e-9));
    });
    test('walking animation and facing point toward the same destination', () {
      final s = exampleScene()..yaw = math.pi / 2;
      s.setMovement(0, -1);
      s.tick(.1);
      expect(s.character!.root.position.x, closeTo(-.2, 1e-6));
      expect(s.character!.root.position.z, closeTo(0, 1e-6));
      expect(s.character!.root.rotation.y, closeTo(-math.pi / 2, 1e-6));
      s.dispose();
    });
    test('diagonal movement has unit speed after rotation', () {
      expect(cameraRelative(1, -1, 1.37).length, closeTo(1, 1e-9));
    });
    test('jump returns to the same ground and cannot jump in midair', () {
      final jump = JumpState();
      expect(jump.start(), isTrue);
      expect(jump.start(), isFalse);
      var max = 0.0;
      for (var i = 0; i < 120; i++) {
        jump.step(1 / 60);
        max = math.max(max, jump.height);
      }
      expect(max, greaterThan(1));
      expect(jump.height, 0);
      expect(jump.velocity, 0);
      expect(jump.start(), isTrue);
    });
    test('ground walking resumes after the jump lands', () async {
      final s = exampleScene();
      s.game.jumpClip = motion('humf_008_jump.ani', .1);
      s.sound = false;
      s.setMovement(0, -1);
      await s.jump();
      expect(s.game.jump.airborne, isTrue);
      for (var i = 0; i < 40; i++) {
        s.tick(.05);
      }
      expect(s.game.jump.airborne, isFalse);
      expect(s.character!.clip, s.character!.walk);
      expect(s.character!.root.position.z, lessThan(-2));
      s.dispose();
    });
  });
  group('Target isolation', () {
    test('changing target never redirects an in-flight impact', () {
      final c = Combat()
        ..counterattack = false
        ..distanceToTarget = (_) => 1;
      c.addTarget('a');
      c.addTarget('b');
      c.selectTarget('a');
      c.attack(1);
      c.selectTarget('b');
      for (var i = 0; i < 20; i++) {
        c.step(.05, 1);
      }
      expect(c.health['a'], 910);
      expect(c.health['b'], 1000);
    });
    test('removed target cancels its scheduled impacts', () {
      final c = Combat()
        ..counterattack = false
        ..distanceToTarget = (_) => 1;
      c.addTarget('a');
      c.selectTarget('a');
      c.attack(1);
      c.removeTarget('a');
      for (var i = 0; i < 20; i++) {
        c.step(.05, 1);
      }
      expect(c.playerHealth, 1000);
      expect(c.health.containsKey('a'), isFalse);
    });
    test('attack events include the actual target identifier', () {
      final events = <String>[];
      final c = Combat()
        ..counterattack = false
        ..onTargetEvent = (id, actor, event) => events.add('$id:$actor:$event');
      c.addTarget('second');
      c.selectTarget('second');
      c.attack(1);
      for (var i = 0; i < 20; i++) {
        c.step(.05, 1);
      }
      expect(events, ['second:player:attack', 'second:enemy:hit']);
    });
    test('reset restores all spawned creature health independently', () {
      final c = Combat();
      c.addTarget('a');
      c.addTarget('b');
      c.health['a'] = 10;
      c.health['b'] = 0;
      c.reset();
      expect(c.health['a'], 1000);
      expect(c.health['b'], 1000);
      expect(c.active, isFalse);
    });
  });

  group('Embedded costume head', () {
    test(
      'head masking preserves the chosen face without editing DATA geometry',
      () {
        final p = Float32List.fromList([
              0,
              2,
              0,
              1,
              2,
              0,
              0,
              2,
              1,
              0,
              0,
              0,
              1,
              0,
              0,
              0,
              0,
              1,
            ]),
            weights = Float32List(24),
            joints = Uint8List(24);
        for (var i = 0; i < 6; i++) {
          weights[i * 4] = 1;
          joints[i * 4] = i < 3 ? 1 : 0;
        }
        final costume = MeshData(
          p,
          Float32List(18),
          Float32List(12),
          Uint16List.fromList([0, 1, 2, 3, 4, 5]),
          joints,
          weights,
          [v.Matrix4.identity(), v.Matrix4.identity()],
          'costume',
        );
        final face = MeshData(
          Float32List.fromList([0, 1.7, 0]),
          Float32List(3),
          Float32List(2),
          Uint16List(0),
          Uint8List.fromList([1, 0, 0, 0]),
          Float32List.fromList([1, 0, 0, 0]),
          [v.Matrix4.identity(), v.Matrix4.identity()],
          'face',
        );
        final visible = keepSelectedHead(costume, face);
        expect(visible.indices, [3, 4, 5]);
        expect(costume.indices, [0, 1, 2, 3, 4, 5]);
        expect(identical(visible.positions, costume.positions), isTrue);
      },
    );
  });
  group('Equipment identity isolation', () {
    test(
      'whole suits restore neither foreign gloves nor a previous helmet',
      () {
        final a = fixture.archetype();
        a.parts[Slot.foot]!.add(fixture.part(Slot.foot, 0, 'humf_foot016.dds'));
        a.parts[Slot.helmet]!.add(
          fixture.part(Slot.helmet, 9, 'humf_wedding_helmet.dds'),
        );
        final next = Appearance.forSet(
          a,
          'wedding',
        ).withResolvedCoverage({Slot.lower, Slot.hand, Slot.foot});
        expect(next.effective.map((p) => p.slot), [Slot.upper]);
      },
    );
    test(
      'changing a complete set preserves explicitly selected face and hair',
      () {
        final a = fixture.archetype();
        final face = fixture.part(Slot.face, 2, 'face2.dds'),
            hair = fixture.part(Slot.hair, 3, 'hair3.dds');
        a.parts[Slot.face]!.add(face);
        a.parts[Slot.hair]!.add(hair);
        final old = Appearance.forSet(
              a,
              '016',
            ).withPart(Slot.face, face).withPart(Slot.hair, hair),
            next = Appearance.forSet(a, 'wedding', previous: old);
        expect(identical(next.selected[Slot.face], face), isTrue);
        expect(identical(next.selected[Slot.hair], hair), isTrue);
      },
    );
  });
  group('Full-map spatial queries', () {
    test('collision floors are queried at their world transform', () {
      final index = SurfaceIndex();
      index.add(
        plane([0, 0, 0, 2, 0, 0, 0, 0, 2], [0, 1, 2]),
        transform: v.Matrix4.translationValues(10, 3, 20),
      );
      expect(index.floor(10.3, 20.3, 3), closeTo(3, 1e-9));
      expect(index.floor(0, 0, 0), isNull);
    });
    test('walls block movement but floor triangles do not', () {
      final index = SurfaceIndex();
      index.add(
        plane([0, 0, -2, 0, 3, -2, 0, 0, 2, 0, 3, 2], [0, 1, 2, 1, 3, 2]),
      );
      expect(index.blocks(v.Vector3(-1, 0, 0), v.Vector3(1, 0, 0)), isTrue);
      expect(index.blocks(v.Vector3(-1, 0, 3), v.Vector3(1, 0, 3)), isFalse);
    });
    test('routing finds a way around a wall instead of walking through it', () {
      final index = SurfaceIndex();
      index.add(
        plane([0, 0, -1, 0, 3, -1, 0, 0, 1, 0, 3, 1], [0, 1, 2, 1, 3, 2]),
      );
      final route = RoutePlanner(
        (x, z, y) => 0,
        (a, b) => index.blocks(a, b),
      ).find(v.Vector3(-3, 0, 0), v.Vector3(3, 0, 0));
      expect(route, isNotNull);
      expect(route!.length, greaterThan(1));
      var p = v.Vector3(-3, 0, 0);
      for (final next in route) {
        expect(index.blocks(p, next), isFalse);
        p = next;
      }
      expect(p.x, 3);
    });
    test('an unwalkable void cannot be treated as an unrestricted plane', () {
      final planner = RoutePlanner(
        (x, z, y) => x > 0 && x < 4 ? null : 0,
        (a, b) => false,
        maxNodes: 200,
      );
      expect(planner.find(v.Vector3(-1, 0, 0), v.Vector3(5, 0, 0)), isNull);
    });
    test(
      'instance culling uses transformed batches rather than a prototype at zero',
      () {
        final world = LoadedWorld(
          WorldResource(WorldData(0, Uint16List(0), Uint8List(0), [], [], '')),
        );
        final geometry = t.BufferGeometry()
          ..setAttributeFromString(
            'position',
            t.Float32BufferAttribute.fromList([
              -.5,
              0,
              0,
              .5,
              0,
              0,
              0,
              1,
              0,
            ], 3),
          );
        geometry.setIndex([0, 1, 2]);
        final mesh = t.InstancedMesh(
          geometry,
          t.MeshBasicMaterial.fromMap({'color': 0xffffff}),
          1,
        );
        mesh.setMatrixAt(0, t.Matrix4()..setPosition(100, 0, 100));
        mesh.computeBoundingSphere();
        mesh.frustumCulled = false;
        world.instances.add(mesh);
        world.root.add(mesh);
        world.origin(100, 100);
        final camera = t.PerspectiveCamera(45, 1, .1, 100)
          ..position.setValues(0, 1, 5);
        camera.lookAt(t.Vector3(0, .5, 0));
        world.updateVisibility(camera);
        expect(mesh.visible, isTrue);
        expect(mesh.frustumCulled, isFalse);
        world.dispose();
        geometry.dispose();
      },
    );
  });
}
