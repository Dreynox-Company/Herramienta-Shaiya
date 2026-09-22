import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart' as v;

import 'formats.dart';

class WorldCollisionTriangle {
  final v.Vector3 a, b, c;
  final double minX, maxX, minY, maxY, minZ, maxZ;
  final bool blocksHorizontalMotion;

  WorldCollisionTriangle(this.a, this.b, this.c)
      : minX = math.min(a.x, math.min(b.x, c.x)),
        maxX = math.max(a.x, math.max(b.x, c.x)),
        minY = math.min(a.y, math.min(b.y, c.y)),
        maxY = math.max(a.y, math.max(b.y, c.y)),
        minZ = math.min(a.z, math.min(b.z, c.z)),
        maxZ = math.max(a.z, math.max(b.z, c.z)),
        blocksHorizontalMotion = _isBlockingPlane(a, b, c);

  static bool _isBlockingPlane(v.Vector3 a, v.Vector3 b, v.Vector3 c) {
    final ux = b.x - a.x, uy = b.y - a.y, uz = b.z - a.z;
    final vx = c.x - a.x, vy = c.y - a.y, vz = c.z - a.z;
    final nx = uy * vz - uz * vy;
    final ny = uz * vx - ux * vz;
    final nz = ux * vy - uy * vx;
    final horizontal = math.sqrt(nx * nx + nz * nz);
    return horizontal > ny.abs() * .22 && horizontal > 1e-7;
  }

  bool blocksPoint(
    double x,
    double y,
    double z, {
    double radius = .34,
    double height = 1.7,
  }) {
    if (!blocksHorizontalMotion) return false;
    if (y + height < minY || y > maxY) return false;
    if (x + radius < minX ||
        x - radius > maxX ||
        z + radius < minZ ||
        z - radius > maxZ) {
      return false;
    }

    if (_pointInTriangleXZ(x, z, a, b, c)) return true;
    final radius2 = radius * radius;
    return _distanceToSegmentXZ2(x, z, a, b) <= radius2 ||
        _distanceToSegmentXZ2(x, z, b, c) <= radius2 ||
        _distanceToSegmentXZ2(x, z, c, a) <= radius2;
  }
}

class WorldCollisionField {
  static const double cellSize = 4;
  final List<WorldCollisionTriangle> triangles;
  final Map<int, List<WorldCollisionTriangle>> _cells = {};

  WorldCollisionField(Iterable<WorldCollisionTriangle> source)
      : triangles = List.unmodifiable(source) {
    for (final triangle in triangles) {
      if (!triangle.blocksHorizontalMotion) continue;
      final minCellX = (triangle.minX / cellSize).floor();
      final maxCellX = (triangle.maxX / cellSize).floor();
      final minCellZ = (triangle.minZ / cellSize).floor();
      final maxCellZ = (triangle.maxZ / cellSize).floor();
      for (var x = minCellX; x <= maxCellX; x++) {
        for (var z = minCellZ; z <= maxCellZ; z++) {
          (_cells[_key(x, z)] ??= <WorldCollisionTriangle>[]).add(triangle);
        }
      }
    }
  }

  bool get isEmpty => triangles.isEmpty;

  bool blocks(
    double x,
    double y,
    double z, {
    double radius = .34,
    double height = 1.7,
  }) {
    final minCellX = ((x - radius) / cellSize).floor();
    final maxCellX = ((x + radius) / cellSize).floor();
    final minCellZ = ((z - radius) / cellSize).floor();
    final maxCellZ = ((z + radius) / cellSize).floor();
    final visited = <WorldCollisionTriangle>{};
    for (var cx = minCellX; cx <= maxCellX; cx++) {
      for (var cz = minCellZ; cz <= maxCellZ; cz++) {
        for (final triangle
            in _cells[_key(cx, cz)] ?? const <WorldCollisionTriangle>[]) {
          if (!visited.add(triangle)) continue;
          if (triangle.blocksPoint(
            x,
            y,
            z,
            radius: radius,
            height: height,
          )) {
            return true;
          }
        }
      }
    }
    return false;
  }

  bool allowsMove({
    required double fromX,
    required double fromY,
    required double fromZ,
    required double toX,
    required double toY,
    required double toZ,
    double radius = .34,
    double height = 1.7,
  }) {
    final dx = toX - fromX, dz = toZ - fromZ;
    final distance = math.sqrt(dx * dx + dz * dz);
    final stepLength = math.max(.08, radius * .65);
    final steps = math.max(1, (distance / stepLength).ceil());
    for (var i = 1; i <= steps; i++) {
      final t = i / steps;
      if (blocks(
        fromX + dx * t,
        fromY + (toY - fromY) * t,
        fromZ + dz * t,
        radius: radius,
        height: height,
      )) {
        return false;
      }
    }
    return true;
  }

  static int _key(int x, int z) =>
      ((x & 0xffffffff) << 32) ^ (z & 0xffffffff);
}

List<WorldCollisionTriangle> transformSmodCollisions(
  List<SmodCollisionMesh> meshes,
  v.Matrix4 matrix,
) {
  final out = <WorldCollisionTriangle>[];
  for (final mesh in meshes) {
    final transformed = mesh.vertices
        .map((point) => _transformPoint(matrix, point))
        .toList(growable: false);
    for (var i = 0; i + 2 < mesh.indices.length; i += 3) {
      out.add(WorldCollisionTriangle(
        transformed[mesh.indices[i]],
        transformed[mesh.indices[i + 1]],
        transformed[mesh.indices[i + 2]],
      ));
    }
  }
  return out;
}

v.Vector3 _transformPoint(v.Matrix4 matrix, v.Vector3 point) {
  final s = matrix.storage;
  return v.Vector3(
    s[0] * point.x + s[4] * point.y + s[8] * point.z + s[12],
    s[1] * point.x + s[5] * point.y + s[9] * point.z + s[13],
    s[2] * point.x + s[6] * point.y + s[10] * point.z + s[14],
  );
}

bool _pointInTriangleXZ(
  double x,
  double z,
  v.Vector3 a,
  v.Vector3 b,
  v.Vector3 c,
) {
  final v0x = c.x - a.x, v0z = c.z - a.z;
  final v1x = b.x - a.x, v1z = b.z - a.z;
  final v2x = x - a.x, v2z = z - a.z;
  final dot00 = v0x * v0x + v0z * v0z;
  final dot01 = v0x * v1x + v0z * v1z;
  final dot02 = v0x * v2x + v0z * v2z;
  final dot11 = v1x * v1x + v1z * v1z;
  final dot12 = v1x * v2x + v1z * v2z;
  final denom = dot00 * dot11 - dot01 * dot01;
  if (denom.abs() < 1e-9) return false;
  final inv = 1 / denom;
  final u = (dot11 * dot02 - dot01 * dot12) * inv;
  final w = (dot00 * dot12 - dot01 * dot02) * inv;
  return u >= 0 && w >= 0 && u + w <= 1;
}

double _distanceToSegmentXZ2(
  double x,
  double z,
  v.Vector3 a,
  v.Vector3 b,
) {
  final dx = b.x - a.x, dz = b.z - a.z;
  final length2 = dx * dx + dz * dz;
  if (length2 < 1e-12) {
    final px = x - a.x, pz = z - a.z;
    return px * px + pz * pz;
  }
  final t = (((x - a.x) * dx + (z - a.z) * dz) / length2).clamp(
    0.0,
    1.0,
  );
  final px = x - (a.x + dx * t);
  final pz = z - (a.z + dz * t);
  return px * px + pz * pz;
}
