import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/offline_game/progress.dart';
import 'package:herramienta_shaiya/offline_game/scene_profile.dart';
import 'package:herramienta_shaiya/offline_game/game_app.dart';
import 'package:herramienta_shaiya/offline/save_store.dart';

void main() {
  const rules = LocalRules();
  test('authored rules round-trip without pretending to be server balance', () {
    expect(
      LocalRules.parse(Map<String, dynamic>.from(rules.toJson())).toJson(),
      rules.toJson(),
    );
  });
  test('negative or unbounded playtest rules are refused', () {
    for (final k in [
      'killExperience',
      'goldReward',
      'healCost',
      'healAmount',
    ]) {
      expect(
        () => LocalRules.parse({...rules.toJson(), k: -1}),
        throwsFormatException,
      );
      expect(
        () => LocalRules.parse({...rules.toJson(), k: 1000001}),
        throwsFormatException,
      );
    }
  });
  test('one reward per enemy instance even after combat reset', () {
    final p = LocalProgress();
    expect(p.defeat('encounter/1', rules), true);
    expect(p.defeat('encounter/1', rules), false);
    expect(p.defeat('', rules), false);
    expect(p.gold, 5);
    expect(p.victories, 1);
    expect(p.experience, 25);
  });
  test('level-up retains excess experience and uses a versioned rule', () {
    final p = LocalProgress();
    for (var i = 0; i < 11; i++) {
      p.defeat('$i', rules);
    }
    expect(p.level, 3);
    expect(p.experience, 25);
    expect(p.gold, 55);
  });
  test('purchase validates capacity and funds; healing never resurrects', () {
    final p = LocalProgress();
    expect(p.buyPotion(rules), false);
    p.gold = 10;
    expect(p.buyPotion(rules), true);
    expect(p.gold, 0);
    expect(p.potions, 4);
    expect(p.consumePotion(900, rules), 1000);
    expect(p.potions, 3);
    expect(p.consumePotion(1000, rules), 1000);
    expect(p.consumePotion(0, rules), 0);
    expect(p.potions, 3);
    p.potions = 9999;
    p.gold = 50;
    expect(p.buyPotion(rules), false);
    expect(p.gold, 50);
  });
  test('time updates are finite and frame-bounded', () {
    final p = LocalProgress();
    p.advance(double.nan);
    p.advance(-1);
    p.advance(10);
    expect(p.seconds, .25);
  });
  test('invalid schema/progress cannot silently reset a save', () {
    final b = LocalProgress().toJson();
    for (final change in [
      {'schema': 2},
      {'gold': -1},
      {'level': 0},
      {'experience': 100},
      {'seconds': double.infinity},
      {'potions': 10000},
    ]) {
      expect(
        () => LocalProgress.parse({...b, ...change}),
        throwsFormatException,
      );
    }
  });
  test('scene scalar ranges reject strings and nonfinite coordinates', () {
    expect(SceneProfile.number({}, 'x', 3, -10, 10), 3);
    for (final v in [double.nan, double.infinity, '3', 11, -11]) {
      expect(
        () => SceneProfile.number({'x': v}, 'x', 0, -10, 10),
        throwsFormatException,
      );
    }
  });
  test('local gameplay survives persistence, Unicode and revisions', () async {
    final root = await Directory.systemTemp.createTemp('local-game-save-');
    try {
      final store = SaveStore(root), p = LocalProgress();
      p.defeat('first', rules);
      p.advance(.1);
      final save = await store.create(
        title: 'Ñandú — Luz',
        faction: 'luz',
        corpusSha256: 'a' * 64,
        state: {
          'engine': 'flutter-local-v1',
          'progress': p.toJson(),
          'rules': rules.toJson(),
        },
      );
      final loaded = await store.load(save.id);
      final fresh = LocalProgress.parse(
        Map<String, dynamic>.from(loaded.state['progress']! as Map),
      );
      expect(fresh.gold, 5);
      expect(fresh.seconds, .1);
      expect(loaded.title, 'Ñandú — Luz');
      fresh.defeat('second', rules);
      await store.update(
        save.id,
        expectedRevision: save.revision,
        expectedCorpus: 'a' * 64,
        state: {...save.state, 'progress': fresh.toJson()},
      );
      final latest = await store.load(save.id);
      expect((latest.state['progress']! as Map)['gold'], 10);
      expect(jsonEncode(latest.state), contains('flutter-local-v1'));
    } finally {
      await root.delete(recursive: true);
    }
  });
  for (final w in [1440.0, 650.0, 390.0]) {
    testWidgets(
      'local menu $w exposes save/source controls without login or overflow',
      (t) async {
        t.view.physicalSize = Size(w, 900);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final dir = Directory.systemTemp.createTempSync('local-menu-');
        await t.pumpWidget(LocalGameApp(saveStore: SaveStore(dir)));
        for (var i = 0; i < 6; i++) {
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
          await t.pump();
        }
        expect(find.text('Nueva partida'), findsOneWidget);
        expect(find.text('Tus partidas'), findsOneWidget);
        expect(find.text('SAH + SAF'), findsOneWidget);
        expect(find.text('Carpeta DATA'), findsOneWidget);
        expect(find.text('Contraseña'), findsNothing);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        dir.deleteSync(recursive: true);
      },
    );
  }
}
