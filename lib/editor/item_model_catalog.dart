import '../core/equipment_rules.dart';
import '../data/item_workspace.dart';
import '../data/library.dart';
import 'catalog_document.dart';
import 'model_reference.dart';
import 'workbench_model.dart';

/// A visual choice is a native material/MON ordinal plus its whole texture
/// association. The display name, set suffix, Icon and TypeId are never IDs.
class ItemModelChoice {
  final ModelReference model;
  final String name;
  final int row;
  final List<String> missing;
  final Map<String, String> fields;
  const ItemModelChoice({required this.model, required this.name,
    required this.row, required this.fields, this.missing = const []});
  String get source => model.sourcePath!;
  int get ordinal => model.sourceOrdinal!;
  String get key => '$source#$ordinal';
  bool get available => model.parts.isNotEmpty && missing.isEmpty;
  String get searchText => foldedSearch('$name $source Image $ordinal '
    '${model.parts.map((p) => '${p.$1} ${p.$2}').join(' ')}');
}

class ItemModelCatalog {
  final List<ItemModelChoice> choices;
  final List<String> warnings;
  final int revision;
  const ItemModelCatalog(this.choices, this.warnings, this.revision);

  static bool supports(int type) => pathsFor(const [], type).isNotEmpty ||
    weaponFamilyForItemType(type) > 0 ||
    equipmentSlotsForItemType(type).any((s) => s >= 0 && s <= 6) ||
    const {121, 42, 125, 120, 123}.contains(type);

  /// Same native path families used by ModelReferences.resolve. A consumable
  /// is not given an unrelated weapon or NPC mesh because Image is nonzero.
  static List<String> pathsFor(Iterable<String> paths, int type) {
    final slots = equipmentSlotsForItemType(type);
    final weapon = weaponFamilyForItemType(type);
    if (weapon > 0 || slots.contains(6)) {
      final family = weapon > 0 ? weapon : const {69, 75}.contains(type)
        ? 19 : const {84, 90}.contains(type) ? 34 : type;
      final path = 'item/${family.toString().padLeft(2, '0')}.itm';
      return paths.contains(path) ? [path] : [];
    }
    String? prefix;
    if (type == wingItemType) prefix = 'character/wing/';
    if (const {42, 125}.contains(type)) prefix = 'vehicle/';
    if (const {120, 123}.contains(type)) prefix = 'pet/';
    if (prefix != null) return paths.where((p) =>
      p.startsWith(prefix!) && p.endsWith('.mon')).toList()..sort();
    final slot = slots.contains(0) ? 'helmet' : slots.contains(1) ? 'upper'
      : slots.contains(2) ? 'lower' : slots.contains(3) ? 'hand'
      : slots.contains(4) ? 'foot' : null;
    if (slot == null) return [];
    return paths.where((p) => p.startsWith('character/') &&
      p.endsWith('_$slot.mlt')).toList()..sort();
  }

  static Future<ItemModelCatalog> load(ItemWorkspace workspace, {
    ItemEntry? item, CatalogDocument? document,
  }) async {
    if ((item == null) == (document == null)) {
      throw ArgumentError('Selecciona un ítem o un catálogo nativo.');
    }
    final revision = workspace.revision;
    final paths = document == null
      ? pathsFor(workspace.preview.files.keys, item!.type) : [document.path];
    final names = <int, List<String>>{};
    if (item != null) {
      for (final candidate in workspace.items) {
        if (candidate.type == item.type && candidate.hasName) {
          final list = names.putIfAbsent(candidate.image, () => []);
          if (!list.contains(candidate.name)) list.add(candidate.name);
        }
      }
    }
    final out = <ItemModelChoice>[], warnings = <String>[];
    for (final path in paths) {
      try {
        final opened = await workspace.openDocument(path);
        if (opened is! CatalogDocument) continue;
        for (var row = 0; row < opened.rows.length; row++) {
          if (!const {'Material', 'Equipo', 'Modelo animado'}
              .contains(opened.rows[row].kind)) continue;
          final models = await ModelReferences.resolve(workspace.preview, opened, row);
          for (final model in models) {
            if (model.parts.isEmpty) continue;
            final missing = <String>{
              for (final part in model.parts)
                for (final p in [part.$1, part.$2])
                  if (p.isEmpty || !workspace.preview.files.containsKey(p)) p,
            }.toList();
            final labels = names[model.sourceOrdinal] ?? const <String>[];
            final resource = model.parts.map((p) =>
              '${baseName(p.$1)} + ${baseName(p.$2)}').join(' · ');
            out.add(ItemModelChoice(model: model,
              name: '${labels.isEmpty ? 'Recurso sin nombre de ítem' : labels.join(' / ')} · $resource',
              row: row, missing: missing,
              fields: {for (final f in opened.fields(row)) f.spec.name: opened.read(f)}));
          }
        }
      } catch (error) {
        warnings.add('$path: $error');
      }
    }
    if (workspace.sourceChanged || workspace.revision != revision) {
      throw StateError('La sesión cambió mientras se cargaban los modelos. Vuelve a abrir el selector.');
    }
    return ItemModelCatalog(List.unmodifiable(out), List.unmodifiable(warnings), revision);
  }
}
