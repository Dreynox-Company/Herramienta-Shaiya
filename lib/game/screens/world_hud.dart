import 'package:flutter/material.dart';

import '../../data/catalog.dart';
import '../../render/studio_scene.dart';
import '../shaiya_widgets.dart';
import '../ui_asset.dart';

class WorldHud extends StatelessWidget {
  final StudioScene scene;
  final Catalog catalog;
  final String characterName,locale;
  final UiAssetCache ui;
  final List<String> messages;
  final bool questOpen;
  final int questId;
  final VoidCallback onAcceptQuest;
  final VoidCallback onCancelQuest;

  const WorldHud({
    super.key,
    required this.scene,
    required this.catalog,
    required this.characterName,
    required this.locale,
    required this.ui,
    required this.messages,
    required this.questOpen,
    required this.questId,
    required this.onAcceptQuest,
    required this.onCancelQuest,
  });

  @override
  Widget build(BuildContext context) => Stack(
        children: [
          Positioned(left: 8, top: 3, width: 216, height: 79, child: _playerHud()),
          Positioned(left: 318, top: 5, width: 420, height: 48, child: _topHotbar()),
          Positioned(right: 8, top: 8, width: 188, height: 232, child: _minimap()),
          Positioned(left: 4, top: 363, width: 360, height: 290, child: _chat()),
          Positioned(left: 0, right: 0, bottom: 0, height: 58, child: _bottomHud()),
          ..._worldLabels(),
          if (questOpen)
            Positioned(
              left: 566,
              top: 118,
              width: 247,
              height: 505,
              child: _questWindow(),
            ),
        ],
      );

  List<Widget> _worldLabels(){
    final labels=scene.projectGameLabels(1024,742);
    return labels.map((label){
      final color=label.mob?const Color(0xffffec3b):const Color(0xff58d7ff);
      return Positioned(
        left:(label.x-90).clamp(0.0,844.0),
        top:(label.y-30).clamp(0.0,680.0),
        width:180,
        child:IgnorePointer(
          child:Column(mainAxisSize:MainAxisSize.min,children:[
            if(label.quest)
              const Text(
                '!',
                style:TextStyle(
                  color:Color(0xffffff26),
                  fontSize:22,
                  fontWeight:FontWeight.w900,
                  height:.8,
                  shadows:[Shadow(color:Colors.black,blurRadius:3)],
                ),
              ),
            Text(
              label.text,
              maxLines:1,
              overflow:TextOverflow.ellipsis,
              textAlign:TextAlign.center,
              style:TextStyle(
                color:color,
                fontSize:10,
                fontWeight:FontWeight.w600,
                shadows:const [
                  Shadow(color:Colors.black,offset:Offset(1,1),blurRadius:2),
                  Shadow(color:Colors.black,offset:Offset(-1,-1),blurRadius:2),
                ],
              ),
            ),
          ]),
        ),
      );
    }).toList();
  }

  Widget _playerHud()=>Stack(children:[
    Positioned.fill(
      child:DataImage(
        cache:ui,
        path:'interface/main_stats_bar_bg.tga',
        fit:BoxFit.fill,
      ),
    ),
    Positioned(
      left:5,top:12,width:48,height:48,
      child:DataRegion(
        cache:ui,
        path:'interface/create_fighter_button.tga',
        sheetWidth:256,
        sheetHeight:64,
        source:const Rect.fromLTWH(0,0,64,64),
        width:48,height:48,
        fallback:const Icon(Icons.sports_martial_arts,color:Color(0xffffae3a),size:34),
      ),
    ),
    Positioned(
      left:61,top:23,width:148,height:48,
      child:DataImage(
        cache:ui,
        path:'interface/main_stats_bar.tga',
        fit:BoxFit.fill,
      ),
    ),
    const Positioned(
      left:63,top:7,
      child:Text('1',style:TextStyle(fontSize:10,color:Colors.white)),
    ),
    Positioned(
      left:93,top:6,right:8,
      child:Text(
        characterName,
        style:const TextStyle(
          color:Color(0xffffed3b),
          fontSize:12,
          shadows:[Shadow(color:Colors.black,blurRadius:2)],
        ),
      ),
    ),
    const Positioned(
      left:83,top:28,
      child:Text('255 / 255',style:TextStyle(fontSize:8,color:Colors.white)),
    ),
    const Positioned(
      left:84,top:42,
      child:Text('95 / 95',style:TextStyle(fontSize:8,color:Colors.white)),
    ),
    const Positioned(
      left:82,top:57,
      child:Text('180 / 180',style:TextStyle(fontSize:8,color:Colors.white)),
    ),
  ]);

  Widget _topHotbar()=>Stack(children:[
    Positioned.fill(
      child:DataImage(
        cache:ui,
        path:'interface/main_slot_3.tga',
        fit:BoxFit.fill,
      ),
    ),
    Positioned(
      left:18,top:8,
      child:Row(children:[
        Container(
          width:29,height:29,
          alignment:Alignment.center,
          child:const Icon(Icons.auto_fix_high,color:Color(0xffffe09a),size:22),
        ),
        const SizedBox(width:10),
        Container(
          width:29,height:29,
          alignment:Alignment.center,
          child:const Icon(Icons.healing,color:Color(0xffffe09a),size:21),
        ),
      ]),
    ),
  ]);

  Widget _minimap() => Stack(
        children: [
          Positioned.fill(
            child: DataImage(
              cache: ui,
              path: 'interface/main_map.tga',
              fit: BoxFit.fill,
            ),
          ),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0x33201b15),
              border: Border.all(color: const Color(0xff8f8264)),
            ),
            child: Column(
              children: [
                Expanded(
                  child: Stack(children:[
                    Positioned.fill(
                      child:DataImage(
                        cache:ui,
                        path:'interface/minimap/1.tga',
                        fit:BoxFit.fill,
                      ),
                    ),
                    Positioned.fill(
                      child:CustomPaint(
                        painter:_MiniMapPainter(scene),
                        child:const SizedBox.expand(),
                      ),
                    ),
                  ]),
                ),
                Row(
                  children: [
                    const Text(
                      '+  −',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      scene.originX.round().toString() +
                          ' ' +
                          scene.originZ.round().toString(),
                      style: const TextStyle(
                        fontSize: 9,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      );

  Widget _chat()=>Stack(children:[
    Positioned.fill(
      child:DataImage(
        cache:ui,
        path:'interface/chat/chat.tga',
        fit:BoxFit.fill,
      ),
    ),
    const Positioned(
      left:18,top:12,
      child:Text(
        'World',
        style:TextStyle(
          fontSize:13,
          color:Colors.white,
          shadows:[Shadow(color:Colors.black,blurRadius:2)],
        ),
      ),
    ),
    Positioned(
      left:12,top:52,right:20,bottom:10,
      child:ListView(
        reverse:true,
        padding:EdgeInsets.zero,
        children:messages.take(12).map((m)=>Padding(
          padding:const EdgeInsets.only(bottom:5),
          child:Text(
            m,
            style:const TextStyle(
              fontSize:10,
              color:Colors.white,
              shadows:[Shadow(color:Colors.black,blurRadius:2)],
            ),
          ),
        )).toList(),
      ),
    ),
  ]);

  Widget _bottomButton(String path)=>DataRegion(
    cache:ui,
    path:path,
    sheetWidth:256,
    sheetHeight:64,
    source:const Rect.fromLTWH(0,0,64,64),
    width:31,
    height:31,
  );

  Widget _bottomHud()=>Stack(children:[
    Positioned.fill(
      child:DataImage(
        cache:ui,
        path:'interface/main_bottom.tga',
        fit:BoxFit.fill,
      ),
    ),
    Positioned(
      left:14,right:14,top:3,height:12,
      child:DataImage(
        cache:ui,
        path:'interface/skillbar_bg.tga',
        fit:BoxFit.fill,
      ),
    ),
    const Positioned(
      left:250,right:250,top:0,
      child:Center(
        child:Text('0,0%',style:TextStyle(fontSize:9,color:Colors.white70)),
      ),
    ),
    Positioned(
      right:7,bottom:1,
      child:Row(children:[
        _bottomButton('interface/main_bottom_btn_status.tga'),
        _bottomButton('interface/main_bottom_btn_skill.tga'),
        _bottomButton('interface/main_bottom_btn_item.tga'),
        _bottomButton('interface/main_bottom_btn_quest.tga'),
        _bottomButton('interface/main_bottom_btn_sub.tga'),
        _bottomButton('interface/main_bottom_btn_guild.tga'),
        _bottomButton('interface/main_bottom_btn_shop.tga'),
        _bottomButton('interface/main_bottom_btn_option.tga'),
        _bottomButton('interface/main_bottom_btn_event.tga'),
        _bottomButton('interface/main_bottom_btn_helper.tga'),
      ]),
    ),
  ]);

  Widget _questWindow() {
    final text=catalog.questText(locale)?.quest(questId);
    final title=text!=null&&text.name.isNotEmpty?text.name:'Operación básica de la interfaz';
    final body=text!=null&&text.initialDescription.isNotEmpty
      ?text.initialDescription
      :'Aprende a moverte, reconocer la interfaz y hablar con los habitantes de la zona.';

    return Stack(children:[
      Positioned.fill(
        child:DataImage(
          cache:ui,
          path:'interface/quest/take.tga',
          fit:BoxFit.fill,
          fallback:DataImage(cache:ui,path:'interface/quest/quest.tga',fit:BoxFit.fill),
        ),
      ),
      Positioned(
        left:29,top:28,right:24,
        child:Text(
          title,
          maxLines:1,
          overflow:TextOverflow.ellipsis,
          style:const TextStyle(
            color:Color(0xffffdf69),
            fontSize:11,
            fontWeight:FontWeight.bold,
            shadows:[Shadow(color:Colors.black,blurRadius:2)],
          ),
        ),
      ),
      Positioned(
        left:18,top:62,right:18,height:254,
        child:SingleChildScrollView(
          child:Text(
            body,
            style:const TextStyle(
              color:Color(0xff321d11),
              fontSize:10,
              height:1.44,
              shadows:[Shadow(color:Color(0x22000000),blurRadius:1)],
            ),
          ),
        ),
      ),
      Positioned(
        left:18,top:333,
        child:Text(
          locale=='spn'?'Objeto de recompensa':'Reward item',
          style:const TextStyle(
            color:Color(0xff321d11),
            fontSize:10,
            fontWeight:FontWeight.w600,
          ),
        ),
      ),
      Positioned(
        left:19,top:356,width:39,height:39,
        child:Stack(children:[
          Positioned.fill(
            child:DataImage(
              cache:ui,
              path:'interface/quest/itemslot.tga',
              fit:BoxFit.fill,
              fallback:DecoratedBox(
                decoration:BoxDecoration(
                  color:const Color(0x66d9cfb6),
                  border:Border.all(color:const Color(0xff6a4b2d)),
                ),
              ),
            ),
          ),
          const Center(
            child:Icon(Icons.auto_awesome,color:Color(0xff6e5ac8),size:20),
          ),
        ]),
      ),
      Positioned(
        left:35,right:35,bottom:18,
        child:Row(
          mainAxisAlignment:MainAxisAlignment.spaceBetween,
          children:[
            shaiyaRedButton(locale=='spn'?'Aceptar':'Accept',onAcceptQuest,width:65,height:28,fontSize:10),
            shaiyaRedButton(locale=='spn'?'Cancelar':'Cancel',onCancelQuest,width:65,height:28,fontSize:10),
          ],
        ),
      ),
    ]);
  }

}

class _MiniMapPainter extends CustomPainter {
  final StudioScene scene;
  _MiniMapPainter(this.scene);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0x5535452b),
    );

    for (final a in scene.gameActors) {
      final x = (a.root.position.x / 120 + .5).clamp(0.0, 1.0);
      final y = (a.root.position.z / 120 + .5).clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(x * size.width, y * size.height),
        2.2,
        Paint()..color = const Color(0xffff3f27),
      );
    }

    canvas.drawCircle(
      Offset(size.width * .5, size.height * .5),
      4,
      Paint()..color = const Color(0xffffdf2f),
    );
    canvas.drawCircle(
      Offset(size.width * .5, size.height * .5),
      7,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _MiniMapPainter oldDelegate) => true;
}
