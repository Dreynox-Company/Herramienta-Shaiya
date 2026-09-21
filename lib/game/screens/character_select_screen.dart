import 'package:flutter/material.dart';
import '../shaiya_widgets.dart';
import '../ui_asset.dart';

class CharacterSelectScreen extends StatelessWidget {
  final UiAssetCache ui;
  final bool created;
  final String name;
  final VoidCallback onCreate;
  final VoidCallback onDelete;
  final VoidCallback onStart;
  final VoidCallback onBack;

  const CharacterSelectScreen({
    super.key,
    required this.ui,
    required this.created,
    required this.name,
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
              const Text('Guerrero',style:TextStyle(fontSize:10,color:Colors.white)),
            ]),
            const Spacer(),
            const Text('Última ubicación : Erina',style:TextStyle(fontSize:9,color:Colors.white)),
            const SizedBox(height:8),
            const Text('Modo : BÁSICO',style:TextStyle(fontSize:9,color:Colors.white)),
          ]),
        )
      else
        const Center(
          child:Text(
            'Por favor crea un personaje.',
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
    onTap:created?onStart:null,
    child:Opacity(
      opacity:created?1:.78,
      child:DataRegion(
        cache:ui,
        path:'interface/characterselect/button/select_start_spn.tga',
        sheetWidth:256,
        sheetHeight:256,
        source:Rect.fromLTWH(4,created?2:130,246,60),
        width:247,
        height:61,
        fallback:shaiyaRedButton(
          'Inicio de Juego',
          created?onStart:null,
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
        'Crear personaje',onCreate,width:114,height:36,fontSize:11,
      ),
    ),
    Positioned(
      left:213,top:642,
      child:shaiyaRedButton(
        'Eliminar',created?onDelete:null,width:114,height:36,fontSize:11,
      ),
    ),
    Positioned(
      left:213,top:684,
      child:shaiyaRedButton('Opciones',(){},width:114,height:36,fontSize:11),
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
