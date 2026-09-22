import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/game/ps0032_protocol.dart';

void _putName(Uint8List b,int offset,String value){
  final raw=latin1.encode(value);
  final n=raw.length>20?20:raw.length;
  b.setRange(offset,offset+n,raw);
}

void main(){
  test('parses exact 102-byte CHARACTER_ITEMS record',(){
    final b=Uint8List(1+102),d=ByteData.sublistView(b);
    b[0]=1; // record count
    const o=1;
    b[o]=2;b[o+1]=7;b[o+2]=11;b[o+3]=22;
    d.setUint16(o+4,333,Endian.little);
    for(var i=0;i<6;i++)d.setInt32(o+6+i*4,100+i,Endian.little);
    b[o+30]=9;
    _putName(b,o+31,'CRAFT');
    b[o+51]=0; // CraftName.IsDisabled
    b[o+75]=1; // IsItemDyed
    final items=parseInventoryItems(PsPacket(PsPacketType.characterItems,b));
    expect(items.length,1);
    final x=items.single;
    expect((x.bag,x.slot,x.type,x.typeId),(2,7,11,22));
    expect(x.quality,333);
    expect(x.gems,[100,101,102,103,104,105]);
    expect(x.count,9);
    expect(x.craftName,'CRAFT');
    expect(x.dyed,isTrue);
  });

  test('parses exact 108-byte warehouse record',(){
    final b=Uint8List(1+108),d=ByteData.sublistView(b);
    b[0]=1;
    const o=1;
    b[o]=17;b[o+1]=5;b[o+2]=6;
    d.setUint16(o+3,444,Endian.little);
    for(var i=0;i<6;i++)d.setInt32(o+5+i*4,200+i,Endian.little);
    b[o+29]=4;
    b[o+60]=1;
    _putName(b,o+87,'WAREHOUSE');
    b[o+107]=0; // CraftName.IsDisabled
    final items=parseWarehouseItems(PsPacket(PsPacketType.warehouseItemList,b));
    expect(items.length,1);
    final x=items.single;
    expect((x.slot,x.type,x.typeId),(17,5,6));
    expect(x.quality,444);
    expect(x.gems,[200,201,202,203,204,205]);
    expect(x.count,4);
    expect(x.craftName,'WAREHOUSE');
    expect(x.dyed,isTrue);
  });

  test('parses US 0x0204 move packet including warehouse bag',(){
    final b=Uint8List(212),d=ByteData.sublistView(b);
    d.setUint32(0,0,Endian.little); // SHAIYA_US prefix
    // source empty at bag 2 slot 3
    b[4]=2;b[5]=3;
    // destination warehouse bag 100, slot 9
    const o=106;
    b[o]=100;b[o+1]=9;b[o+2]=8;b[o+3]=12;b[o+4]=2;
    d.setUint16(o+5,555,Endian.little);
    b[o+30]=1;
    d.setInt32(o+57,88,Endian.little);
    _putName(b,o+81,'MOVE');
    d.setUint32(208,123456,Endian.little);
    final move=PsInventoryMove.parse(PsPacket(PsPacketType.inventoryMoveItem,b));
    expect((move.source.bag,move.source.slot,move.source.type),(2,3,0));
    expect((move.destination.bag,move.destination.slot),(100,9));
    expect((move.destination.type,move.destination.typeId),(8,12));
    expect(move.destination.count,2);
    expect(move.destination.quality,555);
    expect(move.destination.gems.first,88);
    expect(move.destination.craftName,'MOVE');
    expect(move.gold,123456);
  });

  test('parses NPC buy/sell response',(){
    final b=Uint8List(10),d=ByteData.sublistView(b);
    b[0]=0;b[1]=1;b[2]=4;b[3]=7;b[4]=8;b[5]=3;
    d.setUint32(6,9999,Endian.little);
    final result=PsNpcTradeResult.parse(PsPacket(PsPacketType.npcBuyItem,b));
    expect(result.success,isTrue);
    expect((result.bag,result.slot,result.type,result.typeId,result.count),(1,4,7,8,3));
    expect(result.gold,9999);
  });
}
