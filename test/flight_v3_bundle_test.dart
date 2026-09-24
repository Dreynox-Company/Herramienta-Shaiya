import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/flight_v3_bundle.dart';

import 'recovery_test.dart' show Writer;

Uint8List ani36() {
  final b = Writer();
  b.i(0);
  b.i(30);
  b.short(36);
  for (var i = 0; i < 36; i++) {
    b.i(-1);
    b.mat();
    b.u(1);
    b.i(0);
    b.f(0);
    b.f(0);
    b.f(0);
    b.f(1);
    b.u(1);
    b.i(0);
    b.f(0);
    b.f(0);
    b.f(0);
  }
  return b.data.toBytes();
}

List<String> combatFiles() => [
  'ANI/Combate_Humano/humf_000_normal.ani',
  'ANI/Combate_Humano/humf_001_walk.ani',
  'ANI/Combate_Humano/humf_002_run.ani',
  'ANI/Combate_Humano/humf_034_onready.ani',
  for (var i = 35; i <= 38; i++)
    'ANI/Combate_Humano/humf_${i.toString().padLeft(3, '0')}_'
        'onattack0${i - 34}.ani',
  'ANI/Combate_Humano/humf_040_onrun.ani',
  'ANI/Combate_Humano/humf_041_duready.ani',
  for (var i = 42; i <= 45; i++)
    'ANI/Combate_Humano/humf_${i.toString().padLeft(3, '0')}_'
        'duattack0${i - 41}.ani',
  'ANI/Combate_Humano/humf_047_durun.ani',
  'ANI/Combate_Humano/humf_023_thready.ani',
  for (var i = 24; i <= 27; i++)
    'ANI/Combate_Humano/humf_${i.toString().padLeft(3, '0')}_'
        'thattack0${i - 23}.ani',
  'ANI/Combate_Humano/humf_029_thrun.ani',
  'ANI/Combate_Humano/humf_048_spready.ani',
  for (var i = 49; i <= 52; i++)
    'ANI/Combate_Humano/humf_${i.toString().padLeft(3, '0')}_'
        'spattack0${i - 48}.ani',
  'ANI/Combate_Humano/humf_054_sprun.ani',
];

Uint8List package({bool tamperHash = false, int transitions = 26}) {
  final clip = ani36();
  final files = <String, Uint8List>{};

  for (final path in combatFiles()) {
    files[path] = clip;
  }
  for (final path in [
    'ANI/Vuelo/PLAYER_STOP_FLY.ani',
    'ANI/Vuelo/PLAYER_FLY.ani',
    'ANI/Vuelo/PLAYER_STOP_FLY_SHIELD.ani',
    'ANI/Vuelo/PLAYER_FLY_SHIELD.ani',
  ]) {
    files[path] = clip;
  }

  final transitionRows = <Map<String, Object?>>[];
  final required = [
    'V3_TAKEOFF_NORMAL_NEUTRAL',
    'V3_TAKEOFF_NORMAL_SHIELD',
    'V3_LAND_NORMAL_NEUTRAL',
    'V3_LAND_NORMAL_SHIELD',
  ];
  for (var i = 0; i < transitions; i++) {
    final id = i < required.length
        ? required[i]
        : 'V3_TEST_${i.toString().padLeft(2, '0')}';
    final path = 'ANI/Transiciones/$id.ani';
    files[path] = clip;
    transitionRows.add({
      'id': id,
      'file': path,
      'kind': id.contains('TAKEOFF')
          ? 'takeoff'
          : id.contains('LAND')
          ? 'land'
          : 'blend',
      'profile': null,
      'shield': id.endsWith('SHIELD'),
      'duration': 1.0,
      'destinationPhase': 0.0,
      'bones': 36,
    });
  }

  files['transiciones.json'] = Uint8List.fromList(
    utf8.encode(jsonEncode({'transitions': transitionRows})),
  );
  files['mapa_combate_Character.json'] = Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'characters': {
          'humf': {'bones': 36},
        },
      }),
    ),
  );
  files['Pruebas/resultados_binarios.json'] = Uint8List.fromList(
    utf8.encode(jsonEncode({'passed': 91, 'failed': 0})),
  );
  files['Pruebas/resultados_numericos.json'] = Uint8List.fromList(
    utf8.encode(jsonEncode({'passed': 45, 'failed': 0})),
  );

  final lines = <String>[];
  for (final entry in files.entries) {
    var digest = sha256.convert(entry.value).toString();
    if (tamperHash && entry.key == 'ANI/Vuelo/PLAYER_FLY.ani') {
      digest = '0' * 64;
    }
    lines.add('$digest  ${entry.key}');
  }
  files['SHA256SUMS.txt'] = Uint8List.fromList(
    utf8.encode('${lines.join('\n')}\n'),
  );

  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(
      ArchiveFile.bytes('Shaiya_Vuelo_Combate_V3/${entry.key}', entry.value),
    );
  }
  return ZipEncoder().encodeBytes(archive);
}

void main() {
  test('verified V3 bundle exposes flight combat and 26 transitions', () {
    final bundle = FlightV3Bundle.decode(package());

    expect(bundle.normal.bones, hasLength(36));
    expect(bundle.hover.bones, hasLength(36));
    expect(bundle.flightShield.bones, hasLength(36));
    expect(bundle.combat.keys, containsAll(['on', 'du', 'th', 'sp']));
    expect(bundle.combat['on']!.attacks, hasLength(4));
    expect(bundle.transitions, hasLength(26));
    expect(bundle.transitions['V3_TAKEOFF_NORMAL_NEUTRAL'], isNotNull);
    expect(bundle.transitions['V3_LAND_NORMAL_SHIELD'], isNotNull);
    expect(bundle.evidence['binaryFailed'], 0);
    expect(bundle.evidence['numericFailed'], 0);
    expect(bundle.evidence['transitions'], 26);
  });

  test('bundle is compatible only with canonical humf 36-bone hierarchy', () {
    final bundle = FlightV3Bundle.decode(package());
    expect(bundle.compatibleWith('humf', bundle.normal), isTrue);
    expect(bundle.compatibleWith('humm', bundle.normal), isFalse);
  });

  test('tampered declared SHA-256 fails before animation use', () {
    expect(
      () => FlightV3Bundle.decode(package(tamperHash: true)),
      throwsFormatException,
    );
  });

  test('transition inventory must remain complete', () {
    expect(
      () => FlightV3Bundle.decode(package(transitions: 25)),
      throwsFormatException,
    );
  });
}
