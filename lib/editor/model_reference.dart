import '../core/formats.dart';
import '../data/library.dart';
import 'catalog_document.dart';
import 'document.dart';

class ModelReference {
  final String label;
  final List<(String, String, int)> parts;
  final Map<String, String> animations;
  const ModelReference(this.label, this.parts, {this.animations = const {}});
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
                  root,
                  'item/3do',
                  'character/wing/3dc',
                ], uniqueFallback: true) ??
                e.$1,
            lib.resolve(e.$2, [
                  '$root/dds',
                  root,
                  'item/dds',
                  'character/wing/dds',
                ], uniqueFallback: true) ??
                e.$2,
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
        ], uniqueFallback: true);
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
        ),
      ];
    }
    final type = int.tryParse(v['itemtype'] ?? v['type'] ?? ''),
        model = int.tryParse(v['image'] ?? v['model'] ?? v['modelid'] ?? '');
    if (type != null &&
        model != null &&
        (type <= 15 || {19, 34, 69, 84}.contains(type))) {
      final family = type == 69
          ? 19
          : type == 84
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
        ),
      ];
    }
    final slot = switch (type) {
      16 || 31 => 'helmet',
      17 || 32 || 67 || 82 => 'upper',
      18 || 33 || 68 || 83 => 'lower',
      20 || 35 || 70 || 85 => 'hand',
      21 || 36 || 71 || 86 => 'foot',
      _ => null,
    };
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
          ], uniqueFallback: true);
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
          ),
        );
      }
      return out;
    }
    return [];
  }
}
