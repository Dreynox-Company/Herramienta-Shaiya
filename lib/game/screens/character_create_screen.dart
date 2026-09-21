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
    cache:ui,path:path,fit:fit,fallback:fallback,
  );

  Widget classButton(int i,String label,String path){
    final row=classIndex==i?3:0;
    return GestureDetector(
      onTap:()=>onClass(i),
      child:SizedBox(
        width:92,height:80,
        child:Stack(children:[
          Positioned(
            left:0,top:0,
            child:DataRegion(
              cache:ui,
              path:path,
              sheetWidth:128,
              sheetHeight:512,
              source:Rect.fromLTWH(1,row*128+1,95,80),
              width:92,
              height:78,
            ),
          ),
          Positioned(
            left:0,right:0,bottom:2,
            child:Text(
              label,
              textAlign:TextAlign.center,
              style:const TextStyle(
                fontSize:10,
                color:Colors.white,
                shadows:[Shadow(color:Colors.black,blurRadius:3)],
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget genderButton(int value,String path,String label){
    final row=genderIndex==value?3:0;
    return GestureDetector(
      onTap:()=>onGender(value),
      child:Tooltip(
        message:label,
        child:DataRegion(
          cache:ui,
          path:path,
          sheetWidth:64,
          sheetHeight:256,
          source:Rect.fromLTWH(1,row*64,57,62),
          width:56,
          height:54,
        ),
      ),
    );
  }

  Widget navButton(String path,VoidCallback tap)=>GestureDetector(
    onTap:tap,
    child:DataRegion(
      cache:ui,
      path:path,
      sheetWidth:32,
      sheetHeight:256,
      source:const Rect.fromLTWH(0,0,32,38),
      width:32,
      height:38,
    ),
  );

  Widget statLine(double value)=>Container(
    height:8,
    color:const Color(0xff1b1b1b),
    child:FractionallySizedBox(
      alignment:Alignment.centerLeft,
      widthFactor:value,
      child:Container(
        decoration:const BoxDecoration(
          gradient:LinearGradient(colors:[Color(0xffff2b18),Color(0xffffae2b)]),
        ),
      ),
    ),
  );

  Widget weapon(String icon,String text)=>SizedBox(
    width:61,
    height:78,
    child:Column(children:[
      image('interface/charactermake/classinfo/$icon',fit:BoxFit.contain),
      const SizedBox(height:1),
      SizedBox(
        width:61,height:16,
        child:image('interface/charactermake/classinfo/text/$text',fit:BoxFit.contain),
      ),
    ]),
  );

  @override Widget build(BuildContext context)=>Stack(children:[
    // Explicación: la escena 3D select_A.wld queda visible detrás, como en ps0032.
    Positioned(
      left:8,top:48,width:330,height:210,
      child:Container(
        padding:const EdgeInsets.fromLTRB(24,18,22,18),
        decoration:BoxDecoration(
          color:const Color(0x99140f0b),
          border:Border.all(color:const Color(0xff756759)),
        ),
        child:const SingleChildScrollView(
          child:Text(
            'El Guerrero es el combatiente cuerpo a cuerpo estándar. De cerca y en combate personal es como mejor rinde.\n\nEl poder de ataque físico es su especialidad; sus habilidades consumen SP.\n\nCaracterísticas:\n· Gran variedad de armas\n· Potentes ataques físicos',
            style:TextStyle(fontSize:11,color:Colors.white,height:1.55),
          ),
        ),
      ),
    ),

    // Panel izquierdo original, recortado de la hoja 512x512.
    Positioned(
      left:8,top:293,width:330,height:473,
      child:Stack(children:[
        Positioned.fill(
          child:DataRegion(
            cache:ui,
            path:'interface/charactermake/basicinfo_bg.tga',
            sheetWidth:512,
            sheetHeight:512,
            source:const Rect.fromLTWH(0,0,334,466),
            width:330,
            height:473,
          ),
        ),
        Positioned(
          left:20,top:16,right:18,bottom:14,
          child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            const Row(children:[
              Text('Información básica',style:TextStyle(fontSize:11,color:Colors.white)),
              Spacer(),
              Text('Apariencia',style:TextStyle(fontSize:11,color:Colors.white70)),
              Spacer(),
              Text('Modo',style:TextStyle(fontSize:11,color:Colors.white70)),
            ]),
            const SizedBox(height:18),
            const Text('Nombre',style:TextStyle(color:Color(0xffffdc50),fontSize:10)),
            const SizedBox(height:4),
            Row(children:[
              Expanded(
                child:SizedBox(
                  height:28,
                  child:TextField(
                    controller:nameController,
                    style:const TextStyle(fontSize:11),
                    decoration:InputDecoration(
                      filled:true,
                      fillColor:const Color(0xdd101010),
                      contentPadding:const EdgeInsets.symmetric(horizontal:9,vertical:6),
                      border:OutlineInputBorder(borderRadius:BorderRadius.circular(2)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width:8),
              shaiyaRedButton('Comprobar',(){},width:88,height:29,fontSize:9),
            ]),
            const SizedBox(height:13),
            const Text('Clase',style:TextStyle(color:Color(0xffffdc50),fontSize:10)),
            const SizedBox(height:6),
            Wrap(spacing:4,runSpacing:4,children:[
              classButton(0,'Guerrero','interface/charactermake/button/fighter_worrior.tga'),
              classButton(1,'Defensor','interface/charactermake/button/defender_guardian.tga'),
              classButton(2,'Sacerdote','interface/charactermake/button/priest_oracle.tga'),
              classButton(3,'Ranger','interface/charactermake/button/ranger_assassin.tga'),
              classButton(4,'Arquero','interface/charactermake/button/archer_hunter.tga'),
              classButton(5,'Mago','interface/charactermake/button/mage_pagan.tga'),
            ]),
            const SizedBox(height:8),
            const Text('Género',style:TextStyle(color:Color(0xffffdc50),fontSize:10)),
            const SizedBox(height:5),
            Row(children:[
              genderButton(0,'interface/charactermake/button/sexm.tga','Masculino'),
              const SizedBox(width:7),
              genderButton(1,'interface/charactermake/button/sexw.tga','Femenino'),
            ]),
            const Spacer(),
            Row(children:[
              shaiyaRedButton('Atrás',onBack,width:112,height:36,fontSize:10),
              const Spacer(),
              shaiyaRedButton('Crear',onCreate,width:112,height:36,fontSize:10),
            ]),
          ]),
        ),
      ]),
    ),

    // Panel de armas y perfil de clase con las texturas originales.
    Positioned(
      right:6,top:60,width:280,height:435,
      child:Stack(children:[
        Positioned.fill(
          child:DataRegion(
            cache:ui,
            path:'interface/charactermake/classinfo/bg.tga',
            sheetWidth:512,
            sheetHeight:512,
            source:const Rect.fromLTWH(0,0,288,440),
            width:280,
            height:435,
          ),
        ),
        Positioned(
          left:12,top:8,right:12,bottom:10,
          child:Column(children:[
            const Align(
              alignment:Alignment.topRight,
              child:Text('Arma',style:TextStyle(color:Color(0xffffdf39),fontSize:10)),
            ),
            const SizedBox(height:5),
            Wrap(spacing:4,runSpacing:1,children:[
              weapon('icon_onehandedsword.tga','icon_onehandedsword_spn.tga'),
              weapon('icon_twohandedsword.tga','icon_twohandedsword_spn.tga'),
              weapon('icon_dualwieldsword.tga','icon_dualwieldsword_spn.tga'),
              weapon('icon_spear.tga','icon_spear_spn.tga'),
              weapon('icon_onehandedblunt.tga','icon_onehandedblunt_spn.tga'),
              weapon('icon_twohandedblunt.tga','icon_twohandedblunt_spn.tga'),
              weapon('icon_shield.tga','icon_shield_spn.tga'),
            ]),
            const Spacer(),
            const Align(
              alignment:Alignment.centerRight,
              child:Text('Perfil de clase',style:TextStyle(color:Color(0xffffdf39),fontSize:10)),
            ),
            const SizedBox(height:8),
            Row(children:[
              SizedBox(
                width:64,height:64,
                child:image('interface/charactermake/classinfo/text/info_bg01_spn.tga',fit:BoxFit.contain),
              ),
              const SizedBox(width:5),
              Expanded(child:Column(children:[
                statLine(.82),
                const SizedBox(height:20),
                statLine(.66),
              ])),
            ]),
            const SizedBox(height:6),
            Row(children:[
              SizedBox(
                width:64,height:64,
                child:image('interface/charactermake/classinfo/text/info_bg02_spn.tga',fit:BoxFit.contain),
              ),
              const SizedBox(width:5),
              Expanded(child:Column(children:[
                statLine(.83),
                const SizedBox(height:20),
                statLine(.62),
              ])),
            ]),
          ]),
        ),
      ]),
    ),

    Positioned(
      left:711,top:582,
      child:Row(children:[
        navButton('interface/charactermake/button/navi_zoomin.tga',onZoomIn),
        const SizedBox(width:5),
        navButton('interface/charactermake/button/navi_zoomout.tga',onZoomOut),
        const SizedBox(width:12),
        navButton('interface/charactermake/button/navi_play.tga',onPause),
        const SizedBox(width:5),
        navButton('interface/charactermake/button/navi_stop.tga',onReset),
      ]),
    ),
  ]);
}
