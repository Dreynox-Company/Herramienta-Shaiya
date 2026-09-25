import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/native_item_icons.dart';

void main() {
  final files = {
    for (var i = 1; i <= 41; i++)
      'interface/icon/${i.toString().padLeft(2, '0')}.dds',
    for (var i = 101; i <= 141; i++) 'interface/icon/$i.dds',
    for (final n in [
      'somo',
      'somo1',
      'somo2',
      'somo3',
      'quest',
      'quest2',
      'rapis',
      'pet',
      'duallayer',
      'wing',
      '123_pet',
      '125_mount',
      '128_questitem',
      '130_serviceitems',
    ])
      'interface/icon/icon_$n.dds',
  };
  test('Icon is one-based and modern armor resolves its native family', () {
    expect(NativeItemIcons.resolve(1, 1, files)!.index, 0);
    final armor = NativeItemIcons.resolve(73, 47, files)!;
    expect(armor.path, 'interface/icon/17.dds');
    expect(armor.index, 46);
    expect(armor.columns, 4);
  });
  test('bank boundary is +100, not texture cell count', () {
    expect(NativeItemIcons.resolve(1, 64, files)!.index, 63);
    expect(NativeItemIcons.resolve(1, 65, files), isNull);
    expect(NativeItemIcons.resolve(1, 100, files), isNull);
    final next = NativeItemIcons.resolve(1, 101, files)!;
    expect(next.path, 'interface/icon/101.dds');
    expect(next.index, 0);
    expect(next.nativeValue, 101);
    expect(NativeItemIcons.resolve(1, 164, files)!.index, 63);
    expect(NativeItemIcons.resolve(1, 165, files), isNull);
  });
  test('shared aliases honor a numeric texture loaded before the fallback', () {
    expect(
      NativeItemIcons.resolve(25, 1, files)!.path,
      'interface/icon/25.dds',
    );
    final actual = files.difference({
      'interface/icon/25.dds',
      'interface/icon/30.dds',
    });
    expect(
      NativeItemIcons.resolve(25, 1, actual)!.path,
      'interface/icon/icon_somo.dds',
    );
    expect(
      NativeItemIcons.resolve(95, 71, actual)!.path,
      'interface/icon/icon_rapis.dds',
    );
    expect(NativeItemIcons.resolve(95, 71, actual)!.index, 70);
  });
  test(
    'Lapis, Lapisia and modern single-page categories do not use wrong banks',
    () {
      expect(NativeItemIcons.resolve(30, 101, files)!.index, 100);
      expect(NativeItemIcons.resolve(98, 101, files)!.index, 100);
      expect(NativeItemIcons.resolve(95, 101, files)!.index, 100);
      expect(NativeItemIcons.resolve(121, 101, files)!.index, 100);
      expect(
        NativeItemIcons.resolve(125, 1, files)!.path,
        'interface/icon/icon_125_mount.dds',
      );
      expect(
        NativeItemIcons.resolve(128, 1, files)!.path,
        'interface/icon/icon_128_questitem.dds',
      );
    },
  );
  test(
    'quest and ring layout mutations preserve the native texture selection',
    () {
      expect(
        NativeItemIcons.resolve(99, 101, files)!.path,
        'interface/icon/28.dds',
      );
      expect(NativeItemIcons.resolve(99, 101, files)!.index, 100);
      expect(
        NativeItemIcons.resolve(28, 101, files)!.path,
        'interface/icon/127.dds',
      );
      expect(
        NativeItemIcons.resolve(37, 101, files)!.path,
        'interface/icon/122.dds',
      );
      expect(NativeItemIcons.resolve(37, 101, files)!.index, 0);
      expect(
        NativeItemIcons.resolve(22, 101, files)!.path,
        'interface/icon/22.dds',
      );
      expect(NativeItemIcons.resolve(22, 101, files)!.index, 100);
    },
  );
  test(
    'unknown, missing, zero and oversized values never substitute a different item',
    () {
      for (final pair in [
        (0, 1),
        (256, 1),
        (1, 0),
        (1, 256),
        (200, 1),
        (255, 1),
      ]) {
        expect(NativeItemIcons.resolve(pair.$1, pair.$2, files), isNull);
      }
      expect(NativeItemIcons.resolve(73, 1, {'interface/icon/73.dds'}), isNull);
      expect(NativeItemIcons.resolve(1, 1, {'interface/icon/01.tga'}), isNull);
    },
  );
  test(
    'every selectable value round-trips to its exact cell for every byte type',
    () {
      for (var type = 1; type <= 255; type++) {
        for (final choice in NativeItemIcons.choices(type, files)) {
          expect(choice.nativeValue, inInclusiveRange(1, 255));
          final resolved = NativeItemIcons.resolve(
            type,
            choice.nativeValue,
            files,
          )!;
          expect(resolved.cellKey, choice.cellKey);
          expect(
            resolved.index,
            inInclusiveRange(0, resolved.columns * resolved.rows - 1),
          );
        }
      }
    },
  );
}
