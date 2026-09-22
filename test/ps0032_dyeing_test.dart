import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/game/ps0032_protocol.dart';

void main(){
  test('parses dye target selection response',(){
    expect(
      PsDyeSelectionResult.parse(
        PsPacket(PsPacketType.dyeSelectItem,Uint8List.fromList([1])),
      ).success,
      isTrue,
    );
    expect(
      PsDyeSelectionResult.parse(
        PsPacket(PsPacketType.dyeSelectItem,Uint8List.fromList([0])),
      ).success,
      isFalse,
    );
  });

  test('parses exact 5 x 27-byte DYE_REROLL palette layout',(){
    final body=Uint8List(27*5);
    for(var i=0;i<5;i++){
      final o=i*27;
      body[o]=1;
      body[o+1]=200;
      body[o+2]=35+i*10;
      body[o+3]=10+i;
      body[o+4]=20+i;
      body[o+5]=30+i;
      for(var j=6;j<27;j++)body[o+j]=0;
    }
    final palette=PsDyePalette.parse(PsPacket(PsPacketType.dyeReroll,body));
    expect(palette.colors.length,5);
    expect(
      (
        palette.colors.first.enabled,
        palette.colors.first.alpha,
        palette.colors.first.saturation,
        palette.colors.first.r,
        palette.colors.first.g,
        palette.colors.first.b,
      ),
      (true,200,35,10,20,30),
    );
    expect(palette.colors.last.saturation,75);
  });

  test('parses DYE_CONFIRM result color',(){
    final result=PsDyeConfirmResult.parse(
      PsPacket(PsPacketType.dyeConfirm,Uint8List.fromList([1,200,85,120,80,40])),
    );
    expect(result.success,isTrue);
    expect(
      (result.color.alpha,result.color.saturation,result.color.r,result.color.g,result.color.b),
      (200,85,120,80,40),
    );
    expect(result.color.argb,0xc8785028);
  });

  test('dye packet parsers reject malformed layouts',(){
    expect(
      ()=>PsDyeSelectionResult.parse(PsPacket(PsPacketType.dyeSelectItem,Uint8List(0))),
      throwsFormatException,
    );
    expect(
      ()=>PsDyePalette.parse(PsPacket(PsPacketType.dyeReroll,Uint8List(28))),
      throwsFormatException,
    );
    expect(
      ()=>PsDyeConfirmResult.parse(PsPacket(PsPacketType.dyeConfirm,Uint8List(5))),
      throwsFormatException,
    );
  });
}
