import 'package:flutter/material.dart';
import '../shaiya_widgets.dart';

class CharacterSelectScreen extends StatelessWidget {
  final bool created;
  final String name;
  final VoidCallback onCreate;
  final VoidCallback onDelete;
  final VoidCallback onStart;
  final VoidCallback onBack;

  const CharacterSelectScreen({
    super.key,
    required this.created,
    required this.name,
    required this.onCreate,
    required this.onDelete,
    required this.onStart,
    required this.onBack,
  });

  Widget card(int index)=>Container(
    width:330,
    height:112,
    margin:const EdgeInsets.only(bottom:14),
    padding:const EdgeInsets.symmetric(horizontal:16,vertical:12),
    decoration:BoxDecoration(
      border:Border.all(
        color:index==0&&created?const Color(0xff9f3e3a):const Color(0xff493d35),
      ),
      gradient:LinearGradient(
        colors:index==0&&created
          ?const [Color(0xcc641c1f),Color(0xcc1b0c0c)]
          :const [Color(0xcc160d0a),Color(0xcc0c0806)],
      ),
    ),
    child:index==0&&created
      ?Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[
          const Text('Lv. 1',style:TextStyle(fontSize:11)),
          const SizedBox(width:24),
          Expanded(child:Text(name,style:const TextStyle(fontSize:12))),
          const Text('Guerrero',style:TextStyle(fontSize:11)),
        ]),
        const Spacer(),
        const Text('Última ubicación : Erina',style:TextStyle(fontSize:10)),
        const SizedBox(height:6),
        const Text('Modo : BÁSICO',style:TextStyle(fontSize:10)),
      ])
      :const Center(
        child:Text(
          'Por favor crea un personaje.',
          style:TextStyle(fontSize:19,color:Color(0xffc9c5c0)),
        ),
      ),
  );

  @override Widget build(BuildContext context)=>Stack(children:[
    Positioned(
      left:48,top:48,width:330,height:620,
      child:Column(children:List.generate(5,card)),
    ),
    Positioned(left:94,top:668,child:shaiyaRedButton(
      'Crear personaje',onCreate,width:114,height:36,fontSize:11,
    )),
    Positioned(left:213,top:668,child:shaiyaRedButton(
      'Eliminar',created?onDelete:null,width:114,height:36,fontSize:11,
    )),
    Positioned(left:213,top:710,child:shaiyaRedButton(
      'Opciones',(){},width:114,height:36,fontSize:11,
    )),
    Positioned(left:598,top:678,child:shaiyaRedButton(
      'Inicio de Juego',created?onStart:null,width:247,height:61,fontSize:24,
    )),
    Positioned(
      left:10,top:706,
      child:IconButton(
        onPressed:onBack,
        icon:const Icon(Icons.arrow_back,color:Colors.white),
      ),
    ),
  ]);
}
