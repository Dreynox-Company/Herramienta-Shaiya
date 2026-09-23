import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/formats.dart';
import 'package:herramienta_shaiya/core/game_metadata.dart';
import 'package:herramienta_shaiya/data/game_names.dart';

CreatureRecord wing(int id) => CreatureRecord(
      id,
      'wing-$id',
      'character/wing/fixture.mon',
      const {},
      const {},
      const {},
      [MaterialRecord(0, 'wing.3dc', 'wing.dds', 0)],
      1,
    );

void main() {
  test('wing titles use DBItemData type 121 image mapping', () {
    final names = GameNames();
    names.itemByModel['121:7'] = [
      ItemName(121, 55, 'Alas Celestiales', 'fixture'),
    ];

    final record = wing(7);
    expect(names.wingTitle(record, 'Alas 007'), 'Alas Celestiales');
    expect(names.wingDetail(record), contains('ItemType 121'));
    expect(names.wingDetail(record), contains('Image 7'));
    expect(names.wingDetail(record), contains('slot de equipo 16'));
    expect(names.wingDetail(record), contains('wing.3dc'));
  });

  test('wing title falls back to MON label without matching metadata', () {
    final names = GameNames();
    expect(names.wingTitle(wing(3), 'Alas 003'), 'Alas 003');
  });

  test('non-wing item type with same image is never used as wing title', () {
    final names = GameNames();
    names.itemByModel['1:7'] = [
      ItemName(1, 99, 'Espada con image 7', 'fixture'),
    ];
    expect(names.wingTitle(wing(7), 'Alas 007'), 'Alas 007');
  });
}
