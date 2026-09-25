import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../core/formats.dart';
import '../offline_game/scene_profile.dart';
import '../render/studio_scene.dart';
import 'catalog.dart';
import 'file_save.dart';
import 'library.dart';

/// Full editor appearance, not a native game.exe command or item-table row.
/// Exact record identities and resource hashes prevent ordinal-only remapping.
class AppearanceSnapshot {
  static const schema = 3;
  static const kind = 'shaiya-studio-appearance';
  static const maxBytes = 2 * 1024 * 1024;

  static Map<String, dynamic> object(Object? value, String label) {
    if (value is! Map || value.keys.any((k) => k is! String)) {
      throw FormatException('Objeto inválido: $label');
    }
    return Map<String, dynamic>.from(value);
  }

  static double finite(Object? value, double low, double high, String label) {
    if (value is! num || !value.isFinite || value < low || value > high) {
      throw FormatException('Valor fuera de rango: $label');
    }
    return value.toDouble();
  }

  static void validateTransform(
    Object? value,
    String label, {
    bool wing = false,
  }) {
    final map = object(value, label);
    for (final group in ['position', 'rotationDegrees', 'scale', 'mirror']) {
      final axis = object(map[group], '$label.$group');
      for (final key in ['x', 'y', 'z']) {
        if (group == 'mirror') {
          if (axis[key] is! bool) {
            throw FormatException('Booleano inválido: $label.$group.$key');
          }
        } else {
          final low = group == 'scale'
              ? .01
              : group == 'position'
              ? -100.0
              : -3600.0;
          final high = group == 'position' || group == 'scale' ? 100.0 : 3600.0;
          finite(axis[key], low, high, '$label.$group.$key');
        }
      }
    }
    if (wing) {
      if (map['boneIndex'] is! int ||
          (map['boneIndex'] as int) < 0 ||
          (map['boneIndex'] as int) > 255) {
        throw const FormatException('Hueso de alas inválido.');
      }
    } else if (map['profile'] is! int ||
        (map['profile'] as int) < 0 ||
        (map['profile'] as int) > 4) {
      throw const FormatException('Perfil de jinete inválido.');
    }
  }

  static Map<String, dynamic> captureState(StudioScene scene) => {
    'schema': schema,
    'kind': kind,
    'consumer': 'Shaiya Studio',
    'nativeGameReady': false,
    'scene': SceneProfile.capture(scene),
    'wingTransform': scene.wingTransformSnapshot,
    'riderTransform': {
      'position': {
        'x': scene.riderLateral,
        'y': scene.riderHeight,
        'z': scene.riderForward,
      },
      'rotationDegrees': {
        'x': scene.riderRotX,
        'y': scene.riderRotY,
        'z': scene.riderRotZ,
      },
      'scale': {
        'x': scene.riderScaleX,
        'y': scene.riderScaleY,
        'z': scene.riderScaleZ,
      },
      'mirror': {
        'x': scene.riderMirrorX,
        'y': scene.riderMirrorY,
        'z': scene.riderMirrorZ,
      },
      'profile': scene.riderProfile,
    },
    'wingAutoMotion': scene.wingAutoMotion,
  };

  static Set<String> resourcePaths(StudioScene scene) {
    final c = scene.catalog, look = scene.appearance;
    if (c == null || look == null) throw StateError('Conecta DATA primero.');
    return pathsFor(
      c,
      look,
      [scene.weaponRecord, scene.shieldRecord].whereType<WeaponRecord>(),
      [scene.wingRecord, scene.mountRecord].whereType<CreatureRecord>(),
    );
  }

  static Set<String> pathsFor(
    Catalog c,
    Appearance look,
    Iterable<WeaponRecord> weapons,
    Iterable<CreatureRecord> creatures,
  ) {
    final paths = <String>{};
    void add(String path) {
      final key = canon(path);
      if (!c.library.files.containsKey(key)) {
        throw FormatException('Falta el recurso de apariencia: $path');
      }
      paths.add(key);
    }

    // Include selected AND effective fallback pieces, even when a helmet hides hair.
    for (final part in {
      ...look.effective,
      ...look.selected.values.whereType<PartRecord>(),
    }) {
      add(part.meshPath);
      add(part.texturePath);
      if (part.tablePath.isNotEmpty &&
          c.library.files.containsKey(canon(part.tablePath))) {
        add(part.tablePath);
      }
    }
    void material(MaterialRecord part, String source, String meshFolder) {
      final root = directoryName(source);
      for (final pair in [(part.mesh, meshFolder), (part.texture, 'dds')]) {
        final path = c.library.resolve(pair.$1, ['$root/${pair.$2}', root]);
        if (path == null) {
          throw FormatException('Recurso sin resolver: ${pair.$1}');
        }
        add(path);
      }
    }

    for (final weapon in weapons) {
      add(weapon.source);
      material(weapon, weapon.source, '3do');
    }
    for (final actor in creatures) {
      add(actor.source);
      for (final part in actor.parts.where((p) => !p.isNull)) {
        material(part, actor.source, '3dc');
      }
      final root = directoryName(actor.source);
      for (final name in actor.animations.values) {
        final path = c.library.resolve(name, ['$root/ani', root]);
        if (path != null) add(path);
      }
    }
    for (final path in [
      'excelxml/wingposition.xml',
      'excelxml/vehicleposition.ini',
    ]) {
      if (c.library.files.containsKey(path)) add(path);
    }
    return paths;
  }

  static Future<Map<String, dynamic>> capture(StudioScene scene) async {
    final out = captureState(scene), lib = scene.catalog!.library;
    final paths = resourcePaths(scene).toList()..sort();
    out['resources'] = [
      for (final path in paths) await _fingerprint(lib, path),
    ];
    validate(out);
    return out;
  }

  static Future<Map<String, Object>> _fingerprint(
    Library library,
    String path,
  ) async {
    final bytes = await library.read(path);
    return {
      'path': path,
      'bytes': bytes.length,
      'sha256': FileSave.hash(bytes),
    };
  }

  static void validate(Map<String, dynamic> out) {
    if (out['schema'] != schema || out['kind'] != kind) {
      throw const FormatException('Formato de apariencia no compatible.');
    }
    final p = object(out['scene'], 'scene');
    if (p['schema'] != SceneProfile.schema ||
        p['archetype'] is! String ||
        p['class'] is! String ||
        (p['preset'] != null && p['preset'] is! String)) {
      throw const FormatException('Identidad de escena inválida.');
    }
    final parts = object(p['parts'], 'parts');
    if (parts.keys.any((k) => !Slot.values.any((s) => s.name == k))) {
      throw const FormatException('Slot de apariencia desconocido.');
    }
    for (final value in [
      ...parts.values,
      p['weapon'],
      p['shield'],
      p['wing'],
      p['mount'],
    ]) {
      if (value != null &&
          (value is! String || value.isEmpty || value.length > 2048)) {
        throw const FormatException('Referencia de recurso inválida.');
      }
    }
    validateTransform(out['wingTransform'], 'alas', wing: true);
    validateTransform(out['riderTransform'], 'jinete');
    if (out['wingAutoMotion'] is! bool || p['flight'] is! bool) {
      throw const FormatException('Estado de animación inválido.');
    }
    final resources = out['resources'];
    if (resources is! List || resources.isEmpty || resources.length > 1024) {
      throw const FormatException('Manifiesto de recursos vacío o excesivo.');
    }
    final paths = <String>{};
    for (final entry in resources) {
      final r = object(entry, 'recurso');
      if (r['path'] is! String ||
          r['bytes'] is! int ||
          (r['bytes'] as int) < 0 ||
          (r['bytes'] as int) > 64 * 1024 * 1024 ||
          r['sha256'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(r['sha256'] as String)) {
        throw const FormatException('Huella de recurso inválida.');
      }
      final path = r['path'] as String;
      if (canon(path) != path || path.contains('\u0000') || !paths.add(path)) {
        throw const FormatException('Ruta no canónica o repetida.');
      }
    }
  }

  static Map<String, dynamic> decode(List<int> bytes) {
    if (bytes.length > maxBytes) {
      throw const FormatException('Apariencia demasiado grande.');
    }
    final out = object(jsonDecode(utf8.decode(bytes)), 'apariencia');
    validate(out);
    return out;
  }

  static Future<void> verify(
    Library library,
    Map<String, dynamic> value,
  ) async {
    validate(value);
    for (final entry in value['resources'] as List) {
      final record = object(entry, 'recurso'), path = record['path'] as String;
      if (!library.files.containsKey(path)) {
        throw FormatException('Falta $path.');
      }
      final actual = await _fingerprint(library, path);
      if (actual['bytes'] != record['bytes'] ||
          actual['sha256'] != record['sha256']) {
        throw FormatException(
          'DATA diferente: $path. No se aplica la apariencia.',
        );
      }
    }
  }

  static Future<void> save(File file, Map<String, dynamic> value) async {
    validate(value);
    final bytes = Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(value)),
    );
    if (bytes.length > maxBytes) {
      throw const FormatException('Apariencia demasiado grande.');
    }
    if (await file.exists()) {
      await FileSave.replace(
        file.path,
        bytes,
        expectedHash: FileSave.hash(await file.readAsBytes()),
        keepBackup: true,
      );
      return;
    }
    await file.parent.create(recursive: true);
    final stage = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.partial',
    );
    await stage.create(exclusive: true);
    try {
      await stage.writeAsBytes(bytes, flush: true);
      if (sha256.convert(await stage.readAsBytes()).toString() !=
          sha256.convert(bytes).toString()) {
        throw const FileSystemException('No coincide la apariencia escrita.');
      }
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw const FileSystemException(
          'El destino se creó durante el guardado.',
        );
      }
      await stage.rename(file.path);
    } finally {
      if (await stage.exists()) await stage.delete();
    }
  }

  static Future<void> apply(
    StudioScene scene,
    Map<String, dynamic> value,
  ) async {
    final library = scene.catalog?.library;
    if (library == null) throw StateError('Conecta DATA primero.');
    await verify(library, value);
    final target = object(value['scene'], 'scene');
    await SceneProfile.apply(
      scene,
      _presentation(scene, target),
      validateOnly: true,
    );
    final c = scene.catalog!;
    final a = c.archetypes.singleWhere((a) => a.id == target['archetype']);
    final selected = object(target['parts'], 'parts');
    final look = await c.resolveAppearance(
      Appearance(a, {
        for (final slot in Slot.values)
          slot: selected[slot.name] == null
              ? null
              : a.parts[slot]!.singleWhere(
                  (p) => SceneProfile.partKey(p) == selected[slot.name],
                ),
      }),
    );
    final expected = pathsFor(
      c,
      look,
      c.weapons.where(
        (w) => [
          target['weapon'],
          target['shield'],
        ].contains(SceneProfile.weaponKey(w)),
      ),
      [
        ...c.wings.where((r) => SceneProfile.creatureKey(r) == target['wing']),
        ...c.mounts.where(
          (r) => SceneProfile.creatureKey(r) == target['mount'],
        ),
      ],
    );
    final declared = {
      for (final r in value['resources'] as List) object(r, 'recurso')['path'],
    };
    if (!declared.containsAll(expected)) {
      throw const FormatException(
        'El manifiesto omitió recursos de la apariencia.',
      );
    }
    final previous = captureState(scene);
    try {
      await _applyState(scene, value);
    } catch (e) {
      try {
        await _applyState(scene, previous);
      } catch (rollback) {
        throw StateError(
          'No se pudo cargar ($e) ni restaurar el visor ($rollback). Reconecta DATA.',
        );
      }
      rethrow;
    }
  }

  static Map<String, dynamic> _presentation(
    StudioScene scene,
    Map<String, dynamic> p,
  ) {
    final current = SceneProfile.capture(scene);
    // Loading appearance is not a teleport. Exact XYZ transforms follow later.
    return {
      ...p,
      for (final key in [
        'map',
        'x',
        'z',
        'yaw',
        'cameraYaw',
        'cameraPitch',
        'cameraDistance',
      ])
        key: current[key],
      'wingYaw': 0,
      'wingHeight': 0,
      'wingDepth': 0,
      'wingScale': 1,
      'riderHeight': 0,
      'riderForward': 0,
      'flight': false,
    };
  }

  static Future<void> _applyState(
    StudioScene scene,
    Map<String, dynamic> value,
  ) async {
    final p = object(value['scene'], 'scene');
    await SceneProfile.apply(scene, _presentation(scene, p));
    final wing = object(value['wingTransform'], 'wingTransform');
    final bone = wing['boneIndex'] as int;
    if (bone >= scene.wingBoneCount) {
      throw const FormatException('El hueso no existe en el rig cargado.');
    }
    if (!scene.wingBoneWritable && bone != scene.wingBoneIndex) {
      throw const FormatException(
        'El hueso requiere un WingPosition.xml editable.',
      );
    }
    scene.applyWingTransformSnapshot(wing);
    final rider = object(value['riderTransform'], 'riderTransform');
    final pos = object(rider['position'], 'position');
    final rot = object(rider['rotationDegrees'], 'rotation');
    final scale = object(rider['scale'], 'scale');
    final mirror = object(rider['mirror'], 'mirror');
    scene.riderLateral = (pos['x'] as num).toDouble();
    scene.riderHeight = (pos['y'] as num).toDouble();
    scene.riderForward = (pos['z'] as num).toDouble();
    scene.riderRotX = (rot['x'] as num).toDouble();
    scene.riderRotY = (rot['y'] as num).toDouble();
    scene.riderRotZ = (rot['z'] as num).toDouble();
    scene.riderScaleX = (scale['x'] as num).toDouble();
    scene.riderScaleY = (scale['y'] as num).toDouble();
    scene.riderScaleZ = (scale['z'] as num).toDouble();
    scene.riderMirrorX = mirror['x'] as bool;
    scene.riderMirrorY = mirror['y'] as bool;
    scene.riderMirrorZ = mirror['z'] as bool;
    scene.setRiderProfile(rider['profile'] as int);
    scene.wingAutoMotion = value['wingAutoMotion'] as bool;
    if (p['flight'] == true) await scene.requestFlight(true);
    scene.updateAttachments();
    scene.changed();
  }
}
