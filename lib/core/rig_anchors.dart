import 'dart:math' as math;
import 'package:vector_math/vector_math_64.dart' as v;
import 'formats.dart';

/// A point on an original skinned triangle. Evaluating the same barycentric
/// coordinates follows deformation without sampling a bounding-box height.
class SurfaceAnchor {
  final MeshData mesh;
  final List<int> vertices;
  final List<double> barycentric;
  final int bone;
  final v.Quaternion referenceRotation;
  SurfaceAnchor(
    this.mesh,
    this.vertices,
    this.barycentric,
    this.bone,
    this.referenceRotation,
  );

  v.Vector3 position(List<v.Matrix4> pose) {
    final out = v.Vector3.zero();
    for (var i = 0; i < 3; i++) {
      out.add(skinnedPoint(mesh, vertices[i], pose) * barycentric[i]);
    }
    return out;
  }

  v.Quaternion rotation(List<v.Matrix4> pose) {
    if (bone < 0 || bone >= pose.length) return v.Quaternion.identity();
    final q = matrixRotation(pose[bone]);
    final inverse = referenceRotation.conjugated();
    return (q * inverse)..normalize();
  }

  /// Finds an upward surface around the central trunk, not the tallest wing,
  /// horn or head of a mount. Unusual mounts retain manual calibration controls.
  static SurfaceAnchor? locate(List<MeshData> parts, ClipData reference) {
    if (parts.isEmpty || reference.bones.isEmpty) return null;
    final pose = reference.pose(0);
    final points = <v.Vector3>[];
    for (final part in parts) {
      for (var i = 0; i < part.vertices; i++) {
        points.add(skinnedPoint(part, i, pose));
      }
    }
    if (points.isEmpty) return null;
    final lo = points.first.clone(), hi = lo.clone();
    for (final p in points) {
      for (var k = 0; k < 3; k++) {
        lo[k] = math.min(lo[k], p[k]);
        hi[k] = math.max(hi[k], p[k]);
      }
    }
    final span = hi - lo;
    if (span.y < .02 || span.z < .02) return null;
    final root = pose[math.min(2, pose.length - 1)].getTranslation();
    final x = root.x.clamp(lo.x + span.x * .2, hi.x - span.x * .2);
    final z = root.z.clamp(lo.z + span.z * .22, lo.z + span.z * .68);
    final expectedY = root.y + math.min(span.y * .12, .35);
    SurfaceAnchor? best;
    double score = double.infinity;
    for (final mesh in parts) {
      final points = List.generate(
        mesh.vertices,
        (i) => skinnedPoint(mesh, i, pose),
      );
      for (final dz in [0.0, -.06 * span.z, .06 * span.z]) {
        for (var i = 0; i + 2 < mesh.indices.length; i += 3) {
          final ids = [
            mesh.indices[i],
            mesh.indices[i + 1],
            mesh.indices[i + 2],
          ];
          final a = points[ids[0]], b = points[ids[1]], c = points[ids[2]];
          final n = (b - a).cross(c - a);
          if (n.length2 < 1e-12 || n.y.abs() / n.length < .3) continue;
          final denominator =
              (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z);
          if (denominator.abs() < 1e-10) continue;
          final wa =
              ((b.z - c.z) * (x - c.x) + (c.x - b.x) * (z + dz - c.z)) /
              denominator;
          final wb =
              ((c.z - a.z) * (x - c.x) + (a.x - c.x) * (z + dz - c.z)) /
              denominator;
          final wc = 1 - wa - wb;
          if ([wa, wb, wc].any((w) => w < -.00001 || w > 1.00001)) continue;
          final y = wa * a.y + wb * b.y + wc * c.y;
          if (y < root.y - span.y * .12 || y < lo.y + span.y * .3) continue;
          final s = (y - expectedY).abs() + dz.abs() * .6;
          if (s >= score) continue;
          final weights = <int, double>{};
          for (var j = 0; j < 3; j++) {
            for (var k = 0; k < 4 && mesh.weights.isNotEmpty; k++) {
              final weight = mesh.weights[ids[j] * 4 + k] * [wa, wb, wc][j];
              weights.update(
                mesh.joints[ids[j] * 4 + k],
                (v) => v + weight,
                ifAbsent: () => weight,
              );
            }
          }
          final sorted = weights.keys.where((j) => j < pose.length).toList()
            ..sort((a, b) => weights[b]!.compareTo(weights[a]!));
          final bone = sorted.firstOrNull ?? 0;
          best = SurfaceAnchor(
            mesh,
            ids,
            [wa, wb, wc],
            bone,
            matrixRotation(pose[bone]),
          );
          score = s;
        }
      }
    }
    return best;
  }
}

v.Vector3 skinnedPoint(MeshData m, int index, List<v.Matrix4> pose) {
  final p = v.Vector3(
    m.positions[index * 3],
    m.positions[index * 3 + 1],
    m.positions[index * 3 + 2],
  );
  if (m.inverses.isEmpty) return p;
  final out = v.Vector3.zero();
  for (var k = 0; k < 4; k++) {
    final w = m.weights[index * 4 + k], j = m.joints[index * 4 + k];
    if (w <= 1e-7 || j >= pose.length || j >= m.inverses.length) continue;
    out.add((pose[j] * m.inverses[j]).transformed3(p) * w);
  }
  return out;
}

v.Quaternion matrixRotation(v.Matrix4 m) {
  final q = v.Quaternion.identity();
  m.decompose(v.Vector3.zero(), q, v.Vector3.zero());
  return q..normalize();
}

/// Seat and pelvis are expressed in the same model coordinate convention.
/// The resulting transform places the pelvis at the deformed saddle point.
v.Matrix4 seatedTransform(
  v.Vector3 saddle,
  v.Quaternion rotation,
  v.Vector3 pelvis, {
  double lateral = 0,
  double height = 0,
  double forward = 0,
  double rotX = 0,
  double rotY = 0,
  double rotZ = 0,
  double scaleX = 1,
  double scaleY = 1,
  double scaleZ = 1,
}) =>
    v.Matrix4.compose(saddle, rotation, v.Vector3.all(1)) *
    v.Matrix4.diagonal3Values(scaleX, scaleY, scaleZ) *
    v.Matrix4.rotationX(rotX * math.pi / 180) *
    v.Matrix4.rotationY(rotY * math.pi / 180) *
    v.Matrix4.rotationZ(rotZ * math.pi / 180) *
    (v.Matrix4.identity()
      ..translateByVector3(v.Vector3(lateral, height, forward))) *
    (v.Matrix4.identity()..translateByVector3(-pelvis));

/// Restrict the back anchor to ancestors of the actual head. Arms are not a
/// valid back socket even when their height is close to the desired value.
int? backBone(ClipData clip, int? head, double height) {
  if (head == null || head <= 0 || head >= clip.bones.length) return null;
  final pose = clip.pose(0);
  var b = clip.bones[head].parent;
  int? best;
  double score = double.infinity;
  var seen = <int>{};
  while (b > 0 && b < pose.length && seen.add(b)) {
    final p = pose[b].getTranslation();
    final d = (p.y - height * .72).abs() + p.x.abs();
    if (d < score) {
      score = d;
      best = b;
    }
    b = clip.bones[b].parent;
  }
  return best;
}
