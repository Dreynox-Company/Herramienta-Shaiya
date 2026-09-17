import 'dart:math' as math;
import 'dart:typed_data';
import 'package:three_js/three_js.dart' as t;
import 'package:vector_math/vector_math_64.dart' as v;
import '../core/formats.dart';
import '../core/world_resources.dart';
import '../core/scene_objects.dart';
import '../data/library.dart';
import 'studio_scene.dart' show RenderPart;

typedef PartFactory =
    Future<RenderPart> Function(MeshData mesh, String texture, {bool opaque});

class LoadedWorld {
  final t.Group root = t.Group();
  final WorldResource data;
  final List<RenderPart> parts = [];
  final List<t.InstancedMesh> instances = [];
  final List<(RenderPart, VertexAnimationPart)> animated = [];
  double animationTime = 0;
  void animate(double dt) {
    animationTime += dt;
    for (final pair in animated) {
      final part = pair.$1,
          sequence = pair.$2,
          time = animationTime * 30,
          frame = time.floor() % sequence.frames.length,
          next = (frame + 1) % sequence.frames.length,
          blend = time - time.floor();
      final a = sequence.frames[frame],
          b = sequence.frames[next],
          u = sequence.uvFrames[frame];
      for (var i = 0; i < part.data.vertices; i++) {
        part.position.setXYZ(
          i,
          a[i * 3] * (1 - blend) + b[i * 3] * blend,
          a[i * 3 + 1] * (1 - blend) + b[i * 3 + 1] * blend,
          a[i * 3 + 2] * (1 - blend) + b[i * 3 + 2] * blend,
        );
        part.mesh.geometry!.attributes['uv'].setXY(i, u[i * 2], u[i * 2 + 1]);
      }
      part.position.needsUpdate = true;
      part.mesh.geometry!.attributes['uv'].needsUpdate = true;
    }
  }

  final List<t.Object3D> picking = [];
  final SurfaceIndex floors = SurfaceIndex();
  final List<String> diagnostics = [];
  DungeonResource? dungeon;
  late v.Vector3 spawn;
  int objectCount = 0, missingObjects = 0, triangleCount = 0;
  final t.Frustum _frustum = t.Frustum();
  final t.Matrix4 _projection = t.Matrix4();
  final t.BoundingSphere _sphere = t.BoundingSphere();
  void updateVisibility(t.Camera camera) {
    camera.updateMatrixWorld(true);
    root.updateMatrixWorld(true);
    _projection.multiply2(camera.projectionMatrix, camera.matrixWorldInverse);
    _frustum.setFromMatrix(_projection);
    for (final batch in instances) {
      final bounds = batch.boundingSphere;
      if (bounds != null) {
        _sphere.setFrom(bounds).applyMatrix4(batch.matrixWorld);
        batch.visible = _frustum.intersectsSphere(_sphere);
      }
    }
  }

  LoadedWorld(this.data) {
    root.scale.z = -1;
    spawn = data.spawn();
  }
  void origin(double x, double z) {
    root.position.setValues(-x, 0, z);
    root.updateMatrixWorld(true);
  }

  double? floorAt(double x, double z, double current) {
    if (data.terrain.size > 0) {
      if (x < 0 || z < 0 || x > data.terrain.size || z > data.terrain.size) {
        return null;
      }
      final ground = data.terrain.heightAt(x, z),
          surface = floors.floor(x, z, current, maxRise: .8);
      return surface == null ? ground : math.max(ground, surface);
    }
    return floors.floor(x, z, current, maxRise: 1.2);
  }

  void dispose() {
    root.removeFromParent();
    for (final instance in instances) {
      instance.removeFromParent();
      instance.dispose();
    }
    for (final p in parts) {
      p.dispose();
    }
    parts.clear();
    instances.clear();
    picking.clear();
  }
}

class WorldBuilder {
  final Library library;
  final PartFactory makePart;
  final void Function(String) progress;
  final bool Function() cancelled;
  WorldBuilder(this.library, this.makePart, this.progress, this.cancelled);
  void check() {
    if (cancelled()) {
      throw const FormatException(
        'Carga de mapa cancelada por una selección más reciente.',
      );
    }
  }

  Future<LoadedWorld> build(WorldResource resource, {int quality = 1}) async {
    final result = LoadedWorld(resource);
    try {
      if (resource.terrain.size > 0) {
        await _terrain(result, quality);
      } else {
        await _dungeon(result, resource.terrain.layout);
      }
      check();
      final grouped = <String, List<WorldInstance>>{};
      for (final object in resource.terrain.objects) {
        grouped
            .putIfAbsent('${object.category}/${object.asset}', () => [])
            .add(object);
      }
      var index = 0;
      for (final group in grouped.values) {
        check();
        final first = group.first, category = first.category;
        progress(
          'Cargando escenario: ${++index}/${grouped.length} modelos · ${result.objectCount} objetos',
        );
        final model = library.resolve(first.asset, [
          'entity/$category',
          'world/$category',
          'world',
        ]);
        if (model == null) {
          result.missingObjects += group.length;
          result.diagnostics.add('No existe ${first.asset} ($category).');
          continue;
        }
        try {
          List<StaticPart> surfaces;
          List<MeshData> collisions = [];
          VertexAnimation? animation;
          if (model.endsWith('.smod')) {
            final data = SmodResource.parse(await library.read(model), model);
            surfaces = data.surfaces;
            collisions = data.collisions;
          } else if (model.endsWith('.vani')) {
            animation = VertexAnimation.parse(await library.read(model), model);
            surfaces = animation.parts.map((p) => p.surface).toList();
          } else if (model.endsWith('.3do')) {
            final b = await library.read(model), r = Bin(b, model);
            final tex = r.str();
            surfaces = [StaticPart(tex, MeshData.object(b, model))];
          } else if (model.endsWith('.dg')) {
            final d = DungeonResource.parse(await library.read(model), model);
            surfaces = d.surfaces
                .map((s) => StaticPart(d.textures[s.texture], s.mesh))
                .toList();
          } else {
            result.missingObjects += group.length;
            result.diagnostics.add('Formato de objeto no interpretado: $model');
            continue;
          }
          for (final obj in group) {
            final matrix = objectMatrix(obj);
            for (final hull in collisions) {
              result.floors.add(hull, transform: matrix);
            }
          }
          var visibleParts = 0;
          for (final surface in surfaces) {
            final tex = library.resolve(surface.texture, [
              'entity/texture',
              'entity/texture/detail',
              'entity/$category',
              'entity/$category/texture',
              'world/dungeon',
              'world/dungeon/texture',
              'world/texture',
            ], uniqueFallback: true);
            if (tex == null) {
              result.diagnostics.add(
                'Textura no localizada: ${surface.texture} en $model',
              );
              continue;
            }
            final prototype = await makePart(surface.mesh, tex, opaque: false);
            result.parts.add(prototype);
            if (animation != null) {
              final sequence = animation.parts.firstWhere(
                (p) => identical(p.surface, surface),
              );
              result.animated.add((prototype, sequence));
            }
            final cells = <String, List<WorldInstance>>{};
            for (final obj in group) {
              cells
                  .putIfAbsent(
                    '${obj.position.x ~/ 128}:${obj.position.z ~/ 128}',
                    () => [],
                  )
                  .add(obj);
            }
            for (final batch in cells.values) {
              final instanced = t.InstancedMesh(
                prototype.mesh.geometry,
                prototype.mesh.material,
                batch.length,
              );
              for (var i = 0; i < batch.length; i++) {
                final matrix = objectMatrix(batch[i]);
                instanced.setMatrixAt(
                  i,
                  t.Matrix4()..copyFromArray(matrix.storage),
                );
              }
              instanced.instanceMatrix?.needsUpdate = true;
              instanced.computeBoundingSphere();
              instanced.frustumCulled = false;
              result.root.add(instanced);
              result.instances.add(instanced);
              result.picking.add(instanced);
            }
            result.triangleCount += surface.mesh.triangles * group.length;
            visibleParts++;
          }
          if (visibleParts > 0) {
            result.objectCount += group.length;
          } else {
            result.missingObjects += group.length;
          }
        } catch (e) {
          result.missingObjects += group.length;
          result.diagnostics.add('$model: $e');
        }
        if (index % 6 == 0) await Future<void>.delayed(Duration.zero);
      }
      check();
      return result;
    } catch (_) {
      result.dispose();
      rethrow;
    }
  }

  Future<void> _terrain(LoadedWorld out, int quality) async {
    final world = out.data.terrain,
        size = world.size,
        baseStep = quality == 2
            ? 2
            : quality == 0
            ? 8
            : (size > 1536 ? 8 : 4);
    // Every tile is present. Only its sampling density changes with the quality.
    const tileSize = 128;
    final width = size ~/ 2 + 1;
    for (var z0 = 0; z0 < size; z0 += tileSize) {
      for (var x0 = 0; x0 < size; x0 += tileSize) {
        check();
        final groups = <int, List<double>>{}, uvs = <int, List<double>>{};
        final close =
            (x0 + 64 - out.spawn.x).abs() < 180 &&
            (z0 + 64 - out.spawn.z).abs() < 180;
        final step = close ? math.min(baseStep, 2) : baseStep;
        for (var z = z0; z < math.min(size, z0 + tileSize); z += step) {
          for (var x = x0; x < math.min(size, x0 + tileSize); x += step) {
            final raw = world.types[(z ~/ 2) * width + x ~/ 2],
                layer = raw < world.layers.length ? raw : 0;
            if (world.layers.isEmpty) continue;
            final p = groups.putIfAbsent(layer, () => []),
                uv = uvs.putIfAbsent(layer, () => []),
                repeat = math.max(.05, world.layers[layer].tile.abs());
            for (final corner in [
              [0, 0],
              [step, 0],
              [0, step],
              [step, 0],
              [step, step],
              [0, step],
            ]) {
              final xx = math.min(size, x + corner[0]).toDouble(),
                  zz = math.min(size, z + corner[1]).toDouble();
              p.addAll([xx, world.heightAt(xx, zz), zz]);
              uv.addAll([xx / repeat, zz / repeat]);
            }
          }
        }
        for (final entry in groups.entries) {
          final tex = library.resolve(world.layers[entry.key].texture, [
            'terrain/detail',
            'terrain',
            'terrain/texture',
          ], uniqueFallback: true);
          if (tex == null) {
            out.diagnostics.add(
              'Terreno sin textura: ${world.layers[entry.key].texture}',
            );
            continue;
          }
          // Keep each index buffer within the format's 16-bit limit.
          final values = entry.value, uv = uvs[entry.key]!;
          for (var begin = 0; begin < values.length ~/ 3; begin += 60000) {
            final n = math.min(60000, values.length ~/ 3 - begin);
            final normals = Float32List(n * 3);
            for (var k = 1; k < normals.length; k += 3) {
              normals[k] = 1;
            }
            final mesh = MeshData(
              Float32List.fromList(values.sublist(begin * 3, (begin + n) * 3)),
              normals,
              Float32List.fromList(uv.sublist(begin * 2, (begin + n) * 2)),
              Uint16List.fromList(List.generate(n, (i) => i)),
              Uint8List(0),
              Float32List(0),
              [],
              'terrain',
            );
            final part = await makePart(mesh, tex, opaque: true);
            part.mesh.frustumCulled = true;
            out.parts.add(part);
            out.root.add(part.mesh);
            out.picking.add(part.mesh);
            out.triangleCount += mesh.triangles;
          }
        }
        progress('Construyendo terreno completo · $x0, $z0 / $size');
        await Future<void>.delayed(Duration.zero);
      }
    }
    if (out.parts.isEmpty) {
      throw const FormatException(
        'No se pudo interpretar ninguna superficie del terreno.',
      );
    }
  }

  Future<void> _dungeon(LoadedWorld out, String layout) async {
    final path = library.resolve(layout, [
      'world/dungeon',
      'world',
    ], uniqueFallback: true);
    if (path == null) {
      throw FormatException('La geometría de mazmorra no existe: $layout');
    }
    final dungeon = DungeonResource.parse(await library.read(path), path);
    out.dungeon = dungeon;
    if (out.spawn.length2 < .001) {
      out.spawn = (dungeon.minimum + dungeon.maximum) * .5;
    }
    var index = 0;
    for (final surface in dungeon.surfaces) {
      check();
      final tex = library.resolve(dungeon.textures[surface.texture], [
        'entity/texture',
        'world/dungeon',
        'world/dungeon/texture',
        'world/texture',
      ], uniqueFallback: true);
      if (tex == null) {
        out.diagnostics.add(
          'Material de mazmorra no encontrado: ${dungeon.textures[surface.texture]}',
        );
        continue;
      }
      final part = await makePart(surface.mesh, tex, opaque: true);
      part.mesh.frustumCulled = true;
      out.parts.add(part);
      out.root.add(part.mesh);
      out.picking.add(part.mesh);
      out.triangleCount += surface.mesh.triangles;
      if (++index % 10 == 0) {
        progress('Mazmorra · $index/${dungeon.surfaces.length} superficies');
        await Future<void>.delayed(Duration.zero);
      }
    }
    for (final mesh
        in dungeon.collisions.isEmpty
            ? dungeon.surfaces.map((s) => s.mesh)
            : dungeon.collisions) {
      out.floors.add(mesh);
    }
    final y = out.floors.floor(
      out.spawn.x,
      out.spawn.z,
      out.spawn.y,
      maxRise: 1,
    );
    if (y != null) out.spawn.y = y;
  }

  static v.Matrix4 objectMatrix(WorldInstance obj) {
    var forward = obj.forward.clone(), up = obj.up.clone();
    if (forward.length2 < 1e-8) forward = v.Vector3(0, 0, 1);
    if (up.length2 < 1e-8) up = v.Vector3(0, 1, 0);
    forward.normalize();
    up.normalize();
    var right = up.cross(forward);
    if (right.length2 < 1e-8) right = v.Vector3(1, 0, 0);
    right.normalize();
    up = forward.cross(right)..normalize();
    return v.Matrix4.columns(
      v.Vector4(right.x, right.y, right.z, 0),
      v.Vector4(up.x, up.y, up.z, 0),
      v.Vector4(forward.x, forward.y, forward.z, 0),
      v.Vector4(obj.position.x, obj.position.y, obj.position.z, 1),
    );
  }
}
