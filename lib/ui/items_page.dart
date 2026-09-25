import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../data/item_workspace.dart';
import '../data/library.dart';
import '../editor/item_query.dart';
import '../editor/item_semantics.dart';
import '../editor/model_reference.dart';
import '../editor/workbench_model.dart';
import 'editor_icons.dart';
import 'item_asset_import.dart';
import 'editor_model_preview.dart';
import 'item_icon_picker.dart';
import 'item_record_editor.dart';

class ItemsPage extends StatefulWidget {
  final Library library;
  final String? initialItemKey;
  const ItemsPage({super.key, required this.library, this.initialItemKey});
  @override
  State<ItemsPage> createState() => _ItemsPageState();
}

class _ItemsPageState extends State<ItemsPage> {
  final search = TextEditingController();
  ItemWorkspace? workspace;
  EditorImages? images;
  List<ItemEntry> visible = [];
  String? selected, error;
  String kind = 'Todos', sort = 'Nombre';
  bool missingNames = false, missingIcons = false, busy = false;
  Timer? debounce;
  int imageRevision = -1;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final session = await ItemWorkspace.forLibrary(widget.library);
      if (!mounted) return;
      workspace = session;
      images = EditorImages(session.preview);
      imageRevision = session.revision;
      session.addListener(changed);
      selected = session.byKey.containsKey(widget.initialItemKey)
          ? widget.initialItemKey
          : session.byKey.keys.firstOrNull;
      filter();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  @override
  void dispose() {
    debounce?.cancel();
    workspace?.removeListener(changed);
    images?.dispose();
    search.dispose();
    super.dispose();
  }

  void changed() {
    if (!mounted) return;
    // Old image futures must not paint old thumbnails after an atlas edit.
    // Give mounted widgets a new provider before disposing the prior images.
    if (imageRevision != workspace!.revision) {
      final old = images;
      images = EditorImages(workspace!.preview);
      imageRevision = workspace!.revision;
      WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
    }
    filter();
  }

  void filter() {
    final session = workspace;
    if (session == null) return;
    try {
      final fields =
          session.byKey.values.firstOrNull?.values.keys.toSet() ?? <String>{};
      final query = ItemQuery.parse(search.text, fields);
      final entries = session.byKey.values
          .where(
            (i) =>
                query.matches(i) &&
                (kind == 'Todos' || ItemSemantics.kind(i.type) == kind) &&
                (!missingNames || !i.hasName) &&
                (!missingIcons ||
                    images!.icon(session.dataPath, i.summary) == null),
          )
          .toList();
      entries.sort(
        (a, b) => sort == 'ID'
            ? (a.type.compareTo(b.type) != 0
                  ? a.type.compareTo(b.type)
                  : a.typeId.compareTo(b.typeId))
            : sort == 'Nivel'
            ? compareEditorValues(
                a.values['level'] ?? a.values['reqlv'] ?? '0',
                b.values['level'] ?? b.values['reqlv'] ?? '0',
              )
            : compareEditorValues(a.displayName, b.displayName),
      );
      setState(() {
        visible = entries;
        error = null;
      });
    } catch (e) {
      setState(() => error = '$e');
    }
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> edit(ItemEntry item) => run(() async {
    await showItemRecordEditor(context, workspace!, item);
  });
  Future<void> export() => run(() async {
    final dir = await getApplicationDocumentsDirectory();
    final out = await workspace!.exportPatch(
      Directory(
        '${dir.path}/HerramientaShaiya/Publicaciones/Items_${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Parche exportado y releído'),
        content: SelectableText(
          '${out.path}\n\nLee LEEME.txt y conserva los originales. '
          'La copia no cambia automáticamente la DATA activa ni el servidor. '
          'La sesión conserva los cambios para seguir trabajando.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  });
  Future<void> resources(ItemEntry item) => run(() async {
    final models = await ModelReferences.resolve(
      workspace!.preview,
      workspace!.data,
      item.row,
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Modelos y texturas · ${item.key}'),
        content: SizedBox(
          width: 680,
          height: 450,
          child: models.isEmpty
              ? const SelectableText(
                  'No se encontró una asociación MLT/ITM/MON validada para este objeto. '
                  'Un consumible o una misión pueden tener solo icono. No se asigna una malla por parecido de nombre. '
                  'Image y todos los parámetros nativos permanecen accesibles en Propiedades.',
                )
              : ListView(
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Cada opción conserva su familia y archivo nativo. Una entrada puede ser compartida '
                        'por varios ítems. Elige expresamente qué recurso modificar.',
                      ),
                    ),
                    for (final model in models)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                model.label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              for (final part in model.parts)
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SelectableText('${part.$1}\n${part.$2}'),
                                    Wrap(
                                      spacing: 8,
                                      children: [
                                        for (final asset in [part.$1, part.$2])
                                          TextButton.icon(
                                            icon: const Icon(
                                              Icons.file_upload_outlined,
                                              size: 16,
                                            ),
                                            label: Text(
                                              asset == part.$1
                                                  ? 'Importar malla editada'
                                                  : 'Importar textura editada',
                                            ),
                                            onPressed: () async {
                                              try {
                                                await importItemAsset(
                                                  ctx,
                                                  workspace!,
                                                  asset,
                                                );
                                              } catch (e) {
                                                if (ctx.mounted)
                                                  ScaffoldMessenger.of(
                                                    ctx,
                                                  ).showSnackBar(
                                                    SnackBar(
                                                      content: Text('$e'),
                                                    ),
                                                  );
                                              }
                                            },
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              if (model.animations.isNotEmpty)
                                ExpansionTile(
                                  title: Text(
                                    '${model.animations.length} animaciones nativas',
                                  ),
                                  children: [
                                    for (final animation
                                        in model.animations.entries)
                                      ListTile(
                                        title: Text(animation.key),
                                        subtitle: SelectableText(
                                          animation.value,
                                        ),
                                        trailing: IconButton(
                                          tooltip: 'Importar ANI compatible',
                                          icon: const Icon(
                                            Icons.file_upload_outlined,
                                          ),
                                          onPressed: () async {
                                            try {
                                              await importItemAsset(
                                                ctx,
                                                workspace!,
                                                animation.value,
                                              );
                                            } catch (e) {
                                              if (ctx.mounted)
                                                ScaffoldMessenger.of(
                                                  ctx,
                                                ).showSnackBar(
                                                  SnackBar(content: Text('$e')),
                                                );
                                            }
                                          },
                                        ),
                                      ),
                                  ],
                                ),
                              Wrap(
                                spacing: 8,
                                children: [
                                  TextButton.icon(
                                    icon: const Icon(Icons.view_in_ar),
                                    label: const Text('Ver en 3D'),
                                    onPressed: () => showDialog<void>(
                                      context: ctx,
                                      builder: (view) => Dialog(
                                        child: SizedBox(
                                          width: 880,
                                          height: 660,
                                          child: Column(
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Padding(
                                                      padding:
                                                          const EdgeInsets.all(
                                                            12,
                                                          ),
                                                      child: Text(model.label),
                                                    ),
                                                  ),
                                                  IconButton(
                                                    onPressed: () =>
                                                        Navigator.pop(view),
                                                    icon: const Icon(
                                                      Icons.close,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              Expanded(
                                                child: NativeModelPreview(
                                                  library: workspace!.preview,
                                                  model: model,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (model.sourcePath != null &&
                                      model.sourceOrdinal != null)
                                    TextButton.icon(
                                      icon: const Icon(Icons.edit_outlined),
                                      label: const Text(
                                        'Editar catálogo y referencias',
                                      ),
                                      onPressed: () async {
                                        try {
                                          await editItemResource(
                                            ctx,
                                            workspace!,
                                            model.sourcePath!,
                                            model.sourceOrdinal!,
                                          );
                                          if (ctx.mounted) Navigator.pop(ctx);
                                        } catch (e) {
                                          if (ctx.mounted)
                                            ScaffoldMessenger.of(
                                              ctx,
                                            ).showSnackBar(
                                              SnackBar(content: Text('$e')),
                                            );
                                        }
                                      },
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  });
  Future<void> discardAndReload() async {
    final session = workspace;
    if (session == null || busy) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Descartar cambios de esta DATA y recargar'),
        content: const Text(
          'Se eliminarán los cambios preparados, también los de Equipamiento. '
          'La DATA original y los parches ya exportados no cambian. Esta acción no puede deshacerse.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Descartar y recargar'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    await run(() async {
      session.discard();
      await session.reloadFromSource();
    });
  }

  Future<void> addPredicate() async {
    final nativeFields =
        workspace!.byKey.values.firstOrNull?.values.keys.toList() ?? [];
    if (nativeFields.isEmpty) return;
    var field = nativeFields.contains('level') ? 'level' : nativeFields.first,
        op = '>=';
    final value = TextEditingController();
    final added = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Filtrar por una propiedad nativa'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButton<String>(
                  isExpanded: true,
                  value: field,
                  items: [
                    for (final f in nativeFields)
                      DropdownMenuItem(value: f, child: Text(f)),
                  ],
                  onChanged: (v) {
                    if (v != null) set(() => field = v);
                  },
                ),
                DropdownButton<String>(
                  isExpanded: true,
                  value: op,
                  items: [
                    for (final o in ['=', '!=', '>', '>=', '<', '<='])
                      DropdownMenuItem(value: o, child: Text(o)),
                  ],
                  onChanged: (v) {
                    if (v != null) set(() => op = v);
                  },
                ),
                TextField(
                  controller: value,
                  decoration: const InputDecoration(labelText: 'Valor entero'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                if (BigInt.tryParse(value.text.trim()) != null)
                  Navigator.pop(ctx, '$field$op${value.text.trim()}');
              },
              child: const Text('Añadir condición'),
            ),
          ],
        ),
      ),
    );
    value.dispose();
    if (added != null && mounted) {
      search.text = '${search.text} $added'.trim();
      filter();
    }
  }

  Widget details(ItemEntry item) => ListView(
    padding: const EdgeInsets.all(18),
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DataIcon(
            key: ValueKey('${item.key}-$imageRevision'),
            images: images!,
            path: workspace!.dataPath,
            summary: item.summary,
            size: 64,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  item.displayName,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                SelectableText(
                  '${item.key} · ${ItemSemantics.category(item.type)}',
                ),
                Text(
                  'Image ${item.image} · Icon ${item.icon} · ${item.values.length} campos numéricos',
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      SelectableText(
        item.description.isEmpty
            ? 'Sin descripción en la tabla localizada.'
            : item.description.replaceAll(r'\n', '\n'),
      ),
      const SizedBox(height: 14),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            key: const ValueKey('edit-selected-item'),
            onPressed: busy ? null : () => edit(item),
            icon: const Icon(Icons.tune),
            label: const Text('Editar todas las propiedades'),
          ),
          OutlinedButton.icon(
            onPressed: busy ? null : () => resources(item),
            icon: const Icon(Icons.view_in_ar),
            label: const Text('Modelo, texturas y animaciones'),
          ),
          OutlinedButton.icon(
            onPressed: busy
                ? null
                : () => run(
                    () => replaceItemThumbnail(context, workspace!, item),
                  ),
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('Importar miniatura'),
          ),
        ],
      ),
      const SizedBox(height: 18),
      const Text(
        'Propiedades actuales de la sesión',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      for (final group in ItemSemantics.groups.skip(1))
        Builder(
          builder: (ctx) {
            final fields = item.values.entries
                .where(
                  (e) => ItemSemantics.field(item.type, e.key).group == group,
                )
                .toList();
            if (fields.isEmpty) return const SizedBox.shrink();
            return ExpansionTile(
              title: Text('$group · ${fields.length}'),
              children: [
                for (final e in fields)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 5,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${ItemSemantics.field(item.type, e.key).label}\n${e.key}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        SelectableText(e.value),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      const SizedBox(height: 18),
      const Text(
        'Los nombres son los de la tabla cargada. Las etiquetas de categoría son de Studio. '
        'No se inventan traducciones para filas ???? ni se confunden los campos Arg con mecánicas confirmadas. '
        'Daño, uso y misiones pueden depender también del servidor.',
        style: TextStyle(fontSize: 12),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) {
    final session = workspace;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ítems · catálogo SData'),
        actions: [
          IconButton(
            tooltip: 'Deshacer operación',
            onPressed: session?.canUndo == true && !busy ? session!.undo : null,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: 'Rehacer operación',
            onPressed: session?.canRedo == true && !busy ? session!.redo : null,
            icon: const Icon(Icons.redo),
          ),
          IconButton(
            tooltip: 'Advertencias y fuentes',
            onPressed: session == null
                ? null
                : () => showDialog<void>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Fuente y alcance de la edición'),
                      content: SizedBox(
                        width: 620,
                        child: SingleChildScrollView(
                          child: SelectableText(
                            '${session.dataPath}\n${session.textPath ?? 'Sin tabla localizada'}\n\n'
                            '${session.sourceChanged ? 'DATA cambió fuera de esta sesión. Revisa o descarta los cambios antes de recargar.\n\n' : ''}'
                            'Perfil de iconos: ps0032 auditado. Una versión diferente debe verificar su correspondencia.\n\n'
                            '${session.warnings.join('\n\n')}',
                          ),
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            discardAndReload();
                          },
                          child: const Text('Descartar y recargar'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cerrar'),
                        ),
                      ],
                    ),
                  ),
            icon: const Icon(Icons.fact_check_outlined),
          ),
          IconButton(
            key: const ValueKey('export-items-patch'),
            tooltip: 'Exportar parche validado',
            onPressed: session?.dirty == true && !busy ? export : null,
            icon: const Icon(Icons.save_alt),
          ),
        ],
      ),
      body: session == null
          ? Center(
              child: error == null
                  ? const CircularProgressIndicator()
                  : SelectableText(error!),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      TextField(
                        key: const ValueKey('items-search'),
                        controller: search,
                        onChanged: (_) {
                          debounce?.cancel();
                          debounce = Timer(
                            const Duration(milliseconds: 140),
                            filter,
                          );
                        },
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          border: const OutlineInputBorder(),
                          labelText:
                              'Nombre, descripción, Type:TypeId o propiedades',
                          hintText:
                              'poción · 25:1 · level>=80 conststr>0 · nombre~"espada larga"',
                          suffixIcon: IconButton(
                            tooltip: 'Añadir filtro de propiedad',
                            onPressed: addPredicate,
                            icon: const Icon(Icons.filter_alt_outlined),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          DropdownButton<String>(
                            value: kind,
                            items: [
                              for (final k in {
                                'Todos',
                                ...session.byKey.values.map(
                                  (i) => ItemSemantics.kind(i.type),
                                ),
                              })
                                DropdownMenuItem(value: k, child: Text(k)),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                kind = v;
                                filter();
                              }
                            },
                          ),
                          DropdownButton<String>(
                            value: sort,
                            items: [
                              for (final s in ['Nombre', 'ID', 'Nivel'])
                                DropdownMenuItem(
                                  value: s,
                                  child: Text('Orden: $s'),
                                ),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                sort = v;
                                filter();
                              }
                            },
                          ),
                          FilterChip(
                            label: const Text('Sin nombre'),
                            selected: missingNames,
                            onSelected: (v) {
                              missingNames = v;
                              filter();
                            },
                          ),
                          FilterChip(
                            label: const Text('Icono no resuelto'),
                            selected: missingIcons,
                            onSelected: (v) {
                              missingIcons = v;
                              filter();
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (session.sourceChanged)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      'DATA cambió fuera de esta sesión. No se aplicarán cambios sobre una tabla obsoleta; usa Advertencias para descartar y recargar.',
                    ),
                  ),
                if (busy) const LinearProgressIndicator(),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: SelectableText(error!),
                  ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (_, constraints) {
                      final compact = constraints.maxWidth < 850;
                      final list = ListView.builder(
                        key: const ValueKey('items-list'),
                        itemExtent: 76,
                        itemCount: visible.length,
                        itemBuilder: (_, i) {
                          final item = visible[i];
                          return ListTile(
                            key: ValueKey('item-${item.key}'),
                            selected: selected == item.key,
                            leading: DataIcon(
                              key: ValueKey('${item.key}-$imageRevision'),
                              images: images!,
                              path: session.dataPath,
                              summary: item.summary,
                              size: 38,
                            ),
                            title: Text(
                              item.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${item.key} · ${ItemSemantics.kind(item.type)} · Nv. ${item.values['level'] ?? item.values['reqlv'] ?? '—'}',
                              maxLines: 1,
                            ),
                            trailing: IconButton(
                              tooltip: 'Editar ${item.key}',
                              onPressed: busy ? null : () => edit(item),
                              icon: const Icon(Icons.edit_outlined, size: 19),
                            ),
                            onTap: () {
                              setState(() => selected = item.key);
                              if (compact) {
                                showDialog<void>(
                                  context: context,
                                  builder: (ctx) => Dialog(
                                    child: SizedBox(
                                      width: 740,
                                      height:
                                          MediaQuery.sizeOf(ctx).height * .8,
                                      child: Column(
                                        children: [
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.end,
                                            children: [
                                              IconButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx),
                                                icon: const Icon(Icons.close),
                                              ),
                                            ],
                                          ),
                                          Expanded(
                                            child: AnimatedBuilder(
                                              animation: session,
                                              builder: (_, _) => details(
                                                session.byKey[item.key]!,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }
                            },
                          );
                        },
                      );
                      if (compact) return list;
                      final item = session.byKey[selected];
                      return Row(
                        children: [
                          SizedBox(width: 380, child: list),
                          const VerticalDivider(width: 1),
                          Expanded(
                            child: item == null
                                ? const Center(
                                    child: Text('Selecciona un ítem.'),
                                  )
                                : details(item),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  child: Text(
                    '${visible.length}/${session.byKey.length} objetos · ${session.pendingFiles} archivos con cambios preparados · '
                    'DATA original intacta · los cambios de sesión se conservan al cerrar esta vista',
                  ),
                ),
              ],
            ),
    );
  }
}
