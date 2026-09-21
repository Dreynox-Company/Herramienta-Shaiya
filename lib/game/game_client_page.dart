import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:three_js/three_js.dart' as three;
import '../data/catalog.dart';
import '../data/library.dart';
import '../input/viewport_movement_input.dart';
import '../render/studio_scene.dart';

class GameClientPage extends StatefulWidget {
  final String? initialData;
  const GameClientPage({super.key, this.initialData});
  @override State<GameClientPage> createState()=>_GameClientPageState();
}

class _GameClientPageState extends State<GameClientPage> {
  late final StudioScene scene;
  late final three.ThreeJS renderer;
  final focus=FocusNode();
  Catalog? catalog;
  bool loading=true,questOpen=true;
  String progress='Inicializando cliente Flutter…';
  final messages=<String>['[Notice] Laboratorio local','Bienvenido a Dreynox Shaiya Flutter Client.'];
  double gestureScale=1;

  @override void initState(){
    super.initState();
    scene=StudioScene((s){if(mounted)setState(()=>progress=s);});
    renderer=three.ThreeJS(
      settings:three.Settings(clearColor:0x000000,antialias:true,enableShadowMap:false,toneMapping:three.NoToneMapping),
      setup:()=>scene.setup(renderer),
      onSetupComplete:(){if(widget.initialData!=null){unawaited(connect(widget.initialData!));}else{setState(()=>loading=false);}},
    );
    scene.addListener(_refresh);
  }
  void _refresh(){if(mounted)setState((){});}
  @override void dispose(){scene.removeListener(_refresh);scene.dispose();renderer.dispose();focus.dispose();super.dispose();}

  Future<void> chooseData() async {
    setState(()=>loading=true);
    try{
      final lib=await Library.choose((s){if(mounted)setState(()=>progress=s);});
      if(lib==null){setState(()=>loading=false);return;}
      await _connectLibrary(lib);
    }catch(e){setState((){loading=false;progress='$e';});}
  }

  Future<void> connect(String path) async {
    setState(()=>loading=true);
    try{
      final lib=await Library.fromDirectory(path,(s){if(mounted)setState(()=>progress=s);});
      await _connectLibrary(lib);
    }catch(e){setState((){loading=false;progress='$e';});}
  }

  Future<void> _connectLibrary(Library lib) async {
    final c=Catalog(lib);
    await c.load((s){if(mounted)setState(()=>progress=s);});
    scene.catalog=c;
    final archetype=c.archetypes.where((x)=>x.id.toLowerCase()=='humf').firstOrNull??c.archetypes.first;
    await scene.setAppearance(Appearance.initial(archetype));
    String? world;
    for(final p in c.worlds){
      final n=baseName(p).toLowerCase();
      if(n=='1.wld'||n=='01.wld'||n=='map1.wld'){world=p;break;}
    }
    world??=c.worlds.isEmpty?null:c.worlds.first;
    if(world!=null){try{await scene.setWorld(world);}catch(e){messages.insert(0,'[Mapa] $e');}}
    scene.yaw=math.pi;scene.pitch=.12;scene.distance=7.8;scene.targetY=1.2;scene.updateCamera();
    final svmap=await _loadSvmap();
    if(svmap!=null){await scene.spawnGameActorsFromSvmap(svmap);}else{await scene.spawnGameNpcs(count:10);}
    catalog=c;
    messages.insert(0,'[Sistema] \${c.npcs.length} NPC · \${c.creatures.length} criaturas · \${c.worlds.length} mapas indexados.');
    setState(()=>loading=false);
    focus.requestFocus();
  }

  Future<SvmapData?> _loadSvmap() async {
    final exe=File(Platform.resolvedExecutable).parent.path;
    final cwd=Directory.current.path;
    final candidates=<String>[
      '$exe/server/maps/1.svmap',
      '$exe/servicios/world/config/maps/1.svmap',
      '$cwd/server/maps/1.svmap',
      '$cwd/servicios/world/config/maps/1.svmap',
    ];
    for(final path in candidates){
      final file=File(path);
      if(!await file.exists())continue;
      try{
        final data=SvmapData.parse(await file.readAsBytes(),path);
        messages.insert(0,'[Mapa] SVMAP real: ${data.npcs.length} NPC · ${data.mobAreas.length} áreas de criaturas.');
        return data;
      }catch(e){messages.insert(0,'[SVMAP] $e');}
    }
    messages.insert(0,'[Mapa] Sin 1.svmap del backend; usando población visual de respaldo.');
    return null;
  }
  Future<void> attack(int index) async {
    if(index<scene.attackClips.length){
      try{await scene.attack();}catch(e){messages.insert(0,'[Combate] $e');setState((){});}
    }
  }

  Widget gameViewport()=>Stack(children:[
    Positioned.fill(child:renderer.build()),
    Positioned.fill(child:ViewportMovementInput(
      focusNode:focus,
      onChanged:(x,z,run)=>scene.setMovement(x,z,run:run),
      onAction:(key){
        final keys=[LogicalKeyboardKey.digit1,LogicalKeyboardKey.digit2,LogicalKeyboardKey.digit3,LogicalKeyboardKey.digit4];
        final i=keys.indexOf(key);if(i>=0)unawaited(attack(i));if(key==LogicalKeyboardKey.keyR)scene.resetCombat();
      },
      child:Listener(
        onPointerSignal:(e){if(e is PointerScrollEvent)scene.zoom(e.scrollDelta.dy>0?1.08:1/1.08);},
        child:GestureDetector(
          behavior:HitTestBehavior.opaque,onTap:focus.requestFocus,
          onScaleStart:(_){gestureScale=1;focus.requestFocus();},
          onScaleUpdate:(d){if(d.pointerCount==1)scene.orbit(d.focalPointDelta.dx,d.focalPointDelta.dy);else{scene.zoom(gestureScale/d.scale);gestureScale=d.scale;}},
          child:const SizedBox.expand(),
        ),
      ),
    )),
  ]);

  BoxDecoration panel([double opacity=.86])=>BoxDecoration(color:const Color(0xff13100c).withOpacity(opacity),border:Border.all(color:const Color(0xff81705a)),boxShadow:const [BoxShadow(color:Colors.black54,blurRadius:8)]);
  Widget bar(Color color,double value,{double height=10})=>ClipRRect(borderRadius:BorderRadius.circular(1),child:Container(height:height,color:Colors.black87,child:FractionallySizedBox(alignment:Alignment.centerLeft,widthFactor:value.clamp(0,1),child:DecoratedBox(decoration:BoxDecoration(gradient:LinearGradient(colors:[color.withOpacity(.72),color,Colors.white.withOpacity(.22)]))))));

  Widget characterHud()=>Positioned(top:8,left:8,child:Container(width:218,padding:const EdgeInsets.all(5),decoration:panel(.78),child:Row(children:[
    Container(width:48,height:48,decoration:BoxDecoration(color:const Color(0xff5d231d),border:Border.all(color:const Color(0xffc49d58))),child:const Icon(Icons.local_fire_department,color:Color(0xffffb04a),size:32)),
    const SizedBox(width:6),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[Container(width:22,height:17,alignment:Alignment.center,color:const Color(0xff2a2a2a),child:const Text('1',style:TextStyle(fontSize:10))),const SizedBox(width:3),const Expanded(child:Text('DreynoxLocal',style:TextStyle(color:Color(0xffffea4d),fontSize:13,shadows:[Shadow(color:Colors.black,blurRadius:2)])))]),
      const SizedBox(height:2),bar(const Color(0xffdd201d),1,height:8),const SizedBox(height:1),bar(const Color(0xff276bff),1,height:8),const SizedBox(height:1),bar(const Color(0xffffc516),1,height:8),
    ]))
  ])));

  Widget topHotbar()=>Positioned(top:8,left:230,right:310,child:Align(alignment:Alignment.topLeft,child:Row(mainAxisSize:MainAxisSize.min,children:List.generate(10,(i)=>Container(
    width:42,height:42,margin:const EdgeInsets.only(right:2),decoration:BoxDecoration(color:const Color(0xb5201d18),border:Border.all(color:i<2?const Color(0xffc9ab67):const Color(0xff615749))),
    child:Stack(children:[Center(child:Icon(i==0?Icons.auto_fix_high:i==1?Icons.healing:Icons.circle_outlined,size:24,color:i<2?const Color(0xffffd98a):const Color(0xff8e8578))),Positioned(top:1,left:3,child:Text('\${(i+1)%10}',style:const TextStyle(fontSize:9,color:Colors.white70)))]),
  )))));

  Widget minimap()=>Positioned(top:8,right:8,child:Container(width:250,height:238,decoration:panel(.88),padding:const EdgeInsets.all(4),child:Column(children:[
    Expanded(child:ClipRect(child:CustomPaint(painter:_MiniMapPainter(scene),child:const SizedBox.expand()))),const SizedBox(height:3),
    Row(children:[_squareIcon(Icons.add),const SizedBox(width:3),_squareIcon(Icons.remove),const Spacer(),const Icon(Icons.place,color:Color(0xffffdd55),size:18),const SizedBox(width:4),Text('\${scene.originX.round()} · \${scene.originZ.round()}',style:const TextStyle(fontSize:11,color:Color(0xffded7bd)))])
  ])));
  Widget _squareIcon(IconData i)=>Container(width:22,height:20,decoration:BoxDecoration(color:const Color(0xff4d4a3e),border:Border.all(color:const Color(0xffa49670))),child:Icon(i,size:15,color:Colors.white70));

  Widget chat()=>Positioned(left:7,bottom:45,child:Container(width:365,height:170,decoration:const BoxDecoration(color:Color(0x22000000)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:5),decoration:BoxDecoration(color:const Color(0x99150f0b),border:Border.all(color:const Color(0xff7a6545))),child:const Text('World',style:TextStyle(fontSize:13,color:Colors.white))),
    Expanded(child:ListView(padding:const EdgeInsets.fromLTRB(8,8,8,4),reverse:true,children:messages.take(8).map((m)=>Padding(padding:const EdgeInsets.only(bottom:4),child:Text(m,style:const TextStyle(fontSize:11,color:Color(0xfff0e8d6),shadows:[Shadow(color:Colors.black,blurRadius:2)]))).toList()))
  ])));

  Widget questWindow()=>Positioned(top:145,right:270,child:Container(width:310,height:500,decoration:BoxDecoration(border:Border.all(color:const Color(0xff2d1a10),width:3),boxShadow:const [BoxShadow(color:Colors.black87,blurRadius:12)],gradient:const LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,colors:[Color(0xffc69a67),Color(0xff8b6039)])),child:Column(children:[
    Container(height:42,padding:const EdgeInsets.symmetric(horizontal:12),color:const Color(0xff4b2819),child:const Row(children:[Icon(Icons.priority_high,color:Color(0xffffdc43),size:20),SizedBox(width:7),Text('Operación básica de la interfaz',style:TextStyle(color:Color(0xffffe780),fontSize:13,fontWeight:FontWeight.w600))])),
    Expanded(child:Padding(padding:const EdgeInsets.all(15),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Text('¿Nos hemos visto antes? En tiempos difíciles, aprender a moverte y reconocer tu interfaz puede salvarte la vida. Camina con W A S D, gira la cámara y acércate a los habitantes de la zona.',style:TextStyle(color:Color(0xff27180f),fontSize:12,height:1.55)),
      const SizedBox(height:20),const Divider(color:Color(0xff624326)),const Text('Objetivo',style:TextStyle(color:Color(0xff3b2113),fontWeight:FontWeight.bold)),const SizedBox(height:8),
      Text('Explora el mapa local y localiza los \${scene.gameActors.length} NPC/criaturas cargados desde DATA.',style:const TextStyle(color:Color(0xff29180f),fontSize:12)),
      const Spacer(),const Text('Recompensa',style:TextStyle(color:Color(0xff3b2113),fontWeight:FontWeight.bold)),const SizedBox(height:8),
      Container(width:36,height:36,decoration:BoxDecoration(color:const Color(0xffd9d0ba),border:Border.all(color:const Color(0xff49311e))),child:const Icon(Icons.auto_awesome,color:Color(0xff6c5ac7))),
    ]))),
    Padding(padding:const EdgeInsets.all(12),child:Row(mainAxisAlignment:MainAxisAlignment.center,children:[_questButton('Aceptar',(){setState(()=>questOpen=false);messages.insert(0,'[Misión] Operación básica aceptada.');}),const SizedBox(width:24),_questButton('Cancelar',()=>setState(()=>questOpen=false))]))
  ])));
  Widget _questButton(String text,VoidCallback f)=>InkWell(onTap:f,child:Container(width:78,height:31,alignment:Alignment.center,decoration:BoxDecoration(gradient:const LinearGradient(colors:[Color(0xff812b28),Color(0xff471715)]),border:Border.all(color:const Color(0xffd6a36d)),borderRadius:BorderRadius.circular(3)),child:Text(text,style:const TextStyle(fontSize:11,color:Colors.white))));

  Widget bottomBar()=>Positioned(left:0,right:0,bottom:0,child:Column(children:[
    Container(height:14,decoration:BoxDecoration(color:const Color(0xcc30291e),border:Border.all(color:const Color(0xff8e7c5d))),child:Stack(children:[const Center(child:Text('0,0%',style:TextStyle(color:Colors.white70,fontSize:10))),FractionallySizedBox(widthFactor:.03,child:Container(color:const Color(0xffb98d4f)))])),
    Container(height:35,color:const Color(0xb30d0d0d),child:Align(alignment:Alignment.centerRight,child:Padding(padding:const EdgeInsets.only(right:8),child:Row(mainAxisSize:MainAxisSize.min,children:[for(final icon in [Icons.book,Icons.inventory_2,Icons.backpack,Icons.description,Icons.pan_tool,Icons.emoji_events,Icons.chat_bubble,Icons.sports_martial_arts,Icons.settings,Icons.card_giftcard])Container(width:31,height:31,margin:const EdgeInsets.only(left:2),decoration:BoxDecoration(color:const Color(0xff6a4b35),border:Border.all(color:const Color(0xffc19a63)),shape:BoxShape.circle),child:Icon(icon,size:18,color:const Color(0xffffe3a8)))]))))
  ]));

  Widget loadingOverlay()=>Positioned.fill(child:ColoredBox(color:const Color(0xdd05070b),child:Center(child:Container(width:440,padding:const EdgeInsets.all(26),decoration:panel(.97),child:Column(mainAxisSize:MainAxisSize.min,children:[
    const Text('DREYNOX SHAIYA',style:TextStyle(fontSize:28,color:Color(0xffffd05d),fontWeight:FontWeight.w700,letterSpacing:1.5)),const SizedBox(height:7),const Text('Flutter Game Client · laboratorio de compatibilidad',style:TextStyle(color:Colors.white60)),const SizedBox(height:24),
    if(loading)...[const CircularProgressIndicator(strokeWidth:2),const SizedBox(height:15),Text(progress,textAlign:TextAlign.center,style:const TextStyle(fontSize:11,color:Colors.white70))]
    else...[Text(progress,textAlign:TextAlign.center,style:const TextStyle(fontSize:11,color:Colors.white70)),const SizedBox(height:18),FilledButton.icon(onPressed:chooseData,icon:const Icon(Icons.folder_open),label:const Text('Seleccionar DATA_Español'))]
  ])))));

  @override Widget build(BuildContext context){
    final active=catalog!=null&&scene.character!=null;
    return Scaffold(backgroundColor:Colors.black,body:Stack(children:[
      Positioned.fill(child:gameViewport()),
      if(active)...[
        characterHud(),topHotbar(),minimap(),chat(),bottomBar(),
        if(questOpen)questWindow(),
        const Positioned(left:390,bottom:52,child:IgnorePointer(child:Text('DreynoxLocal',style:TextStyle(fontSize:11,color:Colors.white,shadows:[Shadow(color:Colors.black,blurRadius:3)])))),
      ],
      if(!active)loadingOverlay(),
      if(loading&&active)Positioned(top:58,left:8,child:Container(padding:const EdgeInsets.all(8),decoration:panel(.9),child:Row(mainAxisSize:MainAxisSize.min,children:[const SizedBox(width:14,height:14,child:CircularProgressIndicator(strokeWidth:2)),const SizedBox(width:8),Text(progress,style:const TextStyle(fontSize:10))])))
    ]));
  }
}

class _MiniMapPainter extends CustomPainter {
  final StudioScene scene;
  _MiniMapPainter(this.scene);
  @override void paint(Canvas canvas,Size size){
    canvas.drawRect(Offset.zero&size,Paint()..color=const Color(0xff31452a));
    canvas.drawOval(Rect.fromCenter(center:Offset(size.width*.68,size.height*.28),width:size.width*.42,height:size.height*.25),Paint()..color=const Color(0xff446e7c));
    final road=Paint()..color=const Color(0xff87784d)..strokeWidth=10..style=PaintingStyle.stroke;
    final p=Path()..moveTo(size.width*.05,size.height*.86)..cubicTo(size.width*.35,size.height*.6,size.width*.45,size.height*.7,size.width*.9,size.height*.18);canvas.drawPath(p,road);
    final npc=Paint()..color=const Color(0xffff3a22);
    for(final a in scene.gameActors){final x=(a.root.position.x/28+.5).clamp(0.0,1.0),y=(a.root.position.z/28+.5).clamp(0.0,1.0);canvas.drawCircle(Offset(x*size.width,y*size.height),3,npc);}
    canvas.drawCircle(Offset(size.width*.5,size.height*.5),4,Paint()..color=Colors.white);
    canvas.drawCircle(Offset(size.width*.5,size.height*.5),7,Paint()..color=const Color(0xffffd428)..style=PaintingStyle.stroke..strokeWidth=2);
  }
  @override bool shouldRepaint(covariant _MiniMapPainter oldDelegate)=>true;
}
