import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/input/viewport_movement_input.dart';
import 'package:herramienta_shaiya/render/studio_scene.dart';
import 'locomotion_test.dart' show exampleScene;

void main() {
  Future<({StudioScene scene, FocusNode focus})> load(
    WidgetTester tester,
  ) async {
    final scene = exampleScene(), focus = FocusNode();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const TextField(key: ValueKey('search')),
              Expanded(
                child: ViewportMovementInput(
                  focusNode: focus,
                  onChanged: (x, z, run) => scene.setMovement(x, z, run: run),
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
    addTearDown(() {
      scene.dispose();
      focus.dispose();
    });
    return (scene: scene, focus: focus);
  }

  testWidgets('native W then left Shift and releases change actual clips', (
    tester,
  ) async {
    final e = await load(tester), s = e.scene;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
    s.tick(.1);
    expect(s.character!.clip, same(s.character!.walk));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    s.tick(.1);
    expect(s.character!.clip, same(s.character!.run));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    s.tick(.1);
    expect(s.character!.clip, same(s.character!.walk));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
    s.tick(.1);
    expect(s.character!.clip, same(s.character!.normal));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('right Shift held before W also runs', (tester) async {
    final e = await load(tester), s = e.scene;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftRight);
    s.tick(.1);
    expect(s.character!.clip, same(s.character!.normal));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
    s.tick(.1);
    expect(s.character!.clip, same(s.character!.run));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
    s.tick(.1);
    expect(s.character!.clip, same(s.character!.normal));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftRight);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('keyboard repeat does not rewind animation', (tester) async {
    final e = await load(tester), s = e.scene;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
    s.tick(.1);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyW);
    s.tick(.1);
    expect(s.character!.time, closeTo(.2, 1e-6));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('opposite keys cancel and releasing S resumes held W', (
    tester,
  ) async {
    final e = await load(tester), s = e.scene;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
    s.tick(.1);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
    s.tick(.1);
    expect(s.walkZ, 0);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
    s.tick(.1);
    expect(s.character!.clip, same(s.character!.walk));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('search field does not move character', (tester) async {
    final e = await load(tester), s = e.scene;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
    s.tick(.1);
    await tester.tap(find.byKey(const ValueKey('search')));
    await tester.pump();
    s.tick(.1);
    expect(s.walkZ, 0);
    expect(s.running, isFalse);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
    final z = s.character!.root.position.z;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
    s.tick(.1);
    expect(s.character!.root.position.z, z);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('inactive app clears Shift and movement', (tester) async {
    final e = await load(tester), s = e.scene;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftRight);
    s.tick(.1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    s.tick(.1);
    expect(s.walkZ, 0);
    expect(s.running, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    s.tick(.1);
    expect(s.walkZ, 0);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftRight);
    await tester.pumpWidget(const SizedBox());
  });
}
