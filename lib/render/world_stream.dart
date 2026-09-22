part of 'world_builder.dart';

class _Chunk {
  final CellId key;
  final List<RenderPart> own = [];
  final List<t.InstancedMesh> instances = [];
  final List<String> modelKeys = [], collisionKeys = [];
  int objects = 0, triangles = 0;
  _Chunk(this.key);
}

class _Model {
  final List<RenderPart> parts;
  final List<MeshData> collisions;
  final List<(RenderPart, VertexAnimationPart)> animated;
  int users = 0;
  bool direct;
  _Model(this.parts, this.collisions, this.animated, {this.direct = false});
}

class _WorldStream {
  final WorldBuilder builder;
  final LoadedWorld out;
  final int quality;
  late final SpatialWindow window = SpatialWindow(
    radius: quality == 0
        ? 112
        : quality == 2
        ? 240
        : 176,
  );
  final Map<CellId, _Chunk> _chunks = {};
  final Map<CellId, List<WorldInstance>> _objects = {};
  final Map<CellId, List<int>> _surfaces = {}, _hulls = {};
  final Map<String, _Model> _models = {};
  final Map<String, int> _collisionUsers = {};
  final Set<CellId> _failed = {};
  final Set<String> _modelErrors = {};
  final List<Completer<void>> _waiters = [];
  Future<void>? _pumping;
  double x = 0, z = 0;
  int loads = 0, releases = 0;
  bool closed = false;
  String? lastFailure;
  List<CellId> _wanted = [];
  _WorldStream(this.builder, this.out, this.quality);
  int get pending => _wanted
      .where((c) => !_chunks.containsKey(c) && !_failed.contains(c))
      .length;
  bool valid(CellId c) {
    final w = out.data.terrain;
    if (w.size > 0) {
      return c.x >= 0 &&
          c.z >= 0 &&
          c.x * window.cellSize < w.size &&
          c.z * window.cellSize < w.size;
    }
    return _surfaces.containsKey(c) ||
        _hulls.containsKey(c) ||
        _objects.containsKey(c);
  }

  bool isReady(double px, double pz) => _chunks.containsKey(window.at(px, pz));
  void check() {
    if (closed || out.disposed || builder.cancelled()) {
      throw const FormatException('Streaming cancelado.');
    }
  }

  void note(String value) {
    if (out.diagnostics.length < 300) out.diagnostics.add(value);
  }

  Future<void> initialize() async {
    for (final obj in out.data.terrain.objects) {
      _objects
          .putIfAbsent(window.at(obj.position.x, obj.position.z), () => [])
          .add(obj);
    }
    if (out.data.terrain.size == 0) {
      final layout = out.data.terrain.layout;
      final path = builder.library.resolve(layout, [
        'world/dungeon',
        'world',
      ], uniqueFallback: true);
      if (path == null) {
        throw FormatException('No existe la geometría DG $layout.');
      }
      final dg = DungeonResource.parse(await builder.library.read(path), path);
      check();
      out.dungeon = dg;
      if (out.spawn.length2 < .001) out.spawn = (dg.minimum + dg.maximum) * .5;
      void addBounds(MeshData mesh, int index, Map<CellId, List<int>> cells) {
        var minX = double.infinity,
            maxX = -double.infinity,
            minZ = double.infinity,
            maxZ = -double.infinity;
        for (var k = 0; k < mesh.positions.length; k += 3) {
          minX = math.min(minX, mesh.positions[k]);
          maxX = math.max(maxX, mesh.positions[k]);
          minZ = math.min(minZ, mesh.positions[k + 2]);
          maxZ = math.max(maxZ, mesh.positions[k + 2]);
        }
        if (!minX.isFinite) return;
        final low = window.at(minX, minZ), high = window.at(maxX, maxZ);
        if ((high.x - low.x + 1) * (high.z - low.z + 1) > 16384) {
          throw const FormatException(
            'Superficie DG con extensión fuera de límite.',
          );
        }
        for (var xx = low.x; xx <= high.x; xx++) {
          for (var zz = low.z; zz <= high.z; zz++) {
            cells.putIfAbsent((x: xx, z: zz), () => []).add(index);
          }
        }
      }

      for (var i = 0; i < dg.surfaces.length; i++) {
        addBounds(dg.surfaces[i].mesh, i, _surfaces);
      }
      final hulls = dg.collisions.isEmpty
          ? dg.surfaces.map((s) => s.mesh).toList()
          : dg.collisions;
      for (var i = 0; i < hulls.length; i++) {
        addBounds(hulls[i], i, _hulls);
      }
    }
    x = out.spawn.x;
    z = out.spawn.z;
  }

  void setRadius(double value) {
    window.radius = value.clamp(96.0, 320.0);
    focus(x, z, force: true);
  }

  void focus(double px, double pz, {bool force = false}) {
    if (closed || !px.isFinite || !pz.isFinite) return;
    if (!force &&
        _wanted.isNotEmpty &&
        (x - px).abs() < 12 &&
        (z - pz).abs() < 12) {
      return;
    }
    x = px;
    z = pz;
    _wanted = window.select(x, z, valid: valid);
    final retained = _chunks.keys.toList()
      ..sort(
        (a, b) =>
            window.distance2(b, x, z).compareTo(window.distance2(a, x, z)),
      );
    for (final key in retained) {
      if (!window.retain(key, x, z) ||
          (_chunks.length >= window.maxCells && !_wanted.contains(key))) {
        _drop(_chunks.remove(key)!);
      }
    }
    _kick();
  }

  void _kick() {
    if (closed || _pumping != null) return;
    _pumping = _pump().whenComplete(() {
      _pumping = null;
      _signal();
      if (!closed && pending > 0) _kick();
    });
  }

  void _signal() {
    for (final w in _waiters) {
      if (!w.isCompleted) w.complete();
    }
    _waiters.clear();
  }

  Future<void> ensureAt(double px, double pz) async {
    if (!px.isFinite || !pz.isFinite) {
      throw const FormatException('Coordenadas no finitas.');
    }
    final center = window.at(px, pz);
    if (!valid(center)) {
      throw const FormatException(
        'La posición solicitada queda fuera del escenario.',
      );
    }
    focus(px, pz, force: true);
    // The central neighbourhood provides floor and nearby obstacle coverage
    // before teleport/initial publication. Outer cells continue asynchronously.
    final critical = window.select(
      px,
      pz,
      limit: window.cellSize * .65,
      valid: valid,
    );
    while (!closed && critical.any((c) => !_chunks.containsKey(c))) {
      if (critical.any(_failed.contains)) {
        throw FormatException(
          lastFailure ?? 'No se pudo preparar el suelo cercano.',
        );
      }
      final signal = Completer<void>();
      _waiters.add(signal);
      _kick();
      await signal.future;
      if (builder.cancelled()) throw const FormatException('Carga sustituida.');
    }
    check();
  }

  Future<void> settle() async {
    while (!closed && (pending > 0 || _pumping != null)) {
      final signal = Completer<void>();
      _waiters.add(signal);
      _kick();
      await signal.future;
    }
  }

  Future<void> _pump() async {
    while (!closed) {
      if (builder.cancelled()) {
        dispose();
        return;
      }
      final next = _wanted
          .where((c) => !_chunks.containsKey(c) && !_failed.contains(c))
          .firstOrNull;
      if (next == null) return;
      final chunk = _Chunk(next);
      try {
        await _load(chunk);
        check();
        if (window.retain(next, x, z)) {
          _chunks[next] = chunk;
          loads++;
          out.objectCount += chunk.objects;
          out.triangleCount += chunk.triangles;
        } else {
          _drop(chunk, count: false);
        }
      } catch (e) {
        _drop(chunk, count: false);
        if (closed || builder.cancelled()) return;
        _failed.add(next);
        lastFailure = '$e';
        note('Sector ${next.x},${next.z}: $e');
      }
      _signal();
      builder.progress(
        'Escenario cercano · ${_chunks.length} sectores · ${out.objectCount} objetos · $pending en cola',
      );
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
  }

  Future<void> _load(_Chunk chunk) async {
    if (out.data.terrain.size > 0) {
      await _terrain(chunk);
    } else {
      final dg = out.dungeon!;
      for (final index in _surfaces[chunk.key] ?? <int>[]) {
        final key = '@dg:$index';
        final model = await _acquire(key, () async {
          final s = dg.surfaces[index],
              tex = builder.library.resolve(dg.textures[s.texture], [
                'entity/texture',
                'world/dungeon',
                'world/dungeon/texture',
                'world/texture',
              ], uniqueFallback: true);
          if (tex == null) {
            throw FormatException(
              'Material DG ausente: ${dg.textures[s.texture]}',
            );
          }
          final p = await builder.makePart(s.mesh, tex, opaque: true);
          return _Model([p], [], [], direct: true);
        });
        if (model != null) chunk.modelKeys.add(key);
      }
      final hulls = dg.collisions.isEmpty
          ? dg.surfaces.map((s) => s.mesh).toList()
          : dg.collisions;
      for (final index in _hulls[chunk.key] ?? <int>[]) {
        final key = '@collision:$index', users = _collisionUsers[key] ?? 0;
        if (users == 0) out.floors.add(hulls[index], owner: key);
        _collisionUsers[key] = users + 1;
        chunk.collisionKeys.add(key);
      }
    }
    final grouped = <String, List<WorldInstance>>{};
    for (final obj in _objects[chunk.key] ?? <WorldInstance>[]) {
      grouped.putIfAbsent('${obj.category}/${obj.asset}', () => []).add(obj);
    }
    for (final group in grouped.values) {
      check();
      final first = group.first, category = first.category;
      final path = builder.library.resolve(first.asset, [
        'entity/$category',
        'world/$category',
        'world',
      ]);
      if (path == null) {
        note('Recurso no localizado: ${first.asset} ($category)');
        out.missingObjects += group.length;
        continue;
      }
      final model = await _acquire(path, () => _readModel(path, category));
      if (model == null) {
        out.missingObjects += group.length;
        continue;
      }
      chunk.modelKeys.add(path);
      if (model.parts.isEmpty) continue;
      for (final obj in group) {
        final transform = WorldBuilder.objectMatrix(obj);
        for (final hull in model.collisions) {
          out.floors.add(hull, transform: transform, owner: chunk);
        }
      }
      for (final part in model.parts) {
        final batch = t.InstancedMesh(
          part.mesh.geometry,
          part.mesh.material,
          group.length,
        );
        for (var i = 0; i < group.length; i++) {
          batch.setMatrixAt(
            i,
            t.Matrix4()
              ..copyFromArray(WorldBuilder.objectMatrix(group[i]).storage),
          );
        }
        batch.instanceMatrix?.needsUpdate = true;
        batch.computeBoundingSphere();
        batch.frustumCulled = false;
        out.root.add(batch);
        out.instances.add(batch);
        out.picking.add(batch);
        chunk.instances.add(batch);
        chunk.triangles += part.data.triangles * group.length;
      }
      chunk.objects += group.length;
    }
  }

  Future<_Model?> _acquire(String key, Future<_Model> Function() create) async {
    if (_modelErrors.contains(key)) return null;
    var model = _models[key];
    if (model != null) {
      model.users++;
      return model;
    }
    try {
      model = await create();
      if (closed || builder.cancelled()) {
        for (final p in model.parts) {
          p.dispose();
        }
        check();
      }
      model.users = 1;
      _models[key] = model;
      out.parts.addAll(model.parts);
      out.animated.addAll(model.animated);
      if (model.direct) {
        for (final p in model.parts) {
          out.root.add(p.mesh);
          out.picking.add(p.mesh);
          out.triangleCount += p.data.triangles;
        }
      }
      return model;
    } catch (e) {
      if (closed || builder.cancelled()) rethrow;
      _modelErrors.add(key);
      note('$key: $e');
      return null;
    }
  }

  Future<_Model> _readModel(String path, String category) async {
    final bytes = await builder.library.read(path);
    List<StaticPart> surfaces;
    List<MeshData> collisions = [];
    VertexAnimation? animation;
    if (path.endsWith('.smod')) {
      final data = SmodResource.parse(bytes, path);
      surfaces = data.surfaces;
      collisions = data.collisions;
    } else if (path.endsWith('.vani')) {
      animation = VertexAnimation.parse(bytes, path);
      surfaces = animation.parts.map((p) => p.surface).toList();
    } else if (path.endsWith('.3do')) {
      final r = Bin(bytes, path);
      surfaces = [StaticPart(r.str(), MeshData.object(bytes, path))];
    } else if (path.endsWith('.dg')) {
      final d = DungeonResource.parse(bytes, path);
      surfaces = d.surfaces
          .map((s) => StaticPart(d.textures[s.texture], s.mesh))
          .toList();
      collisions = d.collisions;
    } else {
      throw FormatException('Formato de objeto no admitido: $path');
    }
    final parts = <RenderPart>[],
        sequences = <(RenderPart, VertexAnimationPart)>[];
    try {
      for (var i = 0; i < surfaces.length; i++) {
        check();
        final surface = surfaces[i],
            tex = builder.library.resolve(surface.texture, [
              'entity/texture',
              'entity/texture/detail',
              'entity/$category',
              'entity/$category/texture',
              'world/dungeon',
              'world/dungeon/texture',
              'world/texture',
            ], uniqueFallback: true);
        if (tex == null) {
          note('Material no localizado: ${surface.texture} ($path)');
          continue;
        }
        final part = await builder.makePart(surface.mesh, tex, opaque: false);
        parts.add(part);
        if (animation != null) sequences.add((part, animation.parts[i]));
      }
      return _Model(parts, collisions, sequences);
    } catch (_) {
      for (final p in parts) {
        p.dispose();
      }
      rethrow;
    }
  }

  Future<void> _terrain(_Chunk chunk) async {
    final w = out.data.terrain,
        size = w.size,
        x0 = chunk.key.x * 64,
        z0 = chunk.key.z * 64,
        width = size ~/ 2 + 1;
    final step = quality == 0 ? 4 : 2,
        groups = <int, List<double>>{},
        uvs = <int, List<double>>{};
    if (w.layers.isEmpty) {
      throw const FormatException('Terreno sin definición de materiales.');
    }
    for (var zz = z0; zz < math.min(size, z0 + 64); zz += step) {
      for (var xx = x0; xx < math.min(size, x0 + 64); xx += step) {
        final raw = w.types[(zz ~/ 2) * width + xx ~/ 2],
            layer = raw < w.layers.length ? raw : 0;
        final p = groups.putIfAbsent(layer, () => []),
            uv = uvs.putIfAbsent(layer, () => []),
            repeat = math.max(.05, w.layers[layer].tile.abs());
        for (final c in [
          [0, 0],
          [step, 0],
          [0, step],
          [step, 0],
          [step, step],
          [0, step],
        ]) {
          final x = math.min(size, xx + c[0]).toDouble(),
              z = math.min(size, zz + c[1]).toDouble();
          p.addAll([x, w.heightAt(x, z), z]);
          uv.addAll([x / repeat, z / repeat]);
        }
      }
    }
    for (final entry in groups.entries) {
      check();
      final tex = builder.library.resolve(w.layers[entry.key].texture, [
        'terrain/detail',
        'terrain',
        'terrain/texture',
      ], uniqueFallback: true);
      if (tex == null) {
        throw FormatException(
          'Material de terreno no localizado: ${w.layers[entry.key].texture}',
        );
      }
      final n = entry.value.length ~/ 3, no = Float32List(n * 3);
      for (var i = 1; i < no.length; i += 3) {
        no[i] = 1;
      }
      final data = MeshData(
        Float32List.fromList(entry.value),
        no,
        Float32List.fromList(uvs[entry.key]!),
        Uint16List.fromList(List.generate(n, (i) => i)),
        Uint8List(0),
        Float32List(0),
        [],
        'terrain:${chunk.key}',
      );
      final p = await builder.makePart(data, tex, opaque: true);
      chunk.own.add(p);
      check();
      out.parts.add(p);
      out.root.add(p.mesh);
      out.picking.add(p.mesh);
      chunk.triangles += data.triangles;
    }
  }

  void _release(String key) {
    final model = _models[key];
    if (model == null) return;
    if (--model.users > 0) return;
    _models.remove(key);
    for (final pair in model.animated) {
      out.animated.remove(pair);
    }
    for (final p in model.parts) {
      if (model.direct) {
        out.picking.remove(p.mesh);
        out.triangleCount -= p.data.triangles;
      }
      out.parts.remove(p);
      p.dispose();
    }
  }

  void _drop(_Chunk chunk, {bool count = true}) {
    for (final inst in chunk.instances) {
      out.instances.remove(inst);
      out.picking.remove(inst);
      inst.removeFromParent();
      inst.dispose();
    }
    for (final p in chunk.own) {
      out.parts.remove(p);
      out.picking.remove(p.mesh);
      p.dispose();
    }
    for (final key in chunk.modelKeys) {
      _release(key);
    }
    for (final key in chunk.collisionKeys) {
      final left = (_collisionUsers[key] ?? 1) - 1;
      if (left <= 0) {
        _collisionUsers.remove(key);
        out.floors.removeOwner(key);
      } else {
        _collisionUsers[key] = left;
      }
    }
    out.floors.removeOwner(chunk);
    if (count) {
      out.objectCount -= chunk.objects;
      out.triangleCount -= chunk.triangles;
      releases++;
    }
  }

  void dispose() {
    if (closed) return;
    closed = true;
    for (final c in _chunks.values) {
      _drop(c);
    }
    _chunks.clear();
    _signal();
  }
}
