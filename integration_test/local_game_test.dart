import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:herramienta_shaiya/offline_game/game_app.dart';
import 'package:herramienta_shaiya/offline_game/scene_profile.dart';
import 'package:herramienta_shaiya/offline/save_store.dart';
import 'package:herramienta_shaiya/render/studio_scene.dart';
import 'package:herramienta_shaiya/core/extra_motion.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('independent Flutter game: native rendering, play and save reload', (
    t,
  ) async {
    final input = Platform.environment['SHAIYA_FIXTURE_PATH']!;
    final out = Directory(
      '${Platform.environment['SHAIYA_QA_PATH']}/local-game',
    );
    await out.create(recursive: true);
    final saves = await Directory.systemTemp.createTemp('flutter-game-native-');
    final store = SaveStore(saves);
    final capture = GlobalKey();
    final checks = <String>[];
    Future<void> wait(bool Function() predicate, String label) async {
      final until = DateTime.now().add(const Duration(seconds: 60));
      while (!predicate() && DateTime.now().isBefore(until)) {
        await t.pump(const Duration(milliseconds: 40));
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
      expect(predicate(), true, reason: label);
      checks.add(label);
    }

    Future<void> shot(String name) async {
      await t.pump(const Duration(milliseconds: 100));
      final b =
          capture.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await b.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      await File(
        '${out.path}/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
    }

    try {
      await t.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: LocalGameApp(initialData: input, saveStore: store),
        ),
      );
      final dynamic menu = t.state(find.byType(GameMenu));
      await wait(
        () => menu.catalog != null && !menu.busy,
        'Original-format local DATA indexed',
      );
      await shot('01-partidas');
      await t.enterText(find.byType(TextField).first, 'Ñandú local');
      await t.ensureVisible(find.text('Crear y entrar al mundo'));
      await t.tap(find.text('Crear y entrar al mundo'));
      await wait(
        () => find.byType(PlaySession).evaluate().isNotEmpty,
        'No remote login; save creates local session',
      );
      dynamic session = t.state(find.byType(PlaySession));
      await wait(
        () => session.ready && !session.busy,
        'Native 3D character loaded in playable scene',
      );
      final scene = session.scene as StudioScene;
      (session.focus as FocusNode).requestFocus();
      await t.pump();
      final z = scene.character!.root.position.z;
      await t.sendKeyDownEvent(LogicalKeyboardKey.keyW);
      await wait(
        () => scene.character!.root.position.z < z - .05,
        'W walks and advances character',
      );
      await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await wait(() => scene.running, 'Shift preserves W sprint');
      await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await t.sendKeyUpEvent(LogicalKeyboardKey.keyW);
      await scene.equip(scene.catalog!.weapons.first);
      await scene.setWorld(scene.catalog!.worlds.first);
      await scene.installExtras(
        ExtraMotionLibrary.decode(
          await File('$input/Extras/flight.json.gz').readAsBytes(),
        ),
      );
      await scene.selectCreature(scene.catalog!.wings.first, 'wing');
      (session.focus as FocusNode).requestFocus();
      await t.pump();
      await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await t.sendKeyDownEvent(LogicalKeyboardKey.space);
      await t.sendKeyUpEvent(LogicalKeyboardKey.space);
      await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await wait(() => scene.flying, 'Shift+Space toggles manual wing flight');
      await shot('02-vuelo-escenario');
      await scene.requestFlight(false);
      await wait(
        () => scene.flightState.grounded,
        'Controlled landing without removing wings',
      );
      await scene.setWorld(null);
      await scene.addOpponent(scene.catalog!.creatures.first);
      scene.combat.counterattack = false;
      scene.combat.damage = 1000;
      await scene.attack();
      await wait(
        () => session.progress.victories == 1,
        'Animated local hit awards one deterministic victory',
      );
      expect(session.progress.gold, 5);
      expect(session.progress.experience, 25);
      await shot('03-combate-progreso');
      final profile = SceneProfile.capture(scene);
      scene.wingYaw = .7;
      final edited = SceneProfile.capture(scene);
      await SceneProfile.apply(scene, edited);
      expect(scene.wingYaw, .7);
      await SceneProfile.apply(scene, profile);
      checks.add(
        'Shared editor/client scene profile retains referenced equipment and offsets',
      );
      await t.tap(find.byTooltip('Guardar partida'));
      await wait(() => !session.saving, 'Save flush completed');
      final before = (await store.list()).saves.single;
      expect((before.state['progress']! as Map)['gold'], 5);
      await t.tap(find.text('Partidas'));
      await wait(
        () => find.byType(PlaySession).evaluate().isEmpty && !menu.busy,
        'Return to save menu',
      );
      await t.tap(find.text('Ñandú local'));
      await wait(
        () => find.byType(PlaySession).evaluate().isNotEmpty,
        'Reopen persisted local session',
      );
      session = t.state(find.byType(PlaySession));
      await wait(
        () => session.ready && !session.busy,
        'Second native scene reconstructed from saved references',
      );
      expect(session.progress.gold, 5);
      expect(session.progress.victories, 1);
      expect((session.scene as StudioScene).weaponRecord, isNotNull);
      checks.add(
        'Gold, victories, appearance and equipment persist across native sessions',
      );
      await shot('04-partida-recargada');
      await t.tap(find.text('Partidas'));
      await wait(
        () => find.byType(PlaySession).evaluate().isEmpty,
        'Second session closes normally',
      );
      expect(t.takeException(), isNull);
      await File('${out.path}/result.json').writeAsString(
        jsonEncode({
          'native_render': true,
          'scope':
              'independent Flutter playtest; own synthetic resource fixtures, not the original MMO',
          'checks': checks,
        }),
      );
    } finally {
      await t.pumpWidget(const SizedBox());
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await saves.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
