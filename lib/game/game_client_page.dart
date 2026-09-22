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
  int liveMapId=0;
  SvmapData? liveSvmap;
  bool mapSwitching=false;
  final List<PsPacket> pendingMapActorPackets=<PsPacket>[];
  PsCharacterDetails? liveDetails;
  PsHitpoints? liveHitpoints;
  PsAdditionalStats? liveAdditionalStats;
  Map<int,PsActiveBuff> liveBuffs=<int,PsActiveBuff>{};
  int? targetMobGlobalId,targetMobTypeId,targetMobHp,targetMobMaxHp;
  PsSkillBook? liveSkills;
  PsSkillBar? liveSkillBar;
  List<PsInventoryItem> liveInventory=<PsInventoryItem>[];
  List<PsInventoryItem> liveWarehouse=<PsInventoryItem>[];
  StreamSubscription<PsPacket>? livePacketSubscription;
  Timer? movementTimer;
  bool movementSending=false;
  int? activePortalTrigger;
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
  bool rewardSelection=false;
  int rewardNpcId=0;
  bool inventoryOpen=false;
  bool statusOpen=false;
  bool skillsOpen=false;
  bool questLogOpen=false;
  bool shopOpen=false;
  bool gateOpen=false;
  bool warehouseOpen=false;
  NpcShopRule? activeShop;
  NpcGateRule? activeGate;
  int? activeShopNpcGlobalId;
  int? activeGateNpcGlobalId;
  int? liveGold;
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
        liveDetails=selected.details;
        liveGold=selected.details.gold;
        final hpPacket=selected.packets.where((p)=>p.type==PsPacketType.characterCurrentHitpoints).firstOrNull;
        final statsPacket=selected.packets.where((p)=>p.type==PsPacketType.characterAdditionalStats).firstOrNull;
        final buffsPacket=selected.packets.where((p)=>p.type==PsPacketType.characterActiveBuffs).firstOrNull;
        final skillsPacket=selected.packets.where((p)=>p.type==PsPacketType.characterSkills).firstOrNull;
        final barPacket=selected.packets.where((p)=>p.type==PsPacketType.characterSkillBar).firstOrNull;
        liveInventory=selected.packets
          .where((p)=>p.type==PsPacketType.characterItems)
          .expand(parseInventoryItems)
          .toList()
          ..sort((a,b){final bag=a.bag.compareTo(b.bag);return bag!=0?bag:a.slot.compareTo(b.slot);});
        liveWarehouse=selected.packets
          .where((p)=>p.type==PsPacketType.warehouseItemList)
          .expand(parseWarehouseItems)
          .map((w)=>PsInventoryItem(
            bag:100,slot:w.slot,type:w.type,typeId:w.typeId,quality:w.quality,
            count:w.count,gems:w.gems,craftName:w.craftName,dyed:w.dyed,
          ))
          .toList()
          ..sort((a,b)=>a.slot.compareTo(b.slot));
        if(hpPacket!=null)liveHitpoints=PsHitpoints.parse(hpPacket);
        if(statsPacket!=null)liveAdditionalStats=PsAdditionalStats.parse(statsPacket);
        liveBuffs={
          for(final buff in buffsPacket==null?const <PsActiveBuff>[]:parseActiveBuffs(buffsPacket))
            buff.id:buff,
        };
        if(skillsPacket!=null)liveSkills=PsSkillBook.parse(skillsPacket);
        if(barPacket!=null)liveSkillBar=PsSkillBar.parse(barPacket);
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
    liveMapId=mapId;liveSvmap=svmap;
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

  bool _isMapActorPacket(int type)=>{
    PsPacketType.mobEnter,PsPacketType.mobMove,PsPacketType.mobLeave,
    PsPacketType.mapNpcEnter,PsPacketType.mapNpcMove,PsPacketType.mapNpcLeave,
  }.contains(type);

  Future<void> _applyMapTeleport(PsMapTeleport teleport) async {
    if(liveCharacter!=null&&teleport.characterId!=liveCharacter!.id)return;
    if(mapSwitching)return;
    mapSwitching=true;
    activePortalTrigger=null;
    _closeWorldPanels();
    scene.clearMovement();
    targetMobGlobalId=targetMobTypeId=targetMobHp=targetMobMaxHp=null;
    final previous=liveSnapshot;
    liveMapId=teleport.mapId;
    try{
      final c=catalog!;
      final map=await _loadSvmap(teleport.mapId);
      liveSvmap=map;
      var world=c.worlds.where((p)=>baseName(p).toLowerCase()==teleport.mapId.toString()+'.wld').firstOrNull;
      if(world==null){
        messages.insert(0,'[Mapa] No existe world/${teleport.mapId}.wld en DATA.');
      }else{
        await scene.setWorld(world,x:teleport.x,z:teleport.z);
      }
      await scene.spawnGameActorsFromNetwork(
        npcs:const <RuntimeNpcSpawn>[],mobs:const <RuntimeMobSpawn>[],
        npcModels:metadata?.npcModels,mobModels:metadata?.mobModels,
        questNpcKeys:metadata?.npcs.entries.where((e)=>e.value.outQuests.isNotEmpty).map((e)=>e.key).toSet(),
        locale:uiLocale,
      );
      final oldSelf=previous?.self;
      liveSnapshot=PsWorldSnapshot(
        self:PsEnteredMap(
          teleport.characterId,oldSelf?.isAdmin??0,oldSelf?.angle??0,
          teleport.x,teleport.y,teleport.z,oldSelf?.guildId??0,oldSelf?.vehicleId??0,
        ),
        npcs:const <PsNpcEnter>[],mobs:const <PsMobEnter>[],
        quests:previous?.quests??const <PsQuestProgress>[],
        finishedQuests:previous?.finishedQuests??const <PsFinishedQuest>[],
      );
      scene.yaw=0;scene.pitch=.12;scene.distance=5.9;scene.targetY=1.18;
      if(scene.character!=null)scene.character!.root.rotation.y=math.pi;
      scene.updateCamera();
      messages.insert(0,'[Mapa] Teleport → ${teleport.mapId} · ${teleport.x.toStringAsFixed(1)}, ${teleport.z.toStringAsFixed(1)}.');
    }catch(e){
      messages.insert(0,'[Mapa] Teleport ${teleport.mapId}: '+e.toString());
    }finally{
      mapSwitching=false;
      final queued=List<PsPacket>.from(pendingMapActorPackets);pendingMapActorPackets.clear();
      for(final packet in queued){_handleLivePacket(packet);}
      if(mounted)setState((){});
    }
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

  void _sortInventory(){
    liveInventory.sort((a,b){
      final bag=a.bag.compareTo(b.bag);
      return bag!=0?bag:a.slot.compareTo(b.slot);
    });
  }

  void _upsertInventoryItem(PsInventoryItem item){
    final target=item.bag==100?liveWarehouse:liveInventory;
    target.removeWhere((x)=>x.bag==item.bag&&x.slot==item.slot);
    if(item.type!=0&&item.typeId!=0&&item.count>0)target.add(item);
    if(item.bag==100){
      liveWarehouse.sort((a,b)=>a.slot.compareTo(b.slot));
    }else{
      _sortInventory();
    }
  }


  void _removeInventory(PsInventoryRemoval removed){
    final index=liveInventory.indexWhere((x)=>x.bag==removed.bag&&x.slot==removed.slot);
    if(index<0)return;
    if(removed.fullRemove||removed.count<=0){
      liveInventory.removeAt(index);
      return;
    }
    final old=liveInventory[index];
    liveInventory[index]=PsInventoryItem(
      bag:old.bag,slot:old.slot,
      type:removed.type==0?old.type:removed.type,
      typeId:removed.typeId==0?old.typeId:removed.typeId,
      quality:old.quality,count:removed.count,
      gems:old.gems,craftName:old.craftName,dyed:old.dyed,
    );
  }

  void _snapshotAddNpc(PsNpcEnter npc){
    final s=liveSnapshot;if(s==null)return;
    liveSnapshot=PsWorldSnapshot(
      self:s.self,
      npcs:[...s.npcs.where((x)=>x.globalId!=npc.globalId),npc],
      mobs:s.mobs,quests:s.quests,finishedQuests:s.finishedQuests,
    );
  }

  void _snapshotAddMob(PsMobEnter mob){
    final s=liveSnapshot;if(s==null)return;
    liveSnapshot=PsWorldSnapshot(
      self:s.self,npcs:s.npcs,
      mobs:[...s.mobs.where((x)=>x.globalId!=mob.globalId),mob],
      quests:s.quests,finishedQuests:s.finishedQuests,
    );
  }

  void _snapshotRemoveActor(int globalId,{required bool mob}){
    final s=liveSnapshot;if(s==null)return;
    liveSnapshot=PsWorldSnapshot(
      self:s.self,
      npcs:mob?s.npcs:s.npcs.where((x)=>x.globalId!=globalId).toList(),
      mobs:mob?s.mobs.where((x)=>x.globalId!=globalId).toList():s.mobs,
      quests:s.quests,finishedQuests:s.finishedQuests,
    );
  }
  void _handleLivePacket(PsPacket packet){
    if(stage!=GameStage.world)return;
    if(mapSwitching&&_isMapActorPacket(packet.type)){pendingMapActorPackets.add(packet);return;}
    if(packet.type==PsPacketType.characterMapTeleport&&packet.body.length>=18){
      try{unawaited(_applyMapTeleport(PsMapTeleport.parse(packet)));}
      catch(e){messages.insert(0,'[Mapa] CHARACTER_MAP_TELEPORT: '+e.toString());}
      return;
    }
    if([
      PsPacketType.chatNormal,PsPacketType.chatWhisper,PsPacketType.chatWorld,
      PsPacketType.chatGuild,PsPacketType.chatParty,PsPacketType.chatMap,
    ].contains(packet.type)){
      try{
        final chat=PsChatMessage.parse(packet);
        final sender=chat.senderName??(chat.senderId==liveCharacter?.id?nameController.text:'#'+(chat.senderId?.toString()??'?'));
        final channel=packet.type==PsPacketType.chatWhisper?'Whisper':
          packet.type==PsPacketType.chatWorld?'World':
          packet.type==PsPacketType.chatGuild?'Guild':
          packet.type==PsPacketType.chatParty?'Party':
          packet.type==PsPacketType.chatMap?'Map':'Normal';
        messages.insert(0,'['+channel+'] '+sender+': '+chat.message);
      }catch(e){messages.insert(0,'[Chat] '+e.toString());}
    }else if(packet.type==PsPacketType.targetMobHpUpdate&&packet.body.length>=10){
      final hp=PsTargetMobHp.parse(packet);
      targetMobGlobalId=hp.targetId;targetMobHp=hp.currentHp;
      final logical=liveSnapshot?.mobs.where((m)=>m.globalId==hp.targetId).firstOrNull;
      if(logical!=null){
        targetMobTypeId=logical.mobId;
        targetMobMaxHp=metadata?.mobs[logical.mobId]?.hp??targetMobMaxHp;
      }
    }else if(packet.type==PsPacketType.characterMobAutoAttack&&packet.body.length>=15){
      final hit=PsUsualHit.parse(packet);
      if(hit.targetId!=0){
        targetMobGlobalId=hit.targetId;
        final logical=liveSnapshot?.mobs.where((m)=>m.globalId==hit.targetId).firstOrNull;
        if(logical!=null){
          targetMobTypeId=logical.mobId;
          targetMobMaxHp=metadata?.mobs[logical.mobId]?.hp??targetMobMaxHp;
        }
      }
      if(hit.success&&hit.targetId!=0){
        if(targetMobHp!=null)targetMobHp=math.max(0,targetMobHp!-hit.hpDamage);
        unawaited(scene.networkPlayerAttack(hit.targetId));
        if(hit.hpDamage>0)unawaited(scene.networkMobHit(hit.targetId,hit.hpDamage));
        messages.insert(0,'[Combate] Ataque normal · daño '+hit.hpDamage.toString()+'.');
      }else if(hit.result!=12){
        messages.insert(0,'[Combate] Ataque normal rechazado ('+hit.result.toString()+').');
      }
    }else if(packet.type==PsPacketType.useMobTargetSkill&&packet.body.length>=19){
      final hit=PsSkillHit.parse(packet);
      targetMobGlobalId=hit.targetId;
      final logical=liveSnapshot?.mobs.where((m)=>m.globalId==hit.targetId).firstOrNull;
      if(logical!=null){
        targetMobTypeId=logical.mobId;
        targetMobMaxHp=metadata?.mobs[logical.mobId]?.hp??targetMobMaxHp;
      }
      if(hit.success&&targetMobHp!=null)targetMobHp=math.max(0,targetMobHp!-hit.hpDamage);
      if(hit.success&&hit.hpDamage>0)unawaited(scene.networkMobHit(hit.targetId,hit.hpDamage));
      messages.insert(0,'[Combate] Skill '+hit.skillId.toString()+' Lv.'+hit.skillLevel.toString()+' · daño '+hit.hpDamage.toString()+'.');
    }else if(packet.type==PsPacketType.mobAttack&&packet.body.length>=15){
      final hit=PsMobAttack.parse(packet);
      if(hit.success){unawaited(scene.networkPlayerHit(hit.hpDamage));messages.insert(0,'[Combate] Mob '+hit.mobId.toString()+' te golpea por '+hit.hpDamage.toString()+'.');}
    }else if(packet.type==PsPacketType.mobSkillUse&&packet.body.length>=19){
      final hit=PsMobSkillHit.parse(packet);
      if(hit.success){unawaited(scene.networkPlayerHit(hit.hpDamage));messages.insert(0,'[Combate] Mob '+hit.mobId.toString()+' usa skill '+hit.skillId.toString()+' · daño '+hit.hpDamage.toString()+'.');}
    }else if(packet.type==PsPacketType.buffAdd&&packet.body.length>=11){
      try{
        final buff=parseBuffAdd(packet);liveBuffs[buff.id]=buff;
        final name=catalog?.skillName(buff.skillId,buff.skillLevel,uiLocale)??('Buff '+buff.skillId.toString());
        messages.insert(0,'[Buff] '+name+' activado.');
      }catch(e){messages.insert(0,'[Buff] '+e.toString());}
    }else if(packet.type==PsPacketType.buffRemove&&packet.body.length>=4){
      try{
        final id=parseBuffRemove(packet),old=liveBuffs.remove(id);
        if(old!=null){
          final name=catalog?.skillName(old.skillId,old.skillLevel,uiLocale)??('Buff '+old.skillId.toString());
          messages.insert(0,'[Buff] '+name+' finalizado.');
        }
      }catch(e){messages.insert(0,'[Buff] '+e.toString());}
    }else if(packet.type==PsPacketType.usedSpMp&&packet.body.length>=8){
      try{
        final used=PsUsedSpMp.parse(packet),hp=liveHitpoints;
        if(hp!=null){
          liveHitpoints=PsHitpoints(
            hp.hp,math.max(0,hp.mp-used.mp),math.max(0,hp.sp-used.sp),
          );
        }
      }catch(e){messages.insert(0,'[Recurso] '+e.toString());}
    }else if(packet.type==PsPacketType.characterCurrentHitpoints&&packet.body.length>=12){
      liveHitpoints=PsHitpoints.parse(packet);
    }else if(packet.type==PsPacketType.characterAdditionalStats&&packet.body.length>=48){
      liveAdditionalStats=PsAdditionalStats.parse(packet);
    }else if(packet.type==PsPacketType.addItem&&packet.body.length>=106){
      try{
        _upsertInventoryItem(parseAddedInventoryItem(packet));
        messages.insert(0,'[Inventario] Objeto añadido/actualizado.');
      }catch(e){messages.insert(0,'[Inventario] ADD_ITEM: '+e.toString());}
    }else if(packet.type==PsPacketType.removeItem&&packet.body.length>=5){
      try{
        _removeInventory(PsInventoryRemoval.parse(packet));
        messages.insert(0,'[Inventario] Objeto retirado/actualizado.');
      }catch(e){messages.insert(0,'[Inventario] REMOVE_ITEM: '+e.toString());}
    }else if(packet.type==PsPacketType.inventoryMoveItem&&packet.body.length>=208){
      try{
        final move=PsInventoryMove.parse(packet);
        _upsertInventoryItem(move.source);
        _upsertInventoryItem(move.destination);
        liveGold=move.gold;
        messages.insert(0,'[Inventario/Almacén] Movimiento confirmado por World.');
      }catch(e){messages.insert(0,'[Inventario] MOVE_ITEM: '+e.toString());}
    }else if(packet.type==PsPacketType.questStart&&packet.body.length>=6){
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
    }else if(packet.type==PsPacketType.mobEnter&&packet.body.length>=15){
      try{
        final mob=PsMobEnter.parse(packet);_snapshotAddMob(mob);
        unawaited(scene.addNetworkMob(
          RuntimeMobSpawn(mob.mobId,mob.x,mob.z,mob.globalId),
          mobModels:metadata?.mobModels,locale:uiLocale,
        ));
      }catch(e){messages.insert(0,'[Mundo] MOB_ENTER: '+e.toString());}
    }else if(packet.type==PsPacketType.mapNpcEnter&&packet.body.length>=21){
      try{
        final npc=PsNpcEnter.parse(packet);_snapshotAddNpc(npc);
        final keys=metadata?.npcs.entries.where((e)=>e.value.outQuests.isNotEmpty).map((e)=>e.key).toSet();
        unawaited(scene.addNetworkNpc(
          RuntimeNpcSpawn(npc.type,npc.typeId,npc.x,npc.y,npc.z,npc.angle,npc.globalId),
          npcModels:metadata?.npcModels,questNpcKeys:keys,locale:uiLocale,
        ));
      }catch(e){messages.insert(0,'[Mundo] MAP_NPC_ENTER: '+e.toString());}
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
      final d=ByteData.sublistView(packet.body),id=d.getUint32(0,Endian.little);
      _snapshotRemoveActor(id,mob:true);scene.removeNetworkActor(id,mob:true);
    }else if(packet.type==PsPacketType.mapNpcLeave&&packet.body.length>=4){
      final d=ByteData.sublistView(packet.body),id=d.getUint32(0,Endian.little);
      _snapshotRemoveActor(id,mob:false);scene.removeNetworkActor(id,mob:false);
    }else if(packet.type==PsPacketType.mobDeath&&packet.body.length>=4){
      final d=ByteData.sublistView(packet.body),id=d.getUint32(0,Endian.little);
      if(targetMobGlobalId==id)targetMobHp=0;
      unawaited(scene.killNetworkMob(id));
    }
    if(mounted)setState((){});
  }

  Future<void> _checkPhysicalPortal(double x,double y,double z) async {
    final map=liveSvmap,session=liveWorld;
    if(map==null||session==null||map.portals.isEmpty){activePortalTrigger=null;return;}
    int? inside;
    for(var i=0;i<map.portals.length;i++){
      final p=map.portals[i];
      if((x-p.position.x).abs()>5||(y-p.position.y).abs()>5||(z-p.position.z).abs()>5)continue;
      final level=liveCharacter?.level??1;
      if(level<p.minLevel||level>p.maxLevel)continue;
      final factionOk=p.factionOrId==0||p.factionOrId>2||
        (faction=='light'&&p.factionOrId==1)||(faction=='dark'&&p.factionOrId==2);
      if(!factionOk)continue;
      inside=i;break;
    }
    if(inside==null){activePortalTrigger=null;return;}
    if(activePortalTrigger==inside)return;
    activePortalTrigger=inside;
    try{
      await session.enterPortal(inside);
      final p=map.portals[inside];
      messages.insert(0,'[Portal] ${liveMapId} → ${p.targetMap} solicitado a World.');
      if(mounted)setState((){});
    }catch(e){messages.insert(0,'[Portal] '+e.toString());if(mounted)setState((){});}
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
    unawaited(_checkPhysicalPortal(x,y,z));
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

  List<PsQuickSlot> get _primaryQuickSlots{
    final all=liveSkillBar?.slots??const <PsQuickSlot>[];
    if(all.isEmpty)return const [];
    var bar=all.first.bar;
    for(final s in all){if(s.bar<bar)bar=s.bar;}
    final selected=all.where((s)=>s.bar==bar).toList()..sort((a,b)=>a.slot.compareTo(b.slot));
    return selected;
  }

  Future<void> _sendChat(String value) async {
    final session=liveWorld;if(session==null||stage!=GameStage.world)return;
    try{await session.sendNormalChat(value);}
    catch(e){messages.insert(0,'[Chat] '+e.toString());if(mounted)setState((){});}
  }
  Future<void> _selectMobAt(Offset position) async {
    if(stage!=GameStage.world)return;
    focus.requestFocus();
    final id=scene.pickNetworkMob(position.dx,position.dy,1024,742);
    if(id==null)return;
    final logical=liveSnapshot?.mobs.where((m)=>m.globalId==id).firstOrNull;
    targetMobGlobalId=id;
    if(logical!=null){
      targetMobTypeId=logical.mobId;
      targetMobMaxHp=metadata?.mobs[logical.mobId]?.hp??targetMobMaxHp;
    }
    try{
      final hp=await liveWorld?.selectMobTarget(id);
      if(hp!=null){targetMobHp=hp.currentHp;targetMobGlobalId=hp.targetId;}
      messages.insert(0,'[Target] '+(logical==null?'Mob '+id.toString():catalog!.monsterName(logical.mobId,uiLocale)));
    }catch(e){messages.insert(0,'[Target] '+e.toString());}
    if(mounted)setState((){});
  }
  Future<void> _addStat(int index) async {
    final d=liveDetails,session=liveWorld;
    if(d==null||session==null||stage!=GameStage.world)return;
    if(d.statPoint<=0){messages.insert(0,'[Estado] No hay puntos de atributo disponibles.');if(mounted)setState((){});return;}
    try{
      final result=await session.updateStats(
        str:index==0?1:0,dex:index==1?1:0,rec:index==2?1:0,
        intl:index==3?1:0,wis:index==4?1:0,luc:index==5?1:0,
      );
      final spent=result.fold<int>(0,(sum,v)=>sum+v);
      if(spent<=0){messages.insert(0,'[Estado] World no aplicó el punto.');if(mounted)setState((){});return;}
      liveDetails=PsCharacterDetails(
        strength:d.strength+result[0],dexterity:d.dexterity+result[1],reaction:d.reaction+result[2],
        intelligence:d.intelligence+result[3],wisdom:d.wisdom+result[4],luck:d.luck+result[5],
        statPoint:math.max(0,d.statPoint-spent),skillPoint:d.skillPoint,
        maxHp:d.maxHp,maxMp:d.maxMp,maxSp:d.maxSp,angle:d.angle,
        startExp:d.startExp,endExp:d.endExp,currentExp:d.currentExp,gold:d.gold,
        x:d.x,y:d.y,z:d.z,kills:d.kills,deaths:d.deaths,victories:d.victories,defeats:d.defeats,
        guildName:d.guildName,
      );
      messages.insert(0,'[Estado] Atributo actualizado por World.');
      if(mounted)setState((){});
    }catch(e){messages.insert(0,'[Estado] '+e.toString());if(mounted)setState((){});}
  }
  Future<void> _assignSkillToHotbar(PsLearnedSkill skill) async {
    final session=liveWorld;
    if(session==null||stage!=GameStage.world)return;
    final all=[...(liveSkillBar?.slots??const <PsQuickSlot>[])];
    final bar=all.isEmpty?0:all.map((s)=>s.bar).reduce(math.min);
    final occupied={for(final s in all.where((s)=>s.bar==bar))s.slot};
    int? slot;
    for(var i=0;i<10;i++){if(!occupied.contains(i)){slot=i;break;}}
    if(slot==null){
      messages.insert(0,'[Skillbar] No hay slots libres en la barra principal.');
      if(mounted)setState((){});
      return;
    }
    final next=PsQuickSlot(bar,slot,100,skill.skillId,skill.cooldownSeconds);
    all.add(next);
    all.sort((a,b){final byBar=a.bar.compareTo(b.bar);return byBar!=0?byBar:a.slot.compareTo(b.slot);});
    try{
      await session.saveSkillBar(all);
      liveSkillBar=PsSkillBar(List.unmodifiable(all));
      final name=catalog?.skillName(skill.skillId,skill.level,uiLocale)??('Skill '+skill.skillId.toString());
      messages.insert(0,'[Skillbar] '+name+' → slot '+(slot+1).toString()+'.');
      if(mounted)setState((){});
    }catch(e){messages.insert(0,'[Skillbar] '+e.toString());if(mounted)setState((){});}
  }
  Future<void> _autoAttackAt(Offset position) async {
    if(stage!=GameStage.world)return;
    final id=scene.pickNetworkMob(position.dx,position.dy,1024,742);
    if(id==null)return;
    await _selectMobAt(position);
    final target=targetMobGlobalId;
    if(target==null)return;
    try{
      unawaited(scene.networkPlayerAttack(target));
      await liveWorld?.startMobAutoAttack(target);
      messages.insert(0,'[Combate] Autoataque iniciado → '+target.toString()+'.');
      if(mounted)setState((){});
    }catch(e){messages.insert(0,'[Combate] '+e.toString());if(mounted)setState((){});}
  }
  Future<void> _useHotbarSlot(int index) async {
    if(stage!=GameStage.world)return;
    final slots=_primaryQuickSlots;
    final slot=slots.where((s)=>s.slot==index).firstOrNull??(index<slots.length?slots[index]:null);
    if(slot==null){messages.insert(0,'[Skillbar] Slot ${index+1} vacío.');if(mounted)setState((){});return;}
    if(!slot.isSkill){messages.insert(0,'[Skillbar] Slot ${index+1} contiene bag ${slot.bag}, item ${slot.number}.');if(mounted)setState((){});return;}
    final learned=liveSkills?.bySkillId(slot.number);
    if(learned==null){messages.insert(0,'[Skillbar] SkillId ${slot.number} no está aprendida.');if(mounted)setState((){});return;}
    final selected=targetMobGlobalId;
    final target=selected!=null&&scene.networkMobActors.containsKey(selected)?selected:scene.nearestNetworkMobId(maxDistance:18);
    if(target==null){messages.insert(0,'[Combate] No hay criatura viva seleccionada/cercana.');if(mounted)setState((){});return;}
    final logical=liveSnapshot?.mobs.where((m)=>m.globalId==target).firstOrNull;
    targetMobGlobalId=target;
    if(logical!=null){
      targetMobTypeId=logical.mobId;
      targetMobMaxHp=metadata?.mobs[logical.mobId]?.hp??targetMobMaxHp;
      targetMobHp??=targetMobMaxHp;
    }
    try{
      unawaited(scene.networkPlayerAttack(target));
      await liveWorld?.useMobSkill(learned.number,target);
      messages.insert(0,'[Combate] Skill ${learned.skillId} Lv.${learned.level} → mob $target.');
      if(mounted)setState((){});
    }catch(e){messages.insert(0,'[Combate] '+e.toString());if(mounted)setState((){});}
  }
  void _closeWorldPanels(){
    inventoryOpen=false;
    statusOpen=false;
    skillsOpen=false;
    questLogOpen=false;
    shopOpen=false;
    gateOpen=false;
    warehouseOpen=false;
    activeShop=null;
    activeGate=null;
    activeShopNpcGlobalId=null;
    activeGateNpcGlobalId=null;
  }

  void _toggleWorldPanel(String panel){
    final open=panel=='status'?statusOpen:panel=='skills'?skillsOpen:panel=='quests'?questLogOpen:inventoryOpen;
    _closeWorldPanels();
    questOpen=false;
    if(!open){
      if(panel=='status')statusOpen=true;
      else if(panel=='skills')skillsOpen=true;
      else if(panel=='quests')questLogOpen=true;
      else inventoryOpen=true;
    }
    if(mounted)setState((){});
  }

  void _openQuestFromLog(int id){
    _closeWorldPanels();
    questId=id;
    rewardSelection=false;
    rewardNpcId=0;
    questOpen=true;
    if(mounted)setState((){});
  }

  Future<void> _interactNearestNpc() async {
    if(stage!=GameStage.world)return;
    final globalId=scene.nearestNetworkNpcId();
    if(globalId==null){
      messages.insert(0,uiLocale=='spn'?'[NPC] No hay ningún NPC suficientemente cerca.':'[NPC] No NPC is close enough.');
      if(mounted)setState((){});
      return;
    }
    final snapshot=liveSnapshot;
    final logical=snapshot?.npcs.where((n)=>n.globalId==globalId).firstOrNull;
    if(logical==null){
      messages.insert(0,'[NPC] Actor '+globalId.toString()+' sin metadata lógica.');
      if(mounted)setState((){});
      return;
    }
    final key=logical.type.toString()+':'+logical.typeId.toString();
    final rule=metadata?.npcs[key];
    final localized=catalog?.questText(uiLocale)?.npc(logical.type,logical.typeId);
    final npcName=(localized?.name.trim().isNotEmpty??false)?localized!.name.trim():'NPC '+key;
    final openIds={for(final q in snapshot?.quests??const <PsQuestProgress>[])q.questId};
    final finishedIds={for(final q in snapshot?.finishedQuests??const <PsFinishedQuest>[])q.questId};
    int? selectedQuest;

    if(rule!=null){
      for(final id in rule.inQuests){
        if(openIds.contains(id)){selectedQuest=id;break;}
      }
      if(selectedQuest==null){
        final level=liveCharacter?.level??1;
        for(final id in rule.outQuests){
          if(openIds.contains(id)||finishedIds.contains(id))continue;
          final q=metadata?.quests[id];
          if(q!=null&&q.minLevel>0&&level<q.minLevel)continue;
          if(q!=null&&q.maxLevel>0&&level>q.maxLevel)continue;
          selectedQuest=id;break;
        }
      }
    }

    if(selectedQuest!=null){
      _closeWorldPanels();
      questId=selectedQuest;
      rewardSelection=false;rewardNpcId=0;
      questOpen=true;
      messages.insert(0,'[NPC] '+npcName+' · misión '+selectedQuest.toString()+'.');
    }else{
      final shop=metadata?.shop(logical.type,logical.typeId);
      final gate=metadata?.gatekeeper(logical.type,logical.typeId);
      if(shop!=null&&shop.products.isNotEmpty){
        _closeWorldPanels();activeShop=shop;activeShopNpcGlobalId=globalId;shopOpen=true;
        messages.insert(0,'[Tienda] '+npcName+' · '+shop.products.length.toString()+' productos.');
      }else if(gate!=null&&gate.targets.any((g)=>g.mapId>0)){
        _closeWorldPanels();activeGate=gate;activeGateNpcGlobalId=globalId;gateOpen=true;
        messages.insert(0,'[Gatekeeper] '+npcName+' · '+gate.targets.where((g)=>g.mapId>0).length.toString()+' destinos.');
      }else if(logical.type==6){
        _closeWorldPanels();warehouseOpen=true;
        messages.insert(0,'[Almacén] '+npcName+' · '+liveWarehouse.length.toString()+' objetos.');
      }else{
        final welcome=localized?.welcome.trim()??'';
        messages.insert(0,'['+npcName+'] '+(welcome.isEmpty?(uiLocale=='spn'?'No tiene nada que decir ahora.':'Nothing to say right now.'):welcome));
      }
    }
    if(mounted)setState((){});
  }
  void _markQuestFinished(int id){
    final current=liveSnapshot;
    if(current==null)return;
    liveSnapshot=PsWorldSnapshot(
      self:current.self,npcs:current.npcs,mobs:current.mobs,
      quests:current.quests.where((q)=>q.questId!=id).toList(),
      finishedQuests:[
        ...current.finishedQuests.where((q)=>q.questId!=id),
        PsFinishedQuest(id,true),
      ],
    );
  }

  Future<void> _chooseQuestReward(int index) async {
    final session=liveWorld;
    if(session==null||!rewardSelection)return;
    try{
      await session.chooseQuestReward(rewardNpcId,questId,index);
      _markQuestFinished(questId);
      final rule=metadata?.quests[questId];
      final reward=index>=0&&rule!=null&&index<rule.rewards.length?rule.rewards[index]:null;
      final name=reward==null?null:catalog?.itemName(reward.type,reward.id,uiLocale);
      messages.insert(0,'[Misión] Recompensa elegida'+(name==null?'':': '+name)+'.');
      rewardSelection=false;rewardNpcId=0;questOpen=false;
      if(mounted)setState((){});
    }catch(e){messages.insert(0,'[Misión] QUEST_END_SELECT: '+e.toString());if(mounted)setState((){});}
  }

  ({int bag,int slot})? _firstFreeInventorySlot(){
    final occupied=<int>{for(final i in liveInventory.where((i)=>i.bag>=1&&i.bag<=5))i.bag*100+i.slot};
    for(var bag=1;bag<=5;bag++){for(var slot=0;slot<24;slot++){if(!occupied.contains(bag*100+slot))return (bag:bag,slot:slot);}}
    return null;
  }

  int? _firstFreeWarehouseSlot(){
    final occupied={for(final i in liveWarehouse)i.slot};
    for(var slot=0;slot<120;slot++){if(!occupied.contains(slot))return slot;}
    return null;
  }

  Future<void> _storeInWarehouse(PsInventoryItem item) async {
    final session=liveWorld,slot=_firstFreeWarehouseSlot();
    if(session==null||!warehouseOpen)return;
    if(item.bag==0){messages.insert(0,'[Almacén] Debes desequipar el objeto primero.');if(mounted)setState((){});return;}
    if(slot==null){messages.insert(0,'[Almacén] No hay slots libres.');if(mounted)setState((){});return;}
    try{
      final move=await session.moveItem(item.bag,item.slot,100,slot);
      _upsertInventoryItem(move.source);_upsertInventoryItem(move.destination);liveGold=move.gold;
      messages.insert(0,'[Almacén] Objeto guardado en slot '+slot.toString()+'.');
      if(mounted)setState((){});
    }catch(e){messages.insert(0,'[Almacén] '+e.toString());if(mounted)setState((){});}
  }

  Future<void> _withdrawWarehouse(PsInventoryItem item) async {
    final session=liveWorld,dest=_firstFreeInventorySlot();
    if(session==null||!warehouseOpen)return;
    if(dest==null){messages.insert(0,'[Almacén] Inventario lleno.');if(mounted)setState((){});return;}
    try{
      final move=await session.moveItem(100,item.slot,dest.bag,dest.slot);
      _upsertInventoryItem(move.source);_upsertInventoryItem(move.destination);liveGold=move.gold;
      messages.insert(0,'[Almacén] Objeto retirado a bag '+dest.bag.toString()+', slot '+dest.slot.toString()+'.');
      if(mounted)setState((){});
    }catch(e){messages.insert(0,'[Almacén] '+e.toString());if(mounted)setState((){});}
  }
  Future<void> _useGatekeeperTarget(int index) async {
    final gate=activeGate,npc=activeGateNpcGlobalId,session=liveWorld;
    if(gate==null||npc==null||session==null)return;
    final target=gate.targets.where((g)=>g.index==index).firstOrNull;
    if(target==null)return;
    try{
      final result=await session.teleportViaNpc(npc,index);
      liveGold=result.gold;
      if(result.success){
        messages.insert(0,'[Gatekeeper] Destino mapa '+target.mapId.toString()+' autorizado.');
        gateOpen=false;
      }else{
        messages.insert(0,'[Gatekeeper] Teleport rechazado ('+result.reason.toString()+').');
      }
      if(mounted)setState((){});
    }catch(e){
      messages.insert(0,'[Gatekeeper] '+e.toString());
      if(mounted)setState((){});
    }
  }

  Future<void> _buyShopProduct(int index,{int count=1}) async {
    final shop=activeShop,npc=activeShopNpcGlobalId,session=liveWorld;
    if(shop==null||npc==null||session==null)return;
    final product=shop.products.where((p)=>p.index==index).firstOrNull;
    if(product==null)return;
    try{
      final result=await session.buyNpcItem(npc,index,count);
      liveGold=result.gold;
      final name=catalog?.itemName(product.type,product.id,uiLocale)??('${product.type}:${product.id}');
      if(result.success){
        messages.insert(0,'[Tienda] Comprado '+name+' x'+count.toString()+'.');
      }else{
        messages.insert(0,'[Tienda] Compra rechazada ('+result.result.toString()+') · '+name+'.');
      }
      if(mounted)setState((){});
    }catch(e){messages.insert(0,'[Tienda] '+e.toString());if(mounted)setState((){});}
  }

  Future<void> _sellInventoryItem(PsInventoryItem item,{int count=1}) async {
    final session=liveWorld;
    if(session==null||!shopOpen)return;
    if(item.bag==0){messages.insert(0,'[Tienda] Debes desequipar el objeto antes de venderlo.');if(mounted)setState((){});return;}
    final qty=count.clamp(1,item.count).toInt();
    try{
      final result=await session.sellNpcItem(item.bag,item.slot,qty);
      liveGold=result.gold;
      final name=catalog?.itemName(item.type,item.typeId,uiLocale)??item.key;
      if(result.success){
        _removeInventory(PsInventoryRemoval(result.bag,result.slot,result.type,result.typeId,result.count));
        messages.insert(0,'[Tienda] Vendido '+name+' x'+qty.toString()+'.');
      }else{
        messages.insert(0,'[Tienda] Venta rechazada · '+name+'.');
      }
      if(mounted)setState((){});
    }catch(e){messages.insert(0,'[Tienda] '+e.toString());if(mounted)setState((){});}
  }
  Future<void> _acceptCurrentQuest() async {
    final text=catalog?.questText(uiLocale)?.quest(questId);
    final session=liveWorld;
    final rule=metadata?.quests[questId];
    final snapshot=liveSnapshot;
    if(session==null||rule==null||snapshot==null){
      messages.insert(0,'[Misión] '+(text?.name??'Misión')+' · modo visual.');
      if(mounted)setState(()=>questOpen=false);
      return;
    }

    final active=snapshot.quests.any((q)=>q.questId==questId);
    if(active){
      var npcId=0;
      if(rule.endNpcType>0&&rule.endNpcId>0){
        final nearestId=scene.nearestNetworkNpcId();
        final nearest=nearestId==null?null:snapshot.npcs.where((n)=>n.globalId==nearestId).firstOrNull;
        if(nearest==null||nearest.type!=rule.endNpcType||nearest.typeId!=rule.endNpcId){
          messages.insert(0,'[Misión] Debes hablar con el NPC '+rule.endNpcType.toString()+':'+rule.endNpcId.toString()+' para entregar '+questId.toString()+'.');
          if(mounted)setState((){});
          return;
        }
        npcId=nearest.globalId;
      }
      try{
        final result=await session.finishQuest(npcId,questId);
        if(result.requiresChoice){
          rewardSelection=true;rewardNpcId=npcId;questOpen=true;
          messages.insert(0,'[Misión] Elige una recompensa para '+(text?.name??questId.toString())+'.');
        }else if(result.success){
          _markQuestFinished(questId);
          rewardSelection=false;rewardNpcId=0;questOpen=false;
          messages.insert(0,'[Misión] '+(text?.name??('Misión '+questId.toString()))+' completada · XP '+result.xp.toString()+' · oro '+result.gold.toString()+'.');
        }else{
          messages.insert(0,'[Misión] Aún no se cumplen los requisitos de '+(text?.name??questId.toString())+'.');
        }
        if(mounted)setState((){});
      }catch(e){messages.insert(0,'[Misión] QUEST_END '+questId.toString()+': '+e.toString());if(mounted)setState((){});}
      return;
    }

    final npc=rule.startNpcType==0||rule.startNpcId==0
      ?null
      :snapshot.npcs.where((n)=>n.type==rule.startNpcType&&n.typeId==rule.startNpcId).firstOrNull;
    if(rule.startNpcType>0&&rule.startNpcId>0&&npc==null){
      messages.insert(0,'[Misión] No está presente el NPC '+rule.startNpcType.toString()+':'+rule.startNpcId.toString()+' requerido por '+questId.toString()+'.');
      if(mounted)setState((){});
      return;
    }
    try{
      await session.startQuest(npc?.globalId??0,questId);
      final current=liveSnapshot!;
      if(!current.quests.any((q)=>q.questId==questId)){
        liveSnapshot=PsWorldSnapshot(
          self:current.self,npcs:current.npcs,mobs:current.mobs,
          quests:[...current.quests,PsQuestProgress(questId,0,0,0,0)],
          finishedQuests:current.finishedQuests,
        );
      }
      rewardSelection=false;rewardNpcId=0;
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
      if(stage!=GameStage.world)return;
      if(key==LogicalKeyboardKey.keyR){scene.resetCombat();return;}
      if(key==LogicalKeyboardKey.keyE){unawaited(_interactNearestNpc());return;}
      final keys=<LogicalKeyboardKey>[
        LogicalKeyboardKey.digit1,LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit3,LogicalKeyboardKey.digit4,
      ];
      final index=keys.indexOf(key);
      if(index>=0)unawaited(_useHotbarSlot(index));
    },
    child:Listener(
      onPointerSignal:(e){
        if(e is PointerScrollEvent&&stage!=GameStage.faction){
          scene.zoom(e.scrollDelta.dy>0?1.08:1/1.08);
        }
      },
      child:GestureDetector(
        behavior:HitTestBehavior.opaque,
        onTapDown:(d){if(stage==GameStage.world)unawaited(_selectMobAt(d.localPosition));else focus.requestFocus();},
        onDoubleTapDown:(d){if(stage==GameStage.world)unawaited(_autoAttackAt(d.localPosition));},
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
            metadata:metadata,
            characterName:nameController.text,
            level:liveCharacter?.level??1,
            details:liveDetails,
            additionalStats:liveAdditionalStats,
            hitpoints:liveHitpoints,
            buffs:liveBuffs.values.toList(),
            targetMobGlobalId:targetMobGlobalId,
            targetMobId:targetMobTypeId,
            targetHp:targetMobHp,
            targetMaxHp:targetMobMaxHp,
            skillBook:liveSkills,
            skillBar:liveSkillBar,
            inventory:liveInventory,
            warehouse:liveWarehouse,
            inventoryOpen:inventoryOpen,
            statusOpen:statusOpen,
            skillsOpen:skillsOpen,
            questLogOpen:questLogOpen,
            warehouseOpen:warehouseOpen,
            openQuests:liveSnapshot?.quests??const <PsQuestProgress>[],
            finishedQuests:liveSnapshot?.finishedQuests??const <PsFinishedQuest>[],
            gold:liveGold??liveDetails?.gold??0,
            shop:activeShop,
            gate:activeGate,
            shopOpen:shopOpen,
            gateOpen:gateOpen,
            onCloseShop:()=>setState(()=>shopOpen=false),
            onCloseGate:()=>setState(()=>gateOpen=false),
            onCloseWarehouse:()=>setState(()=>warehouseOpen=false),
            onBuyShopProduct:(index)=>unawaited(_buyShopProduct(index)),
            onUseGate:(index)=>unawaited(_useGatekeeperTarget(index)),
            onSellInventory:(item)=>unawaited(_sellInventoryItem(item)),
            onStoreWarehouse:(item)=>unawaited(_storeInWarehouse(item)),
            onWithdrawWarehouse:(item)=>unawaited(_withdrawWarehouse(item)),
            onToggleInventory:()=>_toggleWorldPanel('inventory'),
            onToggleStatus:()=>_toggleWorldPanel('status'),
            onAddStat:(index)=>unawaited(_addStat(index)),
            onToggleSkills:()=>_toggleWorldPanel('skills'),
            onToggleQuestLog:()=>_toggleWorldPanel('quests'),
            onOpenQuest:_openQuestFromLog,
            onAssignSkill:(skill)=>unawaited(_assignSkillToHotbar(skill)),
            onHotbar:(index)=>unawaited(_useHotbarSlot(index)),
            onSendChat:(text)=>unawaited(_sendChat(text)),
            questActive:liveSnapshot?.quests.any((q)=>q.questId==questId)??false,
            rewardSelection:rewardSelection,
            onSelectReward:(index)=>unawaited(_chooseQuestReward(index)),
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
