import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart' as v;

/// Axis-aligned world-space bounds used by the renderer's CPU visibility gate.
final class RenderAabb {
  final v.Vector3 min;
  final v.Vector3 max;

  RenderAabb(this.min, this.max)
      : assert(min.x <= max.x),
        assert(min.y <= max.y),
        assert(min.z <= max.z);

  factory RenderAabb.fromCenterExtent(v.Vector3 center, v.Vector3 extent) =>
      RenderAabb(center - extent, center + extent);
}

final class FrustumPlane {
  final double x;
  final double y;
  final double z;
  final double w;

  const FrustumPlane._(this.x, this.y, this.z, this.w);

  factory FrustumPlane.normalized(
    double x,
    double y,
    double z,
    double w,
  ) {
    final length = math.sqrt(x * x + y * y + z * z);
    if (length <= 1e-12) {
      return const FrustumPlane._(0, 1, 0, double.infinity);
    }
    return FrustumPlane._(x / length, y / length, z / length, w / length);
  }

  double distanceTo(double px, double py, double pz) =>
      x * px + y * py + z * pz + w;

  bool excludesAabb(RenderAabb box) {
    final px = x >= 0 ? box.max.x : box.min.x;
    final py = y >= 0 ? box.max.y : box.min.y;
    final pz = z >= 0 ? box.max.z : box.min.z;
    return distanceTo(px, py, pz) < 0;
  }
}

/// Six-plane camera frustum extracted from a column-major view-projection
/// matrix. The test is conservative: intersecting boxes remain visible.
final class CameraFrustum {
  final List<FrustumPlane> planes;

  const CameraFrustum._(this.planes);

  factory CameraFrustum.fromViewProjection(v.Matrix4 matrix) {
    final m = matrix.storage;
    FrustumPlane plane(
      double a,
      double b,
      double c,
      double d,
    ) =>
        FrustumPlane.normalized(a, b, c, d);

    return CameraFrustum._(<FrustumPlane>[
      // row3 + row0: left
      plane(m[3] + m[0], m[7] + m[4], m[11] + m[8], m[15] + m[12]),
      // row3 - row0: right
      plane(m[3] - m[0], m[7] - m[4], m[11] - m[8], m[15] - m[12]),
      // row3 + row1: bottom
      plane(m[3] + m[1], m[7] + m[5], m[11] + m[9], m[15] + m[13]),
      // row3 - row1: top
      plane(m[3] - m[1], m[7] - m[5], m[11] - m[9], m[15] - m[13]),
      // row3 + row2: near
      plane(m[3] + m[2], m[7] + m[6], m[11] + m[10], m[15] + m[14]),
      // row3 - row2: far
      plane(m[3] - m[2], m[7] - m[6], m[11] - m[10], m[15] - m[14]),
    ]);
  }

  bool intersectsAabb(RenderAabb box) {
    for (final plane in planes) {
      if (plane.excludesAabb(box)) return false;
    }
    return true;
  }

  List<T> visible<T>(
    Iterable<T> values,
    RenderAabb Function(T value) bounds,
  ) =>
      <T>[
        for (final value in values)
          if (intersectsAabb(bounds(value))) value,
      ];
}
