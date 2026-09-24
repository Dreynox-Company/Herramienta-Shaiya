import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:xml/xml.dart';

class WingPositionProfile {
  final int family, job, sex, boneIndex;
  final double rotX, rotY, rotZ, upDown, frontBack, leftRight;
  final bool boneWritable;
  final String provenance;

  const WingPositionProfile({
    required this.family,
    required this.job,
    required this.sex,
    required this.boneIndex,
    required this.rotX,
    required this.rotY,
    required this.rotZ,
    required this.upDown,
    required this.frontBack,
    required this.leftRight,
    this.boneWritable = false,
    this.provenance = 'WingPosition.xml',
  });

  int get key => family * 100 + job * 10 + sex;

  WingPositionProfile copyWith({
    int? boneIndex,
    double? rotX,
    double? rotY,
    double? rotZ,
    double? upDown,
    double? frontBack,
    double? leftRight,
    String? provenance,
  }) => WingPositionProfile(
    family: family,
    job: job,
    sex: sex,
    boneIndex: boneIndex ?? this.boneIndex,
    rotX: rotX ?? this.rotX,
    rotY: rotY ?? this.rotY,
    rotZ: rotZ ?? this.rotZ,
    upDown: upDown ?? this.upDown,
    frontBack: frontBack ?? this.frontBack,
    leftRight: leftRight ?? this.leftRight,
    boneWritable: boneWritable,
    provenance: provenance ?? this.provenance,
  );
}

class _XmlValue {
  final XmlElement? element;
  final XmlAttribute? attribute;
  const _XmlValue.element(this.element) : attribute = null;
  const _XmlValue.attribute(this.attribute) : element = null;

  String get value => attribute?.value ?? element?.innerText.trim() ?? '';

  void write(String value) {
    final a = attribute;
    if (a != null) {
      a.value = value;
      return;
    }
    final e = element;
    if (e != null) e.innerText = value;
  }
}

class _WingRowBinding {
  final int family, job, sex;
  final _XmlValue? bone;
  final _XmlValue rotX, rotY, rotZ, upDown, frontBack, leftRight;
  const _WingRowBinding({
    required this.family,
    required this.job,
    required this.sex,
    required this.bone,
    required this.rotX,
    required this.rotY,
    required this.rotZ,
    required this.upDown,
    required this.frontBack,
    required this.leftRight,
  });
  int get key => family * 100 + job * 10 + sex;
}

/// Parser/editor for DATA_Español/ExcelXml/WingPosition.xml.
///
/// The ps0032 corpus verifies 48 rows = 4 families x 6 jobs x 2 sexes.
/// The game-facing transform is:
/// X = WING_LEFT_RIGHT, Y = WING_UP_DOWN, Z = WING_FRONT_BACK,
/// plus WING_ROT_X/Y/Z. The verified canonical rows use bone index 4.
class WingPositionDocument {
  static const canonicalPath = 'excelxml/wingposition.xml';
  static const verifiedSourceSha256 =
      '8a2c376c898bb025550b5fe34b92a40dbbbb9e39063619cfee4756006908cd03';

  static const _rx = {'WING_ROT_X'};
  static const _ry = {'WING_ROT_Y'};
  static const _rz = {'WING_ROT_Z'};
  static const _up = {'WING_UP_DOWN'};
  static const _front = {'WING_FRONT_BACK'};
  static const _left = {'WING_LEFT_RIGHT'};
  static const _family = {
    'FAMILY',
    'FAMILY_ID',
    'RACE',
    'RACE_ID',
    'WING_FAMILY',
  };
  static const _job = {'JOB', 'JOB_ID', 'CLASS', 'CLASS_ID'};
  static const _sex = {'SEX', 'SEX_ID', 'GENDER', 'GENDER_ID'};
  static const _bone = {
    'BONE',
    'BONE_ID',
    'BONE_INDEX',
    'BONE_IDX',
    'WING_BONE',
    'WING_BONE_INDEX',
  };

  final String path;
  final String sourceSha256;
  final XmlDocument _document;
  final Map<int, _WingRowBinding> _bindings;
  final Map<int, WingPositionProfile> _profiles;

  WingPositionDocument._(
    this.path,
    this.sourceSha256,
    this._document,
    this._bindings,
    this._profiles,
  );

  bool get matchesVerifiedSource =>
      sourceSha256.toLowerCase() == verifiedSourceSha256;

  List<WingPositionProfile> get profiles {
    final out = _profiles.values.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return List.unmodifiable(out);
  }

  WingPositionProfile? resolve(int family, int job, int sex) =>
      _profiles[family * 100 + job * 10 + sex];

  void update(WingPositionProfile profile) {
    final b = _bindings[profile.key];
    if (b == null) {
      throw FormatException(
        'WingPosition.xml no contiene el perfil '
        '${profile.family}/${profile.job}/${profile.sex}.',
      );
    }
    b.rotX.write(_number(profile.rotX));
    b.rotY.write(_number(profile.rotY));
    b.rotZ.write(_number(profile.rotZ));
    b.upDown.write(_number(profile.upDown));
    b.frontBack.write(_number(profile.frontBack));
    b.leftRight.write(_number(profile.leftRight));
    if (b.bone != null) b.bone!.write(profile.boneIndex.toString());
    _profiles[profile.key] = profile.copyWith(provenance: path);
  }

  Uint8List encode() =>
      Uint8List.fromList(utf8.encode(_document.toXmlString(pretty: false)));

  void validateEncoded(Uint8List bytes) {
    final parsed = WingPositionDocument.parse(bytes, path);
    if (parsed.profiles.length != 48) {
      throw const FormatException(
        'WingPosition.xml perdió perfiles durante la serialización.',
      );
    }
    for (final expected in profiles) {
      final actual = parsed.resolve(
        expected.family,
        expected.job,
        expected.sex,
      );
      if (actual == null ||
          !_close(actual.rotX, expected.rotX) ||
          !_close(actual.rotY, expected.rotY) ||
          !_close(actual.rotZ, expected.rotZ) ||
          !_close(actual.upDown, expected.upDown) ||
          !_close(actual.frontBack, expected.frontBack) ||
          !_close(actual.leftRight, expected.leftRight)) {
        throw FormatException(
          'WingPosition.xml no revalidó el perfil '
          '${expected.family}/${expected.job}/${expected.sex}.',
        );
      }
    }
  }

  static WingPositionDocument parse(Uint8List bytes, String path) {
    var raw = bytes;
    if (raw.length >= 3 && raw[0] == 0xef && raw[1] == 0xbb && raw[2] == 0xbf) {
      raw = Uint8List.sublistView(raw, 3);
    }
    final source = utf8.decode(raw, allowMalformed: false);
    final document = XmlDocument.parse(source);
    final all = document.descendants.whereType<XmlElement>().toList();

    bool hasPose(XmlElement e) =>
        _find(e, _rx) != null &&
        _find(e, _ry) != null &&
        _find(e, _rz) != null &&
        _find(e, _up) != null &&
        _find(e, _front) != null &&
        _find(e, _left) != null;

    final rows = all
        .where(hasPose)
        .where((e) => !e.childElements.any(hasPose))
        .toList();
    if (rows.length != 48) {
      final spreadsheet = _spreadsheetBindings(document, path);
      if (spreadsheet != null) {
        return WingPositionDocument._(
          path,
          sha256.convert(bytes).toString(),
          document,
          spreadsheet.bindings,
          spreadsheet.profiles,
        );
      }
      throw FormatException(
        'WingPosition.xml: no se encontró el layout semántico ni la tabla '
        'SpreadsheetML de 48 perfiles (se detectaron ${rows.length} filas '
        'semánticas).',
      );
    }

    final rf = <int?>[], rj = <int?>[], rs = <int?>[];
    for (final row in rows) {
      rf.add(_identity(_find(row, _family)?.value, 'family'));
      rj.add(_identity(_find(row, _job)?.value, 'job'));
      rs.add(_identity(_find(row, _sex)?.value, 'sex'));
    }
    final f1 = _oneBased(rf, 4), j1 = _oneBased(rj, 6), s1 = _oneBased(rs, 2);
    final bindings = <int, _WingRowBinding>{};
    final profiles = <int, WingPositionProfile>{};

    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final family = rf[i] == null ? i ~/ 12 : rf[i]! - (f1 ? 1 : 0);
      final job = rj[i] == null ? (i % 12) ~/ 2 : rj[i]! - (j1 ? 1 : 0);
      final sex = rs[i] == null ? i % 2 : rs[i]! - (s1 ? 1 : 0);
      if (family < 0 ||
          family > 3 ||
          job < 0 ||
          job > 5 ||
          sex < 0 ||
          sex > 1) {
        throw FormatException(
          'WingPosition.xml: identidad fuera de rango en fila $i.',
        );
      }
      final bone = _find(row, _bone);
      final binding = _WingRowBinding(
        family: family,
        job: job,
        sex: sex,
        bone: bone,
        rotX: _required(row, _rx, 'WING_ROT_X'),
        rotY: _required(row, _ry, 'WING_ROT_Y'),
        rotZ: _required(row, _rz, 'WING_ROT_Z'),
        upDown: _required(row, _up, 'WING_UP_DOWN'),
        frontBack: _required(row, _front, 'WING_FRONT_BACK'),
        leftRight: _required(row, _left, 'WING_LEFT_RIGHT'),
      );
      if (bindings.containsKey(binding.key)) {
        throw FormatException(
          'WingPosition.xml: perfil duplicado $family/$job/$sex.',
        );
      }
      bindings[binding.key] = binding;
      profiles[binding.key] = WingPositionProfile(
        family: family,
        job: job,
        sex: sex,
        boneIndex: int.tryParse(bone?.value ?? '') ?? 4,
        rotX: _double(binding.rotX.value, 'WING_ROT_X'),
        rotY: _double(binding.rotY.value, 'WING_ROT_Y'),
        rotZ: _double(binding.rotZ.value, 'WING_ROT_Z'),
        upDown: _double(binding.upDown.value, 'WING_UP_DOWN'),
        frontBack: _double(binding.frontBack.value, 'WING_FRONT_BACK'),
        leftRight: _double(binding.leftRight.value, 'WING_LEFT_RIGHT'),
        boneWritable: bone != null,
        provenance: path,
      );
    }

    return WingPositionDocument._(
      path,
      sha256.convert(bytes).toString(),
      document,
      bindings,
      profiles,
    );
  }

  static _XmlValue _required(XmlElement row, Set<String> names, String label) {
    final value = _find(row, names);
    if (value == null) {
      throw FormatException('WingPosition.xml: falta $label.');
    }
    return value;
  }

  static _XmlValue? _find(XmlElement row, Set<String> names) {
    final wanted = names.map((n) => n.toUpperCase()).toSet();

    _XmlValue? inspect(XmlElement element) {
      for (final attribute in element.attributes) {
        if (wanted.contains(attribute.name.local.toUpperCase())) {
          return _XmlValue.attribute(attribute);
        }
      }

      final elementName = element.name.local.toUpperCase();
      if (wanted.contains(elementName)) {
        final valueAttribute = element.attributes
            .where(
              (a) =>
                  a.name.local.toLowerCase() == 'value' ||
                  a.name.local.toLowerCase() == 'val',
            )
            .firstOrNull;
        return valueAttribute == null
            ? _XmlValue.element(element)
            : _XmlValue.attribute(valueAttribute);
      }

      final key = element.attributes
          .where(
            (a) =>
                a.name.local.toLowerCase() == 'name' ||
                a.name.local.toLowerCase() == 'key' ||
                a.name.local.toLowerCase() == 'field' ||
                a.name.local.toLowerCase() == 'column',
          )
          .map((a) => a.value.trim().toUpperCase())
          .where(wanted.contains)
          .firstOrNull;
      if (key == null) return null;

      final valueAttribute = element.attributes
          .where(
            (a) =>
                a.name.local.toLowerCase() == 'value' ||
                a.name.local.toLowerCase() == 'val',
          )
          .firstOrNull;
      return valueAttribute == null
          ? _XmlValue.element(element)
          : _XmlValue.attribute(valueAttribute);
    }

    final direct = inspect(row);
    if (direct != null) return direct;
    for (final element in row.descendants.whereType<XmlElement>()) {
      final found = inspect(element);
      if (found != null) return found;
    }
    return null;
  }

  static int? _identity(String? raw, String kind) {
    if (raw == null || raw.trim().isEmpty) return null;
    final value = raw.trim().toLowerCase();
    final numeric = int.tryParse(value);
    if (numeric != null) return numeric;
    if (kind == 'family') {
      return const {
        'human': 0,
        'humano': 0,
        'elf': 1,
        'elfo': 1,
        'vail': 2,
        'vile': 2,
        'deatheater': 3,
        'nordein': 3,
      }[value];
    }
    if (kind == 'sex') {
      return const {
        'male': 0,
        'masculino': 0,
        'm': 0,
        'female': 1,
        'femenino': 1,
        'f': 1,
      }[value];
    }
    if (kind == 'job') {
      return const {
        'fighter': 0,
        'warrior': 0,
        'defender': 1,
        'guardian': 1,
        'ranger': 2,
        'assassin': 2,
        'archer': 3,
        'hunter': 3,
        'mage': 4,
        'pagan': 4,
        'priest': 5,
        'oracle': 5,
      }[value];
    }
    return null;
  }

  static bool _oneBased(List<int?> values, int max) {
    final present = values.whereType<int>().toList();
    return present.isNotEmpty &&
        !present.contains(0) &&
        present.every((v) => v >= 1 && v <= max);
  }

  static double _double(String raw, String field) {
    final value = double.tryParse(raw.trim().replaceAll(',', '.'));
    if (value == null || !value.isFinite) {
      throw FormatException('WingPosition.xml: $field inválido: $raw');
    }
    return value;
  }

  static String _number(double value) {
    if (!value.isFinite) {
      throw const FormatException(
        'WingPosition.xml no admite números no finitos.',
      );
    }
    var out = value.toStringAsFixed(6);
    out = out.replaceFirst(RegExp(r'0+$'), '');
    out = out.replaceFirst(RegExp(r'\.$'), '');
    return out == '-0' ? '0' : out;
  }

  static bool _close(double a, double b) => (a - b).abs() <= 1e-6;

  static const List<List<num>> _verifiedRows = [
    [0, 0, 0, 4, 170, 0, 90, .05, -.18, 0],
    [0, 0, 1, 4, 170, 0, 90, .05, -.11, 0],
    [0, 1, 0, 4, 170, 0, 90, .05, -.18, 0],
    [0, 1, 1, 4, 170, 0, 90, .05, -.11, 0],
    [0, 2, 0, 4, 0, 0, 90, 0, 0, 0],
    [0, 2, 1, 4, 0, 0, 90, 0, 0, 0],
    [0, 3, 0, 4, 0, 0, 90, 0, 0, 0],
    [0, 3, 1, 4, 0, 0, 90, 0, 0, 0],
    [0, 4, 0, 4, 0, 0, 90, 0, 0, 0],
    [0, 4, 1, 4, 0, 0, 90, 0, 0, 0],
    [0, 5, 0, 4, 168, 0, 90, .05, -.14, 0],
    [0, 5, 1, 4, 168, 0, 90, .04, -.11, 0],
    [1, 0, 0, 4, 0, 0, 90, 0, 0, 0],
    [1, 0, 1, 4, 0, 0, 90, 0, 0, 0],
    [1, 1, 0, 4, 0, 0, 90, 0, 0, 0],
    [1, 1, 1, 4, 0, 0, 90, 0, 0, 0],
    [1, 2, 0, 4, 180, 0, 90, -.04, -.12, 0],
    [1, 2, 1, 4, 175, 0, 90, .03, -.12, 0],
    [1, 3, 0, 4, 180, 0, 90, -.04, -.12, 0],
    [1, 3, 1, 4, 175, 0, 90, .03, -.12, 0],
    [1, 4, 0, 4, 183, 0, 90, .01, -.13, 0],
    [1, 4, 1, 4, 175, 0, 90, .02, -.10, 0],
    [1, 5, 0, 4, 0, 0, 90, 0, 0, 0],
    [1, 5, 1, 4, 0, 0, 90, 0, 0, 0],
    [2, 0, 0, 4, 0, 0, 90, 0, 0, 0],
    [2, 0, 1, 4, 0, 0, 90, 0, 0, 0],
    [2, 1, 0, 4, 0, 0, 90, 0, 0, 0],
    [2, 1, 1, 4, 0, 0, 90, 0, 0, 0],
    [2, 2, 0, 4, 180, 0, 90, .04, -.12, 0],
    [2, 2, 1, 4, 173, 0, 90, .05, -.11, 0],
    [2, 3, 0, 4, 0, 0, 90, 0, 0, 0],
    [2, 3, 1, 4, 0, 0, 90, 0, 0, 0],
    [2, 4, 0, 4, 178, 0, 90, .06, -.11, 0],
    [2, 4, 1, 4, 175, 0, 90, .04, -.11, 0],
    [2, 5, 0, 4, 178, 0, 90, .06, -.11, 0],
    [2, 5, 1, 4, 175, 0, 90, .04, -.11, 0],
    [3, 0, 0, 4, 192, 0, 90, .10, -.19, 0],
    [3, 0, 1, 4, 165, 0, 90, .04, -.17, 0],
    [3, 1, 0, 4, 192, 0, 90, .10, -.19, 0],
    [3, 1, 1, 4, 165, 0, 90, .04, -.17, 0],
    [3, 2, 0, 4, 0, 0, 90, 0, 0, 0],
    [3, 2, 1, 4, 0, 0, 90, 0, 0, 0],
    [3, 3, 0, 4, 185, 0, 90, .15, -.14, 0],
    [3, 3, 1, 4, 170, 0, 90, 0, -.19, 0],
    [3, 4, 0, 4, 0, 0, 90, 0, 0, 0],
    [3, 4, 1, 4, 0, 0, 90, 0, 0, 0],
    [3, 5, 0, 4, 0, 0, 90, 0, 0, 0],
    [3, 5, 1, 4, 0, 0, 90, 0, 0, 0],
  ];

  static List<WingPositionProfile> get verifiedBaseline => _verifiedRows
      .map(
        (r) => WingPositionProfile(
          family: r[0].toInt(),
          job: r[1].toInt(),
          sex: r[2].toInt(),
          boneIndex: r[3].toInt(),
          rotX: r[4].toDouble(),
          rotY: r[5].toDouble(),
          rotZ: r[6].toDouble(),
          upDown: r[7].toDouble(),
          frontBack: r[8].toDouble(),
          leftRight: r[9].toDouble(),
          provenance: 'verified-baseline',
        ),
      )
      .toList(growable: false);

  static WingPositionProfile? verifiedResolve(int family, int job, int sex) {
    final key = family * 100 + job * 10 + sex;
    for (final p in verifiedBaseline) {
      if (p.key == key) return p;
    }
    return null;
  }
}
