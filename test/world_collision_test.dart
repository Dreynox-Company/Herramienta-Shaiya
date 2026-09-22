import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' as v;
import 'package:herramienta_shaiya/core/formats.dart';
import 'package:herramienta_shaiya/render/world_collision.dart';

SmodCollisionMesh wallMesh() => SmodCollisionMesh(
      <v.Vector3>[
        v.Vector3(0, 0, 0),
        v.Vector3(0, 2, 0),
        v.Vector3(0, 2, 2),
        v.Vector3(0, 0, 2),
      ],
      Uint16List.fromList(<int>[0, 1, 2, 0, 2, 3]),
    );

void main() {
  test('vertical SMOD collision blocks character capsule', () {
    final index = WorldCollisionIndex();
    index.addMesh(wallMesh(), v.Matrix4.identity());

    expect(index.triangleCount, 2);
    expect(index.blocksPosition(.10, 0, 1, radius: .25), isTrue);
    expect(index.blocksPosition(.70, 0, 1, radius: .25), isFalse);
  });

  test('SMOD collision respects world instance transform', () {
    final index = WorldCollisionIndex();
    final matrix = v.Matrix4.identity()..setTranslation(v.Vector3(5, 0, -3));
    index.addMesh(wallMesh(), matrix);

    expect(index.blocksPosition(5.1, 0, -2, radius: .25), isTrue);
    expect(index.blocksPosition(.1, 0, 1, radius: .25), isFalse);
  });

  test('walkable horizontal triangles are excluded', () {
    final mesh = SmodCollisionMesh(
      <v.Vector3>[
        v.Vector3(0, 0, 0),
        v.Vector3(2, 0, 0),
        v.Vector3(0, 0, 2),
      ],
      Uint16List.fromList(<int>[0, 1, 2]),
    );
    final index = WorldCollisionIndex();
    index.addMesh(mesh, v.Matrix4.identity());

    expect(index.triangleCount, 0);
    expect(index.blocksPosition(.2, 0, .2), isFalse);
  });

  test('vertical overlap is required before wall blocks', () {
    final index = WorldCollisionIndex();
    index.addMesh(wallMesh(), v.Matrix4.identity());

    expect(index.blocksPosition(.1, 5, 1, radius: .25), isFalse);
  });
}
