import 'package:vector_math/vector_math_64.dart' as v;

/// ps0032 game.exe SHA-256 509c4a8f...73c2d, routine 0x525440.
/// Native row-vector sequence, established from calls 0x52592a..0x5259ba:
/// T(front=-Z) * T(up=+Y) * T(left=+X) * Rx * Ry * Rz * bone * world.
/// This is its column-vector equivalent. Do NOT write compensating rotations
/// into WingPosition.xml. Scale/mirror are separate Studio-only local controls.
v.Matrix4 nativeWingLocalTransform({
  required double rotX,
  required double rotY,
  required double rotZ,
  required double leftRight,
  required double upDown,
  required double frontBack,
  double scaleX = 1,
  double scaleY = 1,
  double scaleZ = 1,
}) {
  final values = [
    rotX,
    rotY,
    rotZ,
    leftRight,
    upDown,
    frontBack,
    scaleX,
    scaleY,
    scaleZ,
  ];
  if (values.any((value) => !value.isFinite) ||
      scaleX == 0 ||
      scaleY == 0 ||
      scaleZ == 0) {
    throw const FormatException('Transformación de alas no finita o singular.');
  }
  // The original executable uses the float-precision degree factor at 0x86ed30.
  const radiansPerDegree = 0.01745329238474369;
  return v.Matrix4.rotationZ(rotZ * radiansPerDegree) *
      v.Matrix4.rotationY(rotY * radiansPerDegree) *
      v.Matrix4.rotationX(rotX * radiansPerDegree) *
      v.Matrix4.translationValues(leftRight, upDown, -frontBack) *
      v.Matrix4.diagonal3Values(scaleX, scaleY, scaleZ);
}
