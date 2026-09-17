import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' as v;
import 'package:herramienta_shaiya/core/attachment_pose.dart';
import 'package:herramienta_shaiya/ui/asset_selector.dart';
import 'package:herramienta_shaiya/ui/studio_workspace.dart';
import 'package:herramienta_shaiya/render/studio_scene.dart';
import 'locomotion_test.dart' show exampleScene, motion;

void main() {
  testWidgets('catalog reopens at current item 150 and retains search', (
    tester,
  ) async {
    final memory = SelectionMemory();
    String current = '150';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, update) => Center(
              child: SizedBox(
                width: 250,
                child: AssetSelector<String>(
                  title: 'Montura',
                  items: List.generate(200, (i) => '$i'),
                  value: current,
                  id: (s) => s,
                  label: (s) => 'Montura $s',
                  memory: memory,
                  onChanged: (s) async {
                    update(() => current = s);
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Montura 150'));
    await tester.pumpAndSettle();
    expect(find.text('Actual'), findsOneWidget);
    expect(
      tester.widget<ListView>(find.byType(ListView)).controller!.offset,
      greaterThan(8000),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
    expect(current, '151');
    await tester.tap(find.text('Montura 151'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ListView>(find.byType(ListView)).controller!.offset,
      greaterThan(8000),
    );
    await tester.enterText(find.byType(TextField), 'Montura 15');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(memory.query, 'Montura 15');
    await tester.tap(find.text('Montura 151'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Montura 15',
    );
    expect(find.text('Actual'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('field arrows coalesce rapid equipment selection while loading', (
    tester,
  ) async {
    String current = '2';
    final calls = <String>[];
    Completer<void>? gate;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, update) => Center(
              child: SizedBox(
                width: 250,
                child: AssetSelector<String>(
                  title: 'Arma',
                  items: List.generate(10, (i) => '$i'),
                  value: current,
                  id: (s) => s,
                  label: (s) => 'Arma $s',
                  memory: SelectionMemory(),
                  onChanged: (s) async {
                    calls.add(s);
                    if (s == '3') {
                      gate = Completer();
                      await gate!.future;
                    }
                    update(() => current = s);
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Arma 2'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 110));
    expect(calls, ['3']);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 110));
    gate!.complete();
    await tester.pumpAndSettle();
    expect(calls, ['3', '5']);
    expect(current, '5');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump(const Duration(milliseconds: 110));
    await tester.pumpAndSettle();
    expect(current, '4');
    await tester.pumpWidget(const SizedBox());
  });
  for (final size in [
    const Size(1440, 900),
    const Size(1024, 768),
    const Size(390, 844),
    const Size(844, 390),
  ]) {
    testWidgets('non overlapping workspace ${size.width}x${size.height}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: StudioWorkspace(
            viewport: const ColoredBox(
              color: Colors.blue,
              child: SizedBox.expand(),
            ),
            left: const Text('Biblioteca'),
            right: const Text('Inspector'),
            timeline: const SizedBox(
              height: 48,
              child: Text('Línea de tiempo'),
            ),
            actions: const SizedBox(height: 42, child: Text('Ataques')),
            status: const Text('Estado'),
            tabs: const ['Personaje', 'Equipo'],
            icons: const [Icons.person, Icons.shield],
            selectedTab: 0,
            onTab: (_) {},
            onOpenData: () {},
            hasLibrary: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final viewport = tester.getRect(
            find.byKey(const ValueKey('viewport-region')),
          ),
          actions = tester.getRect(find.byKey(const ValueKey('action-region'))),
          timeline = tester.getRect(
            find.byKey(const ValueKey('timeline-region')),
          );
      expect(viewport.bottom, lessThanOrEqualTo(actions.top));
      expect(actions.bottom, lessThanOrEqualTo(timeline.top));
      if (size.width >= 840) {
        final before = viewport.width;
        await tester.tap(find.byKey(const ValueKey('toggle-left')));
        await tester.pumpAndSettle();
        expect(
          tester.getSize(find.byKey(const ValueKey('viewport-region'))).width,
          greaterThan(before),
        );
      } else {
        await tester.tap(find.byKey(const ValueKey('toggle-left')));
        await tester.pumpAndSettle();
        expect(find.byType(Drawer), findsWidgets);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  test('wing anchor applies seat height exactly once', () {
    v.Matrix4 anchor(double seat) => backAttachmentPose(
      position: v.Vector3(3, seat, 5),
      yaw: 0,
      bone: v.Matrix4.identity(),
      referenceInverse: v.Matrix4.identity(),
      offset: v.Vector3(0, 1.3, .25),
      scale: 1,
    );
    final a = anchor(0), b = anchor(2.5), c = anchor(4);
    expect(b.storage[13] - a.storage[13], closeTo(2.5, 1e-8));
    expect(c.storage[13] - b.storage[13], closeTo(1.5, 1e-8));
    expect(c.storage[14], a.storage[14]);
  });
  test('wing attachment follows torso and yaw without cumulative drift', () {
    final bone = v.Matrix4.translationValues(0, 1, 0);
    v.Matrix4 frame(double yaw) => backAttachmentPose(
      position: v.Vector3.zero(),
      yaw: yaw,
      bone: bone,
      referenceInverse: v.Matrix4.inverted(bone),
      offset: v.Vector3(0, 1.3, .25),
      scale: 1,
    );
    final a = frame(0), b = frame(math.pi / 2);
    expect(a.storage[14], closeTo(-.25, 1e-8));
    expect(b.storage[12], closeTo(-.25, 1e-8));
    for (var i = 0; i < 300; i++) {
      expect(frame(0).storage[13], closeTo(1.3, 1e-8));
    }
  });
  test('rider and mount walk, run and stop together', () {
    final s = exampleScene(), mount = Actor();
    mount.clips['Respirar'] = motion('horse_idle.ani', .1);
    mount.clips['Caminar'] = motion('horse_walk.ani', 1);
    mount.clips['Correr'] = motion('horse_run.ani', 2);
    mount.normal = mount.clips['Respirar'];
    s.mount = mount;
    s.character!.riderIdle = motion('humf_021_veh_br.ani', .1);
    s.character!.riderMoving = motion('humf_020_veh_run.ani', 1);
    s.setMovement(0, -1);
    s.tick(.1);
    expect(mount.clip, same(mount.clips['Caminar']));
    expect(s.character!.clip, same(s.character!.riderMoving));
    s.setMovement(0, -1, run: true);
    s.tick(.1);
    expect(mount.clip, same(mount.clips['Correr']));
    s.clearMovement();
    s.tick(.1);
    expect(mount.clip, same(mount.clips['Respirar']));
    expect(s.character!.clip, same(s.character!.riderIdle));
    s.dispose();
  });
}
