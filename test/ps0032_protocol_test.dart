import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/game/ps0032_protocol.dart';

void main(){
  test('parsea CHARACTER_DETAILS ps0032 con stats y posicion reales',(){
    final body=Uint8List(58);
    final d=ByteData.sublistView(body);
    var o=0;
    for(final v in [12,13,14,15,16,17,3,4]){
      d.setUint16(o,v,Endian.little);o+=2;
    }
    d.setUint32(16,255,Endian.little);
    d.setUint32(20,95,Endian.little);
    d.setUint32(24,180,Endian.little);
    d.setUint16(28,90,Endian.little);
    d.setUint32(30,1000,Endian.little);
    d.setUint32(34,2000,Endian.little);
    d.setUint32(38,1250,Endian.little);
    d.setUint32(42,777,Endian.little);
    d.setFloat32(46,580.0,Endian.little);
    d.setFloat32(50,78.68,Endian.little);
    d.setFloat32(54,1769.8774,Endian.little);

    final x=PsCharacterDetails.parse(PsPacket(PsPacketType.characterDetails,body));
    expect(x.strength,12);
    expect(x.luck,17);
    expect(x.statPoints,3);
    expect(x.skillPoints,4);
    expect(x.maxHp,255);
    expect(x.maxMp,95);
    expect(x.maxSp,180);
    expect(x.angle,90);
    expect(x.currentExp,1250);
    expect(x.gold,777);
    expect(x.x,closeTo(580,1e-4));
    expect(x.y,closeTo(78.68,1e-3));
    expect(x.z,closeTo(1769.8774,1e-3));
  });

  test('parsea CHARACTER_CURRENT_HITPOINTS reales',(){
    final body=Uint8List(12);
    final d=ByteData.sublistView(body)
      ..setInt32(0,200,Endian.little)
      ..setInt32(4,75,Endian.little)
      ..setInt32(8,150,Endian.little);
    final x=PsCharacterHitpoints.parse(
      PsPacket(PsPacketType.characterCurrentHitpoints,body),
    );
    expect(x.hp,200);
    expect(x.mp,75);
    expect(x.sp,150);
  });
}
