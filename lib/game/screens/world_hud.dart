import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/catalog.dart';
import '../../render/studio_scene.dart';
import '../ps0032_protocol.dart';
import '../server_metadata.dart';
import '../shaiya_widgets.dart';
import '../ui_asset.dart';

class WorldHud extends StatelessWidget {
  final StudioScene scene;
  final Catalog catalog;
  final ServerMetadata? metadata;
  final String characterName,locale;
  final int mapId,level;
  final PsCharacterDetails? details;
  final PsAdditionalStats? additionalStats;
  final PsHitpoints? hitpoints;
  final bool dead,rebirthPending;
  final VoidCallback onRebirth;
  final List<PsActiveBuff> buffs;
  final PsMapWeather? weather;
  final int? targetMobGlobalId,targetMobId,targetHp,targetMaxHp;
  final PsSkillBook? skillBook;
  final PsSkillBar? skillBar;
  final List<PsInventoryItem> inventory,warehouse;
  final int gold;
  final NpcShopRule? shop;
  final NpcGateRule? gate;
  final PsInventoryItem? blacksmithItem,blacksmithGem,blacksmithHammer;
  final PsLinkingPossibility? blacksmithPossibility;
  final bool blacksmithBusy;
  final bool inventoryOpen,statusOpen,skillsOpen,questLogOpen,shopOpen,blacksmithOpen,gateOpen,warehouseOpen;
  final VoidCallback onCloseShop,onCloseBlacksmith,onCloseGate,onCloseWarehouse,onLinkGem;
  final ValueChanged<int> onBuyShopProduct,onUseGate;
  final ValueChanged<PsInventoryItem?> onSelectBlacksmithItem,onSelectBlacksmithGem,onSelectBlacksmithHammer;
  final ValueChanged<PsInventoryItem> onSellInventory,onActivateInventory,onStoreWarehouse,onWithdrawWarehouse;
  final VoidCallback onToggleInventory,onToggleStatus,onToggleSkills,onToggleQuestLog;
  final ValueChanged<int> onAddStat;
  final ValueChanged<int> onHotbar,onOpenQuest;
  final ValueChanged<PsLearnedSkill> onAssignSkill;
  final ValueChanged<String> onSendChat;
  final UiAssetCache ui;
  final List<String> messages;
  final List<PsQuestProgress> openQuests;
  final List<PsFinishedQuest> finishedQuests;
  final bool questOpen;
  final bool questActive,rewardSelection;
  final int questId;
  final ValueChanged<int> onSelectReward;
  final VoidCallback onAcceptQuest;
  final VoidCallback onCancelQuest;

  const WorldHud({
    super.key,
    required this.scene,
    required this.catalog,
    required this.metadata,
    required this.characterName,
    required this.mapId,
    required this.level,
    required this.details,
    required this.additionalStats,
    required this.hitpoints,
    required this.dead,
    required this.rebirthPending,
    required this.onRebirth,
    required this.buffs,
    required this.weather,
    required this.targetMobGlobalId,
    required this.targetMobId,
    required this.targetHp,
    required this.targetMaxHp,
    required this.skillBook,
    required this.skillBar,
    required this.inventory,
    required this.warehouse,
    required this.gold,
    required this.shop,
    required this.gate,
    required this.blacksmithItem,
    required this.blacksmithGem,
    required this.blacksmithHammer,
    required this.blacksmithPossibility,
    required this.blacksmithBusy,
    required this.inventoryOpen,
    required this.statusOpen,
    required this.skillsOpen,
    required this.questLogOpen,
    required this.shopOpen,
    required this.blacksmithOpen,
    required this.gateOpen,
    required this.warehouseOpen,
    required this.onCloseShop,
    required this.onCloseBlacksmith,
    required this.onCloseGate,
    required this.onCloseWarehouse,
    required this.onLinkGem,
    required this.onSelectBlacksmithItem,
    required this.onSelectBlacksmithGem,
    required this.onSelectBlacksmithHammer,
    required this.onBuyShopProduct,
    required this.onUseGate,
    required this.onSellInventory,
    required this.onActivateInventory,
    required this.onStoreWarehouse,
    required this.onWithdrawWarehouse,
    required this.onToggleInventory,
    required this.onToggleStatus,
    required this.onAddStat,
    required this.onToggleSkills,
    required this.onToggleQuestLog,
    required this.onHotbar,
    required this.onOpenQuest,
    required this.onAssignSkill,
    required this.onSendChat,
    required this.locale,
    required this.ui,
    required this.messages,
    required this.openQuests,
    required this.finishedQuests,
    required this.questOpen,
    required this.questActive,
    required this.rewardSelection,
    required this.questId,
    required this.onSelectReward,
    required this.onAcceptQuest,
    required this.onCancelQuest,
  });

  @override
  Widget build(BuildContext context) => Stack(
        children: [
          Positioned(left: 8, top: 3, width: 216, height: 79, child: _playerHud()),
          if(buffs.isNotEmpty)
            Positioned(left:8,top:84,width:300,height:38,child:_buffBar()),
          Positioned(left: 215, top: 5, width: 520, height: 48, child: _topHotbar()),
          Positioned(right: 8, top: 8, width: 188, height: 232, child: _minimap()),
          if(targetMobId!=null)
            Positioned(left:390,top:60,width:245,height:48,child:_targetHud()),
          Positioned(left: 4, top: 363, width: 360, height: 290, child: _chat()),
          Positioned(left: 0, right: 0, bottom: 0, height: 58, child: _bottomHud()),
          if(weather!=null&&weather!.state!=0)
            Positioned.fill(child:IgnorePointer(child:CustomPaint(painter:_WeatherPainter(weather!)))),
          ..._worldLabels(),
          if(statusOpen)
            Positioned(right:198,top:210,width:318,height:420,child:_statusWindow()),
          if(skillsOpen)
            Positioned(right:198,top:190,width:350,height:455,child:_skillsWindow()),
          if(questLogOpen)
            Positioned(right:198,top:205,width:340,height:430,child:_questLogWindow()),
          if(shopOpen&&shop!=null)
            Positioned(
              right:198,top:250,width:292,height:390,
              child:_shopWindow(),
            ),
          if(blacksmithOpen)
            Positioned(
              right:150,top:175,width:420,height:465,
              child:_blacksmithWindow(),
            ),
          if(gateOpen&&gate!=null)
            Positioned(
              right:198,top:250,width:300,height:300,
              child:_gateWindow(),
            ),
          if(warehouseOpen)
            Positioned(
              right:198,top:250,width:292,height:390,
              child:_warehouseWindow(),
            ),
          if(inventoryOpen)
            Positioned(
              right:198,top:250,width:292,height:390,
              child:_inventoryWindow(),
            ),
          if (questOpen&&!dead)
            Positioned(
              left: 566,
              top: 118,
              width: 247,
              height: 505,
              child: _questWindow(),
            ),
          if(dead||rebirthPending)
            Positioned.fill(child:_deathOverlay()),
        ],
      );

  Widget _deathOverlay()=>Container(
    color:const Color(0x66000000),
    alignment:Alignment.center,
    child:Container(
      width:330,
      padding:const EdgeInsets.fromLTRB(20,18,20,18),
      decoration:BoxDecoration(
        color:const Color(0xf01b1410),
        border:Border.all(color:const Color(0xff8f493e),width:2),
        boxShadow:const [BoxShadow(color:Colors.black87,blurRadius:18)],
      ),
      child:Column(mainAxisSize:MainAxisSize.min,children:[
        const Icon(Icons.warning_amber_rounded,size:40,color:Color(0xffd9634f)),
        const SizedBox(height:7),
        Text(
          locale=='spn'?'Has muerto':'You are dead',
          style:const TextStyle(
            color:Color(0xffffd4b0),fontSize:19,fontWeight:FontWeight.bold,
            shadows:[Shadow(color:Colors.black,blurRadius:3)],
          ),
        ),
        const SizedBox(height:6),
        Text(
          rebirthPending
            ?(locale=='spn'?'World está procesando tu reaparición…':'World is processing your rebirth…')
            :(locale=='spn'?'Puedes renacer en la ciudad segura más cercana.':'You can rebirth at the nearest safe town.'),
          textAlign:TextAlign.center,
          style:const TextStyle(fontSize:10.5,color:Colors.white70,height:1.35),
        ),
        const SizedBox(height:16),
        shaiyaRedButton(
          rebirthPending
            ?(locale=='spn'?'Renaciendo…':'Rebirthing…')
            :(locale=='spn'?'Renacer en ciudad':'Rebirth in town'),
          rebirthPending?null:onRebirth,
          width:150,height:34,fontSize:10.5,
        ),
      ]),
    ),
  );

  List<Widget> _worldLabels(){
    final labels=scene.projectGameLabels(1024,742);
    return labels.map((label){
      final selected=label.mob&&label.globalId!=0&&label.globalId==targetMobGlobalId;
      final color=selected
        ?const Color(0xffff6b56)
        :label.mob
          ?const Color(0xffffec3b)
          :const Color(0xff58d7ff);
      return Positioned(
        left:(label.x-90).clamp(0.0,844.0),
        top:(label.y-34).clamp(0.0,676.0),
        width:180,
        child:IgnorePointer(
          child:Column(mainAxisSize:MainAxisSize.min,children:[
            if(selected)
              SizedBox(
                width:18,height:18,
                child:DataImage(
                  cache:ui,path:'interface/monster_show_high.tga',fit:BoxFit.contain,
                  fallback:const Icon(Icons.arrow_drop_down,color:Color(0xffff5847),size:18),
                ),
              )
            else if(label.quest)
              const Text(
                '!',
                style:TextStyle(
                  color:Color(0xffffff26),
                  fontSize:22,
                  fontWeight:FontWeight.w900,
                  height:.8,
                  shadows:[Shadow(color:Colors.black,blurRadius:3)],
                ),
              ),
            Text(
              label.text,
              maxLines:1,
              overflow:TextOverflow.ellipsis,
              textAlign:TextAlign.center,
              style:TextStyle(
                color:color,
                fontSize:selected?10.5:10,
                fontWeight:FontWeight.w600,
                shadows:const [
                  Shadow(color:Colors.black,offset:Offset(1,1),blurRadius:2),
                  Shadow(color:Colors.black,offset:Offset(-1,-1),blurRadius:2),
                ],
              ),
            ),
          ]),
        ),
      );
    }).toList();
  }

  Widget _playerHud()=>Stack(children:[
    Positioned.fill(
      child:DataImage(
        cache:ui,
        path:'interface/main_stats_bar_bg.tga',
        fit:BoxFit.fill,
      ),
    ),
    Positioned(
      left:5,top:12,width:48,height:48,
      child:DataRegion(
        cache:ui,
        path:'interface/create_fighter_button.tga',
        sheetWidth:256,
        sheetHeight:64,
        source:const Rect.fromLTWH(0,0,64,64),
        width:48,height:48,
        fallback:const Icon(Icons.sports_martial_arts,color:Color(0xffffae3a),size:34),
      ),
    ),
    Positioned(
      left:61,top:23,width:148,height:48,
      child:DataImage(
        cache:ui,
        path:'interface/main_stats_bar.tga',
        fit:BoxFit.fill,
      ),
    ),
    Positioned(
      left:63,top:7,
      child:Text(level.toString(),style:const TextStyle(fontSize:10,color:Colors.white)),
    ),
    Positioned(
      left:93,top:6,right:8,
      child:Text(
        characterName,
        style:const TextStyle(
          color:Color(0xffffed3b),
          fontSize:12,
          shadows:[Shadow(color:Colors.black,blurRadius:2)],
        ),
      ),
    ),
    Positioned(
      left:83,top:28,
      child:Text(
        '${hitpoints?.hp??details?.maxHp??0} / ${details?.maxHp??hitpoints?.hp??0}',
        style:const TextStyle(fontSize:8,color:Colors.white),
      ),
    ),
    Positioned(
      left:84,top:42,
      child:Text(
        '${hitpoints?.mp??details?.maxMp??0} / ${details?.maxMp??hitpoints?.mp??0}',
        style:const TextStyle(fontSize:8,color:Colors.white),
      ),
    ),
    Positioned(
      left:82,top:57,
      child:Text(
        '${hitpoints?.sp??details?.maxSp??0} / ${details?.maxSp??hitpoints?.sp??0}',
        style:const TextStyle(fontSize:8,color:Colors.white),
      ),
    ),
  ]);

  List<PsQuickSlot> get _primarySlots {
    final all=skillBar?.slots??const <PsQuickSlot>[];
    if(all.isEmpty)return const [];
    var bar=all.first.bar;
    for(final s in all){if(s.bar<bar)bar=s.bar;}
    final out=all.where((s)=>s.bar==bar).toList()
      ..sort((a,b)=>a.slot.compareTo(b.slot));
    return out;
  }

  PsQuickSlot? _quickSlot(int index){
    final slots=_primarySlots;
    return slots.where((s)=>s.slot==index).firstOrNull
      ??(index<slots.length?slots[index]:null);
  }

  Widget _quickCell(int index){
    final slot=_quickSlot(index);
    final learned=slot!=null&&slot.isSkill?skillBook?.bySkillId(slot.number):null;
    final skillName=learned==null?null:catalog.skillName(learned.skillId,learned.level,locale);
    final skillText=learned==null?null:catalog.skillText(learned.skillId,learned.level,locale);
    final skillRule=learned==null?null:metadata?.skill(learned.skillId,learned.level);
    final quickItem=slot!=null&&!slot.isSkill
      ?inventory.where((i)=>i.bag==slot.bag&&i.slot==slot.number).firstOrNull
      :null;
    final itemRule=quickItem==null?null:metadata?.item(quickItem.type,quickItem.typeId);
    final iconPath=slot==null?null:(slot.isSkill?skillRule?.iconPath:itemRule?.iconPath);
    final label=slot==null
      ?''
      :slot.isSkill
        ?(learned==null?'S${slot.number}':'S${learned.skillId}')
        :'I${slot.number}';
    final tooltip=slot==null
      ?''
      :slot.isSkill
        ?(skillName??(locale=='spn'?'Habilidad ${slot.number}':'Skill ${slot.number}'))+
          (skillText?.text.trim().isNotEmpty==true?'\n\n${skillText!.text.trim()}':'')+
          (learned==null?'':'\nLv. ${learned.level} · #${learned.number}')
        :quickItem==null
          ?(locale=='spn'?'Objeto rápido · bolsa ${slot.bag} slot ${slot.number}':'Quick item · bag ${slot.bag} slot ${slot.number}')
          :catalog.itemName(quickItem.type,quickItem.typeId,locale)+
            '\n${quickItem.type}:${quickItem.typeId} · Bag ${quickItem.bag} · Slot ${quickItem.slot}';
    final cell=SizedBox(
      width:39,height:39,
      child:Stack(children:[
        Positioned.fill(
          child:Center(
            child:slot==null
              ?const SizedBox.shrink()
              :iconPath!=null
                ?DataImage(
                    cache:ui,
                    path:iconPath,
                    fit:BoxFit.contain,
                    fallback:Icon(
                      slot.isSkill?Icons.auto_fix_high:Icons.inventory_2,
                      color:slot.isSkill?const Color(0xffffdfa0):const Color(0xffd7c18b),
                      size:21,
                    ),
                  )
                :Icon(
                    slot.isSkill?Icons.auto_fix_high:Icons.inventory_2,
                    color:slot.isSkill?const Color(0xffffdfa0):const Color(0xffd7c18b),
                    size:21,
                  ),
          ),
        ),
        Positioned(
          left:2,top:1,
          child:Text(
            index==9?'0':'${index+1}',
            style:const TextStyle(fontSize:8,color:Colors.white70,shadows:[Shadow(color:Colors.black,blurRadius:2)]),
          ),
        ),
        if(label.isNotEmpty)
          Positioned(
            left:2,right:2,bottom:1,
            child:Text(
              label,
              maxLines:1,
              overflow:TextOverflow.clip,
              textAlign:TextAlign.center,
              style:const TextStyle(fontSize:7,color:Color(0xffffe4a3),shadows:[Shadow(color:Colors.black,blurRadius:2)]),
            ),
          ),
        if(learned!=null)
          Positioned(
            right:1,top:1,
            child:Text(
              'L${learned.level}',
              style:const TextStyle(fontSize:7,color:Color(0xff8dd8ff),shadows:[Shadow(color:Colors.black,blurRadius:2)]),
            ),
          ),
      ]),
    );
    return Tooltip(
      message:tooltip,
      waitDuration:const Duration(milliseconds:250),
      child:GestureDetector(onTap:()=>onHotbar(index),child:cell),
    );
  }

  Widget _topHotbar()=>Stack(children:[
    Positioned.fill(
      child:DataImage(
        cache:ui,
        path:'interface/main_slot_3.tga',
        fit:BoxFit.fill,
      ),
    ),
    Positioned(
      left:15,top:5,
      child:Row(
        children:List.generate(10,(i)=>Padding(
          padding:const EdgeInsets.only(right:1),
          child:_quickCell(i),
        )),
      ),
    ),
  ]);

  Widget _buffBar(){
    final list=[...buffs]..sort((a,b){
      final byId=a.skillId.compareTo(b.skillId);
      return byId!=0?byId:a.skillLevel.compareTo(b.skillLevel);
    });
    return Align(
      alignment:Alignment.centerLeft,
      child:ListView.separated(
        scrollDirection:Axis.horizontal,
        itemCount:list.length,
        separatorBuilder:(_,__)=>const SizedBox(width:3),
        itemBuilder:(context,index){
          final buff=list[index];
          final rule=metadata?.skill(buff.skillId,buff.skillLevel);
          final icon=rule?.iconPath;
          final name=catalog.skillName(buff.skillId,buff.skillLevel,locale);
          final desc=catalog.skillText(buff.skillId,buff.skillLevel,locale)?.text.trim()??'';
          final remaining=buff.countdownSeconds;
          return Tooltip(
            waitDuration:const Duration(milliseconds:250),
            message:name+
              '\nLv. ${buff.skillLevel} · #${buff.id}'+
              (remaining<0?'':'\n'+(locale=='spn'?'Tiempo: ':'Time: ')+remaining.toString()+' s')+
              (desc.isEmpty?'':'\n\n'+desc),
            child:Container(
              width:36,height:36,
              decoration:BoxDecoration(
                color:const Color(0xcc17120e),
                border:Border.all(color:const Color(0xff6d5b40)),
              ),
              child:Stack(children:[
                Positioned.fill(
                  child:Padding(
                    padding:const EdgeInsets.all(2),
                    child:icon==null
                      ?const Icon(Icons.shield_moon,color:Color(0xff8ed7ff),size:24)
                      :DataImage(
                          cache:ui,path:icon,fit:BoxFit.contain,
                          fallback:const Icon(Icons.shield_moon,color:Color(0xff8ed7ff),size:24),
                        ),
                  ),
                ),
                Positioned(
                  right:1,top:0,
                  child:Text(
                    'L${buff.skillLevel}',
                    style:const TextStyle(fontSize:7,color:Color(0xffffe081),shadows:[Shadow(color:Colors.black,blurRadius:2)]),
                  ),
                ),
                if(remaining>=0)
                  Positioned(
                    left:1,right:1,bottom:0,
                    child:Text(
                      remaining>999?'999+':remaining.toString(),
                      textAlign:TextAlign.center,
                      style:const TextStyle(fontSize:7,color:Colors.white,shadows:[Shadow(color:Colors.black,blurRadius:2)]),
                    ),
                  ),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _targetHud(){
    final id=targetMobId!;
    final rule=metadata?.mobs[id];
    final name=catalog.monsterName(id,locale);
    final max=targetMaxHp??rule?.hp??1;
    final hp=(targetHp??max).clamp(0,max);
    final ratio=max<=0?0.0:hp/max;
    return Container(
      padding:const EdgeInsets.fromLTRB(5,4,5,4),
      decoration:BoxDecoration(
        color:const Color(0xaa120f0b),
        border:Border.all(color:const Color(0xff7d6b4f)),
        boxShadow:const [BoxShadow(color:Colors.black54,blurRadius:5)],
      ),
      child:Row(children:[
        SizedBox(
          width:32,height:32,
          child:DataImage(
            cache:ui,path:'interface/monster_show.tga',fit:BoxFit.contain,
            fallback:const Icon(Icons.pest_control,color:Color(0xffffd45f),size:24),
          ),
        ),
        const SizedBox(width:5),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Row(children:[
            Expanded(child:Text(
              name,
              maxLines:1,overflow:TextOverflow.ellipsis,
              style:const TextStyle(fontSize:10.5,color:Color(0xffffee74),fontWeight:FontWeight.w600,shadows:[Shadow(color:Colors.black,blurRadius:2)]),
            )),
            Text('Lv.${rule?.level??0}',style:const TextStyle(fontSize:8,color:Colors.white60)),
          ]),
          const SizedBox(height:2),
          SizedBox(
            height:8,
            child:Stack(children:[
              Positioned.fill(child:DataImage(cache:ui,path:'interface/monster_hpbar_bg.tga',fit:BoxFit.fill)),
              Positioned.fill(child:Align(
                alignment:Alignment.centerLeft,
                widthFactor:ratio,
                child:DataImage(cache:ui,path:'interface/monster_hpbar.tga',fit:BoxFit.fill),
              )),
            ]),
          ),
          const SizedBox(height:1),
          Text(
            '$hp / $max',
            style:const TextStyle(fontSize:7.5,color:Colors.white70),
          ),
        ])),
      ]),
    );
  }

  Widget _minimap() => Stack(
        children: [
          Positioned.fill(
            child: DataImage(
              cache: ui,
              path: 'interface/main_map.tga',
              fit: BoxFit.fill,
            ),
          ),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0x33201b15),
              border: Border.all(color: const Color(0xff8f8264)),
            ),
            child: Column(
              children: [
                Expanded(
                  child: Stack(children:[
                    Positioned.fill(
                      child:DataImage(
                        cache:ui,
                        path:'interface/minimap/'+mapId.toString()+'.tga',
                        fit:BoxFit.fill,
                      ),
                    ),
                    Positioned.fill(
                      child:CustomPaint(
                        painter:_MiniMapPainter(scene),
                        child:const SizedBox.expand(),
                      ),
                    ),
                  ]),
                ),
                Row(
                  children: [
                    const Text(
                      '+  −',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      scene.originX.round().toString() +
                          ' ' +
                          scene.originZ.round().toString(),
                      style: const TextStyle(
                        fontSize: 9,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      );

  Widget _chat()=>Stack(children:[
    Positioned.fill(
      child:DataImage(
        cache:ui,
        path:'interface/chat/chat.tga',
        fit:BoxFit.fill,
      ),
    ),
    const Positioned(
      left:18,top:12,
      child:Text(
        'World',
        style:TextStyle(
          fontSize:13,
          color:Colors.white,
          shadows:[Shadow(color:Colors.black,blurRadius:2)],
        ),
      ),
    ),
    Positioned(
      left:12,top:52,right:20,bottom:36,
      child:ListView(
        reverse:true,
        padding:EdgeInsets.zero,
        children:messages.take(12).map((m)=>Padding(
          padding:const EdgeInsets.only(bottom:5),
          child:Text(
            m,
            style:const TextStyle(
              fontSize:10,
              color:Colors.white,
              shadows:[Shadow(color:Colors.black,blurRadius:2)],
            ),
          ),
        )).toList(),
      ),
    ),
    Positioned(
      left:11,right:18,bottom:8,height:24,
      child:_ChatInput(onSend:onSendChat),
    ),
  ]);

  Widget _bottomButton(String path,{VoidCallback? onTap})=>GestureDetector(
    onTap:onTap,
    child:DataRegion(
      cache:ui,
      path:path,
      sheetWidth:256,
      sheetHeight:64,
      source:const Rect.fromLTWH(0,0,64,64),
      width:31,
      height:31,
    ),
  );

  Widget _bottomHud()=>Stack(children:[
    Positioned.fill(
      child:DataImage(
        cache:ui,
        path:'interface/main_bottom.tga',
        fit:BoxFit.fill,
      ),
    ),
    Positioned(
      left:14,right:14,top:3,height:12,
      child:DataImage(
        cache:ui,
        path:'interface/skillbar_bg.tga',
        fit:BoxFit.fill,
      ),
    ),
    Positioned(
      left:250,right:250,top:0,
      child:Center(
        child:Text(
          '${((details?.experienceRatio??0)*100).toStringAsFixed(1).replaceAll('.',',')}%',
          style:const TextStyle(fontSize:9,color:Colors.white70),
        ),
      ),
    ),
    Positioned(
      right:7,bottom:1,
      child:Row(children:[
        _bottomButton('interface/main_bottom_btn_status.tga',onTap:onToggleStatus),
        _bottomButton('interface/main_bottom_btn_skill.tga',onTap:onToggleSkills),
        _bottomButton('interface/main_bottom_btn_item.tga',onTap:onToggleInventory),
        _bottomButton('interface/main_bottom_btn_quest.tga',onTap:onToggleQuestLog),
        _bottomButton('interface/main_bottom_btn_sub.tga'),
        _bottomButton('interface/main_bottom_btn_guild.tga'),
        _bottomButton('interface/main_bottom_btn_shop.tga'),
        _bottomButton('interface/main_bottom_btn_option.tga'),
        _bottomButton('interface/main_bottom_btn_event.tga'),
        _bottomButton('interface/main_bottom_btn_helper.tga'),
      ]),
    ),
  ]);

  Widget _panelShell(String title,Widget body,{Widget? footer})=>Container(
    decoration:BoxDecoration(
      color:const Color(0xee211810),
      border:Border.all(color:const Color(0xff8b7350),width:2),
      boxShadow:const [BoxShadow(color:Colors.black87,blurRadius:12)],
    ),
    child:Column(children:[
      Container(
        height:34,
        padding:const EdgeInsets.symmetric(horizontal:10),
        decoration:const BoxDecoration(
          gradient:LinearGradient(colors:[Color(0xff5d3b24),Color(0xff25160e)]),
        ),
        child:Row(children:[
          Expanded(child:Text(title,style:const TextStyle(color:Color(0xffffdc72),fontSize:12,fontWeight:FontWeight.bold))),
        ]),
      ),
      Expanded(child:body),
      if(footer!=null)footer,
    ]),
  );

  Widget _statLine(String label,Object? base,Object? total,{VoidCallback? onAdd})=>Padding(
    padding:const EdgeInsets.symmetric(vertical:3),
    child:Row(children:[
      Expanded(child:Text(label,style:const TextStyle(fontSize:10,color:Color(0xffe9d9bc)))),
      SizedBox(width:52,child:Text((base??0).toString(),textAlign:TextAlign.right,style:const TextStyle(fontSize:10,color:Colors.white70))),
      const SizedBox(width:8),
      SizedBox(width:52,child:Text((total??base??0).toString(),textAlign:TextAlign.right,style:const TextStyle(fontSize:10,color:Color(0xffffd26a)))),
      if(onAdd!=null)...[
        const SizedBox(width:8),
        SizedBox(
          width:24,height:20,
          child:TextButton(
            onPressed:onAdd,
            style:TextButton.styleFrom(padding:EdgeInsets.zero,foregroundColor:const Color(0xffffe082),backgroundColor:const Color(0xff3c2a1a)),
            child:const Text('+',style:TextStyle(fontSize:14,fontWeight:FontWeight.bold)),
          ),
        ),
      ],
    ]),
  );
  Widget _statusWindow(){
    final d=details,a=additionalStats;
    return _panelShell(
      locale=='spn'?'Estado del personaje':'Character status',
      Padding(
        padding:const EdgeInsets.all(12),
        child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Row(children:[
            Expanded(child:Text(characterName,style:const TextStyle(fontSize:14,color:Color(0xffffe26f),fontWeight:FontWeight.bold))),
            Text('Lv.$level',style:const TextStyle(fontSize:11,color:Colors.white70)),
          ]),
          const SizedBox(height:8),
          Row(children:[
            Expanded(child:Text(locale=='spn'?'Atributo':'Stat',style:const TextStyle(fontSize:9,color:Colors.white54))),
            const SizedBox(width:58,child:Text('Base',textAlign:TextAlign.right,style:TextStyle(fontSize:9,color:Colors.white54))),
            const SizedBox(width:8),
            const SizedBox(width:58,child:Text('Total',textAlign:TextAlign.right,style:TextStyle(fontSize:9,color:Colors.white54))),
          ]),
          const Divider(color:Color(0xff65533b),height:10),
          _statLine(locale=='spn'?'Fuerza':'Strength',d?.strength,a?.strength,onAdd:(d?.statPoint??0)>0?()=>onAddStat(0):null),
          _statLine(locale=='spn'?'Destreza':'Dexterity',d?.dexterity,a?.dexterity,onAdd:(d?.statPoint??0)>0?()=>onAddStat(1):null),
          _statLine(locale=='spn'?'Reacción':'Reaction',d?.reaction,a?.reaction,onAdd:(d?.statPoint??0)>0?()=>onAddStat(2):null),
          _statLine(locale=='spn'?'Inteligencia':'Intelligence',d?.intelligence,a?.intelligence,onAdd:(d?.statPoint??0)>0?()=>onAddStat(3):null),
          _statLine(locale=='spn'?'Sabiduría':'Wisdom',d?.wisdom,a?.wisdom,onAdd:(d?.statPoint??0)>0?()=>onAddStat(4):null),
          _statLine(locale=='spn'?'Suerte':'Luck',d?.luck,a?.luck,onAdd:(d?.statPoint??0)>0?()=>onAddStat(5):null),
          const Divider(color:Color(0xff65533b),height:14),
          _statLine(locale=='spn'?'Ataque':'Attack','${a?.minAttack??0}-${a?.maxAttack??0}',null),
          _statLine(locale=='spn'?'Ataque mágico':'Magic attack','${a?.minMagicAttack??0}-${a?.maxMagicAttack??0}',null),
          _statLine(locale=='spn'?'Defensa':'Defense',a?.defense,null),
          _statLine(locale=='spn'?'Resistencia':'Resistance',a?.resistance,null),
          const Spacer(),
          Text(
            (locale=='spn'?'Puntos de estado: ':'Stat points: ')+(d?.statPoint??0).toString()+
            '   ·   '+(locale=='spn'?'Puntos de habilidad: ':'Skill points: ')+(d?.skillPoint??0).toString(),
            style:const TextStyle(fontSize:9,color:Color(0xffffd26a)),
          ),
          const SizedBox(height:4),
          Text(
            'HP ${hitpoints?.hp??d?.maxHp??0}/${d?.maxHp??0} · MP ${hitpoints?.mp??d?.maxMp??0}/${d?.maxMp??0} · SP ${hitpoints?.sp??d?.maxSp??0}/${d?.maxSp??0}',
            style:const TextStyle(fontSize:8.5,color:Colors.white60),
          ),
        ]),
      ),
    );
  }
  Widget _skillsWindow(){
    final skills=[...(skillBook?.skills??const <PsLearnedSkill>[])];
    skills.sort((a,b){final id=a.skillId.compareTo(b.skillId);return id!=0?id:a.level.compareTo(b.level);});
    return _panelShell(
      locale=='spn'?'Habilidades':'Skills',
      skills.isEmpty
        ?Center(child:Text(locale=='spn'?'No hay habilidades aprendidas.':'No learned skills.',style:const TextStyle(color:Colors.white54,fontSize:11)))
        :ListView.separated(
            padding:const EdgeInsets.all(8),
            itemCount:skills.length,
            separatorBuilder:(_,__)=>const Divider(color:Color(0xff463828),height:7),
            itemBuilder:(context,index){
              final s=skills[index],rule=metadata?.skill(s.skillId,s.level);
              final name=catalog.skillName(s.skillId,s.level,locale);
              final text=catalog.skillText(s.skillId,s.level,locale)?.text.trim()??'';
              final icon=rule?.iconPath;
              final tile=Tooltip(
                waitDuration:const Duration(milliseconds:250),
                message:name+
                  (text.isEmpty?'':'\n\n'+text)+
                  '\nID ${s.skillId} · Lv.${s.level} · #${s.number}'+
                  '\nMP ${rule?.mp??0} · SP ${rule?.sp??0} · CD ${rule?.cooldown??s.cooldownSeconds}',
                child:Container(
                  padding:const EdgeInsets.all(6),
                  decoration:BoxDecoration(color:const Color(0xff17120e),border:Border.all(color:const Color(0xff55452f))),
                  child:Row(children:[
                    SizedBox(
                      width:38,height:38,
                      child:icon==null
                        ?const Icon(Icons.auto_fix_high,color:Color(0xffffd26a))
                        :DataImage(cache:ui,path:icon,fit:BoxFit.contain,fallback:const Icon(Icons.auto_fix_high,color:Color(0xffffd26a))),
                    ),
                    const SizedBox(width:8),
                    Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                      Text(name,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:10,color:Color(0xffffe1a1),fontWeight:FontWeight.w600)),
                      Text(
                        'Lv.${s.level} · MP ${rule?.mp??0} · SP ${rule?.sp??0} · CD ${rule?.cooldown??s.cooldownSeconds}',
                        style:const TextStyle(fontSize:8,color:Colors.white54),
                      ),
                    ])),
                  ]),
                ),
              );
              return GestureDetector(
                onDoubleTap:()=>onAssignSkill(s),
                child:tile,
              );
            },
          ),
      footer:Container(
        height:30,padding:const EdgeInsets.symmetric(horizontal:10),
        alignment:Alignment.centerRight,
        child:Text(
          (locale=='spn'?'Doble clic para añadir a barra · Puntos: ':'Double click to add to bar · Points: ')+(skillBook?.skillPoints??details?.skillPoint??0).toString(),
          style:const TextStyle(fontSize:9,color:Color(0xffffd26a)),
        ),
      ),
    );
  }
  Widget _questLogWindow(){
    final active=[...openQuests];
    return _panelShell(
      locale=='spn'?'Registro de misiones':'Quest log',
      Column(children:[
        Container(
          height:28,padding:const EdgeInsets.symmetric(horizontal:10),
          alignment:Alignment.centerLeft,
          child:Text(
            (locale=='spn'?'Activas: ':'Active: ')+active.length.toString()+
              ' · '+(locale=='spn'?'Finalizadas: ':'Finished: ')+finishedQuests.where((q)=>q.success).length.toString(),
            style:const TextStyle(fontSize:9,color:Colors.white60),
          ),
        ),
        Expanded(
          child:active.isEmpty
            ?Center(child:Text(locale=='spn'?'No hay misiones activas.':'No active quests.',style:const TextStyle(color:Colors.white54,fontSize:11)))
            :ListView.separated(
                padding:const EdgeInsets.fromLTRB(8,0,8,8),
                itemCount:active.length,
                separatorBuilder:(_,__)=>const SizedBox(height:5),
                itemBuilder:(context,index){
                  final q=active[index],text=catalog.questText(locale)?.quest(q.questId),rule=metadata?.quests[q.questId];
                  final name=(text?.name.isNotEmpty??false)?text!.name:(locale=='spn'?'Misión ${q.questId}':'Quest ${q.questId}');
                  final objectives=<String>[];
                  if((rule?.requiredMobId1??0)>0){
                    objectives.add(catalog.monsterName(rule!.requiredMobId1,locale)+' ${q.count1}/${rule.requiredMobCount1}');
                  }
                  if((rule?.requiredMobId2??0)>0){
                    objectives.add(catalog.monsterName(rule!.requiredMobId2,locale)+' ${q.count2}/${rule.requiredMobCount2}');
                  }
                  if(objectives.isEmpty){
                    objectives.add(locale=='spn'?'Progreso ${q.count1}, ${q.count2}, ${q.count3}':'Progress ${q.count1}, ${q.count2}, ${q.count3}');
                  }
                  return GestureDetector(
                    onDoubleTap:()=>onOpenQuest(q.questId),
                    child:Container(
                      padding:const EdgeInsets.all(8),
                      decoration:BoxDecoration(color:const Color(0xff17120e),border:Border.all(color:const Color(0xff5d4c34))),
                      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                        Row(children:[
                          Expanded(child:Text(name,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:10,color:Color(0xffffdc72),fontWeight:FontWeight.w600))),
                          Text('#${q.questId}',style:const TextStyle(fontSize:7.5,color:Colors.white38)),
                        ]),
                        const SizedBox(height:4),
                        ...objectives.map((o)=>Text(o,style:const TextStyle(fontSize:8.5,color:Colors.white60))),
                        const SizedBox(height:3),
                        Text(
                          locale=='spn'?'Doble clic para abrir detalles.':'Double click for details.',
                          style:const TextStyle(fontSize:7,color:Colors.white30),
                        ),
                      ]),
                    ),
                  );
                },
              ),
        ),
      ]),
    );
  }
  Widget _blacksmithPick({
    required String title,
    required List<PsInventoryItem> items,
    required PsInventoryItem? selected,
    required ValueChanged<PsInventoryItem?> onSelect,
  }){
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(title,style:const TextStyle(fontSize:9.5,color:Color(0xffffdc72),fontWeight:FontWeight.w600)),
      const SizedBox(height:4),
      SizedBox(
        height:64,
        child:items.isEmpty
          ?Container(
              alignment:Alignment.centerLeft,
              padding:const EdgeInsets.symmetric(horizontal:8),
              decoration:BoxDecoration(color:const Color(0xff17120e),border:Border.all(color:const Color(0xff514231))),
              child:Text(locale=='spn'?'No hay objetos compatibles.':'No compatible items.',style:const TextStyle(fontSize:8.5,color:Colors.white38)),
            )
          :ListView.separated(
              scrollDirection:Axis.horizontal,
              itemCount:items.length,
              separatorBuilder:(_,__)=>const SizedBox(width:5),
              itemBuilder:(context,index){
                final item=items[index],rule=metadata?.item(item.type,item.typeId);
                final icon=rule?.iconPath,name=catalog.itemName(item.type,item.typeId,locale);
                final chosen=selected?.bag==item.bag&&selected?.slot==item.slot;
                return Tooltip(
                  waitDuration:const Duration(milliseconds:250),
                  message:name+'\nBag ${item.bag} · Slot ${item.slot} · ${item.type}:${item.typeId}',
                  child:GestureDetector(
                    onTap:()=>onSelect(chosen?null:item),
                    child:Container(
                      width:58,padding:const EdgeInsets.all(4),
                      decoration:BoxDecoration(
                        color:const Color(0xff17120e),
                        border:Border.all(color:chosen?const Color(0xffffd15b):const Color(0xff5c4a35),width:chosen?2:1),
                      ),
                      child:Column(children:[
                        Expanded(child:icon==null
                          ?const Icon(Icons.inventory_2,size:26,color:Color(0xffd7c18b))
                          :DataImage(cache:ui,path:icon,fit:BoxFit.contain,fallback:const Icon(Icons.inventory_2,size:26,color:Color(0xffd7c18b)))),
                        Text(name,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:6.7,color:Colors.white70)),
                      ]),
                    ),
                  ),
                );
              },
            ),
      ),
    ]);
  }

  Widget _blacksmithWindow(){
    final targets=inventory.where((item){
      if(item.bag==0||item.type==30)return false;
      final rule=metadata?.item(item.type,item.typeId);
      return rule!=null&&rule.slot>0;
    }).toList();
    final gems=inventory.where((item)=>item.bag!=0&&item.type==30).toList();
    final hammers=inventory.where((item){
      final special=metadata?.item(item.type,item.typeId)?.special??0;
      return item.bag!=0&&(special==36||special==69);
    }).toList();
    final p=blacksmithPossibility;
    final canLink=!blacksmithBusy&&p!=null&&p.available&&blacksmithItem!=null&&blacksmithGem!=null&&gold>=p.gold;

    return _panelShell(
      locale=='spn'?'Herrero · Enlace de lapis':'Blacksmith · Lapis linking',
      Padding(
        padding:const EdgeInsets.all(10),
        child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          _blacksmithPick(
            title:locale=='spn'?'1. Objeto':'1. Item',
            items:targets,selected:blacksmithItem,onSelect:onSelectBlacksmithItem,
          ),
          const SizedBox(height:9),
          _blacksmithPick(
            title:locale=='spn'?'2. Lapis':'2. Lapis',
            items:gems,selected:blacksmithGem,onSelect:onSelectBlacksmithGem,
          ),
          const SizedBox(height:9),
          _blacksmithPick(
            title:locale=='spn'?'3. Martillo opcional':'3. Optional hammer',
            items:hammers,selected:blacksmithHammer,onSelect:onSelectBlacksmithHammer,
          ),
          const Spacer(),
          Container(
            width:double.infinity,
            padding:const EdgeInsets.all(9),
            decoration:BoxDecoration(color:const Color(0xff17120e),border:Border.all(color:const Color(0xff5e4932))),
            child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text(
                p==null
                  ?(blacksmithBusy?(locale=='spn'?'Consultando a World…':'Querying World…'):(locale=='spn'?'Selecciona objeto y lapis para consultar.':'Select item and lapis to query.'))
                  :'Probabilidad: ${p.rate.toStringAsFixed(2)}% · Coste: ${p.gold} oro',
                style:TextStyle(fontSize:10,color:p==null?Colors.white54:(p.rate>=50?const Color(0xff9dff90):const Color(0xffffb46d))),
              ),
              const SizedBox(height:5),
              Text(
                locale=='spn'
                  ?'El resultado es aleatorio y lo decide World. Un fallo puede consumir el lapis.'
                  :'World decides the random result. Failure may consume the lapis.',
                style:const TextStyle(fontSize:7.8,color:Colors.white38),
              ),
            ]),
          ),
        ]),
      ),
      footer:Container(
        height:42,padding:const EdgeInsets.symmetric(horizontal:8),
        child:Row(children:[
          Text('Oro: $gold',style:const TextStyle(fontSize:9.5,color:Color(0xffffd26a))),
          const Spacer(),
          SizedBox(
            width:92,height:29,
            child:ShaiyaButton(
              label:blacksmithBusy?(locale=='spn'?'Procesando…':'Working…'):(locale=='spn'?'Enlazar':'Link'),
              onPressed:canLink?onLinkGem:null,
              compact:true,
            ),
          ),
          const SizedBox(width:7),
          GestureDetector(onTap:onCloseBlacksmith,child:const Icon(Icons.close,size:18,color:Colors.white70)),
        ]),
      ),
    );
  }

  Widget _gateWindow(){
    final g=gate!;
    final localized=catalog.questText(locale)?.npc(g.type,g.typeId);
    final names=localized?.destinations??const <String>[];
    final targets=g.targets.where((x)=>x.mapId>0).toList();
    return _panelShell(
      locale=='spn'?'Gatekeeper':'Gatekeeper',
      ListView.separated(
        padding:const EdgeInsets.all(10),
        itemCount:targets.length,
        separatorBuilder:(_,__)=>const SizedBox(height:7),
        itemBuilder:(context,index){
          final target=targets[index];
          final name=target.index<names.length&&names[target.index].trim().isNotEmpty
            ?names[target.index].trim()
            :(locale=='spn'?'Mapa ${target.mapId}':'Map ${target.mapId}');
          final affordable=gold>=target.cost;
          return Tooltip(
            waitDuration:const Duration(milliseconds:250),
            message:name+
              '\n'+(locale=='spn'?'Mapa: ':'Map: ')+target.mapId.toString()+
              '\n'+(locale=='spn'?'Coordenadas: ':'Coordinates: ')+
                '${target.x.toStringAsFixed(1)}, ${target.y.toStringAsFixed(1)}, ${target.z.toStringAsFixed(1)}'+
              '\n'+(locale=='spn'?'Coste: ':'Cost: ')+target.cost.toString(),
            child:GestureDetector(
              onDoubleTap:affordable?()=>onUseGate(target.index):null,
              child:Container(
                padding:const EdgeInsets.all(8),
                decoration:BoxDecoration(
                  color:const Color(0xff17120e),
                  border:Border.all(color:affordable?const Color(0xff8c7047):const Color(0xff5b3732)),
                ),
                child:Row(children:[
                  const Icon(Icons.public,size:27,color:Color(0xff9fd8ff)),
                  const SizedBox(width:8),
                  Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                    Text(
                      name,
                      maxLines:1,overflow:TextOverflow.ellipsis,
                      style:TextStyle(
                        fontSize:10.5,fontWeight:FontWeight.w600,
                        color:affordable?const Color(0xffffe0a1):const Color(0xffa97670),
                      ),
                    ),
                    Text(
                      'Mapa ${target.mapId} · ${target.cost} oro',
                      style:const TextStyle(fontSize:8,color:Colors.white54),
                    ),
                  ])),
                ]),
              ),
            ),
          );
        },
      ),
      footer:Container(
        height:34,
        padding:const EdgeInsets.symmetric(horizontal:8),
        child:Row(children:[
          Expanded(child:Text(
            locale=='spn'?'Doble clic para viajar.':'Double click to travel.',
            style:const TextStyle(fontSize:8,color:Colors.white54),
          )),
          Text('Oro: $gold',style:const TextStyle(fontSize:10,color:Color(0xffffd26a))),
          const SizedBox(width:8),
          GestureDetector(onTap:onCloseGate,child:const Icon(Icons.close,size:17,color:Colors.white70)),
        ]),
      ),
    );
  }

  Widget _shopWindow(){
    final s=shop!;
    return Container(
      decoration:BoxDecoration(
        color:const Color(0xe6241a12),
        border:Border.all(color:const Color(0xffa9824e),width:2),
        boxShadow:const [BoxShadow(color:Colors.black87,blurRadius:12)],
      ),
      child:Column(children:[
        Container(
          height:34,padding:const EdgeInsets.symmetric(horizontal:10),
          decoration:const BoxDecoration(
            gradient:LinearGradient(colors:[Color(0xff693b20),Color(0xff28150d)]),
          ),
          child:Row(children:[
            Expanded(child:Text(
              locale=='spn'?'Tienda':'Shop',
              style:const TextStyle(color:Color(0xffffdc72),fontSize:12,fontWeight:FontWeight.bold),
            )),
            Text(
              s.products.length.toString()+' productos',
              style:const TextStyle(fontSize:9,color:Colors.white60),
            ),
            const SizedBox(width:6),
            GestureDetector(onTap:onCloseShop,child:const Icon(Icons.close,size:17,color:Colors.white70)),
          ]),
        ),
        Expanded(
          child:GridView.builder(
            padding:const EdgeInsets.all(9),
            gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount:4,crossAxisSpacing:6,mainAxisSpacing:6,childAspectRatio:.86,
            ),
            itemCount:s.products.length,
            itemBuilder:(context,index){
              final product=s.products[index];
              final rule=metadata?.item(product.type,product.id);
              final name=catalog.itemName(product.type,product.id,locale);
              final description=catalog.itemText(product.type,product.id,locale)?.text.trim()??'';
              final price=rule?.buy??0;
              final icon=rule?.iconPath;
              final card=Container(
                padding:const EdgeInsets.all(3),
                decoration:BoxDecoration(
                  color:const Color(0xff17120e),
                  border:Border.all(color:const Color(0xff6f5a3b)),
                ),
                child:Column(children:[
                  Expanded(
                    child:icon==null
                      ?const Icon(Icons.inventory_2,size:28,color:Color(0xffd8bd83))
                      :DataImage(
                          cache:ui,path:icon,fit:BoxFit.contain,
                          fallback:const Icon(Icons.inventory_2,size:28,color:Color(0xffd8bd83)),
                        ),
                  ),
                  Text(
                    name,
                    maxLines:1,overflow:TextOverflow.ellipsis,
                    style:const TextStyle(fontSize:7.5,color:Color(0xffffe4a8)),
                  ),
                  Text(
                    price.toString(),
                    style:const TextStyle(fontSize:7,color:Color(0xffffcf55)),
                  ),
                ]),
              );
              return Tooltip(
                waitDuration:const Duration(milliseconds:250),
                message:name+
                  '\n${product.type}:${product.id} · índice ${product.index}'+
                  '\n'+(locale=='spn'?'Precio: ':'Price: ')+price.toString()+
                  (description.isEmpty?'':'\n\n'+description),
                child:GestureDetector(
                  onDoubleTap:()=>onBuyShopProduct(product.index),
                  child:card,
                ),
              );
            },
          ),
        ),
        Container(
          height:38,
          padding:const EdgeInsets.symmetric(horizontal:8),
          decoration:const BoxDecoration(color:Color(0xff1b130d)),
          child:Row(children:[
            Expanded(child:Text(
              locale=='spn'
                ?'Doble clic: comprar · inventario: doble clic para vender'
                :'Double click: buy · inventory: double click to sell',
              style:const TextStyle(fontSize:7.5,color:Colors.white54),
            )),
            Text(
              'Oro: $gold',
              style:const TextStyle(fontSize:10,color:Color(0xffffdb70),fontWeight:FontWeight.bold),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _warehouseWindow()=>Container(
    decoration:BoxDecoration(
      color:const Color(0xe6201811),
      border:Border.all(color:const Color(0xff8e7856),width:2),
      boxShadow:const [BoxShadow(color:Colors.black87,blurRadius:12)],
    ),
    child:Column(children:[
      Container(
        height:34,padding:const EdgeInsets.symmetric(horizontal:10),
        decoration:const BoxDecoration(
          gradient:LinearGradient(colors:[Color(0xff4b3a27),Color(0xff21170f)]),
        ),
        child:Row(children:[
          Expanded(child:Text(
            locale=='spn'?'Almacén':'Warehouse',
            style:const TextStyle(color:Color(0xffffdc72),fontSize:12,fontWeight:FontWeight.bold),
          )),
          Text(warehouse.length.toString()+'/120',style:const TextStyle(fontSize:9,color:Colors.white60)),
          const SizedBox(width:6),
          GestureDetector(onTap:onCloseWarehouse,child:const Icon(Icons.close,size:17,color:Colors.white70)),
        ]),
      ),
      Expanded(
        child:warehouse.isEmpty
          ?Center(child:Text(locale=='spn'?'Almacén vacío':'Warehouse empty',style:const TextStyle(color:Colors.white54,fontSize:11)))
          :GridView.builder(
              padding:const EdgeInsets.all(9),
              gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount:5,crossAxisSpacing:5,mainAxisSpacing:5,childAspectRatio:1,
              ),
              itemCount:warehouse.length,
              itemBuilder:(context,index){
                final item=warehouse[index],rule=metadata?.item(item.type,item.typeId);
                final icon=rule?.iconPath,name=catalog.itemName(item.type,item.typeId,locale);
                final gems=item.gems.where((g)=>g>0).length;
                final card=Container(
                  decoration:BoxDecoration(
                    color:const Color(0xff17120e),
                    border:Border.all(color:item.quality>0?const Color(0xffa88955):const Color(0xff52483c)),
                  ),
                  child:Stack(children:[
                    Center(child:icon==null
                      ?const Icon(Icons.inventory_2,size:26,color:Color(0xffc0b49d))
                      :DataImage(cache:ui,path:icon,fit:BoxFit.contain,fallback:const Icon(Icons.inventory_2,size:26,color:Color(0xffc0b49d)))),
                    Positioned(left:2,top:1,child:Text(
                      item.slot.toString(),
                      style:const TextStyle(fontSize:7,color:Colors.white54),
                    )),
                    if(item.count>1)Positioned(right:2,bottom:1,child:Text(
                      'x${item.count}',style:const TextStyle(fontSize:8,color:Colors.white),
                    )),
                    if(gems>0)Positioned(left:2,bottom:1,child:Text(
                      '◆$gems',style:const TextStyle(fontSize:8,color:Color(0xff7fd9ff)),
                    )),
                  ]),
                );
                return Tooltip(
                  waitDuration:const Duration(milliseconds:250),
                  message:name+
                    '\n${item.type}:${item.typeId} · slot ${item.slot}'+
                    '\n'+(locale=='spn'?'Doble clic para retirar. Comisión de retiro: 5%.':'Double click to withdraw. Withdrawal fee: 5%.'),
                  child:GestureDetector(onDoubleTap:()=>onWithdrawWarehouse(item),child:card),
                );
              },
            ),
      ),
      Container(
        height:35,padding:const EdgeInsets.symmetric(horizontal:8),
        decoration:const BoxDecoration(color:Color(0xff18120d)),
        child:Row(children:[
          Expanded(child:Text(
            locale=='spn'
              ?'Doble clic en inventario: guardar · aquí: retirar'
              :'Double click inventory: store · here: withdraw',
            style:const TextStyle(fontSize:7.5,color:Colors.white54),
          )),
          Text('Oro: $gold',style:const TextStyle(fontSize:10,color:Color(0xffffdb70))),
        ]),
      ),
    ]),
  );

  Widget _inventoryWindow()=>Container(
    decoration:BoxDecoration(
      color:const Color(0xe6241a12),
      border:Border.all(color:const Color(0xff9b7c54),width:2),
      boxShadow:const [BoxShadow(color:Colors.black87,blurRadius:12)],
    ),
    child:Column(children:[
      Container(
        height:34,
        padding:const EdgeInsets.symmetric(horizontal:10),
        decoration:const BoxDecoration(
          gradient:LinearGradient(colors:[Color(0xff5b3421),Color(0xff2b1810)]),
        ),
        child:Row(children:[
          const Expanded(child:Text('Inventario',style:TextStyle(color:Color(0xffffdc72),fontSize:12,fontWeight:FontWeight.bold))),
          Text(inventory.length.toString()+' objetos',style:const TextStyle(fontSize:9,color:Colors.white60)),
          const SizedBox(width:6),
          GestureDetector(onTap:onToggleInventory,child:const Icon(Icons.close,size:17,color:Colors.white70)),
        ]),
      ),
      Expanded(
        child:inventory.isEmpty
          ?const Center(child:Text('Sin objetos',style:TextStyle(color:Colors.white54,fontSize:11)))
          :GridView.builder(
              padding:const EdgeInsets.all(9),
              gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount:5,crossAxisSpacing:5,mainAxisSpacing:5,childAspectRatio:1,
              ),
              itemCount:inventory.length,
              itemBuilder:(context,index){
                final item=inventory[index];
                final gems=item.gems.where((g)=>g>0).length;
                final localized=catalog.itemText(item.type,item.typeId,locale);
                final itemName=catalog.itemName(item.type,item.typeId,locale);
                final description=localized?.text.trim()??'';
                final rule=metadata?.item(item.type,item.typeId);
                final iconPath=rule?.iconPath;
                final cell=Tooltip(
                  waitDuration:const Duration(milliseconds:250),
                  message:itemName+
                    '\nBag ${item.bag} · Slot ${item.slot} · ${item.type}:${item.typeId}'+
                    '\nCalidad ${item.quality} · Cantidad ${item.count} · Lapis/Gemas: $gems'+
                    (description.isEmpty?'':'\n\n'+description)+
                    (item.craftName.isEmpty?'':'\n'+item.craftName)+
                    (item.dyed?'\nTeñido':''),
                  child:Container(
                    decoration:BoxDecoration(
                      color:const Color(0xff17120e),
                      border:Border.all(color:item.quality>0?const Color(0xffa88955):const Color(0xff52483c)),
                    ),
                    child:Stack(children:[
                      Center(
                        child:iconPath!=null
                          ?DataImage(
                              cache:ui,
                              path:iconPath,
                              fit:BoxFit.contain,
                              fallback:Icon(
                                item.type<=16?Icons.shield:Icons.inventory_2,
                                size:26,color:item.quality>0?const Color(0xffffd177):const Color(0xffc0b49d),
                              ),
                            )
                          :Icon(
                              item.type<=16?Icons.shield:Icons.inventory_2,
                              size:26,color:item.quality>0?const Color(0xffffd177):const Color(0xffc0b49d),
                            ),
                      ),
                      Positioned(left:2,top:1,child:Text(
                        '${item.type}:${item.typeId}',
                        style:const TextStyle(fontSize:6.5,color:Colors.white54),
                      )),
                      if(item.count>1)Positioned(right:2,bottom:1,child:Text(
                        'x${item.count}',style:const TextStyle(fontSize:8,color:Colors.white),
                      )),
                      if(gems>0)Positioned(left:2,bottom:1,child:Text(
                        '◆$gems',style:const TextStyle(fontSize:8,color:Color(0xff7fd9ff)),
                      )),
                    ]),
                  ),
                );
                return warehouseOpen
                  ?GestureDetector(
                      onDoubleTap:()=>onStoreWarehouse(item),
                      child:cell,
                    )
                  :shopOpen
                    ?GestureDetector(
                        onDoubleTap:()=>onSellInventory(item),
                        child:cell,
                      )
                    :GestureDetector(
                        onDoubleTap:()=>onActivateInventory(item),
                        child:cell,
                      );
              },
            ),
      ),
      Container(
        height:30,padding:const EdgeInsets.symmetric(horizontal:10),
        child:Row(children:[
          Text('Oro: $gold',style:const TextStyle(fontSize:10,color:Color(0xffffdb70))),
          const Spacer(),
          Text('Bolsas: ${inventory.map((e)=>e.bag).toSet().length}',style:const TextStyle(fontSize:9,color:Colors.white54)),
        ]),
      ),
    ]),
  );

  Widget _questRewardCell(QuestRewardItem reward,int index){
    final rule=metadata?.item(reward.type,reward.id);
    final icon=rule?.iconPath;
    final name=catalog.itemName(reward.type,reward.id,locale);
    final text=catalog.itemText(reward.type,reward.id,locale)?.text.trim()??'';
    final cell=Container(
      width:42,height:42,
      decoration:BoxDecoration(
        color:const Color(0x66d9cfb6),
        border:Border.all(color:rewardSelection?const Color(0xffffd45f):const Color(0xff6a4b2d),width:rewardSelection?2:1),
      ),
      child:Stack(children:[
        Positioned.fill(
          child:icon==null
            ?const Icon(Icons.auto_awesome,color:Color(0xff6e5ac8),size:21)
            :DataImage(
                cache:ui,path:icon,fit:BoxFit.contain,
                fallback:const Icon(Icons.auto_awesome,color:Color(0xff6e5ac8),size:21),
              ),
        ),
        if(reward.count>1)Positioned(
          right:1,bottom:0,
          child:Text('x${reward.count}',style:const TextStyle(fontSize:8,color:Colors.white,shadows:[Shadow(color:Colors.black,blurRadius:2)])),
        ),
      ]),
    );
    return Tooltip(
      message:name+
        '\n${reward.type}:${reward.id} · x${reward.count}'+
        (text.isEmpty?'':'\n\n'+text)+
        (rewardSelection?'\n\n'+(locale=='spn'?'Haz clic para elegir esta recompensa.':'Click to choose this reward.'):''),
      waitDuration:const Duration(milliseconds:250),
      child:rewardSelection?GestureDetector(onTap:()=>onSelectReward(index),child:cell):cell,
    );
  }

  Widget _questWindow() {
    final text=catalog.questText(locale)?.quest(questId);
    final rule=metadata?.quests[questId];
    final title=text!=null&&text.name.isNotEmpty?text.name:'Operación básica de la interfaz';
    final body=text!=null&&text.initialDescription.isNotEmpty
      ?text.initialDescription
      :'Aprende a moverte, reconocer la interfaz y hablar con los habitantes de la zona.';
    final rewards=rule?.rewards??const <QuestRewardItem>[];

    return Stack(children:[
      Positioned.fill(
        child:DataImage(
          cache:ui,
          path:'interface/quest/take.tga',
          fit:BoxFit.fill,
          fallback:DataImage(cache:ui,path:'interface/quest/quest.tga',fit:BoxFit.fill),
        ),
      ),
      Positioned(
        left:29,top:28,right:24,
        child:Text(
          title,
          maxLines:1,
          overflow:TextOverflow.ellipsis,
          style:const TextStyle(
            color:Color(0xffffdf69),
            fontSize:11,
            fontWeight:FontWeight.bold,
            shadows:[Shadow(color:Colors.black,blurRadius:2)],
          ),
        ),
      ),
      Positioned(
        left:18,top:62,right:18,height:238,
        child:SingleChildScrollView(
          child:Text(
            body,
            style:const TextStyle(
              color:Color(0xff321d11),
              fontSize:10,
              height:1.44,
              shadows:[Shadow(color:Color(0x22000000),blurRadius:1)],
            ),
          ),
        ),
      ),
      Positioned(
        left:18,top:309,right:18,
        child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(
            rewardSelection
              ?(locale=='spn'?'Elige tu recompensa':'Choose your reward')
              :(locale=='spn'?'Recompensa':'Reward'),
            style:const TextStyle(color:Color(0xff321d11),fontSize:10,fontWeight:FontWeight.w600),
          ),
          const SizedBox(height:5),
          Row(children:[
            ...List.generate(rewards.length>4?4:rewards.length,(i)=>Padding(
              padding:const EdgeInsets.only(right:6),
              child:_questRewardCell(rewards[i],i),
            )),
            if(rewards.isEmpty)
              Container(
                width:42,height:42,
                decoration:BoxDecoration(color:const Color(0x66d9cfb6),border:Border.all(color:const Color(0xff6a4b2d))),
                child:const Icon(Icons.auto_awesome,color:Color(0xff6e5ac8),size:20),
              ),
          ]),
          const SizedBox(height:5),
          Text(
            'XP ${rule?.xp??0} · Oro ${rule?.money??0}'+
              ((rule?.nextQuestId??0)>0?' · → Q${rule!.nextQuestId}':''),
            style:const TextStyle(fontSize:8.5,color:Color(0xff432817)),
          ),
        ]),
      ),
      if(!rewardSelection)
        Positioned(
          left:35,right:35,bottom:18,
          child:Row(
            mainAxisAlignment:MainAxisAlignment.spaceBetween,
            children:[
              shaiyaRedButton(
                questActive
                  ?(locale=='spn'?'Completar':'Complete')
                  :(locale=='spn'?'Aceptar':'Accept'),
                onAcceptQuest,
                width:78,height:31,fontSize:10,
              ),
              shaiyaRedButton(
                locale=='spn'?'Cancelar':'Cancel',
                onCancelQuest,
                width:78,height:31,fontSize:10,
              ),
            ],
          ),
        )
      else
        Positioned(
          left:35,right:35,bottom:18,
          child:Center(
            child:shaiyaRedButton(
              locale=='spn'?'Cerrar':'Close',
              onCancelQuest,
              width:100,height:31,fontSize:10,
            ),
          ),
        ),
    ]);
  }
}

class _ChatInput extends StatefulWidget {
  final ValueChanged<String> onSend;
  const _ChatInput({required this.onSend});
  @override State<_ChatInput> createState()=>_ChatInputState();
}

class _ChatInputState extends State<_ChatInput> {
  final controller=TextEditingController();
  @override void dispose(){controller.dispose();super.dispose();}
  void send(String value){
    final text=value.trim();if(text.isEmpty)return;
    widget.onSend(text);controller.clear();
  }
  @override Widget build(BuildContext context)=>TextField(
    controller:controller,
    onSubmitted:send,
    textInputAction:TextInputAction.send,
    style:const TextStyle(fontSize:10,color:Colors.white),
    cursorColor:const Color(0xffffd46a),
    decoration:InputDecoration(
      isDense:true,
      contentPadding:const EdgeInsets.symmetric(horizontal:7,vertical:5),
      hintText:'Enter…',
      hintStyle:const TextStyle(fontSize:9,color:Colors.white38),
      filled:true,
      fillColor:const Color(0xaa080808),
      border:OutlineInputBorder(
        borderRadius:BorderRadius.zero,
        borderSide:const BorderSide(color:Color(0xff665745)),
      ),
      enabledBorder:const OutlineInputBorder(
        borderRadius:BorderRadius.zero,
        borderSide:BorderSide(color:Color(0xff665745)),
      ),
      focusedBorder:const OutlineInputBorder(
        borderRadius:BorderRadius.zero,
        borderSide:BorderSide(color:Color(0xffb08a54)),
      ),
    ),
  );
}

class _WeatherPainter extends CustomPainter {
  final PsMapWeather weather;
  _WeatherPainter(this.weather);

  @override
  void paint(Canvas canvas,Size size){
    final power=weather.power.clamp(1,3).toInt();
    final count=weather.rain?(35+power*28):(weather.snow?25+power*20:0);
    if(count==0)return;
    final tick=DateTime.now().millisecondsSinceEpoch~/50;
    if(weather.rain){
      final paint=Paint()
        ..color=Color.fromARGB(55+power*22,180,210,255)
        ..strokeWidth=.7+power*.25
        ..strokeCap=StrokeCap.round;
      for(var i=0;i<count;i++){
        final x=((i*83+tick*11)%1000)/1000*size.width;
        final y=((i*173+tick*23)%1000)/1000*size.height;
        final len=6.0+power*3+i%4;
        canvas.drawLine(Offset(x,y),Offset(x-2.5-power,y+len),paint);
      }
    }else if(weather.snow){
      final paint=Paint()..color=Color.fromARGB(95+power*32,245,250,255);
      for(var i=0;i<count;i++){
        final x=((i*97+tick*(2+power))%1000)/1000*size.width;
        final y=((i*151+tick*(3+power))%1000)/1000*size.height;
        canvas.drawCircle(Offset(x,y),.8+((i+power)%3)*.55,paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WeatherPainter oldDelegate)=>true;
}

class _MiniMapPainter extends CustomPainter {
  final StudioScene scene;
  _MiniMapPainter(this.scene);

  Offset _worldToMap(double worldX,double worldZ,Size size){
    final worldSize=(scene.world?.size??0).toDouble();
    if(worldSize<=0){
      final x=((worldX-scene.originX)/120+.5).clamp(0.0,1.0);
      final y=((worldZ-scene.originZ)/120+.5).clamp(0.0,1.0);
      return Offset(x*size.width,y*size.height);
    }
    final x=(worldX/worldSize).clamp(0.0,1.0);
    final y=(worldZ/worldSize).clamp(0.0,1.0);
    return Offset(x*size.width,y*size.height);
  }

  @override
  void paint(Canvas canvas, Size size) {
    for(final label in scene.gameLabels){
      final a=label.actor;
      final worldX=scene.originX+a.root.position.x;
      final worldZ=scene.originZ-a.root.position.z;
      final p=_worldToMap(worldX,worldZ,size);
      canvas.drawCircle(
        p,
        label.mob?2.1:2.0,
        Paint()..color=label.mob?const Color(0xffff3f27):const Color(0xff5be5ff),
      );
    }

    final me=scene.character;
    final px=scene.originX+(me?.root.position.x??0);
    final pz=scene.originZ-(me?.root.position.z??0);
    final center=_worldToMap(px,pz,size);
    final angle=-(me?.root.rotation.y??0);
    const radius=6.0;
    final path=Path()
      ..moveTo(
        center.dx+math.sin(angle)*radius,
        center.dy-math.cos(angle)*radius,
      )
      ..lineTo(
        center.dx+math.sin(angle+2.45)*radius*.78,
        center.dy-math.cos(angle+2.45)*radius*.78,
      )
      ..lineTo(
        center.dx+math.sin(angle-2.45)*radius*.78,
        center.dy-math.cos(angle-2.45)*radius*.78,
      )
      ..close();
    canvas.drawPath(path,Paint()..color=const Color(0xffffdf2f));
    canvas.drawPath(
      path,
      Paint()
        ..color=Colors.white
        ..style=PaintingStyle.stroke
        ..strokeWidth=1,
    );
  }

  @override
  bool shouldRepaint(covariant _MiniMapPainter oldDelegate) => true;
}
