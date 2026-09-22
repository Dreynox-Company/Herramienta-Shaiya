import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/game/ps0032_protocol.dart';

void main(){
  test('parses ENCHANT_RATE 10-slot authoritative response',(){
    final b=Uint8List(100),d=ByteData.sublistView(b);
    for(var i=0;i<10;i++){b[i]=i+1;b[10+i]=20+i;d.setInt32(20+i*4,100+i,Endian.little);d.setUint32(60+i*4,5000+i,Endian.little);}
    final r=PsEnchantRate.parse(PsPacket(PsPacketType.enchantRate,b));
    expect(r.lapisiaBag,[1,2,3,4,5,6,7,8,9,10]);
    expect(r.lapisiaSlot,[20,21,22,23,24,25,26,27,28,29]);
    expect(r.rates.first,100);
    expect(r.rates.last,109);
    expect(r.gold.first,5000);
    expect(r.gold.last,5009);
  });

  test('parses ENCHANT_ADD result and craft name',(){
    final b=Uint8List(33),d=ByteData.sublistView(b);
    b[0]=1;b[1]=2;b[2]=3;b[3]=4;b[4]=1;b[5]=7;
    d.setUint32(6,12345,Endian.little);b[10]=1;b[11]=0;
    final name='STR+5'.codeUnits;b.setRange(12,12+name.length,name);b[32]=0;
    final r=PsEnchantResult.parse(PsPacket(PsPacketType.enchantAdd,b));
    expect(r.success,isTrue);
    expect((r.lapisiaBag,r.lapisiaSlot,r.lapisiaCount,r.itemBag,r.itemSlot),(2,3,4,1,7));
    expect(r.gold,12345);
    expect(r.autoEnchant,isTrue);
    expect(r.safetyScrollLeft,isTrue);
    expect(r.craftName,'STR+5');
  });

  test('parses normal and absolute composition results',(){
    final normal=Uint8List(24);
    normal[0]=0;normal[1]=1;normal[2]=8;
    final n='DEX+4'.codeUnits;normal.setRange(3,3+n.length,n);
    final a=PsComposeResult.parse(PsPacket(PsPacketType.itemCompose,normal));
    expect((a.success,a.absolute,a.bag,a.slot,a.craftName),(true,false,1,8,'DEX+4'));

    final absolute=Uint8List(23);
    absolute[0]=0;final m='LUC+7'.codeUnits;absolute.setRange(1,1+m.length,m);absolute[22]=1;
    final b=PsComposeResult.parse(PsPacket(PsPacketType.itemComposeAbsolute,absolute));
    expect((b.success,b.absolute,b.craftName),(true,true,'LUC+7'));
  });

  test('parses rune synthesis result',(){
    expect(PsRuneSynthesizeResult.parse(PsPacket(PsPacketType.runeSynthesize,Uint8List.fromList([0]))).success,isTrue);
    expect(PsRuneSynthesizeResult.parse(PsPacket(PsPacketType.runeSynthesize,Uint8List.fromList([1]))).success,isFalse);
  });

  test('advanced blacksmith parsers reject truncation',(){
    expect(()=>PsEnchantRate.parse(PsPacket(PsPacketType.enchantRate,Uint8List(99))),throwsFormatException);
    expect(()=>PsEnchantResult.parse(PsPacket(PsPacketType.enchantAdd,Uint8List(32))),throwsFormatException);
    expect(()=>PsComposeResult.parse(PsPacket(PsPacketType.itemCompose,Uint8List(23))),throwsFormatException);
    expect(()=>PsComposeResult.parse(PsPacket(PsPacketType.itemComposeAbsolute,Uint8List(22))),throwsFormatException);
    expect(()=>PsRuneSynthesizeResult.parse(PsPacket(PsPacketType.runeSynthesize,Uint8List(0))),throwsFormatException);
  });
}
