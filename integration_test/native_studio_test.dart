import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:herramienta_shaiya/main.dart';
import 'package:herramienta_shaiya/data/library.dart';
import 'package:herramienta_shaiya/data/catalog.dart';
import 'package:herramienta_shaiya/data/archive_export.dart';
import 'package:herramienta_shaiya/ui/data_editor.dart';
import 'package:herramienta_shaiya/ui/editor_model_preview.dart';
import 'package:herramienta_shaiya/data/archive_write.dart';
import 'package:herramienta_shaiya/data/directory_pack.dart';
import 'package:herramienta_shaiya/editor/schema_reader.dart';
import 'package:herramienta_shaiya/core/extra_motion.dart';

import 'package:herramienta_shaiya/render/studio_scene.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native DATA rendering and locomotion regression', (
    tester,
  ) async {
    final input = Platform.environment['SHAIYA_FIXTURE_PATH'];
    expect(
      input,
      isNotNull,
      reason: 'Set SHAIYA_FIXTURE_PATH to the generated synthetic fixture.',
    );
    final output = Directory(
      Platform.environment['SHAIYA_QA_PATH'] ?? 'qa-native',
    );
    await output.create(recursive: true);
    final passed = <String>[];
    await tester.pumpWidget(ShaiyaApp(initialData: input));
    final dynamic state = tester.state(find.byType(StudioPage));
    final scene = state.scene as StudioScene;
    Future<void> waitFor(bool Function() condition, String name) async {
      final deadline = DateTime.now().add(const Duration(seconds: 45));
      while (!condition() && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 40));
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
      expect(condition(), isTrue, reason: '$name; ${scene.status}');
      passed.add(name);
    }

    Future<void> screenshot(String name) async {
      await tester.pump(const Duration(milliseconds: 120));
      final boundary =
          (state.captureKey as GlobalKey).currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      expect(bytes, isNotNull);
      await File(
        '${output.path}/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
    }

    await waitFor(
      () => scene.character != null && !scene.busy && state.catalog != null,
      'Loaded native mesh, texture, catalog and skeletal clips',
    );
    expect(
      scene.character!.clip!.source.toLowerCase(),
      endsWith('_000_normal.ani'),
    );
    passed.add('Initial standing idle, not swimming');
    (state.focus as FocusNode).requestFocus();
    await tester.pump();
    final startZ = scene.character!.root.position.z;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
    await waitFor(
      () => scene.character!.clip == scene.character!.walk,
      'W chooses walk',
    );
    await waitFor(
      () => scene.character!.root.position.z < startZ - .05,
      'W translates only while walking',
    );
    final time = scene.character!.time;
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyW);
    await tester.pump(const Duration(milliseconds: 120));
    expect(scene.character!.time, greaterThan(time));
    passed.add('Key repeat does not restart the clip');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await waitFor(
      () => scene.character!.clip == scene.character!.run,
      'W + Shift chooses run',
    );
    await screenshot('native_run');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await waitFor(
      () => scene.character!.clip == scene.character!.walk,
      'Shift released with W held returns to walk',
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
    await waitFor(
      () => scene.character!.clip == scene.character!.idle,
      'Releasing W returns to idle',
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftRight);
    await tester.pump(const Duration(milliseconds: 160));
    expect(scene.character!.clip, scene.character!.idle);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftRight);
    passed.add('Shift alone leaves the character at rest');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
    await waitFor(
      () => scene.character!.clip == scene.character!.walk,
      'Walking before focus loss',
    );
    (state.focus as FocusNode).unfocus();
    await waitFor(
      () =>
          scene.walkX == 0 &&
          scene.walkZ == 0 &&
          scene.character!.clip == scene.character!.idle,
      'Focus loss cancels held movement and restores idle',
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
    final c = scene.catalog!;
    expect(c.weapons, isNotEmpty);
    await scene.equip(c.weapons.first);
    expect(scene.weapon, isNotNull);
    expect(scene.weapon!.mesh.parent, scene.character!.visual);
    passed.add(
      'Rigid weapon with eight-byte zero footer equips through the native renderer',
    );
    expect(scene.character!.idle, scene.character!.normal);
    expect(scene.combat.inGuard, false);
    passed.add('Equipping does not activate combat guard');
    await scene.equipShield(scene.availableShields.first);
    expect(scene.shield, isNotNull);
    expect(scene.shield!.mesh.parent, scene.character!.visual);
    expect(scene.weapon, isNotNull);
    passed.add('One-handed weapon and independent shield render together');
    await screenshot('native_weapon_shield');
    await scene.equip(
      scene.availableWeapons.firstWhere((w) => weaponFamily(w) == 6),
    );
    expect(scene.shield, isNull);
    expect(scene.character!.weaponRun!.source, endsWith('_054_sprun.ani'));
    (state.focus as FocusNode).requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await waitFor(
      () => scene.character!.clip == scene.character!.weaponRun,
      'Spear Shift movement uses its own run clip',
    );
    await screenshot('native_spear_running');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    passed.add('Two-handed spear removes the conflicting offhand');
    await scene.equip(c.weapons.firstWhere((w) => weaponFamily(w) == 1));
    scene.yaw = math.pi / 2;
    (state.focus as FocusNode).requestFocus();
    await tester.pump();
    final startX = scene.character!.root.position.x;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
    await waitFor(
      () => scene.character!.root.position.x < startX - .05,
      'Camera-relative W at ninety degrees moves toward negative X',
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
    await waitFor(
      () => scene.character!.clip == scene.character!.idle,
      'Camera-relative movement stops',
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await waitFor(
      () => scene.game.jump.height > .08,
      'Space starts the original jump',
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await screenshot('native_jump_weapon');
    await waitFor(() => !scene.game.jump.airborne, 'Jump returns to the floor');
    scene.yaw = .25;
    await scene.selectCreature(c.mounts.first, 'mount');
    await scene.selectCreature(c.wings.first, 'wing');
    (state.focus as FocusNode).requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
    await waitFor(
      () => scene.mount!.clip == scene.mount!.clips['Caminar'],
      'Mounted W selects mount walk',
    );
    expect(scene.character!.clip, scene.character!.riderMoving);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await waitFor(
      () => scene.mount!.clip == scene.mount!.clips['Correr'],
      'Mounted Shift selects mount run',
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await waitFor(
      () => scene.character!.clip == scene.character!.riderIdle,
      'Mounted release returns to riding idle',
    );
    scene.riderHeight = 1.25;
    scene.updateAttachments();
    final wingY = scene.wing!.root.matrix.storage[13];
    scene.riderHeight = 3.75;
    scene.updateAttachments();
    expect(scene.wing!.root.matrix.storage[13] - wingY, closeTo(2.5, .001));
    passed.add('Wing inherits seat height once');
    await scene.selectCreature(c.mounts[1], 'mount');
    await scene.selectCreature(c.mounts.first, 'mount');
    expect(scene.riderHeight, closeTo(3.75, .001));
    passed.add('Mount-specific seat calibration is restored');
    // Restore a reasonable visual seat after the intentionally exaggerated delta test.
    scene.riderHeight = .7;
    scene.updateAttachments();
    await scene.setWorld(c.worlds.first);
    expect(scene.sky, isNotNull);
    expect(scene.environmentParts, isNotEmpty);
    passed.add(
      'Exterior terrain and sky are rendered through original format readers',
    );
    await waitFor(
      () => (scene.character!.root.position.y - scene.groundY).abs() < .001,
      'Map transition restores mounted actor height on the rendering loop',
    );
    expect(
      scene.wing!.root.matrix.storage[13],
      closeTo(
        scene.character!.root.position.y +
            scene.character!.visual.matrix.storage[13] +
            scene.wingHeight,
        .001,
      ),
    );
    passed.add(
      'Wing and rider remain in the same coordinate frame after loading a map',
    );
    await screenshot('native_mount_wings_sky');
    await scene.selectCreature(null, 'mount');
    await scene.selectCreature(c.creatures.first, 'enemy');
    await scene.attack();
    await tester.pump(const Duration(milliseconds: 150));
    expect(scene.combat.active, isTrue);
    passed.add('Combat launches with visible opponent');
    scene.resetCombat();
    scene.combat.counterattack = false;
    final attacked = scene.combat.target;
    await scene.attack();
    await scene.addOpponent(c.creatures.first);
    final newlySelected = scene.combat.target;
    expect(newlySelected, isNot(attacked));
    await waitFor(
      () => (scene.combat.health[attacked] ?? 0) < scene.combat.maxHealth,
      'An in-flight attack remains bound to its original opponent',
    );
    expect(scene.combat.health[newlySelected], scene.combat.maxHealth);
    passed.add('Multiple opponents keep independent health');
    scene.resetCombat();
    scene.combat.counterattack = false;
    await scene.attack();
    await waitFor(
      () => scene.combat.inGuard,
      'Attack enters guard activity window',
    );
    // Allow the actual monotonic scene update to expire the eight-second window.
    await waitFor(
      () => !scene.combat.inGuard,
      'Guard ends eight seconds after the last given/received hit',
    );
    await waitFor(
      () => scene.character!.idle == scene.character!.normal,
      'Out-of-combat idle restored',
    );
    scene.resetCombat();
    scene.clearMovement();
    scene.clearOpponents();
    await scene.setWorld(c.worlds.firstWhere((p) => p.endsWith('/stream.wld')));
    await scene.game.loaded!.settle();
    final resident = scene.game.loaded!.residentChunks;
    expect(resident, lessThan(80));
    await scene.teleport(1850, 1850);
    await scene.game.loaded!.settle();
    expect(scene.game.loaded!.releasedChunks, greaterThan(0));
    expect(scene.game.loaded!.residentChunks, lessThan(100));
    expect(scene.game.loaded!.floorAt(1850, 1850, 0), 0);
    passed.add('Large map streams proximity and frees departed native sectors');
    await screenshot('native_streaming');
    await scene.setWorld(null);
    await scene.installExtras(
      ExtraMotionLibrary.decode(
        await File('$input/Extras/flight.json.gz').readAsBytes(),
      ),
    );
    await scene.selectCreature(c.wings.first, 'wing');
    expect(scene.flightEnabled, false);
    expect(scene.flying, false);
    expect(scene.wingAutoMotion, true);
    expect(scene.wing!.clip, scene.wing!.clips['Reposo']);
    (state.focus as FocusNode).requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.backslash,
      physicalKey: PhysicalKeyboardKey.intlBackslash,
    );
    await tester.sendKeyRepeatEvent(
      LogicalKeyboardKey.backslash,
      physicalKey: PhysicalKeyboardKey.intlBackslash,
    );
    await waitFor(
      () => scene.flightEnabled,
      'ISO < flight key reached editor controller',
    );
    expect(scene.walkZ, -1);
    expect(scene.running, true);
    passed.add(
      'Physical ISO key toggles flight once without cancelling held sprint',
    );
    await tester.sendKeyUpEvent(
      LogicalKeyboardKey.backslash,
      physicalKey: PhysicalKeyboardKey.intlBackslash,
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
    scene.clearMovement();
    await waitFor(
      () =>
          scene.flying &&
          scene.character!.clip == scene.character!.hover &&
          scene.wing!.clip == scene.wing!.clips['Respirar'],
      'Manual flight enters character hover and original wing air loop',
    );
    scene.wingYaw = .65;
    scene.updateAttachments();
    final rotated = scene.wing!.root.matrix.storage.toList();
    scene.wingYaw = 0;
    scene.updateAttachments();
    expect(scene.wing!.root.matrix.storage.toList(), isNot(equals(rotated)));
    scene.wingYaw = .65;
    scene.setMovement(0, -1);
    await waitFor(
      () =>
          scene.character!.clip == scene.character!.flight &&
          scene.wing!.clip == scene.wing!.clips['Correr'],
      'Moving flight uses supplemental body motion and original wing run slot',
    );
    scene.clearMovement();
    await waitFor(
      () => scene.wing!.clip == scene.wing!.clips['Respirar'],
      'Stopping in air returns the wing to its original breathing slot',
    );
    await scene.selectCreature(null, 'wing');
    await scene.selectCreature(c.wings.first, 'wing');
    expect(scene.wingYaw, closeTo(.65, .0001));
    expect(scene.flightEnabled, false);
    await scene.toggleFlight();
    passed.add('Wing horizontal rotation is local and restored per resource');
    await screenshot('native_supplemental_flight');
    scene.clearMovement();
    await scene.selectCreature(c.creatures.first, 'enemy');
    scene.combat.counterattack = false;
    await waitFor(
      () => scene.flightState.height > .25,
      'Wing hover settles above the ground',
    );
    final airTarget = scene.combat.target;
    await scene.attack();
    expect(scene.flightState.pendingTarget, airTarget);
    expect(scene.combat.active, false);
    await waitFor(
      () => scene.combat.active,
      'Queued aerial attack starts only after landing',
    );
    expect(scene.flightState.grounded, true);
    await screenshot('native_grounded_wing_attack');
    await scene.selectCreature(null, 'wing');
    scene.resetCombat();
    await waitFor(
      () => scene.character!.idle == scene.character!.normal,
      'Removing wings restores original ground animations',
    );
    await scene.selectCreature(c.mounts.first, 'mount');
    expect(scene.combatClips, isNotEmpty);
    final mountedTarget = scene.combat.target;
    await scene.attack();
    await waitFor(
      () => scene.character!.clip!.source.contains('mounted_sword'),
      'Mounted attack uses its own isolated supplemental pose',
    );
    await waitFor(
      () => scene.combat.health[mountedTarget]! < scene.combat.maxHealth,
      'Mounted impact changes only target health',
    );
    await screenshot('native_mounted_attack');
    scene.resetCombat();
    await scene.selectCreature(null, 'mount');
    final archive = await Library.fromArchive('$input.sah', '$input.saf');
    final archiveCatalog = Catalog(archive);
    await archiveCatalog.load((_) {});
    expect(archiveCatalog.archetypes.length, c.archetypes.length);
    final model = archiveCatalog.archetypes.first.base(Slot.upper)!.meshPath;
    expect(await archive.read(model), await c.library.read(model));
    scene.catalog = archiveCatalog;
    state.catalog = archiveCatalog;
    await scene.setAppearance(
      Appearance.initial(archiveCatalog.archetypes.first),
    );
    expect(scene.character, isNotNull);
    await scene.equip(scene.availableWeapons.first);
    await scene.equipShield(scene.availableShields.first);
    expect(scene.weapon, isNotNull);
    expect(scene.shield, isNotNull);
    passed.add(
      'SAH index + SAF random access feeds the same native actor/weapon renderer',
    );
    await screenshot('native_archive_source');
    await state.exportArchiveReport();
    passed.add(
      'Archive diagnostics can be exported after successful native loading',
    );
    // The editor runs in the real window. No dialogs are mocked or tests disabled.
    await tester.tap(find.byKey(const ValueKey('open-data-editor')));
    await waitFor(
      () => find.byType(DataEditorPage).evaluate().isNotEmpty,
      'Centered toolbar opens the dedicated editor',
    );
    if (find.byIcon(Icons.folder_open).evaluate().isNotEmpty) {
      await tester.tap(find.byIcon(Icons.folder_open));
      await tester.pump(const Duration(milliseconds: 300));
    }
    await tester.tap(find.text('dbmonsterdata.sdata'));
    await waitFor(
      () => find.text('Oro mínimo (Money1)').evaluate().isNotEmpty,
      'Native editor parses monster economy fields',
    );
    await tester.tap(find.byKey(const ValueKey('edit-selected-record')));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.enterText(
      find.byKey(const ValueKey('record-field-money1')),
      '-1',
    );
    await tester.tap(find.byKey(const ValueKey('record-accept')));
    await waitFor(
      () => find.text('-1').evaluate().isNotEmpty,
      'Signed negative survives native editor interaction',
    );
    await tester.pump(const Duration(milliseconds: 350));
    final editorBoundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('data-editor-capture')),
    );
    final editorImage = await editorBoundary.toImage();
    final editorBytes = await editorImage.toByteData(
      format: ui.ImageByteFormat.png,
    );
    editorImage.dispose();
    await File(
      '${output.path}/native_editor.png',
    ).writeAsBytes(editorBytes!.buffer.asUint8List());
    await tester.tap(find.text('Deshacer'));
    await waitFor(
      () => find.text('-1').evaluate().isEmpty,
      'Undo restores the original economy value',
    );
    final dynamic editorState = tester.state(find.byType(DataEditorPage));
    await editorState.openTable('monster/fixture.mon');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.byKey(const ValueKey('edit-selected-record')));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.text('Ver modelo / animaciones'));
    await waitFor(
      () => find.byType(NativeModelPreview).evaluate().isNotEmpty,
      'MON resolves a real preview from its own mesh and DDS',
    );
    final dynamic preview = tester.state(find.byType(NativeModelPreview));
    await waitFor(
      () => preview.ready == true,
      'Second native GL preview initializes',
    );
    expect(preview.error, isNull);
    expect(preview.actor.parts, isNotEmpty);
    await preview.chooseClip('Correr');
    await tester.pump(const Duration(milliseconds: 200));
    expect(preview.error, isNull);
    expect(preview.actor.clip, isNotNull);
    passed.add(
      'Record preview renders original-format mesh, DDS and MON ANI in a second native context',
    );
    await tester.tap(find.byKey(const ValueKey('model-preview-close')));
    await tester.pump(const Duration(milliseconds: 350));
    // Close the unchanged record; then return to the viewer, whose context
    // must still work after disposing the temporary preview.
    await tester.tap(find.byTooltip('Cerrar registro'));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.byIcon(Icons.arrow_back));
    await waitFor(
      () => find.byType(DataEditorPage).evaluate().isEmpty,
      'Closing editor returns to unchanged native viewer',
    );
    final exportDir = await Directory.systemTemp.createTemp(
      'shaiya-export-integration-',
    );
    try {
      final result = await ArchiveExport.extract(
        archive.archive!,
        exportDir,
        control: ExportControl(),
        progress: (_) {},
      );
      expect(
        await File('${result.folder}/$model').readAsBytes(),
        await archive.read(model),
      );
      const tablePath = 'binarysdata/dbmonsterdata.sdata';
      final original = await archive.read(tablePath);
      final doc = EditorReader.open(original, tablePath);
      final money = doc
          .fields(0)
          .firstWhere((f) => f.spec.name.toLowerCase() == 'money1');
      doc.edit(0, money, '-1');
      final repacked = await ArchiveExport.repack(
        archive.archive!,
        exportDir,
        replacements: {tablePath: doc.exportBytes()},
        control: ExportControl(),
        progress: (_) {},
      );
      final reopened = await Library.fromArchive(
        '${repacked.folder}/data.sah',
        '${repacked.folder}/data.saf',
      );
      final verified = EditorReader.open(
        await reopened.read(tablePath),
        tablePath,
      );
      expect(
        verified.read(
          verified
              .fields(0)
              .firstWhere((f) => f.spec.name.toLowerCase() == 'money1'),
        ),
        '-1',
      );
      expect(await archive.read(tablePath), original);
      const otherValue = '-8';
      final currentHash = sha256
          .convert(await reopened.read(tablePath))
          .toString();
      verified.edit(
        0,
        verified
            .fields(0)
            .firstWhere((f) => f.spec.name.toLowerCase() == 'money1'),
        otherValue,
      );
      await ArchiveWriter.writeInPlace(
        reopened.archive!,
        {tablePath: verified.exportBytes()},
        expectedHashes: {tablePath: currentHash},
        control: ExportControl(),
        progress: (_) {},
      );
      final committed = EditorReader.open(
        await reopened.read(tablePath),
        tablePath,
      );
      expect(
        committed.read(
          committed
              .fields(0)
              .firstWhere((f) => f.spec.name.toLowerCase() == 'money1'),
        ),
        otherValue,
      );
      passed.add(
        'Saving over the same SAH/SAF on Windows invalidates the read view and preserves signed values',
      );
      reopened.dispose();
      final packed = await DirectoryPack.build(
        Directory(input!),
        exportDir,
        control: ExportControl(),
        progress: (_) {},
      );
      final built = await Library.fromArchive(
        '${packed.folder}/data.sah',
        '${packed.folder}/data.saf',
      );
      expect(await built.read(model), await archive.read(model));
      built.dispose();
      passed.add(
        'Native Windows builds a readable SAH/SAF from the DATA folder',
      );
      passed.add(
        'Windows extraction and new SAH/SAF pair preserve originals and edited signed values',
      );
    } finally {
      await exportDir.delete(recursive: true);
    }
    expect(tester.takeException(), isNull);
    await File('${output.path}/result.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'checks': passed,
        'data': 'Own synthetic fixture; no game assets in CI',
        'platform': Platform.operatingSystem,
        'native_render': true,
      }),
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 500));
  }, timeout: const Timeout(Duration(minutes: 6)));
}
