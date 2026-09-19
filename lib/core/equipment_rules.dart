import 'motion_catalog.dart';
import 'formats.dart';

/// Faction values are ITEM restrictions, not the 0/1 user-country enum.
class CharacterClass {
  final String id, label, flag;
  final Set<int> fallbackWeapons;
  const CharacterClass(this.id, this.label, this.flag, this.fallbackWeapons);
}

const fighter = CharacterClass('fighter', 'Luchador', 'attackfighter', {
  1,
  2,
  3,
  4,
  5,
  6,
  19,
});
const defender = CharacterClass('defender', 'Defensor', 'defensefighter', {
  1,
  3,
  7,
  8,
  19,
});
const priest = CharacterClass('priest', 'Sacerdote', 'defensemage', {10, 12});
const ranger = CharacterClass('ranger', 'Ranger', 'patrolrogue', {9, 10, 15});
const archer = CharacterClass('archer', 'Arquero', 'shootrogue', {
  10,
  11,
  13,
  14,
});
const mage = CharacterClass('mage', 'Mago', 'attackmage', {10, 12});
const warrior = CharacterClass('warrior', 'Guerrero', 'attackfighter', {
  1,
  2,
  3,
  4,
  5,
  6,
  34,
});
const guardian = CharacterClass('guardian', 'Guardián', 'defensefighter', {
  1,
  3,
  7,
  8,
  34,
});
const hunter = CharacterClass('hunter', 'Cazador', 'shootrogue', {
  10,
  11,
  13,
  14,
});
const assassin = CharacterClass('assassin', 'Asesino', 'patrolrogue', {
  9,
  10,
  15,
});
const pagan = CharacterClass('pagan', 'Pagano', 'attackmage', {10, 12});
const oracle = CharacterClass('oracle', 'Oráculo', 'defensemage', {10, 12});
const pandaFighter = CharacterClass(
  'panda-fighter',
  'Combatiente Panda',
  'pandafighter',
  {1, 2, 3, 4, 5, 6, 7, 8, 19, 34},
);
List<CharacterClass> classesFor(String id) => switch (id.toLowerCase()) {
  'humf' || 'huwf' => const [fighter, defender],
  'humm' || 'huwm' => const [priest],
  'elmr' || 'elwr' => const [ranger, archer],
  'elmm' || 'elwm' => const [mage],
  'demf' || 'dewf' => const [warrior, guardian],
  'demr' || 'dewr' => const [hunter],
  'vimr' || 'viwr' => const [assassin],
  'vimm' || 'viwm' => const [pagan, oracle],
  _ => const [pandaFighter],
};
int itemRace(String race) => switch (race.toLowerCase()) {
  'human' => 0,
  'elf' => 1,
  'deatheater' => 3,
  'vile' => 4,
  'pandab' => 3,
  'pandaw' || 'pandw' => 0,
  _ => 6,
};
bool isShield(WeaponRecord? w) => const {19, 34}.contains(weaponFamily(w));
bool permitsShield(WeaponRecord? w) =>
    w == null || const {1, 3, 7, 9, 10}.contains(weaponFamily(w));

class ItemRule {
  final int country, type, model;
  final Set<String> classes;
  const ItemRule(this.country, this.type, this.model, this.classes);
  factory ItemRule.fromRow(Map<String, int> row) =>
      ItemRule(row['country'] ?? 6, row['itemtype'] ?? -1, row['image'] ?? -1, {
        for (final flag in [
          'attackfighter',
          'defensefighter',
          'patrolrogue',
          'shootrogue',
          'attackmage',
          'defensemage',
          'pandafighter',
          'pandamage',
        ])
          if ((row[flag] ?? 0) > 0) flag,
      });
  bool allows(String race, CharacterClass cls) {
    final rr = itemRace(race), light = const {0, 1}.contains(rr);
    final faction = country == 6 || country == rr || country == (light ? 2 : 5);
    return faction && classes.contains(cls.flag);
  }
}

/// Metadata is authoritative. The fallback is labelled separately and never
/// used to claim an unknown item was validated against server restrictions.
class EquipmentCompatibility {
  final bool allowed, fromMetadata;
  final String reason;
  const EquipmentCompatibility(this.allowed, this.fromMetadata, this.reason);
}

EquipmentCompatibility equipmentCompatibility({
  required WeaponRecord weapon,
  required String race,
  required CharacterClass characterClass,
  required List<ItemRule> rules,
  required int archetypeIndex,
}) {
  if (archetypeIndex < 0 ||
      archetypeIndex >= weapon.transforms.length ||
      !weapon.transforms[archetypeIndex].any((a) => a.defined)) {
    return const EquipmentCompatibility(
      false,
      false,
      'Sin anclaje para este esqueleto',
    );
  }
  if (rules.isNotEmpty) {
    final allowed = rules.any((r) => r.allows(race, characterClass));
    return EquipmentCompatibility(
      allowed,
      true,
      allowed
          ? 'Clase y facción según DATA'
          : 'Otra clase o facción según DATA',
    );
  }
  final allowed = characterClass.fallbackWeapons.contains(weaponFamily(weapon));
  return EquipmentCompatibility(
    allowed,
    false,
    allowed
        ? 'Compatibilidad de familia; sin regla de objeto'
        : 'Familia ajena a esta clase',
  );
}
