import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/ui/model_orbit_input.dart';

void main() {
  test('orbit is finite, camera-only, bounded at poles and zoom extremes', () {
    final orbit = ModelOrbit();
    addTearDown(orbit.dispose);
    orbit.rotate(const Offset(4000, 4000));
    expect(orbit.yaw, inInclusiveRange(0, math.pi * 2));
    expect(orbit.pitch, lessThan(math.pi / 2));
    for (var i = 0; i < 20; i++) {
      orbit.dolly(1);
    }
    expect(orbit.zoom, 30);
    for (var i = 0; i < 30; i++) {
      orbit.dolly(-1);
    }
    expect(orbit.zoom, .03);
    final before = orbit.snapshot;
    orbit.rotate(const Offset(double.nan, 0));
    orbit.dolly(double.infinity);
    orbit.pan(const Offset(1, 1), 0);
    expect(orbit.snapshot, before);
    orbit.reset();
    expect(orbit.snapshot, [.35, .18, 1, 0, 0, 0]);
  });
  for (final dpr in [1.0, 2.0]) {
    testWidgets(
      'mouse orbit wins over renderer recognizer at offset and DPR $dpr',
      (tester) async {
        tester.view.devicePixelRatio = dpr;
        tester.view.physicalSize = Size(1000 * dpr, 800 * dpr);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final orbit = ModelOrbit();
        addTearDown(orbit.dispose);
        var stolen = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.only(left: 180, top: 100),
                child: SizedBox(
                  width: 500,
                  height: 400,
                  child: ModelOrbitInput(
                    orbit: orbit,
                    child: GestureDetector(
                      onPanUpdate: (_) => stolen++,
                      child: const ColoredBox(color: Colors.black),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final input = find.byKey(const ValueKey('model-orbit-input'));
        final center = tester.getCenter(input);
        final mouse = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
          buttons: kPrimaryMouseButton,
        );
        await mouse.addPointer(location: center);
        await tester.pump();
        await mouse.down(center);
        await mouse.moveBy(const Offset(35, 25));
        await mouse.up();
        await tester.pump();
        expect(orbit.yaw, isNot(.35));
        expect(orbit.pitch, isNot(.18));
        expect(stolen, 0);
        final before = orbit.snapshot;
        final secondary = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await secondary.down(center);
        await secondary.moveBy(const Offset(20, 20));
        await secondary.up();
        await tester.pump();
        expect(orbit.yaw, before[0]);
        expect(orbit.pitch, before[1]);
        expect(orbit.targetX, isNot(0));
        expect(orbit.targetY, isNot(0));
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: center,
            kind: PointerDeviceKind.mouse,
            scrollDelta: const Offset(0, 120),
          ),
        );
        await tester.pump();
        expect(orbit.zoom, greaterThan(1));
        await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
        await tester.pump();
        expect(orbit.snapshot, [.35, .18, 1, 0, 0, 0]);
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'outside press does not orbit, cancellation releases input, drag may leave preview',
    (tester) async {
      final orbit = ModelOrbit();
      addTearDown(orbit.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                height: 220,
                child: ModelOrbitInput(
                  orbit: orbit,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      );
      final center = tester.getCenter(
        find.byKey(const ValueKey('model-orbit-input')),
      );
      final mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryMouseButton,
      );
      await mouse.down(const Offset(1, 1));
      await mouse.moveTo(center);
      await mouse.up();
      expect(orbit.yaw, .35);
      await mouse.down(center);
      await mouse.moveBy(const Offset(400, 0));
      await mouse.cancel();
      await tester.pump();
      expect(orbit.yaw, isNot(.35));
      final before = orbit.snapshot;
      await mouse.moveTo(center);
      await tester.pump();
      expect(orbit.snapshot, before);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('touch orbit and pinch work without feeding the inner renderer', (
    tester,
  ) async {
    final orbit = ModelOrbit();
    addTearDown(orbit.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModelOrbitInput(orbit: orbit, child: const SizedBox.expand()),
        ),
      ),
    );
    final a = await tester.startGesture(const Offset(200, 200), pointer: 1);
    await a.moveBy(const Offset(20, 10));
    expect(orbit.yaw, isNot(.35));
    final b = await tester.startGesture(const Offset(400, 200), pointer: 2);
    final yaw = orbit.yaw;
    await b.moveBy(const Offset(60, 0));
    expect(orbit.zoom, lessThan(1));
    expect(orbit.yaw, yaw);
    await a.up();
    await b.up();
    await tester.pumpWidget(const SizedBox());
  });
}
