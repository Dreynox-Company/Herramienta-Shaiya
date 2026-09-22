import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/game/ps0032_protocol.dart';

void main(){
  test('parses authoritative mount shape update',(){
    final b=Uint8List(13),d=ByteData.sublistView(b);
    d.setUint32(0,77,Endian.little);
    b[4]=222;
    d.setUint32(5,42,Endian.little);
    d.setUint32(9,9,Endian.little);
    final update=PsShapeUpdate.parse(PsPacket(PsPacketType.characterShapeUpdate,b));
    expect(update.characterId,77);
    expect(update.shape,222);
    expect(update.param1,42);
    expect(update.param2,9);
    expect(update.mounted,isTrue);
  });

  test('parses mount use result',(){
    final state=PsUseVehicleState.parse(
      PsPacket(PsPacketType.useVehicle,Uint8List.fromList([1,1])),
    );
    expect(state.success,isTrue);
    expect(state.mounted,isTrue);

    final rejected=PsUseVehicleState.parse(
      PsPacket(PsPacketType.useVehicle,Uint8List.fromList([0,0])),
    );
    expect(rejected.success,isFalse);
    expect(rejected.mounted,isFalse);
  });

  test('parses shared mount passenger state',(){
    final b=Uint8List(8),d=ByteData.sublistView(b);
    d.setUint32(0,101,Endian.little);
    d.setUint32(4,202,Endian.little);
    final passenger=PsVehiclePassenger.parse(PsPacket(PsPacketType.useVehicle2,b));
    expect(passenger.passengerId,101);
    expect(passenger.vehicleCharacterId,202);
  });

  test('parses native motion and speed packets',(){
    final motionBytes=Uint8List(5),md=ByteData.sublistView(motionBytes);
    md.setUint32(0,55,Endian.little);motionBytes[4]=120;
    final motion=PsCharacterMotion.parse(PsPacket(PsPacketType.characterMotion,motionBytes));
    expect((motion.characterId,motion.motion),(55,120));

    final speedBytes=Uint8List(6),sd=ByteData.sublistView(speedBytes);
    sd.setUint32(0,55,Endian.little);speedBytes[4]=3;speedBytes[5]=4;
    final speed=PsCharacterSpeed.parse(PsPacket(PsPacketType.characterAttackMovementSpeed,speedBytes));
    expect((speed.characterId,speed.attackSpeed,speed.moveSpeed),(55,3,4));
  });
}
