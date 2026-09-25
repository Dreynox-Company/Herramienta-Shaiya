import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../core/client_locale.dart';
import '../core/equipment_rules.dart';
import '../core/formats.dart';
import '../core/game_metadata.dart';
import 'catalog.dart';
import 'library.dart';

/// Selection provenance is exclusive. A resource/MLT ordinal is NOT an item ID.
enum EquipmentSelectionMode { resources, registered }

class RegisteredItem {
  final Map<String, int> values;
  final String name, description;
  RegisteredItem(Map<String, int> values, this.name, this.description)
    : values = Map.unmodifiable(values);
  int get type => values['itemtype']!;
  int get id => values['itemtypeid']!;
  int get image => values['image']!;
  int get icon => values['icon'] ?? 0;
  int get level => values['reqlv'] ?? 0;
  String get key => '$type:$id';
  bool get hasName =>
      name.trim().isNotEmpty &&
      !RegExp(r'^[?\s]+$').hasMatch(name) &&
      !name.contains('\uFFFD');
  String get label =>
      '${hasName ? name : 'Sin nombre localizado'} · $key · Nv. $level';
  List<int> get slots => equipmentSlotsForItemType(type);
  bool allows(Archetype a, CharacterClass cls) =>
      ItemRule.fromRow(values).allows(a.race, cls);
}

class EquipmentRegistry {
  final Library library;
  final String dataPath;
  final String? textPath;
  final List<RegisteredItem> items;
  final Map<String, RegisteredItem> byKey;
  final Map<int, List<RegisteredItem>> bySlot = {};
  final int sourceRevision;
  EquipmentRegistry._(this.library, this.dataPath, this.textPath, this.items)
    : byKey = {for (final i in items) i.key: i},
      sourceRevision = library.revision {
    for (final item in items) {
      for (final slot in item.slots) {
        bySlot.putIfAbsent(slot, () => []).add(item);
      }
    }
  }
  bool get hasSpanishText =>
      textPath != null && ClientLocale.languageOf(textPath!) == 'es';

  static Future<EquipmentRegistry> load(Library library) async {
    const dataPath = 'binarysdata/dbitemdata.sdata';
    if (!library.files.containsKey(dataPath)) {
      throw const FormatException(
        'Falta BinarySData/DBItemData.SData. El modo recursos sigue disponible.',
      );
    }
    final textPath = ClientLocale.tableCandidates(
      library.files.keys,
      'dbitemtext',
      beside: dataPath,
    ).firstOrNull;
    final items = await compute(parse, <String, Object?>{
      'data': await library.read(dataPath),
      'dataPath': dataPath,
      'text': textPath == null ? null : await library.read(textPath),
      'textPath': textPath,
    });
    return EquipmentRegistry._(library, dataPath, textPath, items);
  }

  static List<RegisteredItem> parse(Map<String, Object?> input) {
    final data = DataTable.open(
      input['data'] as Uint8List,
      input['dataPath'] as String,
    );
    for (final field in ['itemtype', 'itemtypeid', 'image']) {
      if (!data.fields.contains(field))
        throw FormatException('DBItemData no contiene $field.');
    }
    final names = <String, ItemName>{};
    if (input['text'] != null) {
      for (final name in readItemNames(
        input['text'] as Uint8List,
        input['textPath'] as String,
      )) {
        if (names.containsKey(name.key))
          throw FormatException('Texto duplicado: ${name.key}.');
        names[name.key] = name;
      }
    }
    final seen = <String>{}, items = <RegisteredItem>[];
    for (final row in data.integers()) {
      final key = '${row['itemtype']}:${row['itemtypeid']}';
      if (!seen.add(key)) throw FormatException('Objeto duplicado: $key.');
      final text = names[key];
      items.add(RegisteredItem(row, text?.name ?? '', text?.description ?? ''));
    }
    return items;
  }

  static int? bodySlot(Slot s) => switch (s) {
    Slot.helmet => 0,
    Slot.upper => 1,
    Slot.lower => 2,
    Slot.hand => 3,
    Slot.foot => 4,
    _ => null,
  };

  List<RegisteredItem> forPart(
    PartRecord part,
    Archetype a,
    CharacterClass cls,
  ) {
    final slot = bodySlot(part.slot);
    if (slot == null) return const [];
    return (bySlot[slot] ?? [])
        .where((i) => i.image == part.raw.id && i.allows(a, cls))
        .toList();
  }

  List<PartRecord> partsFor(RegisteredItem item, Slot slot, Archetype a) =>
      (a.parts[slot] ?? [])
          .where(
            (p) =>
                p.raw.id == item.image && item.slots.contains(bodySlot(slot)),
          )
          .toList();

  List<RegisteredItem> forWeapon(
    WeaponRecord weapon,
    Archetype a,
    CharacterClass cls,
  ) {
    final slot = isShield(weapon) ? 6 : 5;
    return (bySlot[slot] ?? [])
        .where(
          (i) =>
              i.image == weapon.id &&
              i.allows(a, cls) &&
              (slot == 6 ||
                  weaponFamilyForItemType(i.type) == weaponFamily(weapon)),
        )
        .toList();
  }

  List<WeaponRecord> weaponsFor(
    RegisteredItem item,
    Iterable<WeaponRecord> weapons,
  ) => weapons
      .where(
        (w) =>
            w.id == item.image &&
            (item.slots.contains(6)
                ? isShield(w)
                : !isShield(w) &&
                      weaponFamilyForItemType(item.type) == weaponFamily(w)),
      )
      .toList();

  List<RegisteredItem> forCreature(
    CreatureRecord creature,
    String kind,
    Archetype a,
    CharacterClass cls,
  ) {
    final slot = kind == 'wing' ? wingEquipmentSlot : 13;
    return (bySlot[slot] ?? [])
        .where((i) => i.image == creature.id && i.allows(a, cls))
        .toList();
  }

  /// Same MON ordinal across different mount families must remain ambiguous
  /// until a family is selected; never take the first matching ID globally.
  List<CreatureRecord> creaturesFor(
    RegisteredItem item,
    Iterable<CreatureRecord> entries,
  ) => entries.where((c) => c.id == item.image).toList();

  Map<String, Object?> describeCandidates(List<RegisteredItem> candidates) => {
    'status': candidates.isEmpty
        ? 'unregistered'
        : candidates.length == 1
        ? 'registered'
        : 'ambiguous',
    'candidates': [
      for (final i in candidates)
        {
          'type': i.type,
          'typeId': i.id,
          'image': i.image,
          'name': i.name,
          'nameMissing': !i.hasName,
          'icon': i.icon,
          'level': i.level,
        },
    ],
  };
}
