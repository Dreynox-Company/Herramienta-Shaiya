import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:convert';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:three_js/three_js.dart' as three;
import '../core/formats.dart';
import '../data/catalog.dart';
import '../data/library.dart';
import '../input/viewport_movement_input.dart';
import '../render/studio_scene.dart';
import 'game_stage.dart';
import 'offline_backend.dart';
import 'server_metadata.dart';
import 'screens/character_create_screen.dart';
import 'screens/connecting_screen.dart';
import 'screens/server_select_screen.dart';
import 'screens/character_select_screen.dart';
import 'screens/faction_screen.dart';
import 'screens/world_hud.dart';
import 'shaiya_widgets.dart';
import 'ui_asset.dart';

class GameClientPage extends StatefulWidget {
  final String? initialData;
  final GameStage? initialStage;final String? qaMarker;
  const GameClientPage({super.key,this.initialData,this.initialStage,this.qaMarker});
  @override State<GameClientPage> createState()=>_GameClientPageState();
}

class _GameClientPageState extends State<GameClientPage> {
  late final StudioScene scene;
  late final three.ThreeJS renderer;
  late final OfflineBackend backend;
  final focus=FocusNode();
  final nameController=TextEditingController(text:'DreynoxLocal');

  Catalog? catalog;
  UiAssetCache? ui;
  SvmapData? svmap;
  ServerMetadata? metadata;
  int questId=1;
  GameStage stage=GameStage.connecting;
  bool loading=true;
  bool characterCreated=false;
  bool questOpen=true;
  String faction='light';
  String progress='Inicializando cliente Flutter…';
  int classIndex=0;
  int genderIndex=0;
  int createTab=0;
  int faceIndex=0;
  int hairIndex=0;
  int modeIndex=0;
  double gestureScale=1;
  final messages=<String>['[Notice] Laboratorio local'];
  final captureKey=GlobalKey();

  Future<void> _signalQaReady() async {
    final path=Platform.environment['SHAIYA_QA_READY_FILE'];
    if(path==null||path.isEmpty)return;
    try{
      final payload={
        'ready':true,
        'stage':stage.name,
        'loading':loading,
        'catalog':{
          'resources':catalog?.library.files.length??0,
          'archetypes':catalog?.archetypes.length??0,
          'npcs':catalog?.npcs.length??0,
          'creatures':catalog?.creatures.length??0,
          'worlds':catalog?.worlds.length??0,
        },
        'scene':{
          'world':scene.worldPath,
          'actors':scene.gameActors.length,
          'character':scene.character!=null,
          'originX':scene.originX,
          'originZ':scene.originZ,
        },
        'metadata':{
          'npcs':metadata?.npcs.length??0,
          'quests':metadata?.quests.length??0,
        },
        'backendReady':backend.ready,
        'questId':questId,
      };
      final file=File(path);
      await file.parent.create(recursive:true);
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(payload),flush:true);
    }catch(e){
      messages.insert(0,'[QA] No se pudo escribir READY: '+e.toString());
    }
  }

  Future<void> _signalQaError(Object error) async {
    final path=Platform.environment['SHAIYA_QA_READY_FILE'];
    if(path==null||path.isEmpty)return;
    try{
      final file=File(path);
      await file.parent.create(recursive:true);
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert({
        'ready':false,
        'stage':stage.name,
        'error':error.toString(),
      }),flush:true);
    }catch(_){}
  }

  @override void initState(){
    super.initState();
    backend=OfflineBackend((s){
      messages.insert(0,'[Backend] '+s);
      if(mounted)setState(()=>progress=s);
    });
    scene=StudioScene((s){if(mounted)setState(()=>progress=s);});
    renderer=three.ThreeJS(
      settings:three.Settings(
        clearColor:0x000000,
        antialias:true,
        enableShadowMap:false,
        toneMapping:three.NoToneMapping,
      ),
      setup:()=>scene.setup(renderer),
      onSetupComplete:(){
        if(widget.initialData!=null){
          unawaited(connect(widget.initialData!));
        }else if(mounted){
          setState(()=>loading=false);
        }
      },
    );
    scene.addListener(_refresh);
  }

  void _refresh(){if(mounted)setState((){});}

  @override void dispose(){
    unawaited(backend.stop());
    scene.removeListener(_refresh);
    scene.dispose();
    renderer.dispose();
    focus.dispose();
    nameController.dispose();
    super.dispose();
  }

  Future<void> chooseData() async {
    setState(()=>loading=true);
    try{
      final lib=await Library.choose((s){if(mounted)setState(()=>progress=s);});
      if(lib==null){setState(()=>loading=false);return;}
      await _connectLibrary(lib);
    }catch(e){
      await _signalQaError(e);
      setState((){loading=false;progress=e.toString();});
    }
  }

  Future<void> connect(String path) async {
    setState(()=>loading=true);
    try{
      final lib=await Library.fromDirectory(
        path,
        (s){if(mounted)setState(()=>progress=s);},
      );
      await _connectLibrary(lib);
    }catch(e){
      await _signalQaError(e);
      setState((){loading=false;progress=e.toString();});
    }
  }

  Future<void> _connectLibrary(Library lib) async {
    final requested=widget.initialStage;
    final c=Catalog(lib);
    catalog=c;
    ui=UiAssetCache(lib);

    // En una partida normal mostramos el mismo estado "Connecting..." mientras
    // se preparan backend y catálogo. Las pruebas directas de una etapa omiten
    // esta transición.
    if(requested==null&&mounted){
      stage=GameStage.connecting;
      loading=false;
      setState((){});
    }

    final started=DateTime.now();
    await backend.start();
    await c.load((s){if(mounted)setState(()=>progress=s);});
    metadata=await ServerMetadata.load();
    scene.catalog=c;
    await _applyDefaultAppearance();

    stage=requested??GameStage.serverSelect;
    if(stage==GameStage.characterSelect||stage==GameStage.characterCreate||stage==GameStage.characterMode){
      if(stage==GameStage.characterMode){createTab=2;}
      await _prepareSelectionWorld();
      characterCreated=stage==GameStage.characterSelect;
    }else if(stage==GameStage.world){
      characterCreated=true;
      await _enterWorld();
    }else if(requested==null){
      final elapsed=DateTime.now().difference(started);
      if(elapsed<const Duration(milliseconds:1300)){
        await Future<void>.delayed(const Duration(milliseconds:1300)-elapsed);
      }
      stage=GameStage.serverSelect;
    }

    messages.insert(
      0,
      '[Sistema] '+c.npcs.length.toString()+' NPC · '+
        c.creatures.length.toString()+' criaturas · '+
        c.worlds.length.toString()+' mapas.',
    );
    if(mounted)setState(()=>loading=false);
    await _signalQaReady();
    await _markQaReady();
    focus.requestFocus();
  }

  Future<void> _markQaReady() async {
    final path=widget.qaMarker;
    if(path==null||path.isEmpty)return;
    try{
      final payload={
        'stage':stage.name,
        'loading':loading,
        'character':scene.character!=null,
        'world':scene.worldPath,
        'npcs':scene.gameActors.length,
        'timestamp':DateTime.now().toIso8601String(),
      };
      await File(path).writeAsString(jsonEncode(payload),flush:true);
    }catch(e){messages.insert(0,'[QA] '+e.toString());}
  }

  Future<void> _applyDefaultAppearance() async {
    final c=catalog!;
    final preferred=faction=='light'
      ?(genderIndex==0?'humf':'huwf')
      :(genderIndex==0?'demf':'dewf');
    final a=c.archetypes.where((x)=>x.id.toLowerCase()==preferred).firstOrNull
      ??c.archetypes.where((x)=>faction=='light'
        ?['human','elf'].contains(x.race)
        :['vile','deatheater'].contains(x.race)).firstOrNull
      ??c.archetypes.first;
    var look=Appearance.initial(a);
    final faces=a.parts[Slot.face]??const <PartRecord>[];
    final hairs=a.parts[Slot.hair]??const <PartRecord>[];
    if(faces.isNotEmpty){look=look.withPart(Slot.face,faces[faceIndex.clamp(0,faces.length-1)]);}
    if(hairs.isNotEmpty){look=look.withPart(Slot.hair,hairs[hairIndex.clamp(0,hairs.length-1)]);}
    await scene.setAppearance(look);
  }

  Future<void> _prepareSelectionWorld() async {
    final c=catalog!;
    final wanted=faction=='light'?'world/select_a.wld':'world/select_b.wld';
    final path=c.library.files.containsKey(wanted)
      ?wanted
      :c.worlds.where((p)=>baseName(p).toLowerCase()=='select_a.wld').firstOrNull;
    if(path!=null){
      try{await scene.setWorld(path);}
      catch(e){messages.insert(0,'[Selección] '+e.toString());}
    }else{
      await scene.setWorld(null);
    }
    scene.yaw=math.pi;
    scene.pitch=.03;
    scene.distance=5.4;
    scene.targetY=1.25;
    scene.updateCamera();
  }

  Future<SvmapData?> _loadSvmap() async {
    final exe=File(Platform.resolvedExecutable).parent.path;
    final cwd=Directory.current.path;
    final candidates=<String>[
      exe+'/server/maps/1.svmap',
      exe+'/servicios/world/config/maps/1.svmap',
      cwd+'/server/maps/1.svmap',
      cwd+'/servicios/world/config/maps/1.svmap',
    ];
    for(final path in candidates){
      final file=File(path);
      if(!await file.exists())continue;
      try{return SvmapData.parse(await file.readAsBytes(),path);}
      catch(e){messages.insert(0,'[SVMAP] '+e.toString());}
    }
    return null;
  }

  Future<void> _enterWorld() async {
    if(mounted)setState(()=>loading=true);
    final c=catalog!;
    svmap??=await _loadSvmap();
    var world=c.worlds.where((p)=>baseName(p).toLowerCase()=='1.wld').firstOrNull;
    world??=c.worlds.firstOrNull;

    double? x,z;
    final map=svmap;
    if(map!=null){
      final side=map.spawns.where((s)=>faction=='light'
        ?(s.faction==0||s.faction==2)
        :(s.faction==1||s.faction==2)).firstOrNull;
      final spawn=side??map.spawns.firstOrNull;
      if(spawn!=null){x=spawn.center.x;z=spawn.center.z;}
    }

    if(world!=null){
      try{await scene.setWorld(world,x:x,z:z);}
      catch(e){messages.insert(0,'[Mapa] '+e.toString());}
    }

    scene.yaw=math.pi;
    scene.pitch=.10;
    scene.distance=7.2;
    scene.targetY=1.15;
    scene.updateCamera();

    if(map!=null){
      final meta=metadata;
      if(meta!=null){
        for(final p in map.npcs){
          final rule=meta.npcs[p.type.toString()+':'+p.id.toString()];
          if(rule!=null&&rule.outQuests.isNotEmpty){questId=rule.outQuests.first;break;}
        }
      }
      await scene.spawnGameActorsFromSvmap(map,npcModels:meta?.npcModels);
      messages.insert(
        0,
        '[Mapa] '+map.npcs.length.toString()+
          ' posiciones NPC · '+map.mobAreas.length.toString()+' áreas de mobs.',
      );
    }else{
      await scene.spawnGameNpcs(count:12);
      messages.insert(0,'[Mapa] Sin SVMAP: población visual de respaldo.');
    }

    stage=GameStage.world;
    questOpen=true;
    if(mounted)setState(()=>loading=false);
    focus.requestFocus();
    await Future<void>.delayed(const Duration(milliseconds:350));
    await _signalQaReady();
  }

  void _goServerSelected(){
    if(mounted)setState(()=>stage=GameStage.faction);
  }

  Future<void> _goFaction() async {
    scene.clearMovement();
    await scene.setWorld(null);
    if(mounted)setState(()=>stage=GameStage.faction);
  }

  Future<void> _goSelect() async {
    if(mounted)setState(()=>loading=true);
    await _applyDefaultAppearance();
    await _prepareSelectionWorld();
    if(mounted)setState((){stage=GameStage.characterSelect;loading=false;});
  }

  Future<void> _goCreate() async {
    if(mounted)setState(()=>loading=true);
    await _applyDefaultAppearance();
    await _prepareSelectionWorld();
    scene.distance=4.4;
    scene.targetY=1.15;
    scene.updateCamera();
    if(mounted)setState((){stage=GameStage.characterCreate;loading=false;});
  }

  Future<void> _finishCreate() async {
    if(nameController.text.trim().isEmpty)nameController.text='DreynoxLocal';
    characterCreated=true;
    await _prepareSelectionWorld();
    if(mounted)setState(()=>stage=GameStage.characterSelect);
  }

  Future<void> _changeGender(int value) async {
    genderIndex=value;
    if(mounted)setState((){});
    await _applyDefaultAppearance();
    scene.distance=4.4;
    scene.targetY=1.15;
    scene.updateCamera();
  }

  Future<void> _changeFace(int value) async {
    faceIndex=value;
    await _applyDefaultAppearance();
    if(mounted)setState((){});
  }

  Future<void> _changeHair(int value) async {
    hairIndex=value;
    await _applyDefaultAppearance();
    if(mounted)setState((){});
  }

  Widget _viewport()=>Positioned.fill(child:ViewportMovementInput(
    focusNode:focus,
    onChanged:(x,z,run){
      if(stage==GameStage.world)scene.setMovement(x,z,run:run);
    },
    onAction:(key){
      if(stage==GameStage.world&&key==LogicalKeyboardKey.keyR)scene.resetCombat();
    },
    child:Listener(
      onPointerSignal:(e){
        if(e is PointerScrollEvent&&stage!=GameStage.faction){
          scene.zoom(e.scrollDelta.dy>0?1.08:1/1.08);
        }
      },
      child:GestureDetector(
        behavior:HitTestBehavior.opaque,
        onTap:focus.requestFocus,
        onScaleStart:(_){gestureScale=1;focus.requestFocus();},
        onScaleUpdate:(d){
          if(stage==GameStage.faction)return;
          if(d.pointerCount==1){
            scene.orbit(d.focalPointDelta.dx,d.focalPointDelta.dy);
          }else{
            scene.zoom(gestureScale/d.scale);
            gestureScale=d.scale;
          }
        },
        child:const SizedBox.expand(),
      ),
    ),
  ));

  Widget _designSurface(Widget child)=>Positioned.fill(
    child:FittedBox(
      fit:BoxFit.contain,
      child:SizedBox(width:1024,height:742,child:child),
    ),
  );

  Widget _loadingOverlay()=>Positioned.fill(
    child:ColoredBox(
      color:const Color(0xee05070b),
      child:Center(child:Container(
        width:430,
        padding:const EdgeInsets.all(24),
        decoration:BoxDecoration(
          color:const Color(0xf0181511),
          border:Border.all(color:const Color(0xff796750)),
        ),
        child:Column(mainAxisSize:MainAxisSize.min,children:[
          const Text(
            'Shaiya',
            style:TextStyle(
              fontSize:46,fontStyle:FontStyle.italic,
              fontWeight:FontWeight.bold,color:Color(0xffffd15e),
            ),
          ),
          const SizedBox(height:10),
          if(loading)...[
            const CircularProgressIndicator(strokeWidth:2),
            const SizedBox(height:14),
            Text(
              progress,textAlign:TextAlign.center,
              style:const TextStyle(fontSize:11,color:Colors.white70),
            ),
          ]else...[
            Text(
              progress,textAlign:TextAlign.center,
              style:const TextStyle(fontSize:11,color:Colors.white70),
            ),
            const SizedBox(height:18),
            shaiyaRedButton(
              'Seleccionar DATA_Español',
              ()=>unawaited(chooseData()),
              width:190,height:38,
            ),
          ],
        ]),
      )),
    ),
  );

  @override Widget build(BuildContext context){
    final hasUi=catalog!=null&&ui!=null;
    final active=hasUi&&scene.character!=null;
    final usesRenderer=active&&![
      GameStage.connecting,
      GameStage.serverSelect,
      GameStage.faction,
    ].contains(stage);
    return Scaffold(
      backgroundColor:Colors.black,
      body:RepaintBoundary(key:captureKey,child:Stack(children:[
        if(usesRenderer)
          Positioned.fill(child:renderer.build())
        else
          const Positioned.fill(child:ColoredBox(color:Colors.black)),
        if(usesRenderer)_viewport(),
        if(hasUi)_designSurface(switch(stage){
          GameStage.connecting=>ConnectingScreen(
            ui:ui!,
            onQuit:()=>exit(0),
          ),
          GameStage.serverSelect=>ServerSelectScreen(
            ui:ui!,
            onNext:_goServerSelected,
            onQuit:()=>exit(0),
          ),
          GameStage.faction=>FactionScreen(
            ui:ui!,
            faction:faction,
            onFaction:(value)=>setState(()=>faction=value),
            onNext:()=>unawaited(_goSelect()),
          ),
          GameStage.characterSelect=>CharacterSelectScreen(
            ui:ui!,
            created:characterCreated,
            name:nameController.text,
            onCreate:()=>unawaited(_goCreate()),
            onDelete:()=>setState(()=>characterCreated=false),
            onStart:()=>unawaited(_enterWorld()),
            onBack:()=>unawaited(_goFaction()),
          ),
          GameStage.characterCreate||GameStage.characterMode=>CharacterCreateScreen(
            ui:ui!,
            nameController:nameController,
            classIndex:classIndex,
            genderIndex:genderIndex,
            tabIndex:createTab,
            faceIndex:faceIndex,
            hairIndex:hairIndex,
            modeIndex:modeIndex,
            onClass:(value)=>setState(()=>classIndex=value),
            onGender:(value)=>unawaited(_changeGender(value)),
            onTab:(value)=>setState(()=>createTab=value),
            onFace:(value)=>unawaited(_changeFace(value)),
            onHair:(value)=>unawaited(_changeHair(value)),
            onMode:(value)=>setState(()=>modeIndex=value),
            onBack:()=>unawaited(_goSelect()),
            onCreate:()=>unawaited(_finishCreate()),
            onZoomIn:()=>scene.zoom(.9),
            onZoomOut:()=>scene.zoom(1.1),
            onPause:(){scene.character?.playing=false;setState((){});},
            onReset:(){scene.character?.time=0;setState((){});},
          ),
          GameStage.world=>WorldHud(
            scene:scene,
            catalog:catalog!,
            characterName:nameController.text,
            ui:ui!,
            messages:messages,
            questOpen:questOpen,
            questId:questId,
            onAcceptQuest:(){
              setState(()=>questOpen=false);
              final q=catalog!.spanishText?.quest(questId);
              messages.insert(0,'[Misión] '+(q?.name??'Misión aceptada'));
            },
            onCancelQuest:()=>setState(()=>questOpen=false),
          ),
        }),
        if(!hasUi||(loading&&widget.initialStage!=null))_loadingOverlay(),
      ])),
    );
  }
}
