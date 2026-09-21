import 'package:flutter/material.dart';
import '../ui_asset.dart';
import '../shaiya_widgets.dart';

class FactionScreen extends StatelessWidget {
  final UiAssetCache ui;
  final String faction;
  final ValueChanged<String> onFaction;
  final VoidCallback onNext;
  const FactionScreen({
    super.key,
    required this.ui,
    required this.faction,
    required this.onFaction,
    required this.onNext,
  });

  DataImage image(String path,{BoxFit fit=BoxFit.contain})=>DataImage(
    cache:ui,
    path:path,
    fit:fit,
  );

  @override Widget build(BuildContext context)=>Stack(children:[
    Positioned.fill(child:image('interface/select_country_bg.jpg',fit:BoxFit.cover)),
    Positioned(
      left:8,top:192,width:505,height:320,
      child:Opacity(opacity:faction=='fury'?1:.42,child:image('interface/choose_fury.tga')),
    ),
    Positioned(
      left:510,top:192,width:505,height:320,
      child:Opacity(opacity:faction=='light'?1:.42,child:image('interface/choose_light.tga')),
    ),
    Positioned(
      left:0,top:178,width:1024,height:410,
      child:Row(children:[
        Expanded(child:GestureDetector(
          behavior:HitTestBehavior.translucent,
          onTap:()=>onFaction('fury'),
          child:const SizedBox.expand(),
        )),
        Expanded(child:GestureDetector(
          behavior:HitTestBehavior.translucent,
          onTap:()=>onFaction('light'),
          child:const SizedBox.expand(),
        )),
      ]),
    ),
    Positioned(
      left:32,top:445,
      child:Text(
        'Unión de la Furia',
        style:TextStyle(
          color:faction=='fury'?Colors.white:Colors.white70,
          fontSize:24,fontStyle:FontStyle.italic,
          shadows:const [Shadow(color:Colors.black,blurRadius:5)],
        ),
      ),
    ),
    Positioned(
      right:32,top:215,
      child:Text(
        'Alianza de la Luz',
        style:TextStyle(
          color:faction=='light'?Colors.white:Colors.white70,
          fontSize:24,fontStyle:FontStyle.italic,
          shadows:const [Shadow(color:Colors.black,blurRadius:5)],
        ),
      ),
    ),
    Positioned(
      left:355,top:520,width:320,
      child:Text(
        faction=='light'
          ?'¿Buscas el sendero de la luz? Entrega tu vida por el bien de los demás y avanza con honor.'
          :'La Unión de la Furia camina por un sendero oscuro y feroz. ¿Tienes la fuerza necesaria?',
        textAlign:TextAlign.center,
        style:const TextStyle(
          color:Colors.white,fontSize:10,height:1.35,
          shadows:[Shadow(color:Colors.black,blurRadius:3)],
        ),
      ),
    ),
    Positioned(left:763,top:706,child:shaiyaRedButton('Atrás',null)),
    Positioned(left:898,top:706,child:shaiyaRedButton('Siguiente',onNext)),
  ]);
}
