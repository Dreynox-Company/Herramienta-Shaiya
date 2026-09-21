import 'package:flutter/material.dart';

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
      decoration:BoxDecoration(
        borderRadius:BorderRadius.circular(3),
        border:Border.all(color:const Color(0xff8b554f)),
        gradient:const LinearGradient(
          begin:Alignment.topCenter,
          end:Alignment.bottomCenter,
          colors:[Color(0xff8d3938),Color(0xff401719)],
        ),
        boxShadow:const [BoxShadow(color:Colors.black54,blurRadius:3)],
      ),
      child:Text(
        label,
        style:TextStyle(
          fontSize:fontSize,
          color:Colors.white,
          shadows:const [Shadow(color:Colors.black,blurRadius:2)],
        ),
      ),
    ),
  ),
);

Widget shaiyaBar(Color color,double value,{double height=9})=>Container(
  height:height,
  decoration:BoxDecoration(
    color:Colors.black,
    border:Border.all(color:const Color(0xffc7b78e)),
  ),
  child:FractionallySizedBox(
    alignment:Alignment.centerLeft,
    widthFactor:value.clamp(0,1),
    child:Container(color:color),
  ),
);
