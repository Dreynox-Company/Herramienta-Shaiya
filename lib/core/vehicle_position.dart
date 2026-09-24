import 'dart:convert';
import 'dart:typed_data';

const Map<int, ({int idle, int moving, String label})>
    riderAnimationProfiles = {
  0: (idle: 21, moving: 20, label: 'Vehículo clásico · 021/020'),
  1: (idle: 97, moving: 22, label: 'Vehículo alterno · 097/022'),
  2: (idle: 98, moving: 98, label: 'Carruaje · 098/098'),
  3: (idle: 97, moving: 22, label: 'Vehículo alterno B · 097/022'),
  4: (idle: 30, moving: 31, label: 'VehB corpus · 030/031'),
};

int? vehicleFamilyFromSource(String source) {
  final path = source.toLowerCase().replaceAll('\\', '/');
  final file = path.split('/').last;
  final match = RegExp(r'^vehicle_(hu|el|vi|de)(?:_|\\.|$)').firstMatch(file);
  return switch (match?.group(1)) {
    'hu' => 0,
    'el' => 1,
    'vi' => 2,
    'de' => 3,
    _ => null,
  };
}

String vehiclePositionSection(int family, int vehicleId) {
  if (family < 0 || family > 3) {
    throw FormatException('Familia de vehículo fuera de rango: $family');
  }
  if (vehicleId < 0 || vehicleId > 0xff) {
    throw FormatException('ID de vehículo fuera de rango: $vehicleId');
  }
  return 'F${family.toRadixString(16).toUpperCase()}_V'
      '${vehicleId.toRadixString(16).padLeft(2, '0').toUpperCase()}';
}

class VehiclePositionProfile {
  final int family;
  final int vehicleId;
  final bool enabled;
  final double posX;
  final double posY;
  final double posZ;
  final double rotX;
  final double rotY;
  final double rotZ;
  final double scaleX;
  final double scaleY;
  final double scaleZ;
  final int riderProfile;

  const VehiclePositionProfile({
    required this.family,
    required this.vehicleId,
    this.enabled = true,
    this.posX = 0,
    this.posY = 0,
    this.posZ = 0,
    this.rotX = 0,
    this.rotY = 0,
    this.rotZ = 0,
    this.scaleX = 1,
    this.scaleY = 1,
    this.scaleZ = 1,
    this.riderProfile = 0,
  });

  String get section => vehiclePositionSection(family, vehicleId);

  VehiclePositionProfile copyWith({
    bool? enabled,
    double? posX,
    double? posY,
    double? posZ,
    double? rotX,
    double? rotY,
    double? rotZ,
    double? scaleX,
    double? scaleY,
    double? scaleZ,
    int? riderProfile,
  }) =>
      VehiclePositionProfile(
        family: family,
        vehicleId: vehicleId,
        enabled: enabled ?? this.enabled,
        posX: posX ?? this.posX,
        posY: posY ?? this.posY,
        posZ: posZ ?? this.posZ,
        rotX: rotX ?? this.rotX,
        rotY: rotY ?? this.rotY,
        rotZ: rotZ ?? this.rotZ,
        scaleX: scaleX ?? this.scaleX,
        scaleY: scaleY ?? this.scaleY,
        scaleZ: scaleZ ?? this.scaleZ,
        riderProfile: riderProfile ?? this.riderProfile,
      );
}

/// DATA-side contract consumed by the ps0032 Studio Bridge.
///
/// ps0032 stores the native saddle/bone logic inside game.exe. The bridge keeps
/// that calculation untouched and applies this profile as a local delta just
/// before D3DTS_WORLD. Integer transport avoids locale-dependent float parsing:
/// position = millimetres / 1000, rotation = millidegrees / 1000 and scale =
/// permille / 1000. Negative scale mirrors an axis.
class VehiclePositionDocument {
  static const canonicalPath = 'excelxml/vehicleposition.ini';

  final String path;
  final Map<String, Map<String, String>> _sections;

  VehiclePositionDocument._(this.path, this._sections);

  factory VehiclePositionDocument.empty({
    String path = canonicalPath,
  }) =>
      VehiclePositionDocument._(path, <String, Map<String, String>>{});

  Iterable<VehiclePositionProfile> get profiles sync* {
    final keys = _sections.keys.toList()..sort();
    for (final key in keys) {
      final identity = _sectionIdentity(key);
      if (identity == null) continue;
      yield _profile(identity.$1, identity.$2, _sections[key]!);
    }
  }

  VehiclePositionProfile? resolve(int family, int vehicleId) {
    final key = vehiclePositionSection(family, vehicleId);
    final values = _sections[key];
    return values == null ? null : _profile(family, vehicleId, values);
  }

  void update(VehiclePositionProfile profile) {
    if (!riderAnimationProfiles.containsKey(profile.riderProfile)) {
      throw FormatException(
        'Perfil ANI de jinete no soportado: ${profile.riderProfile}',
      );
    }
    final values = _sections.putIfAbsent(
      profile.section,
      () => <String, String>{},
    );
    values
      ..['ENABLED'] = profile.enabled ? '1' : '0'
      ..['POS_X_MM'] = _scaled(profile.posX, 1000).toString()
      ..['POS_Y_MM'] = _scaled(profile.posY, 1000).toString()
      ..['POS_Z_MM'] = _scaled(profile.posZ, 1000).toString()
      ..['ROT_X_MDEG'] = _scaled(profile.rotX, 1000).toString()
      ..['ROT_Y_MDEG'] = _scaled(profile.rotY, 1000).toString()
      ..['ROT_Z_MDEG'] = _scaled(profile.rotZ, 1000).toString()
      ..['SCALE_X_PERMILLE'] = _scaled(profile.scaleX, 1000).toString()
      ..['SCALE_Y_PERMILLE'] = _scaled(profile.scaleY, 1000).toString()
      ..['SCALE_Z_PERMILLE'] = _scaled(profile.scaleZ, 1000).toString()
      ..['RIDER_PROFILE'] = profile.riderProfile.toString();
  }

  Uint8List encode() {
    final out = StringBuffer()
      ..writeln('; Shaiya Studio · ps0032 Vehicle Position Bridge')
      ..writeln('; Missing/disabled sections preserve the native game.exe result.')
      ..writeln('; Position=millimetres, rotation=millidegrees, scale=permille.')
      ..writeln('; Negative scale mirrors the corresponding local axis.')
      ..writeln();
    final sections = _sections.keys.toList()..sort();
    for (final section in sections) {
      out.writeln('[$section]');
      final values = _sections[section]!;
      const known = [
        'ENABLED',
        'POS_X_MM',
        'POS_Y_MM',
        'POS_Z_MM',
        'ROT_X_MDEG',
        'ROT_Y_MDEG',
        'ROT_Z_MDEG',
        'SCALE_X_PERMILLE',
        'SCALE_Y_PERMILLE',
        'SCALE_Z_PERMILLE',
        'RIDER_PROFILE',
      ];
      final emitted = <String>{};
      for (final key in known) {
        final value = values[key];
        if (value != null) {
          out.writeln('$key=$value');
          emitted.add(key);
        }
      }
      final extras = values.keys.where((k) => !emitted.contains(k)).toList()
        ..sort();
      for (final key in extras) {
        out.writeln('$key=${values[key]}');
      }
      out.writeln();
    }
    return Uint8List.fromList(utf8.encode(out.toString()));
  }

  void validateEncoded(Uint8List bytes) {
    final parsed = VehiclePositionDocument.parse(bytes, path);
    for (final expected in profiles) {
      final actual = parsed.resolve(expected.family, expected.vehicleId);
      if (actual == null ||
          actual.enabled != expected.enabled ||
          actual.riderProfile != expected.riderProfile ||
          !_sameTransport(actual.posX, expected.posX, 1000) ||
          !_sameTransport(actual.posY, expected.posY, 1000) ||
          !_sameTransport(actual.posZ, expected.posZ, 1000) ||
          !_sameTransport(actual.rotX, expected.rotX, 1000) ||
          !_sameTransport(actual.rotY, expected.rotY, 1000) ||
          !_sameTransport(actual.rotZ, expected.rotZ, 1000) ||
          !_sameTransport(actual.scaleX, expected.scaleX, 1000) ||
          !_sameTransport(actual.scaleY, expected.scaleY, 1000) ||
          !_sameTransport(actual.scaleZ, expected.scaleZ, 1000)) {
        throw FormatException(
          'VehiclePosition.ini no revalidó ${expected.section}.',
        );
      }
    }
  }

  static VehiclePositionDocument parse(Uint8List bytes, String path) {
    var raw = bytes;
    if (raw.length >= 3 &&
        raw[0] == 0xef &&
        raw[1] == 0xbb &&
        raw[2] == 0xbf) {
      raw = Uint8List.sublistView(raw, 3);
    }
    final text = utf8.decode(raw, allowMalformed: false);
    final sections = <String, Map<String, String>>{};
    Map<String, String>? current;
    for (var lineNumber = 0;
        lineNumber < const LineSplitter().convert(text).length;
        lineNumber++) {
      final sourceLine = const LineSplitter().convert(text)[lineNumber];
      final line = sourceLine.trim();
      if (line.isEmpty || line.startsWith(';') || line.startsWith('#')) {
        continue;
      }
      if (line.startsWith('[') && line.endsWith(']')) {
        final name = line.substring(1, line.length - 1).trim().toUpperCase();
        if (name.isEmpty || name.contains(']') || name.contains('[')) {
          throw FormatException(
            '$path · línea ${lineNumber + 1}: sección INI inválida.',
          );
        }
        current = sections.putIfAbsent(name, () => <String, String>{});
        continue;
      }
      final split = line.indexOf('=');
      if (current == null || split <= 0) {
        throw FormatException(
          '$path · línea ${lineNumber + 1}: entrada INI fuera de sección.',
        );
      }
      final key = line.substring(0, split).trim().toUpperCase();
      final value = line.substring(split + 1).trim();
      if (key.isEmpty || key.contains(' ') || key.contains('\t')) {
        throw FormatException(
          '$path · línea ${lineNumber + 1}: clave INI inválida.',
        );
      }
      current[key] = value;
    }

    final document = VehiclePositionDocument._(path, sections);
    for (final profile in document.profiles) {
      if (!riderAnimationProfiles.containsKey(profile.riderProfile)) {
        throw FormatException(
          '$path · ${profile.section}: RIDER_PROFILE fuera de rango.',
        );
      }
    }
    return document;
  }

  static VehiclePositionProfile _profile(
    int family,
    int vehicleId,
    Map<String, String> values,
  ) =>
      VehiclePositionProfile(
        family: family,
        vehicleId: vehicleId,
        enabled: _integer(values, 'ENABLED', 0) != 0,
        posX: _integer(values, 'POS_X_MM', 0) / 1000,
        posY: _integer(values, 'POS_Y_MM', 0) / 1000,
        posZ: _integer(values, 'POS_Z_MM', 0) / 1000,
        rotX: _integer(values, 'ROT_X_MDEG', 0) / 1000,
        rotY: _integer(values, 'ROT_Y_MDEG', 0) / 1000,
        rotZ: _integer(values, 'ROT_Z_MDEG', 0) / 1000,
        scaleX: _integer(values, 'SCALE_X_PERMILLE', 1000) / 1000,
        scaleY: _integer(values, 'SCALE_Y_PERMILLE', 1000) / 1000,
        scaleZ: _integer(values, 'SCALE_Z_PERMILLE', 1000) / 1000,
        riderProfile: _integer(values, 'RIDER_PROFILE', 0),
      );

  static int _integer(Map<String, String> values, String key, int fallback) {
    final raw = values[key];
    if (raw == null || raw.isEmpty) return fallback;
    final value = int.tryParse(raw);
    if (value == null || value < -0x7fffffff || value > 0x7fffffff) {
      throw FormatException('VehiclePosition.ini: $key no es un entero válido.');
    }
    return value;
  }

  static (int, int)? _sectionIdentity(String section) {
    final match = RegExp(r'^F([0-3])_V([0-9A-F]{2})$').firstMatch(section);
    if (match == null) return null;
    return (
      int.parse(match.group(1)!, radix: 16),
      int.parse(match.group(2)!, radix: 16),
    );
  }

  static int _scaled(double value, int factor) {
    if (!value.isFinite) {
      throw const FormatException('VehiclePosition.ini: valor no finito.');
    }
    final encoded = (value * factor).round();
    if (encoded < -0x7fffffff || encoded > 0x7fffffff) {
      throw const FormatException('VehiclePosition.ini: valor fuera de rango.');
    }
    return encoded;
  }

  static bool _sameTransport(double a, double b, int factor) =>
      (a * factor).round() == (b * factor).round();
}
