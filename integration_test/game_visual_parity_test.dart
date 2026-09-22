import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:herramienta_shaiya/main.dart';
import 'package:herramienta_shaiya/game/game_client_page.dart';
import 'package:herramienta_shaiya/game/game_stage.dart';

void main(){
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('render real game stages for native parity',(tester) async {
    final input=Platform.environment['SHAIYA_PARITY_DATA']??Platform.environment['SHAIYA_FIXTURE_PATH'];
    expect(input,isNotNull,reason:'Set SHAIYA_PARITY_DATA or SHAIYA_FIXTURE_PATH.');
    final output=Directory(Platform.environment['SHAIYA_QA_PATH']??'qa-game-integration');
    await output.create(recursive:true);
    final requireReal=Platform.environment['SHAIYA_EXPECT_REAL_DATA']=='1';
    final report=<String,dynamic>{};

    tester.view.devicePixelRatio=1;
    tester.view.physicalSize=const Size(1024,742);
    addTearDown((){
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    Future<dynamic> load(GameStage stage) async {
      await tester.pumpWidget(ShaiyaApp(initialData:input,initialStage:stage));
      final finder=find.byType(GameClientPage);
      expect(finder,findsOneWidget);
      final dynamic state=tester.state(finder);
      final deadline=DateTime.now().add(requireReal?const Duration(minutes:5):const Duration(seconds:75));
      while(DateTime.now().isBefore(deadline)){
        await tester.pump(const Duration(milliseconds:40));
        await Future<void>.delayed(const Duration(milliseconds:40));
        if(state.catalog!=null&&!state.loading&&state.scene.character!=null)break;
      }
      expect(state.catalog,isNotNull,reason:'$stage catalog: ${state.progress}');
      expect(state.loading,isFalse,reason:'$stage loading: ${state.progress}');
      expect(state.scene.character,isNotNull,reason:'$stage character: ${state.progress}');
      if(requireReal&&stage==GameStage.characterSelect){
        expect(state.scene.backdropTexture,isNotNull,reason:'characterSelect must render the native selectbg backdrop.');
      }
      if(requireReal&&(stage==GameStage.characterCreate||stage==GameStage.characterMode)){
        expect(state.scene.world,isNotNull,reason:'$stage must render select_A/select_B world.');
      }
      if(requireReal&&stage==GameStage.world){
        expect(state.scene.world,isNotNull,reason:'world WLD must be loaded.');
        expect(state.svmap,isNotNull,reason:'world SVMAP must be loaded.');
        expect(state.metadata,isNotNull,reason:'server NPC/quest metadata must be loaded.');
        expect(state.scene.gameActors,isNotEmpty,reason:'world must contain rendered NPC/mob actors.');
        expect(state.scene.worldCollision,isNotNull,reason:'world must build SMOD collision data.');
        expect(state.scene.worldCollision!.triangles,isNotEmpty,reason:'world must expose native SMOD collision triangles.');
      }
      if(requireReal){
        final critical=switch(stage){
          GameStage.faction=><String>[
            'interface/countryselect/bg.tga',
            'interface/countryselect/light_select.tga',
            'interface/countryselect/text/lightnormal_usa.tga',
            'interface/countryselect/text/lightselect_usa.tga',
          ],
          GameStage.characterSelect=><String>[
            'interface/characterselect/selectbg.tga',
            'interface/characterselect/button/select_start_usa.tga',
          ],
          GameStage.characterCreate||GameStage.characterMode=><String>[
            'interface/charactermake/basicinfo_bg.tga',
            'interface/charactermake/classinfo/bg.tga',
            'interface/charactermake/button/mode_basic.tga',
          ],
          GameStage.world=><String>[
            'interface/main_stats_bar_bg.tga',
            'interface/main_map.tga',
            'interface/main_bottom.tga',
            'interface/quest/take.tga',
          ],
        };
        for(final path in critical){
          final decoded=await state.ui.load(path);
          expect(decoded,isNotNull,reason:'critical native UI texture did not decode: $path');
        }
      }
      await tester.pump(const Duration(milliseconds:650));
      return state;
    }

    Future<void> shot(dynamic state,String name) async {
      final boundary=state.captureKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image=await boundary.toImage(pixelRatio:1);
      final bytes=await image.toByteData(format:ui.ImageByteFormat.png);
      image.dispose();
      expect(bytes,isNotNull);
      await File('${output.path}/$name.png').writeAsBytes(bytes!.buffer.asUint8List(),flush:true);
    }

    for(final stage in [
      GameStage.faction,
      GameStage.characterSelect,
      GameStage.characterCreate,
      GameStage.characterMode,
      GameStage.world,
    ]){
      final state=await load(stage);
      await shot(state,stage.name);
      report[stage.name]={
        'progress':state.progress,
        'resources':state.catalog.library.files.length,
        'archetypes':state.catalog.archetypes.length,
        'npcs':state.catalog.npcs.length,
        'creatures':state.catalog.creatures.length,
        'worlds':state.catalog.worlds.length,
        'world':state.scene.worldPath,
        'backdrop':state.scene.backdropTexture!=null,
        'worldObjects':state.scene.world?.objects.length??0,
        'worldSky':state.scene.world?.skyFile??'',
        'svmapNpcGroups':state.svmap?.npcs.length??0,
        'svmapNpcWaypoints':state.svmap==null?0:(state.svmap.npcs as List).map<int>((dynamic p)=>(p.route as List).length).fold<int>(0,(int a,int b)=>a+b),
        'actors':state.scene.gameActors.length,
        'loadedWorldAssets':state.scene.loadedWorldAssets,
        'missingWorldAssets':state.scene.missingWorldAssets,
        'collisionTriangles':state.scene.worldCollision?.triangles.length??0,
        'originX':state.scene.originX,
        'originZ':state.scene.originZ,
        'questId':state.questId,
        'metadataNpcs':state.metadata?.npcs.length??0,
        'metadataQuests':state.metadata?.quests.length??0,
      };
      if(requireReal&&stage==GameStage.world){
        final actor=state.scene.character!;
        final fromX=actor.root.position.x,fromZ=actor.root.position.z;
        state.scene.setMovement(0,1);
        for(var i=0;i<60;i++)state.scene.tick(1/30);
        state.scene.clearMovement();
        state.scene.tick(1/30);
        await tester.pump(const Duration(milliseconds:250));
        final dx=actor.root.position.x-fromX,dz=actor.root.position.z-fromZ;
        final moved=math.sqrt(dx*dx+dz*dz);
        expect(moved,greaterThan(.5),reason:'world movement parity probe must advance the avatar.');
        await shot(state,'worldMoved');
        report['worldMoved']={
          'from':[fromX,fromZ],
          'to':[actor.root.position.x,actor.root.position.z],
          'distance':moved,
          'collisionTriangles':state.scene.worldCollision?.triangles.length??0,
        };
      }
      await tester.pumpWidget(const ColoredBox(color:Colors.black));
      await tester.pump(const Duration(seconds:2));
    }

    await File('${output.path}/integration-state.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'platform':Platform.operatingSystem,
        'realData':requireReal,
        'rendered':true,
        'size':[1024,742],
        'stages':report,
      }),
      flush:true,
    );
  },timeout:const Timeout(Duration(minutes:22)));
}
