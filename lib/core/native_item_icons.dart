/// Item icon routing recovered from the owner's ps0032 executable.
/// This is a named client profile, NOT a claim that all Shaiya builds agree.
/// Evidence: docs/audits/R25_NATIVE_ICON_LOOKUP.json and R25_ITEMS.md.
class NativeItemIcon {
  final String path;
  final int index, columns, rows, nativeValue;
  const NativeItemIcon(
    this.path,
    this.index,
    this.columns,
    this.nativeValue, {
    this.rows = 16,
  });
  String get cellKey => '$path:$columns:$rows:$index';
}

class NativeItemIcons {
  static const profile = 'ps0032';
  static const executableSha256 =
      '509c4a8fbe4d5292961fdfb6d1045795a7bb5970fcf2560fd1070aee18273c2d';
  static const familyRemap = <int, int>{
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
  static const _eight = <int>{22, 27, 28, 29, 37, 95, 99, 129};
  static const _sixteen = <int>{
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
  static int family(int type) => familyRemap[type] ?? type;

  /// A missing sheet stays missing. Never substitute an unrelated generic icon,
  /// a .bak file, or a same-number texture from another item family.
  static NativeItemIcon? resolve(int type, int icon, Set<String> files) {
    if (type < 1 || type > 255 || icon < 1 || icon > 255 || type == 200) {
      return null;
    }
    var index = icon - 1; // 0x4e0e31..0x4e0e35: native byte then DEC.
    var selectedType = type;
    var secondBank = false;
    final category = family(type);
    final columns = category == 30 || _eight.contains(type)
        ? 8
        : _sixteen.contains(type)
        ? 16
        : 4;
    if (category != 30 && columns != 16) {
      if (type == 99) {
        selectedType = 28;
      } else if (const {27, 28, 29}.contains(type)) {
        selectedType = 27;
        if (index >= 100) {
          index -= 100;
          secondBank = true;
        }
      } else if (columns == 4 || type == 37) {
        if (type == 37) selectedType = 22;
        if (index >= 100) {
          index -= 100;
          secondBank = true;
        }
      }
    }
    String? sheet;
    // Primary numeric slots alias these shared textures. If a numeric texture
    // was actually loaded first, the original loader leaves that slot intact.
    String primary(int slot) {
      final numeric = 'interface/icon/${slot.toString().padLeft(2, '0')}.dds';
      if (files.contains(numeric)) return numeric;
      return switch (slot) {
        25 => 'interface/icon/icon_somo.dds',
        27 => 'interface/icon/icon_quest.dds',
        28 => 'interface/icon/icon_quest2.dds',
        30 => 'interface/icon/icon_rapis.dds',
        _ => numeric,
      };
    }

    sheet = switch (selectedType) {
      100 || 101 => 'interface/icon/icon_somo2.dds',
      102 || 103 => 'interface/icon/icon_somo3.dds',
      78 || 79 || 80 => 'interface/icon/icon_somo1.dds',
      42 => primary(25),
      99 => primary(28),
      95 => primary(30),
      120 => 'interface/icon/icon_pet.dds',
      150 || 151 => 'interface/icon/icon_duallayer.dds',
      121 || 122 => 'interface/icon/icon_wing.dds',
      123 => 'interface/icon/icon_123_pet.dds',
      125 => 'interface/icon/icon_125_mount.dds',
      128 => 'interface/icon/icon_128_questitem.dds',
      130 => 'interface/icon/icon_130_serviceitems.dds',
      _ => null,
    };
    if (sheet == null) {
      final slot = selectedType == 37 ? 22 : family(selectedType);
      if (slot < 1 || slot > 41) return null;
      sheet = secondBank ? 'interface/icon/${100 + slot}.dds' : primary(slot);
    }
    if (!files.contains(sheet) || index < 0 || index >= columns * 16) {
      return null;
    }
    return NativeItemIcon(sheet, index, columns, icon);
  }

  /// Enumerate only native values that actually address an existing texture.
  /// Picking an icon returns the original 1-based byte, including bank +100.
  static List<NativeItemIcon> choices(int type, Set<String> files) => [
    for (var value = 1; value <= 255; value++)
      if (resolve(type, value, files) case final NativeItemIcon ref) ref,
  ];
}
