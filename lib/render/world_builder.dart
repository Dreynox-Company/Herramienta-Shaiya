import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:three_js/three_js.dart' as t;
import 'package:vector_math/vector_math_64.dart' as v;
import '../core/formats.dart';
import '../core/world_resources.dart';
import '../core/scene_objects.dart';
import '../data/library.dart';
import '../core/spatial_window.dart';
import 'studio_scene.dart' show RenderPart;
part 'world_stream.dart';

typedef PartFactory =
    Future<RenderPart> Function(MeshData mesh, String texture, {bool opaque});

class LoadedWorld {
  final t.Group root = t.Group();
  final WorldResource data;
  _WorldStream? _stream;
  bool disposed = false;
  int get residentChunks => _stream?._chunks.length ?? 0;
  int get pendingChunks => _stream?.pending ?? 0;
  int get loadedChunks => _stream?.loads ?? 0;
  int get releasedChunks => _stream?.releases ?? 0;
  double get drawRadius => _stream?.window.radius ?? 176;
  Map<String, Object> get streamingStats => {
    'chunks': residentChunks,
    'pending': pendingChunks,
    'loaded': loadedChunks,
    'released': releasedChunks,
    'models': _stream?._models.length ?? 0,
    'drawRadius': drawRadius,
    'collisionGroups': floors.ownedGroups,
    'residentObjects': objectCount,
    'residentTriangles': triangleCount,
  };
  void focus(double x, double z) {
    _stream?.focus(x, z);
  }

  Future<void> ensureAt(double x, double z) async {
    await _stream?.ensureAt(x, z);
  }

  Future<void> settle() async {
    await _stream?.settle();
  }

  bool readyAt(double x, double z) => _stream?.isReady(x, z) ?? true;
  void setDrawRadius(double radius) {
    _stream?.setRadius(radius);
  }

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
    if (!readyAt(x, z)) return null;
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
    if (disposed) return;
    disposed = true;
    _stream?.dispose();
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
    floors.clear();
    animated.clear();
  }
}

class WorldBuilder {
  final Library library;
  final PartFactory makePart;
  final void Function(String) progress;
  final bool Function() cancelled;
  WorldBuilder(this.library, this.makePart, this.progress, this.cancelled);
  Future<LoadedWorld> build(WorldResource resource, {int quality = 1}) async {
    final result = LoadedWorld(resource);
    try {
      final stream = _WorldStream(this, result, quality);
      result._stream = stream;
      await stream.initialize();
      await stream.ensureAt(result.spawn.x, result.spawn.z);
      final y = result.floorAt(result.spawn.x, result.spawn.z, result.spawn.y);
      if (y == null) {
        throw const FormatException(
          'El sector inicial no contiene suelo transitable. Revisa el diagnóstico de recursos.',
        );
      }
      result.spawn.y = y;
      if (cancelled()) {
        throw const FormatException('Selección de mapa sustituida.');
      }
      return result;
    } catch (_) {
      result.dispose();
      rethrow;
    }
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
