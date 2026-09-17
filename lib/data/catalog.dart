import '../core/body_coverage.dart';
import 'game_names.dart';
export '../core/motion_catalog.dart';
import '../core/motion_catalog.dart';
import '../core/formats.dart';
import 'library.dart';

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
      r'(^|_)(upper|torso|lower|trousers|pants|hand|gloves?|arm|foot|boots|helmet|body)(?=_|[0-9]|$)',
    ),
    (m) => m.group(1)!,
  );
  return x.replaceAll(RegExp(r'_+'), '_').replaceAll(RegExp(r'^_|_$'), '');
}

String displaySet(String id) {
  if (id == '@base') return 'Cuerpo base original';
  if (id == '@nude') return 'Nude original disponible';
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
  PartRecord(
    this.slot,
    this.raw,
    this.meshPath,
    this.texturePath,
    this.tablePath,
  );
  String get key => setIdentity(raw.texture);
  String get label =>
      '${slot == Slot.face
          ? 'Rostro'
          : slot == Slot.hair
          ? 'Cabello'
          : displaySet(key)} · ${raw.id}';
  bool get explicitNude => RegExp(
    r'nude|naked|undress|desnudo|basebody',
    caseSensitive: false,
  ).hasMatch(raw.mesh);
}

class Archetype {
  final String id, race, root;
  final Map<Slot, List<PartRecord>> parts;
  final List<String> animations;
  Archetype(this.id, this.race, this.root, this.parts, this.animations);
  bool get female => RegExp(r'^(hu|el|vi|de)w|^pd[bw]wf').hasMatch(id);
  String get label =>
      '${raceLabels[race] ?? race} · ${female ? 'Femenino' : 'Masculino'} · ${id.toUpperCase()}';
  Map<String, Map<Slot, PartRecord>> get sets {
    final out = <String, Map<Slot, PartRecord>>{
      '@base': {
        for (final s in [Slot.upper, Slot.lower, Slot.hand, Slot.foot])
          if (base(s) != null) s: base(s)!,
      },
      if (hasOriginalNude) '@nude': originalNude,
    };
    for (final e in parts.entries) {
      if ([Slot.face, Slot.hair].contains(e.key)) continue;
      for (final p in e.value) {
        out.putIfAbsent(p.key, () => {})[e.key] = p;
      }
    }
    out.removeWhere((key, value) => !value.containsKey(Slot.upper));
    return out;
  }

  Map<Slot, PartRecord> get originalNude => {
    for (final s in [Slot.upper, Slot.lower, Slot.hand, Slot.foot])
      if ((parts[s] ?? []).any((p) => p.explicitNude))
        s: parts[s]!.firstWhere((p) => p.explicitNude),
  };
  bool get hasOriginalNude => [
    Slot.upper,
    Slot.lower,
    Slot.hand,
    Slot.foot,
  ].every(originalNude.containsKey);

  PartRecord? base(Slot slot) {
    final rows = parts[slot] ?? [];
    if (rows.isEmpty) return null;
    if ([Slot.helmet, Slot.hair].contains(slot)) return null;
    // Row zero is the original game baseline; never confuse a costume with it.
    return rows.where((r) => r.raw.id == 0).firstOrNull ?? rows.first;
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
  final Map<String, MeshData> _bodyMeshCache = {};
  Catalog(this.library);

  Future<MeshData> appearanceMesh(String path) async {
    final cached = _bodyMeshCache[path];
    if (cached != null) return cached;
    final mesh = MeshData.skinned(await library.read(path), path);
    // Bound CPU-side caching independently of GPU texture ownership.
    if (_bodyMeshCache.length >= 96) {
      _bodyMeshCache.remove(_bodyMeshCache.keys.first);
    }
    _bodyMeshCache[path] = mesh;
    return mesh;
  }

  Future<Appearance> resolveAppearance(Appearance requested) async {
    final a = requested.archetype;
    final top = requested.selected[Slot.upper] ?? a.base(Slot.upper);
    if (top == null) {
      throw const FormatException('El arquetipo no tiene torso base.');
    }
    final mesh = await appearanceMesh(top.meshPath);
    final referenceTop = a.base(Slot.upper);
    final topMesh = referenceTop == null
        ? null
        : await appearanceMesh(referenceTop.meshPath);
    final embedded = <Slot>{};
    for (final slot in [Slot.lower, Slot.hand, Slot.foot]) {
      final reference = a.base(slot);
      if (reference == null) continue;
      final baseMesh = await appearanceMesh(reference.meshPath);
      if (bodyRegionCovered(mesh, baseMesh, upperReference: topMesh)) {
        embedded.add(slot);
      }
    }
    final resolved = requested.withResolvedCoverage(embedded);
    if (!embedded.contains(Slot.lower) &&
        !resolved.effective.any((p) => p.slot == Slot.lower)) {
      throw const FormatException(
        'Faltan las piernas y el torso no las contiene. Se conserva el personaje anterior.',
      );
    }
    return resolved;
  }

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

/// A selection is not evidence that a mesh contains a body region.
/// Only resolveAppearance may suppress fallback pieces after inspecting geometry.
class Appearance {
  final Archetype archetype;
  final Map<Slot, PartRecord?> selected;
  final bool fullCostume;
  final String? preset;
  final bool geometryResolved;
  final Set<Slot> embeddedSlots;
  Appearance(
    this.archetype,
    Map<Slot, PartRecord?> slots, {
    this.fullCostume = false,
    this.preset,
    this.geometryResolved = false,
    Set<Slot> embeddedSlots = const {},
  }) : selected = Map.unmodifiable(slots),
       embeddedSlots = Set.unmodifiable(embeddedSlots);

  factory Appearance.initial(Archetype a) {
    // A complete canonical set is safe; otherwise start from all original bases.
    final preferred = a.sets['016'];
    return Appearance.forSet(
      a,
      preferred != null && preferred.containsKey(Slot.lower) ? '016' : '@base',
    );
  }

  factory Appearance.base(Archetype a, {Appearance? previous}) =>
      Appearance.forSet(a, '@base', previous: previous);

  factory Appearance.forSet(Archetype a, String key, {Appearance? previous}) {
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
    return Appearance(a, slots, preset: key);
  }

  Appearance withResolvedCoverage(Set<Slot> coverage) => Appearance(
    archetype,
    selected,
    preset: preset,
    geometryResolved: true,
    embeddedSlots: coverage,
    fullCostume: coverage.contains(Slot.lower),
  );

  Appearance withPart(Slot slot, PartRecord? part) {
    if (part != null && !(archetype.parts[slot] ?? []).contains(part)) {
      throw const FormatException('La pieza no pertenece al arquetipo activo.');
    }
    // A new torso must not inherit unrelated costume components or an old helmet.
    if (slot == Slot.upper && part != null) {
      final matching = archetype.sets[part.key];
      if (matching != null) {
        return Appearance.forSet(archetype, part.key, previous: this);
      }
    }
    if (slot == Slot.lower &&
        geometryResolved &&
        embeddedSlots.contains(slot) &&
        part != null) {
      throw const FormatException(
        'El torso ya contiene las piernas. Elige un torso modular antes de añadir otro pantalón.',
      );
    }
    return Appearance(
      archetype,
      {...selected, slot: part},
      fullCostume: slot != Slot.upper && fullCostume,
      geometryResolved: slot != Slot.upper && geometryResolved,
      embeddedSlots: slot == Slot.upper ? const {} : embeddedSlots,
      preset: [Slot.face, Slot.hair].contains(slot) ? preset : null,
    );
  }

  List<PartRecord> get effective {
    final out = <PartRecord>[];
    for (final slot in Slot.values) {
      final part = selected[slot];
      if (part != null) {
        out.add(part);
        continue;
      }
      if (geometryResolved && embeddedSlots.contains(slot)) continue;
      final fallback = archetype.base(slot);
      if (fallback != null) out.add(fallback);
    }
    return out;
  }
}
