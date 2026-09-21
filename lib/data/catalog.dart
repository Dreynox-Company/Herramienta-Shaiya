import 'dart:convert';
import 'dart:math' as math;
import 'game_names.dart';
export '../core/motion_catalog.dart';
import '../core/motion_catalog.dart';
import '../core/formats.dart';
import 'library.dart';

const originalBodySet = '__base_original__';
const nudeBodySet = '__nude_original__';

enum Slot { upper, lower, hand, foot, helmet, face, hair }

const slotLabels = {
  Slot.upper: 'Torso y hombreras',
  Slot.lower: 'Piernas y faldones',
  Slot.hand: 'Guantes',
  Slot.foot: 'Botas',
  Slot.helmet: 'Casco',
  Slot.face: 'Rostro',
  Slot.hair: 'Cabello',
};
const raceLabels = {
  'human': 'Humanos',
  'elf': 'Elfos',
  'vile': 'Vail',
  'deatheater': 'Nordein',
  'pandab': 'Panda oscuro',
  'pandaw': 'Panda claro',
  'pandw': 'Panda claro',
};
const archetypeCodes = [
  'humf',
  'huwf',
  'humm',
  'huwm',
  'elmr',
  'elwr',
  'elmm',
  'elwm',
  'vimm',
  'viwm',
  'vimr',
  'viwr',
  'demf',
  'dewf',
  'demr',
  'dewr',
];
String animationLabel(String source) => translatedMotion(source);
String setIdentity(String texture) {
  var x = baseName(texture).toLowerCase().replaceFirst(RegExp(r'\.[^.]+$'), '');
  x = x.replaceFirst(
    RegExp(
      r'^(hum[fwm]*|huw[fwm]*|elm[mr]*|elw[mr]*|vim[mr]*|viw[mr]*|dem[fr]*|dew[fr]*|pd[bw][mw]f)_',
    ),
    '',
  );
  x = x.replaceAllMapped(
    RegExp(
      r'(^|_)(upper|torso|lower|trousers|trouser|pants|legs|leg|hand|hands|gloves|glove|arms|arm|foot|feet|boots|boot|helmet|body)(?=_|[0-9]|$)',
    ),
    (m) => m.group(1)!,
  );
  return x.replaceAll(RegExp(r'_+'), '_').replaceAll(RegExp(r'^_|_$'), '');
}

String displaySet(String id) {
  if (id == originalBodySet) return 'Base original · cuerpo completo';
  if (id == nudeBodySet) return 'Nude · recursos originales';
  var x = id;
  const translations = {
    'christmass': 'Navidad',
    'christmas': 'Navidad',
    'springtime': 'Primavera',
    'wedding': 'Boda',
    'swimsuit': 'Baño',
    'magician': 'Ilusionista',
    'detective': 'Detective',
    'chinaset': 'Ceremonial',
    'dancer': 'Bailarín',
    'vampire': 'Vampiro',
    'pirate': 'Pirata',
    'medieval': 'Medieval',
    'count': 'Conde',
    'hanbok': 'Hanbok',
    'human_m_fighter': 'Humano guerrero',
    'human_f_fighter': 'Humana guerrera',
    'body': 'Cuerpo',
  };
  for (final e in translations.entries) {
    x = x.replaceAll(e.key, e.value);
  }
  return 'Conjunto ${x.replaceAll('_', ' ')}';
}

class PartRecord {
  final Slot slot;
  final MaterialRecord raw;
  final String meshPath, texturePath, tablePath;
  // Populated from actual geometry, never inferred only from a missing row.
  final Set<Slot> coveredSlots = {};
  final bool isBodyProfile;
  PartRecord(
    this.slot,
    this.raw,
    this.meshPath,
    this.texturePath,
    this.tablePath, {
    this.isBodyProfile = false,
  });
  String get key => setIdentity(raw.texture);
  String get label =>
      '${slot == Slot.face
          ? 'Rostro'
          : slot == Slot.hair
          ? 'Cabello'
          : displaySet(key)} · ${raw.id}';
  bool get explicitNude =>
      RegExp(
        r'(^|[_/])(nude|naked|desnudo|desnuda)([_/.]|$)',
        caseSensitive: false,
      ).hasMatch(raw.mesh) ||
      RegExp(
        r'(^|[_/])(nude|naked|desnudo|desnuda)([_/.]|$)',
        caseSensitive: false,
      ).hasMatch(raw.texture);
}

class Archetype {
  final String id, race, root;
  final Map<Slot, List<PartRecord>> parts;
  final List<String> animations;
  final Map<Slot, PartRecord> nudeParts = {};
  String? nudeUnavailableReason;
  bool get hasNude =>
      nudeParts.containsKey(Slot.upper) &&
      [Slot.lower, Slot.hand, Slot.foot].every(
        (s) =>
            nudeParts.containsKey(s) ||
            nudeParts[Slot.upper]!.coveredSlots.contains(s),
      );
  Archetype(this.id, this.race, this.root, this.parts, this.animations);
  bool get female => RegExp(r'^(hu|el|vi|de)w|^pd[bw]wf').hasMatch(id);
  String get label =>
      '${raceLabels[race] ?? race} · ${female ? 'Femenino' : 'Masculino'} · ${id.toUpperCase()}';
  Map<String, Map<Slot, PartRecord>> get sets {
    final out = <String, Map<Slot, PartRecord>>{};
    for (final e in parts.entries) {
      if ([Slot.face, Slot.hair].contains(e.key)) continue;
      for (final p in e.value) {
        out.putIfAbsent(p.key, () => {})[e.key] = p;
      }
    }
    out.removeWhere((key, value) => !value.containsKey(Slot.upper));
    out[originalBodySet] = {
      for (final slot in [Slot.upper, Slot.lower, Slot.hand, Slot.foot])
        if (base(slot) != null) slot: base(slot)!,
    };
    if (hasNude) out[nudeBodySet] = Map.of(nudeParts);
    return out;
  }

  PartRecord? base(Slot slot) {
    final rows = parts[slot] ?? [];
    if (rows.isEmpty) return null;
    if ([Slot.helmet, Slot.hair].contains(slot)) return null;
    // Original base is explicit and independent of optional Nude profiles.
    // Do not silently change appearance merely because a custom texture exists.
    return rows.firstWhere((p) => !p.isBodyProfile, orElse: () => rows.first);
  }
}

class Catalog {
  final Library library;
  final GameNames names = GameNames();
  final List<Archetype> archetypes = [];
  final List<WeaponRecord> weapons = [];
  final List<CreatureRecord> creatures = [], mounts = [], wings = [];
  final List<String> worlds = [],
      sounds = [],
      effects = [],
      skies = [],
      warnings = [];
  Catalog(this.library);
  Future<void> load(void Function(String) progress) async {
    final paths = library.files.keys.toList()..sort();
    for (final p in paths.where(
      (p) => RegExp(r'^character/[^/]+/[^/]+_upper\.mlt$').hasMatch(p),
    )) {
      final root = directoryName(p),
          id = baseName(p).replaceFirst('_upper.mlt', ''),
          race = p.split('/')[1],
          parts = <Slot, List<PartRecord>>{};
      for (final slot in Slot.values) {
        final table = '$root/${id}_${slot.name}.mlt';
        parts[slot] = [];
        if (!library.files.containsKey(table)) continue;
        try {
          for (final raw in readMlt(await library.read(table), table)) {
            if (raw.isNull) continue;
            final m = library.resolve(raw.mesh, ['$root/3dc', root]),
                t = library.resolve(raw.texture, ['$root/dds', root]);
            if (m == null || t == null) {
              warnings.add(
                '$table #${raw.id}: falta ${m == null ? raw.mesh : raw.texture}',
              );
              continue;
            }
            parts[slot]!.add(PartRecord(slot, raw, m, t, table));
          }
        } catch (e) {
          warnings.add(e.toString());
        }
      }
      if (parts[Slot.upper]!.isNotEmpty) {
        archetypes.add(
          Archetype(
            id,
            race,
            root,
            parts,
            paths
                .where(
                  (p) => p.startsWith('$root/ani/${id}_') && p.endsWith('.ani'),
                )
                .toList(),
          ),
        );
      }
      progress('Leyendo arquetipos: ${archetypes.length}');
    }
    await _inspectBodyCoverage(progress);
    await _loadNudeProfiles(progress);
    final weaponIds = <String>{};
    for (final p in paths.where(
      (p) =>
          p.startsWith('item/') && p.endsWith('.itm') && !p.contains('.bak.'),
    )) {
      try {
        for (final w in readItm(await library.read(p), p)) {
          final key = '${w.mesh.toLowerCase()}|${w.texture.toLowerCase()}';
          if (!w.mesh.toLowerCase().startsWith('null.') && weaponIds.add(key)) {
            weapons.add(w);
          }
        }
      } catch (e) {
        warnings.add(e.toString());
      }
    }
    for (final p in paths.where(
      (p) =>
          p.endsWith('.mon') &&
          (p.startsWith('monster/') ||
              p.startsWith('vehicle/') ||
              p.startsWith('character/wing/')),
    )) {
      try {
        final entries = readMon(
          await library.read(p),
          p,
        ).where((c) => c.parts.any((p) => !p.isNull));
        if (p.startsWith('vehicle/')) {
          mounts.addAll(entries);
        } else if (p.startsWith('character/wing/')) {
          wings.addAll(entries);
        } else {
          creatures.addAll(entries);
        }
      } catch (e) {
        warnings.add(e.toString());
      }
    }
    worlds.addAll(
      paths.where(
        (p) =>
            p.startsWith('world/') &&
            p.endsWith('.wld') &&
            !p.contains('.bak.'),
      ),
    );
    skies.addAll(
      paths.where(
        (p) =>
            p.startsWith('sky/') &&
            RegExp(r'\.(dds|tga|bmp|png)$').hasMatch(p) &&
            !p.contains('cloud') &&
            !p.contains('star'),
      ),
    );
    sounds.addAll(
      paths.where(
        (p) =>
            p.startsWith('sound/') && RegExp(r'\.(wav|mp3|ogg)$').hasMatch(p),
      ),
    );
    effects.addAll(
      paths.where(
        (p) =>
            p.startsWith('effect/') && RegExp(r'\.(dds|tga|png)$').hasMatch(p),
      ),
    );
    await names.load(library, progress);
    warnings.addAll(names.warnings);
    if (archetypes.isEmpty) {
      throw const FormatException(
        'No se encontraron arquetipos MLT utilizables. Revisa el diagnóstico.',
      );
    }
  }

  final Map<String, MeshData> _bodyMeshCache = {};
  Future<MeshData> _bodyMesh(PartRecord p) async {
    return _bodyMeshCache[p.meshPath] ??= MeshData.skinned(
      await library.read(p.meshPath),
      p.meshPath,
    );
  }

  Future<void> _inspectBodyCoverage(void Function(String) progress) async {
    for (final a in archetypes) {
      final references = <Slot, MeshData>{};
      for (final slot in [Slot.lower, Slot.hand, Slot.foot]) {
        final p = a.base(slot);
        if (p == null) continue;
        try {
          references[slot] = await _bodyMesh(p);
        } catch (e) {
          warnings.add('Base ${a.id}/${slot.name}: $e');
        }
      }
      final grouped = a.sets;
      for (final upper in a.parts[Slot.upper] ?? <PartRecord>[]) {
        final set = grouped[upper.key] ?? {};
        // Full-body candidates alone need geometry inspection. Matching modular
        // sets are already complete and do not incur extra texture reads.
        final absent = [
          Slot.lower,
          Slot.hand,
          Slot.foot,
        ].where((slot) => !set.containsKey(slot)).toList();
        if (absent.isEmpty) continue;
        try {
          final mesh = await _bodyMesh(upper);
          for (final slot in absent) {
            final ref = references[slot];
            if (ref != null && geometryCovers(mesh, ref, slot)) {
              upper.coveredSlots.add(slot);
            }
          }
        } catch (e) {
          warnings.add('Cobertura ${a.id}/${upper.raw.mesh}: $e');
        }
      }
      progress('Comprobando cuerpo completo: ${a.label}');
    }
    _bodyMeshCache.clear();
  }

  /// Only source-supplied or explicitly mapped resources qualify as Nude.
  /// No recolouring of clothing, anatomical synthesis or censorship is applied.
  Future<void> _loadNudeProfiles(void Function(String) progress) async {
    Map<String, dynamic> custom = {};
    final path = library.resolve('shaiya-studio-bodies.json', ['']);
    if (path != null) {
      try {
        final value = jsonDecode(
          utf8.decode(await library.read(path, limit: 1024 * 1024)),
        );
        if (value is! Map ||
            value['version'] != 1 ||
            value['archetypes'] is! Map) {
          throw const FormatException(
            'Perfil de cuerpos: se requiere version 1 y archetypes.',
          );
        }
        custom = Map<String, dynamic>.from(value['archetypes'] as Map);
      } catch (e) {
        warnings.add('Perfil Nude: $e');
      }
    }
    for (final a in archetypes) {
      final mapped = custom['${a.race}/${a.id}'] ?? custom[a.id];
      final candidates = <Slot, PartRecord>{};
      try {
        if (mapped is Map && mapped['parts'] is Map) {
          final parts = mapped['parts'] as Map;
          for (final slot in [Slot.upper, Slot.lower, Slot.hand, Slot.foot]) {
            final data = parts[slot.name];
            if (data == null) continue;
            if (data is! Map ||
                data['mesh'] is! String ||
                data['texture'] is! String) {
              throw FormatException('Perfil ${a.id}/${slot.name} inválido.');
            }
            final m = library.resolve(data['mesh'] as String, [
              '${a.root}/3dc',
              a.root,
            ]);
            final t = library.resolve(data['texture'] as String, [
              '${a.root}/dds',
              a.root,
            ]);
            if (m == null || t == null) {
              throw FormatException(
                'Falta un recurso Nude de ${a.id}/${slot.name}.',
              );
            }
            if (!m.startsWith('${a.root}/') || !t.startsWith('${a.root}/')) {
              throw FormatException('El perfil ${a.id} apunta a otra raza.');
            }
            final alpha = data['alpha'] is int ? data['alpha'] as int : 1;
            candidates[slot] = PartRecord(
              slot,
              MaterialRecord(-100 - slot.index, m, t, alpha),
              m,
              t,
              path!,
              isBodyProfile: true,
            );
          }
        } else {
          // Explicit Nude table entries are accepted only as one coherent set.
          final uppers = a.parts[Slot.upper]!
              .where((p) => p.explicitNude)
              .toList();
          if (uppers.isNotEmpty) {
            final u = uppers.first;
            candidates[Slot.upper] = u;
            for (final slot in [Slot.lower, Slot.hand, Slot.foot]) {
              final p = a.parts[slot]
                  ?.where((p) => p.explicitNude && p.key == u.key)
                  .firstOrNull;
              if (p != null) candidates[slot] = p;
            }
          }
        }
        if (candidates.isEmpty) {
          a.nudeUnavailableReason =
              'No se encontró un conjunto Nude original completo para ${a.id.toUpperCase()} en esta biblioteca. La base original conserva la ropa de sus texturas.';
          continue;
        }
        final upper = candidates[Slot.upper];
        if (upper == null) {
          throw const FormatException('El perfil Nude no contiene torso.');
        }
        final baseUpper = a.base(Slot.upper);
        final reference = baseUpper == null ? null : await _bodyMesh(baseUpper);
        final nudeUpper = await _bodyMesh(upper);
        if (reference != null &&
            (nudeUpper.inverses.length != reference.inverses.length)) {
          throw FormatException(
            'El esqueleto Nude no corresponde al arquetipo ${a.id}.',
          );
        }
        for (final entry in candidates.entries) {
          final mesh = await _bodyMesh(entry.value);
          if (reference != null &&
              mesh.inverses.length != reference.inverses.length) {
            throw FormatException(
              'Esqueleto incompatible en Nude/${entry.key.name}.',
            );
          }
        }
        for (final slot in [Slot.lower, Slot.hand, Slot.foot]) {
          if (candidates.containsKey(slot)) continue;
          final base = a.base(slot);
          if (base != null &&
              geometryCovers(nudeUpper, await _bodyMesh(base), slot)) {
            upper.coveredSlots.add(slot);
          } else {
            throw FormatException(
              'El cuerpo Nude no cubre ${slotLabels[slot]!.toLowerCase()}; se mantiene el cuerpo anterior completo.',
            );
          }
        }
        a.nudeParts.addAll(candidates);
      } catch (e) {
        a.nudeParts.clear();
        a.nudeUnavailableReason = e.toString();
        warnings.add('Nude ${a.id}: $e');
      }
      progress('Revisando perfiles corporales: ${a.id.toUpperCase()}');
    }
    _bodyMeshCache.clear();
  }

  String creatureLabel(CreatureRecord c) {
    var kind = c.source.startsWith('vehicle/')
        ? 'Montura'
        : c.source.contains('/wing/')
        ? 'Alas'
        : 'Criatura';
    final stem = baseName(c.parts.first.mesh).toLowerCase();
    for (final e in {
      'bear': 'Oso',
      'wolf': 'Lobo',
      'dragon': 'Dragón',
      'horse': 'Caballo',
      'tiger': 'Tigre',
      'lion': 'León',
      'boar': 'Jabalí',
      'spider': 'Araña',
      'golem': 'Gólem',
      'skeleton': 'Esqueleto',
      'rabbit': 'Conejo',
      'deer': 'Ciervo',
      'unicorn': 'Unicornio',
    }.entries) {
      if (stem.contains(e.key)) kind = e.value;
    }
    return names.creatureTitle(c, '$kind ${c.id.toString().padLeft(3, '0')}');
  }
}

class Appearance {
  final Archetype archetype;
  final Map<Slot, PartRecord?> selected;
  final bool fullCostume;
  final String? selectedSetKey;
  Appearance(
    this.archetype,
    Map<Slot, PartRecord?> slots, {
    this.fullCostume = false,
    this.selectedSetKey,
  }) : selected = Map.unmodifiable(slots);

  factory Appearance.initial(Archetype a) =>
      Appearance.forSet(a, a.sets.containsKey('016') ? '016' : originalBodySet);

  factory Appearance.forSet(Archetype a, String key, {Appearance? previous}) {
    if (key == nudeBodySet && !a.hasNude) {
      throw FormatException(
        a.nudeUnavailableReason ??
            'No hay un cuerpo Nude completo para este arquetipo.',
      );
    }
    final set = a.sets[key];
    if (set == null) {
      throw FormatException('El conjunto $key no pertenece a ${a.id}.');
    }
    final slots = <Slot, PartRecord?>{for (final s in Slot.values) s: null};
    slots.addAll(set);
    slots[Slot.helmet] = null;
    for (final s in [Slot.face, Slot.hair]) {
      slots[s] =
          previous?.archetype.id == a.id && previous?.archetype.race == a.race
          ? previous!.selected[s]
          : ((a.parts[s] ?? []).isEmpty ? null : a.parts[s]!.first);
    }
    return Appearance(
      a,
      slots,
      fullCostume:
          slots[Slot.upper]?.coveredSlots.contains(Slot.lower) ?? false,
      selectedSetKey: key,
    );
  }

  Appearance withPart(Slot slot, PartRecord? part) {
    if (part != null &&
        !(archetype.parts[slot] ?? []).contains(part) &&
        !archetype.nudeParts.values.contains(part)) {
      throw const FormatException('La pieza no pertenece al arquetipo activo.');
    }
    final values = <Slot, PartRecord?>{...selected, slot: part};
    if (slot == Slot.upper) {
      // Remove only the previous costume's own body slots. Identity remains.
      final covers = part?.coveredSlots ?? <Slot>{};
      for (final s in [Slot.lower, Slot.hand, Slot.foot]) {
        if (covers.contains(s)) values[s] = null;
      }
    } else if (part != null &&
        [Slot.lower, Slot.hand, Slot.foot].contains(slot) &&
        (selected[Slot.upper]?.coveredSlots.contains(slot) ?? false)) {
      throw FormatException(
        'El torso integral ya cubre ${slotLabels[slot]!.toLowerCase()}. Selecciona primero un torso modular.',
      );
    }
    return Appearance(
      archetype,
      values,
      fullCostume:
          values[Slot.upper]?.coveredSlots.contains(Slot.lower) ?? false,
    );
  }

  List<PartRecord> get effective {
    final out = <PartRecord>[];
    final covered = <Slot>{};
    for (final p in selected.values.whereType<PartRecord>()) {
      covered.addAll(p.coveredSlots);
    }
    for (final slot in Slot.values) {
      final p = selected[slot];
      if (p != null) {
        out.add(p);
        continue;
      }
      if (covered.contains(slot)) continue;
      final fallback = archetype.base(slot);
      if (fallback != null) out.add(fallback);
    }
    return out;
  }
}

/// Conservative bind-space coverage proof for slots absent from an outfit.
/// Name mismatches alone never make body geometry disappear.
bool geometryCovers(MeshData outfit, MeshData reference, Slot slot) {
  if (outfit.vertices < 3 || reference.vertices < 3) return false;
  double minX(MeshData m) {
    var value = double.infinity;
    for (var i = 0; i < m.positions.length; i += 3) {
      value = math.min(value, m.positions[i]);
    }
    return value;
  }

  double maxX(MeshData m) {
    var value = -double.infinity;
    for (var i = 0; i < m.positions.length; i += 3) {
      value = math.max(value, m.positions[i]);
    }
    return value;
  }

  final low = reference.minY,
      high = reference.maxY,
      span = math.max(.001, high - low);
  final left = minX(reference),
      right = maxX(reference),
      width = math.max(.001, right - left);
  final tolerance = span * .12;
  if (slot == Slot.lower || slot == Slot.foot) {
    if (outfit.minY > low + tolerance || outfit.maxY < high - tolerance) {
      return false;
    }
  }
  if (slot == Slot.hand &&
      (minX(outfit) > left + width * .08 ||
          maxX(outfit) < right - width * .08)) {
    return false;
  }
  var leftHits = 0, rightHits = 0, lowHits = 0;
  for (var i = 0; i < outfit.positions.length; i += 3) {
    final x = outfit.positions[i], y = outfit.positions[i + 1];
    if (y < low - tolerance ||
        y > high + tolerance ||
        x < left - width * .3 ||
        x > right + width * .3) {
      continue;
    }
    if (x < 0) {
      leftHits++;
    } else {
      rightHits++;
    }
    if (y < low + span * .45) lowHits++;
  }
  return leftHits >= 3 && rightHits >= 3 && lowHits >= 4;
}
