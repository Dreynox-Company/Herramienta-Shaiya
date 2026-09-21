import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
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
import 'ps0032_protocol.dart';
import 'server_metadata.dart';
import 'screens/character_create_screen.dart';
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
  late final String uiLocale;
  final focus=FocusNode();
  final nameController=TextEditingController(text:'DreynoxLocal');

  Catalog? catalog;
  UiAssetCache? ui;
  SvmapData? svmap;
  ServerMetadata? metadata;
  Ps0032Client? protocolClient;
  PsWorldSession? liveWorld;
  PsWorldSnapshot? liveSnapshot;
  List<PsCharacterSlot> liveSlots=const [];
  bool liveProtocol=false;
  bool _movementSendFault=false;
  int questId=1;
  GameStage stage=GameStage.faction;
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
          'mobs':metadata?.mobs.length??0,
          'createRules':metadata?.createRules.length??0,
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
    final requestedLocale=(Platform.environment['SHAIYA_UI_LOCALE']??'spn').toLowerCase();
    uiLocale=requestedLocale=='usa'?'usa':'spn';
    backend=OfflineBackend((s){
      messages.insert(0,'[Backend] '+s);
      if(mounted)setState(()=>progress=s);
    });
    scene=StudioScene((s){if(mounted)setState(()=>progress=s);});
    scene.onPlayerMoved=_sendLiveMovement;
    scene.gridVisible=false;
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
    unawaited(_shutdownRuntime());
    scene.removeListener(_refresh);
    scene.dispose();
    renderer.dispose();
    focus.dispose();
    nameController.dispose();
    super.dispose();
  }

  bool get _qaVisual=>Platform.environment['SHAIYA_QA_DISABLE_BACKEND']=='1';

  Future<void> _shutdownRuntime() async {
    final world=liveWorld;
    liveWorld=null;liveSlots=const [];liveSnapshot=null;liveProtocol=false;_movementSendFault=false;
    if(world!=null){
      world.removePacketListener(_consumeLivePacket);
      try{await world.close();}catch(_){}
    }
    await backend.stop();
  }

  int _protocolProfession()=>const [0,1,5,2,3,4][classIndex.clamp(0,5)];
  int _protocolRace(){
    final firstRace=classIndex<=2;
    if(faction=='light')return firstRace?0:1;
    return firstRace?2:3;
  }
  int _protocolMode()=>modeIndex==1?3:2;
  int _uiClassFromProfession(int value)=>switch(value){0=>0,1=>1,5=>2,2=>3,3=>4,4=>5,_=>0};

  Future<void> _applyLiveSlot(PsCharacterSlot slot) async {
    if(!slot.exists)return;
    faction=(slot.race<=1)?'light':'fury';
    classIndex=_uiClassFromProfession(slot.profession);
    genderIndex=slot.gender.clamp(0,1);
    hairIndex=slot.hair;
    faceIndex=slot.face;
    modeIndex=slot.mode==3?1:0;
    if(slot.name.isNotEmpty)nameController.text=slot.name;
    characterCreated=true;
    await _applyDefaultAppearance();
  }

  Future<bool> _ensureLiveWorld() async {
    if(_qaVisual)return false;
    if(liveWorld!=null)return true;
    final started=await backend.start(faction:faction);
    if(!started)return false;
    final secret=backend.password;
    if(secret==null||secret.isEmpty)throw StateError('Backend offline sin secreto de sesión.');
    final client=Ps0032Client(trace:(s){
      messages.insert(0,'[ps0032] '+s);
      if(mounted)setState(()=>progress=s);
    });
    protocolClient=client;
    final login=await client.loginOffline(secret);
    final world=await client.openWorld(login);
    final expected=faction=='light'?0:1;
    if(world.faction!=expected){
      await world.close();
      throw StateError('La facción del slot (${world.faction}) no coincide con $faction.');
    }
    liveWorld=world;
    liveSlots=List<PsCharacterSlot>.unmodifiable(world.characters);
    liveProtocol=true;
    final existing=liveSlots.where((s)=>s.exists).firstOrNull;
    if(existing!=null)await _applyLiveSlot(existing);
    messages.insert(0,'[ps0032] Sesión World activa · ${liveSlots.where((s)=>s.exists).length} personaje(s).');
    return true;
  }
  int _wireAngle(double yaw){
    var angle=yaw%(math.pi*2);
    if(angle<0)angle+=math.pi*2;
    return angle.round()&0xffff;
  }

  void _sendLiveMovement(double x,double y,double z,double yaw,bool run){
    final world=liveWorld;
    if(world==null||stage!=GameStage.world||_qaVisual)return;
    unawaited(world.sendCharacterMove(
      x:x,y:y,z:z,angle:_wireAngle(yaw),run:run,
    ).catchError((Object e){
      if(!_movementSendFault){
        _movementSendFault=true;
        messages.insert(0,'[ps0032] Movimiento: '+e.toString());
        if(mounted)setState((){});
      }
    }));
  }

  bool _consumeLivePacket(PsPacket packet){
    switch(packet.type){
      case PsPacketType.mapNpcMove:
      case PsPacketType.mobMove:
      case PsPacketType.mapNpcLeave:
      case PsPacketType.mobLeave:
      case PsPacketType.mapNpcEnter:
      case PsPacketType.mobEnter:
      case PsPacketType.questList:
      case PsPacketType.questFinishedList:
        unawaited(_handleLivePacket(packet));
        return true;
      default:
        return false;
    }
  }

  Future<void> _handleLivePacket(PsPacket packet) async {
    final meta=metadata;
    try{
      switch(packet.type){
        case PsPacketType.mapNpcMove:
          final p=PsNpcMove.parse(packet);
          scene.moveLiveNpc(p.globalId,p.x,p.y,p.z);
          break;
        case PsPacketType.mobMove:
          final p=PsMobMove.parse(packet);
          scene.moveLiveMob(p.globalId,p.x,p.z);
          break;
        case PsPacketType.mapNpcLeave:
        case PsPacketType.mobLeave:
          scene.removeLiveActor(parseActorLeave(packet));
          break;
        case PsPacketType.mapNpcEnter:
          final p=PsNpcEnter.parse(packet);
          final questNpcKeys=meta==null
            ?null
            :meta.npcs.entries.where((e)=>e.value.outQuests.isNotEmpty).map((e)=>e.key).toSet();
          await scene.addLiveNpc(
            globalId:p.globalId,type:p.type,typeId:p.typeId,
            x:p.x,y:p.y,z:p.z,angle:p.angle,
            npcModels:meta?.npcModels,questNpcKeys:questNpcKeys,locale:uiLocale,
          );
          break;
        case PsPacketType.mobEnter:
          final p=PsMobEnter.parse(packet);
          await scene.addLiveMob(
            globalId:p.globalId,mobId:p.mobId,x:p.x,z:p.z,
            mobModels:meta?.mobModels,locale:uiLocale,
          );
          break;
        case PsPacketType.questList:
          final quests=parseQuestList(packet);
          if(quests.isNotEmpty){questId=quests.first.questId;questOpen=true;}
          break;
        case PsPacketType.questFinishedList:
          // Kept for state parity; finished quest badges will consume this next.
          break;
      }
      if(mounted)setState((){});
    }catch(e){
      messages.insert(0,'[ps0032] Paquete vivo '+packet.toString()+': '+e.toString());
      if(mounted)setState((){});
    }
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
    final c=Catalog(lib);
    await c.load((s){if(mounted)setState(()=>progress=s);});
    catalog=c;
    ui=UiAssetCache(lib);
    metadata=await ServerMetadata.load();
    scene.catalog=c;
    await _applyDefaultAppearance();

    stage=widget.initialStage??GameStage.faction;
    if(stage==GameStage.characterSelect||stage==GameStage.characterCreate||stage==GameStage.characterMode){
      if(stage==GameStage.characterMode){createTab=2;stage=GameStage.characterMode;}
      await _prepareSelectionWorld(creation:stage!=GameStage.characterSelect);
      characterCreated=stage==GameStage.characterSelect;
    }else if(stage==GameStage.world){
      characterCreated=true;
      await _enterWorld();
    }

    messages.insert(
      0,
      '[Sistema] '+c.npcs.length.toString()+' NPC · '+
        c.creatures.length.toString()+' criaturas · '+
        c.worlds.length.toString()+' mapas.',
    );
    await _preloadStageUi();
    if(mounted)setState(()=>loading=false);
    await _signalQaReady();
    await _markQaReady();
    focus.requestFocus();
  }

  Future<void> _preloadStageUi() async {
    final cache=ui;
    if(cache==null)return;
    final common=<String>[
      'interface/charactermake/button/navi_zoomin.tga',
      'interface/charactermake/button/navi_zoomout.tga',
    ];
    final paths=switch(stage){
      GameStage.faction=><String>[
        'interface/countryselect/bg.tga',
        'interface/countryselect/light_select.tga',
        'interface/countryselect/fury_select.tga',
        'interface/countryselect/text/lightnormal_$uiLocale.tga',
        'interface/countryselect/text/furynormal_$uiLocale.tga',
        'interface/countryselect/text/lightselect_$uiLocale.tga',
        'interface/countryselect/text/furyselect_$uiLocale.tga',
      ],
      GameStage.characterSelect=><String>[
        'interface/characterselect/selectbg.tga',
        'interface/characterselect/button/selectbtn_fi.tga',
        'interface/characterselect/button/selectbtn_disable.tga',
        'interface/characterselect/button/select_start_$uiLocale.tga',
      ],
      GameStage.characterCreate||GameStage.characterMode=><String>[
        'interface/charactermake/basicinfo_bg.tga',
        'interface/charactermake/appearance_bg.tga',
        'interface/charactermake/mode_bg.tga',
        'interface/charactermake/classinfo/bg.tga',
        'interface/charactermake/button/fighter_worrior.tga',
        'interface/charactermake/button/defender_guardian.tga',
        'interface/charactermake/button/priest_oracle.tga',
        'interface/charactermake/button/ranger_assassin.tga',
        'interface/charactermake/button/archer_hunter.tga',
        'interface/charactermake/button/mage_pagan.tga',
        'interface/charactermake/button/sexm.tga',
        'interface/charactermake/button/sexw.tga',
        'interface/charactermake/button/mode_basic.tga',
        'interface/charactermake/button/mode_ultimate.tga',
        ...common,
      ],
      GameStage.world=><String>[
        'interface/main_stats_bar_bg.tga',
        'interface/main_stats_bar.tga',
        'interface/create_fighter_button.tga',
        'interface/main_slot_3.tga',
        'interface/main_map.tga',
        'interface/minimap/1.tga',
        'interface/chat/chat.tga',
        'interface/main_bottom.tga',
        'interface/skillbar_bg.tga',
        'interface/main_bottom_btn_status.tga',
        'interface/main_bottom_btn_skill.tga',
        'interface/main_bottom_btn_item.tga',
        'interface/main_bottom_btn_quest.tga',
        'interface/main_bottom_btn_sub.tga',
        'interface/main_bottom_btn_guild.tga',
        'interface/main_bottom_btn_shop.tga',
        'interface/main_bottom_btn_option.tga',
        'interface/main_bottom_btn_event.tga',
        'interface/main_bottom_btn_helper.tga',
        'interface/quest/take.tga',
        'interface/quest/itemslot.tga',
      ],
    };
    await cache.preload(paths);
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

  void _applyCreationCamera(){
    // CharacterMake is rendered inside Login.wld -> DUN_LOGIN.dg.
    // Keep the avatar front-facing and offset it away from the left UI panel.
    scene.panX=-.72;
    scene.panZ=0;
    scene.yaw=0;
    scene.pitch=.025;
    scene.distance=3.85;
    scene.targetY=1.18;
    if(scene.character!=null){scene.character!.root.rotation.y=0;}
    scene.updateCamera();
  }

  Future<void> _prepareSelectionWorld({required bool creation}) async {
    final c=catalog!;
    if(!creation){
      await scene.setWorld(null);
      await scene.setSky(null);
      await scene.setBackdrop('interface/characterselect/selectbg.tga');
      scene.panX=-0.82;
      scene.panZ=0;
      scene.yaw=0;
      scene.pitch=.01;
      scene.distance=3.55;
      scene.targetY=1.16;
      scene.updateCamera();
      return;
    }

    await scene.setBackdrop(null);
    await scene.setSky(null);
    scene.panX=0;scene.panZ=0;

    // Static tracing of ps0032 separates the two presentation scenes:
    // CharacterMake references Login.wld; CharacterSelect references select_A/B.
    // Login.wld is a DUN world whose layout is DUN_LOGIN.dg.
    const wanted='world/login.wld';
    final path=c.library.files.containsKey(wanted)
      ?wanted
      :c.worlds.where((p)=>baseName(p).toLowerCase()=='login.wld').firstOrNull;
    if(path!=null){
      try{await scene.setWorld(path);}
      catch(e){messages.insert(0,'[Creación] '+e.toString());}
    }else{
      await scene.setWorld(null);
      messages.insert(0,'[Creación] Login.wld no existe en DATA.');
    }
    _applyCreationCamera();
  }

  Future<SvmapData?> _loadSvmap(int mapId) async {
    final exe=File(Platform.resolvedExecutable).parent.path;
    final cwd=Directory.current.path;
    final name=mapId.toString()+'.svmap';
    final candidates=<String>[
      exe+'/server/maps/'+name,
      exe+'/servicios/world/config/maps/'+name,
      cwd+'/server/maps/'+name,
      cwd+'/servicios/world/config/maps/'+name,
    ];
    for(final path in candidates){
      final file=File(path);
      if(!await file.exists())continue;
      try{return SvmapData.parse(await file.readAsBytes(),path);}
      catch(e){messages.insert(0,'[SVMAP] '+e.toString());}
    }
    return null;
  }

  Future<bool> _enterWorldLive() async {
    final connected=await _ensureLiveWorld();
    final world=liveWorld;
    if(!connected||world==null)return false;
    final selectedSlot=liveSlots.where((s)=>s.exists).firstOrNull;
    if(selectedSlot==null)throw StateError('No hay personaje real para entrar al mapa.');
    await _applyLiveSlot(selectedSlot);
    final selected=await world.selectCharacter(selectedSlot.id);
    final entered=await world.enterMap(collect:const Duration(seconds:5));
    final all=<PsPacket>[...selected.packets,...entered];
    final snapshot=PsWorldSnapshot.fromPackets(all);
    liveSnapshot=snapshot;
    final self=snapshot.self;
    final x=self?.x??selected.details.x;
    final y=self?.y??selected.details.y;
    final z=self?.z??selected.details.z;
    final angle=self?.angle??selected.details.angle;
    final mapId=selectedSlot.mapId;
    svmap=await _loadSvmap(mapId);
    final c=catalog!;
    var worldPath=c.worlds.where((p)=>baseName(p).toLowerCase()==mapId.toString()+'.wld').firstOrNull;
    worldPath??=c.worlds.firstOrNull;
    if(worldPath==null)throw StateError('DATA no contiene WLD para map '+mapId.toString()+'.');
    await scene.setBackdrop(null);
    scene.panX=0;scene.panZ=0;
    await scene.setWorld(worldPath,x:x,z:z);
    if(scene.character!=null){
      scene.character!.root.position.y=y;
      scene.character!.root.rotation.y=-angle.toDouble();
    }
    scene.yaw=math.pi+angle.toDouble();
    scene.pitch=.12;
    scene.distance=5.9;
    scene.targetY=1.18;
    scene.updateCamera();
    final meta=metadata;
    final questNpcKeys=meta==null
      ?null
      :meta.npcs.entries.where((e)=>e.value.outQuests.isNotEmpty).map((e)=>e.key).toSet();
    await scene.spawnGameActorsFromLive(
      npcs:snapshot.npcs.map((p)=>(
        globalId:p.globalId,type:p.type,typeId:p.typeId,
        x:p.x,y:p.y,z:p.z,angle:p.angle,
      )),
      mobs:snapshot.mobs.map((p)=>(globalId:p.globalId,mobId:p.mobId,x:p.x,z:p.z)),
      npcModels:meta?.npcModels,
      mobModels:meta?.mobModels,
      questNpcKeys:questNpcKeys,
      locale:uiLocale,
    );
    scene.groundY=y;
    if(scene.character!=null)scene.character!.root.position.y=y;
    world.addPacketListener(_consumeLivePacket);
    _movementSendFault=false;
    if(snapshot.quests.isNotEmpty)questId=snapshot.quests.first.questId;
    else questId=faction=='light'?3781:3792;
    messages.insert(0,'[ps0032] ENTER_MAP '+mapId.toString()+' · '+
      snapshot.npcs.length.toString()+' NPC · '+snapshot.mobs.length.toString()+' mobs · '+
      'pos '+x.toStringAsFixed(2)+'/'+y.toStringAsFixed(2)+'/'+z.toStringAsFixed(2)+'.');
    characterCreated=true;
    stage=GameStage.world;
    questOpen=true;
    if(mounted)setState(()=>loading=false);
    focus.requestFocus();
    await Future<void>.delayed(const Duration(milliseconds:250));
    await _signalQaReady();
    return true;
  }
  Future<void> _enterWorld() async {
    if(mounted)setState(()=>loading=true);
    if(!_qaVisual){
      try{
        if(await _enterWorldLive())return;
      }catch(e){
        messages.insert(0,'[ps0032] Entrada real falló; se usa fallback local: '+e.toString());
      }
    }
    await scene.setBackdrop(null);
    scene.panX=0;scene.panZ=0;
    final c=catalog!;
    // Tutorial quest shown by the native ps0032 client for a fresh level-1 character.
    questId=faction=='light'?3781:3792;
    final country=faction=='light'?0:1;
    final create=metadata?.createRule(country,classIndex);
    final mapId=create?.mapId??(faction=='light'?1:2);
    svmap=await _loadSvmap(mapId);
    var world=c.worlds.where((p)=>baseName(p).toLowerCase()==mapId.toString()+'.wld').firstOrNull;
    world??=c.worlds.firstOrNull;

    double? x=create?.x,z=create?.z;
    final map=svmap;
    if((x==null||z==null)&&map!=null){
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
    scene.pitch=.12;
    scene.distance=5.9;
    scene.targetY=1.18;
    scene.updateCamera();

    if(map!=null){
      final meta=metadata;
      final questNpcKeys=meta==null
        ?null
        :meta.npcs.entries.where((e)=>e.value.outQuests.isNotEmpty).map((e)=>e.key).toSet();
      await scene.spawnGameActorsFromSvmap(
        map,
        npcModels:meta?.npcModels,
        mobModels:meta?.mobModels,
        questNpcKeys:questNpcKeys,
        locale:uiLocale,
      );
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

  Future<void> _goFaction() async {
    scene.clearMovement();
    await scene.setWorld(null);
    if(!_qaVisual)await _shutdownRuntime();
    if(mounted)setState(()=>stage=GameStage.faction);
  }

  Future<void> _goSelect() async {
    if(mounted)setState(()=>loading=true);
    var connected=false;
    try{
      connected=await _ensureLiveWorld();
      if(connected){
        final existing=liveSlots.where((s)=>s.exists).firstOrNull;
        characterCreated=existing!=null;
        if(existing!=null)await _applyLiveSlot(existing);
        else await _applyDefaultAppearance();
      }else{
        await _applyDefaultAppearance();
      }
    }catch(e){
      liveProtocol=false;
      messages.insert(0,'[ps0032] No se pudo abrir la sesión real: $e');
      await _applyDefaultAppearance();
    }
    await _prepareSelectionWorld(creation:false);
    if(mounted)setState((){stage=GameStage.characterSelect;loading=false;});
  }

  Future<void> _goCreate() async {
    if(mounted)setState(()=>loading=true);
    await _applyDefaultAppearance();
    await _prepareSelectionWorld(creation:true);
    if(mounted)setState((){stage=GameStage.characterCreate;loading=false;});
  }

  Future<void> _finishCreate() async {
    final name=nameController.text.trim().isEmpty?'DreynoxLocal':nameController.text.trim();
    if(name.length>16){
      messages.insert(0,'[Creación] El nombre admite máximo 16 caracteres.');
      return;
    }
    nameController.text=name;
    if(!_qaVisual){
      if(mounted)setState(()=>loading=true);
      try{
        final connected=await _ensureLiveWorld();
        final world=liveWorld;
        if(!connected||world==null)throw StateError('World offline no disponible.');
        final empty=liveSlots.where((s)=>!s.exists).firstOrNull;
        if(empty==null)throw StateError('No quedan slots de personaje disponibles.');
        final slots=await world.createCharacter(
          slot:empty.slot,
          race:_protocolRace(),
          mode:_protocolMode(),
          hair:hairIndex,
          face:faceIndex,
          height:2,
          profession:_protocolProfession(),
          gender:genderIndex,
          name:name,
        );
        liveSlots=List<PsCharacterSlot>.unmodifiable(slots);
        final created=liveSlots.where((s)=>s.exists&&s.slot==empty.slot).firstOrNull
          ??liveSlots.where((s)=>s.exists).firstOrNull;
        if(created==null)throw StateError('El servidor confirmó CREATE_CHARACTER pero no devolvió el personaje.');
        await _applyLiveSlot(created);
        characterCreated=true;
        messages.insert(0,'[ps0032] Personaje creado por World · id '+created.id.toString()+'.');
      }catch(e){
        characterCreated=false;
        messages.insert(0,'[Creación] '+e.toString());
        if(mounted)setState(()=>loading=false);
        return;
      }
    }else{
      characterCreated=true;
    }
    await _prepareSelectionWorld(creation:false);
    if(mounted)setState((){stage=GameStage.characterSelect;loading=false;});
  }

  Future<void> _changeGender(int value) async {
    genderIndex=value;
    if(mounted)setState((){});
    await _applyDefaultAppearance();
    _applyCreationCamera();
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
    final active=catalog!=null&&ui!=null&&scene.character!=null;
    return Scaffold(
      backgroundColor:Colors.black,
      body:RepaintBoundary(key:captureKey,child:Stack(children:[
        // The renderer must be mounted from frame zero. Its onSetupComplete callback
        // starts DATA loading; mounting it only after catalog creation deadlocks startup.
        Positioned.fill(child:renderer.build()),
        if(stage==GameStage.faction||!active)
          const Positioned.fill(child:ColoredBox(color:Colors.black)),
        if(active&&stage!=GameStage.faction)_viewport(),
        if(active)_designSurface(switch(stage){
          GameStage.faction=>FactionScreen(
            ui:ui!,
            faction:faction,
            locale:uiLocale,
            onFaction:(value)=>setState(()=>faction=value),
            onNext:()=>unawaited(_goSelect()),
          ),
          GameStage.characterSelect=>CharacterSelectScreen(
            ui:ui!,
            created:characterCreated,
            name:nameController.text,
            locale:uiLocale,
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
            locale:uiLocale,
            ui:ui!,
            messages:messages,
            questOpen:questOpen,
            questId:questId,
            onAcceptQuest:(){
              setState(()=>questOpen=false);
              final q=catalog!.questText(uiLocale)?.quest(questId);
              messages.insert(0,'[Misión] '+(q?.name??'Misión aceptada'));
            },
            onCancelQuest:()=>setState(()=>questOpen=false),
          ),
        }),
        if(!active||loading)_loadingOverlay(),
      ])),
    );
  }
}
