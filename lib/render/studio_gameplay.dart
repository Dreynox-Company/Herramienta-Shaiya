part of 'studio_scene.dart';

class TextureLease {
  final t.Texture texture;
  int users = 0;
  TextureLease(this.texture);
}

class Opponent {
  final String id;
  final CreatureRecord record;
  final Actor actor;
  Opponent(this.id, this.record, this.actor);
}

class WeaponParticle {
  final t.Sprite sprite;
  final double phase;
  final ParticleRecipe recipe;
  v.Vector3 minimum = v.Vector3.zero(), maximum = v.Vector3.zero();
  int axis = 1;
  WeaponParticle(this.sprite, this.phase, this.recipe, MeshData data) {
    minimum = v.Vector3(double.infinity, double.infinity, double.infinity);
    maximum = v.Vector3(-double.infinity, -double.infinity, -double.infinity);
    for (var i = 0; i < data.positions.length; i += 3) {
      for (var k = 0; k < 3; k++) {
        minimum[k] = math.min(minimum[k], data.positions[i + k]);
        maximum[k] = math.max(maximum[k], data.positions[i + k]);
      }
    }
    final diff = maximum - minimum;
    axis = diff.x > diff.y && diff.x > diff.z
        ? 0
        : diff.y > diff.z
        ? 1
        : 2;
  }
}

class GameplayState {
  final Map<String, Opponent> opponents = {};
  int nextOpponent = 1, opponentRevision = 0, quality = 1, effectRevision = 0;
  LoadedWorld? loaded;
  Destination? destination;
  final List<Destination> route = [];
  final JumpState jump = JumpState();
  ClipData? jumpClip;
  t.Line? selectionRing, destinationRing;
  final List<AudioPlayer> players = [];
  int audioCursor = 0;
  double volume = .65;
  final Map<String, String> audioFiles = {};
  int enchant = 0, element = 0;
  EffectRecipe? recipe;
  final List<WeaponParticle> particles = [];
  final List<t.Texture> particleTextures = [];
  double particleTime = 0;
  bool loadingWorld = false;
  List<EnvironmentFrame> environments = [];
  int environmentIndex = 0;
  String loadStatus = '';
}

extension StudioGameplay on StudioScene {
  String get selectedTargetName => enemyRecord == null
      ? 'Sin objetivo'
      : catalog!.creatureLabel(enemyRecord!);
  int get opponentCount => game.opponents.length;
  double targetDistance(String id) {
    final other = game.opponents[id]?.actor;
    if (other == null || character == null) return double.infinity;
    final dx = other.root.position.x - character!.root.position.x,
        dz = other.root.position.z - character!.root.position.z;
    return math.sqrt(dx * dx + dz * dz);
  }

  Future<void> replaceOpponent(CreatureRecord? record) async {
    if (record == null) {
      clearOpponents();
      return;
    }
    final old = combat.target;
    await addOpponent(record);
    if (game.opponents.containsKey(old)) {
      final actor = game.opponents.remove(old)!;
      combat.removeTarget(old);
      actor.actor.dispose();
    }
  }

  Future<void> addOpponent(CreatureRecord record) async {
    if (game.opponents.length >= 24) {
      throw const FormatException(
        'Máximo 24 oponentes simultáneos. Retira uno antes de añadir otro.',
      );
    }
    final rev = game.opponentRevision, staged = await loadCreature(record);
    if (disposed || rev != game.opponentRevision) {
      staged.dispose();
      return;
    }
    final id = 'mob-${game.nextOpponent++}';
    final a = character;
    final angle = -yaw + game.opponents.length * 1.17;
    final x = (a?.root.position.x ?? 0) + math.cos(angle) * 1.8,
        z = (a?.root.position.z ?? 0) + math.sin(angle) * 1.8;
    final floor =
        game.loaded?.floorAt(originX + x, originZ - z, groundY) ?? groundY;
    staged.root.position.setValues(x, floor, z);
    staged.root.rotation.y = facingYaw(
      (a?.root.position.x ?? 0) - x,
      (a?.root.position.z ?? 0) - z,
    );
    game.opponents[id] = Opponent(id, record, staged);
    combat.addTarget(id);
    view!.scene.add(staged.root);
    selectOpponent(id);
  }

  void selectOpponent(String id) {
    final item = game.opponents[id];
    if (item == null) return;
    enemy = item.actor;
    enemyRecord = item.record;
    combat.selectTarget(id);
    game.destination = null;
    game.route.clear();
    updateSelectionRing();
    say('Objetivo: ${catalog!.creatureLabel(item.record)}');
  }

  void cycleOpponent() {
    final ids = game.opponents.keys.toList();
    if (ids.isEmpty) return;
    selectOpponent(ids[(ids.indexOf(combat.target) + 1) % ids.length]);
  }

  void removeOpponent() {
    final id = combat.target, item = game.opponents.remove(id);
    item?.actor.dispose();
    combat.removeTarget(id);
    if (game.opponents.isNotEmpty) {
      selectOpponent(game.opponents.keys.first);
    } else {
      enemy = null;
      enemyRecord = null;
      game.selectionRing?.visible = false;
      combat.cancelActions();
      changed();
    }
  }

  void clearOpponents() {
    flightState.cancel();
    game.opponentRevision++;
    for (final entry in game.opponents.values) {
      entry.actor.dispose();
      combat.removeTarget(entry.id);
    }
    game.opponents.clear();
    enemy = null;
    enemyRecord = null;
    combat.cancelActions();
    game.selectionRing?.visible = false;
    if (!disposed) changed();
  }

  t.Line ring(int color) {
    final p = <double>[];
    for (var i = 0; i <= 64; i++) {
      final a = i / 64 * math.pi * 2;
      p.addAll([math.cos(a) * .7, .035, math.sin(a) * .7]);
    }
    final geometry = t.BufferGeometry()
      ..setAttributeFromString(
        'position',
        t.Float32BufferAttribute.fromList(p, 3),
      );
    final line = t.Line(
      geometry,
      t.LineBasicMaterial.fromMap({
        'color': color,
        'depthWrite': false,
        'transparent': true,
        'opacity': .9,
      }),
    );
    view!.scene.add(line);
    return line;
  }

  void updateSelectionRing() {
    final a = enemy;
    if (a == null) return;
    game.selectionRing ??= ring(0xffce73);
    game.selectionRing!.visible = true;
    game.selectionRing!.position.setValues(
      a.root.position.x,
      a.root.position.y,
      a.root.position.z,
    );
    final size = (a.height * .4).clamp(.6, 4.0);
    game.selectionRing!.scale.setValues(size, 1, size);
  }

  void clickScene(double x, double y, double width, double height) {
    if (busy ||
        game.loadingWorld ||
        character == null ||
        width <= 0 ||
        height <= 0) {
      return;
    }
    view!.scene.updateMatrixWorld(true);
    view!.camera.updateMatrixWorld(true);
    final ray = t.Raycaster()
      ..setFromCamera(
        t.Vector2(x / width * 2 - 1, 1 - y / height * 2),
        view!.camera,
      );
    Opponent? selected;
    var nearest = double.infinity;
    for (final mob in game.opponents.values) {
      // Bounding spheres are refreshed after CPU skinning before picking.
      for (final p in mob.actor.parts) {
        p.mesh.geometry?.computeBoundingSphere();
      }
      final hits = ray.intersectObject(mob.actor.root, true);
      if (hits.isNotEmpty && hits.first.distance < nearest) {
        nearest = hits.first.distance;
        selected = mob;
      }
    }
    final terrain = game.loaded?.picking ?? <t.Object3D>[];
    final hits = terrain.isEmpty
        ? <t.Intersection>[]
        : ray.intersectObjects(terrain, false);
    if (selected != null &&
        (hits.isEmpty || nearest <= hits.first.distance + .05)) {
      selectOpponent(selected.id);
      return;
    }
    t.Vector3? point;
    if (hits.isNotEmpty) {
      point = hits.first.point;
    } else if (game.loaded == null && ray.ray.direction.y.abs() > 1e-7) {
      final k = (groundY - ray.ray.origin.y) / ray.ray.direction.y;
      if (k > 0) {
        point = ray.ray.origin.clone().add(ray.ray.direction.clone().scale(k));
      }
    }
    if (point == null) return;
    final ground =
        game.loaded?.floorAt(originX + point.x, originZ - point.z, point.y) ??
        groundY;
    final loaded = game.loaded;
    if (loaded != null) {
      final start = v.Vector3(
            originX + character!.root.position.x,
            groundY,
            originZ - character!.root.position.z,
          ),
          goal = v.Vector3(originX + point.x, ground, originZ - point.z);
      final plan = RoutePlanner(
        (x, z, y) => loaded.floorAt(x, z, y),
        (a, b) => loaded.floors.blocks(a, b),
      ).find(start, goal);
      if (plan == null) {
        say('No se encuentra una ruta transitable hasta ese punto.');
        return;
      }
      game.route
        ..clear()
        ..addAll(plan.map((p) => Destination(p.x - originX, originZ - p.z)));
      game.destination = game.route.removeAt(0);
    } else {
      game.route.clear();
      game.destination = Destination(point.x, point.z);
    }
    game.destinationRing ??= ring(0x8ab7ef);
    game.destinationRing!.visible = true;
    game.destinationRing!.scale.setValues(.45, 1, .45);
    game.destinationRing!.position.setValues(point.x, ground + .025, point.z);
    combat.automatic = false;
    movementTransitions.invalidate();
    say(
      'Destino: ${(originX + point.x).toStringAsFixed(1)}, ${(originZ - point.z).toStringAsFixed(1)}',
    );
  }

  Future<void> jump() async {
    if (character == null || busy || game.loadingWorld || sceneCombatLocked) {
      return;
    }
    if (mount != null || flying || !flightState.grounded) {
      throw const FormatException(
        'Desmonta o desactiva el vuelo para saltar a pie.',
      );
    }
    if (game.jumpClip == null) {
      throw const FormatException(
        'Este arquetipo no contiene una animación de salto compatible.',
      );
    }
    if (game.jump.start()) {
      character!.play(game.jumpClip!, repeat: false);
      movementTransitions.invalidate();
      // Jump has no generic ps0032 weapon sound. Do not substitute a hit.
      // Tyros-specific jump WAVs are not valid for an arbitrary character.
    }
  }

  void tickGameplay(double dt) {
    if (disposed) return;
    _frameAccumulator += dt;
    _uiAccumulator += dt;
    if (_frameAccumulator < 1 / 30) return;
    final delta = _frameAccumulator.clamp(0.0, .10);
    _frameAccumulator = 0;
    final actor = character;
    final v3WasLocked = flightV3CombatLock;
    if (_flightV3CombatReturnRemaining > 0) {
      _flightV3CombatReturnRemaining = math.max(
        0,
        _flightV3CombatReturnRemaining - delta,
      );
    }
    flightState.step(
      delta,
      eligible: flightAvailable,
      inCombat: flightCombatLock,
      hoverHeight: hoverOffset,
    );
    if (v3WasLocked &&
        !flightV3CombatLock &&
        flightEnabled &&
        wing != null &&
        mount == null &&
        flightState.grounded &&
        !flightBodyTransitionActive) {
      startFlightV3CombatTakeoff();
    }
    final pending = flightState.pendingTarget;
    if (pending != null &&
        flightState.grounded &&
        !flightBodyTransitionActive) {
      flightState.cancel();
      final selected = combat.target;
      if (game.opponents.containsKey(pending) &&
          targetDistance(pending) <= combat.range &&
          combat.playerHealth > 0 &&
          combatClips.isNotEmpty) {
        combat.selectTarget(pending);
        final targetActor = game.opponents[pending]!.actor;
        if (actor != null) {
          actor.root.rotation.y = facingYaw(
            targetActor.root.position.x - actor.root.position.x,
            targetActor.root.position.z - actor.root.position.z,
          );
        }
        combat.attack(
          targetDistance(pending),
          duration: combatClips[attackCounter % combatClips.length].duration,
        );
        if (game.opponents.containsKey(selected)) combat.selectTarget(selected);
      }
      refreshIdle();
      movementTransitions.invalidate();
    }
    if (actor != null && !game.loadingWorld) {
      game.loaded?.focus(
        originX + actor.root.position.x,
        originZ - actor.root.position.z,
      );
    }
    var direction = cameraRelative(walkX, walkZ, yaw);
    var moving = direction.length2 > 1e-8;
    if (!moving && game.destination != null && actor != null) {
      final destination = game.destination!;
      if (destination.reached(actor.root.position.x, actor.root.position.z)) {
        if (game.route.isNotEmpty) {
          game.destination = game.route.removeAt(0);
        } else {
          game.destination = null;
          game.destinationRing?.visible = false;
        }
      } else {
        direction = destination.delta(
          actor.root.position.x,
          actor.root.position.z,
        )..normalize();
        moving = true;
      }
    }
    final blocked = sceneCombatLocked || game.loadingWorld;
    if (!game.jump.airborne) {
      final transition = movementTransitions.update(
        x: moving ? 1 : 0,
        z: 0,
        running: running || touchRun,
        blocked: blocked,
      );
      if (transition != null) applyLocomotion(transition);
    }
    final desired = movementClip(movementTransitions.requested);
    if (!game.jump.airborne &&
        moving &&
        !blocked &&
        desired != null &&
        actor != null &&
        (actor.clip != desired || !actor.playing || !actor.loop)) {
      applyLocomotion(movementTransitions.requested);
    }
    _syncWingMotion(moving);
    if (actor?.headLook != null) {
      actor!.headTracking = headTracking && combat.playerHealth > 0;
      actor.headLook!.step(
        delta,
        cameraYaw: yaw,
        cameraPitch: pitch,
        bodyYaw: actor.root.rotation.y,
        enabled: actor.headTracking,
      );
    }
    for (final a in [
      character,
      mount,
      wing,
      ...game.opponents.values.map((o) => o.actor),
    ]) {
      a?.tick(delta);
    }
    if (actor != null &&
        moving &&
        !blocked &&
        (game.jump.airborne ||
            ((desired != null && actor.clip == desired ||
                    flightBodyTransitionActive) &&
                actor.playing))) {
      var speed = mount != null
          ? ((running || touchRun) ? 7.0 : 3.5)
          : ((running || touchRun) ? 4.0 : 2.0);
      var step = delta * speed;
      if (game.destination != null && walkX == 0 && walkZ == 0) {
        step = math.min(
          step,
          game.destination!
              .delta(actor.root.position.x, actor.root.position.z)
              .length,
        );
      }
      final x = actor.root.position.x + direction.x * step,
          z = actor.root.position.z + direction.z * step;
      final floor = game.loaded == null
          ? groundY
          : game.loaded!.floorAt(
              originX + x,
              originZ - z,
              groundY + game.jump.height,
            );
      final collision =
          game.loaded?.floors.blocks(
            v.Vector3(
              originX + actor.root.position.x,
              groundY + game.jump.height,
              originZ - actor.root.position.z,
            ),
            v.Vector3(
              originX + x,
              (floor ?? groundY) + game.jump.height,
              originZ - z,
            ),
          ) ??
          false;
      if (floor != null &&
          !collision &&
          (game.jump.airborne || floor - groundY < 1.0)) {
        actor.root.position.x = x;
        actor.root.position.z = z;
        if (game.jump.airborne) {
          game.jump.height = math.max(0, game.jump.height + groundY - floor);
        }
        groundY = floor;
      } else if (game.destination != null) {
        game.destination = null;
        game.route.clear();
        game.destinationRing?.visible = false;
        say(
          'Destino detenido: superficie no transitable o pendiente excesiva.',
        );
      }
      actor.root.rotation.y = facingYaw(direction.x, direction.z);
    }
    if (game.jump.step(delta)) {
      movementTransitions.invalidate();
      if (actor != null) {
        applyLocomotion(
          moving
              ? ((running || touchRun) ? GroundMotion.run : GroundMotion.walk)
              : GroundMotion.idle,
        );
      }
    }
    game.loaded?.animate(delta);
    updateAttachments();
    updateSelectionRing();
    combat.step(delta, enemyDistance);
    if (_lastGuard != combat.inGuard) {
      final wasGuarding = _lastGuard;
      _lastGuard = combat.inGuard;
      if (wasGuarding &&
          !combat.inGuard &&
          !flightV3Compatible &&
          flightEnabled &&
          wing != null &&
          mount == null &&
          flightState.grounded) {
        // Legacy supplemental flight resumes from the original guard timeout.
        // Flight V3 uses its own source-defined 5 s post-combat timer above.
        refreshIdle();
      }
      refreshIdle();
      movementTransitions.invalidate();
      if (!moving &&
          !game.jump.airborne &&
          !sceneCombatLocked &&
          actor?.idle != null) {
        actor!.play(actor.idle!);
      }
    }
    tickWeaponEffect(delta);
    tickImpacts(delta);
    if (hitLife > 0) {
      hitLife -= delta;
      if (hitSprite != null) {
        final size = .065 + .11 * (hitLife / .28).clamp(0.0, 1.0);
        hitSprite!.scale.setValues(size, size, 1);
        hitSprite!.material?.opacity = (hitLife / .28).clamp(0.0, 1.0);
        hitSprite!.visible = false;
      }
    }
    updateCamera();
    if (_uiAccumulator > .15) {
      _uiAccumulator = 0;
      changed();
    }
  }

  Future<void> loadWorldScene(
    String? path, {
    double? x,
    double? z,
    bool forceReload = false,
  }) async {
    // A same-map teleport must not invalidate the live streaming controller.
    if (!forceReload &&
        path != null &&
        path == worldPath &&
        game.loaded != null &&
        x != null &&
        z != null) {
      await teleport(x, z);
      return;
    }
    final revision = ++_worldRevision;
    clearMovement();
    game.jump.reset();
    flightState.reset();
    combat.cancelActions();
    if (path == null) {
      game.loaded?.dispose();
      game.loaded = null;
      game.environments.clear();
      view!.scene.fog = null;
      environment.removeFromParent();
      environment = t.Group();
      view!.scene.add(environment);
      world = null;
      worldPath = null;
      groundY = 0;
      originX = 0;
      originZ = 0;
      character?.root.position.setValues(0, 0, 0);
      await setSky(null);
      repositionOpponents();
      updateAttachments();
      changed();
      return;
    }
    game.loadingWorld = true;
    changed();
    LoadedWorld? staged;
    try {
      final data = await compute<Map<String, Object>, WorldResource>(
        _parseWorldResource,
        {'bytes': await catalog!.library.read(path), 'path': path},
      );
      final sourceLibrary = catalog!.library;
      staged = await WorldBuilder(
        sourceLibrary,
        (mesh, texture, {opaque = false}) =>
            makePartFromLibrary(sourceLibrary, mesh, texture, opaque: opaque),
        (text) {
          game.loadStatus = text;
          status = text;
          if (!disposed) changed();
        },
        () => disposed || revision != _worldRevision,
      ).build(data, quality: game.quality);
      if (disposed || revision != _worldRevision) {
        staged.dispose();
        return;
      }
      final spawn = staged.spawn;
      originX = x ?? spawn.x;
      originZ = z ?? spawn.z;
      await staged.ensureAt(originX, originZ);
      staged.origin(originX, originZ);
      final floor = staged.floorAt(originX, originZ, spawn.y) ?? spawn.y;
      final old = game.loaded;
      game.loaded = staged;
      environment.removeFromParent();
      environment = staged.root;
      view!.scene.add(environment);
      old?.dispose();
      world = data.terrain;
      worldPath = path;
      groundY = floor;
      character?.root.position.setValues(0, groundY, 0);
      game.destination = null;
      game.route.clear();
      game.destinationRing?.visible = false;
      repositionOpponents();
      distance = 8.25;
      pitch = .22;
      targetY = 1.05;
      updateAttachments();
      updateCamera();
      for (final warning in staged.diagnostics.take(50)) {
        report(warning);
      }
      game.environments = [];
      game.environmentIndex = 0;
      final env = catalog!.library.resolve(
        '${baseName(path).replaceFirst('.wld', '')}.env',
        ['world'],
      );
      if (env != null) {
        try {
          game.environments = readEnvironment(
            await catalog!.library.read(env),
            env,
          );
        } catch (e) {
          report('Ambiente: $e');
        }
      }
      final lib = catalog!.library;
      final skyFile =
          lib.resolve(data.sky, ['sky']) ??
          (world!.size > 0
              ? (lib.resolve('sky_a1.bmp', ['sky']) ??
                    catalog!.skies.firstOrNull)
              : null);
      try {
        if (skyFile != null) {
          await setSky(skyFile);
        } else {
          await setSky(null);
        }
      } catch (e) {
        await setSky(null);
        staged.diagnostics.add('Cielo: $e');
        report('El mapa se cargó, pero su cielo no pudo interpretarse: $e');
      }
      if (game.environments.isNotEmpty) {
        final daylight = game.environments.indexWhere(
          (e) => e.start <= 1200 && e.end >= 1200,
        );
        try {
          await setEnvironment(daylight < 0 ? 0 : daylight);
        } catch (e) {
          staged.diagnostics.add('Ambiente: $e');
          report('Ambiente: $e');
        }
      }
      say(
        '${catalog!.names.mapTitle(path)} · ${staged.objectCount} objetos · ${staged.missingObjects} recursos pendientes · ${staged.triangleCount} triángulos',
      );
    } catch (_) {
      if (staged != null && staged != game.loaded) staged.dispose();
      rethrow;
    } finally {
      if (revision == _worldRevision) {
        game.loadingWorld = false;
        if (!disposed) changed();
      }
    }
  }

  void repositionOpponents() {
    var i = 0;
    for (final mob in game.opponents.values) {
      final angle = (i++) * 1.1;
      final x = math.cos(angle) * 1.8, z = math.sin(angle) * 1.8;
      mob.actor.root.position.setValues(
        x,
        game.loaded?.floorAt(originX + x, originZ - z, groundY) ?? groundY,
        z,
      );
    }
    updateSelectionRing();
  }

  Future<void> teleport(double x, double z, {double? expectedY}) async {
    final actor = character, loaded = game.loaded;
    if (actor == null || loaded == null) return;
    clearMovement();
    if (!x.isFinite || !z.isFinite) {
      throw const FormatException('Coordenadas no finitas.');
    }
    final oldX = originX + actor.root.position.x,
        oldZ = originZ - actor.root.position.z;
    game.loadingWorld = true;
    changed();
    try {
      await loaded.ensureAt(x, z);
      if (disposed || loaded != game.loaded || actor != character) return;
      if (loaded.floorAt(x, z, expectedY ?? groundY) == null) {
        await loaded.ensureAt(oldX, oldZ);
        throw const FormatException(
          'No existe suelo transitable en el destino. Se conserva la posición anterior.',
        );
      }
    } catch (_) {
      if (!disposed && loaded == game.loaded) await loaded.ensureAt(oldX, oldZ);
      rethrow;
    } finally {
      if (loaded == game.loaded) {
        game.loadingWorld = false;
        if (!disposed) changed();
      }
    }
    final floor = loaded.floorAt(x, z, expectedY ?? groundY);
    if (floor == null) {
      throw const FormatException(
        'No se encuentra suelo transitable en ese punto.',
      );
    }
    clearMovement();
    game.jump.reset();
    groundY = floor;
    actor.root.position.setValues(
      x - originX,
      floor,
      z == originZ ? 0 : originZ - z,
    );
    updateAttachments();
    updateCamera();
    changed();
  }

  Future<void> visitArea(WorldArea area) async {
    final p = area.center;
    await teleport(p.x, p.z, expectedY: p.y);
  }

  Future<void> setEnvironment(int index) async {
    if (index < 0 || index >= game.environments.length) return;
    game.environmentIndex = index;
    final frame = game.environments[index];
    final file = frame.skies
        .map((s) => catalog!.library.resolve(s, ['sky']))
        .whereType<String>()
        .firstOrNull;
    if (file != null) await setSky(file);
    // Original scene textures contain baked lighting. Avoid multiplying them by
    // unrelated physical lights; environment timing changes sky and fog only.
    if (game.loaded != null) {
      final w = game.loaded!.data;
      final near = w.fogNear > 0 ? w.fogNear : 200.0,
          far = w.fogFar > near ? w.fogFar : 1800.0;
      view!.scene.fog = t.Fog(frame.colors.last, near, far);
    }
    changed();
  }

  Future<void> combatEventFor(String id, String who, String event) async {
    if (!const {'attack', 'hit', 'death'}.contains(event)) return;
    refreshIdle();
    final entry = game.opponents[id];
    if (who == 'player') {
      await _combatEvent(who, event);
      if (event == 'attack') unawaited(weaponSound('attack'));
      if (event == 'hit' || event == 'death') unawaited(characterVoice(event));
    } else if (entry != null) {
      final a = entry.actor,
          key = event == 'attack'
              ? 'Ataque 1'
              : event == 'death'
              ? 'Caída'
              : 'Daño';
      final clip = a.clips[key];
      if (clip != null) a.play(clip, repeat: false);
      if (event == 'death') a.idle = null;
      if (event == 'attack' && character != null) {
        a.root.rotation.y = facingYaw(
          character!.root.position.x - a.root.position.x,
          character!.root.position.z - a.root.position.z,
        );
      }
      final soundSlot = nativeMonSoundSlot(event);
      final original = soundSlot == null
          ? ''
          : entry.record.sounds[soundSlot] ?? '';
      final path = catalog!.library.resolve(original, [
        'sound/monster',
        'sound',
      ], uniqueFallback: true);
      if (path != null) unawaited(playSound(path));
      if (event == 'hit' || event == 'death') {
        hitLife = .28;
        unawaited(emitImpact(a));
        lastImpact =
            '${catalog!.creatureLabel(entry.record)} −${combat.damage.round()}';
        unawaited(weaponSound('hit'));
        if (hitSprite != null) {
          hitSprite!.visible = false;
          hitSprite!.position.setValues(
            a.root.position.x,
            a.root.position.y + a.height * .6,
            a.root.position.z,
          );
        }
      }
    }
  }

  Future<void> weaponSound(String action) async {
    final c = catalog;
    if (!sound || c == null) return;
    final prefix = nativeWeaponSoundPrefix(weaponFamily(weaponRecord), action);
    if (prefix == null) return;
    final available = c.sounds
        .where((p) => baseName(p).toLowerCase().startsWith(prefix))
        .toList();
    if (available.isNotEmpty) {
      await playSound(available[attackCounter % available.length]);
    } else {
      final fallback = c.library.resolve(
        action == 'attack' ? 'ch_att_weaponone001.wav' : 'mob_hit001.wav',
        ['sound'],
      );
      if (fallback != null) await playSound(fallback);
    }
  }

  Future<void> characterVoice(String event) async {
    final c = catalog, actor = character;
    final id = appearance?.archetype.id;
    if (!sound || c == null || actor == null || id == null) return;
    final name = nativeCharacterVoice(id, event);
    if (name == null) return;
    final path = c.library.resolve(name, ['sound']);
    if (path != null && identical(catalog, c) && identical(character, actor)) {
      await playSound(path);
    }
  }

  Future<void> pooledSound(String path) async {
    if (!sound || catalog == null || disposed) return;
    try {
      final source = catalog!.library;
      final sourceRevision = source.revision;
      final cacheKey = '${identityHashCode(source)}|$sourceRevision|$path';
      var file = game.audioFiles[cacheKey];
      if (file == null) {
        final bytes = await source.read(path, limit: 32 * 1024 * 1024),
            dir = await getTemporaryDirectory();
        final safe = baseName(path).replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
        final f = File(
          '${dir.path}/shaiya_${cacheKey.hashCode.toUnsigned(32)}_$safe',
        );
        await f.writeAsBytes(bytes);
        file = f.path;
        game.audioFiles[cacheKey] = file;
      }
      if (disposed ||
          !sound ||
          !identical(catalog?.library, source) ||
          source.revision != sourceRevision) {
        return;
      }
      if (game.players.length < 6) game.players.add(AudioPlayer());
      final player = game.players[game.audioCursor++ % game.players.length];
      await player.setVolume(game.volume);
      await player.play(DeviceFileSource(file));
    } catch (e) {
      report('Audio: $e');
    }
  }

  Future<void> rebuildWeaponEffect() async {
    final revision = ++game.effectRevision;
    for (final p in game.particles) {
      p.sprite.removeFromParent();
      p.sprite.material?.dispose();
    }
    game.particles.clear();
    for (final texture in game.particleTextures) {
      texture.dispose();
    }
    game.particleTextures.clear();
    if (weapon == null || game.enchant == 0 && game.element == 0) return;
    var recipe =
        game.recipe ??
        catalog!.names.weaponEffects
            .where((r) => r.particles.any((p) => p.texture.isNotEmpty))
            .firstOrNull;
    if (recipe == null) return;
    game.recipe = recipe;
    for (final emitter
        in recipe.particles.where((p) => p.texture.isNotEmpty).take(5)) {
      final path = catalog!.library.resolve(emitter.texture, [
        'effect/texture',
        'effect',
        'strip',
      ], uniqueFallback: true);
      if (path == null) {
        report('Textura SEFF no localizada: ${emitter.texture}');
        continue;
      }
      final png = await compute(_decodeTexture, {
        'bytes': await catalog!.library.read(path),
        'path': path,
        'opaque': false,
      });
      final texture = await t.TextureLoader(flipY: false).fromBytes(png);
      if (texture == null) continue;
      if (disposed || revision != game.effectRevision) {
        texture.dispose();
        return;
      }
      game.particleTextures.add(texture);
      final amount = (emitter.count == 0 ? 10 : emitter.count).clamp(4, 48);
      final count = (amount * (.3 + game.enchant / 20)).round().clamp(4, 64);
      for (final owner in [weapon, secondWeapon].whereType<RenderPart>()) {
        for (var i = 0; i < count; i++) {
          final color = game.element == 0
              ? emitter.color
              : <int>[
                  0xffffff,
                  0xf87942,
                  0x6eafff,
                  0x8bec9c,
                  0xcab78c,
                ][game.element];
          final sprite = t.Sprite(
            t.SpriteMaterial.fromMap({
              'map': texture,
              'color': color == 0 ? 0xffffff : color,
              'transparent': true,
              'depthWrite': false,
              'blending': t.AdditiveBlending,
              'opacity': .8,
            }),
          );
          owner.mesh.add(sprite);
          game.particles.add(
            WeaponParticle(sprite, (i + 1) / count, emitter, owner.data),
          );
        }
      }
    }
    changed();
  }

  void tickWeaponEffect(double dt) {
    game.particleTime += dt;
    for (final p in game.particles) {
      final owner = p.sprite.parent == weapon?.mesh ? weapon : secondWeapon;
      if (owner == null) continue;
      final min = p.minimum, max = p.maximum, diff = max - min, axis = p.axis;
      final life =
          (game.particleTime / (p.recipe.lifetime / 1000).clamp(.35, 5) +
              p.phase) %
          1;
      final position = (min + max) * .5;
      position[axis] = min[axis] + diff[axis] * life;
      final radius = .035 + .003 * game.enchant;
      position[(axis + 1) % 3] +=
          math.sin(game.particleTime * 4 + p.phase * 24) * radius;
      position[(axis + 2) % 3] +=
          math.cos(game.particleTime * 4 + p.phase * 24) * radius;
      p.sprite.position.setValues(position.x, position.y, position.z);
      final size =
          (p.recipe.size.abs() * .25).clamp(.04, .2) *
          (1 + game.enchant * .035) *
          math.sin(math.pi * life);
      p.sprite.scale.setValues(size, size, 1);
    }
  }

  void disposeGameplay() {
    game.opponentRevision++;
    game.effectRevision++;
    clearOpponents();
    game.loaded?.dispose();
    game.loaded = null;
    for (final line in [game.selectionRing, game.destinationRing]) {
      line?.removeFromParent();
      line?.geometry?.dispose();
      line?.material?.dispose();
    }
    for (final p in game.particles) {
      p.sprite.removeFromParent();
      p.sprite.material?.dispose();
    }
    for (final texture in game.particleTextures) {
      texture.dispose();
    }
    for (final player in game.players) {
      player.dispose();
    }
  }
}

WorldResource _parseWorldResource(Map<String, Object> value) =>
    WorldResource.parse(value['bytes'] as Uint8List, value['path'] as String);
