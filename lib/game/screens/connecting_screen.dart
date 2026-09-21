import 'package:flutter/material.dart';
import '../ui_asset.dart';
import '../shaiya_widgets.dart';

class ConnectingScreen extends StatelessWidget {
  final UiAssetCache ui;
  final VoidCallback onQuit;
  const ConnectingScreen({super.key,required this.ui,required this.onQuit});

  @override Widget build(BuildContext context)=>Stack(children:[
    const Positioned.fill(child:ColoredBox(color:Colors.black)),
    Positioned(
      left:0,top:51,width:1024,height:640,
      child:DataImage(
        cache:ui,
        path:'interface/login/bg.tga',
        fit:BoxFit.fill,
      ),
    ),
    const Positioned(
      left:450,top:489,width:125,height:20,
      child:Center(child:Text(
        'Connecting...',
        style:TextStyle(
          fontSize:9,color:Colors.white,
          shadows:[Shadow(color:Colors.black,blurRadius:3)],
        ),
      )),
    ),
    Positioned(
      left:858,top:608,
      child:shaiyaRedButton('Quit Game',onQuit,width:115,height:38,fontSize:11),
    ),
  ]);
}
