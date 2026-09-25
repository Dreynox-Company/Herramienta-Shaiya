import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/flight_v3_bundle.dart';
import 'package:herramienta_shaiya/core/flight_presentation.dart';
import 'package:herramienta_shaiya/core/locomotion.dart';
import 'package:herramienta_shaiya/data/catalog.dart';
import 'package:herramienta_shaiya/render/studio_scene.dart';

import 'core_test.dart' show archetype;
import 'flight_v3_bundle_test.dart' show package;
import 'locomotion_test.dart' show motion;

Future<StudioScene> v3Scene() async {
  final bundle = FlightV3Bundle.decode(package());
  final scene = StudioScene((_) {})..yaw = 0;
  final actor = Actor()
    ..normal = bundle.normal
    ..idle = bundle.normal
    ..walk = bundle.walk
    ..run = bundle.run;
  actor.play(bundle.normal);
  scene.character = actor;
  scene.appearance = Appearance.forSet(archetype(), '016');
  scene.wing = Actor();
  scene.combat.counterattack = false;
  await scene.installFlightV3(bundle);
  return scene;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final fps in [30, 60, 144]) {
    test('W is responsive during V3 takeoff at $fps Hz', () async {
      final s = await v3Scene();
      await s.requestFlight(true);
      expect(s.flightBodyTransitionActive, isTrue);
      expect(s.sceneCombatLocked, isFalse);
      s.setMovement(0, -1, run: true);
      var latency = 0.0;
      while (s.character!.root.position.z == 0 && latency < .1) {
        s.tick(1 / fps);
        latency += 1 / fps;
      }
      expect(latency, lessThanOrEqualTo(1 / 30 + 1 / fps));
      expect(s.character!.root.position.z, lessThan(0));
      expect(s.flightBodyTransitionActive, isTrue);
      for (var i = 0; i < fps; i++) {
        s.tick(1 / fps);
      }
      expect(s.character!.clip, same(s.character!.flight));
      expect(s.walkZ, -1);
      expect(s.running, isTrue);
      s.dispose();
    });
    test('landing does not stop held locomotion at $fps Hz', () async {
      final s = await v3Scene();
      await s.requestFlight(true);
      for (var i = 0; i < fps; i++) {
        s.tick(1 / fps);
      }
      s.setMovement(0, -1);
      await s.requestFlight(false);
      final start = s.character!.root.position.z;
      for (var i = 0; i < (fps / 10).ceil(); i++) {
        s.tick(1 / fps);
      }
      expect(s.character!.root.position.z, lessThan(start));
      expect(s.sceneCombatLocked, isFalse);
      expect(s.walkZ, -1);
      s.dispose();
    });
  }
  test(
    'redirecting active takeoff does not restart or freeze the clip',
    () async {
      final s = await v3Scene();
      await s.requestFlight(true);
      s.tick(.05);
      final before = s.character!.time;
      s.applyLocomotion(GroundMotion.walk);
      s.applyLocomotion(GroundMotion.walk);
      expect(s.character!.time, before);
      expect(s.character!.transitionDestination, same(s.character!.flight));
      s.applyLocomotion(GroundMotion.idle);
      expect(s.character!.time, before);
      expect(s.character!.transitionDestination, same(s.character!.hover));
      s.dispose();
    },
  );
  test(
    'presentation retiming preserves overshoot, then restores attack speed',
    () {
      final actor = Actor();
      final transition = motion('takeoff', 0), destination = motion('hover', 0);
      actor.playTransition(
        transition,
        destination,
        destinationPhase: .25,
        presentationSeconds: .2,
      );
      actor.tick(.23);
      expect(actor.clip, same(destination));
      expect(actor.time, closeTo(.28, 1e-8));
      final attack = motion('original-attack', 0);
      actor.play(attack, repeat: false);
      actor.tick(.1);
      expect(actor.time, closeTo(.1, 1e-8));
      expect(actor.speed, 1);
      actor.dispose();
    },
  );
  test('interactive budgets do not retime inspector sequences', () {
    expect(FlightPresentation.budget('TAKEOFF'), .2);
    expect(FlightPresentation.budget('AIR_BLEND'), .09);
    expect(FlightPresentation.budget('LANDING', combat: true), .14);
    expect(FlightPresentation.budget('BODY_SEQUENCE'), isNull);
  });
}
