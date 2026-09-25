"""Readable one-time integration for the R25 Items workbench on the R24 branch.
No DATA assets, executable clients or secrets are written to the repository.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def edit(path, changes):
    p = ROOT / path
    value = p.read_text()
    for before, after in changes:
        if after in value:
            continue
        if value.count(before) != 1:
            raise RuntimeError(f'Unexpected source anchor: {path}: {before[:90]!r}')
        value = value.replace(before, after, 1)
    p.write_text(value)

def main():
    marker = ROOT / '.studio-r25-items-applied'
    if marker.exists():
        return
    edit('lib/data/equipment_registry.dart', [("int get level => values['reqlv'] ?? 0;", "int get level => values['level'] ?? values['reqlv'] ?? 0;")])
    edit('lib/editor/model_reference.dart', [
        ("import '../core/formats.dart';", "import '../core/formats.dart';\nimport '../core/item_icon_layout.dart';"),
        ('  final Map<String, String> animations;', '  final Map<String, String> animations;\n  final String? sourcePath;\n  final int? sourceOrdinal;'),
        ('const ModelReference(this.label, this.parts, {this.animations = const {}});',
         'const ModelReference(this.label, this.parts, {this.animations = const {}, this.sourcePath, this.sourceOrdinal});'),
        ('          animations: anim,', '          animations: anim, sourcePath: d.path, sourceOrdinal: d.rows[row].ordinal,'),
        ('(weaponFamily > 0 || {19, 34, 69, 84}.contains(type))', '(weaponFamily > 0 || equipmentSlotsForItemType(type).contains(6))'),
        ('''      final family = weaponFamily > 0
          ? weaponFamily
          : type == 69
          ? 19
          : type == 84
          ? 34
          : type;''', '''      final family = weaponFamily > 0 ? weaponFamily : ItemIconLayout.family(type);'''),
        ('          locate([(record.mesh, record.texture, record.alpha)], path),', '          locate([(record.mesh, record.texture, record.alpha)], path),\n          sourcePath: path, sourceOrdinal: model,'),
        ('    if (type == wingItemType && model != null) {', "    if ((type == wingItemType || type == 122 || type == 42 || type == 125) && model != null) {\n      final rootPrefix = (type == 42 || type == 125) ? 'vehicle/' : 'character/wing/';"),
        ("(p) => p.startsWith('character/wing/') && p.endsWith('.mon'),", "(p) => p.startsWith(rootPrefix) && p.endsWith('.mon'),"),
        ("            'Alas · ItemType $wingItemType · Image $model · ${baseName(path)}',", "            '${type == 42 || type == 125 ? 'Montura' : 'Alas'} · ItemType $type · Image $model · ${baseName(path)}',"),
        ('''              path,
            ),
            animations: animations,''', '''              path,
            ),
            animations: animations, sourcePath: path, sourceOrdinal: model,'''),
        ('            locate([(r.mesh, r.texture, r.alpha)], path),', '            locate([(r.mesh, r.texture, r.alpha)], path),\n            sourcePath: path, sourceOrdinal: model,'),
    ])
    edit('lib/ui/editor_icons.dart', [
        ("import '../core/textures.dart';", "import '../core/textures.dart';\nimport '../core/item_icon_layout.dart';"),
        ('  final bool sheet;', '  final bool sheet;\n  final int? columns, rows;\n  final int pageBase;'),
        ('const EditorIconRef(this.path, this.index, {this.sheet = true});',
         'const EditorIconRef(this.path, this.index, {this.sheet = true, this.columns, this.rows, this.pageBase = 0});'),
        ('if (closed || cache.length > 64) return null;', 'if (closed) return null;'),
    ])
    p=ROOT/'lib/ui/editor_icons.dart';v=p.read_text();start=v.index('      final number = type.toString()');end=v.index('\n    if (domain == EditorDomain.skills', start)
    v=v[:start]+'''      final layout = ItemIconLayout.resolve(type, index);
      if (layout == null || !layout.inBounds) return null;
      for (final ext in ['dds', 'tga']) {
        final path = 'interface/icon/${layout.stem}.$ext';
        if (library.files.containsKey(path)) return EditorIconRef(path, layout.tile,
          columns: layout.columns, rows: layout.rows, pageBase: layout.pageBase);
      }
    }
'''+v[end:];p.write_text(v)
    edit('lib/ui/editor_icons.dart',[
        ('          ? fallback\n          : FutureBuilder', "          ? Tooltip(message: 'Icono ausente, fuera de rango o tipo no soportado por ps0032. No se sustituye por otro objeto.', child: fallback)\n          : FutureBuilder"),
        ('                final image = s.data;', '                final image = s.connectionState == ConnectionState.done ? s.data : null;'),
        ('final columns = image.width ~/ 32, rows = image.height ~/ 32;', 'final columns = ref.columns ?? image.width ~/ 32, rows = ref.rows ?? image.height ~/ 32;'),
        ("message: '${ref.path} · icono ${ref.index}',", "message: '${ref.path} · Icon ${ref.index + ref.pageBase} · celda ${ref.index} · ps0032',"),
        ('_IconPainter(image, ref.index, columns)', '_IconPainter(image, ref.index, columns, rows)'),
        ('final int index, columns;', 'final int index, columns, rows;'),
        ('_IconPainter(this.image, this.index, this.columns);', '_IconPainter(this.image, this.index, this.columns, this.rows);'),
        ('''        (index % columns) * 32.0,
        (index ~/ columns) * 32.0,
        32,
        32,''','''        (index % columns) * image.width / columns,
        (index ~/ columns) * image.height / rows,
        image.width / columns,
        image.height / rows,'''),
        ('o.image != image || o.index != index;', 'o.image != image || o.index != index || o.columns != columns || o.rows != rows;'),
    ])
    edit('lib/ui/editor_pickers.dart', [
        ('_IconDialog(image: image, path: ref.path, current: current)', '_IconDialog(image: image, path: ref.path, current: current - ref.pageBase, ref: ref)'),
        ('  final int current;\n  const _IconDialog', '  final int current;\n  final EditorIconRef ref;\n  const _IconDialog'),
        ('    required this.path,\n    required this.current,\n  });', '    required this.path,\n    required this.current,\n    required this.ref,\n  });'),
        ('''final cols = widget.image.width ~/ 32,
        count = cols * (widget.image.height ~/ 32);''', '''final cols = widget.ref.columns ?? widget.image.width ~/ 32,
        rows = widget.ref.rows ?? widget.image.height ~/ 32,
        count = cols * rows;'''),
        ('IconTilePainter(widget.image, i, cols)', 'IconTilePainter(widget.image, i, cols, rows: rows)'),
        ("                          '$i',", "                          '${i + widget.ref.pageBase}',"),
        ('onPressed: selected < 0 || selected >= count\n              ? null\n              : () => Navigator.pop(context, selected),', 'onPressed: selected < 0 || selected >= count || (widget.ref.pageBase > 0 && selected + widget.ref.pageBase > 255)\n              ? null\n              : () => Navigator.pop(context, selected + widget.ref.pageBase),'),
        ('  final int index, columns;\n  IconTilePainter(this.image, this.index, this.columns);', '  final int index, columns;\n  final int? rows;\n  IconTilePainter(this.image, this.index, this.columns, {this.rows});'),
        ('Rect.fromLTWH(index % columns * 32.0, index ~/ columns * 32.0, 32, 32)', 'Rect.fromLTWH(index % columns * image.width / columns, index ~/ columns * image.height / (rows ?? image.height ~/ 32), image.width / columns, image.height / (rows ?? image.height ~/ 32))'),
    ])
    edit('lib/main.dart', [
        ("import 'ui/data_editor.dart';", "import 'ui/data_editor.dart';\nimport 'ui/item_workbench.dart';"),
        ('  Future<void> openDataEditor() async {', '''  Future<void> openItems() async {
    final library = catalog?.library;
    if (library == null || working) return;
    scene.clearMovement(); focus.unfocus();
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => ItemWorkbench(library: library)));
    if (mounted) focus.requestFocus();
  }

  Future<void> openDataEditor() async {'''),
        ('    onOpenEditor:', '    onOpenItems: catalog == null || working ? null : openItems,\n    onOpenEditor:'),
        ("const studioVersion = '0.6.24';", "const studioVersion = '0.6.25';"),
    ])
    edit('lib/ui/studio_workspace.dart',[
        ('      onOpenEditor,', '      onOpenEditor,\n      onOpenItems,'),
        ('    this.onOpenEditor,', '    this.onOpenEditor,\n    this.onOpenItems,'),
        ('            if (widget.onOpenSpk != null)', '''            if (widget.onOpenItems != null)
              IconButton(key: const ValueKey('open-items'), tooltip: 'Ítems · nombres del juego, iconos y edición SData',
                onPressed: widget.onOpenItems, icon: const Icon(Icons.inventory_2_outlined)),
            if (widget.onOpenSpk != null)'''),
    ])
    edit('lib/ui/equipment_registry_panel.dart', [
        ("import 'data_editor.dart';", "import 'data_editor.dart';\nimport 'item_workbench.dart';\nimport 'editor_icons.dart';\nimport '../data/library.dart';\nimport '../editor/workbench_model.dart';"),
        ('_ItemPicker(items: items, title: title)', '_ItemPicker(items: items, title: title, library: widget.scene.catalog!.library)'),
        ('''        const SizedBox(height: 8),
      ];''','''        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: !widget.enabled ? null : () => Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => ItemWorkbench(library: c.library))),
          icon: const Icon(Icons.inventory_2_outlined), label: const Text('Ítems · editar cualquier objeto')),
      ];'''),
        ('  final String title;\n', '  final String title;\n  final Library library;\n'),
        ('const _ItemPicker({required this.items, required this.title});', 'const _ItemPicker({required this.items, required this.title, required this.library});'),
        ("class _ItemPickerState extends State<_ItemPicker> {\n  String query = '';", "class _ItemPickerState extends State<_ItemPicker> {\n  late final images = EditorImages(widget.library);\n  @override void dispose() { images.dispose(); super.dispose(); }\n  String query = '';"),
        ('                    title: Text(item.label),', '''                    leading: DataIcon(images: images, path: 'dbitemdata.sdata',
                      summary: RecordSummary(0, item.key, item.name, '', {for (final v in item.values.entries) v.key: '${v.value}'}), size: 36),
                    title: Text(item.label),
                    trailing: IconButton(tooltip: 'Editar todas las propiedades de este ítem', icon: const Icon(Icons.edit_outlined),
                      onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute(
                        builder: (_) => ItemWorkbench(library: widget.library, initialKey: item.key)))),'''),
    ])
    edit('tool/run_all_local.dart',[("void main() {", "import '../test/item_workspace_test.dart' as itemsR25;\n\nvoid main() {\n  itemsR25.main();")])
    edit('pubspec.yaml',[("version: 0.6.24+31", "version: 0.6.25+32")])
    # Type names are grounded in the supplied Spanish corpus (not old guesses).
    edit('lib/editor/workbench_model.dart', [
        ("25: 'Lapis',", "25: 'Consumibles',"),
        ("27: 'Consumible',", "27: 'Misiones / materiales',"),
        ("28: 'Consumible',", "28: 'Misiones / materiales',"),
        ("30: 'Consumible',", "30: 'Lapis',"),
        ("41: 'Capa',", "41: 'Objetos especiales',"),
        ("94: 'Lapisia',", "94: 'Lingotes de gremio',"),
        ("95: 'Material',", "95: 'Lapisias',"),
        ("23: 'Brazalete',", "23: 'Amuletos',"),
        ("24: 'Collar',", "24: 'Capas',"),
        ("40: 'Capa',", "40: 'Brazaletes',"),
    ])
    edit('lib/editor/item_workspace.dart', [
        ("if (type==94) return 'Lapisias';", "if (type==95) return 'Lapisias';\n  if (type==94) return 'Lingotes de gremio';"),
        ("if ({30,95,98}.contains(type))", "if ({30,98}.contains(type))"),
    ])
    ui=ROOT/'lib/ui/item_workbench.dart'
    ui.write_text(ui.read_text().replace("import '../editor/catalog_document.dart';\n", ''))
    marker.write_text('R25: native item icons, unified SData editing and staged shared resources\n')

if __name__=='__main__': main()
