import 'package:vector_math/vector_math_64.dart';

/// Apply the rider transform exactly once; all attachment factors are in model space.
Matrix4 backAttachmentPose({
  required Vector3 position,
  required double yaw,
  required Matrix4 bone,
  required Matrix4 referenceInverse,
  required Vector3 offset,
  required double scale,
}) {
  final root = Matrix4.compose(
    position,
    Quaternion.axisAngle(Vector3(0, 1, 0), yaw),
    Vector3(1, 1, -1),
  );
  return root *
      bone *
      referenceInverse *
      Matrix4.compose(offset, Quaternion.identity(), Vector3.all(scale));
}
