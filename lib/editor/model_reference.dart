import '../core/formats.dart';
import '../core/equipment_rules.dart';
import '../data/library.dart';
import 'catalog_document.dart';
import 'document.dart';

class ModelReference {
  final String label;
  final List<(String, String, int)> parts;
  final Map<String, String> animations;
  final String? sourcePath;
  final int? sourceOrdinal;
  const ModelReference(
    this.label,
    this.parts, {
    this.animations = const {},
    this.sourcePath,
    this.sourceOrdinal,
  });
}

class ModelReferences {
  static Future<List<ModelReference>> resolve(
    Library lib,
    EditDocument d,
    int row,
  ) async {
    final v = {
      for (final f in d.fields(row)) f.spec.name.toLowerCase(): d.read(f),
    };
    List<(String, String, int)> locate(
      List<(String, String, int)> parts,
      String source,
    ) {
      final dir = directoryName(source),
          root = dir.endsWith('/mlt') ? directoryName(dir) : dir;
      return [
        for (final e in parts)
          (
            lib.resolve(e.$1, [
                  '$root/3dc',
                  '$root/3do',
                ], uniqueFallback: false) ??
                e.$1,
            lib.resolve(e.$2, ['$root/dds'], uniqueFallback: false) ?? e.$2,
            e.$3,
          ),
      ];
    }

    if (d is CatalogDocument) {
      final parts = d.materials(row);
      if (parts.isEmpty) return [];
      final anim = <String, String>{};
      for (final f
          in d.fields(row).where((f) => f.spec.name.startsWith('Animation.'))) {
        final name = d.read(f);
        final path = lib.resolve(name, [
          '${directoryName(d.path)}/ani',
          directoryName(d.path),
        ], uniqueFallback: false);
        if (path != null) {
          final key = f.spec.name.substring(10);
          const labels = {
            'Walk': 'Caminar',
            'Run': 'Correr',
            'Attack1': 'Ataque 1',
            'Attack2': 'Ataque 2',
            'Attack3': 'Ataque 3',
            'Damage': 'Daño',
            'Death': 'Caída',
            'Idle': 'Respirar',
            'Stop': 'Respirar',
          };
          anim[labels[key] ?? key] = path;
        }
      }
      return [
        ModelReference(
          'Registro original #${d.rows[row].ordinal}',
          locate(parts, d.path),
          animations: anim,
          sourcePath: d.path,
          sourceOrdinal: d.rows[row].ordinal,
        ),
      ];
    }
    final type = int.tryParse(v['itemtype'] ?? v['type'] ?? ''),
        model = int.tryParse(v['image'] ?? v['model'] ?? v['modelid'] ?? '');
    final weaponFamily = type == null ? 0 : weaponFamilyForItemType(type);
    if (type != null &&
        model != null &&
        (weaponFamily > 0 || equipmentSlotsForItemType(type).contains(6))) {
      final family = weaponFamily > 0
          ? weaponFamily
          : const {69, 75}.contains(type)
          ? 19
          : const {84, 90}.contains(type)
          ? 34
          : type;
      final path = 'item/${family.toString().padLeft(2, '0')}.itm';
      if (!lib.files.containsKey(path)) return [];
      final rows = readItm(await lib.read(path), path);
      if (model < 0 || model >= rows.length) return [];
      final record = rows[model];
      return [
        ModelReference(
          '$path · modelo $model',
          locate([(record.mesh, record.texture, record.alpha)], path),
          sourcePath: path,
          sourceOrdinal: model,
        ),
      ];
    }

    if (type == wingItemType && model != null) {
      final out = <ModelReference>[];
      for (final path in lib.files.keys.where(
        (p) => p.startsWith('character/wing/') && p.endsWith('.mon'),
      )) {
        final rows = readMon(await lib.read(path), path);
        if (model < 0 || model >= rows.length) continue;
        final record = rows[model];
        if (!record.parts.any((p) => !p.isNull)) continue;
        final root = directoryName(path);
        final animations = <String, String>{};
        for (final animation in record.animations.entries) {
          if (animation.value.isEmpty) continue;
          final resolved = lib.resolve(animation.value, [
            '$root/ani',
            root,
          ], uniqueFallback: false);
          if (resolved != null) animations[animation.key] = resolved;
        }
        out.add(
          ModelReference(
            'Alas · ItemType $wingItemType · Image $model · ${baseName(path)}',
            locate(
              record.parts
                  .where((p) => !p.isNull)
                  .map((p) => (p.mesh, p.texture, p.alpha))
                  .toList(),
              path,
            ),
            animations: animations,
            sourcePath: path,
            sourceOrdinal: model,
          ),
        );
      }
      return out;
    }

    // Mount families can share Image. Preserve every matching MON source so
    // the user chooses a family explicitly; never silently select the first.
    if (model != null && const {42, 125, 120, 123}.contains(type)) {
      final mount = type == 42 || type == 125;
      final out = <ModelReference>[];
      for (final path in lib.files.keys.where(
        (p) => mount
            ? p.startsWith('vehicle/') && p.endsWith('.mon')
            : p.startsWith('pet/') && p.endsWith('.mon'),
      )) {
        final records = readMon(await lib.read(path), path);
        if (model < 0 || model >= records.length) continue;
        final record = records[model];
        if (!record.parts.any((p) => !p.isNull)) continue;
        final root = directoryName(path);
        final animations = <String, String>{};
        for (final animation in record.animations.entries) {
          if (animation.value.isEmpty) continue;
          final resolved = lib.resolve(animation.value, [
            '$root/ani',
            root,
          ], uniqueFallback: false);
          if (resolved != null) animations[animation.key] = resolved;
        }
        out.add(
          ModelReference(
            '$path · Image $model',
            locate(
              record.parts
                  .where((p) => !p.isNull)
                  .map((p) => (p.mesh, p.texture, p.alpha))
                  .toList(),
              path,
            ),
            animations: animations,
            sourcePath: path,
            sourceOrdinal: model,
          ),
        );
      }
      return out;
    }

    final equipmentSlots = type == null
        ? const <int>[]
        : equipmentSlotsForItemType(type);
    final slot = equipmentSlots.contains(0)
        ? 'helmet'
        : equipmentSlots.contains(1)
        ? 'upper'
        : equipmentSlots.contains(2)
        ? 'lower'
        : equipmentSlots.contains(3)
        ? 'hand'
        : equipmentSlots.contains(4)
        ? 'foot'
        : null;
    if (slot != null && model != null) {
      final out = <ModelReference>[];
      for (final path in lib.files.keys.where(
        (p) => p.startsWith('character/') && p.endsWith('_$slot.mlt'),
      )) {
        final rows = readMlt(await lib.read(path), path);
        if (model < 0 || model >= rows.length) continue;
        final r = rows[model];
        if (r.isNull) continue;
        out.add(
          ModelReference(
            baseName(path).replaceAll('.mlt', '').toUpperCase(),
            locate([(r.mesh, r.texture, r.alpha)], path),
            sourcePath: path,
            sourceOrdinal: model,
          ),
        );
      }
      return out;
    }
    if (model != null &&
        (d.path.toLowerCase().contains('monster') ||
            d.path.toLowerCase().contains('npcquest'))) {
      final root = d.path.toLowerCase().contains('npcquest')
          ? 'npc'
          : 'monster';
      final out = <ModelReference>[];
      for (final p in lib.files.keys.where(
        (p) => p.startsWith('$root/') && p.endsWith('.mon'),
      )) {
        final rows = readMon(await lib.read(p), p);
        if (model < 0 || model >= rows.length) continue;
        final r = rows[model];
        final animations = <String, String>{};
        for (final a in r.animations.entries) {
          final path = lib.resolve(a.value, [
            '$root/ani',
          ], uniqueFallback: false);
          if (path != null) animations[a.key] = path;
        }
        out.add(
          ModelReference(
            '${baseName(p)} #$model',
            locate(
              r.parts.map((p) => (p.mesh, p.texture, p.alpha)).toList(),
              p,
            ),
            animations: animations,
            sourcePath: p,
            sourceOrdinal: model,
          ),
        );
      }
      return out;
    }
    return [];
  }
}
