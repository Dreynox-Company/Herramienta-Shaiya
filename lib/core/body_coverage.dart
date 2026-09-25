import 'dart:math' as math;

import 'formats.dart';

/// Conservative body-region classification using original skinning and geometry.
/// Unknown or inconclusive geometry always retains the fallback body region.
/// Naming or a NULL record alone can never suppress legs, hands or feet.
bool bodyRegionCovered(
  MeshData garment,
  MeshData reference, {
  MeshData? upperReference,
}) {
  if (garment.source == reference.source) return true;
  if (garment.indices.isEmpty ||
      reference.indices.isEmpty ||
      garment.inverses.isEmpty ||
      reference.inverses.isEmpty) {
    return false;
  }
  final target = _Profile.of(reference);
  final candidate = _Profile.of(garment);
  final torso = upperReference == null ? null : _Profile.of(upperReference);
  if (target.total <= 0 || candidate.total <= 0) return false;
  // Bones substantially used by the base torso are not evidence of legs/gloves.
  final anchors = target.weights.keys.where((bone) {
    final share = target.weights[bone]! / target.total;
    final torsoShare = (torso?.weights[bone] ?? 0) / (torso?.total ?? 1);
    return share >= .045 && torsoShare < .08;
  }).toList();
  if (anchors.length < 2) return false;
  double expected = 0, covered = 0;
  var matched = 0;
  for (final bone in anchors) {
    final targetArea = target.weights[bone]!;
    expected += targetArea;
    final contribution = candidate.weights[bone] ?? 0;
    final ratio = (contribution / targetArea).clamp(0.0, 1.0);
    covered += targetArea * ratio;
    if (ratio >= .22) matched++;
  }
  // Require both limbs, not a dangling skirt point or one decorative vertex.
  if (matched < math.max(2, (anchors.length * .7).ceil()) ||
      expected <= 0 ||
      covered / expected < .32) {
    return false;
  }
  final minY = target.minY, maxY = target.maxY;
  final height = maxY - minY;
  if (!height.isFinite || height < 1e-6) return false;
  final overlap =
      math.min(candidate.maxY, maxY) - math.max(candidate.minY, minY);
  return overlap >= height * .7;
}

class _Profile {
  final Map<int, double> weights = {};
  double total = 0;
  double minY = double.infinity, maxY = double.negativeInfinity;
  static _Profile of(MeshData mesh) {
    final result = _Profile();
    for (var f = 0; f < mesh.indices.length; f += 3) {
      final a = mesh.indices[f],
          b = mesh.indices[f + 1],
          c = mesh.indices[f + 2];
      final p = mesh.positions;
      final ax = p[b * 3] - p[a * 3],
          ay = p[b * 3 + 1] - p[a * 3 + 1],
          az = p[b * 3 + 2] - p[a * 3 + 2];
      final bx = p[c * 3] - p[a * 3],
          by = p[c * 3 + 1] - p[a * 3 + 1],
          bz = p[c * 3 + 2] - p[a * 3 + 2];
      final nx = ay * bz - az * by,
          ny = az * bx - ax * bz,
          nz = ax * by - ay * bx;
      final area = math.sqrt(nx * nx + ny * ny + nz * nz) / 6;
      if (!area.isFinite || area <= 1e-14) continue;
      for (final i in [a, b, c]) {
        result.minY = math.min(result.minY, p[i * 3 + 1]);
        result.maxY = math.max(result.maxY, p[i * 3 + 1]);
        for (var k = 0; k < 4; k++) {
          if (i * 4 + k >= mesh.weights.length) continue;
          final weight = mesh.weights[i * 4 + k] * area;
          if (weight <= 1e-10) continue;
          final bone = mesh.joints[i * 4 + k];
          result.weights.update(
            bone,
            (old) => old + weight,
            ifAbsent: () => weight,
          );
          result.total += weight;
        }
      }
    }
    return result;
  }
}

/// Costume feet can include shins while the torso contains thighs. Test their
/// joint coverage rather than adding the whole original lower-body underneath.
bool bodyRegionCoveredBy(
  List<MeshData> garments,
  MeshData reference, {
  MeshData? upperReference,
}) {
  if (garments.any((m) => m.source == reference.source)) return true;
  if (garments.isEmpty || reference.inverses.isEmpty) return false;
  final valid = garments
      .where((m) => m.inverses.length == reference.inverses.length)
      .toList();
  if (valid.isEmpty) return false;
  // Build only an area profile: no copy of the combined vertex buffers.
  final target = _Profile.of(reference), candidate = _Profile();
  for (final mesh in valid) {
    final profile = _Profile.of(mesh);
    candidate.total += profile.total;
    candidate.minY = math.min(candidate.minY, profile.minY);
    candidate.maxY = math.max(candidate.maxY, profile.maxY);
    for (final e in profile.weights.entries) {
      candidate.weights.update(
        e.key,
        (w) => w + e.value,
        ifAbsent: () => e.value,
      );
    }
  }
  final torso = upperReference == null ? null : _Profile.of(upperReference);
  if (target.total <= 0 || candidate.total <= 0) return false;
  final anchors = target.weights.keys
      .where(
        (bone) =>
            target.weights[bone]! / target.total >= .045 &&
            (torso?.weights[bone] ?? 0) / (torso?.total ?? 1) < .08,
      )
      .toList();
  if (anchors.length < 2) return false;
  var expected = 0.0, covered = 0.0;
  var matched = 0;
  for (final bone in anchors) {
    final area = target.weights[bone]!;
    expected += area;
    final ratio = ((candidate.weights[bone] ?? 0) / area).clamp(0.0, 1.0);
    covered += area * ratio;
    if (ratio >= .22) matched++;
  }
  final height = target.maxY - target.minY;
  return matched >= math.max(2, (anchors.length * .7).ceil()) &&
      expected > 0 &&
      covered / expected >= .32 &&
      height.isFinite &&
      height > 1e-6 &&
      math.min(candidate.maxY, target.maxY) -
              math.max(candidate.minY, target.minY) >=
          height * .7;
}
