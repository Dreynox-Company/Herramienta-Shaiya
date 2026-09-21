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

  DataImage image(String path,{BoxFit fit=BoxFit.fill})=>DataImage(
    cache:ui,
    path:path,
    fit:fit,
  );

  Widget fullTexture(String path)=>Positioned(
    left:0,top:0,width:1024,height:1024,
    child:image(path,fit:BoxFit.fill),
  );

  @override Widget build(BuildContext context)=>ClipRect(
    child:Stack(clipBehavior:Clip.hardEdge,children:[
      fullTexture('interface/countryselect/bg.tga'),
      if(faction=='fury')fullTexture('interface/countryselect/fury_select.tga'),
      if(faction=='light')fullTexture('interface/countryselect/light_select.tga'),

      Positioned(
        left:0,top:185,width:512,height:335,
        child:GestureDetector(
          behavior:HitTestBehavior.translucent,
          onTap:()=>onFaction('fury'),
          child:const SizedBox.expand(),
        ),
      ),
      Positioned(
        left:512,top:185,width:512,height:335,
        child:GestureDetector(
          behavior:HitTestBehavior.translucent,
          onTap:()=>onFaction('light'),
          child:const SizedBox.expand(),
        ),
      ),

      const Positioned(
        left:31,top:438,
        child:Text(
          'Union of Fury',
          style:TextStyle(
            color:Colors.white,fontSize:23,fontStyle:FontStyle.italic,
            shadows:[Shadow(color:Colors.black,blurRadius:5)],
          ),
        ),
      ),
      const Positioned(
        right:31,top:202,
        child:Text(
          'Alliance of Light',
          style:TextStyle(
            color:Colors.white,fontSize:23,fontStyle:FontStyle.italic,
            shadows:[Shadow(color:Colors.black,blurRadius:5)],
          ),
        ),
      ),

      if(faction=='light')
        const Positioned(
          left:355,top:513,width:320,
          child:Text(
            'Seek you the Path of light?\n'
            'To give your life for the sake of another is the noblest of deeds.\n'
            'purify your heart, for the road ahead is dark and fraught with peril.\n\n'
            'Have you the strength?',
            textAlign:TextAlign.center,
            style:TextStyle(
              color:Colors.white,fontSize:10,height:1.35,
              shadows:[Shadow(color:Colors.black,blurRadius:3)],
            ),
          ),
        ),
      if(faction=='fury')
        const Positioned(
          left:355,top:528,width:320,
          child:Text(
            'The Union of Fury follows the path of strength.\n'
            'Only those prepared to fight for survival should proceed.\n\n'
            'Do you have the courage?',
            textAlign:TextAlign.center,
            style:TextStyle(
              color:Colors.white,fontSize:10,height:1.35,
              shadows:[Shadow(color:Colors.black,blurRadius:3)],
            ),
          ),
        ),

      Positioned(left:763,top:680,child:shaiyaRedButton('Back',null)),
      Positioned(left:898,top:680,child:shaiyaRedButton('Next',onNext)),
    ]),
  );
}
