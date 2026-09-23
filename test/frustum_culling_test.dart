import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' as v;
import 'package:herramienta_shaiya/render/frustum_culling.dart';

void main() {
  test('identity clip frustum keeps origin and rejects distant AABB', () {
    final frustum = CameraFrustum.fromViewProjection(v.Matrix4.identity());

    expect(
      frustum.intersectsAabb(
        RenderAabb.fromCenterExtent(
          v.Vector3.zero(),
          v.Vector3.all(.25),
        ),
      ),
      isTrue,
    );
    expect(
      frustum.intersectsAabb(
        RenderAabb.fromCenterExtent(
          v.Vector3(5, 0, 0),
          v.Vector3.all(.25),
        ),
      ),
      isFalse,
    );
  });

  test('intersecting AABB is kept conservatively', () {
    final frustum = CameraFrustum.fromViewProjection(v.Matrix4.identity());
    expect(
      frustum.intersectsAabb(
        RenderAabb(
          v.Vector3(.8, -.2, -.2),
          v.Vector3(1.2, .2, .2),
        ),
      ),
      isTrue,
    );
  });
}
