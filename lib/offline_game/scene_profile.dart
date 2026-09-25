import '../core/equipment_rules.dart';
import '../core/formats.dart';
import '../data/catalog.dart';
import '../render/studio_scene.dart';

/// Portable scene contract shared by the editor and the independently built
/// Flutter client. This is NOT an understood file of the original executable.
class SceneProfile {
  static const schema = 1;
  static String weaponKey(WeaponRecord p) => '${p.source}#${p.id}';
  static String creatureKey(CreatureRecord p) => '${p.source}#${p.id}';
  static String partKey(PartRecord p) =>
      '${p.tablePath}#${p.raw.id}#${p.texturePath}';
  static double number(
    Map<String, dynamic> map,
    String name,
    double fallback,
    double min,
    double max,
  ) {
    final value = map[name];
    if (value == null) return fallback;
    if (value is! num || !value.isFinite || value < min || value > max) {
      throw FormatException('Valor de escena no válido: $name');
    }
    return value.toDouble();
  }

  static Map<String, Object?> capture(StudioScene s) {
    final a = s.appearance;
    if (a == null) throw StateError('No hay un personaje para guardar.');
    return {
      'schema': schema,
      'archetype': a.archetype.id,
      'class': s.characterClass.id,
      'preset': a.preset ?? '@base',
      'parts': {
        for (final e in a.selected.entries)
          e.key.name: e.value == null ? null : partKey(e.value!),
      },
      'weapon': s.weaponRecord == null ? null : weaponKey(s.weaponRecord!),
      'shield': s.shieldRecord == null ? null : weaponKey(s.shieldRecord!),
      'wing': s.wingRecord == null ? null : creatureKey(s.wingRecord!),
      'mount': s.mountRecord == null ? null : creatureKey(s.mountRecord!),
      'map': s.worldPath,
      'x': s.originX + (s.character?.root.position.x ?? 0),
      'z': s.originZ - (s.character?.root.position.z ?? 0),
      'yaw': s.character?.root.rotation.y ?? 0,
      'wingYaw': s.wingYaw,
      'wingHeight': s.wingHeight,
      'wingDepth': s.wingDepth,
      'wingScale': s.wingSize,
      'riderHeight': s.riderHeight,
      'riderForward': s.riderForward,
      'flight': s.flightEnabled,
      'cameraYaw': s.yaw,
      'cameraPitch': s.pitch,
      'cameraDistance': s.distance,
    };
  }

  /// Resolve ALL referenced records and scalar ranges before replacing anything.
  /// Individual renderer changes stage their resources before committing them.
  static Future<void> apply(
    StudioScene s,
    Map<String, dynamic> p, {
    bool reloadWorld = false,
    bool validateOnly = false,
  }) async {
    if (p['schema'] != schema) {
      throw const FormatException('Versión de escena desconocida.');
    }
    final c = s.catalog;
    if (c == null) throw StateError('Conecta DATA primero.');
    final a = c.archetypes.where((a) => a.id == p['archetype']).firstOrNull;
    if (a == null) {
      throw FormatException('Arquetipo no disponible: ${p['archetype']}');
    }
    final cls = classesFor(a.id).where((v) => v.id == p['class']).firstOrNull;
    if (cls == null) {
      throw const FormatException('Clase no compatible con el arquetipo.');
    }
    T? resolve<T>(Object? key, Iterable<T> items, String Function(T) getKey) {
      if (key == null) return null;
      final item = items.where((v) => getKey(v) == key).firstOrNull;
      if (item == null) throw FormatException('Recurso ausente: $key');
      return item;
    }

    final weapon = resolve(p['weapon'], c.weapons, weaponKey);
    final shield = resolve(p['shield'], c.weapons, weaponKey);
    if (weapon != null &&
        (isShield(weapon) ||
            !s.compatibilityFor(weapon, archetype: a, cls: cls).allowed)) {
      throw const FormatException('Arma no compatible.');
    }
    if (shield != null &&
        (!isShield(shield) ||
            !permitsShield(weapon) ||
            !s.compatibilityFor(shield, archetype: a, cls: cls).allowed)) {
      throw const FormatException('Escudo no compatible.');
    }
    final wing = resolve(p['wing'], c.wings, creatureKey);
    final mount = resolve(p['mount'], c.mounts, creatureKey);
    final world = p['map'];
    if (world != null && (world is! String || !c.worlds.contains(world))) {
      throw const FormatException('Mapa no disponible en esta DATA.');
    }
    final parts = p['parts'];
    final selected = <Slot, PartRecord?>{};
    if (parts != null) {
      if (parts is! Map ||
          parts.keys.any((k) => !Slot.values.any((s) => s.name == k))) {
        throw const FormatException('Slots de apariencia desconocidos.');
      }
      for (final slot in Slot.values) {
        selected[slot] = resolve(
          parts[slot.name],
          a.parts[slot] ?? [],
          partKey,
        );
      }
    } else {
      selected.addAll(Appearance.initial(a).selected);
    }
    final x = number(p, 'x', 0, -1000000, 1000000),
        z = number(p, 'z', 0, -1000000, 1000000);
    final yaw = number(p, 'yaw', 0, -100, 100);
    final wy = number(p, 'wingYaw', 0, -6.284, 6.284),
        wh = number(p, 'wingHeight', 1.3, -5, 10);
    final wd = number(p, 'wingDepth', .25, -5, 5),
        ws = number(p, 'wingScale', 1, .02, 5);
    final rh = number(p, 'riderHeight', 1, -5, 10),
        rf = number(p, 'riderForward', 0, -5, 5);
    final cy = number(p, 'cameraYaw', .25, -100, 100),
        cp = number(p, 'cameraPitch', .18, -1.2, 1.2);
    final cd = number(p, 'cameraDistance', 5.2, .4, 250);
    if (p['flight'] != null && p['flight'] is! bool) {
      throw const FormatException('Modo vuelo inválido.');
    }
    if (validateOnly) return;
    await s.setAppearance(
      Appearance(a, selected, preset: p['preset'] as String?),
    );
    await s.selectClass(cls);
    await s.equip(weapon);
    await s.equipShield(shield);
    await s.selectCreature(mount, 'mount');
    await s.selectCreature(wing, 'wing');
    s.wingYaw = wy;
    s.wingHeight = wh;
    s.wingDepth = wd;
    s.wingSize = ws;
    s.riderHeight = rh;
    s.riderForward = rf;
    await s.setWorld(
      world as String?,
      x: world == null ? null : x,
      z: world == null ? null : z,
      forceReload: reloadWorld,
    );
    if (world == null) s.character?.root.position.setValues(x, 0, -z);
    s.character?.root.rotation.y = yaw;
    s.yaw = cy;
    s.pitch = cp;
    s.distance = cd;
    await s.requestFlight(p['flight'] == true);
    s.updateAttachments();
    s.updateCamera();
    s.changed();
  }
}
