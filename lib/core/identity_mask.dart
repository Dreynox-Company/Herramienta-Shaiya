import 'dart:typed_data';

import 'formats.dart';

/// View-only mask for whole costumes that embed a head/hood. Character identity
/// still comes from the chosen face and hair. Original DATA is never modified.
MeshData keepSelectedHead(MeshData costume, MeshData face) {
  if (face.joints.isEmpty || costume.joints.isEmpty || face.vertices == 0) {
    return costume;
  }
  final bones = <int>{};
  for (var i = 0; i < face.weights.length; i++) {
    if (face.weights[i] > .5) bones.add(face.joints[i]);
  }
  if (bones.isEmpty) return costume;
  final neck = face.minY - .025;
  bool head(int vertex) {
    if (costume.positions[vertex * 3 + 1] < neck) return false;
    var influence = 0.0;
    for (var k = 0; k < 4; k++) {
      if (bones.contains(costume.joints[vertex * 4 + k])) {
        influence += costume.weights[vertex * 4 + k];
      }
    }
    return influence > .75;
  }

  final visible = <int>[];
  for (var i = 0; i < costume.indices.length; i += 3) {
    final a = costume.indices[i],
        b = costume.indices[i + 1],
        c = costume.indices[i + 2];
    if (head(a) && head(b) && head(c)) continue;
    visible.addAll([a, b, c]);
  }
  if (visible.length == costume.indices.length) return costume;
  final result = MeshData(
    costume.positions,
    costume.normals,
    costume.uv,
    Uint16List.fromList(visible),
    costume.joints,
    costume.weights,
    costume.inverses,
    costume.source,
  );
  result.repairs.addAll(costume.repairs);
  result.repairs.add(
    '${(costume.indices.length - visible.length) ~/ 3} triángulos de cabeza integrada ocultos para conservar el rostro y cabello seleccionados.',
  );
  return result;
}
