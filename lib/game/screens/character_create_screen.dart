import 'package:flutter/material.dart';
import '../ui_asset.dart';
import '../shaiya_widgets.dart';

class CharacterCreateScreen extends StatelessWidget {
  final UiAssetCache ui;
  final TextEditingController nameController;
  final int classIndex;
  final int genderIndex;
  final int tabIndex;
  final int faceIndex;
  final int hairIndex;
  final int modeIndex;
  final ValueChanged<int> onClass;
  final ValueChanged<int> onGender;
  final ValueChanged<int> onTab;
  final ValueChanged<int> onFace;
  final ValueChanged<int> onHair;
  final ValueChanged<int> onMode;
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
    required this.tabIndex,
    required this.faceIndex,
    required this.hairIndex,
    required this.modeIndex,
    required this.onClass,
    required this.onGender,
    required this.onTab,
    required this.onFace,
    required this.onHair,
    required this.onMode,
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


  String get appearanceCode=>genderIndex==0?'hum':'huf';

  Widget tabButton(int index,String text)=>GestureDetector(
    onTap:()=>onTab(index),
    child:Container(
      width:index==0?91:95,
      height:31,
      alignment:Alignment.center,
      decoration:BoxDecoration(
        gradient:LinearGradient(colors:tabIndex==index
          ?const [Color(0xff574630),Color(0xff221c15)]
          :const [Color(0xff302b24),Color(0xff161411)]),
        border:Border.all(color:tabIndex==index?const Color(0xffaf8b4d):const Color(0xff595149)),
      ),
      child:Text(text,style:TextStyle(fontSize:10,color:tabIndex==index?const Color(0xffffecad):Colors.white70)),
    ),
  );

  Widget baseInfoContent()=>Padding(
    padding:const EdgeInsets.fromLTRB(20,14,18,14),
    child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Text('Name',style:TextStyle(color:Color(0xffffdc50),fontSize:10)),
      const SizedBox(height:4),
      Row(children:[
        Expanded(child:SizedBox(height:28,child:TextField(
          controller:nameController,
          style:const TextStyle(fontSize:11),
          decoration:InputDecoration(
            filled:true,fillColor:const Color(0xdd101010),
            contentPadding:const EdgeInsets.symmetric(horizontal:9,vertical:6),
            border:OutlineInputBorder(borderRadius:BorderRadius.circular(2)),
          ),
        ))),
        const SizedBox(width:8),
        shaiyaRedButton('Name Check',(){},width:88,height:29,fontSize:9),
      ]),
      const SizedBox(height:13),
      const Text('Class',style:TextStyle(color:Color(0xffffdc50),fontSize:10)),
      const SizedBox(height:6),
      Wrap(spacing:4,runSpacing:4,children:[
        classButton(0,'Fighter','interface/charactermake/button/fighter_worrior.tga'),
        classButton(1,'Defender','interface/charactermake/button/defender_guardian.tga'),
        classButton(2,'Priest','interface/charactermake/button/priest_oracle.tga'),
        classButton(3,'Ranger','interface/charactermake/button/ranger_assassin.tga'),
        classButton(4,'Archer','interface/charactermake/button/archer_hunter.tga'),
        classButton(5,'Mage','interface/charactermake/button/mage_pagan.tga'),
      ]),
      const SizedBox(height:8),
      const Text('Gender',style:TextStyle(color:Color(0xffffdc50),fontSize:10)),
      const SizedBox(height:5),
      Row(children:[
        genderButton(0,'interface/charactermake/button/sexm.tga','Male'),
        const SizedBox(width:7),
        genderButton(1,'interface/charactermake/button/sexw.tga','Female'),
      ]),
    ]),
  );

  Widget appearanceChoice(String title,bool face)=>Column(
    crossAxisAlignment:CrossAxisAlignment.start,
    children:[
      Text(title,style:const TextStyle(color:Color(0xffffdc50),fontSize:10)),
      const SizedBox(height:8),
      Row(
        mainAxisAlignment:MainAxisAlignment.spaceBetween,
        children:List.generate(5,(i){
          final selected=(face?faceIndex:hairIndex)==i;
          final path='interface/charactermake/appearance/create_appearance_${appearanceCode}_${face?'face':'hair'}0${i+1}.tga';
          return GestureDetector(
            onTap:()=>face?onFace(i):onHair(i),
            child:Container(
              width:52,height:52,padding:const EdgeInsets.all(2),
              decoration:BoxDecoration(
                color:const Color(0xaa121212),
                border:Border.all(color:selected?const Color(0xffffdd55):const Color(0xff5f5549),width:selected?2:1),
              ),
              child:image(path,fit:BoxFit.cover),
            ),
          );
        }),
      ),
    ],
  );

  Widget appearanceContent()=>Padding(
    padding:const EdgeInsets.fromLTRB(18,18,18,14),
    child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      appearanceChoice('Face',true),
      const SizedBox(height:26),
      appearanceChoice('Hair',false),
      const Spacer(),
      const Text(
        'Face and hair are applied to the actual MLT pieces of the active 3D archetype.',
        style:TextStyle(fontSize:9,color:Colors.white60,height:1.4),
      ),
    ]),
  );

  Widget modeCard(int index,String path)=>GestureDetector(
    onTap:()=>onMode(index),
    child:DataRegion(
      cache:ui,
      path:path,
      sheetWidth:512,
      sheetHeight:512,
      source:Rect.fromLTWH(0,(modeIndex==index?3:0)*128,318,128),
      width:308,
      height:127,
    ),
  );

  Widget modeContent()=>Padding(
    padding:const EdgeInsets.fromLTRB(11,31,11,8),
    child:Column(children:[
      modeCard(0,'interface/charactermake/button/mode_basic.tga'),
      const SizedBox(height:14),
      modeCard(1,'interface/charactermake/button/mode_ultimate.tga'),
      const Spacer(),
    ]),
  );

  Widget leftPanel()=>Positioned(
    left:8,top:267,width:330,height:473,
    child:Stack(children:[
      Positioned.fill(child:DataRegion(
        cache:ui,
        path:tabIndex==0
          ?'interface/charactermake/basicinfo_bg.tga'
          :tabIndex==1
            ?'interface/charactermake/appearance_bg.tga'
            :'interface/charactermake/mode_bg.tga',
        sheetWidth:512,sheetHeight:512,
        source:const Rect.fromLTWH(0,0,334,466),
        width:330,height:473,
      )),
      Positioned(left:28,top:0,child:Row(children:[
        tabButton(0,'Basic Info'),
        tabButton(1,'Appearance'),
        tabButton(2,'Mode'),
      ])),
      Positioned(left:0,top:31,right:0,bottom:54,child:switch(tabIndex){
        1=>appearanceContent(),
        2=>modeContent(),
        _=>baseInfoContent(),
      }),
      Positioned(
        left:20,right:18,bottom:13,
        child:Row(children:[
          shaiyaRedButton('Back',onBack,width:112,height:36,fontSize:10),
          const Spacer(),
          shaiyaRedButton('Create',onCreate,width:112,height:36,fontSize:10),
        ]),
      ),
    ]),
  );

  @override Widget build(BuildContext context)=>Stack(children:[
    Positioned(
      left:8,top:22,width:330,height:210,
      child:Container(
        padding:const EdgeInsets.fromLTRB(24,18,22,18),
        decoration:BoxDecoration(
          color:const Color(0x99140f0b),
          border:Border.all(color:const Color(0xff756759)),
        ),
        child:SingleChildScrollView(
          child:Text(
            tabIndex==2
              ?(modeIndex==0
                ?'It requires low level of Experience and will allow you to level up fast.\n\nAlso, character will not be deleted on death, so you may play safer.'
                :'Ultimate mode grants more Status and Skill Points, but is intended for experienced players and a more demanding adventure.')
              :'The Fighter is your standard melee combatant. Up close and personal is how the Fighter prefers confrontation.\n\nPhysical attack power is the focus of the Fighter, but don\'t be fooled. A certain amount of Magical Points (MP) is needed to power the Fighter\'s devastating Special Skills.\n\nCharacteristics:\n· Wide range of available weapons\n· Powerful physical attacks',
            style:const TextStyle(fontSize:11,color:Colors.white,height:1.55),
          ),
        ),
      ),
    ),
    leftPanel(),

    // Panel de armas y perfil de clase con las texturas originales.
    Positioned(
      right:6,top:34,width:280,height:435,
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
      left:711,top:556,
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
