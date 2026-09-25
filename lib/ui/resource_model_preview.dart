import 'package:flutter/material.dart';

import '../core/formats.dart';
import '../data/catalog.dart';
import '../data/library.dart';
import '../editor/model_reference.dart';
import 'editor_model_preview.dart';

/// Convert catalog records, never filenames guessed by similarity. Each native
/// row owns its texture reference; a set is the actual group of material rows.
ModelReference? resourceModelReference(
  Library library,
  Object? value, {
  Map<Slot, PartRecord>? setParts,
}) {
  if (value is PartRecord) {
    return ModelReference(
      value.label,
      [(value.meshPath, value.texturePath, value.raw.alpha)],
      sourcePath: value.tablePath,
      sourceOrdinal: value.raw.id,
    );
  }
  if (setParts != null) {
    return ModelReference('Conjunto $value', [
      for (final part in setParts.values)
        (part.meshPath, part.texturePath, part.raw.alpha),
    ]);
  }
  String? source;
  List<MaterialRecord> parts = [];
  Map<String, String> animations = {};
  String label = '';
  int? ordinal;
  if (value is WeaponRecord) {
    source = value.source;
    parts = [value];
    label = baseName(value.mesh);
    ordinal = value.id;
  } else if (value is CreatureRecord) {
    source = value.source;
    parts = value.parts.where((p) => !p.isNull).toList();
    label = value.name;
    ordinal = value.id;
    final root = directoryName(source);
    for (final animation in value.animations.entries) {
      if (animation.value.isEmpty) continue;
      final resolved = library.resolve(animation.value, [
        '$root/ani',
        root,
      ], uniqueFallback: false);
      if (resolved != null) animations[animation.key] = resolved;
    }
  }
  if (source == null) return null;
  final root = directoryName(source);
  return ModelReference(
    label,
    [
      for (final part in parts)
        (
          library.resolve(part.mesh, [
                '$root/3dc',
                '$root/3do',
              ], uniqueFallback: false) ??
              part.mesh,
          library.resolve(part.texture, ['$root/dds'], uniqueFallback: false) ??
              part.texture,
          part.alpha,
        ),
    ],
    animations: animations,
    sourcePath: source,
    sourceOrdinal: ordinal,
  );
}

Widget resourceModelPreview(
  BuildContext context,
  Library library,
  Object? value,
  ValueChanged<bool> onReady, {
  Map<Slot, PartRecord>? setParts,
}) {
  final model = resourceModelReference(library, value, setParts: setParts);
  if (model == null || model.parts.isEmpty) {
    return const Center(
      child: Text('Este recurso no tiene geometría asociada.'),
    );
  }
  return NativeModelPreview(
    library: library,
    model: model,
    onReadyChanged: onReady,
  );
}
