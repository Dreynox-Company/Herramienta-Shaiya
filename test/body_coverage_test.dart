import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' as v;
import 'package:herramienta_shaiya/core/formats.dart';
import 'package:herramienta_shaiya/core/body_coverage.dart';
import 'package:herramienta_shaiya/data/catalog.dart';

import 'core_test.dart' as old;

MeshData legs(String name, {bool oneLeg = false, double y = 0}) {
  final p = Float32List.fromList([
    -1,
    y,
    0,
    -.5,
    y,
    0,
    -.5,
    y + 1,
    0,
    -1,
    y + 1,
    0,
    .5,
    y,
    0,
    1,
    y,
    0,
    1,
    y + 1,
    0,
    .5,
    y + 1,
    0,
  ]);
  final j = Uint8List(32), w = Float32List(32);
  for (var i = 0; i < 8; i++) {
    j[i * 4] = i < 4 ? 1 : 2;
    w[i * 4] = 1;
  }
  return MeshData(
    p,
    Float32List(24),
    Float32List(16),
    Uint16List.fromList([
      0,
      1,
      2,
      0,
      2,
      3,
      if (!oneLeg) ...[4, 5, 6, 4, 6, 7],
    ]),
    j,
    w,
    List.generate(3, (_) => v.Matrix4.identity()),
    name,
  );
}

void main() {
  group('Cobertura corporal y conjuntos', () {
    test('Panda une Torso, Trousers, Arm y foot', () {
      for (final id in ['Pdbmf', 'Pdbwf', 'Pdwmf', 'Pdwwf']) {
        final key = setIdentity('${id}_00_Torso.dds');
        for (final slot in ['Trousers', 'Arm', 'foot']) {
          expect(setIdentity('${id}_00_$slot.dds'), key);
        }
      }
    });
    test('variantes con guantes y pantalones comparten conjunto', () {
      expect(
        setIdentity('humf_summer_gloves.dds'),
        setIdentity('humf_summer_pants.dds'),
      );
    });
    test('sin metadatos de piernas no se asume un traje integral', () {
      final a = old.archetype();
      final look = Appearance.forSet(a, 'wedding');
      expect(look.fullCostume, false);
      expect(look.effective.any((p) => p.slot == Slot.lower), true);
    });
    test('un guardado antiguo fullCostume=true no elimina las piernas', () {
      final a = old.archetype();
      final legacy = Appearance(a, {
        Slot.upper: a.parts[Slot.upper]!.last,
      }, fullCostume: true);
      expect(legacy.effective.any((p) => p.slot == Slot.lower), true);
    });
    test('base original se ofrece primero', () {
      final a = old.archetype();
      expect(a.sets.keys.first, '@base');
      final base = Appearance.base(a);
      expect(base.preset, '@base');
      expect(base.selected[Slot.upper]!.raw.id, 0);
      expect(base.selected[Slot.lower], isNotNull);
    });
    test('base original conserva cara y cabello y retira casco', () {
      final a = old.archetype();
      final face = old.part(Slot.face, 3, 'face3.dds'),
          hair = old.part(Slot.hair, 7, 'hair7.dds');
      a.parts[Slot.face]!.add(face);
      a.parts[Slot.hair]!.add(hair);
      final previous = Appearance.forSet(
        a,
        '016',
      ).withPart(Slot.face, face).withPart(Slot.hair, hair);
      final base = Appearance.base(a, previous: previous);
      expect(identical(base.selected[Slot.face], face), true);
      expect(identical(base.selected[Slot.hair], hair), true);
      expect(base.selected[Slot.helmet], isNull);
    });
    test('no se etiqueta como nude una armadura o un perfil incompleto', () {
      final a = old.archetype();
      expect(a.hasOriginalNude, false);
      expect(a.sets.containsKey('@nude'), false);
      a.parts[Slot.upper]!.add(
        PartRecord(
          Slot.upper,
          const MaterialRecord(
            99,
            'humf_nude_upper.3dc',
            'humf_nude_upper.dds',
            1,
          ),
          'a',
          'b',
          'c',
        ),
      );
      expect(a.hasOriginalNude, false);
    });
    test('perfiles nude existentes se incorporan sin cambiar su textura', () {
      final a = old.archetype();
      for (final slot in [Slot.upper, Slot.lower, Slot.hand, Slot.foot]) {
        a.parts[slot]!.add(
          PartRecord(
            slot,
            MaterialRecord(
              99,
              'humf_nude_${slot.name}.3dc',
              'humf_nude_${slot.name}.dds',
              1,
            ),
            'mesh',
            'texture_${slot.name}',
            'table',
          ),
        );
      }
      expect(a.hasOriginalNude, true);
      final nude = Appearance.forSet(a, '@nude');
      for (final slot in [Slot.upper, Slot.lower, Slot.hand, Slot.foot]) {
        expect(nude.selected[slot]!.raw.id, 99);
        expect(nude.selected[slot]!.texturePath, 'texture_${slot.name}');
      }
    });
    test('un cambio de torso invalida cobertura previa', () {
      final a = old.archetype();
      final suit = Appearance.forSet(
        a,
        'wedding',
      ).withResolvedCoverage({Slot.lower, Slot.hand});
      final next = suit.withPart(Slot.upper, a.parts[Slot.upper]!.first);
      expect(next.geometryResolved, false);
      expect(next.effective.any((p) => p.slot == Slot.lower), true);
    });
    test('una sola pierna no oculta el par de piernas base', () {
      expect(bodyRegionCovered(legs('one', oneLeg: true), legs('base')), false);
    });
    test('el par de piernas integrado se reconoce por geometría', () {
      expect(bodyRegionCovered(legs('suit'), legs('base')), true);
    });
    test('los huesos correctos fuera de la región no bastan', () {
      expect(bodyRegionCovered(legs('suit', y: 2), legs('base')), false);
    });
    test('un catálogo parcial comienza con todas las partes base', () {
      final a = old.archetype();
      a.parts[Slot.upper]!.removeAt(0);
      final initial = Appearance.initial(a);
      expect(initial.preset, '@base');
      expect(initial.effective.any((p) => p.slot == Slot.lower), true);
    });
    test('selección y cobertura resueltas no se mutan desde fuera', () {
      final look = Appearance.base(old.archetype())
          .withResolvedCoverage({Slot.hand});
      expect(() => look.embeddedSlots.add(Slot.lower), throwsUnsupportedError);
      expect(() => look.selected[Slot.lower] = null, throwsUnsupportedError);
    });
  });
}
