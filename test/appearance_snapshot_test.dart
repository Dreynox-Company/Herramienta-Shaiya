import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/data/appearance_snapshot.dart';
import 'package:herramienta_shaiya/data/file_save.dart';
import 'package:herramienta_shaiya/data/library.dart';

Map<String, dynamic> snapshotFixture() {
  Map<String, dynamic> transform() => {
    'position': {'x': .12, 'y': -.7, 'z': .9},
    'rotationDegrees': {'x': 170, 'y': -46.5, 'z': 90},
    'scale': {'x': .8, 'y': 1.2, 'z': 2.5},
    'mirror': {'x': true, 'y': false, 'z': true},
  };
  return {
    'schema': 3,
    'kind': 'shaiya-studio-appearance',
    'scene': {
      'schema': 1,
      'archetype': 'humf',
      'class': 'fighter',
      'parts': {
        'upper':
            'character/human/humf_upper.mlt#42#character/human/dds/humf_upper016.dds',
      },
      'weapon': 'item/01.itm#6',
      'shield': 'item/19.itm#2',
      'wing': 'character/wing/wing.mon#7',
      'mount': 'vehicle/vehicle_hu.mon#2',
      'flight': false,
    },
    'wingTransform': {...transform(), 'boneIndex': 4},
    'riderTransform': {...transform(), 'profile': 2},
    'wingAutoMotion': true,
    'resources': [
      {
        'path': 'character/wing/wing.mon',
        'bytes': 3,
        'sha256': FileSave.hash([1, 2, 3]),
      },
    ],
  };
}

void main() {
  test(
    'full appearance keeps every equipment category and independent XYZ/mirrors',
    () {
      final source = snapshotFixture();
      final decoded = AppearanceSnapshot.decode(
        utf8.encode(jsonEncode(source)),
      );
      expect(decoded, equals(source));
      final scene = decoded['scene'] as Map;
      for (final key in ['weapon', 'shield', 'wing', 'mount']) {
        expect(scene[key], isNotNull);
      }
    },
  );
  test('invalid transform, bool, bone and path fail before applying', () {
    for (final mutation in <void Function(Map<String, dynamic>)>[
      (v) => v['wingTransform']['scale']['x'] = 0,
      (v) => v['wingTransform']['rotationDegrees']['y'] = double.nan,
      (v) => v['riderTransform']['mirror']['y'] = 'false',
      (v) => v['wingTransform']['boneIndex'] = 4.5,
      (v) => v['riderTransform']['profile'] = 5,
      (v) => v['resources'][0]['path'] = '../wing.mon',
      (v) => v['resources'][0]['path'] = 'C:/wing.mon',
      (v) => v['resources'][0]['path'] = 'Character/Wing/Wing.MON',
      (v) => v['resources'][0]['sha256'] = 'not-a-hash',
      (v) => v['resources'].add(v['resources'][0]),
      (v) => v['resources'] = [],
      (v) => v['scene']['parts']['unknown'] = 'x',
    ]) {
      // A real input is decoded JSON. Deeply decode the fixture so a mutation
      // reaches our validator instead of failing in Map<String, double>.[]=.
      final fixture =
          jsonDecode(jsonEncode(snapshotFixture())) as Map<String, dynamic>;
      mutation(fixture);
      expect(() => AppearanceSnapshot.validate(fixture), throwsFormatException);
    }
  });
  test('resource fingerprint mismatch refuses another DATA', () async {
    final dir = await Directory.systemTemp.createTemp('appearance-hash-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/wing.mon');
    await file.writeAsBytes([1, 2, 3]);
    final library = Library(dir.path, false, {
      'character/wing/wing.mon': file.path,
    });
    await AppearanceSnapshot.verify(library, snapshotFixture());
    await file.writeAsBytes([3, 2, 1]);
    await expectLater(
      AppearanceSnapshot.verify(library, snapshotFixture()),
      throwsFormatException,
    );
  });
  test('save replaces with backup and leaves no partial file', () async {
    final dir = await Directory.systemTemp.createTemp('appearance-save-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/appearance.json'),
        original = snapshotFixture();
    await AppearanceSnapshot.save(file, original);
    final changed = snapshotFixture()..['wingAutoMotion'] = false;
    await AppearanceSnapshot.save(file, changed);
    expect(AppearanceSnapshot.decode(await file.readAsBytes()), changed);
    final files = await dir.list().toList();
    expect(files.where((f) => f.path.endsWith('.partial')), isEmpty);
    final backup = files.where((f) => f.path.endsWith('.bak')).single;
    expect(
      AppearanceSnapshot.decode(await File(backup.path).readAsBytes()),
      original,
    );
  });
  test('oversized input is rejected without decoding', () {
    expect(
      () =>
          AppearanceSnapshot.decode(Uint8List(AppearanceSnapshot.maxBytes + 1)),
      throwsFormatException,
    );
  });
}
