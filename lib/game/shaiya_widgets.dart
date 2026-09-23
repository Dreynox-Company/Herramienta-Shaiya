import 'package:flutter/material.dart';
import 'dreynox_game_theme.dart';

Widget shaiyaRedButton(
  String label,
  VoidCallback? onTap, {
  double width=112,
  double height=38,
  double fontSize=12,
}) => Opacity(
  opacity:onTap==null ? .55 : 1,
  child:GestureDetector(
    onTap:onTap,
    child:Container(
      width:width,
      height:height,
      alignment:Alignment.center,
      decoration:DreynoxGameStyle.buttonDecoration(active:onTap!=null),
      child:Text(
        label,
        style:TextStyle(
          fontSize:fontSize,
          color:DreynoxGameStyle.text,
          shadows:const [Shadow(color:Colors.black,blurRadius:2)],
        ),
      ),
    ),
  ),
);

Widget shaiyaBar(Color color,double value,{double height=9})=>Container(
  height:height,
  decoration:BoxDecoration(
    color:const Color(0xb0061020),
    border:Border.all(color:DreynoxGameStyle.border),
  ),
  child:FractionallySizedBox(
    alignment:Alignment.centerLeft,
    widthFactor:value.clamp(0,1),
    child:Container(color:color),
  ),
);
