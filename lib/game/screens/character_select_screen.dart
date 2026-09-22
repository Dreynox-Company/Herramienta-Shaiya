import 'package:flutter/material.dart';
import '../ps0032_protocol.dart';
import '../shaiya_widgets.dart';
import '../ui_asset.dart';

class CharacterSelectScreen extends StatelessWidget {
  final UiAssetCache ui;
  final List<PsCharacterSlot> slots;
  final int? selectedSlot;
  final String locale;
  final ValueChanged<PsCharacterSlot> onSelect;
  final VoidCallback onCreate,onDelete,onRestore,onRename,onStart,onBack;

  const CharacterSelectScreen({
    super.key,
    required this.ui,
    required this.slots,
    required this.selectedSlot,
    required this.locale,
    required this.onSelect,
    required this.onCreate,
    required this.onDelete,
    required this.onRestore,
    required this.onRename,
    required this.onStart,
    required this.onBack,
  });

  PsCharacterSlot? _slot(int index)=>slots.where((x)=>x.slot==index).firstOrNull;
  PsCharacterSlot? get selected=>selectedSlot==null?null:_slot(selectedSlot!);
  bool get canStart=>selected?.exists==true&&selected?.isDelete!=true;
  bool get canCreate=>slots.where((x)=>x.exists).length<5;

  String _profession(int value){
    const es=<int,String>{0:'Guerrero',1:'Defensor',2:'Ranger',3:'Arquero',4:'Mago',5:'Sacerdote'};
    const en=<int,String>{0:'Fighter',1:'Defender',2:'Ranger',3:'Archer',4:'Mage',5:'Priest'};
    return (locale=='spn'?es:en)[value]??(locale=='spn'?'Clase $value':'Class $value');
  }

  Widget _slotFrame(int index,PsCharacterSlot? slot){
    final active=slot?.exists==true&&selectedSlot==index;
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

  Widget card(int index){
    final slot=_slot(index),exists=slot?.exists==true,deleted=slot?.isDelete==true;
    final body=SizedBox(
      width:330,
      height:112,
      child:Stack(children:[
        Positioned.fill(child:_slotFrame(index,slot)),
        if(exists)
          Positioned(
            left:17,top:13,right:13,bottom:13,
            child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Row(children:[
                Text('Lv. ${slot!.level}',style:TextStyle(fontSize:10,color:deleted?const Color(0xffff8d81):Colors.white)),
                const SizedBox(width:25),
                Expanded(child:Text(
                  slot.name,
                  maxLines:1,overflow:TextOverflow.ellipsis,
                  style:TextStyle(fontSize:10,color:deleted?const Color(0xffff8d81):const Color(0xff7cd7ff)),
                )),
                Text(_profession(slot.profession),style:const TextStyle(fontSize:10,color:Colors.white)),
              ]),
              const Spacer(),
              Text(
                deleted
                  ?(locale=='spn'?'Eliminado · disponible para restaurar':'Deleted · available to restore')
                  :(locale=='spn'?'Última ubicación : Mapa ${slot.mapId}':'Last Location : Map ${slot.mapId}'),
                style:TextStyle(fontSize:9,color:deleted?const Color(0xffff8d81):Colors.white),
              ),
              const SizedBox(height:5),
              Row(children:[
                Text(
                  (locale=='spn'?'Modo : ':'Mode : ')+(slot.mode>=3?(locale=='spn'?'MÁXIMO':'ULTIMATE'):(locale=='spn'?'BÁSICO':'BASIC')),
                  style:const TextStyle(fontSize:9,color:Colors.white),
                ),
                const Spacer(),
                if(slot.isRename&&!deleted)
                  Text(locale=='spn'?'RENOMBRAR':'RENAME',style:const TextStyle(fontSize:8,color:Color(0xffffd45f))),
              ]),
            ]),
          )
        else
          Center(
            child:Text(
              locale=='spn'?'Por favor crea un personaje.':'Please create a character.',
              style:const TextStyle(
                fontSize:18,
                color:Color(0xffc7c2bc),
                shadows:[Shadow(color:Colors.black,blurRadius:3)],
              ),
            ),
          ),
      ]),
    );
    return exists?GestureDetector(onTap:()=>onSelect(slot!),child:body):body;
  }

  Widget _startButton()=>GestureDetector(
    onTap:canStart?onStart:null,
    child:Opacity(
      opacity:canStart?1:.78,
      child:DataRegion(
        cache:ui,
        path:'interface/characterselect/button/select_start_${locale=='spn'?'spn':'usa'}.tga',
        sheetWidth:256,
        sheetHeight:256,
        source:Rect.fromLTWH(4,canStart?2:130,246,60),
        width:247,
        height:61,
        fallback:shaiyaRedButton(
          locale=='spn'?'Inicio de Juego':'Game Start',
          canStart?onStart:null,
          width:247,
          height:61,
          fontSize:24,
        ),
      ),
    ),
  );

  @override Widget build(BuildContext context){
    final current=selected;
    return Stack(children:[
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
          locale=='spn'?'Crear personaje':'Create Character',
          canCreate?onCreate:null,width:114,height:36,fontSize:11,
        ),
      ),
      Positioned(
        left:213,top:642,
        child:shaiyaRedButton(
          current?.isDelete==true
            ?(locale=='spn'?'Restaurar':'Restore')
            :(locale=='spn'?'Eliminar':'Delete Character'),
          current==null?null:(current.isDelete?onRestore:onDelete),
          width:114,height:36,fontSize:11,
        ),
      ),
      if(current?.isRename==true&&current?.isDelete!=true)
        Positioned(
          left:332,top:642,
          child:shaiyaRedButton(
            locale=='spn'?'Renombrar':'Rename',onRename,width:114,height:36,fontSize:11,
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
}
