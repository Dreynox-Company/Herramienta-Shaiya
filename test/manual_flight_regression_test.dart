import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:three_js/three_js.dart' as t;
import 'package:herramienta_shaiya/core/flight_transition.dart';
import 'package:herramienta_shaiya/core/formats.dart';
import 'package:herramienta_shaiya/input/viewport_movement_input.dart';
import 'package:herramienta_shaiya/render/studio_scene.dart';
import 'locomotion_test.dart' show exampleScene, motion;

StudioScene flyingFixture() {
  final scene = exampleScene();
  scene.wing = Actor();
  scene.character!.hover = motion('hover-extra', 0);
  scene.character!.flight = motion('flight-extra', 0);
  scene.combat.counterattack = false;
  return scene;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final fps in [30, 60, 144]) {
    test('normal hover combat contact is reached within 180 ms at $fps Hz', () {
      final f = FlightTransition()..height = .38;
      f.queue('target');
      expect(f.height, .38); // Starting an attack does not teleport.
      var frames = 0, previous = f.height;
      while (!f.grounded && frames < fps) {
        f.step(1 / fps, eligible: true, inCombat: false, hoverHeight: .38);
        expect(f.height, greaterThanOrEqualTo(0));
        expect(f.height, lessThanOrEqualTo(previous + 1e-8));
        expect(f.velocity.isFinite, true);
        previous = f.height;
        frames++;
      }
      expect(f.grounded, true);
      expect(frames / fps, lessThanOrEqualTo(.18));
      expect(f.pendingTarget, 'target');
      expect(f.velocity, 0);
    });
    test('retargeting a queued attack does not restart landing at $fps Hz', () {
      final f = FlightTransition()..height = .38;
      f.queue('first');
      for (var i = 0; i < (fps * .20).ceil(); i++) {
        f.step(1 / fps, eligible: true, inCombat: false, hoverHeight: .38);
        if (!f.grounded) f.queue('target-$i');
      }
      expect(f.grounded, true);
    });
  }
  test('receiving damage also requests the compressed landing', () {
    final f = FlightTransition()..height = .38;
    for (var i = 0; i < 11; i++) {
      f.step(1 / 60, eligible: true, inCombat: true, hoverHeight: .38);
    }
    expect(f.grounded, true);
    expect(f.wantsFlight, false);
  });
  test('ascending and descending states settle without invalid positions', () {
    for (final velocity in [-1.5, 0.0, 1.2]) {
      for (final height in [.005, .12, .38, 1.0, 2.0]) {
        final f = FlightTransition()
          ..height = height
          ..velocity = velocity;
        f.queue('target');
        expect(f.velocity, velocity);
        for (var i = 0; i < 50; i++) {
          f.step(1 / 144, eligible: true, inCombat: false, hoverHeight: height);
          expect(f.height.isFinite && f.velocity.isFinite, true);
          expect(f.height, greaterThanOrEqualTo(0));
        }
        expect(f.grounded, true);
      }
    }
  });
  test(
    'equipment does not activate flight; the user controls the preference',
    () async {
      final s = flyingFixture();
      expect(s.flightEnabled, false);
      s.tick(.1);
      expect(s.flightState.height, 0);
      await s.toggleFlight();
      expect(s.flightEnabled, true);
      s.tick(.1);
      expect(s.flightState.height, greaterThan(0));
      await s.toggleFlight();
      expect(s.flightEnabled, false);
      for (var i = 0; i < 100; i++) {
        s.tick(1 / 30);
      }
      expect(s.flightState.grounded, true);
      expect(s.wing, isNotNull);
      s.dispose();
    },
  );
  test('flight mode rejects absent wings and incompatible movements', () async {
    final s = exampleScene();
    await expectLater(s.toggleFlight(), throwsFormatException);
    expect(s.flightEnabled, false);
    s.wing = Actor();
    await expectLater(s.toggleFlight(), throwsFormatException);
    expect(s.flightEnabled, false);
    s.dispose();
  });
  test('mounted or dead characters cannot initiate flight', () async {
    final s = flyingFixture();
    s.mount = Actor();
    await expectLater(s.toggleFlight(), throwsFormatException);
    s.mount!.dispose();
    s.mount = null;
    s.combat.playerHealth = 0;
    await expectLater(s.toggleFlight(), throwsFormatException);
    expect(s.flightEnabled, false);
    s.dispose();
  });
  test(
    'combat expiration blends sprint into flight without stopping the route',
    () async {
      final s = flyingFixture();
      await s.toggleFlight();
      s.combat.attack(1); // Simulated combat activity, without a live renderer.
      for (var i = 0; i < 230; i++) {
        s.tick(1 / 30);
      }
      expect(s.combat.inGuard, true);
      s.setMovement(0, -1, run: true);
      var last = s.character!.root.position.clone();
      for (var i = 0; i < 80; i++) {
        s.tick(1 / 30);
        final now = s.character!.root.position;
        final dx = now.x - last.x, dz = now.z - last.z;
        expect(dx * dx + dz * dz, closeTo(16 / 900, 1e-7), reason: 'frame $i');
        expect(s.walkZ, -1);
        expect(s.running, true);
        last = now.clone();
      }
      expect(s.combat.inGuard, false);
      expect(s.flying, true);
      expect(s.character!.clip, same(s.character!.flight));
      expect(s.flightState.height, greaterThan(.2));
      s.dispose();
    },
  );
  test('queued combat landing leaves maintained sprint input intact', () async {
    final s = flyingFixture();
    await s.toggleFlight();
    s.flightState.height = .38;
    s.setMovement(0, -1, run: true);
    s.flightState.queue('not-instantiated');
    final before = s.character!.root.position.clone();
    s.tick(1 / 30);
    expect(s.sceneCombatLocked, false);
    expect(s.character!.root.position.distanceTo(before), greaterThan(0));
    expect(s.walkZ, -1);
    expect(s.running, true);
    s.dispose();
  });
  test(
    'flight UI action policy preserves held sprint across both toggles',
    () async {
      final s = flyingFixture();
      s.setMovement(0, -1, run: true);
      await s.runUserAction(s.toggleFlight, preserveMovement: true);
      expect(s.flightEnabled, true);
      expect(s.walkZ, -1);
      expect(s.running, true);
      s.tick(1 / 30);
      final position = s.character!.root.position.clone();
      await s.runUserAction(s.toggleFlight, preserveMovement: true);
      s.tick(1 / 30);
      expect(s.flightEnabled, false);
      final now = s.character!.root.position;
      final dx = now.x - position.x, dz = now.z - position.z;
      expect(dx * dx + dz * dz, closeTo(16 / 900, 1e-7));
      s.dispose();
    },
  );
  test(
    'an invalid flight UI action does not swallow or stop held movement',
    () async {
      final s = exampleScene();
      s.setMovement(0, -1, run: true);
      await expectLater(
        s.runUserAction(s.toggleFlight, preserveMovement: true),
        throwsFormatException,
      );
      expect(s.walkZ, -1);
      expect(s.running, true);
      expect(s.flightEnabled, false);
      s.dispose();
    },
  );
  test(
    'non-movement UI operations still cancel movement before editing',
    () async {
      final s = flyingFixture();
      s.setMovement(0, -1, run: true);
      var invoked = false;
      await s.runUserAction(() async {
        invoked = true;
        expect(s.walkZ, 0);
        expect(s.running, false);
      });
      expect(invoked, true);
      s.dispose();
    },
  );
  test(
    'a new attack during final contact waits for the ground state, not height alone',
    () async {
      final s = flyingFixture();
      final target = Actor()..root.position.z = -1;
      s.game.selectionRing = t.Line(t.BufferGeometry(), t.LineBasicMaterial());
      s.enemy = target;
      s.attackClips = [motion('original-weapon-attack', 0)];
      final record = CreatureRecord(
        0,
        'Fixture',
        'fixture.mon',
        {},
        {},
        {},
        [],
        1,
      );
      s.game.opponents['fixture'] = Opponent('fixture', record, target);
      s.combat.addTarget('fixture');
      s.combat.selectTarget('fixture');
      await s.toggleFlight();
      s.flightState.height = .003;
      s.flightState.velocity = -.1;
      expect(s.flightState.grounded, false);
      await s.attack();
      expect(s.combat.active, false);
      expect(s.flightState.pendingTarget, 'fixture');
      for (var i = 0; i < 5 && !s.combat.active; i++) {
        s.tick(1 / 30);
        if (s.combat.active) expect(s.flightState.grounded, true);
      }
      expect(s.flightState.grounded, true);
      expect(s.combat.active, true);
      s.dispose();
    },
  );
  test(
    'compressed descent does not invent an early hit or alter the weapon cooldown',
    () async {
      final s = flyingFixture();
      final target = Actor()..root.position.z = -1;
      s.game.selectionRing = t.Line(t.BufferGeometry(), t.LineBasicMaterial());
      s.enemy = target;
      final attack = motion('original-weapon-attack', 0);
      s.attackClips = [attack];
      final record = CreatureRecord(
        0,
        'Fixture',
        'fixture.mon',
        {},
        {},
        {},
        [],
        1,
      );
      s.game.opponents['fixture'] = Opponent('fixture', record, target);
      s.combat.addTarget('fixture');
      s.combat.selectTarget('fixture');
      await s.toggleFlight();
      s.flightState.height = .38;
      await s.attack();
      for (var i = 0; i < 6; i++) {
        s.tick(1 / 30);
      }
      expect(s.combat.active, true);
      expect(s.flightState.grounded, true);
      expect(s.combat.health['fixture'], s.combat.maxHealth);
      expect(attack.duration, 1);
      expect(s.combat.cooldown, 1.1);
      for (var i = 0; i < 17; i++) {
        s.tick(1 / 30);
      }
      expect(s.combat.health['fixture'], s.combat.maxHealth - s.combat.damage);
      s.dispose();
    },
  );
  for (final shift in [
    null,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
  ]) {
    testWidgets('ISO flight key toggles once and preserves sprint ($shift)', (
      tester,
    ) async {
      final focus = FocusNode();
      var flights = 0, jumps = 0;
      var running = false;
      var direction = 0.0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const TextField(key: ValueKey('search')),
                Expanded(
                  child: ViewportMovementInput(
                    focusNode: focus,
                    onChanged: (x, z, run) {
                      direction = z;
                      running = run;
                    },
                    onFlightToggle: () => flights++,
                    onAction: (key) {
                      if (key == LogicalKeyboardKey.space) jumps++;
                    },
                    child: const SizedBox.expand(),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW, platform: 'web');
      if (shift != null) await tester.sendKeyDownEvent(shift, platform: 'web');
      final logical = shift == null
          ? LogicalKeyboardKey.less
          : LogicalKeyboardKey.greater;
      await tester.sendKeyDownEvent(
        logical,
        physicalKey: PhysicalKeyboardKey.intlBackslash,
        platform: 'web',
      );
      for (var i = 0; i < 5; i++) {
        await tester.sendKeyRepeatEvent(
          logical,
          physicalKey: PhysicalKeyboardKey.intlBackslash,
          platform: 'web',
        );
      }
      expect(flights, 1);
      expect(jumps, 0);
      expect(direction, -1);
      expect(running, shift != null);
      await tester.sendKeyUpEvent(
        logical,
        physicalKey: PhysicalKeyboardKey.intlBackslash,
        platform: 'web',
      );
      // Space is always jump, including Shift+Space while sprinting.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space, platform: 'web');
      await tester.sendKeyRepeatEvent(
        LogicalKeyboardKey.space,
        platform: 'web',
      );
      expect(jumps, 1);
      expect(flights, 1);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space, platform: 'web');
      await tester.sendKeyDownEvent(
        logical,
        physicalKey: PhysicalKeyboardKey.intlBackslash,
        platform: 'web',
      );
      expect(flights, 2);
      await tester.sendKeyUpEvent(
        logical,
        physicalKey: PhysicalKeyboardKey.intlBackslash,
        platform: 'web',
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW, platform: 'web');
      if (shift != null) await tester.sendKeyUpEvent(shift, platform: 'web');
      await tester.tap(find.byKey(const ValueKey('search')));
      await tester.pump();
      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.less,
        physicalKey: PhysicalKeyboardKey.intlBackslash,
        platform: 'web',
      );
      expect(flights, 2);
      expect(jumps, 1);
      await tester.sendKeyUpEvent(
        LogicalKeyboardKey.less,
        physicalKey: PhysicalKeyboardKey.intlBackslash,
        platform: 'web',
      );
      await tester.pumpWidget(const SizedBox());
      focus.dispose();
    });
  }
}
