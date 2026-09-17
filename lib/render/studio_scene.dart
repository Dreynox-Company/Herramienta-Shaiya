import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:three_js/three_js.dart' as t;
import 'package:vector_math/vector_math_64.dart' as v;
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import '../core/formats.dart';
import '../core/textures.dart';
import '../core/combat.dart';
import '../core/locomotion.dart';
import '../core/attachment_pose.dart';
import '../data/library.dart';
import '../data/catalog.dart';
import '../core/navigation.dart';
import '../core/identity_mask.dart';
import '../core/world_resources.dart';
import '../core/game_metadata.dart';
import 'world_builder.dart';
part 'studio_gameplay.dart';

class RenderPart {
  final MeshData data;
  final t.Mesh mesh;
  final t.Float32BufferAttribute position;
  final t.Texture texture;
  final void Function()? releaseTexture;
  bool _disposed = false;
  RenderPart(
    this.data,
    this.mesh,
    this.position,
    this.texture, {
    this.releaseTexture,
  });
  void skin(List<v.Matrix4> world) {
    if (data.inverses.isEmpty) return;
    final palette = List.generate(
      math.min(world.length, data.inverses.length),
      (i) => (world[i] * data.inverses[i]).storage,
    );
    for (var i = 0; i < data.vertices; i++) {
      final x = data.positions[i * 3],
          y = data.positions[i * 3 + 1],
          z = data.positions[i * 3 + 2];
      var px = 0.0, py = 0.0, pz = 0.0;
      for (var k = 0; k < 4; k++) {
        final w = data.weights[i * 4 + k];
        if (w <= 1e-7) continue;
        final j = data.joints[i * 4 + k];
        if (j >= palette.length) continue;
        final m = palette[j];
        px += w * (m[0] * x + m[4] * y + m[8] * z + m[12]);
        py += w * (m[1] * x + m[5] * y + m[9] * z + m[13]);
        pz += w * (m[2] * x + m[6] * y + m[10] * z + m[14]);
      }
      position.setXYZ(i, px, py, pz);
    }
    position.needsUpdate = true;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    mesh.removeFromParent();
    mesh.geometry?.dispose();
    mesh.material?.dispose();
    if (releaseTexture != null) {
      releaseTexture!();
    } else {
      texture.dispose();
    }
  }
}

class Actor {
  final t.Group root = t.Group();
  final List<RenderPart> parts = [];
  ClipData? clip, idle, normal, walk, run, riderIdle, riderMoving;
  int? wingBone;
  v.Matrix4? wingReference;
  double time = 0, speed = 1;
  bool playing = true, loop = true;
  List<v.Matrix4> world = [];
  final Map<String, ClipData> clips = {};
  void pose() {
    if (clip == null) return;
    world = clip!.pose(time, loop: loop);
    for (final p in parts) {
      p.skin(world);
    }
  }

  void tick(double dt) {
    if (playing) time += dt * speed;
    if (!loop && clip != null && time > clip!.duration && idle != null) {
      play(idle!);
    }
    pose();
  }

  void play(ClipData c, {bool repeat = true}) {
    clip = c;
    time = 0;
    loop = repeat;
    playing = true;
    pose();
  }

  int get requiredBones =>
      parts.fold(0, (n, p) => math.max(n, p.data.requiredBones));
  double get height =>
      parts.isEmpty ? 2 : parts.map((p) => p.data.maxY).reduce(math.max);
  void dispose() {
    root.removeFromParent();
    for (final p in parts) {
      p.dispose();
    }
    parts.clear();
  }
}

class _WeaponMotionSet {
  final List<ClipData> attacks;
  final ClipData? idle;
  const _WeaponMotionSet(this.attacks, this.idle);
}

class StudioScene extends ChangeNotifier {
  final void Function(String) report;
  StudioScene(this.report);
  final GameplayState game = GameplayState();
  final Map<String, Future<TextureLease>> _textures = {};
  t.ThreeJS? view;
  Catalog? catalog;
  Actor? character, enemy, mount, wing;
  Appearance? appearance;
  CreatureRecord? enemyRecord, mountRecord, wingRecord;
  RenderPart? weapon, secondWeapon, sky;
  WeaponRecord? weaponRecord;
  Attachment? weaponAttachment, secondAttachment;
  List<ClipData> attackClips = [];
  int attackCounter = 0;
  bool running = false, touchRun = false;
  final movementTransitions = LocomotionTransitions();
  final Set<String> _missingMovementWarnings = {};
  t.Group environment = t.Group();
  final List<RenderPart> environmentParts = [];
  WorldData? world;
  String? worldPath, effectPath, skyPath;
  final Map<String, ({double height, double forward})> _seats = {};
  String lastImpact = '';
  t.Sprite? hitSprite;
  t.Texture? effectTexture;
  double hitLife = 0;
  final Combat combat = Combat();
  AudioPlayer? _audio;
  AudioPlayer get audio => _audio ??= AudioPlayer();
  bool separateCostumeHead = true;
  bool sound = true,
      wireframe = false,
      ready = false,
      disposed = false,
      busy = false;
  int _appearanceRevision = 0,
      _creatureRevision = 0,
      _mountRevision = 0,
      _wingRevision = 0,
      _worldRevision = 0,
      _weaponRevision = 0,
      _clipRevision = 0,
      _effectRevision = 0,
      _skyRevision = 0;
  double yaw = .25,
      pitch = .18,
      distance = 5.2,
      targetY = 1.05,
      panX = 0,
      panZ = 0;
  double riderHeight = 1.0,
      riderForward = 0,
      wingHeight = 1.3,
      wingDepth = .25,
      wingSize = 1;
  double originX = 0,
      originZ = 0,
      groundY = 0,
      walkX = 0,
      walkZ = 0,
      _frameAccumulator = 0,
      _uiAccumulator = 0;
  String status = 'Selecciona la carpeta DATA.';
  List<String> get animations => appearance?.archetype.animations ?? [];
  Future<void> setup(t.ThreeJS three) async {
    view = three;
    three.scene = t.Scene();
    three.camera = t.PerspectiveCamera(
      45,
      three.width / three.height,
      .02,
      2500,
    );
    three.scene.background = t.Color.fromHex32(0x11151e);
    three.scene.add(environment);
    final points = <double>[], indices = <int>[];
    void strip(double x1, double z1, double x2, double z2) {
      final n = points.length ~/ 3;
      final dx = (x2 - x1).abs() < 0.01 ? 0.004 : 0.0,
          dz = (z2 - z1).abs() < 0.01 ? 0.004 : 0.0;
      points.addAll([
        x1 - dx,
        -.02,
        z1 - dz,
        x2 - dx,
        -.02,
        z2 - dz,
        x2 + dx,
        -.02,
        z2 + dz,
        x1 + dx,
        -.02,
        z1 + dz,
      ]);
      indices.addAll([n, n + 1, n + 2, n, n + 2, n + 3]);
    }

    for (var i = -15; i <= 15; i++) {
      strip(i.toDouble(), -15, i.toDouble(), 15);
      strip(-15, i.toDouble(), 15, i.toDouble());
    }
    final geometry = t.BufferGeometry()
      ..setAttributeFromString(
        'position',
        t.Float32BufferAttribute.fromList(points, 3),
      );
    geometry.setIndex(indices);
    three.scene.add(
      t.Mesh(
        geometry,
        t.MeshBasicMaterial.fromMap({'color': 0x323b4d, 'side': t.DoubleSide}),
      ),
    );
    combat.onTargetEvent = (id, actor, event) {
      unawaited(combatEventFor(id, actor, event));
    };
    combat.distanceToTarget = (id) => targetDistance(id);
    three.addAnimationEvent(tick);
    ready = true;
    updateCamera();
    notifyListeners();
  }

  void changed() {
    if (!disposed) notifyListeners();
  }

  void say(String value) {
    status = value;
    report(value);
    if (!disposed) notifyListeners();
  }

  Future<RenderPart> makePart(
    MeshData data,
    String texturePath, {
    bool opaque = false,
  }) async {
    final key = '${catalog!.library.location}|$texturePath|$opaque';
    final future = _textures.putIfAbsent(key, () async {
      final bytes = await catalog!.library.read(texturePath);
      final png = await compute(_decodeTexture, {
        'bytes': bytes,
        'path': texturePath,
        'opaque': opaque,
      });
      final texture = await t.TextureLoader(flipY: false).fromBytes(png);
      if (texture == null) {
        throw FormatException('No se pudo cargar $texturePath');
      }
      texture.colorSpace = t.SRGBColorSpace;
      texture.wrapS = t.RepeatWrapping;
      texture.wrapT = t.RepeatWrapping;
      return TextureLease(texture);
    });
    TextureLease lease;
    try {
      lease = await future;
    } catch (_) {
      _textures.remove(key);
      rethrow;
    }
    lease.users++;
    final texture = lease.texture;
    final geometry = t.BufferGeometry(),
        positions = t.Float32BufferAttribute.fromList(
          data.positions.toList(),
          3,
        );
    geometry.setAttributeFromString('position', positions);
    geometry.setAttributeFromString(
      'normal',
      t.Float32BufferAttribute.fromList(data.normals.toList(), 3),
    );
    geometry.setAttributeFromString(
      'uv',
      t.Float32BufferAttribute.fromList(data.uv.toList(), 2),
    );
    geometry.setIndex(data.indices.toList());
    final material = t.MeshBasicMaterial.fromMap({
      'map': texture,
      'color': 0xffffff,
      'side': t.DoubleSide,
      'alphaTest': opaque ? 0.0 : .35,
      'wireframe': wireframe,
      'toneMapped': false,
    });
    final mesh = t.Mesh(geometry, material);
    mesh.frustumCulled = false;
    return RenderPart(
      data,
      mesh,
      positions,
      texture,
      releaseTexture: () {
        lease.users--;
        if (lease.users == 0) {
          _textures.remove(key);
          texture.dispose();
        }
      },
    );
  }

  Future<RenderPart> skinned(
    String mesh,
    String texture, {
    int alpha = 0,
  }) async {
    final data = MeshData.skinned(await catalog!.library.read(mesh), mesh);
    for (final repair in data.repairs) {
      report('$mesh · $repair');
    }
    return makePart(data, texture, opaque: alpha == 1);
  }

  Future<ClipData> clip(String path) =>
      catalog!.library.read(path).then((b) => ClipData.parse(b, path));
  bool compatible(Actor actor, ClipData clip) =>
      actor.requiredBones <= clip.bones.length;
  Future<ClipData?> firstCompatible(Actor actor, List<String> paths) async {
    // Priority is supplied by the caller. Never rank by a substring of normal.
    for (final path in paths) {
      try {
        final c = actor.clips[path] ?? await clip(path);
        if (compatible(actor, c)) {
          actor.clips[path] = c;
          return c;
        }
      } catch (e) {
        report(e.toString());
      }
    }
    return null;
  }

  Future<void> setAppearance(Appearance next) async {
    final revision = ++_appearanceRevision;
    busy = true;
    notifyListeners();
    final staged = Actor();
    var committed = false;
    try {
      next = await catalog!.resolveAppearance(next);
      if (disposed || revision != _appearanceRevision) {
        staged.dispose();
        return;
      }
      final prepared = <(PartRecord, MeshData)>[];
      for (final p in next.effective) {
        prepared.add((p, await catalog!.appearanceMesh(p.meshPath)));
        if (disposed || revision != _appearanceRevision) {
          staged.dispose();
          return;
        }
      }
      final face = prepared
          .where((e) => e.$1.slot == Slot.face)
          .firstOrNull
          ?.$2;
      for (final entry in prepared) {
        final record = entry.$1, original = entry.$2;
        final data =
            separateCostumeHead && record.slot == Slot.upper && face != null
            ? keepSelectedHead(original, face)
            : original;
        for (final repair in data.repairs) {
          report('${record.meshPath} · $repair');
        }
        final part = await makePart(
          data,
          record.texturePath,
          opaque: record.raw.alpha == 1,
        );
        staged.parts.add(part);
        staged.root.add(part.mesh);
        if (disposed || revision != _appearanceRevision) {
          staged.dispose();
          return;
        }
      }
      final c = await firstCompatible(
        staged,
        groundMotionCandidates(next.archetype.animations, GroundMotion.idle),
      );
      if (c == null) {
        throw FormatException(
          'No hay reposo terrestre compatible para ${next.archetype.id}. No se sustituye por natación.',
        );
      }
      final nextJumpClip = await firstCompatible(
        staged,
        next.archetype.animations.where((p) => motionIndex(p) == 8).toList(),
      );
      staged.walk = await firstCompatible(
        staged,
        groundMotionCandidates(next.archetype.animations, GroundMotion.walk),
      );
      staged.run = await firstCompatible(
        staged,
        groundMotionCandidates(next.archetype.animations, GroundMotion.run),
      );
      staged.riderIdle = await firstCompatible(
        staged,
        next.archetype.animations
            .where((p) => p.toLowerCase().endsWith('_021_veh_br.ani'))
            .toList(),
      );
      staged.riderMoving = await firstCompatible(
        staged,
        next.archetype.animations
            .where((p) => p.toLowerCase().endsWith('_020_veh_run.ani'))
            .toList(),
      );
      staged.idle = c;
      staged.normal = c;
      staged.play(c);
      var score = double.infinity;
      for (var i = 1; i < math.min(staged.world.length, 12); i++) {
        final m = staged.world[i].storage;
        final d =
            (m[13] - staged.height * .74).abs() +
            m[12].abs() * .7 +
            m[14].abs() * .3;
        if (d < score && staged.world[i].determinant().abs() > 1e-12) {
          score = d;
          staged.wingBone = i;
          staged.wingReference = v.Matrix4.inverted(staged.world[i]);
        }
      }
      final keep =
          appearance?.archetype.id == next.archetype.id &&
          appearance?.archetype.race == next.archetype.race;
      // Prepare dependent animations before publishing any geometry. A failed
      // preparation must never dispose a newly published valid actor.
      final motions = await _loadWeaponMotions(
        staged,
        next.archetype.animations,
        keep ? weaponRecord : null,
      );
      staged.idle = motions.idle ?? staged.normal;
      if (mount != null && staged.riderIdle != null) {
        staged.play(staged.riderIdle!);
      } else if (staged.idle != null) {
        staged.play(staged.idle!);
      }
      if (disposed || revision != _appearanceRevision) {
        staged.dispose();
        return;
      }
      staged.root.scale.z = -1;
      final old = character;
      if (old != null) {
        staged.root.position.setValues(
          old.root.position.x,
          old.root.position.y,
          old.root.position.z,
        );
        staged.root.rotation.y = old.root.rotation.y;
      }
      if (keep) {
        for (final part in [weapon, secondWeapon]) {
          if (part != null) {
            part.mesh.removeFromParent();
            staged.root.add(part.mesh);
          }
        }
      } else {
        weapon?.dispose();
        secondWeapon?.dispose();
        weapon = null;
        secondWeapon = null;
        weaponRecord = null;
        weaponAttachment = null;
        secondAttachment = null;
      }
      ++_weaponRevision;
      ++_clipRevision;
      movementTransitions.invalidate();
      _missingMovementWarnings.clear();
      attackClips
        ..clear()
        ..addAll(motions.attacks);
      attackCounter = 0;
      character?.dispose();
      character = staged;
      game.jump.reset();
      game.jumpClip = nextJumpClip;
      appearance = next;
      view!.scene.add(staged.root);
      committed = true;
      combat.reset();
      if (attackClips.isNotEmpty) {
        combat.attackDuration = attackClips.first.duration;
      }
      updateAttachments();
      updateCamera();
      say(
        'Apariencia aplicada · ${staged.parts.fold(0, (n, p) => n + p.data.triangles)} triángulos.',
      );
    } catch (e) {
      if (!committed) {
        staged.dispose();
        say('Se conserva la apariencia anterior. $e');
      } else {
        report(
          'La apariencia se cargó, pero falló una actualización de interfaz: $e',
        );
      }
      rethrow;
    } finally {
      if (revision == _appearanceRevision) {
        busy = false;
        if (!disposed) notifyListeners();
      }
    }
  }

  Future<void> selectAnimation(String path) async {
    final a = character;
    if (a == null) return;
    final revision = ++_clipRevision, c = a.clips[path] ?? await clip(path);
    if (disposed || revision != _clipRevision || a != character) return;
    if (!compatible(a, c)) {
      throw FormatException(
        'Animación incompatible: necesita ${a.requiredBones} huesos y contiene ${c.bones.length}.',
      );
    }
    a.clips[path] = c;
    a.play(c);
    say('${animationLabel(path)} · ${c.duration.toStringAsFixed(2)} s');
  }

  Future<Actor> loadCreature(CreatureRecord c) async {
    final lib = catalog!.library, root = directoryName(c.source), a = Actor();
    try {
      for (final p in c.parts.where((p) => !p.isNull)) {
        final m = lib.resolve(p.mesh, ['$root/3dc', root]),
            tex = lib.resolve(p.texture, ['$root/dds', root]);
        if (m == null || tex == null) {
          throw FormatException(
            'Falta una pieza de ${c.name}: ${m == null ? p.mesh : p.texture}',
          );
        }
        final part = await skinned(m, tex);
        a.parts.add(part);
        a.root.add(part.mesh);
      }
      for (final entry in c.animations.entries) {
        final p = lib.resolve(entry.value, ['$root/ani', root]);
        if (p == null) continue;
        try {
          final animation = await clip(p);
          if (compatible(a, animation)) a.clips[entry.key] = animation;
        } catch (e) {
          report(e.toString());
        }
      }
      final idle =
          a.clips['Respirar'] ??
          a.clips['Reposo'] ??
          (a.clips.isEmpty ? null : a.clips.values.first);
      if (idle != null) {
        a.idle = idle;
        a.normal = idle;
        a.play(idle);
      }
      a.root.scale.z = -1;
      return a;
    } catch (_) {
      a.dispose();
      rethrow;
    }
  }

  Future<void> selectCreature(CreatureRecord? c, String kind) async {
    if (kind == 'enemy') {
      await replaceOpponent(c);
      return;
    }
    final revision = kind == 'enemy'
        ? ++_creatureRevision
        : kind == 'mount'
        ? ++_mountRevision
        : ++_wingRevision;
    if (kind == 'mount' && mountRecord != null) {
      _seats['${mountRecord!.source}#${mountRecord!.id}'] = (
        height: riderHeight,
        forward: riderForward,
      );
    }
    final staged = c == null ? null : await loadCreature(c);
    final current = kind == 'enemy'
        ? _creatureRevision
        : kind == 'mount'
        ? _mountRevision
        : _wingRevision;
    if (disposed || revision != current) {
      staged?.dispose();
      return;
    }
    if (kind == 'enemy') {
      enemy?.dispose();
      enemy = staged;
      enemyRecord = c;
      combat.reset();
      if (staged != null) {
        staged.root.position.setValues(1.8, groundY, 0);
        staged.root.rotation.y = -math.pi / 2;
      }
    } else if (kind == 'mount') {
      mount?.dispose();
      mount = staged;
      mountRecord = c;
      combat.reset();
      if (staged != null) {
        final seat = _seats['${c!.source}#${c.id}'];
        riderHeight = seat?.height ?? (staged.height * .58).clamp(.2, 5.0);
        riderForward = seat?.forward ?? 0;
        await riderPose();
      } else if (character?.idle != null) {
        character!.play(character!.idle!);
      }
    } else {
      wing?.dispose();
      wing = staged;
      wingRecord = c;
    }
    if (staged != null) view!.scene.add(staged.root);
    if (kind == 'wing' && staged != null) staged.root.matrixAutoUpdate = false;
    if (kind == 'mount') movementTransitions.invalidate();
    updateAttachments();
    distance = mount != null ? math.max(7, mount!.height * 2.5) : 5.2;
    updateCamera();
    say(
      c == null
          ? 'Elemento retirado.'
          : '${catalog!.creatureLabel(c)} cargado.',
    );
  }

  Future<void> riderPose() async {
    final a = character;
    if (a == null) return;
    if (a.riderIdle != null) a.play(a.riderIdle!);
    movementTransitions.invalidate();
  }

  Future<void> equip(WeaponRecord? w) async {
    final a = character;
    if (a == null) return;
    final rev = ++_weaponRevision;
    if (w == null) {
      weapon?.dispose();
      secondWeapon?.dispose();
      weapon = null;
      secondWeapon = null;
      weaponRecord = null;
      weaponAttachment = null;
      secondAttachment = null;
      await prepareWeaponMotions();
      await rebuildWeaponEffect();
      notifyListeners();
      return;
    }
    final lib = catalog!.library,
        root = directoryName(w.source),
        m = lib.resolve(w.mesh, ['$root/3do', root]),
        tex = lib.resolve(w.texture, ['$root/dds', root]);
    if (m == null || tex == null) {
      throw FormatException('Faltan recursos del arma ${w.id}.');
    }
    final data = MeshData.object(await lib.read(m), m);
    final part = await makePart(data, tex, opaque: w.alpha != 0);
    if (disposed || rev != _weaponRevision || character != a) {
      part.dispose();
      return;
    }
    final code = archetypeCodes.indexOf(appearance!.archetype.id);
    Attachment? attachment;
    if (code >= 0 && code < w.transforms.length) {
      attachment = w.transforms[code][0];
    }
    if (attachment == null ||
        !attachment.defined ||
        attachment.bone >= a.world.length) {
      part.dispose();
      throw const FormatException(
        'Esta arma no define un anclaje válido para el arquetipo actual.',
      );
    }
    RenderPart? other;
    Attachment? otherAttachment;
    if ([5, 15].contains(weaponFamily(w)) && w.transforms[code][1].defined) {
      otherAttachment = w.transforms[code][1];
      if (otherAttachment.bone >= a.world.length) {
        part.dispose();
        throw const FormatException(
          'El segundo anclaje requiere otro esqueleto.',
        );
      }
      try {
        other = await makePart(data, tex, opaque: w.alpha != 0);
      } catch (_) {
        part.dispose();
        rethrow;
      }
    }
    if (disposed || rev != _weaponRevision || character != a) {
      part.dispose();
      other?.dispose();
      return;
    }
    weapon?.dispose();
    secondWeapon?.dispose();
    weapon = part;
    secondWeapon = other;
    weaponRecord = w;
    weaponAttachment = attachment;
    secondAttachment = otherAttachment;
    for (final p in [part, other]) {
      if (p != null) {
        a.root.add(p.mesh);
        p.mesh.matrixAutoUpdate = false;
      }
    }
    await prepareWeaponMotions();
    try {
      await rebuildWeaponEffect();
    } catch (e) {
      report(
        'El arma se equipó, pero el efecto seleccionado no pudo cargarse: $e',
      );
    }
    updateAttachments();
    say(
      '${weaponLabel(w)} equipado${other == null ? '' : ' en ambas manos'} con anclajes IT2 originales.',
    );
  }

  Future<_WeaponMotionSet> _loadWeaponMotions(
    Actor a,
    List<String> available,
    WeaponRecord? equipped,
  ) async {
    final loaded = <ClipData>[];
    final family = weaponFamily(equipped), wanted = attackMotions(family);
    final candidates = wanted.isEmpty
        ? available.where((p) => p.contains('attack')).take(4)
        : available.where((p) => wanted.contains(motionIndex(p)));
    for (final path in candidates) {
      final c = await firstCompatible(a, [path]);
      if (c != null) loaded.add(c);
    }
    final ready = readyMotion(family);
    final paths = ready == null
        ? <String>[]
        : available.where((p) => motionIndex(p) == ready).toList();
    final idle = paths.isEmpty ? a.normal : await firstCompatible(a, paths);
    return _WeaponMotionSet(loaded, idle ?? a.normal);
  }

  Future<void> prepareWeaponMotions() async {
    final a = character, selectedWeapon = weaponRecord;
    if (a == null) return;
    final revision = _weaponRevision;
    final prepared = await _loadWeaponMotions(a, animations, selectedWeapon);
    if (disposed ||
        a != character ||
        revision != _weaponRevision ||
        selectedWeapon != weaponRecord) {
      return;
    }
    attackClips
      ..clear()
      ..addAll(prepared.attacks);
    attackCounter = 0;
    if (prepared.idle != null) {
      a.idle = prepared.idle;
      if (mount == null && walkX == 0 && walkZ == 0) a.play(prepared.idle!);
    }
    movementTransitions.invalidate();
    if (attackClips.isNotEmpty) {
      combat.attackDuration = attackClips.first.duration;
    }
  }

  void setMovement(double x, double z, {bool run = false}) {
    if (disposed) return;
    walkX = x.isFinite ? x.clamp(-1.0, 1.0) : 0;
    walkZ = z.isFinite ? z.clamp(-1.0, 1.0) : 0;
    running = run;
    if (x != 0 || z != 0) {
      game.destination = null;
      game.route.clear();
      game.destinationRing?.visible = false;
    }
  }

  void clearMovement() {
    setMovement(0, 0);
    game.destination = null;
    game.route.clear();
    game.destinationRing?.visible = false;
  }

  bool get sceneCombatLocked {
    final a = character;
    return busy ||
        combat.playerHealth <= 0 ||
        (combat.active &&
            a != null &&
            !a.loop &&
            a.clip != null &&
            a.time < a.clip!.duration);
  }

  ClipData? movementClip(GroundMotion mode) {
    final a = character;
    if (a == null) return null;
    if (mount != null) {
      if (mode != GroundMotion.idle &&
          mount!.clips['Caminar'] == null &&
          mount!.clips['Correr'] == null) {
        return null;
      }
      return mode == GroundMotion.idle ? a.riderIdle : a.riderMoving;
    }
    return switch (mode) {
      GroundMotion.idle => a.idle ?? a.normal,
      GroundMotion.walk => a.walk,
      GroundMotion.run => a.run,
    };
  }

  bool applyLocomotion(GroundMotion mode) {
    final a = character;
    if (a == null || sceneCombatLocked) return false;
    final desired = movementClip(mode), vehicle = mount;
    if (vehicle != null && mode != GroundMotion.idle) {
      final movement =
          vehicle.clips[mode == GroundMotion.run ? 'Correr' : 'Caminar'] ??
          vehicle.clips['Correr'] ??
          vehicle.clips['Caminar'];
      if (movement == null) return false;
    }
    if (desired == null) {
      final key = '${appearance?.archetype.id}:${mode.name}:${mount != null}';
      if (_missingMovementWarnings.add(key)) {
        report(
          'No hay animación compatible de ${mode == GroundMotion.run
              ? 'correr'
              : mode == GroundMotion.walk
              ? 'caminar'
              : 'reposo'}. Se impide el desplazamiento sin animación.',
        );
      }
      return false;
    }
    a.play(desired);
    if (vehicle != null) {
      final key = mode == GroundMotion.idle
          ? 'Respirar'
          : mode == GroundMotion.run
          ? 'Correr'
          : 'Caminar';
      final c =
          vehicle.clips[key] ??
          vehicle.clips[mode == GroundMotion.idle ? 'Reposo' : 'Correr'] ??
          (mode == GroundMotion.idle
              ? vehicle.normal
              : vehicle.clips['Caminar']);
      if (c != null) vehicle.play(c);
    }
    return true;
  }

  void updateAttachments() {
    final a = character;
    if (a == null) return;
    final x = a.root.position.x,
        z = a.root.position.z,
        rotation = a.root.rotation.y;
    a.root.position.y =
        groundY + (mount == null ? game.jump.height : riderHeight);
    if (weapon != null &&
        weaponAttachment != null &&
        weaponAttachment!.bone < a.world.length) {
      weapon!.mesh.matrix.copyFromArray(
        (a.world[weaponAttachment!.bone] * weaponAttachment!.matrix).storage,
      );
      weapon!.mesh.matrixWorldNeedsUpdate = true;
    }
    if (secondWeapon != null &&
        secondAttachment != null &&
        secondAttachment!.bone < a.world.length) {
      secondWeapon!.mesh.matrix.copyFromArray(
        (a.world[secondAttachment!.bone] * secondAttachment!.matrix).storage,
      );
      secondWeapon!.mesh.matrixWorldNeedsUpdate = true;
    }
    if (mount != null) {
      mount!.root.position.setValues(
        x + math.sin(rotation) * riderForward,
        groundY,
        z + math.cos(rotation) * riderForward,
      );
      mount!.root.rotation.y = rotation;
    }
    if (wing != null) {
      final bone = a.wingBone;
      final valid =
          bone != null && bone < a.world.length && a.wingReference != null;
      final matrix = backAttachmentPose(
        position: v.Vector3(x, a.root.position.y, z),
        yaw: rotation,
        bone: valid ? a.world[bone] : v.Matrix4.identity(),
        referenceInverse: valid ? a.wingReference! : v.Matrix4.identity(),
        offset: v.Vector3(0, wingHeight, wingDepth),
        scale: wingSize,
      );
      wing!.root.matrix.copyFromArray(matrix.storage);
      wing!.root.matrixWorldNeedsUpdate = true;
    }
  }

  Future<void> previewActorAnimation(String target, String name) async {
    final a = target == 'enemy'
        ? enemy
        : target == 'mount'
        ? mount
        : wing;
    final c = a?.clips[name];
    if (a != null && c != null) a.play(c);
    notifyListeners();
  }

  Future<void> playSound(String path) => pooledSound(path);

  Future<void> setEffect(String path) async {
    final revision = ++_effectRevision, lib = catalog!.library;
    final png = await compute(_decodeTexture, {
      'bytes': await lib.read(path),
      'path': path,
      'opaque': false,
    });
    final texture = await t.TextureLoader(flipY: false).fromBytes(png);
    if (texture == null) return;
    if (disposed || revision != _effectRevision) {
      texture.dispose();
      return;
    }
    hitSprite?.removeFromParent();
    hitSprite?.material?.dispose();
    effectTexture?.dispose();
    effectTexture = texture;
    hitSprite = t.Sprite(
      t.SpriteMaterial.fromMap({
        'map': texture,
        'transparent': true,
        'depthWrite': false,
        'blending': t.AdditiveBlending,
        'color': 0xffffff,
      }),
    );
    hitSprite!.visible = false;
    view!.scene.add(hitSprite!);
    effectPath = path;
    say(
      'Textura de efecto seleccionada. La secuencia del laboratorio es una simulación.',
    );
  }

  Future<void> _combatEvent(String who, String event) async {
    try {
      final a = who == 'enemy' ? enemy : character;
      if (a == null) return;
      if (who == 'enemy') {
        final key = event == 'attack'
            ? 'Ataque 1'
            : event == 'death'
            ? 'Caída'
            : 'Daño';
        final c = a.clips[key];
        if (c != null) a.play(c, repeat: false);
        final raw = enemyRecord?.sounds[key] ?? '';
        final s = catalog?.library.resolve(raw, [
          'sound/monster',
          'sound',
        ], uniqueFallback: true);
        if (s != null) unawaited(playSound(s));
      } else {
        ClipData? c;
        if (event == 'attack' && attackClips.isNotEmpty) {
          c = attackClips[attackCounter++ % attackClips.length];
          combat.attackDuration =
              attackClips[attackCounter % attackClips.length].duration;
        } else {
          final index = event == 'death'
              ? 9
              : damageMotion(weaponFamily(weaponRecord));
          final candidates = animations
              .where(
                (p) => index != null
                    ? motionIndex(p) == index
                    : p.contains('damage'),
              )
              .toList();
          c = await firstCompatible(a, candidates);
        }
        if (c != null && a == character) a.play(c, repeat: false);
      }
      if (event == 'death') a.idle = null;
      if (event == 'hit') {
        hitLife = .65;
        lastImpact = who == 'enemy'
            ? 'Impacto −${combat.damage.round()}'
            : 'Recibido −${combat.enemyDamage.round()}';
        if (hitSprite != null) {
          hitSprite!.visible = true;
          hitSprite!.position.setValues(
            a.root.position.x,
            a.root.position.y + 1,
            -.1 + a.root.position.z,
          );
        }
      }
    } catch (e) {
      report('Animación de combate: $e');
    }
  }

  Future<void> attack() async {
    if (character == null || enemy == null) {
      throw const FormatException(
        'Carga un personaje y una criatura antes de combatir.',
      );
    }
    if (mount != null) {
      throw const FormatException(
        'Desmonta antes de iniciar la prueba de combate.',
      );
    }
    if (attackClips.isEmpty) await prepareWeaponMotions();
    if (attackClips.isEmpty) {
      throw const FormatException(
        'No existe un ataque compatible con el equipo y arquetipo seleccionados.',
      );
    }
    character!.root.rotation.y = facingYaw(
      enemy!.root.position.x - character!.root.position.x,
      enemy!.root.position.z - character!.root.position.z,
    );
    if (game.jump.airborne) {
      throw const FormatException('Espera a aterrizar antes de atacar.');
    }
    combat.attack(enemyDistance);
    notifyListeners();
  }

  double get enemyDistance {
    if (enemy == null || character == null) return double.infinity;
    final dx = enemy!.root.position.x - character!.root.position.x,
        dz = enemy!.root.position.z - character!.root.position.z;
    return math.sqrt(dx * dx + dz * dz);
  }

  void resetCombat() {
    combat.reset();
    movementTransitions.invalidate();
    for (final a in [character, ...game.opponents.values.map((e) => e.actor)]) {
      if (a == null) continue;
      final c = a.clips['Respirar'] ?? a.clips['Reposo'] ?? a.normal;
      if (c != null) {
        a.idle = c;
        a.play(c);
      }
    }
    notifyListeners();
  }

  void setWireframe(bool value) {
    wireframe = value;
    for (final a in [character, enemy, mount, wing]) {
      for (final p in a?.parts ?? <RenderPart>[]) {
        p.mesh.material?.wireframe = value;
      }
    }
    weapon?.mesh.material?.wireframe = value;
    secondWeapon?.mesh.material?.wireframe = value;
    notifyListeners();
  }

  void tick(double dt) => tickGameplay(dt);

  void orbit(double dx, double dy) {
    yaw -= dx * .006;
    pitch = (pitch + dy * .006).clamp(-1.2, 1.2);
    updateCamera();
  }

  void zoom(double amount) {
    distance = (distance * amount).clamp(.4, 250);
    updateCamera();
  }

  void updateCamera() {
    if (!ready || view == null) return;
    final a = character;
    final x = (a?.root.position.x ?? 0) + panX,
        z = (a?.root.position.z ?? 0) + panZ,
        y = groundY + targetY + (mount == null ? 0 : riderHeight * .6);
    view!.camera.position.setValues(
      x + math.sin(yaw) * math.cos(pitch) * distance,
      y + math.sin(pitch) * distance,
      z + math.cos(yaw) * math.cos(pitch) * distance,
    );
    view!.camera.lookAt(t.Vector3(x, y, z));
    game.loaded?.updateVisibility(view!.camera);
    if (sky != null) {
      sky!.mesh.position.setValues(
        view!.camera.position.x,
        view!.camera.position.y,
        view!.camera.position.z,
      );
    }
  }

  Future<void> setSky(String? path) async {
    final revision = ++_skyRevision;
    if (path == null) {
      sky?.dispose();
      sky = null;
      skyPath = null;
      notifyListeners();
      return;
    }
    final lib = catalog!.library,
        model = catalog!.library.resolve('sky.3do', ['sky']);
    if (model == null) {
      throw const FormatException(
        'No se encuentra la cúpula original Sky/sky.3DO.',
      );
    }
    final data = MeshData.object(await lib.read(model), model);
    final part = await makePart(data, path, opaque: true);
    if (disposed || revision != _skyRevision) {
      part.dispose();
      return;
    }
    var radius = 0.0;
    for (final coordinate in data.positions) {
      radius = math.max(radius, coordinate.abs());
    }
    if (radius < 1e-6) {
      part.dispose();
      throw const FormatException('Cúpula de cielo vacía.');
    }
    part.mesh.scale.setValues(850 / radius, 850 / radius, -850 / radius);
    part.mesh.renderOrder = -1000;
    part.mesh.material?.depthWrite = false;
    part.mesh.material?.depthTest = false;
    sky?.dispose();
    sky = part;
    skyPath = path;
    view!.scene.add(part.mesh);
    updateCamera();
    say('Cielo original: ${baseName(path)}');
  }

  Future<void> setWorld(String? path, {double? x, double? z}) =>
      loadWorldScene(path, x: x, z: z);

  @override
  void dispose() {
    disposed = true;
    ++_appearanceRevision;
    ++_creatureRevision;
    ++_mountRevision;
    ++_wingRevision;
    ++_worldRevision;
    ++_weaponRevision;
    ++_effectRevision;
    ++_skyRevision;
    sky?.dispose();
    disposeGameplay();
    for (final a in [character, mount, wing]) {
      a?.dispose();
    }
    weapon?.dispose();
    secondWeapon?.dispose();
    environmentParts.clear();
    effectTexture?.dispose();
    _audio?.dispose();
    super.dispose();
  }
}

Uint8List _decodeTexture(Map<String, Object> args) => Pixels.decode(
  args['bytes'] as Uint8List,
  args['path'] as String,
).png(opaque: args['opaque'] as bool);
