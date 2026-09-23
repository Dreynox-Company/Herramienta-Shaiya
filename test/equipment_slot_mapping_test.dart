import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/equipment_rules.dart';

void main() {
  test('modern weapon item types map to original ITM families', () {
    expect(weaponFamilyForItemType(1), 1);
    expect(weaponFamilyForItemType(45), 1);
    expect(weaponFamilyForItemType(49), 5);
    expect(weaponFamilyForItemType(65), 15);
    expect(weaponFamilyForItemType(121), 0);
  });

  test('equipment slot map includes wings and modern armor variants', () {
    expect(equipmentSlotsForItemType(121), [wingEquipmentSlot]);
    expect(wingItemType, 121);
    expect(wingEquipmentSlot, 16);
    expect(equipmentSlotsForItemType(72), [0]);
    expect(equipmentSlotsForItemType(73), [1]);
    expect(equipmentSlotsForItemType(74), [2]);
    expect(equipmentSlotsForItemType(76), [3]);
    expect(equipmentSlotsForItemType(77), [4]);
    expect(equipmentSlotsForItemType(42), [13]);
    expect(equipmentSlotsForItemType(150), [15]);
  });

  test('non-equipment consumables remain outside the equipment layout', () {
    expect(equipmentSlotsForItemType(27), isEmpty);
    expect(equipmentSlotsForItemType(100), isEmpty);
  });
}
