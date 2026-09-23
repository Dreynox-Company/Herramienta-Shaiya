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
import '../core/pose_layers.dart';
import '../core/rig_anchors.dart';
import '../core/flight_transition.dart';
import '../core/wing_motion.dart';
import '../core/mounted_motion.dart';
import '../core/equipment_rules.dart';
import '../core/extra_motion.dart';
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

class ImpactParticle {
  final t.Sprite sprite;
  double life = 0, duration = .2, size = .03, vx = 0, vy = 0, vz = 0;
  ImpactParticle(this.sprite);
}

class Actor {
  final t.Group root = t.Group(), visual = t.Group();
  Actor() {
    root.add(visual);
    visual.matrixAutoUpdate = false;
  }
  SurfaceAnchor? seat;
  int pelvisBone = 1;
  final Map<String, ClipData> mountedAttacks = {};
  final List<RenderPart> parts = [];
  ClipData? clip,
      idle,
      normal,
      walk,
      run,
      weaponRun,
      guard,
      hover,
      flight,
      riderIdle,
      riderMoving;
  HeadLookController? headLook;
  List<v.Matrix4>? _blendFrom;
  List<v.Matrix4> _rawPose = [];
  double _blendTime = .18;
  bool headTracking = false;
  int? wingBone;
  v.Matrix4? wingReference;
  double time = 0, speed = 1;
  bool playing = true, loop = true;
  List<v.Matrix4> world = [];
  final Map<String, ClipData> clips = {};
  void pose() {
    if (clip == null) return;
    final pose = clip!.pose(time, loop: loop);
    _rawPose = _blendFrom != null && _blendTime < .18
        ? blendSkeleton(_blendFrom!, pose, clip!.bones, _blendTime / .18)
        : pose;
    world = _rawPose.map((m) => m.clone()).toList();
    if (headTracking) headLook?.apply(world);
    for (final p in parts) {
      p.skin(world);
    }
  }

  void tick(double dt) {
    _blendTime += dt;
    if (_blendTime >= .18) _blendFrom = null;
    if (playing) time += dt * speed;
    if (!loop && clip != null && time > clip!.duration && idle != null) {
      play(idle!);
    }
    pose();
  }

  void play(ClipData c, {bool repeat = true}) {
    if (clip != c && _rawPose.length == c.bones.length) {
      _blendFrom = _rawPose.map((m) => m.clone()).toList();
      _blendTime = 0;
    }
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
  final ClipData? idle, run;
  const _WeaponMotionSet(this.attacks, this.idle, this.run);
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
  RenderPart? weapon, secondWeapon, shield, sky;
  WeaponRecord? weaponRecord, shieldRecord;
  Attachment? shieldAttachment;
  CharacterClass? selectedClass;
  ExtraMotionLibrary? extraMotions;
  final FlightTransition flightState = FlightTransition();
  bool flightEnabled = false,
      wingAutoMotion = true,
      headTracking = true,
      inspectAnyEquipment = false;
  WingMotionPhase? _wingMotionPhase;
  double hoverOffset = .38, wingYaw = 0;
  final Map<String, ({double height, double depth, double size, double yaw})>
  _wingSettings = {};
  bool _lastGuard = false;
  CharacterClass get characterClass =>
      selectedClass ?? classesFor(appearance?.archetype.id ?? 'humf').first;
  List<CharacterClass> get availableClasses =>
      classesFor(appearance?.archetype.id ?? 'humf');
  String get wingMotionStatus => _wingMotionPhase == null
      ? 'Sin sincronización automática'
      : wingMotionLabel(_wingMotionPhase!);

  String _wingBindingKey(CreatureRecord record, {Archetype? archetype}) {
    final a = archetype ?? appearance?.archetype;
    final identity = a == null ? 'sin-personaje' : '${a.race}/${a.id}';
    return '$identity|${record.source}#${record.id}';
  }

  void _rememberWingSettings() {
    final record = wingRecord;
    if (record == null) return;
    _wingSettings[_wingBindingKey(record)] = (
      height: wingHeight,
      depth: wingDepth,
      size: wingSize,
      yaw: wingYaw,
    );
  }

  void _restoreWingSettings() {
    final record = wingRecord, char = character;
    if (record == null || char == null) return;
    final cfg = _wingSettings[_wingBindingKey(record)];
    final bone = char.wingBone;
    final reference = char.normal?.pose(0);
    final p = bone != null && reference != null && bone < reference.length
        ? reference[bone].getTranslation()
        : v.Vector3(0, 1.3, 0);
    wingHeight = cfg?.height ?? p.y;
    wingDepth = cfg?.depth ?? (p.z + .08);
    wingSize = cfg?.size ?? 1;
    wingYaw = cfg?.yaw ?? 0;
  }

  Future<void> setWingAutoMotion(bool enabled) async {
    wingAutoMotion = enabled;
    _wingMotionPhase = null;
    if (enabled) {
      final moving =
          walkX.abs() + walkZ.abs() > 1e-8 || game.destination != null;
      _syncWingMotion(moving);
    }
    changed();
  }

  void _syncWingMotion(bool moving) {
    final actor = wing;
    if (!wingAutoMotion || actor == null || actor.clips.isEmpty) return;
    final phase = wingMotionPhase(
      flightEnabled: flightEnabled,
      grounded: flightState.grounded,
      landing: flightState.landing || flightState.combatDescent,
      moving: moving,
    );
    final clip = selectWingMotion(actor.clips, phase);
    _wingMotionPhase = phase;
    if (clip != null &&
        (actor.clip != clip || !actor.playing || !actor.loop)) {
      actor.play(clip);
    }
  }

  EquipmentCompatibility compatibilityFor(
    WeaponRecord item, {
    Archetype? archetype,
    CharacterClass? cls,
  }) {
    final a = archetype ?? appearance?.archetype;
    if (a == null) {
      return const EquipmentCompatibility(
        false,
        false,
        'Selecciona un personaje',
      );
    }
    return equipmentCompatibility(
      weapon: item,
      race: a.race,
      characterClass: cls ?? characterClass,
      rules: catalog?.names.itemRules['${weaponFamily(item)}:${item.id}'] ?? [],
      archetypeIndex: archetypeCodes.indexOf(a.id),
    );
  }

  List<WeaponRecord> get availableWeapons => (catalog?.weapons ?? [])
      .where(
        (w) =>
            !isShield(w) &&
            (inspectAnyEquipment || compatibilityFor(w).allowed),
      )
      .toList();
  List<WeaponRecord> get availableShields => (catalog?.weapons ?? [])
      .where(
        (w) =>
            isShield(w) && (inspectAnyEquipment || compatibilityFor(w).allowed),
      )
      .toList();
  bool get flying =>
      flightAvailable &&
      !combat.inGuard &&
      flightState.pendingTarget == null &&
      !flightState.combatDescent;
  bool get flightAvailable =>
      combat.playerHealth > 0 &&
      flightEnabled &&
      wing != null &&
      mount == null &&
      character?.hover != null &&
      character?.flight != null;
  List<ClipData> get combatClips {
    if (mount == null) return attackClips;
    final key = mountedMotionKey(weaponFamily(weaponRecord));
    final clip = character?.mountedAttacks[key];
    return clip == null ? const [] : [clip];
  }

  Attachment? weaponAttachment, secondAttachment;
  List<ClipData> attackClips = [];
  int attackCounter = 0;
  bool running = false, touchRun = false;
  final movementTransitions = LocomotionTransitions();
  final Set<String> _missingMovementWarnings = {};
  t.Group environment = t.Group();
  List<RenderPart> get environmentParts =>
      game.loaded?.parts ?? const <RenderPart>[];
  WorldData? world;
  String? worldPath, effectPath, skyPath;
  final Map<String, ({double height, double forward})> _seats = {};
  String lastImpact = '';
  t.Sprite? hitSprite;
  t.Texture? effectTexture;
  double hitLife = 0;
  final List<ImpactParticle> impactParticles = [];
  int _impactCursor = 0;
  double _impactSequence = 0;
  Future<void>? _impactPreparing;
  Future<void> prepareImpactParticles() {
    if (impactParticles.isNotEmpty || disposed || view == null) {
      return Future<void>.value();
    }
    return _impactPreparing ??= _createImpactParticles().whenComplete(
      () => _impactPreparing = null,
    );
  }

  Future<void> _createImpactParticles() async {
    if (impactParticles.isNotEmpty || disposed) return;
    final rev = _effectRevision;
    t.Texture? texture = effectTexture;
    if (texture == null) {
      final rgba = Uint8List(16 * 16 * 4);
      for (var y = 0; y < 16; y++) {
        for (var x = 0; x < 16; x++) {
          final i = (y * 16 + x) * 4,
              d = math.sqrt(
                math.pow((x - 7.5) / 7.5, 2) + math.pow((y - 7.5) / 7.5, 2),
              );
          rgba[i] = 255;
          rgba[i + 1] = 229;
          rgba[i + 2] = 184;
          rgba[i + 3] = ((1 - d).clamp(0.0, 1.0) * 230).round();
        }
      }
      texture = await t.TextureLoader(
        flipY: false,
      ).fromBytes(Pixels(16, 16, rgba).png());
      if (texture == null) return;
      if (disposed || rev != _effectRevision) {
        texture.dispose();
        return;
      }
      effectTexture = texture;
    }
    if (impactParticles.isNotEmpty || disposed || rev != _effectRevision) {
      return;
    }
    for (var i = 0; i < 32; i++) {
      final sprite = t.Sprite(
        t.SpriteMaterial.fromMap({
          'map': texture,
          'transparent': true,
          'depthWrite': false,
          'blending': t.AdditiveBlending,
          'color': 0xffffff,
          'opacity': 0.0,
        }),
      );
      sprite.visible = false;
      view!.scene.add(sprite);
      impactParticles.add(ImpactParticle(sprite));
    }
  }

  void clearImpactParticles() {
    for (final p in impactParticles) {
      p.sprite.removeFromParent();
      p.sprite.material?.dispose();
    }
    impactParticles.clear();
  }

  Future<void> emitImpact(Actor actor) async {
    await prepareImpactParticles();
    if (disposed || impactParticles.isEmpty) return;
    _impactSequence++;
    actor.root.updateMatrixWorld(true);
    final impact = t.Vector3(0, (actor.height * .57).clamp(.3, 2.5), 0)
      ..applyMatrix4(actor.visual.matrixWorld);
    for (var i = 0; i < 7; i++) {
      final p = impactParticles[_impactCursor++ % impactParticles.length],
          angle = i * 2.399 + _impactSequence * .37;
      p.life = p.duration = .16 + i * .012;
      p.size = .024 + (i % 3) * .009;
      p.vx = math.cos(angle) * .34;
      p.vz = math.sin(angle) * .34;
      p.vy = .12 + (i % 4) * .11;
      p.sprite.position.setValues(impact.x, impact.y, impact.z);
      p.sprite.visible = true;
      p.sprite.scale.setValues(p.size, p.size, 1);
      p.sprite.material?.opacity = 1;
    }
  }

  void tickImpacts(double dt) {
    for (final p in impactParticles) {
      if (p.life <= 0) continue;
      p.life -= dt;
      p.sprite.visible = p.life > 0;
      if (!p.sprite.visible) continue;
      p.sprite.position.x += p.vx * dt;
      p.sprite.position.z += p.vz * dt;
      p.sprite.position.y += p.vy * dt;
      p.vy -= 1.2 * dt;
      final ratio = p.life / p.duration;
      p.sprite.material?.opacity = ratio;
      p.sprite.scale.setValues(
        p.size * (.4 + .6 * ratio),
        p.size * (.4 + .6 * ratio),
        1,
      );
    }
  }

  final Combat combat = Combat();
  AudioPlayer? _audio;
  AudioPlayer get audio => _audio ??= AudioPlayer();
  bool separateCostumeHead = true;
  bool paused = false;
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
      _shieldRevision = 0,
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
  }) =>
      makePartFromLibrary(catalog!.library, data, texturePath, opaque: opaque);
  Future<RenderPart> makePartFromLibrary(
    Library library,
    MeshData data,
    String texturePath, {
    bool opaque = false,
  }) async {
    final key =
        '${identityHashCode(library)}|${library.revision}|$texturePath|$opaque';
    final future = _textures.putIfAbsent(key, () async {
      final bytes = await library.read(texturePath);
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

  void clearAppearance() {
    ++_appearanceRevision;
    ++_weaponRevision;
    ++_shieldRevision;
    ++_clipRevision;
    movementTransitions.invalidate();
    _missingMovementWarnings.clear();

    character?.dispose();
    character = null;
    appearance = null;

    weapon?.dispose();
    secondWeapon?.dispose();
    shield?.dispose();
    weapon = null;
    secondWeapon = null;
    shield = null;
    weaponRecord = null;
    shieldRecord = null;
    weaponAttachment = null;
    secondAttachment = null;
    shieldAttachment = null;
    selectedClass = null;
    extraMotions = null;

    attackClips.clear();
    attackCounter = 0;
    game.jump.reset();
    game.jumpClip = null;
    combat.reset();
    _lastGuard = false;
    clearMovement();
    if (!disposed) notifyListeners();
  }

  Future<void> setAppearance(Appearance next) async {
    _rememberWingSettings();
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
        staged.visual.add(part.mesh);
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
        next.archetype.animations.where((p) => motionIndex(p) == 21).toList(),
      );
      staged.riderMoving = await firstCompatible(
        staged,
        next.archetype.animations.where((p) => motionIndex(p) == 20).toList(),
      );
      staged.idle = c;
      staged.normal = c;
      final profile = extraMotions?.profiles[next.archetype.id];
      final compatibleProfile =
          profile != null &&
          profile.matches(next.archetype.id, next.archetype.female, c);
      if (compatibleProfile) {
        staged.hover = profile.hover;
        staged.flight = profile.flight;
        staged.mountedAttacks.addAll(profile.mounted);
      }
      if (face != null) {
        final scores = <int, double>{};
        for (var i = 0; i < face.weights.length; i++) {
          scores.update(
            face.joints[i],
            (n) => n + face.weights[i],
            ifAbsent: () => face.weights[i],
          );
        }
        final candidates =
            scores.keys.where((b) => b > 0 && b < c.bones.length).toList()
              ..sort((a, b) => scores[b]!.compareTo(scores[a]!));
        final h =
            (compatibleProfile ? profile.head : null) ?? candidates.firstOrNull;
        if (h != null && h > 0 && h < c.bones.length) {
          staged.headLook = HeadLookController(h, c.bones);
        }
      }
      staged.play(c);
      staged.wingBone = backBone(c, staged.headLook?.bone, staged.height);
      final b = staged.wingBone;
      if (b != null) staged.wingReference = v.Matrix4.inverted(staged.world[b]);
      staged.pelvisBone = c.bones.length > 1 ? 1 : 0;
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
      staged.guard = motions.idle;
      staged.weaponRun = motions.run;
      staged.idle = staged.normal;
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
        for (final part in [weapon, secondWeapon, shield]) {
          if (part != null) {
            part.mesh.removeFromParent();
            staged.visual.add(part.mesh);
          }
        }
      } else {
        weapon?.dispose();
        secondWeapon?.dispose();
        shield?.dispose();
        shield = null;
        shieldRecord = null;
        shieldAttachment = null;
        ++_shieldRevision;
        selectedClass = classesFor(next.archetype.id).first;
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
      _restoreWingSettings();
      _wingMotionPhase = null;
      view!.scene.add(staged.root);
      committed = true;
      combat.reset();
      _lastGuard = false;
      refreshIdle();
      applyLocomotion(GroundMotion.idle);
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
        a.visual.add(part.mesh);
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
    if (kind == 'wing') {
      _rememberWingSettings();
    }
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
      flightState.reset();
      combat.reset();
      if (staged != null) {
        final seat = _seats['${c!.source}#${c.id}'];
        if (staged.normal != null) {
          staged.seat = SurfaceAnchor.locate(
            staged.parts.map((p) => p.data).toList(),
            staged.normal!,
          );
        }
        if (staged.seat == null) {
          report(
            'Montura sin superficie central reconocida. Usa los ajustes del asiento; no se ha certificado el encaje automático.',
          );
        }
        riderHeight = seat?.height ?? .04;
        riderForward = seat?.forward ?? 0;
        await riderPose();
      } else if (character?.idle != null) {
        character!.play(character!.idle!);
      }
    } else {
      wing?.dispose();
      wing = staged;
      wingRecord = c;
      if (c == null) {
        flightEnabled = false;
        _wingMotionPhase = null;
      } else {
        wingAutoMotion = true;
        _restoreWingSettings();
        _wingMotionPhase = null;
        _syncWingMotion(false);
      }
    }
    if (staged != null) view!.scene.add(staged.root);
    if (kind == 'wing' && staged != null) staged.root.matrixAutoUpdate = false;
    if (kind == 'mount' || kind == 'wing') {
      refreshIdle();
      movementTransitions.invalidate();
      game.jump.reset();
      applyLocomotion(
        walkX == 0 && walkZ == 0
            ? GroundMotion.idle
            : (running || touchRun ? GroundMotion.run : GroundMotion.walk),
      );
    }
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
    if (isShield(w)) {
      await equipShield(w);
      return;
    }
    if (!inspectAnyEquipment && !compatibilityFor(w).allowed) {
      throw FormatException(compatibilityFor(w).reason);
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
    if (!permitsShield(w)) {
      shield?.dispose();
      shield = null;
      shieldRecord = null;
      shieldAttachment = null;
      ++_shieldRevision;
    }
    weapon = part;
    secondWeapon = other;
    weaponRecord = w;
    weaponAttachment = attachment;
    secondAttachment = otherAttachment;
    for (final p in [part, other]) {
      if (p != null) {
        a.visual.add(p.mesh);
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
    final runId = runningMotion(family);
    final run = runId == null
        ? a.run
        : await firstCompatible(
            a,
            available.where((p) => motionIndex(p) == runId).toList(),
          );
    return _WeaponMotionSet(loaded, idle ?? a.normal, run ?? a.run);
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
    a.guard = prepared.idle;
    a.weaponRun = prepared.run;
    refreshIdle();
    if (mount == null && walkX == 0 && walkZ == 0 && a.loop && a.idle != null) {
      a.play(a.idle!);
    }
    movementTransitions.invalidate();
    if (attackClips.isNotEmpty) {
      combat.attackDuration = attackClips.first.duration;
    }
  }

  Future<void> selectClass(CharacterClass cls) async {
    if (!availableClasses.contains(cls)) {
      throw const FormatException('Clase ajena al arquetipo');
    }
    selectedClass = cls;
    if (weaponRecord != null && !compatibilityFor(weaponRecord!).allowed) {
      await equip(null);
    }
    if (shieldRecord != null && !compatibilityFor(shieldRecord!).allowed) {
      await equipShield(null);
    }
    combat.reset();
    refreshIdle();
    movementTransitions.invalidate();
    changed();
  }

  Future<void> equipShield(WeaponRecord? item) async {
    final actor = character;
    if (actor == null) return;
    final revision = ++_shieldRevision;
    if (item == null) {
      shield?.dispose();
      shield = null;
      shieldRecord = null;
      shieldAttachment = null;
      changed();
      return;
    }
    if (!isShield(item) || !permitsShield(weaponRecord)) {
      throw const FormatException(
        'El escudo requiere la mano secundaria libre y un arma de una mano.',
      );
    }
    if (!inspectAnyEquipment && !compatibilityFor(item).allowed) {
      throw FormatException(compatibilityFor(item).reason);
    }
    final code = archetypeCodes.indexOf(appearance!.archetype.id);
    if (code < 0 || code >= item.transforms.length) {
      throw const FormatException('Escudo sin anclaje para el arquetipo.');
    }
    final available = item.transforms[code];
    // A shield IT2 stores its own left-hand bone, even in transform slot 0.
    final socket = available
        .where((a) => a.defined && a.bone < actor.world.length)
        .firstOrNull;
    if (socket == null) {
      throw const FormatException('El escudo no contiene un anclaje válido.');
    }
    final lib = catalog!.library,
        root = directoryName(item.source),
        model = lib.resolve(item.mesh, ['$root/3do', root]),
        texture = lib.resolve(item.texture, ['$root/dds', root]);
    if (model == null || texture == null) {
      throw const FormatException('Falta la malla o textura del escudo.');
    }
    final staged = await makePart(
      MeshData.object(await lib.read(model), model),
      texture,
      opaque: item.alpha != 0,
    );
    if (disposed || revision != _shieldRevision || actor != character) {
      staged.dispose();
      return;
    }
    shield?.dispose();
    shield = staged;
    shieldRecord = item;
    shieldAttachment = socket;
    actor.visual.add(staged.mesh);
    staged.mesh.matrixAutoUpdate = false;
    updateAttachments();
    say('Escudo equipado en la mano secundaria.');
  }

  void refreshIdle() {
    final a = character;
    if (a == null || combat.playerHealth <= 0) return;
    a.idle = mount != null
        ? (a.riderIdle ?? a.normal)
        : flying
        ? a.hover
        : combat.inGuard
        ? (a.guard ?? a.normal)
        : a.normal;
  }

  Future<void> installExtras(ExtraMotionLibrary extras) async {
    extraMotions = extras;
    final a = character, look = appearance;
    if (a != null && look != null && a.normal != null) {
      final p = extras.profiles[look.archetype.id];
      if (p != null &&
          p.matches(look.archetype.id, look.archetype.female, a.normal!)) {
        a.hover = p.hover;
        a.flight = p.flight;
        a.mountedAttacks
          ..clear()
          ..addAll(p.mounted);
      } else {
        a.hover = null;
        a.flight = null;
        a.mountedAttacks.clear();
        report(
          'Suplemento sin vuelo compatible para ${look.archetype.id}; se conservan sus ANI originales.',
        );
      }
    }
    refreshIdle();
    movementTransitions.invalidate();
    changed();
  }

  /// UI actions normally cancel walking before opening tools or changing assets.
  /// Flight mode changes opt out so a held key or click route is not lost.
  Future<void> runUserAction(
    Future<void> Function() action, {
    bool preserveMovement = false,
  }) async {
    if (!preserveMovement) clearMovement();
    await action();
  }

  Future<void> toggleFlight() => requestFlight(!flightEnabled);
  Future<void> requestFlight(bool enabled) async {
    if (enabled) {
      if (wing == null) {
        throw const FormatException('Equipa alas antes de activar el vuelo.');
      }
      if (mount != null) {
        throw const FormatException('Desmonta antes de activar el vuelo.');
      }
      if (character?.hover == null || character?.flight == null) {
        throw const FormatException(
          'Este cuerpo necesita un suplemento de vuelo compatible.',
        );
      }
      if (combat.playerHealth <= 0 || game.jump.airborne) {
        throw const FormatException(
          'El personaje debe estar vivo y terminar el salto para activar el vuelo.',
        );
      }
    }
    setFlightEnabled(enabled);
    _syncWingMotion(
      walkX.abs() + walkZ.abs() > 1e-8 || game.destination != null,
    );
    say(
      enabled
          ? (combat.inGuard
                ? 'Vuelo preparado: se retomará al terminar el combate, sin detener el recorrido.'
                : 'Modo vuelo activado · < para aterrizar.')
          : 'Modo terrestre activado; las alas siguen equipadas.',
    );
  }

  void setFlightEnabled(bool enabled) {
    flightEnabled = enabled;
    refreshIdle();
    movementTransitions.invalidate();
    changed();
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
    if (flying) return mode == GroundMotion.idle ? a.hover : a.flight;
    return switch (mode) {
      GroundMotion.idle => a.idle ?? a.normal,
      GroundMotion.walk => a.walk,
      GroundMotion.run => a.weaponRun ?? a.run,
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
    a.visual.matrix.identity();
    if (mount != null) {
      final vehicle = mount!;
      final saddle =
          vehicle.seat?.position(vehicle.world) ??
          (vehicle.world.isNotEmpty
              ? vehicle.world[math.min(1, vehicle.world.length - 1)]
                    .getTranslation()
              : v.Vector3(0, vehicle.height * .45, 0));
      final pelvis = a.world.isEmpty
          ? v.Vector3.zero()
          : a.world[a.pelvisBone.clamp(0, a.world.length - 1)].getTranslation();
      final q =
          vehicle.seat?.rotation(vehicle.world) ?? v.Quaternion.identity();
      a.visual.matrix.copyFromArray(
        seatedTransform(
          saddle,
          q,
          pelvis,
          height: riderHeight,
          forward: riderForward,
        ).storage,
      );
      a.root.position.y = groundY;
    } else {
      a.root.position.y = groundY + game.jump.height + flightState.height;
    }
    a.visual.matrixWorldNeedsUpdate = true;
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
    if (shield != null &&
        shieldAttachment != null &&
        shieldAttachment!.bone < a.world.length) {
      shield!.mesh.matrix.copyFromArray(
        (a.world[shieldAttachment!.bone] * shieldAttachment!.matrix).storage,
      );
      shield!.mesh.matrixWorldNeedsUpdate = true;
    }
    if (mount != null) {
      mount!.root.position.setValues(x, groundY, z);
      mount!.root.rotation.y = rotation;
    }
    if (wing != null) {
      final bone = a.wingBone;
      final valid =
          bone != null && bone < a.world.length && a.wingReference != null;
      final root = v.Matrix4.compose(
        v.Vector3(x, a.root.position.y, z),
        v.Quaternion.axisAngle(v.Vector3(0, 1, 0), rotation),
        v.Vector3(1, 1, -1),
      );
      final delta = valid
          ? a.world[bone] * a.wingReference!
          : v.Matrix4.identity();
      final local = v.Matrix4.compose(
        v.Vector3(0, wingHeight, wingDepth),
        v.Quaternion.axisAngle(v.Vector3(0, 1, 0), wingYaw),
        v.Vector3.all(wingSize),
      );
      final matrix =
          root * v.Matrix4.fromList(a.visual.matrix.storage) * delta * local;
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
    if (target == 'wing') {
      wingAutoMotion = false;
      _wingMotionPhase = null;
    }
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
    clearImpactParticles();
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
    await prepareImpactParticles();
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
        if (event == 'attack' && combatClips.isNotEmpty) {
          final clips = combatClips;
          c = clips[attackCounter++ % clips.length];
          combat.attackDuration = clips[attackCounter % clips.length].duration;
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
          c = mount != null && event != 'death'
              ? null
              : await firstCompatible(a, candidates);
        }
        if (c != null && a == character) a.play(c, repeat: false);
      }
      if (event == 'death') a.idle = null;
      if (event == 'hit') {
        hitLife = .28;
        unawaited(emitImpact(a));
        lastImpact = who == 'enemy'
            ? 'Impacto −${combat.damage.round()}'
            : 'Recibido −${combat.enemyDamage.round()}';
        if (hitSprite != null) {
          hitSprite!.visible = false;
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
    if (mount != null && combatClips.isEmpty) {
      throw const FormatException(
        'Esta familia no tiene un ataque montado suplementario compatible cargado. Importa el suplemento 0.5 o desmonta.',
      );
    }
    if (mount == null && attackClips.isEmpty) await prepareWeaponMotions();
    if (combatClips.isEmpty) {
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
    if (enemyDistance > combat.range ||
        combat.cooldownRemaining > 0 ||
        !combat.alive) {
      combat.record('Ataque no iniciado: alcance, vida o tiempo de espera.');
      notifyListeners();
      return;
    }
    if (!flightState.grounded && mount == null) {
      flightState.queue(combat.target);
      // Preserve held movement and click-to-move routes while touching down.
      refreshIdle();
      movementTransitions.invalidate();
      say('Descenso rápido de combate…');
      return;
    }
    combat.attack(
      enemyDistance,
      duration: combatClips[attackCounter % combatClips.length].duration,
    );
    notifyListeners();
  }

  double get enemyDistance {
    if (enemy == null || character == null) return double.infinity;
    final dx = enemy!.root.position.x - character!.root.position.x,
        dz = enemy!.root.position.z - character!.root.position.z;
    return math.sqrt(dx * dx + dz * dz);
  }

  void resetCombat() {
    flightState.cancel();
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
    shield?.mesh.material?.wireframe = value;
    notifyListeners();
  }

  void tick(double dt) {
    if (!paused) tickGameplay(dt);
  }

  void orbit(double dx, double dy) {
    yaw -= dx * .006;
    pitch = (pitch + dy * .006).clamp(-1.2, 1.2);
    updateCamera();
  }

  void zoom(double amount) {
    distance = (distance * amount).clamp(.4, game.loaded == null ? 250 : 60);
    updateCamera();
  }

  void updateCamera() {
    if (!ready || view == null) return;
    final a = character;
    final x = (a?.root.position.x ?? 0) + panX,
        z = (a?.root.position.z ?? 0) + panZ,
        y =
            groundY +
            targetY +
            (mount == null
                ? flightState.height
                : (a?.visual.matrix.storage[13] ?? 0));
    view!.camera.position.setValues(
      x + math.sin(yaw) * math.cos(pitch) * distance,
      y + math.sin(pitch) * distance,
      z + math.cos(yaw) * math.cos(pitch) * distance,
    );
    view!.camera.lookAt(t.Vector3(x, y, z));
    game.loaded?.updateVisibility(view!.camera);
    final loaded = game.loaded;
    if (loaded != null) {
      final far = (loaded.drawRadius - distance - 20).clamp(48.0, 280.0),
          fog = view!.scene.fog;
      if (fog is t.Fog) {
        fog.near = far * .55;
        fog.far = far;
      } else {
        view!.scene.fog = t.Fog(loaded.data.fogColor, far * .55, far);
      }
    }
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

  Future<void> setWorld(
    String? path, {
    double? x,
    double? z,
    bool forceReload = false,
  }) => loadWorldScene(path, x: x, z: z, forceReload: forceReload);

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
    shield?.dispose();
    clearImpactParticles();
    effectTexture?.dispose();
    _audio?.dispose();
    super.dispose();
  }
}

Uint8List _decodeTexture(Map<String, Object> args) => Pixels.decode(
  args['bytes'] as Uint8List,
  args['path'] as String,
).png(opaque: args['opaque'] as bool);
