import 'package:flutter/material.dart';
import '../ui_asset.dart';
import '../shaiya_widgets.dart';

class FactionScreen extends StatelessWidget {
  final UiAssetCache ui;
  final String faction,locale;
  final ValueChanged<String> onFaction;
  final VoidCallback onNext;
  const FactionScreen({
    super.key,
    required this.ui,
    required this.faction,
    required this.locale,
    required this.onFaction,
    required this.onNext,
  });

  String get lang=>locale=='spn'?'spn':'usa';

  DataImage image(String path,{BoxFit fit=BoxFit.fill,Widget? fallback})=>DataImage(
    cache:ui,path:path,fit:fit,fallback:fallback,
  );

  Widget fullTexture(String path)=>Positioned(
    left:0,top:0,width:1024,height:1024,
    child:image(path,fit:BoxFit.fill),
  );

  Widget nameTexture(String side)=>Positioned(
    // Native ps0032 draws these 512×64 source textures at half scale.
    left:side=='fury'?31:746,
    top:side=='fury'?462:224,
    width:256,height:32,
    child:image(
      'interface/countryselect/text/${side}normal_$lang.tga',
      fit:BoxFit.fill,
      fallback:Align(
        alignment:side=='fury'?Alignment.centerLeft:Alignment.centerRight,
        child:Padding(
          padding:const EdgeInsets.symmetric(horizontal:30),
          child:Text(
            side=='fury'
              ?(lang=='spn'?'Unión de la Furia':'Union of Fury')
              :(lang=='spn'?'Alianza de la Luz':'Alliance of Light'),
            style:const TextStyle(
              color:Colors.white,fontSize:23,fontStyle:FontStyle.italic,
              shadows:[Shadow(color:Colors.black,blurRadius:5)],
            ),
          ),
        ),
      ),
    ),
  );

  Widget descriptionTexture(String side)=>Positioned(
    // 1024×256 source sheet is presented as a 512×128 native text plate.
    left:256,top:505,width:512,height:128,
    child:image(
      'interface/countryselect/text/${side}select_$lang.tga',
      fit:BoxFit.fill,
      fallback:Center(
        child:SizedBox(
          width:520,
          child:Text(
            side=='light'
              ?(lang=='spn'
                ?'¿Buscas el camino de la luz?\nDar tu vida por otro es el más noble de los sacrificios.\nPurifica tu corazón, pues el camino que tienes por delante es oscuro y peligroso.\n\n¿Tienes la fuerza?'
                :'Seek you the Path of light?\nTo give your life for the sake of another is the noblest of deeds.\npurify your heart, for the road ahead is dark and fraught with peril.\n\nHave you the strength?')
              :(lang=='spn'
                ?'La Unión de la Furia sigue el camino de la fuerza.\nSolo quienes estén preparados para luchar por sobrevivir deben continuar.\n\n¿Tienes el valor?'
                :'The Union of Fury follows the path of strength.\nOnly those prepared to fight for survival should proceed.\n\nDo you have the courage?'),
            textAlign:TextAlign.center,
            style:const TextStyle(
              color:Colors.white,fontSize:10,height:1.35,
              shadows:[Shadow(color:Colors.black,blurRadius:3)],
            ),
          ),
        ),
      ),
    ),
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

      nameTexture('fury'),
      nameTexture('light'),
      descriptionTexture(faction),

      Positioned(left:763,top:680,child:shaiyaRedButton(lang=='spn'?'Atrás':'Back',null)),
      Positioned(left:898,top:680,child:shaiyaRedButton(lang=='spn'?'Siguiente':'Next',onNext)),
    ]),
  );
}
