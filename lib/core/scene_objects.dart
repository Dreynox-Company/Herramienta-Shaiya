import 'dart:typed_data';

import 'formats.dart';

/// Static surfaces and collision hulls are independent lists in SMOD.
class SmodResource {
  final List<StaticPart> surfaces;
  final List<MeshData> collisions;
  SmodResource(this.surfaces, this.collisions);
  static SmodResource parse(Uint8List bytes, String source) {
    final r = Bin(bytes, source);
    r.skip(40);
    final surfaces = <StaticPart>[], collisions = <MeshData>[];
    final count = r.count(10000);
    for (var i = 0; i < count; i++) {
      final texture = r.str();
      surfaces.add(StaticPart(texture, MeshData.rigid(r, boneField: true)));
    }
    if (r.remaining == 0) return SmodResource(surfaces, collisions);
    r.skip(24);
    final hulls = r.count(10000);
    for (var i = 0; i < hulls; i++) {
      final vertices = r.count(65536);
      r.need(vertices * 12);
      final p = Float32List(vertices * 3);
      for (var j = 0; j < p.length; j++) {
        p[j] = r.f32();
      }
      final index = MeshData.readIndices(r, vertices);
      collisions.add(
        MeshData(
          p,
          Float32List(p.length),
          Float32List(vertices * 2),
          index,
          Uint8List(0),
          Float32List(0),
          [],
          source,
        ),
      );
    }
    r.meshEnd();
    return SmodResource(surfaces, collisions);
  }
}

class VertexAnimationPart {
  final StaticPart surface;
  final List<Float32List> frames, uvFrames;
  VertexAnimationPart(this.surface, this.frames, this.uvFrames);
}

class VertexAnimation {
  final List<VertexAnimationPart> parts;
  final int frames;
  VertexAnimation(this.parts, this.frames);
  static VertexAnimation parse(Uint8List bytes, String source) {
    final r = Bin(bytes, source);
    r.skip(40);
    final meshes = r.count(10000), frames = r.count(10000);
    r.i32();
    if (frames == 0) r.fail('Animación de vértices sin fotogramas.');
    final out = <VertexAnimationPart>[];
    for (var i = 0; i < meshes; i++) {
      final texture = r.str(), nf = r.count(2000000);
      r.need(nf * 6);
      final indices = Uint16List(nf * 3);
      for (var j = 0; j < indices.length; j++) {
        indices[j] = r.u16();
      }
      final nv = r.count(65536);
      r.need(frames * nv * 36);
      if (indices.any((n) => n >= nv)) r.fail('Índice VANI fuera de la malla.');
      final positions = <Float32List>[], uvs = <Float32List>[];
      for (var frame = 0; frame < frames; frame++) {
        final p = Float32List(nv * 3), uv = Float32List(nv * 2);
        for (var vertex = 0; vertex < nv; vertex++) {
          for (var k = 0; k < 3; k++) {
            p[vertex * 3 + k] = r.f32();
          }
          r.skip(16);
          uv[vertex * 2] = r.f32();
          uv[vertex * 2 + 1] = r.f32();
        }
        positions.add(p);
        uvs.add(uv);
      }
      final mesh = MeshData(
        positions.first,
        Float32List(nv * 3),
        uvs.first,
        indices,
        Uint8List(0),
        Float32List(0),
        [],
        source,
      );
      out.add(VertexAnimationPart(StaticPart(texture, mesh), positions, uvs));
    }
    r.skip(28);
    r.meshEnd();
    return VertexAnimation(out, frames);
  }
}
