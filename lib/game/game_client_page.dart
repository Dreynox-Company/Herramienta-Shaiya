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
  bool mapSwitching=false,sectorStreaming=false;
  final List<PsPacket> pendingMapActorPackets=<PsPacket>[];
  PsCharacterDetails? liveDetails;
  PsHitpoints? liveHitpoints;
  PsAdditionalStats? liveAdditionalStats;
  PsMapWeather? liveWeather;
  Map<int,PsActiveBuff> liveBuffs=<int,PsActiveBuff>{};
  int? targetMobGlobalId,targetMobTypeId,targetMobHp,targetMobMaxHp;
  int? targetAttackSpeed,targetMoveSpeed;
  List<PsTargetBuff> targetBuffs=<PsTargetBuff>[];
  PsSkillCasting? targetCasting;
  final Map<int,PsEnteredMap> remotePlayerEntries=<int,PsEnteredMap>{};
  final Map<int,PsPlayerShape> remotePlayerShapes=<int,PsPlayerShape>{};
  final Set<int> remoteShapeLoads=<int>{};
  int? targetPlayerId,targetPlayerHp,targetPlayerMaxHp;
  String? targetPlayerName;
  PsSkillBook? liveSkills;
  PsSkillBar? liveSkillBar;
  List<PsInventoryItem> liveInventory=<PsInventoryItem>[];
  List<PsInventoryItem> liveWarehouse=<PsInventoryItem>[];
  List<PsInventoryItem> liveGuildWarehouse=<PsInventoryItem>[];
  bool guildWarehouseAvailable=false;
  List<PsFriend> liveFriends=<PsFriend>[];
  List<PsPartyMember> livePartyMembers=<PsPartyMember>[];
  PsRaidState? liveRaid;
  List<PsGuildSummary> guildDirectory=<PsGuildSummary>[];
  List<PsGuildMember> liveGuildMembers=<PsGuildMember>[];
  List<PsGuildJoinApplicant> guildApplicants=<PsGuildJoinApplicant>[];
  int liveGuildId=0,liveGuildRank=0;
  String liveGuildName='';
  bool guildListLoading=false;
  PsGuildCreateInvite? pendingGuildCreateInvite;
  final Map<int,PsTradeItem> localTradeItems=<int,PsTradeItem>{},remoteTradeItems=<int,PsTradeItem>{};
  int localTradeMoney=0,remoteTradeMoney=0;
  bool localTradeDecided=false,remoteTradeDecided=false,localTradeConfirmed=false,remoteTradeConfirmed=false;
  int? tradePartnerId,pendingTradeRequesterId,outgoingTradeTargetId;
  final Map<int,PsTradeItem> localDuelItems=<int,PsTradeItem>{},remoteDuelItems=<int,PsTradeItem>{};
  int localDuelMoney=0,remoteDuelMoney=0;
  bool localDuelApproved=false,remoteDuelApproved=false,duelTradeOpen=false,duelStarted=false,duelReady=false;
  int? duelOpponentId,pendingDuelRequesterId,outgoingDuelTargetId;
  double duelCenterX=0,duelCenterZ=0;
  String duelResultText='';
  int? partyLeaderId,pendingPartyRequesterId,outgoingPartyInviteId;
  int? pendingRaidRequesterId;
  int? pendingVehicleRequesterId,vehiclePassengerId;
  bool vehicleMounted=false,vehicleSummoning=false;
  String? pendingFriendRequestName;
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
  bool dead=false;
  bool rebirthPending=false;
  PsDeadRebirth? lastRebirth;
  bool questOpen=true;
  bool rewardSelection=false;
  int rewardNpcId=0;
  bool inventoryOpen=false;
  bool tradeOpen=false;
  bool socialOpen=false;
  bool guildOpen=false;
  bool guildWarehouseOpen=false;
  bool statusOpen=false;
  bool skillsOpen=false;
  bool questLogOpen=false;
  bool shopOpen=false;
  bool blacksmithOpen=false;
  bool gateOpen=false;
  bool warehouseOpen=false;
  NpcShopRule? activeShop;
  int blacksmithMode=0;
  PsInventoryItem? blacksmithItem,blacksmithGem,blacksmithHammer;
  PsLinkingPossibility? blacksmithPossibility;
  PsInventoryItem? blacksmithExtractItem,blacksmithExtractHammer;
  int blacksmithExtractPosition=0;
  PsLinkingPossibility? blacksmithExtractPossibility;
  bool blacksmithBusy=false;
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
    scene.sound=Platform.environment['SHAIYA_QA_DISABLE_BACKEND']!='1';
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
      final target=File(path),temp=File(path+'.tmp');
      await target.parent.create(recursive:true);
      await temp.writeAsString(jsonEncode(payload),flush:true);
      if(await target.exists())await target.delete();
      await temp.rename(target.path);
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
        final friendsPacket=selected.packets.where((p)=>p.type==PsPacketType.friendList).lastOrNull;
        final partyPacket=selected.packets.where((p)=>p.type==PsPacketType.partyList).lastOrNull;
        final raidPacket=selected.packets.where((p)=>p.type==PsPacketType.raidList).lastOrNull;
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
        if(friendsPacket!=null)liveFriends=parseFriendList(friendsPacket).toList();
        if(raidPacket!=null){
          liveRaid=PsRaidState.parse(raidPacket);livePartyMembers=[];partyLeaderId=null;
        }else if(partyPacket!=null){
          final party=PsPartyList.parse(partyPacket);
          livePartyMembers=party.members.toList();
          if(partyLeaderId==null&&party.leaderIndex<party.members.length){
            partyLeaderId=party.members[party.leaderIndex].id;
          }
        }
        if(skillsPacket!=null)liveSkills=PsSkillBook.parse(skillsPacket);
        if(barPacket!=null)liveSkillBar=PsSkillBar.parse(barPacket);
        final entered=await session.enterMap(collect:const Duration(seconds:5));
        final weatherPacket=entered.where((p)=>p.type==PsPacketType.mapWeather).lastOrNull;
        if(weatherPacket!=null)liveWeather=PsMapWeather.parse(weatherPacket);
        final guildWarehousePackets=entered.where((p)=>p.type==PsPacketType.guildWarehouseItemList).toList();
        guildWarehouseAvailable=guildWarehousePackets.isNotEmpty;
        liveGuildWarehouse=[];
        for(final packet in guildWarehousePackets){
          for(final item in parseGuildWarehouseItems(packet)){
            liveGuildWarehouse.removeWhere((x)=>x.slot==item.slot);
            liveGuildWarehouse.add(item);
          }
        }
        liveGuildWarehouse.sort((a,b)=>a.slot.compareTo(b.slot));
        networkSnapshot=PsWorldSnapshot.fromPackets(<PsPacket>[...selected.packets,...entered]);
        liveSnapshot=networkSnapshot;
        liveGuildId=networkSnapshot.self?.guildId??0;
        liveGuildName=selected.details.guildName;
        for(final p in <PsPacket>[...selected.packets,...entered]){_handleGuildPacket(p,notify:false);}
        mapId=current.mapId;
        x=networkSnapshot.self?.x??selected.details.x;
        z=networkSnapshot.self?.z??selected.details.z;
        if(networkSnapshot.quests.isNotEmpty)questId=networkSnapshot.quests.first.questId;
        messages.insert(
          0,
          '[ps0032] Mundo real: ${networkSnapshot.npcs.length} NPC · '
          '${networkSnapshot.mobs.length} mobs · ${networkSnapshot.mapItems.length} drops · '
          '${networkSnapshot.quests.length} quests abiertas.',
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
    if(liveInventory.isNotEmpty){
      await _syncVisibleEquipmentFromInventory();
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
    for(final player in liveSnapshot?.players??const <PsEnteredMap>[]){
      if(player.characterId==liveCharacter?.id)continue;
      remotePlayerEntries[player.characterId]=player;
      unawaited(_ensureRemotePlayer(player));
    }
    if(mounted)setState(()=>loading=false);
    focus.requestFocus();
    await Future<void>.delayed(const Duration(milliseconds:350));
    await _signalQaReady();
  }

  bool _isMapActorPacket(int type)=>{
    PsPacketType.mobEnter,PsPacketType.mobMove,PsPacketType.mobLeave,
    PsPacketType.mapNpcEnter,PsPacketType.mapNpcMove,PsPacketType.mapNpcLeave,
    PsPacketType.characterEnteredMap,PsPacketType.characterLeftMap,
    PsPacketType.characterMove,PsPacketType.characterShape,
    PsPacketType.mapAddItem,PsPacketType.mapRemoveItem,
  }.contains(type);

  Future<void> _applyMapTeleport(PsMapTeleport teleport) async {
    if(liveCharacter!=null&&teleport.characterId!=liveCharacter!.id)return;
    if(mapSwitching)return;
    mapSwitching=true;
    activePortalTrigger=null;
    guildWarehouseAvailable=false;liveGuildWarehouse=[];guildWarehouseOpen=false;
    _closeWorldPanels();
    scene.clearMovement();
    _clearCombatTarget();
    remotePlayerEntries.clear();remotePlayerShapes.clear();remoteShapeLoads.clear();
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
        players:const <PsEnteredMap>[],
        npcs:const <PsNpcEnter>[],mobs:const <PsMobEnter>[],
        quests:previous?.quests??const <PsQuestProgress>[],
        finishedQuests:previous?.finishedQuests??const <PsFinishedQuest>[],
      );
      scene.yaw=0;scene.pitch=.12;scene.distance=5.9;scene.targetY=1.18;
      if(scene.character!=null)scene.character!.root.rotation.y=math.pi;
      scene.updateCamera();
      await liveWorld?.confirmMapLoaded();
      messages.insert(0,'[Mapa] Teleport → ${teleport.mapId} · ${teleport.x.toStringAsFixed(1)}, ${teleport.z.toStringAsFixed(1)} · 0x0201 confirmado.');
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

  Slot? _appearanceSlotForEquipmentSlot(int slot)=>switch(slot){
    0=>Slot.helmet,1=>Slot.upper,2=>Slot.lower,3=>Slot.hand,4=>Slot.foot,15=>Slot.upper,_=>null,
  };

  PsInventoryItem? _equippedItem(int slot)=>
    liveInventory.where((i)=>i.bag==0&&i.slot==slot&&i.type!=0&&i.typeId!=0).firstOrNull;

  Future<void> _applyBodyEquipmentSlot(int equipmentSlot,ItemRule? rule) async {
    final renderSlot=_appearanceSlotForEquipmentSlot(equipmentSlot),look=scene.appearance;
    if(renderSlot==null||look==null)return;
    PartRecord? part;
    if(rule!=null){
      part=look.archetype.parts[renderSlot]?.where((p)=>p.raw.id==rule.image).firstOrNull;
      if(part==null){
        messages.insert(0,'[Equipo 3D] No existe MLT image '+rule.image.toString()+' para '+renderSlot.name+'.');
      }
    }
    try{
      await scene.setAppearance(look.withPart(renderSlot,part));
    }catch(e){messages.insert(0,'[Equipo 3D] '+e.toString());}
  }

  Future<void> _applyWeaponVisual(ItemRule? rule) async {
    if(rule==null){await scene.equip(null);return;}
    final family=weaponFamilyForItemType(rule.type);
    final exact=catalog?.weapons.where((w)=>w.id==rule.image&&weaponFamily(w)==family).firstOrNull;
    final fallback=exact??catalog?.weapons.where((w)=>w.id==rule.image).firstOrNull;
    if(fallback==null){
      messages.insert(0,'[Equipo 3D] Arma ITM no encontrada · family '+family.toString()+' image '+rule.image.toString()+'.');
      await scene.equip(null);
      return;
    }
    try{await scene.equip(fallback);}catch(e){messages.insert(0,'[Equipo 3D] '+e.toString());}
  }

  Future<void> _applyWingVisual(ItemRule? rule) async {
    if(rule==null){await scene.selectCreature(null,'wing');return;}
    final record=catalog?.wings.where((w)=>w.id==rule.image).firstOrNull;
    if(record==null){
      messages.insert(0,'[Equipo 3D] Alas MON image '+rule.image.toString()+' no encontradas.');
      await scene.selectCreature(null,'wing');
      return;
    }
    try{await scene.selectCreature(record,'wing');}catch(e){messages.insert(0,'[Equipo 3D] '+e.toString());}
  }

  CreatureRecord? _mountRecordForItem(int type,int typeId){
    final rule=metadata?.item(type,typeId);
    if(rule==null)return null;
    return catalog?.mounts.where((m)=>m.id==rule.image).firstOrNull;
  }

  Future<void> _applyMountVisual(bool mounted,{int? type,int? typeId}) async {
    if(!mounted){await scene.selectCreature(null,'mount');return;}
    PsInventoryItem? item;
    if(type==null||typeId==null||type==0||typeId==0)item=_equippedItem(13);
    final record=(type!=null&&typeId!=null&&type!=0&&typeId!=0)
      ?_mountRecordForItem(type,typeId)
      :(item==null?null:_mountRecordForItem(item.type,item.typeId));
    if(record==null){
      messages.insert(0,'[Montura] No se encontró el modelo MON de la montura equipada.');
      await scene.selectCreature(null,'mount');
      return;
    }
    try{await scene.selectCreature(record,'mount');}
    catch(e){messages.insert(0,'[Montura] '+e.toString());}
  }

  CreatureRecord? _remoteMountRecord(int characterId,int type,int typeId){
    if(type!=0&&typeId!=0){
      final direct=_mountRecordForItem(type,typeId);
      if(direct!=null)return direct;
    }
    final shape=remotePlayerShapes[characterId];
    final equipment=shape?.equipment.where((e)=>e.slot==13&&!e.empty).firstOrNull;
    if(equipment==null)return null;
    return _mountRecordForItem(equipment.type,equipment.typeId);
  }

  Future<void> _syncVisibleEquipmentFromInventory() async {
    // Primary body slots first, costume last so its full-set semantics can override armor.
    for(final slot in const [0,1,2,3,4]){
      final item=_equippedItem(slot),rule=item==null?null:metadata?.item(item.type,item.typeId);
      await _applyBodyEquipmentSlot(slot,rule);
    }
    final costume=_equippedItem(15);
    if(costume!=null)await _applyBodyEquipmentSlot(15,metadata?.item(costume.type,costume.typeId));
    final weaponItem=_equippedItem(5);
    await _applyWeaponVisual(weaponItem==null?null:metadata?.item(weaponItem.type,weaponItem.typeId));
    final wingItem=_equippedItem(16);
    await _applyWingVisual(wingItem==null?null:metadata?.item(wingItem.type,wingItem.typeId));
    if(vehicleMounted)await _applyMountVisual(true);
  }

  Future<void> _applyEquipmentVisual(PsEquipmentChange change) async {
    if(change.characterId!=liveCharacter?.id)return;
    final rule=(change.type==0||change.typeId==0)?null:metadata?.item(change.type,change.typeId);
    if(change.slot==5){await _applyWeaponVisual(rule);return;}
    if(change.slot==13){
      if(rule==null){vehicleMounted=false;vehicleSummoning=false;await _applyMountVisual(false);}
      else if(vehicleMounted){await _applyMountVisual(true,type:change.type,typeId:change.typeId);}
      return;
    }
    if(change.slot==16){await _applyWingVisual(rule);return;}
    if(_appearanceSlotForEquipmentSlot(change.slot)!=null){
      // Costume removal restores the ordinary upper armor from live bag-0 state.
      if(change.slot==15&&rule==null){
        final upper=_equippedItem(1);
        await _applyBodyEquipmentSlot(1,upper==null?null:metadata?.item(upper.type,upper.typeId));
      }else{
        await _applyBodyEquipmentSlot(change.slot,rule);
      }
    }
  }
  String? _remoteRaceKey(int race)=>switch(race){
    0=>'human',1=>'elf',2=>'vile',3=>'deatheater',_=>null,
  };

  Appearance? _remoteAppearance(PsPlayerShape shape){
    final c=catalog,race=_remoteRaceKey(shape.race);
    if(c==null||race==null)return null;
    final female=shape.gender!=0;
    final candidates=c.archetypes.where((a)=>a.race==race&&a.female==female).toList();
    if(candidates.isEmpty)return null;

    int score(Archetype a){
      var value=0;
      for(final equipment in shape.equipment){
        if(equipment.empty)continue;
        final slot=_appearanceSlotForEquipmentSlot(equipment.slot);
        if(slot==null)continue;
        final rule=metadata?.item(equipment.type,equipment.typeId);
        if(rule==null)continue;
        if((a.parts[slot]??const <PartRecord>[]).any((p)=>p.raw.id==rule.image)){
          value+=slot==Slot.upper?4:2;
        }
      }
      return value;
    }

    candidates.sort((a,b)=>score(b).compareTo(score(a)));
    try{
      var look=Appearance.initial(candidates.first);
      final faces=look.archetype.parts[Slot.face]??const <PartRecord>[];
      final hairs=look.archetype.parts[Slot.hair]??const <PartRecord>[];
      if(shape.face>=0&&shape.face<faces.length)look=look.withPart(Slot.face,faces[shape.face]);
      if(shape.hair>=0&&shape.hair<hairs.length)look=look.withPart(Slot.hair,hairs[shape.hair]);

      for(final equipmentSlot in const [0,1,2,3,4]){
        final equipment=shape.equipment.where((e)=>e.slot==equipmentSlot&&!e.empty).firstOrNull;
        if(equipment==null)continue;
        final slot=_appearanceSlotForEquipmentSlot(equipmentSlot),rule=metadata?.item(equipment.type,equipment.typeId);
        if(slot==null||rule==null)continue;
        final part=(look.archetype.parts[slot]??const <PartRecord>[]).where((p)=>p.raw.id==rule.image).firstOrNull;
        if(part!=null)look=look.withPart(slot,part);
      }

      final costume=shape.equipment.where((e)=>e.slot==15&&!e.empty).firstOrNull;
      if(costume!=null){
        final rule=metadata?.item(costume.type,costume.typeId);
        if(rule!=null){
          final part=(look.archetype.parts[Slot.upper]??const <PartRecord>[]).where((p)=>p.raw.id==rule.image).firstOrNull;
          if(part!=null)look=look.withPart(Slot.upper,part);
        }
      }
      return look;
    }catch(e){
      messages.insert(0,'[Jugador remoto] Apariencia '+shape.characterId.toString()+': '+e.toString());
      return null;
    }
  }

  Future<void> _renderRemotePlayer(PsEnteredMap entered,PsPlayerShape shape) async {
    if(entered.characterId==liveCharacter?.id||stage!=GameStage.world)return;
    final appearance=_remoteAppearance(shape);
    if(appearance==null){
      messages.insert(0,'[Jugador remoto] Sin arquetipo compatible para '+shape.name+' ('+shape.characterId.toString()+').');
      return;
    }
    await scene.addNetworkPlayer(
      characterId:entered.characterId,appearance:appearance,
      name:shape.name.isEmpty?('#'+shape.characterId.toString()):shape.name,
      x:entered.x,y:entered.y,z:entered.z,angle:entered.angle,
    );
    if(shape.dead)unawaited(scene.networkRemotePlayerDeath(entered.characterId));
  }

  Future<void> _ensureRemotePlayer(PsEnteredMap entered) async {
    final id=entered.characterId,session=liveWorld;
    if(id==liveCharacter?.id||session==null||!remoteShapeLoads.add(id))return;
    try{
      final shape=remotePlayerShapes[id]??await session.requestCharacterShape(id);
      remotePlayerShapes[id]=shape;
      final latest=remotePlayerEntries[id]??entered;
      if(stage==GameStage.world&&remotePlayerEntries.containsKey(id)){
        await _renderRemotePlayer(latest,shape);
      }
    }catch(e){
      messages.insert(0,'[Jugador remoto] CHARACTER_SHAPE '+id.toString()+': '+e.toString());
    }finally{
      remoteShapeLoads.remove(id);
      if(mounted)setState((){});
    }
  }

  void _clearCombatTarget(){
    targetMobGlobalId=targetMobTypeId=targetMobHp=targetMobMaxHp=null;
    targetPlayerId=targetPlayerHp=targetPlayerMaxHp=null;targetPlayerName=null;
    targetAttackSpeed=targetMoveSpeed=null;targetBuffs=<PsTargetBuff>[];targetCasting=null;
  }

  void _sortInventory(){
    liveInventory.sort((a,b){
      final bag=a.bag.compareTo(b.bag);
      return bag!=0?bag:a.slot.compareTo(b.slot);
    });
  }

  void _upsertInventoryItem(PsInventoryItem item){
    if(item.bag==254)return; // backend compatibility quirk for withdrawals from guild bag 255
    final target=item.bag==100
      ?liveWarehouse
      :item.bag==255
        ?liveGuildWarehouse
        :liveInventory;
    target.removeWhere((x)=>x.bag==item.bag&&x.slot==item.slot);
    if(item.type!=0&&item.typeId!=0&&item.count>0)target.add(item);
    if(item.bag==100){
      liveWarehouse.sort((a,b)=>a.slot.compareTo(b.slot));
    }else if(item.bag==255){
      liveGuildWarehouse.sort((a,b)=>a.slot.compareTo(b.slot));
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
      self:s.self,players:s.players,
      npcs:[...s.npcs.where((x)=>x.globalId!=npc.globalId),npc],
      mobs:s.mobs,quests:s.quests,finishedQuests:s.finishedQuests,
    );
  }

  void _snapshotAddMob(PsMobEnter mob){
    final s=liveSnapshot;if(s==null)return;
    liveSnapshot=PsWorldSnapshot(
      self:s.self,players:s.players,npcs:s.npcs,
      mobs:[...s.mobs.where((x)=>x.globalId!=mob.globalId),mob],
      quests:s.quests,finishedQuests:s.finishedQuests,
    );
  }

  void _snapshotRemoveActor(int globalId,{required bool mob}){
    final s=liveSnapshot;if(s==null)return;
    liveSnapshot=PsWorldSnapshot(
      self:s.self,players:s.players,
      npcs:mob?s.npcs:s.npcs.where((x)=>x.globalId!=globalId).toList(),
      mobs:mob?s.mobs.where((x)=>x.globalId!=globalId).toList():s.mobs,
      quests:s.quests,finishedQuests:s.finishedQuests,
    );
  }
  void _snapshotAddMapItem(PsMapItem item){
    final s=liveSnapshot;if(s==null)return;
    liveSnapshot=PsWorldSnapshot(
      self:s.self,players:s.players,npcs:s.npcs,mobs:s.mobs,
      mapItems:[...s.mapItems.where((x)=>x.id!=item.id),item],worldDay:s.worldDay,
      quests:s.quests,finishedQuests:s.finishedQuests,
    );
  }

  void _snapshotRemoveMapItem(int id){
    final s=liveSnapshot;if(s==null)return;
    liveSnapshot=PsWorldSnapshot(
      self:s.self,players:s.players,npcs:s.npcs,mobs:s.mobs,
      mapItems:s.mapItems.where((x)=>x.id!=id).toList(),worldDay:s.worldDay,
      quests:s.quests,finishedQuests:s.finishedQuests,
    );
  }

  void _snapshotWorldDay(PsWorldDay day){
    final s=liveSnapshot;if(s==null)return;
    liveSnapshot=PsWorldSnapshot(
      self:s.self,players:s.players,npcs:s.npcs,mobs:s.mobs,
      mapItems:s.mapItems,worldDay:day,
      quests:s.quests,finishedQuests:s.finishedQuests,
    );
  }

  void _snapshotUpsertPlayer(PsEnteredMap player){
    final s=liveSnapshot;if(s==null)return;
    liveSnapshot=PsWorldSnapshot(
      self:s.self,
      players:[...s.players.where((x)=>x.characterId!=player.characterId),player],
      npcs:s.npcs,mobs:s.mobs,quests:s.quests,finishedQuests:s.finishedQuests,
    );
  }

  void _snapshotRemovePlayer(int characterId){
    final s=liveSnapshot;if(s==null)return;
    liveSnapshot=PsWorldSnapshot(
      self:s.self,players:s.players.where((x)=>x.characterId!=characterId).toList(),
      npcs:s.npcs,mobs:s.mobs,quests:s.quests,finishedQuests:s.finishedQuests,
    );
  }

  void _handleLivePacket(PsPacket packet){
    if(stage!=GameStage.world)return;
    if((mapSwitching||sectorStreaming)&&_isMapActorPacket(packet.type)){pendingMapActorPackets.add(packet);return;}
    if(packet.type==PsPacketType.mapAddItem&&packet.body.length>=24){
      try{
        final item=PsMapItem.parse(packet);_snapshotAddMapItem(item);
        messages.insert(0,'[Drop] '+(catalog?.itemName(item.type,item.typeId,uiLocale)??('${item.type}:${item.typeId}'))+' apareció.');
      }catch(e){messages.insert(0,'[Drop] MAP_ADD_ITEM: '+e.toString());}
      if(mounted)setState((){});
      return;
    }else if(packet.type==PsPacketType.mapRemoveItem&&packet.body.length>=4){
      try{_snapshotRemoveMapItem(parseMapItemRemove(packet));}
      catch(e){messages.insert(0,'[Drop] MAP_REMOVE_ITEM: '+e.toString());}
      if(mounted)setState((){});
      return;
    }else if(packet.type==PsPacketType.worldDay&&packet.body.length>=4){
      try{_snapshotWorldDay(PsWorldDay.parse(packet));}
      catch(e){messages.insert(0,'[Mundo] WORLD_DAY: '+e.toString());}
      if(mounted)setState((){});
      return;
    }
    if(packet.type==PsPacketType.characterMapTeleport&&packet.body.length>=18){
      try{unawaited(_applyMapTeleport(PsMapTeleport.parse(packet)));}
      catch(e){messages.insert(0,'[Mapa] CHARACTER_MAP_TELEPORT: '+e.toString());}
      return;
    }
    if(packet.type==PsPacketType.characterEnteredMap&&packet.body.length>=27){
      try{
        final entered=PsEnteredMap.parse(packet);
        if(entered.characterId!=liveCharacter?.id){
          remotePlayerEntries[entered.characterId]=entered;
          _snapshotUpsertPlayer(entered);
          unawaited(_ensureRemotePlayer(entered));
        }
      }catch(e){messages.insert(0,'[Jugador remoto] ENTER_MAP: '+e.toString());}
      if(mounted)setState((){});
      return;
    }else if(packet.type==PsPacketType.characterShape&&packet.body.length>=685){
      try{
        final shape=PsPlayerShape.parse(packet);
        if(shape.characterId!=liveCharacter?.id){
          remotePlayerShapes[shape.characterId]=shape;
          final entered=remotePlayerEntries[shape.characterId];
          if(entered!=null&&!remoteShapeLoads.contains(shape.characterId)){
            unawaited(_renderRemotePlayer(entered,shape));
          }
          if(targetPlayerId==shape.characterId)targetPlayerName=shape.name;
        }
      }catch(e){messages.insert(0,'[Jugador remoto] SHAPE: '+e.toString());}
      if(mounted)setState((){});
      return;
    }else if(packet.type==PsPacketType.characterMove&&packet.body.length>=19){
      try{
        final move=PsCharacterMove.parse(packet);
        if(move.characterId!=liveCharacter?.id){
          final old=remotePlayerEntries[move.characterId];
          final entered=PsEnteredMap(
            move.characterId,old?.isAdmin??0,move.angle,move.x,move.y,move.z,
            old?.guildId??0,old?.vehicleId??0,
          );
          remotePlayerEntries[move.characterId]=entered;_snapshotUpsertPlayer(entered);
          if(scene.networkPlayerActors.containsKey(move.characterId)){
            scene.moveNetworkPlayer(move.characterId,move.x,move.y,move.z,move.angle,move.motion);
          }else{
            unawaited(_ensureRemotePlayer(entered));
          }
        }
      }catch(e){messages.insert(0,'[Jugador remoto] MOVE: '+e.toString());}
      if(mounted)setState((){});
      return;
    }else if(packet.type==PsPacketType.characterLeftMap&&packet.body.length>=4){
      try{
        final left=PsCharacterLeftMap.parse(packet),id=left.characterId;
        if(id!=liveCharacter?.id){
          remotePlayerEntries.remove(id);remotePlayerShapes.remove(id);remoteShapeLoads.remove(id);
          _snapshotRemovePlayer(id);scene.removeNetworkPlayer(id);
          if(targetPlayerId==id)_clearCombatTarget();
        }
      }catch(e){messages.insert(0,'[Jugador remoto] LEFT_MAP: '+e.toString());}
      if(mounted)setState((){});
      return;
    }else if(packet.type==PsPacketType.targetCharacterMaxHp&&packet.body.length>=12){
      try{
        final hp=PsTargetCharacterSelection.parse(packet);
        targetPlayerId=hp.targetId;targetPlayerMaxHp=hp.maxHp;targetPlayerHp=hp.currentHp;
        targetPlayerName=remotePlayerShapes[hp.targetId]?.name??_knownCharacterName(hp.targetId);
        targetMobGlobalId=targetMobTypeId=targetMobHp=targetMobMaxHp=null;
        targetBuffs=<PsTargetBuff>[];targetCasting=null;
      }catch(e){messages.insert(0,'[PvP Target] '+e.toString());}
      if(mounted)setState((){});
      return;
    }else if(packet.type==PsPacketType.targetCharacterHpUpdate&&packet.body.length>=14){
      try{
        final hp=PsTargetCharacterHp.parse(packet);
        if(targetPlayerId==hp.targetId){
          targetPlayerHp=hp.currentHp;targetPlayerMaxHp=hp.maxHp;
          targetAttackSpeed=hp.attackSpeed;targetMoveSpeed=hp.moveSpeed;
          targetPlayerName=remotePlayerShapes[hp.targetId]?.name??targetPlayerName??_knownCharacterName(hp.targetId);
        }
      }catch(e){messages.insert(0,'[PvP Target] '+e.toString());}
      if(mounted)setState((){});
      return;
    }else if(packet.type==PsPacketType.targetBuffs&&packet.body.length>=6){
      try{
        final state=PsTargetBuffs.parse(packet);
        final selected=(state.character&&targetPlayerId==state.targetId)||(state.mob&&targetMobGlobalId==state.targetId);
        if(selected)targetBuffs=state.buffs.toList();
      }catch(e){messages.insert(0,'[Target Buff] '+e.toString());}
      if(mounted)setState((){});
      return;
    }else if((packet.type==PsPacketType.targetBuffAdd||packet.type==PsPacketType.targetBuffRemove)&&packet.body.length>=8){
      try{
        final change=PsTargetBuffChange.parse(packet);
        final selected=(change.character&&targetPlayerId==change.targetId)||(change.mob&&targetMobGlobalId==change.targetId);
        if(selected){
          targetBuffs.removeWhere((x)=>x.skillId==change.skillId&&x.skillLevel==change.skillLevel);
          if(packet.type==PsPacketType.targetBuffAdd){
            targetBuffs=[...targetBuffs,PsTargetBuff(change.skillId,change.skillLevel,-1)];
          }
        }
      }catch(e){messages.insert(0,'[Target Buff] '+e.toString());}
      if(mounted)setState((){});
      return;
    }else if(packet.type==PsPacketType.targetMobGetState&&packet.body.length>=10){
      try{
        final state=PsTargetMobState.parse(packet);
        if(targetMobGlobalId==state.targetId){
          targetMobHp=state.currentHp;targetAttackSpeed=state.attackSpeed;targetMoveSpeed=state.moveSpeed;
        }
      }catch(e){messages.insert(0,'[Target State] '+e.toString());}
      if(mounted)setState((){});
      return;
    }else if((packet.type==PsPacketType.characterSkillCasting||packet.type==PsPacketType.mobSkillCasting)&&packet.body.length>=11){
      try{
        final casting=PsSkillCasting.parse(packet);
        final selected=casting.casterId==targetPlayerId||casting.casterId==targetMobGlobalId||
          casting.targetId==targetPlayerId||casting.targetId==targetMobGlobalId;
        if(selected)targetCasting=casting;
        final name=catalog?.skillName(casting.skillId,casting.skillLevel,uiLocale)??('Skill '+casting.skillId.toString());
        messages.insert(0,'[Cast] '+name+' Lv.'+casting.skillLevel.toString()+'.');
      }catch(e){messages.insert(0,'[Cast] '+e.toString());}
      if(mounted)setState((){});
      return;
    }else if(packet.type==PsPacketType.characterRecover&&packet.body.length>=16){
      try{
        final recovery=PsCharacterRecovery.parse(packet);
        if(recovery.characterId==liveCharacter?.id){
          liveHitpoints=PsHitpoints(recovery.hp,recovery.mp,recovery.sp);
        }else if(recovery.characterId==targetPlayerId){
          targetPlayerHp=recovery.hp;
        }
      }catch(e){messages.insert(0,'[Recover] '+e.toString());}
      if(mounted)setState((){});
      return;
    }else if(packet.type==PsPacketType.characterMaxHitpoints&&packet.body.length>=9){
      try{
        final max=PsMaxHitpointUpdate.parse(packet);
        if(max.characterId==targetPlayerId&&max.hitpointType==0)targetPlayerMaxHp=max.value;
      }catch(e){messages.insert(0,'[Max HP] '+e.toString());}
      if(mounted)setState((){});
      return;
    }else if((packet.type==PsPacketType.characterSkillKeep||packet.type==PsPacketType.mobSkillKeep)&&packet.body.length>=13){
      try{
        final keep=PsSkillKeep.parse(packet);
        final name=catalog?.skillName(keep.skillId,keep.skillLevel,uiLocale)??('Skill '+keep.skillId.toString());
        if(keep.sourceId==liveCharacter?.id||keep.sourceId==targetPlayerId||keep.sourceId==targetMobGlobalId){
          messages.insert(0,'[Skill continuo] '+name+' · HP '+keep.hpDamage.toString()+' / SP '+keep.spDamage.toString()+' / MP '+keep.mpDamage.toString()+'.');
        }
      }catch(e){messages.insert(0,'[Skill continuo] '+e.toString());}
      if(mounted)setState((){});
      return;
    }else if(packet.type==PsPacketType.characterCharacterAutoAttack&&packet.body.length>=15){
      try{
        final hit=PsCharacterUsualHit.parse(packet),self=liveCharacter?.id;
        if(hit.success&&self!=null){
          if(hit.attackerId==self){
            if(targetPlayerId==hit.targetId&&targetPlayerHp!=null)targetPlayerHp=math.max(0,targetPlayerHp!-hit.hpDamage);
            unawaited(scene.networkPlayerAttackCharacter(hit.targetId));
            if(hit.hpDamage>0)unawaited(scene.networkRemotePlayerHit(hit.targetId,hit.hpDamage));
          }else if(hit.targetId==self){
            final hp=liveHitpoints;
            if(hp!=null)liveHitpoints=PsHitpoints(math.max(0,hp.hp-hit.hpDamage),math.max(0,hp.mp-hit.mpDamage),math.max(0,hp.sp-hit.spDamage));
            if(hit.hpDamage>0)unawaited(scene.networkPlayerHit(hit.hpDamage));
          }else if(hit.hpDamage>0){
            unawaited(scene.networkRemotePlayerHit(hit.targetId,hit.hpDamage));
          }
        }
      }catch(e){messages.insert(0,'[PvP] Autoataque: '+e.toString());}
      if(mounted)setState((){});
      return;
    }else if(<int>{PsPacketType.useCharacterTargetSkill,PsPacketType.useCharacterRangeSkill}.contains(packet.type)&&packet.body.length>=19){
      try{
        final hit=PsCharacterSkillHit.parse(packet),self=liveCharacter?.id;
        if(targetCasting?.casterId==hit.attackerId)targetCasting=null;
        if(hit.success&&self!=null){
          if(hit.attackerId==self){
            if(targetPlayerId==hit.targetId&&targetPlayerHp!=null)targetPlayerHp=math.max(0,targetPlayerHp!-hit.hpDamage);
            unawaited(scene.networkPlayerAttackCharacter(hit.targetId));
            if(hit.hpDamage>0)unawaited(scene.networkRemotePlayerHit(hit.targetId,hit.hpDamage));
          }else if(hit.targetId==self){
            final hp=liveHitpoints;
            if(hp!=null)liveHitpoints=PsHitpoints(math.max(0,hp.hp-hit.hpDamage),math.max(0,hp.mp-hit.mpDamage),math.max(0,hp.sp-hit.spDamage));
            if(hit.hpDamage>0)unawaited(scene.networkPlayerHit(hit.hpDamage));
          }else if(hit.hpDamage>0){
            unawaited(scene.networkRemotePlayerHit(hit.targetId,hit.hpDamage));
          }
        }
      }catch(e){messages.insert(0,'[PvP] Skill: '+e.toString());}
      if(mounted)setState((){});
      return;
    }
    if(packet.type==PsPacketType.characterMotion&&packet.body.length>=5){
      try{
        final motion=PsCharacterMotion.parse(packet);
        if(motion.characterId!=liveCharacter?.id)unawaited(scene.applyNetworkPlayerMotion(motion.characterId,motion.motion));
      }catch(e){messages.insert(0,'[Movimiento] MOTION: '+e.toString());}
      return;
    }else if(packet.type==PsPacketType.characterShapeUpdate&&packet.body.length>=13){
      try{
        final update=PsShapeUpdate.parse(packet),self=liveCharacter?.id;
        if(update.characterId==self){
          if(update.mounted){
            vehicleMounted=true;vehicleSummoning=false;
            unawaited(_applyMountVisual(true,type:update.param1,typeId:update.param2));
          }else if(update.shape==0){
            vehicleMounted=false;vehicleSummoning=false;vehiclePassengerId=null;
            unawaited(_applyMountVisual(false));
          }
        }else if(remotePlayerEntries.containsKey(update.characterId)){
          if(update.mounted){
            final record=_remoteMountRecord(update.characterId,update.param1,update.param2);
            if(record!=null)unawaited(scene.setNetworkPlayerMount(update.characterId,record));
          }else if(update.shape==0){
            unawaited(scene.setNetworkPlayerMount(update.characterId,null));
          }
        }
      }catch(e){messages.insert(0,'[Montura] SHAPE_UPDATE: '+e.toString());}
      if(mounted)setState((){});
      return;
    }else if(packet.type==PsPacketType.useVehicleReady&&packet.body.length>=4){
      final id=ByteData.sublistView(packet.body).getUint32(0,Endian.little);
      if(id==liveCharacter?.id){
        vehicleSummoning=true;
        messages.insert(0,'[Montura] Invocando montura…');
      }
      if(mounted)setState((){});
      return;
    }else if(packet.type==PsPacketType.useVehicle&&packet.body.length>=2){
      try{
        final state=PsUseVehicleState.parse(packet);
        vehicleSummoning=false;
        if(state.success){
          vehicleMounted=state.mounted;
          unawaited(_applyMountVisual(state.mounted));
          messages.insert(0,state.mounted?'[Montura] Montura activa.':'[Montura] Has bajado de la montura.');
        }else{
          messages.insert(0,'[Montura] World rechazó el uso de la montura.');
        }
      }catch(e){messages.insert(0,'[Montura] '+e.toString());}
      if(mounted)setState((){});
      return;
    }else if(packet.type==PsPacketType.vehicleRequest&&packet.body.length>=4){
      pendingVehicleRequesterId=ByteData.sublistView(packet.body).getUint32(0,Endian.little);
      messages.insert(0,'[Montura] '+_knownCharacterName(pendingVehicleRequesterId!)+' te invita a subir.');
      if(mounted)setState((){});
      return;
    }else if(packet.type==PsPacketType.vehicleResponse&&packet.body.isNotEmpty){
      final status=packet.body[0];
      if(status==0)messages.insert(0,'[Montura] Invitación de pasajero aceptada.');
      else if(status==1)messages.insert(0,'[Montura] Invitación de pasajero rechazada.');
      else messages.insert(0,'[Montura] No se pudo compartir la montura.');
      if(mounted)setState((){});
      return;
    }else if(packet.type==PsPacketType.useVehicle2&&packet.body.length>=8){
      try{
        final passenger=PsVehiclePassenger.parse(packet),self=liveCharacter?.id;
        if(passenger.passengerId==self){
          vehiclePassengerId=passenger.vehicleCharacterId==0?null:passenger.vehicleCharacterId;
          vehicleMounted=vehiclePassengerId!=null;
          messages.insert(0,vehiclePassengerId==null?'[Montura] Has bajado de la montura compartida.':'[Montura] Pasajero de '+_knownCharacterName(vehiclePassengerId!)+'.');
        }else if(passenger.vehicleCharacterId==self){
          messages.insert(0,passenger.passengerId==0?'[Montura] Pasajero retirado.':'[Montura] Pasajero #'+passenger.passengerId.toString()+' subió.');
        }
      }catch(e){messages.insert(0,'[Montura] Pasajero: '+e.toString());}
      if(mounted)setState((){});
      return;
    }

    if(packet.type==PsPacketType.duelRequest&&packet.body.length>=8){
      try{
        final req=PsDuelRequest.parse(packet),self=liveCharacter?.id??0;
        duelOpponentId=req.starterId==self?req.opponentId:req.starterId;
        if(req.opponentId==self&&req.starterId!=self){
          pendingDuelRequesterId=req.starterId;
          _closeWorldPanels();
          messages.insert(0,'[Duel] '+_knownCharacterName(req.starterId)+' te ha desafiado.');
        }else if(req.starterId==self){
          outgoingDuelTargetId=req.opponentId;
          messages.insert(0,'[Duel] Esperando respuesta de '+_knownCharacterName(req.opponentId)+'.');
        }
      }catch(e){messages.insert(0,'[Duel] '+e.toString());}
    }else if(packet.type==PsPacketType.duelResponse&&packet.body.length>=5){
      try{
        final response=PsDuelResponse.parse(packet);
        if(response.accepted){
          duelOpponentId=response.characterId==liveCharacter?.id?duelOpponentId:response.characterId;
          messages.insert(0,'[Duel] Desafío aceptado.');
        }else{
          messages.insert(0,'[Duel] Desafío no aceptado ('+response.response.toString()+').');
          _resetDuel();
        }
      }catch(e){messages.insert(0,'[Duel] '+e.toString());}
    }else if(packet.type==PsPacketType.duelTrade&&packet.body.length>=5){
      try{
        final open=PsDuelTradeOpen.parse(packet);
        _resetDuel();
        duelOpponentId=open.characterId;
        duelTradeOpen=true;
        inventoryOpen=true;
        _closeWorldPanels();
        duelTradeOpen=true;
        inventoryOpen=true;
        messages.insert(0,'[Duel] Ventana de apuesta abierta contra '+_knownCharacterName(open.characterId)+'.');
      }catch(e){messages.insert(0,'[Duel] '+e.toString());}
    }else if(packet.type==PsPacketType.duelTradeAddItem&&packet.body.length>=4){
      try{
        final ack=PsDuelTradeItemAck.parse(packet);
        final item=liveInventory.where((i)=>i.bag==ack.bag&&i.slot==ack.slot).firstOrNull;
        if(item!=null)localDuelItems[ack.tradeSlot]=_duelItemFromInventory(item,ack.tradeSlot,ack.count);
        localDuelApproved=remoteDuelApproved=false;
      }catch(e){messages.insert(0,'[Duel] '+e.toString());}
    }else if(packet.type==PsPacketType.duelTradeOpponentAddItem&&packet.body.length>=108){
      try{
        final item=PsDuelTradeItem.parse(packet);
        remoteDuelItems[item.tradeSlot]=_duelItemFromRemote(item);
        localDuelApproved=remoteDuelApproved=false;
      }catch(e){messages.insert(0,'[Duel] '+e.toString());}
    }else if(packet.type==PsPacketType.duelTradeRemoveItem&&packet.body.length>=2){
      try{
        final remove=PsDuelTradeRemove.parse(packet);
        if(remove.senderType==1)localDuelItems.remove(remove.tradeSlot);
        else if(remove.senderType==2)remoteDuelItems.remove(remove.tradeSlot);
        localDuelApproved=remoteDuelApproved=false;
      }catch(e){messages.insert(0,'[Duel] '+e.toString());}
    }else if(packet.type==PsPacketType.duelTradeAddMoney&&packet.body.length>=5){
      try{
        final money=PsDuelTradeMoney.parse(packet);
        if(money.senderType==1)localDuelMoney=money.money;
        else if(money.senderType==2)remoteDuelMoney=money.money;
        localDuelApproved=remoteDuelApproved=false;
      }catch(e){messages.insert(0,'[Duel] '+e.toString());}
    }else if(packet.type==PsPacketType.duelTradeOk&&packet.body.length>=2){
      try{
        final approval=PsDuelTradeApproval.parse(packet);
        if(approval.senderType==1)localDuelApproved=approval.approved;
        else if(approval.senderType==2)remoteDuelApproved=approval.approved;
      }catch(e){messages.insert(0,'[Duel] '+e.toString());}
    }else if(packet.type==PsPacketType.duelReady&&packet.body.length>=8){
      try{
        final ready=PsDuelReady.parse(packet);
        duelReady=true;duelTradeOpen=false;duelCenterX=ready.x;duelCenterZ=ready.z;
        inventoryOpen=false;
        messages.insert(0,'[Duel] Duelo listo · centro '+ready.x.toStringAsFixed(1)+', '+ready.z.toStringAsFixed(1)+'.');
      }catch(e){messages.insert(0,'[Duel] '+e.toString());}
    }else if(packet.type==PsPacketType.duelCloseTrade&&packet.body.isNotEmpty){
      duelTradeOpen=false;inventoryOpen=false;
      messages.insert(0,'[Duel] Ventana de apuesta cerrada ('+packet.body[0].toString()+').');
    }else if(packet.type==PsPacketType.duelStart){
      duelStarted=true;duelReady=false;duelTradeOpen=false;inventoryOpen=false;
      messages.insert(0,'[Duel] ¡COMIENZA EL DUELO!');
    }else if(packet.type==PsPacketType.duelCancel&&packet.body.length>=5){
      try{
        final cancel=PsDuelCancel.parse(packet);
        messages.insert(0,'[Duel] Cancelado · razón '+cancel.reason.toString()+' · jugador '+cancel.playerId.toString()+'.');
      }catch(e){messages.insert(0,'[Duel] '+e.toString());}
      _resetDuel();
    }else if(packet.type==PsPacketType.duelWinLose&&packet.body.isNotEmpty){
      try{
        final result=PsDuelResult.parse(packet);
        duelResultText=result.won?(uiLocale=='spn'?'VICTORIA':'VICTORY'):(uiLocale=='spn'?'DERROTA':'DEFEAT');
        messages.insert(0,'[Duel] '+duelResultText+'.');
      }catch(e){messages.insert(0,'[Duel] '+e.toString());}
      _resetDuel(keepResult:true);
    }else if(packet.type==PsPacketType.tradeRequest&&packet.body.length>=4){
      pendingTradeRequesterId=ByteData.sublistView(packet.body).getUint32(0,Endian.little);
      _closeWorldPanels();tradeOpen=true;
      messages.insert(0,'[Trade] Solicitud de '+_knownCharacterName(pendingTradeRequesterId!)+'.');
    }else if(packet.type==PsPacketType.tradeStart&&packet.body.length>=4){
      final id=ByteData.sublistView(packet.body).getUint32(0,Endian.little);
      _resetTrade(close:false);tradePartnerId=id;pendingTradeRequesterId=null;tradeOpen=true;inventoryOpen=true;
      messages.insert(0,'[Trade] Intercambio iniciado con '+_knownCharacterName(id)+'.');
    }else if(packet.type==PsPacketType.tradeOwnerAddItem&&packet.body.length>=4){
      try{
        final ack=PsTradeOwnerItemAck.parse(packet);
        final item=liveInventory.where((i)=>i.bag==ack.bag&&i.slot==ack.slot).firstOrNull;
        if(item!=null)localTradeItems[ack.tradeSlot]=_tradeItemFromInventory(item,ack.tradeSlot,ack.count);
        localTradeDecided=remoteTradeDecided=localTradeConfirmed=remoteTradeConfirmed=false;
      }catch(e){messages.insert(0,'[Trade] '+e.toString());}
    }else if(packet.type==PsPacketType.tradeReceiverAddItem&&packet.body.length>=108){
      try{
        final item=PsTradeItem.parse(packet);remoteTradeItems[item.tradeSlot]=item;
        localTradeDecided=remoteTradeDecided=localTradeConfirmed=remoteTradeConfirmed=false;
      }catch(e){messages.insert(0,'[Trade] '+e.toString());}
    }else if(packet.type==PsPacketType.tradeRemoveItem&&packet.body.isNotEmpty){
      final byWho=packet.body[0];
      if(byWho==2){
        // Backend ps0032 no incluye el slot remoto retirado; vaciamos esa oferta
        // para no dejar items visualmente aceptados que ya no están en World.
        remoteTradeItems.clear();
      }
      localTradeDecided=remoteTradeDecided=localTradeConfirmed=remoteTradeConfirmed=false;
    }else if(packet.type==PsPacketType.tradeAddMoney&&packet.body.length>=5){
      try{
        final money=PsTradeMoney.parse(packet);
        if(money.byWho==1)localTradeMoney=money.money;else if(money.byWho==2)remoteTradeMoney=money.money;
        localTradeDecided=remoteTradeDecided=localTradeConfirmed=remoteTradeConfirmed=false;
      }catch(e){messages.insert(0,'[Trade] '+e.toString());}
    }else if(packet.type==PsPacketType.tradeDecide&&packet.body.length>=2){
      try{
        final d=PsTradeDecision.parse(packet);
        if(d.byWho==1)localTradeDecided=d.decided;else if(d.byWho==2)remoteTradeDecided=d.decided;
        if(!d.decided)localTradeConfirmed=remoteTradeConfirmed=false;
      }catch(e){messages.insert(0,'[Trade] '+e.toString());}
    }else if(packet.type==PsPacketType.tradeFinish&&packet.body.length>=2){
      try{
        final f=PsTradeConfirmation.parse(packet);
        if(f.declined){
          localTradeConfirmed=remoteTradeConfirmed=false;
        }else if(f.byWho==1){
          localTradeConfirmed=true;
        }else if(f.byWho==2){
          remoteTradeConfirmed=true;
        }
      }catch(e){messages.insert(0,'[Trade] '+e.toString());}
    }else if(packet.type==PsPacketType.tradeStop&&packet.body.isNotEmpty){
      final reason=packet.body[0];
      messages.insert(0,reason==0?'[Trade] Intercambio completado.':'[Trade] Intercambio cancelado.');
      _resetTrade();
      inventoryOpen=false;
    }else if(_handleGuildPacket(packet)){
      // Guild packet consumed.
    }else if(packet.type==PsPacketType.friendList){
      try{liveFriends=parseFriendList(packet).toList();}
      catch(e){messages.insert(0,'[Friends] '+e.toString());}
    }else if(packet.type==PsPacketType.friendRequest&&packet.body.length>=21){
      try{
        pendingFriendRequestName=parseFriendRequestName(packet);
        _closeWorldPanels();socialOpen=true;
        messages.insert(0,'[Friends] Solicitud de '+pendingFriendRequestName!+'.');
      }catch(e){messages.insert(0,'[Friends] '+e.toString());}
    }else if(packet.type==PsPacketType.friendResponse&&packet.body.isNotEmpty){
      final accepted=packet.body[0]!=0;
      messages.insert(0,'[Friends] Solicitud '+(accepted?'aceptada.':'rechazada.'));
    }else if(packet.type==PsPacketType.friendAdd&&packet.body.length>=26){
      try{
        final friend=parseFriendAdd(packet);_upsertFriend(friend);
        messages.insert(0,'[Friends] '+friend.name+' agregado.');
      }catch(e){messages.insert(0,'[Friends] '+e.toString());}
    }else if(packet.type==PsPacketType.friendDelete&&packet.body.length>=4){
      final id=ByteData.sublistView(packet.body).getUint32(0,Endian.little);
      final old=liveFriends.where((f)=>f.id==id).firstOrNull;
      liveFriends=liveFriends.where((f)=>f.id!=id).toList();
      if(old!=null)messages.insert(0,'[Friends] '+old.name+' eliminado.');
    }else if(packet.type==PsPacketType.friendOnline&&packet.body.length>=5){
      final d=ByteData.sublistView(packet.body),id=d.getUint32(0,Endian.little),online=packet.body[4]!=0;
      final old=liveFriends.where((f)=>f.id==id).firstOrNull;
      if(old!=null)_upsertFriend(old.copyWith(online:online));
    }else if(packet.type==PsPacketType.partyRequest&&packet.body.length>=4){
      pendingPartyRequesterId=ByteData.sublistView(packet.body).getUint32(0,Endian.little);
      _closeWorldPanels();socialOpen=true;
      final known=liveFriends.where((f)=>f.id==pendingPartyRequesterId).firstOrNull;
      messages.insert(0,'[Party] Invitación de '+(known?.name??('#'+pendingPartyRequesterId.toString()))+'.');
    }else if(packet.type==PsPacketType.partyResponse&&packet.body.length>=5){
      final accepted=packet.body[0]!=0;
      final id=ByteData.sublistView(packet.body).getUint32(1,Endian.little);
      if(!accepted){
        outgoingPartyInviteId=null;
        messages.insert(0,'[Party] '+(liveFriends.where((f)=>f.id==id).firstOrNull?.name??('#'+id.toString()))+' rechazó la invitación.');
      }
    }else if(packet.type==PsPacketType.partyList&&packet.body.length>=2){
      try{
        final party=PsPartyList.parse(packet);
        livePartyMembers=party.members.toList();
        if(partyLeaderId==null){
          if(outgoingPartyInviteId!=null)partyLeaderId=liveCharacter?.id;
          else if(party.leaderIndex<party.members.length)partyLeaderId=party.members[party.leaderIndex].id;
        }
        outgoingPartyInviteId=null;
        messages.insert(0,'[Party] Grupo sincronizado · '+party.members.length.toString()+' miembros remotos.');
      }catch(e){messages.insert(0,'[Party] '+e.toString());}
    }else if(packet.type==PsPacketType.partyEnter){
      try{
        final member=parsePartyEnter(packet);_upsertPartyMember(member);
        messages.insert(0,'[Party] '+member.name+' entró al grupo.');
      }catch(e){messages.insert(0,'[Party] '+e.toString());}
    }else if((packet.type==PsPacketType.partyLeave||packet.type==PsPacketType.partyKick)&&packet.body.length>=4){
      final id=ByteData.sublistView(packet.body).getUint32(0,Endian.little);
      if(id==liveCharacter?.id){
        livePartyMembers=[];partyLeaderId=null;
        messages.insert(0,packet.type==PsPacketType.partyKick?'[Party] Fuiste expulsado del grupo.':'[Party] Grupo disuelto/salida confirmada.');
      }else{
        final old=livePartyMembers.where((m)=>m.id==id).firstOrNull;
        livePartyMembers=livePartyMembers.where((m)=>m.id!=id).toList();
        if(old!=null)messages.insert(0,'[Party] '+old.name+(packet.type==PsPacketType.partyKick?' fue expulsado.':' salió del grupo.'));
      }
    }else if(packet.type==PsPacketType.partyChangeLeader&&packet.body.length>=4){
      partyLeaderId=ByteData.sublistView(packet.body).getUint32(0,Endian.little);
      final leader=livePartyMembers.where((m)=>m.id==partyLeaderId).firstOrNull;
      messages.insert(0,'[Party] Nuevo líder: '+(leader?.name??(partyLeaderId==liveCharacter?.id?nameController.text:'#'+partyLeaderId.toString()))+'.');
    }else if(packet.type==PsPacketType.partyMemberHpSpMp&&packet.body.length>=16){
      try{
        final v=PsPartyVitals.parse(packet,maximum:false);
        _updatePartyMember(v.id,(m)=>m.copyWith(hp:v.hp,sp:v.sp,mp:v.mp));
      }catch(e){messages.insert(0,'[Party] '+e.toString());}
    }else if(packet.type==PsPacketType.partyMemberMaxHpSpMp&&packet.body.length>=16){
      try{
        final v=PsPartyVitals.parse(packet,maximum:true);
        _updatePartyMember(v.id,(m)=>m.copyWith(maxHp:v.hp,maxSp:v.sp,maxMp:v.mp));
      }catch(e){messages.insert(0,'[Party] '+e.toString());}
    }else if((packet.type==PsPacketType.partyCharacterSpMp||packet.type==PsPacketType.partySetMax)&&packet.body.length>=9){
      try{
        final v=PsPartySingleValue.parse(packet),maximum=packet.type==PsPacketType.partySetMax;
        _updatePartyMember(v.id,(m){
          if(maximum){
            if(v.type==0)return m.copyWith(maxHp:v.value);
            if(v.type==1)return m.copyWith(maxSp:v.value);
            return m.copyWith(maxMp:v.value);
          }
          if(v.type==0)return m.copyWith(hp:v.value);
          if(v.type==1)return m.copyWith(sp:v.value);
          return m.copyWith(mp:v.value);
        });
      }catch(e){messages.insert(0,'[Party] '+e.toString());}
    }else if(packet.type==PsPacketType.partyMemberLevel&&packet.body.length>=6){
      final d=ByteData.sublistView(packet.body),id=d.getUint32(0,Endian.little),level=d.getUint16(4,Endian.little);
      _updatePartyMember(id,(m)=>m.copyWith(level:level));
    }else if((packet.type==PsPacketType.partyAddedBuff||packet.type==PsPacketType.partyRemovedBuff)&&packet.body.length>=7){
      try{
        final change=PsPartyBuffChange.parse(packet);
        _updatePartyMember(change.id,(m){
          final next=[...m.buffs.where((b)=>!(b.skillId==change.skillId&&b.skillLevel==change.skillLevel))];
          if(packet.type==PsPacketType.partyAddedBuff)next.add(PsPartyBuff(change.skillId,change.skillLevel,-1));
          return m.copyWith(buffs:List.unmodifiable(next));
        });
      }catch(e){messages.insert(0,'[Party] '+e.toString());}
    }else if(packet.type==PsPacketType.raidInvite&&packet.body.length>=4){
      pendingRaidRequesterId=ByteData.sublistView(packet.body).getUint32(0,Endian.little);
      _closeWorldPanels();socialOpen=true;
      messages.insert(0,'[Raid] Invitación de #'+pendingRaidRequesterId.toString()+'.');
    }else if(packet.type==PsPacketType.raidList&&packet.body.length>=8){
      try{
        liveRaid=PsRaidState.parse(packet);pendingRaidRequesterId=null;livePartyMembers=[];partyLeaderId=null;
        messages.insert(0,'[Raid] Sincronizada · '+liveRaid!.members.length.toString()+'/30 miembros.');
      }catch(e){messages.insert(0,'[Raid] '+e.toString());}
    }else if(packet.type==PsPacketType.raidEnter){
      try{
        final row=parseRaidEnter(packet),raid=liveRaid;
        if(raid!=null){
          final members=[...raid.members.where((m)=>m.member.id!=row.member.id),row]..sort((a,b)=>a.index.compareTo(b.index));
          liveRaid=PsRaidState(leaderIndex:raid.leaderIndex,subLeaderIndex:raid.subLeaderIndex,dropType:raid.dropType,autoJoin:raid.autoJoin,members:List.unmodifiable(members));
        }
        messages.insert(0,'[Raid] '+row.member.name+' entró.');
      }catch(e){messages.insert(0,'[Raid] '+e.toString());}
    }else if((packet.type==PsPacketType.raidLeave||packet.type==PsPacketType.raidKick)&&packet.body.length>=4){
      final id=ByteData.sublistView(packet.body).getUint32(0,Endian.little),raid=liveRaid;
      if(id==liveCharacter?.id){liveRaid=null;messages.insert(0,'[Raid] Has salido del raid.');}
      else if(raid!=null){
        final members=raid.members.where((m)=>m.member.id!=id).toList();
        liveRaid=PsRaidState(leaderIndex:raid.leaderIndex,subLeaderIndex:raid.subLeaderIndex,dropType:raid.dropType,autoJoin:raid.autoJoin,members:List.unmodifiable(members));
      }
    }else if(packet.type==PsPacketType.raidDismantle){
      liveRaid=null;messages.insert(0,'[Raid] Raid disuelto.');
    }else if(packet.type==PsPacketType.raidChangeLoot&&packet.body.length>=4){
      final raid=liveRaid;if(raid!=null){
        liveRaid=PsRaidState(leaderIndex:raid.leaderIndex,subLeaderIndex:raid.subLeaderIndex,dropType:ByteData.sublistView(packet.body).getInt32(0,Endian.little),autoJoin:raid.autoJoin,members:raid.members);
      }
    }else if(packet.type==PsPacketType.raidChangeAutoInvite&&packet.body.isNotEmpty){
      final raid=liveRaid;if(raid!=null){
        liveRaid=PsRaidState(leaderIndex:raid.leaderIndex,subLeaderIndex:raid.subLeaderIndex,dropType:raid.dropType,autoJoin:packet.body[0]!=0,members:raid.members);
      }
    }else if((packet.type==PsPacketType.raidChangeLeader||packet.type==PsPacketType.raidChangeSubLeader)&&packet.body.length>=4){
      final raid=liveRaid,id=ByteData.sublistView(packet.body).getUint32(0,Endian.little);
      if(raid!=null){
        final row=raid.members.where((m)=>m.member.id==id).firstOrNull;
        if(row!=null){
          liveRaid=PsRaidState(
            leaderIndex:packet.type==PsPacketType.raidChangeLeader?row.index:raid.leaderIndex,
            subLeaderIndex:packet.type==PsPacketType.raidChangeSubLeader?row.index:raid.subLeaderIndex,
            dropType:raid.dropType,autoJoin:raid.autoJoin,members:raid.members,
          );
        }
      }
    }else if(packet.type==PsPacketType.raidMovePlayer&&packet.body.length>=16){
      try{
        final move=PsRaidMove.parse(packet),raid=liveRaid;
        if(raid!=null){
          final members=<PsRaidMember>[];
          for(final row in raid.members){
            if(row.index==move.sourceIndex)members.add(row.copyWith(index:move.destinationIndex));
            else if(row.index==move.destinationIndex)members.add(row.copyWith(index:move.sourceIndex));
            else members.add(row);
          }
          members.sort((a,b)=>a.index.compareTo(b.index));
          liveRaid=PsRaidState(leaderIndex:move.leaderIndex,subLeaderIndex:move.subLeaderIndex,dropType:raid.dropType,autoJoin:raid.autoJoin,members:List.unmodifiable(members));
        }
      }catch(e){messages.insert(0,'[Raid] '+e.toString());}
    }else if((packet.type==PsPacketType.raidCharacterSpMp||packet.type==PsPacketType.raidSetMax)&&packet.body.length>=9){
      final d=ByteData.sublistView(packet.body),id=d.getUint32(0,Endian.little),type=packet.body[4],value=d.getInt32(5,Endian.little),maximum=packet.type==PsPacketType.raidSetMax;
      _updateRaidMember(id,(m){
        if(maximum){if(type==0)return m.copyWith(maxHp:value);if(type==1)return m.copyWith(maxSp:value);return m.copyWith(maxMp:value);}
        if(type==0)return m.copyWith(hp:value);if(type==1)return m.copyWith(sp:value);return m.copyWith(mp:value);
      });
    }else if((packet.type==PsPacketType.raidAddedBuff||packet.type==PsPacketType.raidRemovedBuff)&&packet.body.length>=7){
      final d=ByteData.sublistView(packet.body),id=d.getUint32(0,Endian.little),skillId=d.getUint16(4,Endian.little),level=packet.body[6];
      _updateRaidMember(id,(m){
        final buffs=[...m.buffs.where((b)=>!(b.skillId==skillId&&b.skillLevel==level))];
        if(packet.type==PsPacketType.raidAddedBuff)buffs.add(PsPartyBuff(skillId,level,-1));
        return m.copyWith(buffs:List.unmodifiable(buffs));
      });    }else if([
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
    }else if(packet.type==PsPacketType.characterDeath&&packet.body.length>=9){
      try{
        final death=PsCharacterDeath.parse(packet);
        if(death.characterId==liveCharacter?.id){
          dead=true;rebirthPending=false;lastRebirth=null;
          scene.clearMovement();
          targetMobGlobalId=targetMobTypeId=targetMobHp=targetMobMaxHp=null;
          _closeWorldPanels();questOpen=false;
          final hp=liveHitpoints;
          if(hp!=null)liveHitpoints=PsHitpoints(0,hp.mp,hp.sp);
          unawaited(scene.networkPlayerDeath());
          messages.insert(0,'[Muerte] Has muerto · killer '+death.killerId.toString()+'.');
        }else if(remotePlayerEntries.containsKey(death.characterId)){
          if(targetPlayerId==death.characterId)targetPlayerHp=0;
          unawaited(scene.networkRemotePlayerDeath(death.characterId));
        }
      }catch(e){messages.insert(0,'[Muerte] '+e.toString());}
    }else if(packet.type==PsPacketType.characterLeaveDead&&packet.body.length>=4){
      final id=ByteData.sublistView(packet.body).getUint32(0,Endian.little);
      if(id==liveCharacter?.id){
        rebirthPending=true;
        messages.insert(0,'[Renacer] World confirmó salida del estado muerto.');
      }
    }else if(packet.type==PsPacketType.deadRebirth&&packet.body.length>=21){
      try{
        final info=PsDeadRebirth.parse(packet);
        if(info.characterId==liveCharacter?.id){
          lastRebirth=info;dead=false;rebirthPending=false;
          unawaited(scene.networkPlayerRebirth(info.x,info.y,info.z));
          messages.insert(0,'[Renacer] Posición '+info.x.toStringAsFixed(1)+', '+info.z.toStringAsFixed(1)+' · penalización '+info.expLoss.toString()+'.');
        }else if(remotePlayerEntries.containsKey(info.characterId)){
          final old=remotePlayerEntries[info.characterId]!;
          final entered=PsEnteredMap(info.characterId,old.isAdmin,old.angle,info.x,info.y,info.z,old.guildId,old.vehicleId);
          remotePlayerEntries[info.characterId]=entered;_snapshotUpsertPlayer(entered);
          unawaited(scene.networkRemotePlayerRebirth(info.characterId,info.x,info.y,info.z,old.angle));
        }
      }catch(e){messages.insert(0,'[Renacer] '+e.toString());}
    }else if(packet.type==PsPacketType.targetMobHpUpdate&&packet.body.length>=10){
      final hp=PsTargetMobHp.parse(packet);
      targetMobGlobalId=hp.targetId;targetMobHp=hp.currentHp;targetAttackSpeed=hp.attackSpeed;targetMoveSpeed=hp.moveSpeed;
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
    }else if(<int>{PsPacketType.useMobTargetSkill,PsPacketType.useMobRangeSkill}.contains(packet.type)&&packet.body.length>=19){
      final hit=PsSkillHit.parse(packet);
      if(targetCasting?.casterId==hit.attackerId)targetCasting=null;
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
    }else if(packet.type==PsPacketType.mobRangeSkillUse&&packet.body.length>=19){
      try{
        final hit=PsSkillHit.parse(PsPacket(PsPacketType.useMobRangeSkill,packet.body));
        if(targetCasting?.casterId==hit.attackerId)targetCasting=null;
        if(hit.targetId==liveCharacter?.id&&hit.success){
          final hp=liveHitpoints;
          if(hp!=null)liveHitpoints=PsHitpoints(
            math.max(0,hp.hp-hit.hpDamage),math.max(0,hp.mp-hit.mpDamage),math.max(0,hp.sp-hit.spDamage),
          );
          if(hit.hpDamage>0)unawaited(scene.networkPlayerHit(hit.hpDamage));
        }
        messages.insert(0,'[Combate] Skill de área '+hit.skillId.toString()+' · daño '+hit.hpDamage.toString()+'.');
      }catch(e){messages.insert(0,'[Combate] Range mob: '+e.toString());}
    }else if(packet.type==PsPacketType.mapWeather&&packet.body.length>=3){
      try{
        liveWeather=PsMapWeather.parse(packet);
        messages.insert(0,'[Clima] '+(liveWeather!.rain?'Lluvia':liveWeather!.snow?'Nieve':'Despejado')+' · intensidad '+liveWeather!.power.toString()+'.');
      }catch(e){messages.insert(0,'[Clima] '+e.toString());}
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
    }else if(packet.type==PsPacketType.sendEquipment&&packet.body.length>=13){
      try{
        final change=PsEquipmentChange.parse(packet);
        if(change.characterId==liveCharacter?.id){
          unawaited(_applyEquipmentVisual(change));
          final label=change.type==0||change.typeId==0
            ?'slot '+change.slot.toString()+' vacío'
            :catalog!.itemName(change.type,change.typeId,uiLocale);
          messages.insert(0,'[Equipo] World confirmó '+label+'.');
        }
      }catch(e){messages.insert(0,'[Equipo] SEND_EQUIPMENT: '+e.toString());}
    }else if(packet.type==PsPacketType.useItem&&packet.body.length>=9){
      try{
        final used=PsUsedItem.parse(packet);
        if(used.characterId==liveCharacter?.id){
          final index=liveInventory.indexWhere((x)=>x.bag==used.bag&&x.slot==used.slot);
          if(index>=0){
            final old=liveInventory[index];
            if(used.count<=0){
              liveInventory.removeAt(index);
            }else{
              liveInventory[index]=PsInventoryItem(
                bag:old.bag,slot:old.slot,type:old.type,typeId:old.typeId,
                quality:old.quality,count:used.count,gems:old.gems,
                craftName:old.craftName,dyed:old.dyed,
              );
            }
          }
          messages.insert(0,'[Objeto] '+catalog!.itemName(used.type,used.typeId,uiLocale)+' usado · restantes '+used.count.toString()+'.');
        }
      }catch(e){messages.insert(0,'[Objeto] USE_ITEM: '+e.toString());}
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
    }else if(packet.type==PsPacketType.guildWarehouseItemList){
      try{
        if(!guildWarehouseAvailable){liveGuildWarehouse=[];}
        guildWarehouseAvailable=true;
        for(final item in parseGuildWarehouseItems(packet)){
          liveGuildWarehouse.removeWhere((x)=>x.slot==item.slot);
          liveGuildWarehouse.add(item);
        }
        liveGuildWarehouse.sort((a,b)=>a.slot.compareTo(b.slot));
      }catch(e){messages.insert(0,'[Guild Warehouse] '+e.toString());}
    }else if(packet.type==PsPacketType.guildWarehouseItemAdd&&packet.body.length>=104){
      try{
        final change=PsGuildWarehouseMutation.parse(packet);
        _upsertInventoryItem(change.item);
        final actor=change.characterId==liveCharacter?.id?nameController.text:'#'+change.characterId.toString();
        messages.insert(0,'[Guild Warehouse] '+actor+' guardó '+catalog!.itemName(change.item.type,change.item.typeId,uiLocale)+'.');
      }catch(e){messages.insert(0,'[Guild Warehouse] '+e.toString());}
    }else if(packet.type==PsPacketType.guildWarehouseItemRemove&&packet.body.length>=104){
      try{
        final change=PsGuildWarehouseMutation.parse(packet);
        liveGuildWarehouse.removeWhere((x)=>x.slot==change.item.slot);
        final actor=change.characterId==liveCharacter?.id?nameController.text:'#'+change.characterId.toString();
        messages.insert(0,'[Guild Warehouse] '+actor+' retiró '+catalog!.itemName(change.item.type,change.item.typeId,uiLocale)+'.');
      }catch(e){messages.insert(0,'[Guild Warehouse] '+e.toString());}
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
  Future<void> _streamWorldSectorIfNeeded(double worldX,double worldY,double worldZ) async {
    if(sectorStreaming||mapSwitching||stage!=GameStage.world)return;
    final w=scene.world,path=scene.worldPath,a=scene.character;
    if(w==null||w.size==0||path==null||a==null)return;
    if(a.root.position.x.abs()<44&&a.root.position.z.abs()<44)return;
    sectorStreaming=true;
    final mapAtStart=liveMapId;
    try{
      await scene.setWorld(path,x:worldX,z:worldZ);
      if(mapSwitching||liveMapId!=mapAtStart||scene.worldPath!=path)return;

      final snapshot=liveSnapshot,meta=metadata;
      final questNpcKeys=meta==null
        ?null
        :meta.npcs.entries.where((e)=>e.value.outQuests.isNotEmpty).map((e)=>e.key).toSet();
      if(snapshot!=null){
        await scene.spawnGameActorsFromNetwork(
          npcs:snapshot.npcs.map((p)=>RuntimeNpcSpawn(
            p.type,p.typeId,p.x,p.y,p.z,p.angle,p.globalId,
          )).toList(),
          mobs:snapshot.mobs.map((p)=>RuntimeMobSpawn(p.mobId,p.x,p.z,p.globalId)).toList(),
          npcModels:meta?.npcModels,mobModels:meta?.mobModels,
          questNpcKeys:questNpcKeys,locale:uiLocale,
        );
      }
      for(final entered in remotePlayerEntries.values.toList()){
        final shape=remotePlayerShapes[entered.characterId];
        if(shape!=null){
          await _renderRemotePlayer(entered,shape);
        }else{
          unawaited(_ensureRemotePlayer(entered));
        }
      }
      messages.insert(0,'[Streaming] Sector continuo → '+worldX.toStringAsFixed(1)+', '+worldZ.toStringAsFixed(1)+'.');
    }catch(e){
      messages.insert(0,'[Streaming] '+e.toString());
    }finally{
      sectorStreaming=false;
      final queued=List<PsPacket>.from(pendingMapActorPackets);pendingMapActorPackets.clear();
      for(final packet in queued){_handleLivePacket(packet);}
      if(mounted)setState((){});
    }
  }

  Future<void> _syncMovement() async {
    if(movementSending||stage!=GameStage.world||dead||rebirthPending)return;
    final session=liveWorld,a=scene.character;
    if(session==null||a==null)return;
    final moving=scene.walkX!=0||scene.walkZ!=0;
    final x=scene.originX+a.root.position.x;
    final z=scene.originZ-a.root.position.z;
    final y=a.root.position.y;
    final run=scene.running;
    unawaited(_checkPhysicalPortal(x,y,z));
    unawaited(_streamWorldSectorIfNeeded(x,y,z));
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

  Future<void> _rebirthTown() async {
    final session=liveWorld;
    if(session==null||!dead||rebirthPending)return;
    rebirthPending=true;
    scene.clearMovement();
    try{
      await session.rebirth();
      messages.insert(0,'[Renacer] Solicitud enviada a World.');
      if(mounted)setState((){});
    }catch(e){
      rebirthPending=false;
      messages.insert(0,'[Renacer] '+e.toString());
      if(mounted)setState((){});
    }
  }

  void _upsertFriend(PsFriend friend){
    liveFriends=[
      ...liveFriends.where((f)=>f.id!=friend.id),
      friend,
    ]..sort((a,b){
      if(a.online!=b.online)return a.online?-1:1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  }

  void _updateRaidMember(int id,PsPartyMember Function(PsPartyMember) update){
    final raid=liveRaid;if(raid==null)return;
    final next=<PsRaidMember>[];
    for(final row in raid.members){
      next.add(row.member.id==id?row.copyWith(member:update(row.member)):row);
    }
    liveRaid=PsRaidState(
      leaderIndex:raid.leaderIndex,subLeaderIndex:raid.subLeaderIndex,dropType:raid.dropType,
      autoJoin:raid.autoJoin,members:List.unmodifiable(next),
    );
  }
  void _upsertPartyMember(PsPartyMember member){
    livePartyMembers=[
      ...livePartyMembers.where((m)=>m.id!=member.id),
      member,
    ];
  }

  void _updatePartyMember(int id,PsPartyMember Function(PsPartyMember) update){
    final current=livePartyMembers.where((m)=>m.id==id).firstOrNull;
    if(current==null)return;
    _upsertPartyMember(update(current));
  }

  String _knownCharacterName(int id){
    if(id==liveCharacter?.id)return nameController.text;
    final friend=liveFriends.where((f)=>f.id==id).firstOrNull;if(friend!=null)return friend.name;
    final party=livePartyMembers.where((m)=>m.id==id).firstOrNull;if(party!=null)return party.name;
    final guild=liveGuildMembers.where((m)=>m.id==id).firstOrNull;if(guild!=null)return guild.name;
    return '#'+id.toString();
  }

  void _resetDuel({bool keepResult=false}){
    localDuelItems.clear();remoteDuelItems.clear();
    localDuelMoney=remoteDuelMoney=0;
    localDuelApproved=remoteDuelApproved=false;
    duelTradeOpen=false;duelStarted=false;duelReady=false;
    duelOpponentId=null;pendingDuelRequesterId=null;outgoingDuelTargetId=null;
    duelCenterX=duelCenterZ=0;
    if(!keepResult)duelResultText='';
  }

  PsTradeItem _duelItemFromInventory(PsInventoryItem item,int tradeSlot,int count)=>PsTradeItem(
    tradeSlot:tradeSlot,type:item.type,typeId:item.typeId,count:count,quality:item.quality,
    gems:item.gems,craftName:item.craftName,dyed:item.dyed,
  );

  PsTradeItem _duelItemFromRemote(PsDuelTradeItem item)=>PsTradeItem(
    tradeSlot:item.tradeSlot,type:item.type,typeId:item.typeId,count:item.count,quality:item.quality,
    gems:item.gems,craftName:item.craftName,dyed:item.dyed,
  );

  void _resetTrade({bool close=true}){
    localTradeItems.clear();remoteTradeItems.clear();
    localTradeMoney=remoteTradeMoney=0;
    localTradeDecided=remoteTradeDecided=localTradeConfirmed=remoteTradeConfirmed=false;
    tradePartnerId=null;outgoingTradeTargetId=null;
    if(close){tradeOpen=false;pendingTradeRequesterId=null;}
  }

  PsTradeItem _tradeItemFromInventory(PsInventoryItem item,int tradeSlot,int count)=>PsTradeItem(
    tradeSlot:tradeSlot,type:item.type,typeId:item.typeId,count:count,quality:item.quality,
    gems:item.gems,craftName:item.craftName,dyed:item.dyed,
  );

  Future<void> _requestDuel(int characterId) async {
    final session=liveWorld;
    if(session==null||characterId==liveCharacter?.id||duelStarted||duelTradeOpen)return;
    try{
      outgoingDuelTargetId=characterId;
      await session.requestDuel(characterId);
      messages.insert(0,'[Duel] Desafío enviado a '+_knownCharacterName(characterId)+'.');
    }catch(e){messages.insert(0,'[Duel] '+e.toString());}
    if(mounted)setState((){});
  }

  Future<void> _respondDuel(bool accepted) async {
    final session=liveWorld,id=pendingDuelRequesterId;
    if(session==null||id==null)return;
    try{
      await session.respondDuel(accepted);
      if(accepted){
        duelOpponentId=id;
        messages.insert(0,'[Duel] Desafío aceptado contra '+_knownCharacterName(id)+'.');
      }else{
        messages.insert(0,'[Duel] Desafío rechazado.');
        _resetDuel();
      }
      pendingDuelRequesterId=null;
    }catch(e){messages.insert(0,'[Duel] '+e.toString());}
    if(mounted)setState((){});
  }

  Future<void> _addInventoryToDuel(PsInventoryItem item) async {
    final session=liveWorld;
    if(session==null||!duelTradeOpen||duelOpponentId==null||item.bag==0)return;
    final occupied=localDuelItems.keys.toSet();
    int? tradeSlot;
    for(var i=0;i<8;i++){if(!occupied.contains(i)){tradeSlot=i;break;}}
    if(tradeSlot==null){messages.insert(0,'[Duel] No hay slots de apuesta libres.');if(mounted)setState((){});return;}
    try{
      await session.addDuelItem(item.bag,item.slot,item.count,tradeSlot);
      messages.insert(0,'[Duel] Apostando '+(catalog?.itemName(item.type,item.typeId,uiLocale)??item.key)+'…');
    }catch(e){messages.insert(0,'[Duel] '+e.toString());}
    if(mounted)setState((){});
  }

  Future<void> _removeDuelItem(int tradeSlot) async {
    final session=liveWorld;if(session==null||!duelTradeOpen)return;
    try{
      await session.removeDuelItem(tradeSlot);
      localDuelItems.remove(tradeSlot);
      localDuelApproved=remoteDuelApproved=false;
    }catch(e){messages.insert(0,'[Duel] '+e.toString());}
    if(mounted)setState((){});
  }

  Future<void> _setDuelMoney(int value) async {
    final session=liveWorld;if(session==null||!duelTradeOpen)return;
    final amount=value.clamp(0,liveGold??0).toInt();
    try{await session.addDuelMoney(amount);}
    catch(e){messages.insert(0,'[Duel] '+e.toString());}
    if(mounted)setState((){});
  }

  Future<void> _decideDuel(bool ready) async {
    final session=liveWorld;if(session==null||!duelTradeOpen)return;
    try{await session.decideDuelTrade(ready?0:1);}
    catch(e){messages.insert(0,'[Duel] '+e.toString());}
  }

  Future<void> _closeDuelTrade() async {
    final session=liveWorld;if(session==null||!duelTradeOpen)return;
    try{await session.decideDuelTrade(2);}
    catch(e){messages.insert(0,'[Duel] '+e.toString());}
  }

  Future<void> _admitDuelDefeat() async {
    final session=liveWorld;if(session==null||!duelStarted)return;
    try{await session.admitDuelDefeat();}
    catch(e){messages.insert(0,'[Duel] '+e.toString());}
  }

  Future<void> _requestTrade(int characterId) async {
    final session=liveWorld;
    if(session==null||characterId==liveCharacter?.id||tradeOpen)return;
    try{
      outgoingTradeTargetId=characterId;
      await session.requestTrade(characterId);
      messages.insert(0,'[Trade] Solicitud enviada a '+_knownCharacterName(characterId)+'.');
    }catch(e){messages.insert(0,'[Trade] '+e.toString());}
    if(mounted)setState((){});
  }

  Future<void> _respondTrade(bool accepted) async {
    final session=liveWorld,id=pendingTradeRequesterId;
    if(session==null||id==null)return;
    try{
      await session.respondTrade(declined:!accepted);
      if(accepted){
        tradePartnerId=id;tradeOpen=true;inventoryOpen=true;
        messages.insert(0,'[Trade] Aceptaste intercambio con '+_knownCharacterName(id)+'.');
      }else{
        tradeOpen=false;
        messages.insert(0,'[Trade] Intercambio rechazado.');
      }
      pendingTradeRequesterId=null;
    }catch(e){messages.insert(0,'[Trade] '+e.toString());}
    if(mounted)setState((){});
  }

  Future<void> _addInventoryToTrade(PsInventoryItem item) async {
    final session=liveWorld;
    if(session==null||!tradeOpen||tradePartnerId==null||item.bag==0)return;
    final occupied=localTradeItems.keys.toSet();
    int? tradeSlot;for(var i=0;i<8;i++){if(!occupied.contains(i)){tradeSlot=i;break;}}
    if(tradeSlot==null){messages.insert(0,'[Trade] No hay slots libres.');if(mounted)setState((){});return;}
    try{
      await session.addTradeItem(item.bag,item.slot,item.count,tradeSlot);
      messages.insert(0,'[Trade] Ofertando '+(catalog?.itemName(item.type,item.typeId,uiLocale)??item.key)+'…');
    }catch(e){messages.insert(0,'[Trade] '+e.toString());}
    if(mounted)setState((){});
  }

  Future<void> _removeTradeItem(int tradeSlot) async {
    final session=liveWorld;if(session==null||!tradeOpen)return;
    try{
      await session.removeTradeItem(tradeSlot);
      localTradeItems.remove(tradeSlot);
      localTradeDecided=remoteTradeDecided=localTradeConfirmed=remoteTradeConfirmed=false;
    }catch(e){messages.insert(0,'[Trade] '+e.toString());}
    if(mounted)setState((){});
  }

  Future<void> _setTradeMoney(int value) async {
    final session=liveWorld;if(session==null||!tradeOpen)return;
    final amount=value.clamp(0,liveGold??0).toInt();
    try{await session.addTradeMoney(amount);}
    catch(e){messages.insert(0,'[Trade] '+e.toString());}
    if(mounted)setState((){});
  }

  Future<void> _decideTrade(bool decided) async {
    final session=liveWorld;if(session==null||!tradeOpen)return;
    try{await session.decideTrade(decided);}
    catch(e){messages.insert(0,'[Trade] '+e.toString());}
  }

  Future<void> _finishTrade(int result) async {
    final session=liveWorld;if(session==null||!tradeOpen)return;
    try{await session.finishTrade(result);}
    catch(e){messages.insert(0,'[Trade] '+e.toString());}
  }
  void _upsertGuildSummary(PsGuildSummary guild){
    guildDirectory=[
      ...guildDirectory.where((g)=>g.id!=guild.id),
      guild,
    ]..sort((a,b){
      final rank=a.rank.compareTo(b.rank);
      if(rank!=0)return rank;
      return b.points.compareTo(a.points);
    });
  }

  void _upsertGuildMember(PsGuildMember member){
    liveGuildMembers=[
      ...liveGuildMembers.where((m)=>m.id!=member.id),
      member,
    ]..sort((a,b){
      if(a.online!=b.online)return a.online?-1:1;
      final rank=a.rank.compareTo(b.rank);
      if(rank!=0)return rank;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    if(member.id==liveCharacter?.id)liveGuildRank=member.rank;
  }

  void _clearGuildState(){
    liveGuildId=0;liveGuildRank=0;liveGuildName='';
    liveGuildMembers=[];guildApplicants=[];pendingGuildCreateInvite=null;
  }

  bool _handleGuildPacket(PsPacket packet,{bool notify=true}){
    try{
      if(packet.type==PsPacketType.guildListLoadingStart){
        guildDirectory=[];guildListLoading=true;return true;
      }
      if(packet.type==PsPacketType.guildList){
        for(final g in parseGuildList(packet))_upsertGuildSummary(g);
        return true;
      }
      if(packet.type==PsPacketType.guildListLoadingEnd){
        guildListLoading=false;return true;
      }
      if(packet.type==PsPacketType.guildListAdd&&packet.body.length>=185){
        _upsertGuildSummary(PsGuildSummary.parseUnit(packet.body,0));return true;
      }
      if(packet.type==PsPacketType.guildListRemove&&packet.body.length>=4){
        final id=ByteData.sublistView(packet.body).getUint32(0,Endian.little);
        guildDirectory=guildDirectory.where((g)=>g.id!=id).toList();
        return true;
      }
      if(packet.type==PsPacketType.guildUserListOnline||packet.type==PsPacketType.guildUserListNotOnline){
        final online=packet.type==PsPacketType.guildUserListOnline;
        for(final m in parseGuildMembers(packet,online:online))_upsertGuildMember(m);
        return true;
      }
      if(packet.type==PsPacketType.guildUserListAdd&&packet.body.length>=30){
        _upsertGuildMember(parseGuildMemberAdd(packet));return true;
      }
      if(packet.type==PsPacketType.guildJoinListAdd&&packet.body.length>=28){
        final a=PsGuildJoinApplicant.parseUnit(packet.body,0);
        guildApplicants=[...guildApplicants.where((x)=>x.id!=a.id),a];
        if(notify)messages.insert(0,'[Guild] Solicitud de '+a.name+'.');
        return true;
      }
      if(packet.type==PsPacketType.guildJoinListRemove&&packet.body.length>=4){
        final id=ByteData.sublistView(packet.body).getUint32(0,Endian.little);
        guildApplicants=guildApplicants.where((a)=>a.id!=id).toList();
        return true;
      }
      if(packet.type==PsPacketType.guildJoinRequest&&packet.body.isNotEmpty){
        if(notify)messages.insert(0,packet.body[0]!=0?'[Guild] Solicitud de ingreso enviada.':'[Guild] Solicitud de ingreso rechazada.');
        return true;
      }
      if(packet.type==PsPacketType.guildJoinResultUser&&packet.body.length>=31){
        final result=PsGuildJoinResult.parse(packet);
        if(result.ok){
          liveGuildId=result.guildId;liveGuildRank=result.rank;liveGuildName=result.name;
          guildApplicants=[];
          if(notify)messages.insert(0,'[Guild] Ingreso confirmado en '+result.name+'.');
        }else if(notify){
          messages.insert(0,'[Guild] Ingreso rechazado.');
        }
        return true;
      }
      if(packet.type==PsPacketType.guildUserState&&packet.body.length>=5){
        final d=ByteData.sublistView(packet.body),state=packet.body[0],id=d.getUint32(1,Endian.little);
        if(state==101){
          _clearGuildState();
          if(notify)messages.insert(0,'[Guild] Guild disuelta.');
        }else if(state==102||state==103){
          if(id==liveCharacter?.id)_clearGuildState();
          else liveGuildMembers=liveGuildMembers.where((m)=>m.id!=id).toList();
        }else if(state==104||state==105){
          final m=liveGuildMembers.where((x)=>x.id==id).firstOrNull;
          if(m!=null)_upsertGuildMember(m.copyWith(online:state==104));
        }else if(state>=202&&state<=209){
          final rank=state-200,m=liveGuildMembers.where((x)=>x.id==id).firstOrNull;
          if(m!=null)_upsertGuildMember(m.copyWith(rank:rank));
          if(id==liveCharacter?.id)liveGuildRank=rank;
        }
        return true;
      }
      if(packet.type==PsPacketType.guildLeave&&packet.body.isNotEmpty){
        final ok=packet.body[0]!=0;
        if(ok)_clearGuildState();
        if(notify)messages.insert(0,ok?'[Guild] Saliste del guild.':'[Guild] No fue posible salir.');
        return true;
      }
      if(packet.type==PsPacketType.guildKick&&packet.body.length>=5){
        final ok=packet.body[0]!=0,id=ByteData.sublistView(packet.body).getUint32(1,Endian.little);
        if(ok){
          if(id==liveCharacter?.id)_clearGuildState();
          else liveGuildMembers=liveGuildMembers.where((m)=>m.id!=id).toList();
        }
        return true;
      }
      if(packet.type==PsPacketType.guildCreate){
        final result=PsGuildCreateResult.parse(packet);
        if(result.success){
          liveGuildId=result.guildId;liveGuildRank=result.rank;liveGuildName=result.name;
          if(notify)messages.insert(0,'[Guild] '+result.name+' creado.');
        }else if(notify){
          messages.insert(0,'[Guild] Creación rechazada · código '+result.reason.toString()+'.');
        }
        return true;
      }
      if(packet.type==PsPacketType.guildCreateAgree&&packet.body.length>=94){
        pendingGuildCreateInvite=PsGuildCreateInvite.parse(packet);
        _closeWorldPanels();guildOpen=true;
        if(notify)messages.insert(0,'[Guild] Invitación para crear '+pendingGuildCreateInvite!.name+'.');
        return true;
      }
    }catch(e){
      if(notify)messages.insert(0,'[Guild] '+e.toString());
      return true;
    }
    return false;
  }

  Future<void> _requestGuildJoin(PsGuildSummary guild) async {
    final session=liveWorld;if(session==null||liveGuildId!=0)return;
    try{
      await session.requestGuildJoin(guild.id);
      messages.insert(0,'[Guild] Solicitud → '+guild.name+'.');
    }catch(e){messages.insert(0,'[Guild] '+e.toString());}
    if(mounted)setState((){});
  }

  Future<void> _respondGuildApplicant(PsGuildJoinApplicant applicant,bool accepted) async {
    final session=liveWorld;if(session==null||liveGuildId==0||liveGuildRank>3)return;
    try{
      await session.respondGuildJoin(applicant.id,accepted:accepted);
      guildApplicants=guildApplicants.where((a)=>a.id!=applicant.id).toList();
      messages.insert(0,'[Guild] '+applicant.name+(accepted?' aceptado.':' rechazado.'));
    }catch(e){messages.insert(0,'[Guild] '+e.toString());}
    if(mounted)setState((){});
  }

  Future<void> _leaveGuild() async {
    final session=liveWorld;if(session==null||liveGuildId==0)return;
    try{await session.leaveGuild();messages.insert(0,'[Guild] Solicitud de salida enviada.');}
    catch(e){messages.insert(0,'[Guild] '+e.toString());}
    if(mounted)setState((){});
  }

  Future<void> _kickGuildMember(PsGuildMember member) async {
    final session=liveWorld;if(session==null||liveGuildRank>3)return;
    try{await session.kickGuildMember(member.id);messages.insert(0,'[Guild] Expulsando a '+member.name+'…');}
    catch(e){messages.insert(0,'[Guild] '+e.toString());}
    if(mounted)setState((){});
  }

  Future<void> _changeGuildMemberRank(PsGuildMember member,bool demote) async {
    final session=liveWorld;if(session==null||liveGuildRank>3)return;
    try{
      await session.changeGuildRank(member.id,demote:demote);
      messages.insert(0,'[Guild] '+(demote?'Descenso':'Ascenso')+' solicitado para '+member.name+'.');
    }catch(e){messages.insert(0,'[Guild] '+e.toString());}
    if(mounted)setState((){});
  }

  Future<void> _createGuild(String name,String message) async {
    final session=liveWorld;if(session==null||liveGuildId!=0)return;
    try{await session.createGuild(name,message);messages.insert(0,'[Guild] Creación solicitada: '+name+'.');}
    catch(e){messages.insert(0,'[Guild] '+e.toString());}
    if(mounted)setState((){});
  }

  Future<void> _respondGuildCreate(bool accepted) async {
    final session=liveWorld,invite=pendingGuildCreateInvite;
    if(session==null||invite==null)return;
    try{
      await session.respondGuildCreate(accepted);
      messages.insert(0,'[Guild] Creación '+(accepted?'aceptada.':'rechazada.'));
      pendingGuildCreateInvite=null;
    }catch(e){messages.insert(0,'[Guild] '+e.toString());}
    if(mounted)setState((){});
  }

  Future<void> _dismantleGuild() async {
    final session=liveWorld;if(session==null||liveGuildId==0||liveGuildRank!=1)return;
    try{await session.dismantleGuild();messages.insert(0,'[Guild] Solicitud de disolución enviada.');}
    catch(e){messages.insert(0,'[Guild] '+e.toString());}
    if(mounted)setState((){});
  }

  Future<void> _requestFriend(String name) async {
    final session=liveWorld;if(session==null)return;
    try{
      await session.requestFriend(name);
      messages.insert(0,'[Friends] Solicitud enviada a '+name.trim()+'.');
    }catch(e){messages.insert(0,'[Friends] '+e.toString());}
    if(mounted)setState((){});
  }

  Future<void> _respondFriend(bool accepted) async {
    final session=liveWorld,name=pendingFriendRequestName;
    if(session==null||name==null)return;
    try{
      await session.respondFriend(accepted);
      messages.insert(0,'[Friends] '+(accepted?'Aceptaste a ':'Rechazaste a ')+name+'.');
      pendingFriendRequestName=null;
    }catch(e){messages.insert(0,'[Friends] '+e.toString());}
    if(mounted)setState((){});
  }

  Future<void> _deleteFriend(PsFriend friend) async {
    final session=liveWorld;if(session==null)return;
    try{
      await session.deleteFriend(friend.id);
      messages.insert(0,'[Friends] Eliminando '+friend.name+'…');
    }catch(e){messages.insert(0,'[Friends] '+e.toString());}
    if(mounted)setState((){});
  }

  Future<void> _inviteFriendToParty(PsFriend friend) async {
    final session=liveWorld;if(session==null||!friend.online)return;
    try{
      outgoingPartyInviteId=friend.id;
      if(livePartyMembers.isEmpty)partyLeaderId=liveCharacter?.id;
      await session.requestParty(friend.id);
      messages.insert(0,'[Party] Invitación enviada a '+friend.name+'.');
    }catch(e){messages.insert(0,'[Party] '+e.toString());}
    if(mounted)setState((){});
  }

  Future<void> _respondParty(bool accepted) async {
    final session=liveWorld,id=pendingPartyRequesterId;
    if(session==null||id==null)return;
    try{
      if(accepted)partyLeaderId=id;
      await session.respondParty(id,declined:!accepted);
      messages.insert(0,'[Party] Invitación '+(accepted?'aceptada.':'rechazada.'));
      pendingPartyRequesterId=null;
    }catch(e){messages.insert(0,'[Party] '+e.toString());}
    if(mounted)setState((){});
  }

  Future<void> _createRaid() async {
    final session=liveWorld;if(session==null)return;
    try{await session.createRaid(autoJoin:true,dropType:1);messages.insert(0,'[Raid] Creación solicitada.');}
    catch(e){messages.insert(0,'[Raid] '+e.toString());}
    if(mounted)setState((){});
  }

  Future<void> _joinRaidByName(String name) async {
    final value=name.trim();if(value.isEmpty)return;
    try{await liveWorld?.joinRaid(value);messages.insert(0,'[Raid] Solicitud AutoJoin → '+value+'.');}
    catch(e){messages.insert(0,'[Raid] '+e.toString());}
    if(mounted)setState((){});
  }

  Future<void> _kickRaidMember(PsRaidMember row) async {
    final raid=liveRaid;if(raid==null||raid.leader?.member.id!=liveCharacter?.id)return;
    try{await liveWorld?.kickRaidMember(row.member.id);}
    catch(e){messages.insert(0,'[Raid] '+e.toString());}
  }

  Future<void> _changeRaidLeader(PsRaidMember row) async {
    final raid=liveRaid;if(raid==null||raid.leader?.member.id!=liveCharacter?.id)return;
    try{await liveWorld?.changeRaidLeader(row.member.id);}
    catch(e){messages.insert(0,'[Raid] '+e.toString());}
  }

  Future<void> _changeRaidSubLeader(PsRaidMember row) async {
    final raid=liveRaid;if(raid==null||raid.leader?.member.id!=liveCharacter?.id)return;
    try{await liveWorld?.changeRaidSubLeader(row.member.id);}
    catch(e){messages.insert(0,'[Raid] '+e.toString());}
  }

  Future<void> _moveRaidMemberToGroup(PsRaidMember row,int group) async {
    final raid=liveRaid,self=liveCharacter?.id;
    if(raid==null||self==null||group<0||group>4)return;
    final allowed=raid.leader?.member.id==self||raid.subLeader?.member.id==self;
    if(!allowed)return;
    final occupied={for(final r in raid.members)r.index};
    int destination=group*6;
    for(var i=group*6;i<group*6+6;i++){if(!occupied.contains(i)){destination=i;break;}}
    if(destination==row.index)return;
    try{await liveWorld?.moveRaidMember(row.index,destination);}
    catch(e){messages.insert(0,'[Raid] '+e.toString());}
  }
  Future<void> _leaveRaid() async {
    try{await liveWorld?.leaveRaid();}catch(e){messages.insert(0,'[Raid] '+e.toString());}
  }

  Future<void> _dismantleRaid() async {
    try{await liveWorld?.dismantleRaid();}catch(e){messages.insert(0,'[Raid] '+e.toString());}
  }

  Future<void> _respondRaid(bool accepted) async {
    final id=pendingRaidRequesterId;if(id==null)return;
    try{await liveWorld?.respondRaid(id,declined:!accepted);if(!accepted)pendingRaidRequesterId=null;}
    catch(e){messages.insert(0,'[Raid] '+e.toString());}
    if(mounted)setState((){});
  }

  Future<void> _inviteRaidCharacter(int id) async {
    try{await liveWorld?.inviteRaid(id);messages.insert(0,'[Raid] Invitación enviada a #'+id.toString()+'.');}
    catch(e){messages.insert(0,'[Raid] '+e.toString());}
    if(mounted)setState((){});
  }

  Future<void> _changeRaidLoot(int value) async {
    try{await liveWorld?.changeRaidLoot(value);}catch(e){messages.insert(0,'[Raid] '+e.toString());}
  }

  Future<void> _toggleRaidAutoJoin() async {
    final raid=liveRaid;if(raid==null)return;
    try{await liveWorld?.changeRaidAutoJoin(!raid.autoJoin);}catch(e){messages.insert(0,'[Raid] '+e.toString());}
  }
  Future<void> _leaveParty() async {
    final session=liveWorld;if(session==null)return;
    try{
      await session.leaveParty();
      livePartyMembers=[];partyLeaderId=null;
      messages.insert(0,'[Party] Has salido del grupo.');
    }catch(e){messages.insert(0,'[Party] '+e.toString());}
    if(mounted)setState((){});
  }

  Future<void> _kickPartyMember(PsPartyMember member) async {
    final session=liveWorld;if(session==null||partyLeaderId!=liveCharacter?.id)return;
    try{
      await session.kickPartyMember(member.id);
      messages.insert(0,'[Party] Expulsando a '+member.name+'…');
    }catch(e){messages.insert(0,'[Party] '+e.toString());}
    if(mounted)setState((){});
  }

  Future<void> _promotePartyMember(PsPartyMember member) async {
    final session=liveWorld;if(session==null||partyLeaderId!=liveCharacter?.id)return;
    try{
      await session.changePartyLeader(member.id);
      messages.insert(0,'[Party] Cambio de líder solicitado → '+member.name+'.');
    }catch(e){messages.insert(0,'[Party] '+e.toString());}
    if(mounted)setState((){});
  }

  Future<void> _toggleVehicle() async {
    final session=liveWorld;
    if(session==null||stage!=GameStage.world||dead||rebirthPending)return;
    if(vehiclePassengerId!=null){
      try{await session.leaveVehiclePassenger();}
      catch(e){messages.insert(0,'[Montura] '+e.toString());}
      return;
    }
    final mount=_equippedItem(13);
    if(!vehicleMounted&&mount==null){
      messages.insert(0,'[Montura] Equipa una montura en el slot correspondiente.');
      if(mounted)setState((){});
      return;
    }
    try{
      await session.toggleVehicle();
      messages.insert(0,vehicleMounted?'[Montura] Bajando…':'[Montura] Solicitud de invocación enviada.');
    }catch(e){messages.insert(0,'[Montura] '+e.toString());}
    if(mounted)setState((){});
  }

  Future<void> _respondVehicleRequest(bool accepted) async {
    if(pendingVehicleRequesterId==null||liveWorld==null)return;
    try{
      await liveWorld!.respondVehiclePassenger(rejected:!accepted);
      messages.insert(0,accepted?'[Montura] Invitación aceptada.':'[Montura] Invitación rechazada.');
      pendingVehicleRequesterId=null;
    }catch(e){messages.insert(0,'[Montura] '+e.toString());}
    if(mounted)setState((){});
  }

  Future<void> _pickMapItem(PsMapItem item) async {
    final session=liveWorld;if(session==null||stage!=GameStage.world||dead||rebirthPending)return;
    final a=scene.character;
    if(a!=null){
      final worldX=scene.originX+a.root.position.x,worldZ=scene.originZ-a.root.position.z;
      final dx=worldX-item.x,dz=worldZ-item.z;
      if(dx*dx+dz*dz>49){
        messages.insert(0,'[Drop] Acércate al objeto antes de recogerlo.');
        if(mounted)setState((){});
        return;
      }
    }
    try{
      await session.pickUpMapItem(item.id);
      messages.insert(0,'[Drop] Recogiendo '+(catalog?.itemName(item.type,item.typeId,uiLocale)??item.id.toString())+'…');
    }catch(e){messages.insert(0,'[Drop] '+e.toString());}
    if(mounted)setState((){});
  }

  Future<void> _sendChat(String value) async {
    final session=liveWorld;if(session==null||stage!=GameStage.world)return;
    try{await session.sendNormalChat(value);}
    catch(e){messages.insert(0,'[Chat] '+e.toString());if(mounted)setState((){});}
  }
  Future<void> _selectTargetAt(Offset position) async {
    if(stage!=GameStage.world||dead||rebirthPending)return;
    focus.requestFocus();
    final picked=scene.pickNetworkCombatTarget(position.dx,position.dy,1024,742);
    if(picked==null)return;
    if(picked.player){
      final id=picked.id;
      targetMobGlobalId=targetMobTypeId=targetMobHp=targetMobMaxHp=null;
      targetAttackSpeed=targetMoveSpeed=null;targetBuffs=<PsTargetBuff>[];targetCasting=null;
      targetPlayerId=id;
      targetPlayerName=remotePlayerShapes[id]?.name??_knownCharacterName(id);
      try{
        final selected=await liveWorld?.selectCharacterTarget(id);
        if(selected!=null){
          targetPlayerId=selected.targetId;targetPlayerMaxHp=selected.maxHp;targetPlayerHp=selected.currentHp;
        }
        final refreshed=await liveWorld?.refreshCharacterTargetHp(id);
        if(refreshed!=null){
          targetPlayerHp=refreshed.currentHp;targetPlayerMaxHp=refreshed.maxHp;
          targetAttackSpeed=refreshed.attackSpeed;targetMoveSpeed=refreshed.moveSpeed;
        }
        final targetBuffState=await liveWorld?.requestCharacterTargetBuffs(id);
        if(targetBuffState!=null)targetBuffs=targetBuffState.buffs.toList();
        final label=targetPlayerName?.isNotEmpty==true?targetPlayerName!:('#'+id.toString());
        messages.insert(0,'[PvP Target] '+label);
      }catch(e){messages.insert(0,'[PvP Target] '+e.toString());}
    }else{
      final id=picked.id,logical=liveSnapshot?.mobs.where((m)=>m.globalId==picked.id).firstOrNull;
      targetPlayerId=targetPlayerHp=targetPlayerMaxHp=null;targetPlayerName=null;
      targetAttackSpeed=targetMoveSpeed=null;targetBuffs=<PsTargetBuff>[];targetCasting=null;
      targetMobGlobalId=id;
      if(logical!=null){
        targetMobTypeId=logical.mobId;
        targetMobMaxHp=metadata?.mobs[logical.mobId]?.hp??targetMobMaxHp;
      }
      try{
        final hp=await liveWorld?.selectMobTarget(id);
        if(hp!=null){
          targetMobHp=hp.currentHp;targetMobGlobalId=hp.targetId;
          targetAttackSpeed=hp.attackSpeed;targetMoveSpeed=hp.moveSpeed;
        }
        final state=await liveWorld?.requestMobTargetState(id);
        if(state!=null){
          targetMobHp=state.currentHp;targetAttackSpeed=state.attackSpeed;targetMoveSpeed=state.moveSpeed;
        }
        final targetBuffState=await liveWorld?.requestMobTargetBuffs(id);
        if(targetBuffState!=null)targetBuffs=targetBuffState.buffs.toList();
        messages.insert(0,'[Target] '+(logical==null?'Mob '+id.toString():catalog!.monsterName(logical.mobId,uiLocale)));
      }catch(e){messages.insert(0,'[Target] '+e.toString());}
    }
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
    if(stage!=GameStage.world||dead||rebirthPending)return;
    final picked=scene.pickNetworkCombatTarget(position.dx,position.dy,1024,742);
    if(picked==null)return;
    await _selectTargetAt(position);
    try{
      if(targetPlayerId!=null){
        final target=targetPlayerId!;
        unawaited(scene.networkPlayerAttackCharacter(target));
        await liveWorld?.startCharacterAutoAttack(target);
        messages.insert(0,'[PvP] Autoataque iniciado → '+(targetPlayerName??target.toString())+'.');
      }else if(targetMobGlobalId!=null){
        final target=targetMobGlobalId!;
        unawaited(scene.networkPlayerAttack(target));
        await liveWorld?.startMobAutoAttack(target);
        messages.insert(0,'[Combate] Autoataque iniciado → '+target.toString()+'.');
      }
      if(mounted)setState((){});
    }catch(e){messages.insert(0,'[Combate] '+e.toString());if(mounted)setState((){});}
  }
  Future<void> _useHotbarSlot(int index) async {
    if(stage!=GameStage.world||dead||rebirthPending)return;
    final slots=_primaryQuickSlots;
    final slot=slots.where((s)=>s.slot==index).firstOrNull??(index<slots.length?slots[index]:null);
    if(slot==null){messages.insert(0,'[Skillbar] Slot '+(index+1).toString()+' vacío.');if(mounted)setState((){});return;}
    if(!slot.isSkill){messages.insert(0,'[Skillbar] Slot '+(index+1).toString()+' contiene bag '+slot.bag.toString()+', item '+slot.number.toString()+'.');if(mounted)setState((){});return;}
    final learned=liveSkills?.bySkillId(slot.number);
    if(learned==null){messages.insert(0,'[Skillbar] SkillId '+slot.number.toString()+' no está aprendida.');if(mounted)setState((){});return;}

    final pvp=targetPlayerId;
    if(pvp!=null&&scene.networkPlayerActors.containsKey(pvp)){
      try{
        unawaited(scene.networkPlayerAttackCharacter(pvp));
        await liveWorld?.useCharacterSkill(learned.number,pvp);
        messages.insert(0,'[PvP] Skill '+learned.skillId.toString()+' Lv.'+learned.level.toString()+' → '+(targetPlayerName??pvp.toString())+'.');
        if(mounted)setState((){});
      }catch(e){messages.insert(0,'[PvP] '+e.toString());if(mounted)setState((){});}
      return;
    }

    final selected=targetMobGlobalId;
    final target=selected!=null&&scene.networkMobActors.containsKey(selected)?selected:scene.nearestNetworkMobId(maxDistance:18);
    if(target==null){messages.insert(0,'[Combate] No hay objetivo seleccionado/cercano.');if(mounted)setState((){});return;}
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
      messages.insert(0,'[Combate] Skill '+learned.skillId.toString()+' Lv.'+learned.level.toString()+' → mob '+target.toString()+'.');
      if(mounted)setState((){});
    }catch(e){messages.insert(0,'[Combate] '+e.toString());if(mounted)setState((){});}
  }
  void _closeWorldPanels(){
    inventoryOpen=false;
    socialOpen=false;
    guildOpen=false;
    guildWarehouseOpen=false;
    statusOpen=false;
    skillsOpen=false;
    questLogOpen=false;
    shopOpen=false;
    blacksmithOpen=false;
    gateOpen=false;
    warehouseOpen=false;
    activeShop=null;
    blacksmithMode=0;
    blacksmithItem=blacksmithGem=blacksmithHammer=null;
    blacksmithPossibility=null;
    blacksmithExtractItem=blacksmithExtractHammer=null;
    blacksmithExtractPosition=0;blacksmithExtractPossibility=null;blacksmithBusy=false;
    activeGate=null;
    activeShopNpcGlobalId=null;
    activeGateNpcGlobalId=null;
  }

  void _toggleWorldPanel(String panel){
    final open=panel=='social'?socialOpen:panel=='guild'?guildOpen:panel=='status'?statusOpen:panel=='skills'?skillsOpen:panel=='quests'?questLogOpen:inventoryOpen;
    _closeWorldPanels();
    questOpen=false;
    if(!open){
      if(panel=='social')socialOpen=true;
      else if(panel=='guild')guildOpen=true;
      else if(panel=='status')statusOpen=true;
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
    if(stage!=GameStage.world||dead||rebirthPending)return;
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
      }else if(logical.type==3){
        _closeWorldPanels();blacksmithOpen=true;
        messages.insert(0,'[Herrero] '+npcName+' · Linking disponible.');
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

  int? _preferredEquipmentSlot(PsInventoryItem item){
    final slots=equipmentSlotsForItemType(item.type);
    if(slots.isEmpty)return null;
    final equipped={for(final x in liveInventory.where((x)=>x.bag==0))x.slot};
    for(final slot in slots){if(!equipped.contains(slot))return slot;}
    return slots.first;
  }

  Future<void> _activateInventoryItem(PsInventoryItem item) async {
    final session=liveWorld;
    if(session==null||stage!=GameStage.world||dead||rebirthPending)return;
    if(item.bag==100){messages.insert(0,'[Inventario] Retira primero el objeto del almacén.');if(mounted)setState((){});return;}
    try{
      if(item.bag==0){
        final dest=_firstFreeInventorySlot();
        if(dest==null){messages.insert(0,'[Inventario] No hay espacio para desequipar.');if(mounted)setState((){});return;}
        final move=await session.moveItem(0,item.slot,dest.bag,dest.slot);
        _upsertInventoryItem(move.source);_upsertInventoryItem(move.destination);liveGold=move.gold;
        messages.insert(0,'[Equipo] Objeto desequipado.');
        if(mounted)setState((){});
        return;
      }

      final equipSlot=_preferredEquipmentSlot(item);
      if(equipSlot!=null){
        final move=await session.moveItem(item.bag,item.slot,0,equipSlot);
        _upsertInventoryItem(move.source);_upsertInventoryItem(move.destination);liveGold=move.gold;
        messages.insert(0,'[Equipo] '+(catalog?.itemName(item.type,item.typeId,uiLocale)??item.key)+' → slot '+equipSlot.toString()+'.');
        if(mounted)setState((){});
        return;
      }

      final rule=metadata?.item(item.type,item.typeId);
      if(rule==null){messages.insert(0,'[Objeto] No hay metadata para '+item.key+'.');if(mounted)setState((){});return;}
      final usable=item.type==27||item.type==28||item.type==29||item.type==30||item.type==98||item.type==99||
        rule.special!=0||rule.hp!=0||rule.mp!=0||rule.sp!=0||rule.itemSkill!=0;
      if(!usable){messages.insert(0,'[Objeto] '+catalog!.itemName(item.type,item.typeId,uiLocale)+' no es equipable ni utilizable.');if(mounted)setState((){});return;}
      if(rule.special==32){
        messages.insert(0,'[Objeto] Movement Rune requiere seleccionar un jugador del grupo; no se enviará contra un mob.');
        if(mounted)setState((){});
        return;
      }
      await session.useInventoryItem(item.bag,item.slot);
      messages.insert(0,'[Objeto] Uso solicitado: '+catalog!.itemName(item.type,item.typeId,uiLocale)+'.');
      if(mounted)setState((){});
    }catch(e){messages.insert(0,'[Objeto/Equipo] '+e.toString());if(mounted)setState((){});}
  }
  int? _firstFreeGuildWarehouseSlot(){
    final occupied={for(final i in liveGuildWarehouse)i.slot};
    for(var slot=0;slot<40;slot++){if(!occupied.contains(slot))return slot;}
    return null;
  }

  Future<void> _storeInGuildWarehouse(PsInventoryItem item) async {
    final session=liveWorld,slot=_firstFreeGuildWarehouseSlot();
    if(session==null||!guildWarehouseOpen||!guildWarehouseAvailable)return;
    if(liveGuildRank<=0||liveGuildRank>8){
      messages.insert(0,'[Guild Warehouse] Tu rango no puede depositar objetos.');
      if(mounted)setState((){});return;
    }
    if(item.bag==0){
      messages.insert(0,'[Guild Warehouse] Debes desequipar el objeto primero.');
      if(mounted)setState((){});return;
    }
    if(slot==null){
      messages.insert(0,'[Guild Warehouse] Primera pestaña llena. No se asume nivel de pestañas superiores.');
      if(mounted)setState((){});return;
    }
    try{
      final move=await session.moveItem(item.bag,item.slot,255,slot);
      _upsertInventoryItem(move.source);_upsertInventoryItem(move.destination);liveGold=move.gold;
      messages.insert(0,'[Guild Warehouse] Objeto guardado en slot '+slot.toString()+'.');
      if(mounted)setState((){});
    }catch(e){messages.insert(0,'[Guild Warehouse] '+e.toString());if(mounted)setState((){});}
  }

  Future<void> _withdrawGuildWarehouse(PsInventoryItem item) async {
    final session=liveWorld,dest=_firstFreeInventorySlot();
    if(session==null||!guildWarehouseOpen||!guildWarehouseAvailable)return;
    if(liveGuildRank<=0||liveGuildRank>2){
      messages.insert(0,'[Guild Warehouse] Solo rangos 1–2 pueden retirar.');
      if(mounted)setState((){});return;
    }
    if(dest==null){messages.insert(0,'[Guild Warehouse] Inventario lleno.');if(mounted)setState((){});return;}
    try{
      final move=await session.moveItem(255,item.slot,dest.bag,dest.slot);
      liveGuildWarehouse.removeWhere((x)=>x.slot==item.slot);
      _upsertInventoryItem(move.destination);liveGold=move.gold;
      messages.insert(0,'[Guild Warehouse] Objeto retirado a bag '+dest.bag.toString()+', slot '+dest.slot.toString()+'.');
      if(mounted)setState((){});
    }catch(e){messages.insert(0,'[Guild Warehouse] '+e.toString());if(mounted)setState((){});}
  }

  void _toggleGuildWarehouse(){
    if(!guildWarehouseAvailable){
      messages.insert(0,'[Guild Warehouse] Solo está disponible dentro del Guild House.');
      if(mounted)setState((){});return;
    }
    final open=!guildWarehouseOpen;
    _closeWorldPanels();
    guildOpen=true;guildWarehouseOpen=open;inventoryOpen=open;
    if(mounted)setState((){});
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
  void _setBlacksmithMode(int mode){
    blacksmithMode=mode.clamp(0,1).toInt();
    if(mounted)setState((){});
  }

  Future<void> _refreshExtractPossibility() async {
    final item=blacksmithExtractItem,session=liveWorld;
    blacksmithExtractPossibility=null;
    if(item==null||session==null){if(mounted)setState((){});return;}
    if(blacksmithExtractPosition<0||blacksmithExtractPosition>=item.gems.length||item.gems[blacksmithExtractPosition]<=0){
      if(mounted)setState((){});return;
    }
    blacksmithBusy=true;if(mounted)setState((){});
    try{
      final hammer=blacksmithExtractHammer;
      blacksmithExtractPossibility=await session.gemRemovePossibility(
        itemBag:item.bag,itemSlot:item.slot,specific:true,gemPosition:blacksmithExtractPosition,
        hammerBag:hammer?.bag??0,hammerSlot:hammer?.slot??0,
      );
      final p=blacksmithExtractPossibility!;
      messages.insert(0,'[Herrero] Extracción: '+p.rate.toStringAsFixed(2)+'% · '+p.gold.toString()+' oro.');
    }catch(e){messages.insert(0,'[Herrero] '+e.toString());}
    finally{blacksmithBusy=false;if(mounted)setState((){});}
  }

  void _selectExtractItem(PsInventoryItem? item){
    blacksmithExtractItem=item;
    if(item!=null){
      final first=item.gems.indexWhere((g)=>g>0);
      blacksmithExtractPosition=first<0?0:first;
    }
    unawaited(_refreshExtractPossibility());
  }
  void _selectExtractPosition(int position){
    blacksmithExtractPosition=position;
    unawaited(_refreshExtractPossibility());
  }
  void _selectExtractHammer(PsInventoryItem? item){
    blacksmithExtractHammer=item;
    unawaited(_refreshExtractPossibility());
  }

  void _upsertRecoveredGem(int bag,int slot,int typeId,int count){
    if(bag<=0||typeId<=0||count<=0)return;
    final index=liveInventory.indexWhere((x)=>x.bag==bag&&x.slot==slot);
    if(index>=0){
      final old=liveInventory[index];
      liveInventory[index]=PsInventoryItem(
        bag:bag,slot:slot,type:old.type==0?30:old.type,typeId:typeId,quality:old.quality,
        count:count,gems:old.gems,craftName:old.craftName,dyed:old.dyed,
      );
    }else{
      liveInventory.add(PsInventoryItem(
        bag:bag,slot:slot,type:30,typeId:typeId,quality:0,count:count,
        gems:const [0,0,0,0,0,0],craftName:'',dyed:false,
      ));
    }
    _sortInventory();
  }

  Future<void> _extractSelectedGem() async {
    final item=blacksmithExtractItem,session=liveWorld,p=blacksmithExtractPossibility;
    if(item==null||session==null||p==null||blacksmithBusy)return;
    if(!p.available||liveGold!=null&&liveGold!<p.gold){
      messages.insert(0,'[Herrero] No se puede ejecutar la extracción con el estado actual.');
      if(mounted)setState((){});return;
    }
    blacksmithBusy=true;if(mounted)setState((){});
    try{
      final hammer=blacksmithExtractHammer;
      final result=await session.removeGem(
        itemBag:item.bag,itemSlot:item.slot,gemPosition:blacksmithExtractPosition,
        hammerBag:hammer?.bag??0,hammerSlot:hammer?.slot??0,
      );
      liveGold=result.gold;
      final itemIndex=liveInventory.indexWhere((x)=>x.bag==result.itemBag&&x.slot==result.itemSlot);
      if(itemIndex>=0&&result.success){
        final old=liveInventory[itemIndex],gems=[...old.gems];
        if(result.gemPosition>=0&&result.gemPosition<gems.length)gems[result.gemPosition]=0;
        liveInventory[itemIndex]=PsInventoryItem(
          bag:old.bag,slot:old.slot,type:old.type,typeId:old.typeId,quality:old.quality,
          count:old.count,gems:List.unmodifiable(gems),craftName:old.craftName,dyed:old.dyed,
        );
        blacksmithExtractItem=liveInventory[itemIndex];
      }
      for(var i=0;i<6;i++){
        _upsertRecoveredGem(result.savedBags[i],result.savedSlots[i],result.savedTypeIds[i],result.savedCounts[i]);
      }
      blacksmithExtractPossibility=null;
      messages.insert(0,result.success?'[Herrero] Lapis extraído según World.':'[Herrero] La extracción falló según World.');
    }catch(e){messages.insert(0,'[Herrero] GEM_REMOVE: '+e.toString());}
    finally{blacksmithBusy=false;if(mounted)setState((){});}
    if(blacksmithExtractItem?.gems.any((g)=>g>0)==true)unawaited(_refreshExtractPossibility());
  }
  Future<void> _refreshBlacksmithPossibility() async {
    final item=blacksmithItem,gem=blacksmithGem,session=liveWorld;
    blacksmithPossibility=null;
    if(item==null||gem==null||session==null){if(mounted)setState((){});return;}
    final itemRule=metadata?.item(item.type,item.typeId),gemRule=metadata?.item(gem.type,gem.typeId);
    if(itemRule==null||itemRule.slot<=0||gemRule==null||gem.type!=30){
      messages.insert(0,'[Herrero] Selección de objeto/lapis inválida.');
      if(mounted)setState((){});return;
    }
    final usedSockets=item.gems.where((g)=>g>0).length;
    if(usedSockets>=itemRule.slot){
      messages.insert(0,'[Herrero] El objeto no tiene huecos de lapis libres.');
      if(mounted)setState((){});return;
    }
    blacksmithBusy=true;if(mounted)setState((){});
    try{
      final hammer=blacksmithHammer;
      blacksmithPossibility=await session.gemAddPossibility(
        gemBag:gem.bag,gemSlot:gem.slot,itemBag:item.bag,itemSlot:item.slot,
        hammerBag:hammer?.bag??0,hammerSlot:hammer?.slot??0,
      );
      final p=blacksmithPossibility!;
      messages.insert(0,'[Herrero] Enlace: '+p.rate.toStringAsFixed(2)+'% · '+p.gold.toString()+' oro.');
    }catch(e){messages.insert(0,'[Herrero] '+e.toString());}
    finally{blacksmithBusy=false;if(mounted)setState((){});}
  }

  void _selectBlacksmithItem(PsInventoryItem? item){
    blacksmithItem=item;unawaited(_refreshBlacksmithPossibility());
  }
  void _selectBlacksmithGem(PsInventoryItem? item){
    blacksmithGem=item;unawaited(_refreshBlacksmithPossibility());
  }
  void _selectBlacksmithHammer(PsInventoryItem? item){
    blacksmithHammer=item;unawaited(_refreshBlacksmithPossibility());
  }

  void _replaceInventoryCount(int bag,int slot,int count){
    final index=liveInventory.indexWhere((x)=>x.bag==bag&&x.slot==slot);
    if(index<0)return;
    final old=liveInventory[index];
    if(count<=0){liveInventory.removeAt(index);return;}
    liveInventory[index]=PsInventoryItem(
      bag:old.bag,slot:old.slot,type:old.type,typeId:old.typeId,quality:old.quality,
      count:count,gems:old.gems,craftName:old.craftName,dyed:old.dyed,
    );
  }

  Future<void> _linkSelectedGem() async {
    final item=blacksmithItem,gem=blacksmithGem,session=liveWorld,p=blacksmithPossibility;
    if(item==null||gem==null||session==null||p==null||blacksmithBusy)return;
    if(!p.available||liveGold!=null&&liveGold!<p.gold){
      messages.insert(0,'[Herrero] No se puede ejecutar el enlace con el estado actual.');
      if(mounted)setState((){});return;
    }
    blacksmithBusy=true;if(mounted)setState((){});
    try{
      final hammer=blacksmithHammer;
      final result=await session.addGem(
        gemBag:gem.bag,gemSlot:gem.slot,itemBag:item.bag,itemSlot:item.slot,
        hammerBag:hammer?.bag??0,hammerSlot:hammer?.slot??0,
      );
      liveGold=result.gold;
      _replaceInventoryCount(result.gemBag,result.gemSlot,result.gemCount);
      final itemIndex=liveInventory.indexWhere((x)=>x.bag==result.itemBag&&x.slot==result.itemSlot);
      if(itemIndex>=0&&result.success&&result.linkSlot>=0&&result.linkSlot<6){
        final old=liveInventory[itemIndex],gems=[...old.gems];
        while(gems.length<6){gems.add(0);}
        gems[result.linkSlot]=result.gemTypeId;
        liveInventory[itemIndex]=PsInventoryItem(
          bag:old.bag,slot:old.slot,type:old.type,typeId:old.typeId,quality:old.quality,
          count:old.count,gems:List.unmodifiable(gems),craftName:old.craftName,dyed:old.dyed,
        );
        blacksmithItem=liveInventory[itemIndex];
      }
      blacksmithGem=liveInventory.where((x)=>x.bag==result.gemBag&&x.slot==result.gemSlot).firstOrNull;
      blacksmithPossibility=null;
      messages.insert(0,result.success?'[Herrero] Lapis enlazado correctamente.':'[Herrero] El enlace falló según World.');
    }catch(e){messages.insert(0,'[Herrero] GEM_ADD: '+e.toString());}
    finally{blacksmithBusy=false;if(mounted)setState((){});}
    if(blacksmithGem!=null)unawaited(_refreshBlacksmithPossibility());
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
        final requestedName=nameController.text.trim();
        final available=await session.checkCharacterName(requestedName);
        if(!available)throw StateError('El nombre "'+requestedName+'" no está disponible.');
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
      if(stage==GameStage.world&&!dead&&!rebirthPending)scene.setMovement(x,z,run:run);
      else if(dead||rebirthPending)scene.clearMovement();
    },
    onAction:(key){
      if(stage!=GameStage.world||dead||rebirthPending)return;
      if(key==LogicalKeyboardKey.keyR){scene.resetCombat();return;}
      if(key==LogicalKeyboardKey.keyE){unawaited(_interactNearestNpc());return;}
      if(key==LogicalKeyboardKey.keyM){unawaited(_toggleVehicle());return;}
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
        onTapDown:(d){if(stage==GameStage.world&&!dead&&!rebirthPending)unawaited(_selectTargetAt(d.localPosition));else focus.requestFocus();},
        onDoubleTapDown:(d){if(stage==GameStage.world&&!dead&&!rebirthPending)unawaited(_autoAttackAt(d.localPosition));},
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
            mapId:liveMapId,
            level:liveCharacter?.level??1,
            details:liveDetails,
            additionalStats:liveAdditionalStats,
            hitpoints:liveHitpoints,
            dead:dead,
            rebirthPending:rebirthPending,
            onRebirth:()=>unawaited(_rebirthTown()),
            buffs:liveBuffs.values.toList(),
            weather:liveWeather,
            mapItems:liveSnapshot?.mapItems??const <PsMapItem>[],
            targetMobGlobalId:targetMobGlobalId,
            targetMobId:targetMobTypeId,
            targetPlayerName:targetPlayerName,
            targetHp:targetPlayerId!=null?targetPlayerHp:targetMobHp,
            targetMaxHp:targetPlayerId!=null?targetPlayerMaxHp:targetMobMaxHp,
            targetAttackSpeed:targetAttackSpeed,
            targetMoveSpeed:targetMoveSpeed,
            targetBuffs:targetBuffs,
            targetCasting:targetCasting,
            skillBook:liveSkills,
            skillBar:liveSkillBar,
            inventory:liveInventory,
            warehouse:liveWarehouse,
            guildWarehouse:liveGuildWarehouse,
            guildWarehouseAvailable:guildWarehouseAvailable,
            guildWarehouseOpen:guildWarehouseOpen,
            friends:liveFriends,
            partyMembers:livePartyMembers,
            raid:liveRaid,
            pendingRaidRequesterId:pendingRaidRequesterId,
            pendingVehicleRequesterId:pendingVehicleRequesterId,
            vehicleMounted:vehicleMounted,
            vehicleSummoning:vehicleSummoning,
            onToggleVehicle:()=>unawaited(_toggleVehicle()),
            onRespondVehicle:_respondVehicleRequest,
            partyLeaderId:partyLeaderId,
            guildDirectory:guildDirectory,
            guildMembers:liveGuildMembers,
            guildApplicants:guildApplicants,
            guildId:liveGuildId,
            guildRank:liveGuildRank,
            guildName:liveGuildName,
            guildListLoading:guildListLoading,
            pendingGuildCreateInvite:pendingGuildCreateInvite,
            tradeOpen:tradeOpen,
            tradePartnerId:tradePartnerId,
            pendingTradeRequesterId:pendingTradeRequesterId,
            localTradeItems:localTradeItems,
            remoteTradeItems:remoteTradeItems,
            localTradeMoney:localTradeMoney,
            remoteTradeMoney:remoteTradeMoney,
            localTradeDecided:localTradeDecided,
            remoteTradeDecided:remoteTradeDecided,
            localTradeConfirmed:localTradeConfirmed,
            remoteTradeConfirmed:remoteTradeConfirmed,
            duelTradeOpen:duelTradeOpen,
            duelStarted:duelStarted,
            duelReady:duelReady,
            duelOpponentId:duelOpponentId,
            pendingDuelRequesterId:pendingDuelRequesterId,
            localDuelItems:localDuelItems,
            remoteDuelItems:remoteDuelItems,
            localDuelMoney:localDuelMoney,
            remoteDuelMoney:remoteDuelMoney,
            localDuelApproved:localDuelApproved,
            remoteDuelApproved:remoteDuelApproved,
            duelResultText:duelResultText,
            selfCharacterId:liveCharacter?.id,
            pendingFriendRequestName:pendingFriendRequestName,
            pendingPartyRequesterId:pendingPartyRequesterId,
            inventoryOpen:inventoryOpen,
            socialOpen:socialOpen,
            guildOpen:guildOpen,
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
            blacksmithOpen:blacksmithOpen,
            gateOpen:gateOpen,
            blacksmithMode:blacksmithMode,
            blacksmithItem:blacksmithItem,
            blacksmithGem:blacksmithGem,
            blacksmithHammer:blacksmithHammer,
            blacksmithPossibility:blacksmithPossibility,
            blacksmithExtractItem:blacksmithExtractItem,
            blacksmithExtractHammer:blacksmithExtractHammer,
            blacksmithExtractPosition:blacksmithExtractPosition,
            blacksmithExtractPossibility:blacksmithExtractPossibility,
            blacksmithBusy:blacksmithBusy,
            onCloseShop:()=>setState(()=>shopOpen=false),
            onCloseBlacksmith:()=>setState(()=>blacksmithOpen=false),
            onCloseGate:()=>setState(()=>gateOpen=false),
            onCloseWarehouse:()=>setState(()=>warehouseOpen=false),
            onBlacksmithMode:_setBlacksmithMode,
            onSelectBlacksmithItem:_selectBlacksmithItem,
            onSelectBlacksmithGem:_selectBlacksmithGem,
            onSelectBlacksmithHammer:_selectBlacksmithHammer,
            onSelectExtractItem:_selectExtractItem,
            onSelectExtractPosition:_selectExtractPosition,
            onSelectExtractHammer:_selectExtractHammer,
            onLinkGem:()=>unawaited(_linkSelectedGem()),
            onExtractGem:()=>unawaited(_extractSelectedGem()),
            onBuyShopProduct:(index)=>unawaited(_buyShopProduct(index)),
            onUseGate:(index)=>unawaited(_useGatekeeperTarget(index)),
            onSellInventory:(item)=>unawaited(_sellInventoryItem(item)),
            onActivateInventory:(item)=>unawaited(_activateInventoryItem(item)),
            onStoreWarehouse:(item)=>unawaited(_storeInWarehouse(item)),
            onWithdrawWarehouse:(item)=>unawaited(_withdrawWarehouse(item)),
            onToggleGuildWarehouse:_toggleGuildWarehouse,
            onStoreGuildWarehouse:(item)=>unawaited(_storeInGuildWarehouse(item)),
            onWithdrawGuildWarehouse:(item)=>unawaited(_withdrawGuildWarehouse(item)),
            onPickMapItem:(item)=>unawaited(_pickMapItem(item)),
            onToggleInventory:()=>_toggleWorldPanel('inventory'),
            onToggleSocial:()=>_toggleWorldPanel('social'),
            onToggleGuild:()=>_toggleWorldPanel('guild'),
            onRequestGuildJoin:(guild)=>unawaited(_requestGuildJoin(guild)),
            onRespondGuildApplicant:(entry,accepted)=>unawaited(_respondGuildApplicant(entry,accepted)),
            onLeaveGuild:()=>unawaited(_leaveGuild()),
            onKickGuild:(member)=>unawaited(_kickGuildMember(member)),
            onPromoteGuild:(member)=>unawaited(_changeGuildMemberRank(member,false)),
            onDemoteGuild:(member)=>unawaited(_changeGuildMemberRank(member,true)),
            onCreateGuild:(name,message)=>unawaited(_createGuild(name,message)),
            onRespondGuildCreate:(accepted)=>unawaited(_respondGuildCreate(accepted)),
            onDismantleGuild:()=>unawaited(_dismantleGuild()),
            onRequestTrade:(id)=>unawaited(_requestTrade(id)),
            onRespondTrade:(accepted)=>unawaited(_respondTrade(accepted)),
            onTradeInventoryItem:(item)=>unawaited(_addInventoryToTrade(item)),
            onRemoveTradeItem:(slot)=>unawaited(_removeTradeItem(slot)),
            onSetTradeMoney:(money)=>unawaited(_setTradeMoney(money)),
            onDecideTrade:(ready)=>unawaited(_decideTrade(ready)),
            onFinishTrade:(result)=>unawaited(_finishTrade(result)),
            onRequestDuel:(id)=>unawaited(_requestDuel(id)),
            onRespondDuel:(accepted)=>unawaited(_respondDuel(accepted)),
            onDuelInventoryItem:(item)=>unawaited(_addInventoryToDuel(item)),
            onRemoveDuelItem:(slot)=>unawaited(_removeDuelItem(slot)),
            onSetDuelMoney:(money)=>unawaited(_setDuelMoney(money)),
            onDecideDuel:(ready)=>unawaited(_decideDuel(ready)),
            onCloseDuelTrade:()=>unawaited(_closeDuelTrade()),
            onAdmitDuelDefeat:()=>unawaited(_admitDuelDefeat()),
            onRequestFriend:(name)=>unawaited(_requestFriend(name)),
            onRespondFriend:(accepted)=>unawaited(_respondFriend(accepted)),
            onDeleteFriend:(friend)=>unawaited(_deleteFriend(friend)),
            onInviteParty:(friend)=>unawaited(_inviteFriendToParty(friend)),
            onRespondParty:(accepted)=>unawaited(_respondParty(accepted)),
            onCreateRaid:()=>unawaited(_createRaid()),
            onRespondRaid:(accepted)=>unawaited(_respondRaid(accepted)),
            onLeaveRaid:()=>unawaited(_leaveRaid()),
            onDismantleRaid:()=>unawaited(_dismantleRaid()),
            onInviteRaid:(id)=>unawaited(_inviteRaidCharacter(id)),
            onJoinRaid:(name)=>unawaited(_joinRaidByName(name)),
            onKickRaid:(row)=>unawaited(_kickRaidMember(row)),
            onChangeRaidLeader:(row)=>unawaited(_changeRaidLeader(row)),
            onChangeRaidSubLeader:(row)=>unawaited(_changeRaidSubLeader(row)),
            onMoveRaidGroup:(row,group)=>unawaited(_moveRaidMemberToGroup(row,group)),
            onChangeRaidLoot:(value)=>unawaited(_changeRaidLoot(value)),
            onToggleRaidAutoJoin:()=>unawaited(_toggleRaidAutoJoin()),
            onLeaveParty:()=>unawaited(_leaveParty()),
            onKickParty:(member)=>unawaited(_kickPartyMember(member)),
            onPromoteParty:(member)=>unawaited(_promotePartyMember(member)),
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
