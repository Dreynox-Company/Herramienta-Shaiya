import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:three_js/three_js.dart' as three;
import '../data/library.dart';
import '../data/catalog.dart';
import '../render/studio_scene.dart';
import '../input/viewport_movement_input.dart';
import 'ui_texture_cache.dart';

enum GamePhase { connecting, faction, character, world }

class FlutterGameClientPage extends StatefulWidget {
  final String? initialData;
  final bool autoWorld;
  const FlutterGameClientPage({super.key,this.initialData,this.autoWorld=false});
  @override State<FlutterGameClientPage> createState()=>_FlutterGameClientPageState();
}

class _FlutterGameClientPageState extends State<FlutterGameClientPage> {
  late final StudioScene scene;
  late final three.ThreeJS renderer;
  final FocusNode focus=FocusNode(debugLabel:'game-input');
  Catalog? catalog;
  GameUiTextureCache? ui;
  GamePhase phase=GamePhase.connecting;
  bool busy=true;
  String status='Inicializando renderer…';
  String faction='light';
  String characterName='DreynoxLocal';
  bool questOpen=true;
  bool chatExpanded=true;
  bool showDebug=false;
  double gestureScale=1;
  final List<String> log=[];

  @override void initState(){
    super.initState();
    scene=StudioScene(_log);
    renderer=three.ThreeJS(
      settings:three.Settings(clearColor:0x0b0c0f,antialias:true,enableShadowMap:false,toneMapping:three.NoToneMapping),
      setup:()=>scene.setup(renderer),
      onSetupComplete:(){if(mounted)unawaited(_connect());},
    );
    scene.addListener(_refresh);
  }

  void _refresh(){if(mounted)setState((){});}
  void _log(String message){
    log.insert(0,DateTime.now().toIso8601String()+' · '+message);
    if(log.length>200)log.removeLast();
  }

  Future<void> _connect() async {
    if(!mounted)return;
    setState((){busy=true;phase=GamePhase.connecting;status='Indexando DATA…';});
    try{
      void report(String s){if(mounted)setState(()=>status=s);}
      final Library? library=widget.initialData!=null
          ? await Library.fromDirectory(widget.initialData!,report)
          : await Library.choose(report);
      if(library==null){if(mounted)Navigator.of(context).maybePop();return;}
      final next=Catalog(library);
      await next.load(report);
      scene.catalog=next;catalog=next;ui=GameUiTextureCache(library);
      final list=next.archetypes.where((a)=>a.id.toLowerCase()=='humf').toList();
      final humf=list.isNotEmpty?list.first:next.archetypes.first;
      await scene.setAppearance(Appearance.initial(humf));
      scene.yaw=3.12;scene.pitch=.16;scene.distance=5.4;scene.targetY=1.15;scene.updateCamera();
      if(!mounted)return;
      setState(()=>status='Conectando con la partida local…');
      await Future.delayed(const Duration(milliseconds:700));
      if(widget.autoWorld){
        await _enterWorld();
      } else if(mounted) {
        setState((){busy=false;phase=GamePhase.faction;});
      }
    }catch(e,st){
      _log(e.toString()+'\n'+st.toString());
      if(mounted){setState((){busy=false;status='Error: '+e.toString();});ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
    }
  }

  Future<void> _enterCharacter() async {
    setState((){busy=true;status='Preparando personaje…';});
    try{
      scene.yaw=.25;scene.pitch=.12;scene.distance=4.7;scene.targetY=1.0;scene.updateCamera();
      if(mounted)setState((){busy=false;phase=GamePhase.character;});
    }catch(e){if(mounted)setState((){busy=false;status=e.toString();});}
  }

  Future<void> _enterWorld() async {
    setState((){busy=true;status='Cargando mapa 1 · Keolloseu…';});
    try{
      final resolved=catalog!.library.resolve('1.wld',['world']);
      final path=resolved??'world/1.wld';
      await scene.setWorld(path,x:580,z:1769.877);
      scene.yaw=3.08;scene.pitch=.24;scene.distance=7.4;scene.targetY=1.1;scene.updateCamera();
      final merchant=catalog!.creatures.where((c)=>c.id==491).toList();
      final guard=catalog!.creatures.where((c)=>c.id==92).toList();
      final guard2=catalog!.creatures.where((c)=>c.id==93).toList();
      final dog=catalog!.creatures.where((c)=>c.id==798).toList();
      final visuals=<CreatureRecord>[
        if(merchant.isNotEmpty)merchant.first,
        if(guard.isNotEmpty)guard.first,
        if(guard2.isNotEmpty)guard2.first,
        if(dog.isNotEmpty)dog.first,
      ];
      final world=scene.world;
      if(world!=null&&visuals.isNotEmpty){
        final nearby=world.npcs.where((npc){
          final dx=npc.position.x-scene.originX;
          final dz=npc.position.z-scene.originZ;
          return dx*dx+dz*dz<72*72;
        }).toList()
          ..sort((a,b){
            final adx=a.position.x-scene.originX,adz=a.position.z-scene.originZ;
            final bdx=b.position.x-scene.originX,bdz=b.position.z-scene.originZ;
            return (adx*adx+adz*adz).compareTo(bdx*bdx+bdz*bdz);
          });
        for(var i=0;i<nearby.length&&i<12;i++){
          final npc=nearby[i];
          CreatureRecord visual;
          if(npc.type==8&&dog.isNotEmpty){
            visual=dog.first;
          }else{
            visual=visuals[i%visuals.length];
          }
          final key='${npc.type}:${npc.typeId}';
          final names=<String,String>{
            '7:1167':'Guardfection Merchant',
            '7:1081':'Beika Security Trainer',
            '7:1125':'Union Guard',
            '8:20':'Dog',
          };
          await scene.spawnWorldNpc(
            visual,
            name:names[key]??'NPC ${npc.typeId}',
            x:npc.position.x-scene.originX,
            z:-(npc.position.z-scene.originZ),
            quest:npc.type==7,
            rotation:npc.orientation,
          );
        }
      }
      if(mounted)setState((){busy=false;phase=GamePhase.world;questOpen=true;status='Mapa 1 cargado';});
      focus.requestFocus();
    }catch(e,st){
      _log(e.toString()+'\n'+st.toString());
      if(mounted)setState((){busy=false;status='No se pudo entrar al mundo: '+e.toString();});
    }
  }

  @override void dispose(){scene.removeListener(_refresh);scene.dispose();renderer.dispose();focus.dispose();super.dispose();}

  @override Widget build(BuildContext context)=>Scaffold(
    backgroundColor:Colors.black,
    body:KeyboardListener(
      focusNode:FocusNode(skipTraversal:true),
      onKeyEvent:(event){if(event is KeyDownEvent&&event.logicalKey==LogicalKeyboardKey.f10)setState(()=>showDebug=!showDebug);},
      child:Stack(children:[
        Positioned.fill(child:_phase()),
        if(busy)Positioned.fill(child:_loadingOverlay()),
        if(showDebug)Positioned(left:8,bottom:8,width:430,child:_debugPanel()),
      ]),
    ),
  );

  Widget _phase()=>switch(phase){
    GamePhase.connecting=>_connecting(),
    GamePhase.faction=>_faction(),
    GamePhase.character=>_character(),
    GamePhase.world=>_world(),
  };

  Widget _loadingOverlay()=>IgnorePointer(child:ColoredBox(
    color:const Color(0x7f000000),
    child:Center(child:Container(
      padding:const EdgeInsets.symmetric(horizontal:22,vertical:14),
      decoration:BoxDecoration(color:const Color(0xdf15100f),border:Border.all(color:const Color(0xff6d4b45)),borderRadius:BorderRadius.circular(3)),
      child:Row(mainAxisSize:MainAxisSize.min,children:[
        const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2,color:Color(0xffe5b38d))),
        const SizedBox(width:12),
        ConstrainedBox(constraints:const BoxConstraints(maxWidth:420),child:Text(status,style:const TextStyle(color:Colors.white,fontSize:12))),
      ]),
    )),
  ));

  Widget _connecting(){
    final cache=ui;
    if(cache==null)return const ColoredBox(color:Colors.black);
    return Stack(fit:StackFit.expand,children:[
      cache.image('interface/loading/loading_spn.jpg',fit:BoxFit.cover,fallback:const ColoredBox(color:Color(0xff101010))),
      const DecoratedBox(decoration:BoxDecoration(gradient:LinearGradient(begin:Alignment.topCenter,end:Alignment.bottomCenter,colors:[Color(0x20000000),Color(0x10000000),Color(0x90000000)]))),
      const Align(alignment:Alignment(0,.23),child:Text('Connecting...',style:TextStyle(color:Colors.white,fontSize:12,shadows:[Shadow(blurRadius:4,color:Colors.black)]))),
      Positioned(right:42,bottom:36,child:_oldButton('Quit Game',onTap:()=>exit(0),width:116)),
    ]);
  }

  Widget _faction(){
    final cache=ui!;
    return Stack(fit:StackFit.expand,children:[
      const ColoredBox(color:Colors.black),
      Positioned.fill(top:140,bottom:100,child:Row(children:[
        Expanded(child:GestureDetector(onTap:()=>setState(()=>faction='fury'),child:Stack(fit:StackFit.expand,children:[
          cache.image('interface/countryselect/fury_select.tga',fit:BoxFit.cover),
          Container(color:faction=='fury'?Colors.transparent:Colors.black.withValues(alpha:.45)),
          const Positioned(left:28,bottom:22,child:Text('Unión de la Furia',style:TextStyle(color:Colors.white,fontSize:25,fontStyle:FontStyle.italic,shadows:[Shadow(blurRadius:6,color:Colors.black)]))),
        ]))),
        Expanded(child:GestureDetector(onTap:()=>setState(()=>faction='light'),child:Stack(fit:StackFit.expand,children:[
          cache.image('interface/countryselect/light_select.tga',fit:BoxFit.cover),
          Container(color:faction=='light'?Colors.transparent:Colors.black.withValues(alpha:.45)),
          const Positioned(right:24,top:22,child:Text('Alianza de la Luz',style:TextStyle(color:Colors.white,fontSize:25,fontStyle:FontStyle.italic,shadows:[Shadow(blurRadius:6,color:Colors.black)]))),
        ]))),
      ])),
      Positioned(right:18,bottom:20,child:Row(children:[
        _oldButton('Atrás',onTap:()=>setState(()=>phase=GamePhase.connecting),width:112),
        const SizedBox(width:18),
        _oldButton('Siguiente',onTap:_enterCharacter,width:112),
      ])),
    ]);
  }

  Widget _character()=>Stack(children:[
    Positioned.fill(child:renderer.build()),
    Positioned.fill(child:IgnorePointer(child:DecoratedBox(decoration:BoxDecoration(gradient:LinearGradient(colors:[Colors.black.withValues(alpha:.25),Colors.transparent,Colors.black.withValues(alpha:.2)]))))),
    Positioned(left:10,top:22,bottom:18,width:330,child:_characterLeftPanel()),
    Positioned(right:10,top:34,width:280,height:440,child:_characterRightPanel()),
    Positioned(right:10,bottom:20,child:Row(children:[
      _oldButton('Atrás',onTap:()=>setState(()=>phase=GamePhase.faction),width:115),
      const SizedBox(width:14),
      _oldButton('Crear',onTap:_enterWorld,width:115),
    ])),
  ]);

  Widget _characterLeftPanel()=>Container(
    decoration:_frame(),padding:const EdgeInsets.all(12),
    child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      const Text('Explicación',style:TextStyle(color:Colors.white,fontSize:12)),const SizedBox(height:8),
      Container(height:190,padding:const EdgeInsets.all(10),decoration:BoxDecoration(color:Colors.black.withValues(alpha:.44),border:Border.all(color:const Color(0xff5c5b54))),child:const SingleChildScrollView(child:Text(
        'El Guerrero es un combatiente cuerpo a cuerpo. De cerca, su fuerza y resistencia dominan el combate.\n\nCaracterísticas:\n· Amplia gama de armas\n· Ataques físicos poderosos\n· Excelente supervivencia',
        style:TextStyle(color:Color(0xffeeeeee),fontSize:11,height:1.6)))),
      const SizedBox(height:16),
      Row(children:[Expanded(child:_tab('Información',true)),Expanded(child:_tab('Apariencia',false)),Expanded(child:_tab('Modo',false))]),
      const SizedBox(height:10),const Text('Nombre',style:TextStyle(color:Color(0xffffef3b),fontSize:11)),const SizedBox(height:6),
      Row(children:[
        Expanded(child:TextFormField(initialValue:characterName,onChanged:(v)=>characterName=v,style:const TextStyle(fontSize:12,color:Colors.white),decoration:const InputDecoration(isDense:true,filled:true,fillColor:Color(0xaa121212),border:OutlineInputBorder(),contentPadding:EdgeInsets.symmetric(horizontal:8,vertical:8)))),
        const SizedBox(width:10),_oldButton('Comprobar',onTap:(){},width:92,height:34),
      ]),
      const SizedBox(height:14),const Text('Clase',style:TextStyle(color:Color(0xffffef3b),fontSize:11)),const SizedBox(height:8),
      Expanded(child:GridView.count(crossAxisCount:3,mainAxisSpacing:6,crossAxisSpacing:6,childAspectRatio:1.08,children:[
        _classTile('Guerrero','interface/create_fighter_button.tga',true),
        _classTile('Defensor','interface/create_defender_button.tga',false),
        _classTile('Sacerdote','interface/create_priest_button.tga',false),
        _classTile('Ranger','interface/create_ranger_button.tga',false),
        _classTile('Arquero','interface/create_archer_button.tga',false),
        _classTile('Mago','interface/create_mage_button.tga',false),
      ])),
      const Text('Género',style:TextStyle(color:Color(0xffffef3b),fontSize:11)),const SizedBox(height:8),
      Row(children:[_gender('♂',true),const SizedBox(width:8),_gender('♀',false)]),
    ]),
  );

  Widget _characterRightPanel()=>Container(
    decoration:_frame(),padding:const EdgeInsets.all(12),
    child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      const Align(alignment:Alignment.centerRight,child:Text('Armas',style:TextStyle(color:Color(0xffffef3b),fontSize:11))),const SizedBox(height:12),
      Wrap(alignment:WrapAlignment.center,spacing:14,runSpacing:12,children:[
        _weapon('⚔','Espada\n1 mano'),_weapon('🗡','Espada\n2 manos'),_weapon('⚔','Doble\nespada'),_weapon('⌁','Lanza'),_weapon('◒','Maza\n1 mano'),_weapon('◓','Maza\n2 manos'),_weapon('⬟','Escudo'),
      ]),
      const Spacer(),const Align(alignment:Alignment.centerRight,child:Text('Figura de clase',style:TextStyle(color:Color(0xffffef3b),fontSize:11))),const SizedBox(height:22),
      _stat('Solo',.78),const SizedBox(height:14),_stat('Grupo',.62),const SizedBox(height:26),_stat('ATQ',.77),const SizedBox(height:14),_stat('DEF',.63),const SizedBox(height:12),
    ]),
  );

  Widget _world()=>Stack(children:[
    Positioned.fill(child:ViewportMovementInput(
      focusNode:focus,
      onChanged:(x,z,run)=>scene.setMovement(x,z,run:run),
      onAction:(key){if(key==LogicalKeyboardKey.keyR)setState(()=>questOpen=!questOpen);},
      child:Listener(
        onPointerSignal:(e){if(e is PointerScrollEvent)scene.zoom(e.scrollDelta.dy>0?1.08:1/1.08);},
        child:GestureDetector(
          behavior:HitTestBehavior.opaque,onTap:focus.requestFocus,
          onScaleStart:(_){gestureScale=1;focus.requestFocus();},
          onScaleUpdate:(d){if(d.pointerCount==1)scene.orbit(d.focalPointDelta.dx,d.focalPointDelta.dy);else{scene.zoom(gestureScale/d.scale);gestureScale=d.scale;}},
          child:renderer.build(),
        ),
      ),
    )),
    Positioned(left:6,top:6,child:_statusHud()),
    Positioned(top:2,left:320,right:300,child:_hotbar()),
    Positioned(right:8,top:8,width:192,height:190,child:_minimap()),
    if(questOpen)Positioned(right:212,top:118,width:250,height:540,child:_questPanel()),
    Positioned(left:4,bottom:52,width:330,height:340,child:_chat()),
    Positioned(left:12,right:12,bottom:8,child:_bottomHud()),
    for(final entry in scene.worldNpcs.asMap().entries)_npcLabel(entry.key,entry.value),
  ]);

  Widget _npcLabel(int index,WorldNpcActor npc){
    final positions=<Offset>[const Offset(88,214),const Offset(118,232),const Offset(364,238)];
    final p=positions[index.clamp(0,positions.length-1).toInt()];
    return Positioned(left:p.dx,top:p.dy,child:IgnorePointer(child:Column(children:[
      if(npc.quest)const Text('!',style:TextStyle(color:Color(0xffffff31),fontSize:28,fontWeight:FontWeight.bold,shadows:[Shadow(color:Colors.black,blurRadius:3)])),
      Text(npc.name,style:TextStyle(color:npc.quest?const Color(0xff62d5ff):const Color(0xffffff7a),fontSize:10,shadows:const [Shadow(color:Colors.black,blurRadius:3),Shadow(color:Colors.black,offset:Offset(1,1))])),
    ])));
  }

  Widget _statusHud()=>Container(
    width:216,height:72,
    decoration:BoxDecoration(color:const Color(0xb5151719),border:Border.all(color:const Color(0xff69685f)),borderRadius:BorderRadius.circular(4)),
    padding:const EdgeInsets.all(5),
    child:Row(children:[
      Container(width:48,height:48,decoration:BoxDecoration(color:const Color(0xff281b17),border:Border.all(color:const Color(0xff7e6d55))),child:const Center(child:Text('♨',style:TextStyle(color:Color(0xffff684c),fontSize:28)))),
      const SizedBox(width:6),
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Row(children:[const Text('1',style:TextStyle(color:Colors.white,fontSize:11)),const SizedBox(width:8),Expanded(child:Text(characterName,style:const TextStyle(color:Color(0xffffff36),fontSize:12)))]),
        _bar(const Color(0xffd7191c),1,'255 / 255'),_bar(const Color(0xff1d60e8),1,'95 / 95'),_bar(const Color(0xffffd226),1,'160 / 160'),
      ])),
    ]),
  );

  Widget _hotbar()=>Container(
    height:45,
    decoration:BoxDecoration(color:const Color(0xa90a0a09),border:Border.all(color:const Color(0xff5b594d)),borderRadius:BorderRadius.circular(3)),
    child:Row(mainAxisAlignment:MainAxisAlignment.center,children:List.generate(12,(i)=>Container(
      width:40,height:40,margin:const EdgeInsets.symmetric(horizontal:1),decoration:BoxDecoration(color:const Color(0xaa1e211d),border:Border.all(color:const Color(0xff4f4e43))),
      child:Stack(children:[
        Positioned(left:2,top:1,child:Text(((i+1)%10).toString(),style:const TextStyle(color:Colors.white,fontSize:9))),
        if(i==0)const Center(child:Text('⚔',style:TextStyle(fontSize:22))),if(i==1)const Center(child:Text('🧪',style:TextStyle(fontSize:19))),
      ]),
    ))),
  );

  Widget _minimap()=>Container(
    decoration:BoxDecoration(color:const Color(0xda1a1a15),border:Border.all(color:const Color(0xff77705e)),borderRadius:BorderRadius.circular(3)),
    padding:const EdgeInsets.all(5),
    child:Column(children:[
      Expanded(child:ClipRRect(borderRadius:BorderRadius.circular(2),child:Stack(fit:StackFit.expand,children:[
        ui!.image('interface/worldmap-light.jpg',fit:BoxFit.cover,alignment:const Alignment(-.35,-.18),fallback:const ColoredBox(color:Color(0xff335238))),
        const Center(child:Icon(Icons.location_on,color:Colors.white,size:18,shadows:[Shadow(color:Colors.black,blurRadius:3)])),
        const Positioned(top:2,left:0,right:0,child:Center(child:Text('N',style:TextStyle(color:Colors.white,fontWeight:FontWeight.bold,fontSize:12)))),
      ]))),
      const SizedBox(height:4),
      Row(children:[const Icon(Icons.zoom_in,size:15,color:Color(0xffded6b8)),const SizedBox(width:3),const Icon(Icons.zoom_out,size:15,color:Color(0xffded6b8)),const Spacer(),const Text('09.21  00:19',style:TextStyle(color:Colors.white,fontSize:9))]),
    ]),
  );

  Widget _questPanel()=>Container(
    decoration:BoxDecoration(
      color:const Color(0xf2a77845),
      border:Border.all(color:const Color(0xff30241b),width:3),
      boxShadow:const [BoxShadow(color:Colors.black54,blurRadius:8)],
    ),
    child:Column(children:[
      Container(
        height:34,
        padding:const EdgeInsets.symmetric(horizontal:12),
        decoration:const BoxDecoration(
          color:Color(0xff55331e),
          border:Border(bottom:BorderSide(color:Color(0xffc58d52))),
        ),
        child:const Row(children:[
          Text('!',style:TextStyle(color:Color(0xffffff33),fontSize:22,fontWeight:FontWeight.bold)),
          SizedBox(width:8),
          Text('Operación básica de la interfaz',style:TextStyle(color:Color(0xffffff66),fontSize:12)),
        ]),
      ),
      Expanded(
        child:Container(
          margin:const EdgeInsets.all(8),
          padding:const EdgeInsets.all(10),
          decoration:const BoxDecoration(color:Color(0xffc79a67)),
          child:const SingleChildScrollView(
            child:Text(
              'Hmm? ¿Nos hemos visto antes? En estos tiempos difíciles… pero es el mejor momento para que un guerrero construya su fama. ¿Quieres convertirte en un guerrero? Convertirte en guerrero te aportará mucho dolor y dificultad.\n\nDebes aprender y recordar todo lo que te enseñe.\n\n\nObjeto de recompensa',
              style:TextStyle(color:Color(0xff2e251d),fontSize:11,height:1.65),
            ),
          ),
        ),
      ),
      Padding(
        padding:const EdgeInsets.fromLTRB(12,4,12,12),
        child:Row(children:[
          Expanded(child:_oldButton('Aceptar',onTap:()=>setState(()=>questOpen=false),height:34)),
          const SizedBox(width:18),
          Expanded(child:_oldButton('Cancelar',onTap:()=>setState(()=>questOpen=false),height:34)),
        ]),
      ),
    ]),
  );

  Widget _chat()=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    const Spacer(),
    Container(decoration:BoxDecoration(color:const Color(0x25000000),border:Border.all(color:const Color(0x447b775f))),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Row(children:[IconButton(onPressed:()=>setState(()=>chatExpanded=!chatExpanded),icon:Icon(chatExpanded?Icons.remove:Icons.add,size:14,color:Colors.white),padding:EdgeInsets.zero,constraints:const BoxConstraints.tightFor(width:20,height:20)),const SizedBox(width:4),const Text('Mundo',style:TextStyle(color:Colors.white,fontSize:12))]),
      if(chatExpanded)SizedBox(height:110,child:Padding(padding:const EdgeInsets.all(6),child:ListView(children:const [
        Text('[Aviso] Laboratorio local',style:TextStyle(color:Colors.white,fontSize:10)),Text('Cliente Flutter conectado a DATA local.',style:TextStyle(color:Color(0xffddddaa),fontSize:10)),
      ]))),
    ])),
  ]);

  Widget _bottomHud()=>Row(crossAxisAlignment:CrossAxisAlignment.end,children:[
    Expanded(child:Column(children:[
      Container(height:11,decoration:BoxDecoration(color:const Color(0xff151515),border:Border.all(color:const Color(0xff6e6651))),child:const FractionallySizedBox(widthFactor:.003,alignment:Alignment.centerLeft,child:ColoredBox(color:Color(0xff68a7e6)))),
      const Text('0.0%',style:TextStyle(color:Colors.white,fontSize:10)),
    ])),
    const SizedBox(width:14),
    Row(children:[_roundIcon('📕'),_roundIcon('🛡'),_roundIcon('✊'),_roundIcon('📜'),_roundIcon('✋'),_roundIcon('🏃'),_roundIcon('💬'),_roundIcon('🪽'),_roundIcon('⚙'),_roundIcon('🎁')]),
  ]);

  Widget _debugPanel()=>Container(
    padding:const EdgeInsets.all(8),decoration:BoxDecoration(color:const Color(0xe6000000),border:Border.all(color:const Color(0xff777777))),
    child:Text([
      'F10: ocultar diagnóstico','phase='+phase.name+' busy='+busy.toString(),'DATA='+(catalog?.library.location??'-'),
      'world='+(scene.worldPath??'-')+' origin='+scene.originX.toStringAsFixed(1)+','+scene.originZ.toStringAsFixed(1),
      'NPC='+scene.worldNpcs.length.toString(),'actor='+(scene.appearance?.archetype.id??'-'),...log.take(7),
    ].join('\n'),style:const TextStyle(color:Color(0xffb8ffb8),fontSize:10,fontFamily:'Consolas')),
  );

  BoxDecoration _frame()=>BoxDecoration(color:const Color(0xc9191b18),border:Border.all(color:const Color(0xff6b685d)),borderRadius:BorderRadius.circular(6),boxShadow:const [BoxShadow(color:Colors.black54,blurRadius:10)]);

  Widget _oldButton(String text,{required VoidCallback onTap,double width=100,double height=38})=>SizedBox(
    width:width,height:height,
    child:Material(color:Colors.transparent,child:InkWell(onTap:onTap,child:Ink(
      decoration:BoxDecoration(gradient:const LinearGradient(begin:Alignment.topCenter,end:Alignment.bottomCenter,colors:[Color(0xff8e3f3f),Color(0xff311719)]),border:Border.all(color:const Color(0xffa86b62)),borderRadius:BorderRadius.circular(3)),
      child:Center(child:Text(text,style:const TextStyle(color:Colors.white,fontSize:11,shadows:[Shadow(color:Colors.black,blurRadius:2)]))),
    ))),
  );

  Widget _tab(String text,bool selected)=>Container(
    height:32,decoration:BoxDecoration(gradient:LinearGradient(colors:selected?[const Color(0xff4d4532),const Color(0xff1f1c16)]:[const Color(0xff2b2924),const Color(0xff171715)]),border:Border.all(color:selected?const Color(0xffa3893f):const Color(0xff5a574c))),
    child:Center(child:Text(text,style:TextStyle(color:selected?Colors.white:const Color(0xffc7c6bc),fontSize:11))),
  );

  Widget _classTile(String label,String asset,bool selected)=>Container(
    decoration:BoxDecoration(color:const Color(0xaa1d1d18),border:Border.all(color:selected?const Color(0xffffd73f):const Color(0xff4b4940),width:selected?2:1),borderRadius:BorderRadius.circular(3)),
    padding:const EdgeInsets.all(3),child:Column(children:[
      Expanded(child:ui!.image(asset,fit:BoxFit.contain,fallback:Center(child:Text(label.substring(0,1),style:const TextStyle(fontSize:30,color:Colors.white))))),Text(label,style:const TextStyle(color:Colors.white,fontSize:10)),
    ]),
  );

  Widget _gender(String symbol,bool selected)=>Container(
    width:56,height:52,decoration:BoxDecoration(color:const Color(0xaa1d1d18),border:Border.all(color:selected?const Color(0xffffd73f):const Color(0xff4b4940),width:selected?2:1)),
    child:Center(child:Text(symbol,style:TextStyle(fontSize:34,color:selected?const Color(0xff149eff):const Color(0xffff4040)))),
  );

  Widget _weapon(String icon,String label)=>SizedBox(width:54,child:Column(children:[Text(icon,style:const TextStyle(fontSize:24,color:Color(0xffffe3b2))),const SizedBox(height:3),Text(label,textAlign:TextAlign.center,style:const TextStyle(color:Colors.white,fontSize:9,height:1.1))]));

  Widget _stat(String label,double value)=>Row(children:[
    Expanded(child:ClipRRect(borderRadius:BorderRadius.circular(5),child:LinearProgressIndicator(value:value,minHeight:8,backgroundColor:const Color(0xff242323),color:const Color(0xffff5b21)))),const SizedBox(width:8),SizedBox(width:44,child:Text(label,style:const TextStyle(color:Colors.white,fontSize:11))),
  ]);

  Widget _bar(Color color,double value,String text)=>SizedBox(height:13,child:Stack(fit:StackFit.expand,children:[
    Container(decoration:BoxDecoration(color:const Color(0xff171717),border:Border.all(color:const Color(0xff5a574f)))),
    FractionallySizedBox(widthFactor:value,alignment:Alignment.centerLeft,child:ColoredBox(color:color)),
    Center(child:Text(text,style:const TextStyle(color:Colors.white,fontSize:8,shadows:[Shadow(color:Colors.black,blurRadius:2)]))),
  ]));

  Widget _roundIcon(String text)=>Container(
    width:31,height:31,margin:const EdgeInsets.only(left:3),decoration:BoxDecoration(color:const Color(0xcc2a251d),shape:BoxShape.circle,border:Border.all(color:const Color(0xff8e7b5d))),
    child:Center(child:Text(text,style:const TextStyle(fontSize:17))),
  );
}
