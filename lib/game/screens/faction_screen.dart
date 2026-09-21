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

  @override Widget build(BuildContext context){
    final light=faction=='light';
    return Stack(children:[
      const Positioned.fill(child:ColoredBox(color:Colors.black)),
      // El cliente original compone un lado "over" con el lado seleccionado.
      // Se reutilizan exactamente los fondos de 1920x1200 del DATA y se
      // muestran a 1024x640, igual que el ps0032 a 1024x768.
      Positioned(
        left:0,top:0,width:1024,height:640,
        child:image(
          light?'interface/ta_2d_country_fury_over.tga':'interface/ta_2d_country_light_over.tga',
          fit:BoxFit.fill,
        ),
      ),
      Positioned(
        left:0,top:0,width:1024,height:640,
        child:image(
          light?'interface/ta_2d_country_light_select.tga':'interface/ta_2d_country_fury_select.tga',
          fit:BoxFit.fill,
        ),
      ),

      // Cubrir el texto de idioma embebido en algunos fondos antiguos y
      // superponer los rótulos españoles originales del mismo DATA.
      Positioned(left:12,top:405,width:360,height:70,child:ColoredBox(color:Colors.black.withValues(alpha:.78))),
      Positioned(right:10,top:175,width:360,height:70,child:ColoredBox(color:Colors.black.withValues(alpha:.78))),
      Positioned(
        left:18,top:418,width:300,height:38,
        child:image(
          light?'interface/countryselect/text/furynormal_spn.tga':'interface/countryselect/text/furyover_spn.tga',
          fit:BoxFit.contain,
        ),
      ),
      Positioned(
        right:18,top:188,width:300,height:38,
        child:image(
          light?'interface/countryselect/text/lightover_spn.tga':'interface/countryselect/text/lightnormal_spn.tga',
          fit:BoxFit.contain,
        ),
      ),
      Positioned(left:265,top:493,width:500,height:105,child:ColoredBox(color:Colors.black.withValues(alpha:.88))),
      Positioned(
        left:0,top:430,width:1024,height:256,
        child:image(
          light?'interface/countryselect/text/lightselect_spn.tga':'interface/countryselect/text/furyselect_spn.tga',
          fit:BoxFit.fill,
        ),
      ),

      // Zonas interactivas coincidentes con las dos mitades del original.
      Positioned(
        left:0,top:170,width:512,height:330,
        child:GestureDetector(
          behavior:HitTestBehavior.translucent,
          onTap:()=>onFaction('fury'),
          child:const SizedBox.expand(),
        ),
      ),
      Positioned(
        left:512,top:170,width:512,height:330,
        child:GestureDetector(
          behavior:HitTestBehavior.translucent,
          onTap:()=>onFaction('light'),
          child:const SizedBox.expand(),
        ),
      ),

      Positioned(left:763,top:706,child:shaiyaRedButton('Atrás',null)),
      Positioned(left:898,top:706,child:shaiyaRedButton('Siguiente',onNext)),
    ]);
  }
}
