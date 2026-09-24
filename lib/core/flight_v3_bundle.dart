import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import 'formats.dart';

class FlightV3CombatProfile {
  final String code;
  final ClipData guard;
  final List<ClipData> attacks;
  final ClipData run;

  const FlightV3CombatProfile({
    required this.code,
    required this.guard,
    required this.attacks,
    required this.run,
  });
}

class FlightV3Transition {
  final String id;
  final String kind;
  final String? profile;
  final String? targetClip;
  final bool shield;
  final double duration;
  final double destinationPhase;
  final ClipData clip;

  const FlightV3Transition({
    required this.id,
    required this.kind,
    required this.profile,
    required this.targetClip,
    required this.shield,
    required this.duration,
    required this.destinationPhase,
    required this.clip,
  });
}

/// Verified reader for Shaiya_Vuelo_Combate_V3_Completo.zip.
///
/// The ZIP is treated as evidence, not as arbitrary executable content:
/// - no JS/BAT/HTML is executed;
/// - every file listed in SHA256SUMS.txt is verified before the bundle is used;
/// - ANI are reparsed with Studio's native ANI parser;
/// - the body package is accepted only for the canonical 36-bone humf rig;
/// - the package's own binary/numeric QA summaries must report zero failures.
class FlightV3Bundle {
  static const packageMarker = 'Shaiya_Vuelo_Combate_V3/';
  static const int maxZipBytes = 32 * 1024 * 1024;
  static const int maxExpandedBytes = 64 * 1024 * 1024;
  static const int maxEntries = 512;
  static const canonicalSourceSha256 =
      '7f720a9e339d96a6e47cdce11094ecb64663c2f80f102de179f76e7f0b2c8a44';
  static const requiredTransitionIds = <String>{
    'V3_TAKEOFF_NORMAL_NEUTRAL',
    'V3_LAND_NORMAL_NEUTRAL',
    'V3_HOVER_TO_FLIGHT_NEUTRAL',
    'V3_FLIGHT_TO_HOVER_NEUTRAL',
    'V3_TAKEOFF_NORMAL_SHIELD',
    'V3_LAND_NORMAL_SHIELD',
    'V3_HOVER_TO_FLIGHT_SHIELD',
    'V3_FLIGHT_TO_HOVER_SHIELD',
    'V3_LAND_COMBAT_ON',
    'V3_FLIGHT_LAND_COMBAT_ON',
    'V3_TAKEOFF_COMBAT_ON',
    'V3_LAND_COMBAT_ON_SHIELD',
    'V3_FLIGHT_LAND_COMBAT_ON_SHIELD',
    'V3_TAKEOFF_COMBAT_ON_SHIELD',
    'V3_LAND_COMBAT_DU',
    'V3_FLIGHT_LAND_COMBAT_DU',
    'V3_TAKEOFF_COMBAT_DU',
    'V3_LAND_COMBAT_TH',
    'V3_FLIGHT_LAND_COMBAT_TH',
    'V3_TAKEOFF_COMBAT_TH',
    'V3_LAND_COMBAT_SP',
    'V3_FLIGHT_LAND_COMBAT_SP',
    'V3_TAKEOFF_COMBAT_SP',
    'V3_SEQUENCE_ON_NEUTRAL',
    'V3_SEQUENCE_ON_SHIELD',
    'V3_SEQUENCE_DU_NEUTRAL',
  };

  final ClipData normal;
  final ClipData walk;
  final ClipData run;
  final ClipData hover;
  final ClipData flight;
  final ClipData hoverShield;
  final ClipData flightShield;
  final Map<String, FlightV3CombatProfile> combat;
  final Map<String, FlightV3Transition> transitions;
  final Map<String, Object?> evidence;
  final Map<String, Object?> characterMap;

  const FlightV3Bundle({
    required this.normal,
    required this.walk,
    required this.run,
    required this.hover,
    required this.flight,
    required this.hoverShield,
    required this.flightShield,
    required this.combat,
    required this.transitions,
    required this.evidence,
    required this.characterMap,
  });

  bool compatibleWith(String archetype, ClipData original) {
    if (archetype.toLowerCase() != 'humf') return false;
    if (original.bones.length != 36) return false;
    return _sameHierarchy(normal, original);
  }

  FlightV3CombatProfile? combatFor(String code) => combat[code];

  FlightV3Transition? transition(String id, {String? profile, bool? shield}) {
    final exact = transitions[id];
    if (exact != null) return exact;
    for (final value in transitions.values) {
      if (value.kind != id.toUpperCase()) continue;
      if (profile != null && value.profile != profile) continue;
      if (shield != null && value.shield != shield) continue;
      return value;
    }
    return null;
  }

  static bool _sameHierarchy(ClipData a, ClipData b) {
    if (a.bones.length != b.bones.length) return false;
    for (var i = 0; i < a.bones.length; i++) {
      if (a.bones[i].parent != b.bones[i].parent) return false;
    }
    return true;
  }

  static FlightV3Bundle decode(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maxZipBytes) {
      throw const FormatException('Paquete Flight V3 fuera de límite.');
    }

    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    if (archive.length > maxEntries) {
      throw const FormatException(
        'Paquete Flight V3 contiene demasiadas entradas.',
      );
    }

    final files = <String, Uint8List>{};
    var expanded = 0;
    for (final entry in archive) {
      if (!entry.isFile) continue;
      final normalized = entry.name.replaceAll('\\', '/');
      final marker = normalized.indexOf(packageMarker);
      final relative = marker >= 0
          ? normalized.substring(marker + packageMarker.length)
          : normalized;
      if (relative.isEmpty ||
          relative.startsWith('/') ||
          relative.contains('../') ||
          relative.contains(':')) {
        throw FormatException(
          'Ruta insegura dentro de Flight V3: ${entry.name}',
        );
      }
      final raw = entry.readBytes();
      if (raw == null) {
        throw FormatException('Flight V3: no se pudo leer ${entry.name}.');
      }
      final data = Uint8List.fromList(raw);
      expanded += data.length;
      if (expanded > maxExpandedBytes) {
        throw const FormatException('Flight V3 expandido supera 64 MiB.');
      }
      files[relative] = data;
    }

    Uint8List required(String path) {
      final value = files[path];
      if (value == null) {
        throw FormatException('Flight V3 incompleto: falta $path.');
      }
      return value;
    }

    final sumsText = utf8.decode(required('SHA256SUMS.txt'));
    final declared = <String, String>{};
    for (final line in const LineSplitter().convert(sumsText)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final match = RegExp(
        r'^([0-9a-fA-F]{64})\s+\*?(.+)$',
      ).firstMatch(trimmed);
      if (match == null) {
        throw const FormatException('SHA256SUMS.txt de Flight V3 es inválido.');
      }
      declared[match.group(2)!.replaceAll('\\', '/')] = match
          .group(1)!
          .toLowerCase();
    }
    if (declared.isEmpty) {
      throw const FormatException('Flight V3 no contiene hashes verificables.');
    }
    for (final entry in declared.entries) {
      final data = files[entry.key];
      if (data == null) {
        throw FormatException(
          'Flight V3: falta archivo listado en SHA256SUMS: ${entry.key}.',
        );
      }
      if (sha256.convert(data).toString().toLowerCase() != entry.value) {
        throw FormatException('Flight V3: SHA-256 incorrecto: ${entry.key}.');
      }
    }

    Map<String, dynamic> jsonFile(String path) {
      final raw = jsonDecode(utf8.decode(required(path)));
      if (raw is! Map) {
        throw FormatException('Flight V3: $path no contiene un objeto JSON.');
      }
      return Map<String, dynamic>.from(raw);
    }

    Map<String, dynamic>? runtimeManifest;
    final runtimeBytes = files['RUNTIME_MANIFEST.json'];
    if (runtimeBytes != null) {
      final raw = jsonDecode(utf8.decode(runtimeBytes));
      if (raw is! Map) {
        throw const FormatException(
          'Flight V3: RUNTIME_MANIFEST.json no es un objeto JSON.',
        );
      }
      runtimeManifest = Map<String, dynamic>.from(raw);
      final schema = (runtimeManifest['schema'] as num?)?.toInt();
      final declaredFiles = (runtimeManifest['files'] as num?)?.toInt();
      final sourceSha = runtimeManifest['sourceSha256']
          ?.toString()
          .toLowerCase();
      if (schema != 1 ||
          declaredFiles != files.length - 1 ||
          sourceSha != canonicalSourceSha256) {
        throw const FormatException(
          'Flight V3 Runtime no coincide con el paquete V3 canónico auditado.',
        );
      }
      final tracked = files.keys.where(
        (path) => path != 'SHA256SUMS.txt' && path != 'RUNTIME_MANIFEST.json',
      );
      final missingHashes = tracked.where(
        (path) => !declared.containsKey(path),
      );
      if (missingHashes.isNotEmpty) {
        throw FormatException(
          'Flight V3 Runtime contiene recursos sin SHA-256: '
          '${missingHashes.take(4).join(', ')}.',
        );
      }
    }

    final binaryQa = jsonFile('Pruebas/resultados_binarios.json');
    final numericQa = jsonFile('Pruebas/resultados_numericos.json');
    if ((binaryQa['failed'] as num?)?.toInt() != 0 ||
        (numericQa['failed'] as num?)?.toInt() != 0) {
      throw const FormatException(
        'Flight V3 no supera sus pruebas binarias/numericas de origen.',
      );
    }

    ClipData clip(String path, {int expectedBones = 36}) {
      final parsed = ClipData.parse(required(path), 'flight-v3:$path');
      if (parsed.bones.length != expectedBones) {
        throw FormatException(
          'Flight V3: $path tiene ${parsed.bones.length} huesos; '
          'se esperaban $expectedBones.',
        );
      }
      return parsed;
    }

    final normal = clip('ANI/Combate_Humano/humf_000_normal.ani');
    final walk = clip('ANI/Combate_Humano/humf_001_walk.ani');
    final run = clip('ANI/Combate_Humano/humf_002_run.ani');
    final hover = clip('ANI/Vuelo/PLAYER_STOP_FLY.ani');
    final flight = clip('ANI/Vuelo/PLAYER_FLY.ani');
    final hoverShield = clip('ANI/Vuelo/PLAYER_STOP_FLY_SHIELD.ani');
    final flightShield = clip('ANI/Vuelo/PLAYER_FLY_SHIELD.ani');

    for (final candidate in [
      walk,
      run,
      hover,
      flight,
      hoverShield,
      flightShield,
    ]) {
      if (!_sameHierarchy(normal, candidate)) {
        throw const FormatException(
          'Flight V3 contiene ANI con jerarquias corporales incompatibles.',
        );
      }
    }

    FlightV3CombatProfile combatProfile(
      String code,
      int ready,
      List<int> attacks,
      int running,
      String prefix,
    ) {
      String file(int id, String suffix) =>
          'ANI/Combate_Humano/humf_${id.toString().padLeft(3, '0')}_$suffix.ani';
      final guard = clip(file(ready, '${prefix}ready'));
      final attackClips = <ClipData>[
        for (var i = 0; i < attacks.length; i++)
          clip(file(attacks[i], '${prefix}attack0${i + 1}')),
      ];
      final runClip = clip(file(running, '${prefix}run'));
      for (final candidate in [guard, ...attackClips, runClip]) {
        if (!_sameHierarchy(normal, candidate)) {
          throw FormatException(
            'Flight V3: perfil $code usa una jerarquia incompatible.',
          );
        }
      }
      return FlightV3CombatProfile(
        code: code,
        guard: guard,
        attacks: attackClips,
        run: runClip,
      );
    }

    final combat = <String, FlightV3CombatProfile>{
      'on': combatProfile('on', 34, const [35, 36, 37, 38], 40, 'on'),
      'du': combatProfile('du', 41, const [42, 43, 44, 45], 47, 'du'),
      'th': combatProfile('th', 23, const [24, 25, 26, 27], 29, 'th'),
      'sp': combatProfile('sp', 48, const [49, 50, 51, 52], 54, 'sp'),
    };

    final transitionManifest = jsonFile('transiciones.json');
    final rawTransitions = transitionManifest['transitions'];
    if (rawTransitions is! List || rawTransitions.length > 64) {
      throw const FormatException(
        'Flight V3: manifiesto de transiciones inválido.',
      );
    }

    final transitions = <String, FlightV3Transition>{};
    for (final item in rawTransitions) {
      if (item is! Map) {
        throw const FormatException('Flight V3: transición inválida.');
      }
      final row = Map<String, dynamic>.from(item);
      final id = row['id']?.toString() ?? '';
      final transitionPath =
          row['file']?.toString().replaceAll('\\', '/') ?? '';
      final kind = row['kind']?.toString().toUpperCase() ?? '';
      final duration = (row['duration'] as num?)?.toDouble();
      final destinationPhase =
          (row['destinationPhase'] as num?)?.toDouble() ?? 0;
      final bones = (row['bones'] as num?)?.toInt();
      final profile = row['profile']?.toString();
      if (!RegExp(r'^V3_[A-Z0-9_]+$').hasMatch(id) ||
          transitionPath.isEmpty ||
          !const {
            'TAKEOFF',
            'LANDING',
            'AIR_BLEND',
            'BODY_SEQUENCE',
          }.contains(kind) ||
          duration == null ||
          !duration.isFinite ||
          duration <= 0 ||
          bones != 36 ||
          (profile != null &&
              !const {'on', 'du', 'th', 'sp'}.contains(profile)) ||
          transitions.containsKey(id)) {
        throw FormatException('Flight V3: transición mal formada: $id.');
      }

      final parsed = clip(transitionPath);
      if (!_sameHierarchy(normal, parsed)) {
        throw FormatException('Flight V3: $id no coincide con el rig humf.');
      }
      if ((parsed.duration - duration).abs() > 1 / 15) {
        throw FormatException(
          'Flight V3: duración declarada de $id no coincide con el ANI.',
        );
      }

      transitions[id] = FlightV3Transition(
        id: id,
        kind: kind,
        profile: profile,
        targetClip: row['targetClip']?.toString(),
        shield: row['shield'] == true,
        duration: duration,
        destinationPhase: destinationPhase,
        clip: parsed,
      );
    }

    final actualTransitionIds = transitions.keys.toSet();
    if (actualTransitionIds.difference(requiredTransitionIds).isNotEmpty ||
        requiredTransitionIds.difference(actualTransitionIds).isNotEmpty) {
      throw const FormatException(
        'Flight V3: el inventario de 26 transiciones no coincide con V3 canónico.',
      );
    }

    final characterMap = jsonFile('mapa_combate_Character.json');
    final characters = characterMap['characters'];
    if (characters is! Map || !characters.containsKey('humf')) {
      throw const FormatException('Flight V3: mapa de personajes incompleto.');
    }
    final humf = characters['humf'];
    final humfBones = humf is Map ? humf['bones'] : null;
    if (humfBones is! List ||
        !humfBones.map((value) => (value as num?)?.toInt()).contains(36)) {
      throw const FormatException(
        'Flight V3: mapa humf no declara el rig canónico de 36 huesos.',
      );
    }

    return FlightV3Bundle(
      normal: normal,
      walk: walk,
      run: run,
      hover: hover,
      flight: flight,
      hoverShield: hoverShield,
      flightShield: flightShield,
      combat: Map.unmodifiable(combat),
      transitions: Map.unmodifiable(transitions),
      evidence: Map.unmodifiable({
        'shaEntries': declared.length,
        'binaryPassed': (binaryQa['passed'] as num?)?.toInt() ?? 0,
        'binaryFailed': (binaryQa['failed'] as num?)?.toInt() ?? 0,
        'numericPassed': (numericQa['passed'] as num?)?.toInt() ?? 0,
        'numericFailed': (numericQa['failed'] as num?)?.toInt() ?? 0,
        'transitions': transitions.length,
        'combatProfiles': combat.length,
        'expandedBytes': expanded,
        'runtimeSubset': runtimeManifest != null,
        'sourceSha256': runtimeManifest?['sourceSha256']
            ?.toString()
            .toLowerCase(),
        'runtimeFiles': (runtimeManifest?['files'] as num?)?.toInt(),
      }),
      characterMap: Map.unmodifiable(characterMap),
    );
  }
}
