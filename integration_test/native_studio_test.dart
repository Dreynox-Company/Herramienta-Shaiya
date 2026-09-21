import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:herramienta_shaiya/main.dart';
import 'package:herramienta_shaiya/render/studio_scene.dart';

void main(){
 IntegrationTestWidgetsFlutterBinding.ensureInitialized();
 testWidgets('native DATA rendering and locomotion regression',(tester)async{
  final input=Platform.environment['SHAIYA_FIXTURE_PATH'];
  expect(input,isNotNull,reason:'Set SHAIYA_FIXTURE_PATH to the generated synthetic fixture.');
  final output=Directory(Platform.environment['SHAIYA_QA_PATH']??'qa-native');await output.create(recursive:true);
  final passed=<String>[];
  await tester.pumpWidget(ShaiyaApp(initialData:input));
  final dynamic state=tester.state(find.byType(StudioPage));
  final scene=state.scene as StudioScene;
  Future<void> waitFor(bool Function() condition,String name)async{
   final deadline=DateTime.now().add(const Duration(seconds:45));
   while(!condition()&&DateTime.now().isBefore(deadline)){
    await tester.pump(const Duration(milliseconds:40));await Future<void>.delayed(const Duration(milliseconds:40));
   }
   expect(condition(),isTrue,reason:'$name; ${scene.status}');passed.add(name);
  }
  Future<void> screenshot(String name)async{
   await tester.pump(const Duration(milliseconds:120));
   final boundary=(state.captureKey as GlobalKey).currentContext!.findRenderObject() as RenderRepaintBoundary;
   final image=await boundary.toImage();final bytes=await image.toByteData(format:ui.ImageByteFormat.png);image.dispose();
   expect(bytes,isNotNull);await File('${output.path}/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  }
  await waitFor(()=>scene.character!=null&&!scene.busy&&state.catalog!=null,'Loaded native mesh, texture, catalog and skeletal clips');
  expect(scene.character!.clip!.source.toLowerCase(),endsWith('_000_normal.ani'));passed.add('Initial standing idle, not swimming');
  (state.focus as FocusNode).requestFocus();await tester.pump();
  final startZ=scene.character!.root.position.z;
  await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
  await waitFor(()=>scene.character!.clip==scene.character!.walk,'W chooses walk');
  await waitFor(()=>scene.character!.root.position.z<startZ-.05,'W translates only while walking');
  final time=scene.character!.time;
  await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyW);await tester.pump(const Duration(milliseconds:120));
  expect(scene.character!.time,greaterThan(time));passed.add('Key repeat does not restart the clip');
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await waitFor(()=>scene.character!.clip==scene.character!.run,'W + Shift chooses run');
  await screenshot('native_run');
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await waitFor(()=>scene.character!.clip==scene.character!.walk,'Shift released with W held returns to walk');
  await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
  await waitFor(()=>scene.character!.clip==scene.character!.idle,'Releasing W returns to idle');
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftRight);await tester.pump(const Duration(milliseconds:160));
  expect(scene.character!.clip,scene.character!.idle);await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftRight);passed.add('Shift alone leaves the character at rest');
  await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
  await waitFor(()=>scene.character!.clip==scene.character!.walk,'Walking before focus loss');
  (state.focus as FocusNode).unfocus();
  await waitFor(()=>scene.walkX==0&&scene.walkZ==0&&scene.character!.clip==scene.character!.idle,'Focus loss cancels held movement and restores idle');
  await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
  final c=scene.catalog!;
  await scene.selectCreature(c.mounts.first,'mount');await scene.selectCreature(c.wings.first,'wing');
  (state.focus as FocusNode).requestFocus();await tester.pump();
  await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
  await waitFor(()=>scene.mount!.clip==scene.mount!.clips['Caminar'],'Mounted W selects mount walk');
  expect(scene.character!.clip,scene.character!.riderMoving);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await waitFor(()=>scene.mount!.clip==scene.mount!.clips['Correr'],'Mounted Shift selects mount run');
  await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await waitFor(()=>scene.character!.clip==scene.character!.riderIdle,'Mounted release returns to riding idle');
  scene.riderHeight=1.25;scene.updateAttachments();final wingY=scene.wing!.root.matrix.storage[13];
  scene.riderHeight=3.75;scene.updateAttachments();expect(scene.wing!.root.matrix.storage[13]-wingY,closeTo(2.5,.001));passed.add('Wing inherits seat height once');
  await scene.selectCreature(c.mounts[1],'mount');await scene.selectCreature(c.mounts.first,'mount');
  expect(scene.riderHeight,closeTo(3.75,.001));passed.add('Mount-specific seat calibration is restored');
  // Restore a reasonable visual seat after the intentionally exaggerated delta test.
  scene.riderHeight=.7;scene.updateAttachments();
  await scene.setWorld(c.worlds.first);
  expect(scene.sky,isNotNull);expect(scene.environmentParts,isNotEmpty);passed.add('Exterior terrain and sky are rendered through original format readers');
  await waitFor(()=>(scene.character!.root.position.y-scene.groundY-scene.riderHeight).abs()<.001,'Map transition restores mounted actor height on the rendering loop');
  expect(scene.wing!.root.matrix.storage[13],closeTo(scene.character!.root.position.y+scene.wingHeight,.001));
  passed.add('Wing and rider remain in the same coordinate frame after loading a map');
  await screenshot('native_mount_wings_sky');
  await scene.selectCreature(null,'mount');
  await scene.selectCreature(c.creatures.first,'enemy');
  await scene.attack();await tester.pump(const Duration(milliseconds:150));
  expect(scene.combat.active,isTrue);passed.add('Combat launches with visible opponent');
  scene.resetCombat();scene.clearMovement();
  expect(tester.takeException(),isNull);
  await File('${output.path}/result.json').writeAsString(const JsonEncoder.withIndent('  ').convert({'checks':passed,'data':'Own synthetic fixture; no game assets in CI','platform':Platform.operatingSystem,'native_render':true}));
  await tester.pumpWidget(const SizedBox());await tester.pump(const Duration(milliseconds:500));
 },timeout:const Timeout(Duration(minutes:4)));
}
