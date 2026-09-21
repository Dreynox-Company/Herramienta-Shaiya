import 'package:flutter/material.dart';
import '../ui_asset.dart';
import '../shaiya_widgets.dart';

class ServerSelectScreen extends StatelessWidget {
  final UiAssetCache ui;
  final VoidCallback onNext;
  final VoidCallback onQuit;
  const ServerSelectScreen({
    super.key,
    required this.ui,
    required this.onNext,
    required this.onQuit,
  });

  @override Widget build(BuildContext context)=>Stack(children:[
    const Positioned.fill(child:ColoredBox(color:Colors.black)),
    Positioned(
      left:0,top:51,width:1024,height:640,
      child:DataImage(cache:ui,path:'interface/login/bg.tga',fit:BoxFit.fill),
    ),
    Positioned(
      left:343,top:115,width:338,height:488,
      child:DataRegion(
        cache:ui,
        path:'interface/serverselect/ta_2d_server.tga',
        sheetWidth:512,sheetHeight:512,
        source:const Rect.fromLTWH(0,0,338,488),
        width:338,height:488,
      ),
    ),
    Positioned(
      left:384,top:125,width:256,height:32,
      child:DataImage(
        cache:ui,
        path:'interface/serverselect/text/maintitle_spn.tga',
        fit:BoxFit.fill,
      ),
    ),
    Positioned(
      left:371,top:180,width:290,height:46,
      child:DataRegion(
        cache:ui,
        path:'interface/serverselect/ta_2d_server_list.tga',
        sheetWidth:512,sheetHeight:64,
        source:const Rect.fromLTWH(0,0,290,46),
        width:290,height:46,
      ),
    ),
    Positioned(
      left:380,top:193,width:271,height:22,
      child:DataRegion(
        cache:ui,
        path:'interface/serverselect/mark.tga',
        sheetWidth:512,sheetHeight:32,
        source:const Rect.fromLTWH(0,0,271,22),
        width:271,height:22,
      ),
    ),
    const Positioned(
      left:392,top:191,width:165,height:24,
      child:Align(
        alignment:Alignment.centerLeft,
        child:Text(
          'Partida local',
          style:TextStyle(
            color:Colors.white,fontSize:11,
            shadows:[Shadow(color:Colors.black,blurRadius:2)],
          ),
        ),
      ),
    ),
    const Positioned(
      left:579,top:191,width:58,height:24,
      child:Center(child:Text(
        'Normal',
        style:TextStyle(color:Color(0xffd5e97b),fontSize:9),
      )),
    ),
    Positioned(
      left:414,top:538,
      child:shaiyaRedButton('Cancelar',onQuit,width:96,height:34,fontSize:10),
    ),
    Positioned(
      left:516,top:538,
      child:shaiyaRedButton('Aceptar',onNext,width:96,height:34,fontSize:10),
    ),
  ]);
}
