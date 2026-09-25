/// Item icon layout recovered from the supplied ps0032 client, not a universal
/// Shaiya episode guess. See docs/audits/STUDIO_R25_ITEMS.md for addresses.
class ItemIconLayout {
  static const profile = 'ps0032';
  static const clientSha256 =
      '509c4a8fbe4d5292961fdfb6d1045795a7bb5970fcf2560fd1070aee18273c2d';
  final String stem;
  final int tile, columns, rows, nativeIcon, pageBase;
  const ItemIconLayout(
    this.stem,
    this.tile,
    this.columns,
    this.nativeIcon,
    this.pageBase, {
    this.rows = 16,
  });
  String get path => 'interface/icon/$stem.dds';
  bool get inBounds => tile >= 0 && tile < columns * rows;
  int get x => tile % columns;
  int get y => tile ~/ columns;

  static int family(int type) => _families[type] ?? type;
  static const _families = <int, int>{
    37: 22,
    38: 25,
    41: 25,
    43: 25,
    44: 25,
    45: 1,
    46: 2,
    47: 3,
    48: 4,
    49: 5,
    50: 5,
    51: 6,
    52: 6,
    53: 7,
    54: 7,
    55: 8,
    56: 8,
    57: 9,
    58: 10,
    59: 11,
    60: 12,
    61: 12,
    62: 13,
    63: 13,
    64: 14,
    65: 15,
    66: 16,
    67: 17,
    68: 18,
    69: 19,
    70: 20,
    71: 21,
    72: 16,
    73: 17,
    74: 18,
    75: 19,
    76: 20,
    77: 21,
    78: 25,
    79: 25,
    80: 25,
    81: 31,
    82: 32,
    83: 33,
    84: 34,
    85: 35,
    86: 36,
    87: 31,
    88: 32,
    89: 33,
    90: 34,
    91: 35,
    92: 36,
    94: 25,
    96: 23,
    97: 40,
    98: 30,
    99: 27,
    101: 100,
    102: 100,
    103: 100,
    122: 121,
    123: 120,
    125: 42,
    126: 25,
    127: 25,
    128: 27,
    129: 27,
    130: 25,
    131: 25,
    151: 150,
    170: 16,
    171: 22,
    172: 17,
    173: 18,
    175: 20,
    176: 19,
    177: 23,
    180: 15,
    181: 1,
    182: 2,
    183: 14,
    184: 13,
  };
  static const _wide = {
    25,
    38,
    41,
    42,
    43,
    44,
    78,
    79,
    80,
    94,
    100,
    101,
    102,
    103,
    120,
    121,
    122,
    123,
    125,
    126,
    127,
    128,
    130,
    131,
    150,
    151,
  };
  static const _medium = {22, 27, 28, 29, 37, 95, 99, 129};
  static const _special = <int, String>{
    100: 'icon_somo2',
    101: 'icon_somo2',
    102: 'icon_somo3',
    103: 'icon_somo3',
    78: 'icon_somo1',
    79: 'icon_somo1',
    80: 'icon_somo1',
    42: 'icon_somo',
    95: 'icon_rapis',
    120: 'icon_pet',
    150: 'icon_duallayer',
    151: 'icon_duallayer',
    121: 'icon_wing',
    122: 'icon_wing',
    123: 'icon_123_pet',
    125: 'icon_125_mount',
    128: 'icon_128_questitem',
    130: 'icon_130_serviceitems',
  };
  static ItemIconLayout? resolve(int type, int icon) {
    // The native item structure reads a BYTE Icon then subtracts one. Do not
    // wrap negative/overflow values or use a nearby icon to hide bad DATA.
    if (type < 1 || type > 255 || icon < 1 || icon > 255) return null;
    var effective = type, tile = icon - 1, second = false;
    final columns = family(type) == 30
        ? 8
        : _wide.contains(type)
        ? 16
        : _medium.contains(type)
        ? 8
        : 4;
    if (columns == 4 || type == 37 || {27, 28, 29}.contains(type)) {
      if (tile >= 100) {
        tile -= 100;
        second = true;
      }
    }
    if ({27, 28, 29}.contains(type)) effective = 27;
    if (type == 99) effective = 28;
    if (type == 37) effective = 22;
    var stem = _special[effective];
    final f = family(effective);
    if (stem == null) {
      if (f < 1 || f > 41) return null;
      stem = second
          ? '${100 + f}'
          : switch (f) {
              25 => 'icon_somo',
              27 => 'icon_quest',
              28 => 'icon_quest2',
              30 => 'icon_rapis',
              _ => f.toString().padLeft(2, '0'),
            };
    }
    return ItemIconLayout(stem, tile, columns, icon, second ? 101 : 1);
  }
}
