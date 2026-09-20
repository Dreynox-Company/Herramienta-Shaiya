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
  Future<_Probe> load(WidgetTester t, {bool nestedEditor = false}) async {
    final p = _Probe();
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ViewportMovementInput(
            focusNode: p.focus,
            onChanged: (x, z, running) {
              p.z = z;
              p.running = running;
            },
            onFlightToggle: () => p.toggles++,
            onAction: (key) {
              if (key == LogicalKeyboardKey.space) p.jumps++;
            },
            child: nestedEditor
                ? const TextField(key: ValueKey('nested-editor'))
                : const SizedBox.expand(),
          ),
        ),
      ),
    );
    p.focus.requestFocus();
    await t.pump();
    addTearDown(p.focus.dispose);
    return p;
  }

  Future<void> press(WidgetTester t, LogicalKeyboardKey key) async {
    await t.sendKeyDownEvent(
      key,
      physicalKey: PhysicalKeyboardKey.intlBackslash,
      platform: 'web',
    );
    await t.sendKeyUpEvent(
      key,
      physicalKey: PhysicalKeyboardKey.intlBackslash,
      platform: 'web',
    );
  }

  for (final logical in [
    LogicalKeyboardKey.less,
    LogicalKeyboardKey.greater,
    LogicalKeyboardKey.bar,
    LogicalKeyboardKey.backslash,
  ]) {
    testWidgets(
      'ISO position, independent of its logical character: $logical',
      (t) async {
        final p = await load(t);
        await press(t, logical);
        expect(p.toggles, 1);
        expect(p.jumps, 0);
        await t.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('less-than from a comma key is not the key beside Z', (t) async {
    final p = await load(t);
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft, platform: 'web');
    await t.sendKeyDownEvent(
      LogicalKeyboardKey.less,
      physicalKey: PhysicalKeyboardKey.comma,
      platform: 'web',
    );
    await t.sendKeyUpEvent(
      LogicalKeyboardKey.less,
      physicalKey: PhysicalKeyboardKey.comma,
      platform: 'web',
    );
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft, platform: 'web');
    expect(p.toggles, 0);
    await t.pumpWidget(const SizedBox());
  });

  for (final modifier in [
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
  ]) {
    testWidgets('editing/system shortcut is not flight: $modifier', (t) async {
      final p = await load(t);
      await t.sendKeyDownEvent(modifier, platform: 'web');
      await press(t, LogicalKeyboardKey.less);
      expect(p.toggles, 0);
      await t.sendKeyUpEvent(modifier, platform: 'web');
      await press(t, LogicalKeyboardKey.less);
      expect(p.toggles, 1);
      await t.pumpWidget(const SizedBox());
    });
  }

  testWidgets('focused editor inside viewport does not intercept text', (
    t,
  ) async {
    final p = await load(t, nestedEditor: true);
    await t.sendKeyDownEvent(LogicalKeyboardKey.keyW, platform: 'web');
    expect(p.z, -1);
    await t.tap(find.byKey(const ValueKey('nested-editor')));
    await t.pump();
    expect(p.focus.hasFocus, true);
    expect(p.focus.hasPrimaryFocus, false);
    expect(p.z, 0);
    await t.sendKeyUpEvent(LogicalKeyboardKey.keyW, platform: 'web');
    await press(t, LogicalKeyboardKey.less);
    await t.sendKeyDownEvent(LogicalKeyboardKey.space, platform: 'web');
    await t.sendKeyUpEvent(LogicalKeyboardKey.space, platform: 'web');
    await t.enterText(find.byType(TextField), 'distancia < 10');
    expect(p.toggles, 0);
    expect(p.jumps, 0);
    expect(find.text('distancia < 10'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('inactive, resumed and repeating key requires a fresh press', (
    t,
  ) async {
    final p = await load(t);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await t.pump();
    await t.sendKeyDownEvent(
      LogicalKeyboardKey.less,
      physicalKey: PhysicalKeyboardKey.intlBackslash,
      platform: 'web',
    );
    expect(p.toggles, 0);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump();
    await t.sendKeyRepeatEvent(
      LogicalKeyboardKey.less,
      physicalKey: PhysicalKeyboardKey.intlBackslash,
      platform: 'web',
    );
    expect(p.toggles, 0);
    await t.sendKeyUpEvent(
      LogicalKeyboardKey.less,
      physicalKey: PhysicalKeyboardKey.intlBackslash,
      platform: 'web',
    );
    await press(t, LogicalKeyboardKey.less);
    expect(p.toggles, 1);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('OS-synthesized key down never initiates flight', (t) async {
    final p = await load(t);
    final handler = t
        .widget<Focus>(
          find.byWidgetPredicate((w) => w is Focus && w.focusNode == p.focus),
        )
        .onKeyEvent!;
    final result = handler(
      p.focus,
      const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.intlBackslash,
        logicalKey: LogicalKeyboardKey.less,
        timeStamp: Duration.zero,
        synthesized: true,
      ),
    );
    expect(result, KeyEventResult.ignored);
    expect(p.toggles, 0);
    await t.pumpWidget(const SizedBox());
  });
}
