import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/vehicle_position.dart';

void main() {
  test('VehiclePosition round-trip preserves bridge transport exactly', () {
    final document = VehiclePositionDocument.empty();
    document.update(
      const VehiclePositionProfile(
        family: 2,
        vehicleId: 0x1a,
        posX: 0.125,
        posY: -0.04,
        posZ: 1.75,
        rotX: 12.5,
        rotY: -180,
        rotZ: 359.999,
        scaleX: -1.25,
        scaleY: 0.8,
        scaleZ: 2,
        riderProfile: 2,
      ),
    );

    final bytes = document.encode();
    document.validateEncoded(bytes);
    final text = utf8.decode(bytes);
    expect(text, contains('[F2_V1A]'));
    expect(text, contains('POS_X_MM=125'));
    expect(text, contains('ROT_X_MDEG=12500'));
    expect(text, contains('SCALE_X_PERMILLE=-1250'));

    final parsed = VehiclePositionDocument.parse(
      bytes,
      VehiclePositionDocument.canonicalPath,
    );
    final profile = parsed.resolve(2, 0x1a);
    expect(profile, isNotNull);
    expect(profile!.enabled, isTrue);
    expect(profile.posX, 0.125);
    expect(profile.posY, -0.04);
    expect(profile.posZ, 1.75);
    expect(profile.rotX, 12.5);
    expect(profile.rotY, -180);
    expect(profile.rotZ, 359.999);
    expect(profile.scaleX, -1.25);
    expect(profile.scaleY, 0.8);
    expect(profile.scaleZ, 2);
    expect(profile.riderProfile, 2);
  });

  test('vehicle MON family is derived from the native Hu/El/Vi/De source', () {
    expect(vehicleFamilyFromSource('Vehicle/Vehicle_Hu_01.MON'), 0);
    expect(vehicleFamilyFromSource('vehicle/vehicle_El_01.mon'), 1);
    expect(vehicleFamilyFromSource('Vehicle/Vehicle_Vi_01.MON'), 2);
    expect(vehicleFamilyFromSource('Vehicle/Vehicle_De_01.MON'), 3);
    expect(vehicleFamilyFromSource('Vehicle/Special.MON'), isNull);
  });

  test('native rider profiles retain the ps0032 motion IDs', () {
    expect(riderAnimationProfiles[0], (idle: 21, moving: 20, label: 'Vehículo clásico · 021/020'));
    expect(riderAnimationProfiles[1]!.idle, 97);
    expect(riderAnimationProfiles[1]!.moving, 22);
    expect(riderAnimationProfiles[2]!.idle, 98);
    expect(riderAnimationProfiles[2]!.moving, 98);
    expect(riderAnimationProfiles[3]!.idle, 97);
    expect(riderAnimationProfiles[3]!.moving, 22);
    expect(riderAnimationProfiles[4]!.idle, 30);
    expect(riderAnimationProfiles[4]!.moving, 31);
  });

  test('section key is fail-closed outside native family and byte ID range', () {
    expect(vehiclePositionSection(0, 0), 'F0_V00');
    expect(vehiclePositionSection(3, 255), 'F3_VFF');
    expect(() => vehiclePositionSection(4, 0), throwsFormatException);
    expect(() => vehiclePositionSection(0, 256), throwsFormatException);
  });
}
