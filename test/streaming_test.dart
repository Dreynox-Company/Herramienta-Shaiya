import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:three_js/three_js.dart' as t;
import 'package:herramienta_shaiya/core/formats.dart';
import 'package:herramienta_shaiya/core/world_resources.dart';
import 'package:herramienta_shaiya/data/library.dart';
import 'package:herramienta_shaiya/render/world_builder.dart';
import 'package:herramienta_shaiya/render/studio_scene.dart';

WorldResource terrain(int size) {
  final n = (size ~/ 2 + 1) * (size ~/ 2 + 1), b = BytesBuilder();
  void u(int x) =>
      b.add((ByteData(4)..setUint32(0, x, Endian.little)).buffer.asUint8List());
  void f(double x) => b.add(
    (ByteData(4)..setFloat32(0, x, Endian.little)).buffer.asUint8List(),
  );
  void str(String x) {
    b.add(x.codeUnits);
    b.add(Uint8List(256 - x.length));
  }

  b.add('FLD\x00'.codeUnits);
  u(size);
  final heights = ByteData(n * 2);
  for (var i = 0; i < n; i++) {
    heights.setUint16(i * 2, 10000, Endian.little);
  }
  b.add(heights.buffer.asUint8List());
  b.add(Uint8List(n));
  u(1);
  str('ground.dds');
  f(4);
  str('');
  str('');
  b.add(Uint8List(56));
  return WorldResource.parse(b.toBytes(), 'fixture.wld');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'real chunk lifecycle loads only proximity and releases resources after travel',
    () async {
      var created = 0, released = 0;
      Future<RenderPart> factory(
        MeshData mesh,
        String path, {
        bool opaque = false,
      }) async {
        created++;
        final geo = t.BufferGeometry(),
            pos = t.Float32BufferAttribute.fromList(mesh.positions.toList(), 3),
            texture = t.Texture();
        geo.setAttributeFromString('position', pos);
        geo.setIndex(mesh.indices.toList());
        return RenderPart(
          mesh,
          t.Mesh(geo, t.MeshBasicMaterial()),
          pos,
          texture,
          releaseTexture: () {
            released++;
            texture.dispose();
          },
        );
      }

      final lib = Library('', false, {'terrain/ground.dds': 'unused'}),
          builder = WorldBuilder(lib, factory, (_) {}, () => false);
      final world = await builder.build(terrain(2048), quality: 0);
      await world.settle();
      expect(world.residentChunks, lessThan(35));
      expect(world.residentChunks, greaterThan(4));
      expect(created, world.parts.length);
      expect(world.floorAt(world.spawn.x, world.spawn.z, 0), 0);
      final firstCreated = created;
      await world.ensureAt(1850, 1850);
      await world.settle();
      expect(world.releasedChunks, greaterThan(0));
      expect(released, greaterThan(0));
      expect(world.floorAt(1850, 1850, 0), 0);
      expect(world.floorAt(world.spawn.x, world.spawn.z, 0), isNull);
      expect(created, greaterThan(firstCreated));
      expect(created - released, world.parts.length);
      final resident = world.residentChunks;
      await expectLater(world.ensureAt(-100, -100), throwsFormatException);
      expect(world.residentChunks, resident);
      expect(world.floorAt(1850, 1850, 0), 0);
      await world.ensureAt(1851, 1850);
      await world.settle();
      expect(world.residentChunks, resident);
      world.dispose();
      world.dispose();
      expect(released, created);
      expect(world.parts, isEmpty);
      expect(world.instances, isEmpty);
      expect(world.floors.ownedGroups, 0);
    },
  );
  test(
    'stream load failure keeps diagnostics and never treats missing floor as traversable',
    () async {
      final builder = WorldBuilder(
        Library('', false, {'terrain/ground.dds': 'unused'}),
        (mesh, path, {opaque = false}) async =>
            throw const FormatException('missing material'),
        (_) {},
        () => false,
      );
      await expectLater(builder.build(terrain(128)), throwsFormatException);
    },
  );
  test(
    'cancellation releases in-flight geometry and cannot publish a later scene',
    () async {
      var canceled = false, created = 0, released = 0;
      Future<RenderPart> factory(
        MeshData mesh,
        String path, {
        bool opaque = false,
      }) async {
        created++;
        canceled = true;
        final pos = t.Float32BufferAttribute.fromList(
              mesh.positions.toList(),
              3,
            ),
            geo = t.BufferGeometry()..setAttributeFromString('position', pos),
            tex = t.Texture();
        return RenderPart(
          mesh,
          t.Mesh(geo, t.MeshBasicMaterial()),
          pos,
          tex,
          releaseTexture: () {
            released++;
            tex.dispose();
          },
        );
      }

      await expectLater(
        WorldBuilder(
          Library('', false, {'terrain/ground.dds': 'unused'}),
          factory,
          (_) {},
          () => canceled,
        ).build(terrain(128)),
        throwsFormatException,
      );
      expect(created, greaterThan(0));
      expect(released, created);
    },
  );
}
