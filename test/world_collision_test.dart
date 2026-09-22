import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' as v;

import 'package:herramienta_shaiya/core/formats.dart';
import 'package:herramienta_shaiya/core/world_collision.dart';

void main() {
  group('WorldCollisionField', () {
    test('blocks a character crossing a vertical SMOD wall', () {
      final wall = WorldCollisionTriangle(
        v.Vector3(0, 0, -1),
        v.Vector3(0, 2, -1),
        v.Vector3(0, 0, 1),
      );
      final field = WorldCollisionField([wall]);

      expect(field.blocks(.1, 0, -.2, radius: .25), isTrue);
      expect(field.blocks(1.0, 0, -.2, radius: .25), isFalse);
      expect(
        field.allowsMove(
          fromX: -1,
          fromY: 0,
          fromZ: -.2,
          toX: 1,
          toY: 0,
          toZ: -.2,
          radius: .25,
        ),
        isFalse,
      );
    });

    test('does not treat horizontal floor triangles as walls', () {
      final floor = WorldCollisionTriangle(
        v.Vector3(-2, 0, -2),
        v.Vector3(2, 0, -2),
        v.Vector3(0, 0, 2),
      );
      final field = WorldCollisionField([floor]);

      expect(field.blocks(0, 0, 0), isFalse);
      expect(
        field.allowsMove(
          fromX: -1,
          fromY: 0,
          fromZ: 0,
          toX: 1,
          toY: 0,
          toZ: 0,
        ),
        isTrue,
      );
    });

    test('transforms SMOD collision vertices with the WLD instance matrix', () {
      final mesh = SmodCollisionMesh(
        [
          v.Vector3(0, 0, 0),
          v.Vector3(0, 2, 0),
          v.Vector3(0, 0, 1),
        ],
        Uint16List.fromList([0, 1, 2]),
      );
      final matrix = v.Matrix4.identity()..setTranslationRaw(12, 3, -7);
      final triangles = transformSmodCollisions([mesh], matrix);

      expect(triangles, hasLength(1));
      expect(triangles.single.a.x, closeTo(12, 1e-6));
      expect(triangles.single.a.y, closeTo(3, 1e-6));
      expect(triangles.single.a.z, closeTo(-7, 1e-6));
      expect(triangles.single.c.z, closeTo(-6, 1e-6));
    });
  });
}
