import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/extra_motion.dart';
import 'package:herramienta_shaiya/core/formats.dart';
import 'recovery_test.dart' show Writer;

Uint8List clip() {
  final b = Writer();
  b.i(0);
  b.i(30);
  b.short(1);
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
  return b.data.toBytes();
}

Map<String, Object?> manifest() {
  final b = clip(),
      c = {'data': base64Encode(b), 'sha256': sha256.convert(b).toString()};
  return {
    'schema': 1,
    'profiles': [
      {
        'archetype': 'humf',
        'sex': 'Masculino',
        'parents': [-1],
        'semantic': <String, int>{},
        'clips': {'hover': c, 'flight': c},
      },
    ],
  };
}

Uint8List encode(Map<String, Object?> m) =>
    Uint8List.fromList(gzip.encode(utf8.encode(jsonEncode(m))));
void main() {
  test('extras are isolated, sex and archetype must match', () {
    final x = ExtraMotionLibrary.decode(encode(manifest())),
        p = x.profiles['humf']!,
        native = ClipData.parse(clip(), 'original');
    expect(p.matches('humf', false, native), true);
    expect(p.matches('humf', true, native), false);
    expect(p.matches('humm', false, native), false);
    expect(native.source, 'original');
    expect(p.hover.source, startsWith('extra:'));
  });
  test('modifying clip checksum is detected before animation use', () {
    final m = manifest();
    ((m['profiles'] as List).first['clips']['hover'] as Map)['sha256'] =
        '0' * 64;
    expect(() => ExtraMotionLibrary.decode(encode(m)), throwsFormatException);
  });
  test(
    'different skeleton hierarchy cannot enter the supplemental library',
    () {
      final m = manifest();
      (m['profiles'] as List).first['parents'] = [0];
      expect(() => ExtraMotionLibrary.decode(encode(m)), throwsFormatException);
    },
  );
  test('a decompression bomb is bounded', () {
    final b = Uint8List.fromList(gzip.encode(Uint8List(9 * 1024 * 1024)));
    expect(() => ExtraMotionLibrary.decode(b), throwsFormatException);
  });
  test('supplemental head index cannot escape its own rig', () {
    for (final value in [-1, 0, 1, 999]) {
      final m = manifest();
      (m['profiles'] as List).first['semantic'] = {'head': value};
      expect(() => ExtraMotionLibrary.decode(encode(m)), throwsFormatException);
    }
  });
  test(
    'mounted supplement preserves ground ANI and validates its own checksum',
    () {
      final m = manifest();
      final clips = (m['profiles'] as List).first['clips'] as Map;
      clips['mounted_spear'] = Map<String, String>.from(clips['hover'] as Map);
      final p = ExtraMotionLibrary.decode(encode(m)).profiles['humf']!;
      expect(p.mounted['mounted_spear']!.source, 'extra:humf/mounted_spear');
      expect(p.hover.source, 'extra:humf/hover');
      (clips['mounted_spear'] as Map)['sha256'] = '0' * 64;
      expect(() => ExtraMotionLibrary.decode(encode(m)), throwsFormatException);
    },
  );
  test('catalogue rejects duplicate identities', () {
    final m = manifest();
    (m['profiles'] as List).add((m['profiles'] as List).first);
    expect(() => ExtraMotionLibrary.decode(encode(m)), throwsFormatException);
  });
}
