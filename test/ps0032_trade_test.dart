import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/game/ps0032_protocol.dart';

void fixed(Uint8List b,int offset,int length,String value){
  final raw=utf8.encode(value),n=raw.length<length?raw.length:length;
  b.setRange(offset,offset+n,raw);
}

void main(){
  test('parses exact 108-byte remote trade item',(){
    final b=Uint8List(108),d=ByteData.sublistView(b);
    b[0]=3;b[1]=7;b[2]=9;b[3]=4;
    d.setUint16(4,555,Endian.little);
    b[36]=1;
    for(var i=0;i<6;i++)d.setInt32(63+i*4,100+i,Endian.little);
    fixed(b,87,20,'TRADECRAFT');
    final item=PsTradeItem.parse(PsPacket(PsPacketType.tradeReceiverAddItem,b));
    expect((item.tradeSlot,item.type,item.typeId,item.count,item.quality),(3,7,9,4,555));
    expect(item.gems,[100,101,102,103,104,105]);
    expect(item.craftName,'TRADECRAFT');
    expect(item.dyed,isTrue);
  });

  test('parses local trade item acknowledgement',(){
    final ack=PsTradeOwnerItemAck.parse(
      PsPacket(PsPacketType.tradeOwnerAddItem,Uint8List.fromList([2,11,5,6])),
    );
    expect((ack.bag,ack.slot,ack.count,ack.tradeSlot),(2,11,5,6));
  });

  test('parses trade money decide and confirmation events',(){
    final money=Uint8List(5),md=ByteData.sublistView(money);
    money[0]=2;md.setUint32(1,123456,Endian.little);
    final m=PsTradeMoney.parse(PsPacket(PsPacketType.tradeAddMoney,money));
    expect((m.byWho,m.money),(2,123456));

    final d=PsTradeDecision.parse(
      PsPacket(PsPacketType.tradeDecide,Uint8List.fromList([1,1])),
    );
    expect((d.byWho,d.decided),(1,true));

    final c=PsTradeConfirmation.parse(
      PsPacket(PsPacketType.tradeFinish,Uint8List.fromList([2,0])),
    );
    expect((c.byWho,c.declined),(2,false));
  });
}
