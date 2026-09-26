import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/input/viewport_movement_input.dart';

void main() {
  testWidgets('mount gate ignores actions and samples held W after the mount completes', (tester) async {
    final focus = FocusNode(); addTearDown(focus.dispose);
    var enabled = false, jumps = 0, toggles = 0;
    var z = 0.0;
    late StateSetter update;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: StatefulBuilder(
      builder: (context, setState) {
        update = setState;
        return ViewportMovementInput(focusNode: focus, enabled: enabled,
          onChanged: (_, next, _) => z = next,
          onFlightToggle: () => toggles++, onAction: (_) => jumps++,
          child: const SizedBox.expand());
      },
    ))));
    focus.requestFocus(); await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW, platform: 'web');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.less,
      physicalKey: PhysicalKeyboardKey.intlBackslash, platform: 'web');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space, platform: 'web');
    expect(z, 0); expect(jumps, 0); expect(toggles, 0);
    update(() => enabled = true); await tester.pump(); await tester.pump();
    expect(z, -1); expect(jumps, 0); expect(toggles, 0);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.less,
      physicalKey: PhysicalKeyboardKey.intlBackslash, platform: 'web');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space, platform: 'web');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.less,
      physicalKey: PhysicalKeyboardKey.intlBackslash, platform: 'web');
    expect(toggles, 1); expect(z, -1);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.less,
      physicalKey: PhysicalKeyboardKey.intlBackslash, platform: 'web');
    update(() => enabled = false); await tester.pump();
    expect(z, 0);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW, platform: 'web');
    update(() => enabled = true); await tester.pump();
    expect(z, 0); expect(jumps, 0); expect(toggles, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
