import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/game/ps0032_protocol.dart';

void main(){
  test('parses duel request and response',(){
    final req=Uint8List(8),d=ByteData.sublistView(req);
    d.setUint32(0,100,Endian.little);
    d.setUint32(4,200,Endian.little);
    final request=PsDuelRequest.parse(PsPacket(PsPacketType.duelRequest,req));
    expect((request.starterId,request.opponentId),(100,200));

    final res=Uint8List(5),rd=ByteData.sublistView(res);
    res[0]=1;rd.setUint32(1,200,Endian.little);
    final response=PsDuelResponse.parse(PsPacket(PsPacketType.duelResponse,res));
    expect(response.accepted,isTrue);
    expect(response.characterId,200);
  });

  test('parses duel wager events',(){
    final ack=PsDuelTradeItemAck.parse(PsPacket(PsPacketType.duelTradeAddItem,Uint8List.fromList([2,7,3,4])));
    expect((ack.bag,ack.slot,ack.count,ack.tradeSlot),(2,7,3,4));

    final money=Uint8List(5),md=ByteData.sublistView(money);
    money[0]=2;md.setUint32(1,123456,Endian.little);
    final parsedMoney=PsDuelTradeMoney.parse(PsPacket(PsPacketType.duelTradeAddMoney,money));
    expect(parsedMoney.senderType,2);
    expect(parsedMoney.money,123456);

    final approval=PsDuelTradeApproval.parse(PsPacket(PsPacketType.duelTradeOk,Uint8List.fromList([1,0])));
    expect(approval.senderType,1);
    expect(approval.approved,isTrue);
  });

  test('parses duel opponent item TradeItem payload',(){
    final b=Uint8List(108),d=ByteData.sublistView(b);
    b[0]=3;b[1]=8;b[2]=9;b[3]=2;
    d.setUint16(4,555,Endian.little);
    b[36]=1;
    for(var i=0;i<6;i++)d.setInt32(63+i*4,100+i,Endian.little);
    final name='DUEL'.codeUnits;
    b.setRange(87,87+name.length,name);
    final item=PsDuelTradeItem.parse(PsPacket(PsPacketType.duelTradeOpponentAddItem,b));
    expect((item.tradeSlot,item.type,item.typeId,item.count),(3,8,9,2));
    expect(item.quality,555);
    expect(item.gems,[100,101,102,103,104,105]);
    expect(item.craftName,'DUEL');
    expect(item.dyed,isTrue);
  });

  test('parses duel ready cancel and result',(){
    final ready=Uint8List(8),d=ByteData.sublistView(ready);
    d.setFloat32(0,123.5,Endian.little);d.setFloat32(4,456.25,Endian.little);
    final parsedReady=PsDuelReady.parse(PsPacket(PsPacketType.duelReady,ready));
    expect(parsedReady.x,closeTo(123.5,1e-6));
    expect(parsedReady.z,closeTo(456.25,1e-6));

    final cancel=Uint8List(5),cd=ByteData.sublistView(cancel);
    cancel[0]=4;cd.setUint32(1,77,Endian.little);
    final parsedCancel=PsDuelCancel.parse(PsPacket(PsPacketType.duelCancel,cancel));
    expect((parsedCancel.reason,parsedCancel.playerId),(4,77));

    final win=PsDuelResult.parse(PsPacket(PsPacketType.duelWinLose,Uint8List.fromList([1])));
    final lose=PsDuelResult.parse(PsPacket(PsPacketType.duelWinLose,Uint8List.fromList([2])));
    expect(win.won,isTrue);expect(win.lost,isFalse);
    expect(lose.lost,isTrue);expect(lose.won,isFalse);
  });
}
