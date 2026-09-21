import 'package:flutter/material.dart';
import '../ui_asset.dart';
import '../shaiya_widgets.dart';

class CharacterCreateScreen extends StatelessWidget {
  final UiAssetCache ui;
  final TextEditingController nameController;
  final int classIndex;
  final int genderIndex;
  final ValueChanged<int> onClass;
  final ValueChanged<int> onGender;
  final VoidCallback onBack;
  final VoidCallback onCreate;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onPause;
  final VoidCallback onReset;

  const CharacterCreateScreen({
    super.key,
    required this.ui,
    required this.nameController,
    required this.classIndex,
    required this.genderIndex,
    required this.onClass,
    required this.onGender,
    required this.onBack,
    required this.onCreate,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onPause,
    required this.onReset,
  });

  DataImage image(String path,{BoxFit fit=BoxFit.contain,Widget? fallback})=>DataImage(
    cache:ui,
    path:path,
    fit:fit,
    fallback:fallback,
  );

  Widget classButton(int i,String label,String asset)=>GestureDetector(
    onTap:()=>onClass(i),
    child:Container(
      width:88,height:78,
      decoration:BoxDecoration(
        border:Border.all(
          color:classIndex==i?const Color(0xffffd34e):const Color(0xff42392f),
          width:classIndex==i?2:1,
        ),
        color:const Color(0xaa1b1711),
      ),
      child:Stack(children:[
        Positioned.fill(child:image(asset,fallback:Center(child:Text(label,style:const TextStyle(fontSize:10))))),
        Positioned(left:0,right:0,bottom:3,child:Text(
          label,
          textAlign:TextAlign.center,
          style:const TextStyle(
            fontSize:11,color:Colors.white,
            shadows:[Shadow(color:Colors.black,blurRadius:2)],
          ),
        )),
      ]),
    ),
  );

  Widget genderButton(int value,IconData icon,String label)=>GestureDetector(
    onTap:()=>onGender(value),
    child:Container(
      width:56,height:54,alignment:Alignment.center,
      decoration:BoxDecoration(
        color:const Color(0xff1b1711),
        border:Border.all(
          color:genderIndex==value?const Color(0xffffd248):const Color(0xff55483b),
          width:2,
        ),
      ),
      child:Tooltip(
        message:label,
        child:Icon(
          icon,size:38,
          color:value==0?const Color(0xff00b8ff):const Color(0xffff5847),
        ),
      ),
    ),
  );

  Widget statLine(String label,double value)=>Padding(
    padding:const EdgeInsets.symmetric(vertical:6),
    child:Row(children:[
      SizedBox(
        width:55,
        child:Text(label,textAlign:TextAlign.right,style:const TextStyle(color:Colors.white,fontSize:11)),
      ),
      const SizedBox(width:8),
      Expanded(child:Container(
        height:8,color:const Color(0xff1b1b1b),
        child:FractionallySizedBox(
          alignment:Alignment.centerLeft,
          widthFactor:value,
          child:Container(
            decoration:const BoxDecoration(
              gradient:LinearGradient(colors:[Color(0xffff2b18),Color(0xffffae2b)]),
            ),
          ),
        ),
      )),
    ]),
  );

  Widget roundControl(IconData icon,VoidCallback tap)=>GestureDetector(
    onTap:tap,
    child:Container(
      width:27,height:27,
      decoration:BoxDecoration(
        shape:BoxShape.circle,
        color:const Color(0xffcf757d),
        border:Border.all(color:const Color(0xffffc1c6)),
      ),
      child:Icon(icon,size:17,color:Colors.white),
    ),
  );

  @override Widget build(BuildContext context)=>Stack(children:[
    Positioned(
      left:8,top:48,width:330,height:210,
      child:Container(
        padding:const EdgeInsets.all(22),
        decoration:BoxDecoration(
          color:const Color(0x99211914),
          border:Border.all(color:const Color(0xff66584c)),
        ),
        child:const SingleChildScrollView(
          child:Text(
            'El Guerrero es el combatiente cuerpo a cuerpo estándar. Sus ataques físicos y su amplia selección de armas permiten enfrentarse de frente a los enemigos.\n\nCaracterísticas:\n· Gran variedad de armas\n· Potentes ataques físicos',
            style:TextStyle(fontSize:12,color:Colors.white,height:1.45),
          ),
        ),
      ),
    ),
    Positioned(
      left:8,top:293,width:330,height:473,
      child:Container(
        padding:const EdgeInsets.fromLTRB(20,18,18,14),
        decoration:BoxDecoration(
          color:const Color(0xaa211914),
          border:Border.all(color:const Color(0xff66584c)),
        ),
        child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          const Row(children:[
            Text('Información básica',style:TextStyle(fontSize:12,color:Colors.white)),
            Spacer(),
            Text('Apariencia',style:TextStyle(fontSize:12,color:Colors.white70)),
            Spacer(),
            Text('Modo',style:TextStyle(fontSize:12,color:Colors.white70)),
          ]),
          const SizedBox(height:18),
          const Text('Nombre',style:TextStyle(color:Color(0xffffdc50),fontSize:11)),
          const SizedBox(height:5),
          SizedBox(
            height:31,
            child:TextField(
              controller:nameController,
              style:const TextStyle(fontSize:12),
              decoration:InputDecoration(
                filled:true,
                fillColor:const Color(0xdd111111),
                contentPadding:const EdgeInsets.symmetric(horizontal:10,vertical:8),
                border:OutlineInputBorder(borderRadius:BorderRadius.circular(2)),
              ),
            ),
          ),
          const SizedBox(height:17),
          const Text('Clase',style:TextStyle(color:Color(0xffffdc50),fontSize:11)),
          const SizedBox(height:8),
          Wrap(spacing:6,runSpacing:6,children:[
            classButton(0,'Guerrero','interface/charactermake/ta_2d_character_fighterm_select.tga'),
            classButton(1,'Defensor','interface/charactermake/ta_2d_character_defenderm_select.tga'),
            classButton(2,'Sacerdote','interface/charactermake/ta_2d_character_priestm_select.tga'),
            classButton(3,'Ranger','interface/charactermake/ta_2d_character_rangerm_select.tga'),
            classButton(4,'Arquero','interface/charactermake/ta_2d_character_archerm_select.tga'),
            classButton(5,'Mago','interface/charactermake/ta_2d_character_magem_select.tga'),
          ]),
          const SizedBox(height:12),
          const Text('Género',style:TextStyle(color:Color(0xffffdc50),fontSize:11)),
          const SizedBox(height:7),
          Row(children:[
            genderButton(0,Icons.male,'Masculino'),
            const SizedBox(width:10),
            genderButton(1,Icons.female,'Femenino'),
          ]),
          const Spacer(),
          Row(children:[
            shaiyaRedButton('Atrás',onBack,width:112,height:36,fontSize:11),
            const Spacer(),
            shaiyaRedButton('Crear',onCreate,width:112,height:36,fontSize:11),
          ]),
        ]),
      ),
    ),
    Positioned(
      right:18,top:60,width:270,height:435,
      child:Container(
        padding:const EdgeInsets.all(10),
        decoration:BoxDecoration(
          color:const Color(0x77140f0b),
          border:Border.all(color:const Color(0xff67594d)),
        ),
        child:Column(children:[
          const Align(
            alignment:Alignment.topRight,
            child:Text('Arma',style:TextStyle(color:Color(0xffffdf39),fontSize:11)),
          ),
          const SizedBox(height:8),
          const Wrap(spacing:10,runSpacing:9,children:[
            _WeaponGlyph(Icons.colorize,'espada'),
            _WeaponGlyph(Icons.gavel,'mandoble'),
            _WeaponGlyph(Icons.close,'doble'),
            _WeaponGlyph(Icons.horizontal_rule,'lanza'),
            _WeaponGlyph(Icons.handyman,'maza'),
            _WeaponGlyph(Icons.build,'martillo'),
            _WeaponGlyph(Icons.shield,'escudo'),
          ]),
          const Spacer(),
          const Align(
            alignment:Alignment.centerRight,
            child:Text('Perfil de clase',style:TextStyle(color:Color(0xffffdf39),fontSize:11)),
          ),
          const SizedBox(height:10),
          statLine('Solo',.82),
          statLine('Grupo',.66),
          const SizedBox(height:12),
          statLine('ATQ',.83),
          statLine('DEF',.62),
        ]),
      ),
    ),
    Positioned(
      left:710,top:570,
      child:Row(children:[
        roundControl(Icons.add,onZoomIn),
        const SizedBox(width:7),
        roundControl(Icons.remove,onZoomOut),
        const SizedBox(width:14),
        roundControl(Icons.pause,onPause),
        const SizedBox(width:7),
        roundControl(Icons.stop,onReset),
      ]),
    ),
  ]);
}

class _WeaponGlyph extends StatelessWidget {
  final IconData icon;
  final String label;
  const _WeaponGlyph(this.icon,this.label);
  @override Widget build(BuildContext context)=>SizedBox(
    width:52,height:60,
    child:Column(children:[
      Icon(icon,color:const Color(0xffffcf86),size:30),
      const SizedBox(height:2),
      Text(label,textAlign:TextAlign.center,style:const TextStyle(fontSize:8,color:Colors.white)),
    ]),
  );
}
