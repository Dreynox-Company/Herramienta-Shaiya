import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../editor/document.dart';
import '../editor/workbench_model.dart';
import '../editor/field_semantics.dart';
import 'editor_icons.dart';
import 'editor_style.dart';

class EditorCatalog extends StatefulWidget {
  final EditDocument document;
  final List<int> rows;
  final int selected;
  final RecordSummary Function(int) summary;
  final EditorImages images;
  final ValueChanged<int> onSelect, onEdit;
  final void Function(String, bool) onSort;
  final VoidCallback? onDuplicate, onDelete;
  const EditorCatalog({
    super.key,
    required this.document,
    required this.rows,
    required this.selected,
    required this.summary,
    required this.images,
    required this.onSelect,
    required this.onEdit,
    required this.onSort,
    this.onDuplicate,
    this.onDelete,
  });
  @override
  State<EditorCatalog> createState() => _EditorCatalogState();
}

class _EditorCatalogState extends State<EditorCatalog> {
  final horizontal = ScrollController(), vertical = ScrollController();
  final widths = <String, double>{
    '@icon': 38,
    '@id': 82,
    '@name': 240,
    '@category': 165,
  };
  String sorting = '@id';
  bool descending = false;
  Set<String>? visibleColumns;
  @override
  void dispose() {
    horizontal.dispose();
    vertical.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant EditorCatalog old) {
    super.didUpdateWidget(old);
    if (old.document.path != widget.document.path) {
      visibleColumns = null;
    }
    if (old.rows != widget.rows &&
        vertical.hasClients &&
        vertical.offset > math.max(0, widget.rows.length * 34 - 100)) {
      vertical.jumpTo(0);
    }
  }

  List<String> get columns {
    final domain = editorDomain(widget.document.path),
        fs = widget.document.rows.isEmpty
            ? <String>[]
            : widget.document
                  .fields(widget.rows.isEmpty ? 0 : widget.rows.first)
                  .map((f) => f.spec.name.toLowerCase())
                  .toList();
    final preferred = domain == EditorDomain.items
        ? ['level', 'country', 'grade', 'buy', 'sell', 'image', 'icon']
        : domain == EditorDomain.skills
        ? [
            'skilllevel',
            'level',
            'skillpoint',
            'point',
            'attackrange',
            'resettime',
            'image',
            'icon',
          ]
        : domain == EditorDomain.creatures
        ? ['level', 'hp', 'money1', 'money2', 'item1', 'itemdroprate1']
        : domain == EditorDomain.shops
        ? ['cost', 'price', 'productcode', 'itemcount']
        : ['npctype', 'npctypeid', 'mapid', 'image', 'icon', 'height'];
    return [
      '@icon',
      '@id',
      '@name',
      '@category',
      ...(visibleColumns == null
          ? preferred.where(fs.contains)
          : fs.where(visibleColumns!.contains)),
    ];
  }

  String title(String c) =>
      const {
        '@icon': '',
        '@id': 'ID',
        '@name': 'Nombre',
        '@category': 'Categoría',
      }[c] ??
      FieldMeaning.of(c).label;
  String value(RecordSummary s, String c) => switch (c) {
    '@id' => s.id,
    '@name' => s.name,
    '@category' => s.category,
    'country' =>
      editorDomain(widget.document.path) == EditorDomain.items
          ? itemCountryLabel(s.values[c])
          : s.values[c] ?? '—',
    _ => s.values[c] ?? '—',
  };
  Future<void> chooseColumns() async {
    if (widget.document.rows.isEmpty) return;
    final available = widget.document
        .fields(0)
        .where((f) => f.spec.type != 'opaque')
        .map((f) => f.spec.name.toLowerCase())
        .toList();
    final next = Set<String>.of(
      visibleColumns ?? columns.where((c) => !c.startsWith('@')),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: const Text('Columnas del catálogo'),
          content: SizedBox(
            width: 480,
            height: 450,
            child: ListView(
              children: available
                  .map(
                    (n) => CheckboxListTile(
                      dense: true,
                      value: next.contains(n),
                      title: Text(FieldMeaning.of(n).label),
                      subtitle: Text(n),
                      onChanged: (v) =>
                          update(() => v! ? next.add(n) : next.remove(n)),
                    ),
                  )
                  .toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Aplicar'),
            ),
          ],
        ),
      ),
    );
    if (ok == true && mounted) setState(() => visibleColumns = next);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (c, box) {
      final cols = columns,
          total = cols.fold<double>(0, (s, k) => s + (widths[k] ?? 106));
      final contentWidth = math.max(box.maxWidth, total);
      return Column(
        children: [
          SizedBox(
            height: 32,
            child: Row(
              children: [
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    '${widget.rows.length} registros · doble clic para editar',
                    style: const TextStyle(
                      fontSize: 10,
                      color: EditorStyle.muted,
                    ),
                  ),
                ),
                if (widget.onDuplicate != null)
                  IconButton(
                    tooltip: 'Duplicar como registro nuevo',
                    onPressed: widget.onDuplicate,
                    icon: const Icon(Icons.copy_outlined, size: 15),
                  ),
                if (widget.onDelete != null)
                  IconButton(
                    tooltip: 'Eliminar registro',
                    onPressed: widget.onDelete,
                    icon: const Icon(Icons.delete_outline, size: 15),
                  ),
                TextButton.icon(
                  onPressed: chooseColumns,
                  icon: const Icon(Icons.view_column_outlined, size: 14),
                  label: const Text('Columnas'),
                ),
              ],
            ),
          ),
          Expanded(
            child: Scrollbar(
              controller: horizontal,
              thumbVisibility: true,
              child: SingleChildScrollView(
                key: PageStorageKey('columns-${widget.document.path}'),
                controller: horizontal,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: contentWidth,
                  child: Column(
                    children: [
                      Container(
                        height: 34,
                        color: EditorStyle.panel,
                        child: Row(
                          children: cols.map((col) {
                            final w = widths[col] ?? 106;
                            return SizedBox(
                              width: w,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: InkWell(
                                      onTap: col == '@icon'
                                          ? null
                                          : () {
                                              setState(() {
                                                descending = sorting == col
                                                    ? !descending
                                                    : false;
                                                sorting = col;
                                              });
                                              widget.onSort(col, descending);
                                            },
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 9,
                                          vertical: 8,
                                        ),
                                        child: Text(
                                          '${title(col)}${sorting == col ? (descending ? ' ↓' : ' ↑') : ''}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (col != '@icon')
                                    GestureDetector(
                                      onHorizontalDragUpdate: (d) => setState(
                                        () => widths[col] = (w + d.delta.dx)
                                            .clamp(60, 600),
                                      ),
                                      child: const MouseRegion(
                                        cursor:
                                            SystemMouseCursors.resizeLeftRight,
                                        child: SizedBox(
                                          width: 5,
                                          height: 32,
                                          child: VerticalDivider(width: 1),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          key: PageStorageKey('rows-${widget.document.path}'),
                          controller: vertical,
                          itemExtent: 34,
                          itemCount: widget.rows.length,
                          itemBuilder: (c, i) {
                            final row = widget.rows[i],
                                s = widget.summary(row),
                                chosen = row == widget.selected;
                            return Material(
                              color: chosen
                                  ? const Color(0xff2b3f60)
                                  : i.isEven
                                  ? EditorStyle.background
                                  : const Color(0xff141c28),
                              child: InkWell(
                                key: ValueKey('catalog-row-$row'),
                                onTap: () => widget.onSelect(row),
                                onDoubleTap: () => widget.onEdit(row),
                                onLongPress: () => widget.onEdit(row),
                                child: Row(
                                  children: cols
                                      .map(
                                        (col) => SizedBox(
                                          width: widths[col] ?? 106,
                                          child: col == '@icon'
                                              ? Center(
                                                  child: DataIcon(
                                                    images: widget.images,
                                                    path: widget.document.path,
                                                    summary: s,
                                                    size: 26,
                                                  ),
                                                )
                                              : Padding(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 9,
                                                      ),
                                                  child: Text(
                                                    value(s, col),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: col == '@id'
                                                          ? EditorStyle.muted
                                                          : EditorStyle.text,
                                                    ),
                                                  ),
                                                ),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}
