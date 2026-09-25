import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/native_wing_profile.dart';
import 'package:herramienta_shaiya/core/wing_position.dart';
import 'package:herramienta_shaiya/data/catalog.dart';
import 'package:herramienta_shaiya/data/library.dart';

import 'wing_position_test.dart' as fixtures;

class RefusingWingLibrary extends Library {
  int writes = 0;
  RefusingWingLibrary() : super('/not-written', false, {});
  @override
  Future<void> writeResource(String path, Uint8List bytes) async {
    writes++;
    throw StateError('fixture refuses write');
  }
}

void main() {
  test('all canonical native wing profiles are representable', () {
    for (final profile in WingPositionDocument.verifiedBaseline) {
      expect(() => validateNativeWingProfile(profile), returnsNormally);
    }
  });
  test('native export rejects fractional, non-finite and overflowing angles', () {
    final original = WingPositionDocument.verifiedResolve(0, 0, 0)!;
    for (final bad in [0.25, -12.5, double.nan, double.infinity, 2147483648.0]) {
      expect(() => validateNativeWingProfile(original.copyWith(rotX: bad)), throwsFormatException);
      expect(() => validateNativeWingProfile(original.copyWith(rotY: bad)), throwsFormatException);
      expect(() => validateNativeWingProfile(original.copyWith(rotZ: bad)), throwsFormatException);
    }
    expect(original.rotX, 170);
  });
  test('native offsets are finite float32 while translation may be fractional', () {
    final original = WingPositionDocument.verifiedResolve(0, 0, 0)!;
    expect(() => validateNativeWingProfile(original.copyWith(upDown: 0.125)), returnsNormally);
    for (final bad in [double.nan, double.infinity, 1e39]) {
      expect(() => validateNativeWingProfile(original.copyWith(upDown: bad)), throwsFormatException);
      expect(() => validateNativeWingProfile(original.copyWith(frontBack: bad)), throwsFormatException);
      expect(() => validateNativeWingProfile(original.copyWith(leftRight: bad)), throwsFormatException);
    }
    expect(() => validateNativeWingProfile(original.copyWith(boneIndex: -1)), throwsFormatException);
  });
  test('rejected native pose does not write or mutate the mounted document', () async {
    final library = RefusingWingLibrary();
    final catalog = Catalog(library);
    final document = WingPositionDocument.parse(fixtures.spreadsheetFixture(), WingPositionDocument.canonicalPath);
    catalog.wingPositions = document;
    catalog.wingPositionPath = WingPositionDocument.canonicalPath;
    final before = document.encode();
    await expectLater(catalog.saveWingPosition(document.resolve(0, 0, 0)!.copyWith(rotX: 12.5)), throwsFormatException);
    expect(library.writes, 0);
    expect(catalog.wingPositions!.encode(), before);
  });
  test('late write failure preserves every mounted wing profile', () async {
    final library = RefusingWingLibrary();
    final catalog = Catalog(library);
    final document = WingPositionDocument.parse(fixtures.spreadsheetFixture(), WingPositionDocument.canonicalPath);
    catalog.wingPositions = document;
    catalog.wingPositionPath = WingPositionDocument.canonicalPath;
    final before = document.encode();
    await expectLater(catalog.saveWingPosition(document.resolve(0, 0, 0)!.copyWith(rotX: 12)), throwsStateError);
    expect(library.writes, 1);
    expect(identical(catalog.wingPositions, document), isTrue);
    expect(catalog.wingPositions!.encode(), before);
  });
}
