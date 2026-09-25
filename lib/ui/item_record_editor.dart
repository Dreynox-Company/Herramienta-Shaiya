import 'package:flutter/material.dart';

import '../core/formats.dart';
import '../data/item_workspace.dart';
import '../editor/catalog_document.dart';
import '../editor/document.dart';
import '../editor/field_semantics.dart';
import '../editor/item_semantics.dart';
import 'editor_icons.dart';
import 'editor_pickers.dart';
import 'item_icon_picker.dart';

Future<bool?> showItemRecordEditor(
  BuildContext context,
  ItemWorkspace workspace,
  ItemEntry entry,
) => showDialog<bool>(
  context: context,
  barrierDismissible: false,
  builder: (_) => ItemRecordEditor(workspace: workspace, entry: entry),
);

/// Exact native fields are shared with the catalogue editor. No separate
/// weapon/armor/potion save implementation and no lossy int32 conversion.
class ItemRecordEditor extends StatefulWidget {
  final ItemWorkspace workspace;
  final ItemEntry? entry;
  final EditDocument? resource;
  final int? resourceRow;
  const ItemRecordEditor({
    super.key,
    required this.workspace,
    this.entry,
    this.resource,
    this.resourceRow,
  });
  @override
  State<ItemRecordEditor> createState() => _ItemRecordEditorState();
}

class _EditableItemField {
  final EditDocument document;
  final int row;
  final FieldSpan span;
  final String before;
  final TextEditingController controller;
  String? error;
  _EditableItemField(this.document, this.row, this.span)
    : before = document.read(span),
      controller = TextEditingController(text: document.read(span));
  bool get identity => const {
    'itemtype',
    'itemtypeid',
    'type',
    'typeid',
  }.contains(span.spec.name.toLowerCase());
  bool get writable =>
      span.spec.editable && span.spec.type != 'opaque' && !identity;
  bool get changed => controller.text != before;
}

class _ItemRecordEditorState extends State<ItemRecordEditor> {
  final fields = <_EditableItemField>[];
  late final EditorImages images;
  String group = 'Todos los campos', query = '';
  String? message;
  bool allowClose = false;
  @override
  void initState() {
    super.initState();
    images = EditorImages(widget.workspace.preview);
    void add(EditDocument doc, int row) {
      fields.addAll(
        doc.fields(row).map((span) => _EditableItemField(doc, row, span)),
      );
    }

    final item = widget.entry;
    if (item != null) {
      add(widget.workspace.data, item.row);
      if (item.textRow != null && widget.workspace.text != null) {
        add(widget.workspace.text!, item.textRow!);
      }
    } else {
      add(widget.resource!, widget.resourceRow!);
    }
  }

  @override
  void dispose() {
    for (final field in fields) {
      field.controller.dispose();
    }
    images.dispose();
    super.dispose();
  }

  FieldMeaning meaning(_EditableItemField f) => widget.entry == null
      ? FieldMeaning.of(f.span.spec.name)
      : ItemSemantics.field(widget.entry!.type, f.span.spec.name);
  Future<void> close() async {
    if (fields.any((f) => f.changed)) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Descartar este borrador sin aplicar'),
          content: const Text(
            'Los cambios ya preparados en otros ítems se conservan. '
            'Solo se descartan los campos aún no aplicados de este diálogo.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Seguir editando'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Descartar borrador'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    setState(() => allowClose = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context, false);
    });
  }

  void apply() {
    var failed = false;
    for (final field in fields) {
      field.error = null;
      if (!field.changed) continue;
      try {
        widget.workspace.validateField(
          field.document,
          field.span,
          field.controller.text,
        );
      } catch (e) {
        field.error = '$e';
        failed = true;
      }
    }
    if (failed) {
      setState(() {
        group = 'Todos los campos';
        query = '';
        message = 'Corrige los campos señalados. No se aplicó ningún cambio.';
      });
      return;
    }
    try {
      widget.workspace.apply(
        [
          for (final f in fields)
            if (f.changed)
              ItemFieldEdit(
                f.document.path,
                f.row,
                f.span.spec.name,
                f.before,
                f.controller.text,
              ),
        ],
        title:
            'Editar ${widget.entry?.key ?? '${widget.resource!.path} #${widget.resourceRow}'}',
      );
      setState(() => allowClose = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context, true);
      });
    } catch (e) {
      setState(() => message = '$e');
    }
  }

  Future<void> chooseAsset(_EditableItemField field) async {
    final chosen = await pickAsset(
      context,
      images,
      field.span.spec.name,
      field.controller.text,
    );
    if (chosen == null || !mounted) return;
    final n = field.span.spec.name.toLowerCase();
    var root = directoryName(field.document.path).toLowerCase();
    if (root.endsWith('/mlt')) root = directoryName(root);
    if (n.contains('sound') || n.contains('effect')) root = '';
    final sub = n.contains('texture')
        ? 'dds'
        : n.contains('animation')
        ? 'ani'
        : n.contains('sound')
        ? 'sound'
        : n.contains('effect')
        ? 'effect'
        : chosen.endsWith('.3do')
        ? '3do'
        : '3dc';
    // The native catalog loaders append names to a fixed directory. Storing
    // a full DATA path here would duplicate that prefix in game.exe.
    final expectedRoot = root.isEmpty ? sub : '$root/$sub';
    if (directoryName(chosen) != expectedRoot) {
      setState(
        () => message =
            'Esta referencia requiere un archivo dentro de $expectedRoot. '
            'No se guarda una ruta completa que el cliente concatenaría dos veces.',
      );
      return;
    }
    setState(() {
      field.controller.text = baseName(chosen);
      message = null;
    });
  }

  Widget editField(_EditableItemField f) {
    final meta = meaning(f), name = f.span.spec.name;
    final choices = fieldChoices(f.document, name);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    meta.label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (f.changed)
                  const Text('Modificado', style: TextStyle(fontSize: 11)),
                Tooltip(
                  message: '${meta.help}\n${f.span.spec.limits}',
                  child: const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(Icons.info_outline, size: 17),
                  ),
                ),
              ],
            ),
            Text(
              '$name · ${f.span.spec.type} · ${meta.group}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            TextField(
              key: ValueKey('item-field-${f.document.path}-$name'),
              controller: f.controller,
              readOnly: !f.writable,
              maxLines: f.span.spec.text
                  ? (name.toLowerCase() == 'text' ? 4 : 2)
                  : 1,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                isDense: true,
                border: const OutlineInputBorder(),
                errorText: f.error,
                helperText: f.identity
                    ? 'Identidad estable; renumerar requiere migrar referencias.'
                    : null,
                suffixIcon: !f.writable
                    ? const Icon(Icons.lock_outline, size: 16)
                    : f.changed
                    ? IconButton(
                        tooltip: 'Restaurar este campo',
                        onPressed: () =>
                            setState(() => f.controller.text = f.before),
                        icon: const Icon(Icons.restore, size: 18),
                      )
                    : null,
              ),
            ),
            if (f.writable && choices != null)
              Wrap(
                spacing: 6,
                children: [
                  for (final c in choices.entries)
                    ActionChip(
                      label: Text(
                        c.value,
                        style: const TextStyle(fontSize: 11),
                      ),
                      onPressed: () =>
                          setState(() => f.controller.text = c.key),
                    ),
                ],
              ),
            if (f.writable &&
                name.toLowerCase() == 'icon' &&
                widget.entry != null)
              TextButton.icon(
                icon: const Icon(Icons.image_search, size: 17),
                label: const Text('Elegir miniatura real'),
                onPressed: () async {
                  final value = await pickNativeItemIcon(
                    context,
                    images,
                    widget.entry!.type,
                    int.tryParse(f.controller.text) ?? 0,
                  );
                  if (value != null && mounted)
                    setState(() => f.controller.text = '$value');
                },
              ),
            if (f.writable && isAssetField(name))
              TextButton.icon(
                onPressed: () => chooseAsset(f),
                icon: const Icon(Icons.folder_open, size: 17),
                label: const Text('Buscar recurso de DATA'),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = fields
        .where(
          (f) =>
              (group == 'Todos los campos' || meaning(f).group == group) &&
              ('${f.span.spec.name} ${meaning(f).label}')
                  .toLowerCase()
                  .contains(query.toLowerCase()),
        )
        .toList();
    final groups = {'Todos los campos', ...fields.map((f) => meaning(f).group)};
    return PopScope(
      canPop: allowClose,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) close();
      },
      child: AlertDialog(
        title: Text(
          widget.entry?.displayName ?? 'Editar recurso #${widget.resourceRow}',
        ),
        content: SizedBox(
          width: 830,
          height: MediaQuery.sizeOf(context).height * .69,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.entry == null
                    ? 'Catálogo compartido. Cambiar geometría o textura afecta a todos los usuarios de esa entrada.'
                    : '${widget.entry!.key} · ${ItemSemantics.category(widget.entry!.type)}\n'
                          'Cambios preparados en sesión; no se escriben sobre DATA ni sobre el servidor.',
              ),
              if (widget.entry != null && widget.entry!.textRow == null)
                const Text(
                  'No existe fila de texto: no se crea ni se asocia otro nombre automáticamente.',
                ),
              const SizedBox(height: 10),
              TextField(
                onChanged: (s) => setState(() => query = s),
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Buscar propiedad por nombre nativo o etiqueta',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              DropdownButton<String>(
                isExpanded: true,
                value: group,
                items: [
                  for (final g in groups)
                    DropdownMenuItem(value: g, child: Text(g)),
                ],
                onChanged: (s) {
                  if (s != null) setState(() => group = s);
                },
              ),
              if (message != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(message!),
                ),
              Expanded(
                child: ListView.builder(
                  itemCount: visible.length,
                  itemBuilder: (_, i) => editField(visible[i]),
                ),
              ),
              Text(
                '${visible.length}/${fields.length} campos visibles · ${fields.where((f) => f.changed).length} cambios',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: close, child: const Text('Cerrar')),
          FilledButton.icon(
            key: const ValueKey('apply-item-draft'),
            onPressed: widget.workspace.exporting ? null : apply,
            icon: const Icon(Icons.check),
            label: const Text('Aplicar a la sesión'),
          ),
        ],
      ),
    );
  }
}

Future<void> editItemResource(
  BuildContext context,
  ItemWorkspace workspace,
  String path,
  int ordinal,
) async {
  final document = await workspace.openDocument(path);
  if (document is! CatalogDocument)
    throw const FormatException('La referencia no es un catálogo MLT/ITM/MON.');
  final candidates = [
    for (var row = 0; row < document.rows.length; row++)
      if (document.rows[row].ordinal == ordinal &&
          const {
            'Material',
            'Equipo',
            'Modelo animado',
          }.contains(document.rows[row].kind))
        row,
  ];
  if (candidates.length != 1)
    throw const FormatException(
      'No hay una entrada única para el ordinal seleccionado.',
    );
  if (!context.mounted) return;
  await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ItemRecordEditor(
      workspace: workspace,
      resource: document,
      resourceRow: candidates.single,
    ),
  );
  if (!context.mounted) return;
  // Mesh/Texture name rows are separate from the material's indices in MLT/ITM.
  // Expose both instead of pretending Image is a filename.
  final spans = document.fields(candidates.single);
  final shared = <(String, int)>[];
  for (final key in ['MeshIndex', 'TextureIndex']) {
    final f = spans.where((f) => f.spec.name == key).firstOrNull;
    if (f == null) continue;
    final i = int.tryParse(document.read(f));
    final table = key == 'MeshIndex' ? document.meshes : document.textures;
    if (i == null || i < 0 || i >= table.length) continue;
    final row = document.rows.indexWhere(
      (r) => r.offset <= table[i].start && r.end > table[i].start,
    );
    if (row >= 0) shared.add((key == 'MeshIndex' ? 'Malla' : 'Textura', row));
  }
  if (shared.isEmpty || !context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Referencias de geometría y textura'),
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Los nombres de archivo también pueden editarse. '
            'Una misma entrada puede ser usada por varios materiales; el cambio no es exclusivo de este ítem.',
          ),
        ),
        for (final ref in shared)
          SimpleDialogOption(
            child: Text('Editar ${ref.$1} usada'),
            onPressed: () async {
              await showDialog<bool>(
                context: ctx,
                barrierDismissible: false,
                builder: (_) => ItemRecordEditor(
                  workspace: workspace,
                  resource: document,
                  resourceRow: ref.$2,
                ),
              );
            },
          ),
        SimpleDialogOption(
          child: const Text('Cerrar'),
          onPressed: () => Navigator.pop(ctx),
        ),
      ],
    ),
  );
}
