import 'wing_position.dart';

/// ps0032 imports WingPosition angles as signed integers, offsets as float32.
/// Preview and appearance snapshots may retain fractional angles. Native DATA
/// writes must not silently truncate them or claim parity with the preview.
void validateNativeWingProfile(WingPositionProfile profile) {
  final angles = <String, double>{
    'WING_ROT_X': profile.rotX,
    'WING_ROT_Y': profile.rotY,
    'WING_ROT_Z': profile.rotZ,
  };
  for (final entry in angles.entries) {
    final value = entry.value;
    if (!value.isFinite ||
        value < -2147483648 ||
        value > 2147483647 ||
        value != value.truncateToDouble()) {
      throw FormatException(
        '${entry.key}: el cliente ps0032 lee grados enteros de 32 bits. '
        'La vista previa conserva $value, pero no se ha guardado en DATA. '
        'Elige explícitamente un ángulo entero antes de guardar.',
      );
    }
  }
  final offsets = <String, double>{
    'WING_UP_DOWN': profile.upDown,
    'WING_FRONT_BACK': profile.frontBack,
    'WING_LEFT_RIGHT': profile.leftRight,
  };
  for (final entry in offsets.entries) {
    if (!entry.value.isFinite || entry.value.abs() > 3.4028234663852886e38) {
      throw FormatException(
        '${entry.key}: desplazamiento no representable como float32.',
      );
    }
  }
  if (profile.boneIndex < 0 || profile.boneIndex > 2147483647) {
    throw const FormatException('BONE_IDX: índice nativo no válido.');
  }
}
