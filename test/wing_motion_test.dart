import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/wing_motion.dart';

void main() {
  test('ground idle walk and run map to native Wing MON locomotion slots', () {
    expect(
      wingMotionPhase(
        flightEnabled: false,
        grounded: true,
        landing: false,
        moving: false,
      ),
      WingMotionPhase.groundedIdle,
    );
    expect(
      wingMotionPhase(
        flightEnabled: false,
        grounded: true,
        landing: false,
        moving: true,
      ),
      WingMotionPhase.groundedWalk,
    );
    expect(
      wingMotionPhase(
        flightEnabled: false,
        grounded: true,
        landing: false,
        moving: true,
        running: true,
      ),
      WingMotionPhase.groundedRun,
    );
  });

  test('landing takes priority over hover and cruise while airborne', () {
    expect(
      wingMotionPhase(
        flightEnabled: true,
        grounded: false,
        landing: true,
        moving: true,
        running: true,
      ),
      WingMotionPhase.landing,
    );
  });

  test('flight chooses hover or cruise from actual movement', () {
    expect(
      wingMotionPhase(
        flightEnabled: true,
        grounded: false,
        landing: false,
        moving: false,
      ),
      WingMotionPhase.hover,
    );
    expect(
      wingMotionPhase(
        flightEnabled: true,
        grounded: false,
        landing: false,
        moving: true,
      ),
      WingMotionPhase.cruise,
    );
  });

  test('resolver covers all native locomotion/fall slots with fallbacks', () {
    final clips = <String, int>{
      'Reposo': 1,
      'Respirar': 2,
      'Caminar': 3,
      'Correr': 4,
      'Caída': 5,
    };
    expect(selectWingMotion(clips, WingMotionPhase.groundedIdle), 1);
    expect(selectWingMotion(clips, WingMotionPhase.groundedWalk), 3);
    expect(selectWingMotion(clips, WingMotionPhase.groundedRun), 4);
    expect(selectWingMotion(clips, WingMotionPhase.hover), 2);
    expect(selectWingMotion(clips, WingMotionPhase.cruise), 4);
    expect(selectWingMotion(clips, WingMotionPhase.landing), 5);

    final partial = <String, int>{'Respirar': 8};
    expect(selectWingMotion(partial, WingMotionPhase.cruise), 8);
    expect(selectWingMotion(partial, WingMotionPhase.landing), 8);
  });

  test('loop selector never references attack/damage slots', () {
    for (final phase in WingMotionPhase.values) {
      expect(
        wingMotionCandidates(phase),
        isNot(
          anyOf(
            contains('Ataque 1'),
            contains('Ataque 2'),
            contains('Ataque 3'),
            contains('Daño'),
          ),
        ),
      );
    }
  });
}
