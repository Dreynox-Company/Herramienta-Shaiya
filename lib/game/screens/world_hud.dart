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
  final int level;
  final PsCharacterDetails? details;
  final PsHitpoints? hitpoints;
  final int? targetMobGlobalId,targetMobId,targetHp,targetMaxHp;
  final PsSkillBook? skillBook;
  final PsSkillBar? skillBar;
  final List<PsInventoryItem> inventory,warehouse;
  final int gold;
  final NpcShopRule? shop;
  final bool inventoryOpen,shopOpen,warehouseOpen;
  final VoidCallback onCloseShop,onCloseWarehouse;
  final ValueChanged<int> onBuyShopProduct;
  final ValueChanged<PsInventoryItem> onSellInventory,onStoreWarehouse,onWithdrawWarehouse;
  final VoidCallback onToggleInventory;
  final ValueChanged<int> onHotbar;
  final UiAssetCache ui;
  final List<String> messages;
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
    required this.level,
    required this.details,
    required this.hitpoints,
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
    required this.inventoryOpen,
    required this.shopOpen,
    required this.warehouseOpen,
    required this.onCloseShop,
    required this.onCloseWarehouse,
    required this.onBuyShopProduct,
    required this.onSellInventory,
    required this.onStoreWarehouse,
    required this.onWithdrawWarehouse,
    required this.onToggleInventory,
    required this.onHotbar,
    required this.locale,
    required this.ui,
    required this.messages,
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
          Positioned(left: 215, top: 5, width: 520, height: 48, child: _topHotbar()),
          Positioned(right: 8, top: 8, width: 188, height: 232, child: _minimap()),
          if(targetMobId!=null)
            Positioned(left:390,top:60,width:245,height:48,child:_targetHud()),
          Positioned(left: 4, top: 363, width: 360, height: 290, child: _chat()),
          Positioned(left: 0, right: 0, bottom: 0, height: 58, child: _bottomHud()),
          ..._worldLabels(),
          if(shopOpen&&shop!=null)
            Positioned(
              right:198,top:250,width:292,height:390,
              child:_shopWindow(),
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
          if (questOpen)
            Positioned(
              left: 566,
              top: 118,
              width: 247,
              height: 505,
              child: _questWindow(),
            ),
        ],
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
                        path:'interface/minimap/1.tga',
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
      left:12,top:52,right:20,bottom:10,
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
        _bottomButton('interface/main_bottom_btn_status.tga'),
        _bottomButton('interface/main_bottom_btn_skill.tga'),
        _bottomButton('interface/main_bottom_btn_item.tga',onTap:onToggleInventory),
        _bottomButton('interface/main_bottom_btn_quest.tga'),
        _bottomButton('interface/main_bottom_btn_sub.tga'),
        _bottomButton('interface/main_bottom_btn_guild.tga'),
        _bottomButton('interface/main_bottom_btn_shop.tga'),
        _bottomButton('interface/main_bottom_btn_option.tga'),
        _bottomButton('interface/main_bottom_btn_event.tga'),
        _bottomButton('interface/main_bottom_btn_helper.tga'),
      ]),
    ),
  ]);

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
                    :cell;
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

class _MiniMapPainter extends CustomPainter {
  final StudioScene scene;
  _MiniMapPainter(this.scene);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0x5535452b),
    );

    for (final a in scene.gameActors) {
      final x = (a.root.position.x / 120 + .5).clamp(0.0, 1.0);
      final y = (a.root.position.z / 120 + .5).clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(x * size.width, y * size.height),
        2.2,
        Paint()..color = const Color(0xffff3f27),
      );
    }

    canvas.drawCircle(
      Offset(size.width * .5, size.height * .5),
      4,
      Paint()..color = const Color(0xffffdf2f),
    );
    canvas.drawCircle(
      Offset(size.width * .5, size.height * .5),
      7,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _MiniMapPainter oldDelegate) => true;
}
