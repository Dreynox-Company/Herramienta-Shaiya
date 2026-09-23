import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/input/viewport_movement_input.dart';

class _Probe {
  final focus = FocusNode();
  int toggles = 0;
  int jumps = 0;
  double z = 0;
  bool running = false;
}

void main() {
  Future<_Probe> load(WidgetTester tester, {bool nestedEditor = false}) async {
    final probe = _Probe();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ViewportMovementInput(
            focusNode: probe.focus,
            onChanged: (x, z, running) {
              probe.z = z;
              probe.running = running;
            },
            onFlightToggle: () => probe.toggles++,
            onAction: (key) {
              if (key == LogicalKeyboardKey.space) probe.jumps++;
            },
            child: nestedEditor
                ? const TextField(key: ValueKey('nested-editor'))
                : const SizedBox.expand(),
          ),
        ),
      ),
    );
    probe.focus.requestFocus();
    await tester.pump();
    addTearDown(probe.focus.dispose);
    return probe;
  }

  Future<void> tapKey(
    WidgetTester tester,
    LogicalKeyboardKey key,
  ) async {
    await tester.sendKeyDownEvent(key, platform: 'web');
    await tester.sendKeyUpEvent(key, platform: 'web');
  }

  testWidgets('Space alone is terrestrial jump and never flight', (
    tester,
  ) async {
    final probe = await load(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.space, platform: 'web');
    for (var i = 0; i < 5; i++) {
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.space, platform: 'web');
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space, platform: 'web');

    expect(probe.jumps, 1);
    expect(probe.toggles, 0);
  });

  for (final shift in [
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
  ]) {
    testWidgets('Shift+Space toggles flight once ($shift)', (tester) async {
      final probe = await load(tester);

      await tester.sendKeyDownEvent(shift, platform: 'web');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space, platform: 'web');
      for (var i = 0; i < 5; i++) {
        await tester.sendKeyRepeatEvent(
          LogicalKeyboardKey.space,
          platform: 'web',
        );
      }
      expect(probe.toggles, 1);
      expect(probe.jumps, 0);

      await tester.sendKeyUpEvent(LogicalKeyboardKey.space, platform: 'web');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space, platform: 'web');
      expect(probe.toggles, 2);
      expect(probe.jumps, 0);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space, platform: 'web');
      await tester.sendKeyUpEvent(shift, platform: 'web');
    });
  }

  testWidgets('Shift+Space preserves held W sprint', (tester) async {
    final probe = await load(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW, platform: 'web');
    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.shiftLeft,
      platform: 'web',
    );
    expect(probe.z, -1);
    expect(probe.running, true);

    await tapKey(tester, LogicalKeyboardKey.space);

    expect(probe.toggles, 1);
    expect(probe.jumps, 0);
    expect(probe.z, -1);
    expect(probe.running, true);

    await tester.sendKeyUpEvent(
      LogicalKeyboardKey.shiftLeft,
      platform: 'web',
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW, platform: 'web');
  });

  for (final modifier in [
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
  ]) {
    testWidgets('system modifier never turns Shift+Space into flight: $modifier', (
      tester,
    ) async {
      final probe = await load(tester);
      await tester.sendKeyDownEvent(modifier, platform: 'web');
      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.shiftLeft,
        platform: 'web',
      );
      await tapKey(tester, LogicalKeyboardKey.space);
      expect(probe.toggles, 0);
      expect(probe.jumps, 0);
      await tester.sendKeyUpEvent(
        LogicalKeyboardKey.shiftLeft,
        platform: 'web',
      );
      await tester.sendKeyUpEvent(modifier, platform: 'web');
    });
  }

  testWidgets('focused editor does not intercept jump or flight shortcuts', (
    tester,
  ) async {
    final probe = await load(tester, nestedEditor: true);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW, platform: 'web');
    expect(probe.z, -1);

    await tester.tap(find.byKey(const ValueKey('nested-editor')));
    await tester.pump();
    expect(probe.focus.hasFocus, true);
    expect(probe.focus.hasPrimaryFocus, false);
    expect(probe.z, 0);

    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.shiftLeft,
      platform: 'web',
    );
    await tapKey(tester, LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(
      LogicalKeyboardKey.shiftLeft,
      platform: 'web',
    );
    await tapKey(tester, LogicalKeyboardKey.space);
    await tester.enterText(find.byType(TextField), 'Shift+Espacio');

    expect(probe.toggles, 0);
    expect(probe.jumps, 0);
    expect(find.text('Shift+Espacio'), findsOneWidget);
  });

  testWidgets('inactive and synthesized Space never initiate flight', (
    tester,
  ) async {
    final probe = await load(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.shiftLeft,
      platform: 'web',
    );
    await tapKey(tester, LogicalKeyboardKey.space);
    expect(probe.toggles, 0);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.sendKeyUpEvent(
      LogicalKeyboardKey.shiftLeft,
      platform: 'web',
    );

    final handler = tester
        .widget<Focus>(
          find.byWidgetPredicate(
            (widget) => widget is Focus && widget.focusNode == probe.focus,
          ),
        )
        .onKeyEvent!;
    final result = handler(
      probe.focus,
      const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.space,
        logicalKey: LogicalKeyboardKey.space,
        timeStamp: Duration.zero,
        synthesized: true,
      ),
    );
    expect(result, KeyEventResult.ignored);
    expect(probe.toggles, 0);

    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.shiftLeft,
      platform: 'web',
    );
    await tapKey(tester, LogicalKeyboardKey.space);
    expect(probe.toggles, 1);
    await tester.sendKeyUpEvent(
      LogicalKeyboardKey.shiftLeft,
      platform: 'web',
    );
  });
}
