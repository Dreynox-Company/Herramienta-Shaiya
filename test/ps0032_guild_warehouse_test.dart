import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/game/ps0032_protocol.dart';

void _name(Uint8List b,int offset,String value){
  final raw=latin1.encode(value),n=raw.length>20?20:raw.length;
  b.setRange(offset,offset+n,raw);
}

void _putGuildItem(Uint8List b,int o,{int slot=17,int type=5,int id=6}){
  final d=ByteData.sublistView(b);
  b[o]=slot;b[o+1]=type;b[o+2]=id;
  d.setUint16(o+3,444,Endian.little);
  for(var i=0;i<6;i++)d.setInt32(o+5+i*4,200+i,Endian.little);
  b[o+29]=4;
  b[o+52]=1;
  _name(b,o+79,'GUILDCRAFT');
  b[o+99]=0;
}

void main(){
  test('parses exact 100-byte GUILD_WAREHOUSE_ITEM_LIST record',(){
    final b=Uint8List(1+100);b[0]=1;_putGuildItem(b,1);
    final items=parseGuildWarehouseItems(PsPacket(PsPacketType.guildWarehouseItemList,b));
    expect(items.length,1);
    final x=items.single;
    expect((x.bag,x.slot,x.type,x.typeId),(255,17,5,6));
    expect(x.quality,444);
    expect(x.gems,[200,201,202,203,204,205]);
    expect(x.count,4);
    expect(x.dyed,isTrue);
    expect(x.craftName,'GUILDCRAFT');
  });

  test('parses guild warehouse add/remove actor id',(){
    final add=Uint8List(104);_putGuildItem(add,0,slot:9,type:11,id:12);
    ByteData.sublistView(add).setUint32(100,123456,Endian.little);
    final a=PsGuildWarehouseMutation.parse(PsPacket(PsPacketType.guildWarehouseItemAdd,add));
    expect((a.item.bag,a.item.slot,a.item.type,a.item.typeId),(255,9,11,12));
    expect(a.characterId,123456);

    final remove=Uint8List.fromList(add);
    final r=PsGuildWarehouseMutation.parse(PsPacket(PsPacketType.guildWarehouseItemRemove,remove));
    expect(r.item.slot,9);expect(r.characterId,123456);
  });
}
