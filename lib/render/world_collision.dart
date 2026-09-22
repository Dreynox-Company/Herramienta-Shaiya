import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart' as v;

import '../core/formats.dart';

class WorldCollisionTriangle {
  final double ax, ay, az;
  final double bx, by, bz;
  final double cx, cy, cz;
  final double minX, maxX, minY, maxY, minZ, maxZ;
  final double normalY;

  const WorldCollisionTriangle._(
    this.ax,
    this.ay,
    this.az,
    this.bx,
    this.by,
    this.bz,
    this.cx,
    this.cy,
    this.cz,
    this.minX,
    this.maxX,
    this.minY,
    this.maxY,
    this.minZ,
    this.maxZ,
    this.normalY,
  );

  factory WorldCollisionTriangle.fromPoints(
    v.Vector3 a,
    v.Vector3 b,
    v.Vector3 c,
  ) {
    final abx = b.x - a.x;
    final aby = b.y - a.y;
    final abz = b.z - a.z;
    final acx = c.x - a.x;
    final acy = c.y - a.y;
    final acz = c.z - a.z;
    final nx = aby * acz - abz * acy;
    final ny = abz * acx - abx * acz;
    final nz = abx * acy - aby * acx;
    final length = math.sqrt(nx * nx + ny * ny + nz * nz);
    final normalY = length <= 1e-9 ? 1.0 : ny / length;
    return WorldCollisionTriangle._(
      a.x,
      a.y,
      a.z,
      b.x,
      b.y,
      b.z,
      c.x,
      c.y,
      c.z,
      math.min(a.x, math.min(b.x, c.x)),
      math.max(a.x, math.max(b.x, c.x)),
      math.min(a.y, math.min(b.y, c.y)),
      math.max(a.y, math.max(b.y, c.y)),
      math.min(a.z, math.min(b.z, c.z)),
      math.max(a.z, math.max(b.z, c.z)),
      normalY,
    );
  }

  bool get blocksHorizontalMovement => normalY.abs() < .72;
}

class WorldCollisionIndex {
  final List<WorldCollisionTriangle> _triangles = <WorldCollisionTriangle>[];

  int get triangleCount => _triangles.length;
  bool get isEmpty => _triangles.isEmpty;

  void clear() => _triangles.clear();

  void replaceWith(WorldCollisionIndex other) {
    _triangles
      ..clear()
      ..addAll(other._triangles);
  }

  void addSmod(SmodData smod, v.Matrix4 transform) {
    for (final mesh in smod.collisions) {
      addMesh(mesh, transform);
    }
  }

  void addMesh(SmodCollisionMesh mesh, v.Matrix4 transform) {
    final storage = transform.storage;

    v.Vector3 apply(v.Vector3 point) => v.Vector3(
          storage[0] * point.x +
              storage[4] * point.y +
              storage[8] * point.z +
              storage[12],
          storage[1] * point.x +
              storage[5] * point.y +
              storage[9] * point.z +
              storage[13],
          storage[2] * point.x +
              storage[6] * point.y +
              storage[10] * point.z +
              storage[14],
        );

    final transformed = mesh.vertices.map(apply).toList(growable: false);
    for (var i = 0; i + 2 < mesh.indices.length; i += 3) {
      final a = transformed[mesh.indices[i]];
      final b = transformed[mesh.indices[i + 1]];
      final c = transformed[mesh.indices[i + 2]];
      final triangle = WorldCollisionTriangle.fromPoints(a, b, c);
      if (triangle.blocksHorizontalMovement) {
        _triangles.add(triangle);
      }
    }
  }

  bool blocksPosition(
    double x,
    double groundY,
    double z, {
    double radius = .32,
    double height = 1.65,
  }) {
    if (_triangles.isEmpty) return false;
    final bottom = groundY + .08;
    final top = groundY + math.max(.5, height);
    final radiusSquared = radius * radius;

    for (final triangle in _triangles) {
      if (triangle.maxY < bottom || triangle.minY > top) continue;
      if (x < triangle.minX - radius ||
          x > triangle.maxX + radius ||
          z < triangle.minZ - radius ||
          z > triangle.maxZ + radius) {
        continue;
      }

      if (_pointInsideProjectedTriangle(x, z, triangle) ||
          _segmentDistanceSquared(
                x,
                z,
                triangle.ax,
                triangle.az,
                triangle.bx,
                triangle.bz,
              ) <=
              radiusSquared ||
          _segmentDistanceSquared(
                x,
                z,
                triangle.bx,
                triangle.bz,
                triangle.cx,
                triangle.cz,
              ) <=
              radiusSquared ||
          _segmentDistanceSquared(
                x,
                z,
                triangle.cx,
                triangle.cz,
                triangle.ax,
                triangle.az,
              ) <=
              radiusSquared) {
        return true;
      }
    }
    return false;
  }
}

bool _pointInsideProjectedTriangle(
  double x,
  double z,
  WorldCollisionTriangle triangle,
) {
  double cross(
    double ax,
    double az,
    double bx,
    double bz,
    double px,
    double pz,
  ) =>
      (bx - ax) * (pz - az) - (bz - az) * (px - ax);

  final area = cross(
    triangle.ax,
    triangle.az,
    triangle.bx,
    triangle.bz,
    triangle.cx,
    triangle.cz,
  );
  if (area.abs() < 1e-8) return false;

  final ab = cross(
    triangle.ax,
    triangle.az,
    triangle.bx,
    triangle.bz,
    x,
    z,
  );
  final bc = cross(
    triangle.bx,
    triangle.bz,
    triangle.cx,
    triangle.cz,
    x,
    z,
  );
  final ca = cross(
    triangle.cx,
    triangle.cz,
    triangle.ax,
    triangle.az,
    x,
    z,
  );
  const epsilon = 1e-8;
  final hasNegative = ab < -epsilon || bc < -epsilon || ca < -epsilon;
  final hasPositive = ab > epsilon || bc > epsilon || ca > epsilon;
  return !(hasNegative && hasPositive);
}

double _segmentDistanceSquared(
  double px,
  double pz,
  double ax,
  double az,
  double bx,
  double bz,
) {
  final dx = bx - ax;
  final dz = bz - az;
  final lengthSquared = dx * dx + dz * dz;
  if (lengthSquared <= 1e-12) {
    final ex = px - ax;
    final ez = pz - az;
    return ex * ex + ez * ez;
  }
  final t = (((px - ax) * dx + (pz - az) * dz) / lengthSquared)
      .clamp(0.0, 1.0)
      .toDouble();
  final qx = ax + dx * t;
  final qz = az + dz * t;
  final ex = px - qx;
  final ez = pz - qz;
  return ex * ex + ez * ez;
}
