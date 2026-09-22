import 'dart:math' as math;
import 'package:vector_math/vector_math_64.dart' as v;
import 'formats.dart';

double wrapRadians(double angle) =>
    math.atan2(math.sin(angle), math.cos(angle));

/// Additive head layer. It never writes into clip keys or changes the original
/// skeleton. A fresh world pose is passed in on every evaluation.
class HeadLookController {
  final int bone;
  final List<int> descendants;
  double yaw = 0, pitch = 0;
  double maxYaw = 55 * math.pi / 180, maxPitch = 24 * math.pi / 180;
  double response = .16, maxSpeed = 2.8;
  HeadLookController(this.bone, List<BoneTrack> bones)
    : descendants = [
        for (var i = 0; i < bones.length; i++)
          if (_child(i, bone, bones)) i,
      ];
  static bool _child(int i, int parent, List<BoneTrack> bones) {
    for (var n = 0; i >= 0 && i < bones.length && n <= bones.length; n++) {
      if (i == parent) return true;
      i = bones[i].parent;
    }
    return false;
  }

  void step(
    double dt, {
    required double cameraYaw,
    required double cameraPitch,
    required double bodyYaw,
    bool enabled = true,
  }) {
    if (!dt.isFinite || dt <= 0) return;
    final d = dt.clamp(0.0, .1);
    final relative = wrapRadians(cameraYaw + math.pi - bodyYaw);
    // The neck cannot look behind its body. Fade away instead of flipping sign.
    final fade = ((math.pi - relative.abs()) / (math.pi * .35)).clamp(0.0, 1.0);
    final targetYaw = enabled ? relative.clamp(-maxYaw, maxYaw) * fade : 0.0;
    final targetPitch = enabled
        ? (-cameraPitch).clamp(-maxPitch, maxPitch) * fade
        : 0.0;
    final a = 1 - math.exp(-d / response);
    yaw += (a * (targetYaw - yaw)).clamp(-maxSpeed * d, maxSpeed * d);
    pitch += (a * (targetPitch - pitch)).clamp(-maxSpeed * d, maxSpeed * d);
  }

  void apply(List<v.Matrix4> pose) {
    if (bone < 0 || bone >= pose.length) return;
    final p = pose[bone].getTranslation();
    final rotate = v.Matrix4.identity()
      ..translateByVector3(p)
      ..rotateY(-yaw)
      ..rotateX(pitch)
      ..translateByVector3(-p);
    for (final i in descendants) {
      if (i < pose.length) pose[i] = rotate * pose[i];
    }
  }
}

/// Crossfades local rotations/translations and reconstructs the hierarchy.
/// This keeps joint lengths stable and avoids matrix-linear interpolation.
List<v.Matrix4> blendSkeleton(
  List<v.Matrix4> from,
  List<v.Matrix4> to,
  List<BoneTrack> bones,
  double alpha,
) {
  if (from.length != to.length || bones.length != to.length) return to;
  final out = <v.Matrix4>[];
  final t = alpha.clamp(0.0, 1.0);
  for (var i = 0; i < bones.length; i++) {
    final parent = bones[i].parent;
    final a = parent < 0 ? from[i] : v.Matrix4.inverted(from[parent]) * from[i];
    final b = parent < 0 ? to[i] : v.Matrix4.inverted(to[parent]) * to[i];
    final ap = v.Vector3.zero(),
        bp = v.Vector3.zero(),
        as = v.Vector3.zero(),
        bs = v.Vector3.zero();
    final aq = v.Quaternion.identity(), bq = v.Quaternion.identity();
    a.decompose(ap, aq, as);
    b.decompose(bp, bq, bs);
    final local = v.Matrix4.compose(
      ap * (1 - t) + bp * t,
      BoneTrack.slerp(aq, bq, t),
      as * (1 - t) + bs * t,
    );
    out.add(parent < 0 ? local : out[parent] * local);
  }
  return out;
}
