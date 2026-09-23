import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/wing_motion.dart';

void main() {
  test('ground state wins when flight is disabled or already grounded', () {
    expect(
      wingMotionPhase(
        flightEnabled: false,
        grounded: false,
        landing: false,
        moving: true,
      ),
      WingMotionPhase.grounded,
    );
    expect(
      wingMotionPhase(
        flightEnabled: true,
        grounded: true,
        landing: true,
        moving: true,
      ),
      WingMotionPhase.grounded,
    );
  });

  test('landing takes priority over hover and cruise', () {
    expect(
      wingMotionPhase(
        flightEnabled: true,
        grounded: false,
        landing: true,
        moving: true,
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

  test('resolver uses only MON semantic slots and deterministic fallbacks', () {
    final clips = <String, int>{
      'Reposo': 1,
      'Respirar': 2,
      'Caminar': 3,
      'Correr': 4,
    };
    expect(selectWingMotion(clips, WingMotionPhase.grounded), 1);
    expect(selectWingMotion(clips, WingMotionPhase.hover), 2);
    expect(selectWingMotion(clips, WingMotionPhase.cruise), 4);

    final partial = <String, int>{'Respirar': 8};
    expect(selectWingMotion(partial, WingMotionPhase.cruise), 8);
    expect(
      wingMotionCandidates(WingMotionPhase.cruise),
      everyElement(isIn(clips.keys)),
    );
  });
}
