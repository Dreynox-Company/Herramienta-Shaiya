import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/data/catalog.dart';
import 'package:herramienta_shaiya/core/formats.dart';
import 'core_test.dart' show part;

Archetype panda() {
  final values = {for (final s in Slot.values) s: <PartRecord>[]};
  for (final id in [0, 1, 2]) {
    final prefix = 'Pdbwf_${id.toString().padLeft(2, '0')}';
    for (final e in {
      Slot.upper: 'Torso',
      Slot.lower: 'Trousers',
      Slot.hand: 'Arm',
      Slot.foot: 'foot',
    }.entries) {
      values[e.key]!.add(part(e.key, id, '${prefix}_${e.value}.dds'));
    }
  }
  values[Slot.face]!.add(part(Slot.face, 3, 'pdbwf_face03.dds'));
  values[Slot.hair]!.add(part(Slot.hair, 4, 'pdbwf_hair04.dds'));
  return Archetype('pdbwf', 'pandab', 'character/pandab', values, []);
}

void main() {
  group('Complete bodies and correct set identity', () {
    test('Panda Trousers Arm Torso and Foot use the same outfit key', () {
      for (final stem in ['Pdbmf', 'Pdbwf', 'Pdwmf', 'Pdwwf']) {
        final keys = [
          'Torso',
          'Trousers',
          'Arm',
          'foot',
        ].map((s) => setIdentity('${stem}_00_$s.dds')).toSet();
        expect(keys, {'00'});
      }
    });
    test(
      'initial Panda appearance always has legs without restore workaround',
      () {
        final look = Appearance.initial(panda());
        expect(look.fullCostume, isFalse);
        expect(
          look.effective.map((p) => p.slot),
          containsAll([
            Slot.upper,
            Slot.lower,
            Slot.hand,
            Slot.foot,
            Slot.face,
            Slot.hair,
          ]),
        );
      },
    );
    test(
      'switching every Panda outfit keeps exactly one of each body slot',
      () {
        final a = panda();
        var previous = Appearance.initial(a);
        for (final key in a.sets.keys) {
          previous = Appearance.forSet(a, key, previous: previous);
          for (final slot in [Slot.upper, Slot.lower, Slot.hand, Slot.foot]) {
            expect(previous.effective.where((p) => p.slot == slot).length, 1);
          }
        }
      },
    );
    test('a missing lower record does not prove a whole-body costume', () {
      final a = panda();
      a.parts[Slot.upper]!.add(
        part(Slot.upper, 17, 'pdbwf_modular_special_upper.dds'),
      );
      final look = Appearance.forSet(a, 'modular_special');
      expect(look.fullCostume, isFalse);
      expect(look.effective.any((p) => p.slot == Slot.lower), isTrue);
    });
    test('only proven whole-body geometry suppresses lower fallback', () {
      final a = panda();
      final u = part(Slot.upper, 17, 'pdbwf_full_upper.dds')
        ..coveredSlots.addAll([Slot.lower, Slot.hand, Slot.foot]);
      a.parts[Slot.upper]!.add(u);
      final look = Appearance.forSet(a, 'full');
      expect(look.fullCostume, isTrue);
      expect(
        look.effective.where(
          (p) => [Slot.lower, Slot.hand, Slot.foot].contains(p.slot),
        ),
        isEmpty,
      );
      final modular = look.withPart(Slot.upper, a.parts[Slot.upper]!.first);
      expect(
        modular.effective.map((p) => p.slot),
        containsAll([Slot.lower, Slot.hand, Slot.foot]),
      );
    });
    test(
      'body base is visible for every arquetype and keeps selected identity',
      () {
        final a = panda();
        final initial = Appearance.initial(a);
        final base = Appearance.forSet(a, originalBodySet, previous: initial);
        expect(a.sets.containsKey(originalBodySet), isTrue);
        expect(base.selectedSetKey, originalBodySet);
        expect(base.selected[Slot.face], same(initial.selected[Slot.face]));
        expect(base.selected[Slot.hair], same(initial.selected[Slot.hair]));
        expect(base.selected[Slot.helmet], isNull);
      },
    );
  });
  group('Authentic Nude profile integrity', () {
    test('no source Nude is not falsely substituted with a painted armor', () {
      final a = panda();
      expect(a.hasNude, isFalse);
      expect(() => Appearance.forSet(a, nudeBodySet), throwsFormatException);
      expect(a.base(Slot.upper)!.explicitNude, isFalse);
    });
    test('complete supplied Nude uses exact source mesh and texture paths', () {
      final a = panda(), prior = Appearance.initial(panda());
      for (final slot in [Slot.upper, Slot.lower, Slot.hand, Slot.foot]) {
        final stem = 'pdbwf_nude_${slot.name}';
        a.nudeParts[slot] = PartRecord(
          slot,
          MaterialRecord(-100 - slot.index, '$stem.3dc', '$stem.dds', 1),
          'character/pandab/3dc/$stem.3dc',
          'character/pandab/dds/$stem.dds',
          'shaiya-studio-bodies.json',
          isBodyProfile: true,
        );
      }
      expect(a.hasNude, isTrue);
      final nude = Appearance.forSet(a, nudeBodySet, previous: prior);
      for (final slot in [Slot.upper, Slot.lower, Slot.hand, Slot.foot]) {
        expect(nude.selected[slot], same(a.nudeParts[slot]));
        expect(
          nude.effective.where((p) => p.slot == slot).single.texturePath,
          endsWith('nude_${slot.name}.dds'),
        );
      }
      expect(nude.selected[Slot.face], same(prior.selected[Slot.face]));
      expect(nude.selected[Slot.hair], same(prior.selected[Slot.hair]));
    });
    test('a partial Nude profile cannot create an incomplete body', () {
      final a = panda();
      a.nudeParts[Slot.upper] = part(Slot.upper, 0, 'pdbwf_nude_upper.dds');
      expect(a.hasNude, isFalse);
      expect(() => Appearance.forSet(a, nudeBodySet), throwsFormatException);
    });
  });
}
