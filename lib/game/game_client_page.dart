import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
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
  Ps0032Client? protocolClient;
  LoginSession? liveLogin;
  PsWorldSession? liveWorld;
  PsWorldSnapshot? liveSnapshot;
  StreamSubscription<PsPacket>? livePacketSubscription;
  Timer? movementTimer;
  bool movementSending=false;
  double? lastNetworkX,lastNetworkZ;
  bool lastNetworkMoving=false,lastNetworkRun=false;
  List<PsCharacterSlot> liveCharacters=<PsCharacterSlot>[];
  PsCharacterSlot? liveCharacter;
  final focus=FocusNode();
  final nameController=TextEditingController(text:'DreynoxLocal');

  Catalog? catalog;
  UiAssetCache? ui;
  SvmapData? svmap;
  ServerMetadata? metadata;
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
    movementTimer?.cancel();
    unawaited(livePacketSubscription?.cancel());
    if(liveWorld!=null)unawaited(liveWorld!.close());
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
    final backendStarted=await backend.start();
    final c=Catalog(lib);
    await c.load((s){if(mounted)setState(()=>progress=s);});
    catalog=c;
    ui=UiAssetCache(lib);
    metadata=await ServerMetadata.load();
    scene.catalog=c;
    if(backendStarted&&backend.password!=null){
      await _connectLiveProtocol(backend.password!);
    }
    if(liveCharacter!=null){
      _syncUiFromLiveCharacter(liveCharacter!);
    }
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

  int _protocolProfession(int index)=>const [0,1,5,2,3,4][index.clamp(0,5)];
  int _uiClassFromProfession(int profession){
    const map=<int,int>{0:0,1:1,5:2,2:3,3:4,4:5};
    return map[profession]??0;
  }
  int _protocolRace(){
    final firstGroup=classIndex<=2;
    if(faction=='light')return firstGroup?0:1;
    return firstGroup?2:3;
  }
  int _protocolMode()=>modeIndex==0?2:3;

  Future<void> _connectLiveProtocol(String password) async {
    try{
      protocolClient=Ps0032Client(trace:(s){
        messages.insert(0,'[ps0032] '+s);
        if(mounted)setState(()=>progress=s);
      });
      liveLogin=await protocolClient!.loginOffline(password);
      liveWorld=await protocolClient!.openWorld(liveLogin!);
      liveCharacters=liveWorld!.characters;
      liveCharacter=liveCharacters.where((s)=>s.exists&&!s.isDelete).firstOrNull;
      if(liveWorld!.faction==0)faction='light';
      if(liveWorld!.faction==1)faction='fury';
      characterCreated=liveCharacter!=null;
      messages.insert(0,'[ps0032] Sesión World real lista · ${liveCharacters.where((c)=>c.exists).length} personaje(s).');
    }catch(e){
      messages.insert(0,'[ps0032] Fallback visual: '+e.toString());
      try{await liveWorld?.close();}catch(_){}
      liveWorld=null;liveLogin=null;protocolClient=null;liveCharacters=<PsCharacterSlot>[];liveCharacter=null;
    }
  }

  void _syncUiFromLiveCharacter(PsCharacterSlot slot){
    if(slot.race<=1)faction='light';else faction='fury';
    genderIndex=slot.gender.clamp(0,1);
    classIndex=_uiClassFromProfession(slot.profession);
    faceIndex=slot.face.clamp(0,4);
    hairIndex=slot.hair.clamp(0,4);
    modeIndex=slot.mode>=3?1:0;
    if(slot.name.isNotEmpty)nameController.text=slot.name;
  }

  Future<void> _selectFactionAndContinue() async {
    if(mounted)setState(()=>loading=true);
    try{
      final session=liveWorld;
      if(session!=null){
        final selected=await session.setFaction(faction=='light'?0:1);
        messages.insert(0,'[ps0032] Facción confirmada por World: ${selected.faction}.');
      }
      await _goSelect();
    }catch(e){
      messages.insert(0,'[ps0032] No se pudo seleccionar facción: '+e.toString());
      if(mounted)setState(()=>loading=false);
    }
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
    // Native CharacterMake centers the avatar on the DUN_LOGIN circular dais.
    // The reference framebuffer gives ~560 px character height at 742 px.
    scene.panX=0;
    scene.panZ=0;
    scene.yaw=0;
    scene.pitch=.025;
    scene.distance=2.72;
    scene.targetY=1.06;
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
      scene.distance=3.25;
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

  Future<void> _enterWorld() async {
    if(mounted)setState(()=>loading=true);
    await scene.setBackdrop(null);
    scene.panX=0;scene.panZ=0;
    final c=catalog!;

    PsWorldSnapshot? networkSnapshot;
    var mapId=0;
    double? x,z;

    final session=liveWorld;
    if(session!=null){
      liveCharacter??=liveCharacters.where((s)=>s.exists&&!s.isDelete).firstOrNull;
      final current=liveCharacter;
      if(current==null){
        messages.insert(0,'[ps0032] No existe personaje para Game Start.');
        await _goCreate();
        if(mounted)setState(()=>loading=false);
        return;
      }
      try{
        final selected=await session.selectCharacter(current.id);
        final entered=await session.enterMap(collect:const Duration(seconds:5));
        networkSnapshot=PsWorldSnapshot.fromPackets(<PsPacket>[...selected.packets,...entered]);
        liveSnapshot=networkSnapshot;
        mapId=current.mapId;
        x=networkSnapshot.self?.x??selected.details.x;
        z=networkSnapshot.self?.z??selected.details.z;
        if(networkSnapshot.quests.isNotEmpty)questId=networkSnapshot.quests.first.questId;
        messages.insert(
          0,
          '[ps0032] Mundo real: ${networkSnapshot.npcs.length} NPC · '
          '${networkSnapshot.mobs.length} mobs · ${networkSnapshot.quests.length} quests abiertas.',
        );
      }catch(e){
        messages.insert(0,'[ps0032] Entrada real falló; se conserva fallback SVMAP: '+e.toString());
        networkSnapshot=null;
      }
    }

    // The native fresh-character tutorial is client-visible even before it
    // appears in QUEST_LIST, so retain its canonical id as the empty-list fallback.
    if(questId<=1)questId=faction=='light'?3781:3792;
    final country=faction=='light'?0:1;
    final create=metadata?.createRule(country,classIndex);
    if(mapId==0)mapId=create?.mapId??(faction=='light'?1:2);
    svmap=await _loadSvmap(mapId);
    var world=c.worlds.where((p)=>baseName(p).toLowerCase()==mapId.toString()+'.wld').firstOrNull;
    world??=c.worlds.firstOrNull;

    x??=create?.x;
    z??=create?.z;
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

    // Native map-1 proof faces toward increasing world Z (Dog / Guard route).
    // Three uses local Z = -(worldZ-originZ), so yaw 0 puts the camera behind
    // the avatar while looking toward that same native sector.
    scene.yaw=0;
    scene.pitch=.12;
    scene.distance=5.9;
    scene.targetY=1.18;
    if(scene.character!=null){scene.character!.root.rotation.y=math.pi;}
    scene.updateCamera();

    final meta=metadata;
    final questNpcKeys=meta==null
      ?null
      :meta.npcs.entries.where((e)=>e.value.outQuests.isNotEmpty).map((e)=>e.key).toSet();
    if(networkSnapshot!=null){
      await scene.spawnGameActorsFromNetwork(
        npcs:networkSnapshot.npcs.map((p)=>RuntimeNpcSpawn(
          p.type,p.typeId,p.x,p.y,p.z,p.angle,p.globalId,
        )).toList(),
        mobs:networkSnapshot.mobs.map((p)=>RuntimeMobSpawn(p.mobId,p.x,p.z,p.globalId)).toList(),
        npcModels:meta?.npcModels,
        mobModels:meta?.mobModels,
        questNpcKeys:questNpcKeys,
        locale:uiLocale,
      );
    }else if(map!=null){
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
          ' NPC lógicos · '+map.mobAreas.length.toString()+' áreas de mobs.',
      );
    }else{
      await scene.spawnGameNpcs(count:12);
      messages.insert(0,'[Mapa] Sin SVMAP: población visual de respaldo.');
    }

    stage=GameStage.world;
    questOpen=true;
    _startWorldRealtime();
    if(mounted)setState(()=>loading=false);
    focus.requestFocus();
    await Future<void>.delayed(const Duration(milliseconds:350));
    await _signalQaReady();
  }

  void _startWorldRealtime(){
    movementTimer?.cancel();
    unawaited(livePacketSubscription?.cancel());
    final session=liveWorld;
    if(session==null)return;
    livePacketSubscription=session.packets.listen(
      _handleLivePacket,
      onError:(Object e){
        messages.insert(0,'[ps0032] Stream World: '+e.toString());
        if(mounted)setState((){});
      },
    );
    movementTimer=Timer.periodic(const Duration(milliseconds:200),(_)=>unawaited(_syncMovement()));
  }

  void _stopWorldRealtime(){
    movementTimer?.cancel();movementTimer=null;
    unawaited(livePacketSubscription?.cancel());livePacketSubscription=null;
    lastNetworkX=lastNetworkZ=null;
    lastNetworkMoving=lastNetworkRun=false;
  }

  void _handleLivePacket(PsPacket packet){
    if(stage!=GameStage.world)return;
    if(packet.type==PsPacketType.questStart&&packet.body.length>=6){
      final d=ByteData.sublistView(packet.body);
      final id=d.getInt16(4,Endian.little);
      messages.insert(0,'[Misión] World confirmó QUEST_START '+id.toString()+'.');
    }else if(packet.type==PsPacketType.questUpdateCount&&packet.body.length>=4){
      final d=ByteData.sublistView(packet.body);
      final id=d.getInt16(0,Endian.little),objective=packet.body[2]+1,count=packet.body[3];
      messages.insert(0,'[Misión] '+id.toString()+' · objetivo '+objective.toString()+': '+count.toString());
    }else if(packet.type==PsPacketType.questEnd&&packet.body.length>=7){
      final d=ByteData.sublistView(packet.body);
      final id=d.getInt16(4,Endian.little),ok=packet.body[6]!=0;
      messages.insert(0,'[Misión] '+id.toString()+(ok?' completada.':' aún no puede completarse.'));
    }else if(packet.type==PsPacketType.mobMove&&packet.body.length>=13){
      final d=ByteData.sublistView(packet.body);
      scene.moveNetworkMob(
        d.getUint32(0,Endian.little),d.getFloat32(5,Endian.little),
        d.getFloat32(9,Endian.little),packet.body[4],
      );
    }else if(packet.type==PsPacketType.mapNpcMove&&packet.body.length>=17){
      final d=ByteData.sublistView(packet.body);
      scene.moveNetworkNpc(
        d.getUint32(0,Endian.little),d.getFloat32(5,Endian.little),
        d.getFloat32(9,Endian.little),d.getFloat32(13,Endian.little),packet.body[4],
      );
    }else if(packet.type==PsPacketType.mobLeave&&packet.body.length>=4){
      final d=ByteData.sublistView(packet.body);
      scene.removeNetworkActor(d.getUint32(0,Endian.little),mob:true);
    }else if(packet.type==PsPacketType.mapNpcLeave&&packet.body.length>=4){
      final d=ByteData.sublistView(packet.body);
      scene.removeNetworkActor(d.getUint32(0,Endian.little),mob:false);
    }else if(packet.type==PsPacketType.mobDeath&&packet.body.length>=4){
      final d=ByteData.sublistView(packet.body);
      unawaited(scene.killNetworkMob(d.getUint32(0,Endian.little)));
    }
    if(mounted)setState((){});
  }

  Future<void> _syncMovement() async {
    if(movementSending||stage!=GameStage.world)return;
    final session=liveWorld,a=scene.character;
    if(session==null||a==null)return;
    final moving=scene.walkX!=0||scene.walkZ!=0;
    final x=scene.originX+a.root.position.x;
    final z=scene.originZ-a.root.position.z;
    final y=a.root.position.y;
    final run=scene.running;
    final changed=lastNetworkX==null||
      ((x-lastNetworkX!)*(x-lastNetworkX!)+(z-lastNetworkZ!)*(z-lastNetworkZ!))>.01||
      moving!=lastNetworkMoving||run!=lastNetworkRun;
    if(!changed)return;
    movementSending=true;
    try{
      await session.moveCharacter(x:x,y:y,z:z,yawRadians:-a.root.rotation.y,run:run);
      lastNetworkX=x;lastNetworkZ=z;lastNetworkMoving=moving;lastNetworkRun=run;
    }catch(e){
      messages.insert(0,'[Movimiento] '+e.toString());
      if(mounted)setState((){});
    }finally{movementSending=false;}
  }

  Future<void> _acceptCurrentQuest() async {
    final text=catalog?.questText(uiLocale)?.quest(questId);
    final session=liveWorld;
    final rule=metadata?.quests[questId];
    final snapshot=liveSnapshot;
    if(session==null||rule==null||snapshot==null){
      messages.insert(0,'[Misión] '+(text?.name??'Misión aceptada')+' · modo visual.');
      if(mounted)setState(()=>questOpen=false);
      return;
    }
    final npc=snapshot.npcs.where((n)=>n.type==rule.startNpcType&&n.typeId==rule.startNpcId).firstOrNull;
    if(npc==null){
      messages.insert(0,'[Misión] No está presente el NPC '+rule.startNpcType.toString()+':'+rule.startNpcId.toString()+' requerido por '+questId.toString()+'.');
      if(mounted)setState((){});
      return;
    }
    try{
      await session.startQuest(npc.globalId,questId);
      final current=liveSnapshot!;
      if(!current.quests.any((q)=>q.questId==questId)){
        liveSnapshot=PsWorldSnapshot(
          self:current.self,npcs:current.npcs,mobs:current.mobs,
          quests:[...current.quests,PsQuestProgress(questId,0,0,0,0)],
          finishedQuests:current.finishedQuests,
        );
      }
      messages.insert(0,'[Misión] '+(text?.name??('Misión '+questId.toString()))+' aceptada por World.');
      if(mounted)setState(()=>questOpen=false);
    }catch(e){
      messages.insert(0,'[Misión] QUEST_START '+questId.toString()+': '+e.toString());
      if(mounted)setState((){});
    }
  }
  Future<void> _goFaction() async {
    _stopWorldRealtime();
    scene.clearMovement();
    await scene.setWorld(null);
    if(mounted)setState(()=>stage=GameStage.faction);
  }

  Future<void> _goSelect() async {
    _stopWorldRealtime();
    if(mounted)setState(()=>loading=true);
    await _applyDefaultAppearance();
    await _prepareSelectionWorld(creation:false);
    if(mounted)setState((){stage=GameStage.characterSelect;loading=false;});
  }

  Future<void> _goCreate() async {
    _stopWorldRealtime();
    if(mounted)setState(()=>loading=true);
    await _applyDefaultAppearance();
    await _prepareSelectionWorld(creation:true);
    if(mounted)setState((){stage=GameStage.characterCreate;loading=false;});
  }

  Future<void> _finishCreate() async {
    if(nameController.text.trim().isEmpty)nameController.text='DreynoxLocal';
    if(mounted)setState(()=>loading=true);
    try{
      final session=liveWorld;
      if(session!=null){
        final free=liveCharacters.where((s)=>!s.exists).firstOrNull?.slot??0;
        final slots=await session.createCharacter(
          slot:free,
          race:_protocolRace(),
          mode:_protocolMode(),
          hair:hairIndex,
          face:faceIndex,
          height:2,
          profession:_protocolProfession(classIndex),
          gender:genderIndex,
          name:nameController.text.trim(),
        );
        liveCharacters=slots;
        liveCharacter=slots.where((s)=>s.exists&&s.name==nameController.text.trim()).firstOrNull
          ??slots.where((s)=>s.exists&&!s.isDelete).firstOrNull;
        if(liveCharacter!=null)_syncUiFromLiveCharacter(liveCharacter!);
        messages.insert(0,'[ps0032] Personaje creado y persistido en World.');
      }
      characterCreated=true;
      await _prepareSelectionWorld(creation:false);
      if(mounted)setState(()=>stage=GameStage.characterSelect);
    }catch(e){
      messages.insert(0,'[ps0032] CREATE_CHARACTER: '+e.toString());
    }finally{
      if(mounted)setState(()=>loading=false);
    }
  }

  Future<void> _deleteSelectedCharacter() async {
    if(mounted)setState(()=>loading=true);
    try{
      final current=liveCharacter;
      if(liveWorld!=null&&current!=null){
        await liveWorld!.deleteCharacter(current.id);
        liveCharacters=liveCharacters.where((s)=>s.id!=current.id).toList();
        liveCharacter=liveCharacters.where((s)=>s.exists&&!s.isDelete).firstOrNull;
        characterCreated=liveCharacter!=null;
        if(liveCharacter!=null)_syncUiFromLiveCharacter(liveCharacter!);
        messages.insert(0,'[ps0032] Personaje eliminado en World.');
      }else{
        characterCreated=false;
      }
      if(mounted)setState((){});
    }catch(e){
      messages.insert(0,'[ps0032] DELETE_CHARACTER: '+e.toString());
    }finally{
      if(mounted)setState(()=>loading=false);
    }
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
            onNext:()=>unawaited(_selectFactionAndContinue()),
          ),
          GameStage.characterSelect=>CharacterSelectScreen(
            ui:ui!,
            created:characterCreated,
            name:nameController.text,
            locale:uiLocale,
            onCreate:()=>unawaited(_goCreate()),
            onDelete:()=>unawaited(_deleteSelectedCharacter()),
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
            onAcceptQuest:()=>unawaited(_acceptCurrentQuest()),
            onCancelQuest:()=>setState(()=>questOpen=false),
          ),
        }),
        if(!active||loading)_loadingOverlay(),
      ])),
    );
  }
}
