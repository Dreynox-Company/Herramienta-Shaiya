import 'package:flutter/material.dart';
import '../shaiya_widgets.dart';
import '../ui_asset.dart';

class CharacterSelectScreen extends StatelessWidget {
  final UiAssetCache ui;
  final bool created,pendingDelete;
  final String name,locale;
  final VoidCallback onCreate;
  final VoidCallback onDelete;
  final VoidCallback onStart;
  final VoidCallback onBack;

  const CharacterSelectScreen({
    super.key,
    required this.ui,
    required this.created,
    required this.pendingDelete,
    required this.name,
    required this.locale,
    required this.onCreate,
    required this.onDelete,
    required this.onStart,
    required this.onBack,
  });

  Widget _slotFrame(int index){
    final active=index==0&&created;
    final path=active
      ?'interface/characterselect/button/selectbtn_fi.tga'
      :'interface/characterselect/button/selectbtn_disable.tga';
    return DataRegion(
      cache:ui,
      path:path,
      sheetWidth:512,
      sheetHeight:512,
      source:const Rect.fromLTWH(0,0,334,118),
      width:330,
      height:112,
    );
  }

  Widget card(int index)=>SizedBox(
    width:330,
    height:112,
    child:Stack(children:[
      Positioned.fill(child:_slotFrame(index)),
      if(index==0&&created)
        Positioned(
          left:17,top:13,right:13,bottom:13,
          child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Row(children:[
              const Text('Lv. 1',style:TextStyle(fontSize:10,color:Colors.white)),
              const SizedBox(width:25),
              Expanded(child:Text(name,style:const TextStyle(fontSize:10,color:Color(0xff7cd7ff)))),
              Text(locale=='spn'?'Guerrero':'Fighter',style:const TextStyle(fontSize:10,color:Colors.white)),
            ]),
            const Spacer(),
            Text(locale=='spn'?'Última ubicación : Erina':'Last Location : Erina',style:const TextStyle(fontSize:9,color:Colors.white)),
            const SizedBox(height:8),
            Text(locale=='spn'?'Modo : BÁSICO':'Mode : BASIC',style:const TextStyle(fontSize:9,color:Colors.white)),
          ]),
        )
      else
        Center(
          child:Text(
            locale=='spn'?'Por favor crea un personaje.':'Please create a character.',
            style:TextStyle(
              fontSize:18,
              color:Color(0xffc7c2bc),
              shadows:[Shadow(color:Colors.black,blurRadius:3)],
            ),
          ),
        ),
    ]),
  );

  Widget _startButton()=>GestureDetector(
    onTap:created&&!pendingDelete?onStart:null,
    child:Opacity(
      opacity:created&&!pendingDelete?1:.55,
      child:DataRegion(
        cache:ui,
        path:'interface/characterselect/button/select_start_${locale=='spn'?'spn':'usa'}.tga',
        sheetWidth:256,
        sheetHeight:256,
        source:Rect.fromLTWH(4,created&&!pendingDelete?2:130,246,60),
        width:247,
        height:61,
        fallback:shaiyaRedButton(
          locale=='spn'?'Inicio de Juego':'Game Start',
          created&&!pendingDelete?onStart:null,
          width:247,
          height:61,
          fontSize:24,
        ),
      ),
    ),
  );

  @override Widget build(BuildContext context)=>Stack(children:[
    Positioned(
      left:48,top:22,width:330,height:620,
      child:Column(
        children:[
          for(var i=0;i<5;i++)...[
            card(i),
            if(i<4)const SizedBox(height:14),
          ],
        ],
      ),
    ),
    Positioned(
      left:94,top:642,
      child:shaiyaRedButton(
        locale=='spn'?'Crear personaje':'Create Character',onCreate,width:114,height:36,fontSize:11,
      ),
    ),
    Positioned(
      left:213,top:642,
      child:shaiyaRedButton(
        pendingDelete
          ?(locale=='spn'?'Restaurar':'Restore')
          :(locale=='spn'?'Eliminar':'Delete Character'),
        created?onDelete:null,width:114,height:36,fontSize:11,
      ),
    ),
    Positioned(
      left:213,top:684,
      child:shaiyaRedButton(locale=='spn'?'Opciones':'Option Setting',(){},width:114,height:36,fontSize:11),
    ),
    Positioned(left:598,top:652,child:_startButton()),
    Positioned(
      left:10,top:680,
      child:IconButton(
        onPressed:onBack,
        icon:const Icon(Icons.arrow_back,color:Colors.white),
      ),
    ),
  ]);
}
