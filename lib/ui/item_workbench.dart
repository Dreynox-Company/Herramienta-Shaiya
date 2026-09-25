import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import '../data/library.dart';
import '../editor/document.dart';
import '../editor/item_field_profile.dart';
import '../editor/item_workspace.dart';
import '../editor/model_reference.dart';
import '../editor/workbench_model.dart';
import '../core/item_icon_layout.dart';
import 'editor_icons.dart';
import 'editor_model_preview.dart';
import 'editor_pickers.dart';

/// The same entry point is used by the global Items section and SData equipment
/// selectors. Nothing here assumes that every item is equippable or has a mesh.
class ItemWorkbench extends StatefulWidget {
  final Library library;
  final String? initialKey;
  const ItemWorkbench({super.key, required this.library, this.initialKey});
  @override
  State<ItemWorkbench> createState() => _ItemWorkbenchState();
}

class _ItemWorkbenchState extends State<ItemWorkbench> {
  ItemWorkspace? session;
  late EditorImages images;
  final search = TextEditingController();
  Timer? debounce;
  String? selected, category, error, filterError;
  String message = 'Leyendo tablas del DATA…';
  bool busy = false, leaving = false, onlyUnnamed = false, mobileDetail = false;
  List<ItemEntry> visible = [];
  Future<List<ModelReference>>? references;
  @override
  void initState() {
    super.initState();
    images = EditorImages(widget.library);
    unawaited(load());
  }

  @override
  void dispose() {
    debounce?.cancel();
    search.dispose();
    images.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final s = await ItemWorkspace.load(widget.library);
      if (!mounted) return;
      setState(() {
        session = s;
        message =
            '${s.entries.length} ítems · ${s.text?.path ?? 'sin tabla de nombres'}';
      });
      filter();
      select(s.byKey[widget.initialKey]?.key ?? visible.firstOrNull?.key);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  void filter() {
    final s = session;
    if (s == null) return;
    try {
      final q = ItemQuery.parse(search.text, s.fieldNames);
      setState(() {
        filterError = null;
        visible = s.entries
            .where(
              (e) =>
                  (category == null || e.category == category) &&
                  (!onlyUnnamed || !e.named) &&
                  q.matches(e),
            )
            .toList(growable: false);
      });
    } catch (e) {
      setState(() => filterError = '$e');
    }
  }

  void select(String? key) {
    setState(() {
      selected = key;
      final e = session?.byKey[key];
      references = e == null
          ? null
          : ModelReferences.resolve(
              session!.view(widget.library),
              session!.data,
              e.row,
            );
    });
  }

  Future<void> run(Future<void> Function() fn) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await fn();
    } catch (e) {
      if (mounted) setState(() => message = 'No se aplicó: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> leave() async {
    if (busy) return;
    if (mobileDetail) {
      setState(() => mobileDetail = false);
      return;
    }
    if (session?.dirty == true &&
        !await confirm(
          context,
          'Salir del editor',
          'El borrador tiene cambios. Exportar crea una carpeta nueva; no modifica el DATA conectado. ¿Descartar este borrador y salir?',
        )) {
      return;
    }
    if (mounted) {
      setState(() => leaving = true);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.pop(context);
    }
  }

  void changed() {
    filter();
    select(selected);
    setState(
      () => message =
          'Borrador actualizado. DATA original intacta. Exporta el lote para instalarlo.',
    );
  }

  Future<void> edit(ItemEntry e) async {
    final s = session!;
    final bindings = <PropertyBinding>[
      for (final f in s.data.fields(e.row)) PropertyBinding(s.data, e.row, f),
      if (s.text != null && e.textRow != null)
        for (final f in s.text!.fields(e.textRow!))
          if (!{
            'type',
            'typeid',
            'itemtype',
            'itemtypeid',
          }.contains(f.spec.name.toLowerCase()))
            PropertyBinding(s.text!, e.textRow!, f),
    ];
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ItemPropertiesDialog(
        session: s,
        images: images,
        entry: e,
        bindings: bindings,
      ),
    );
    if (accepted == true && mounted) changed();
  }

  Future<void> editReference(ModelReference ref) async {
    final capturedEntry = session!.byKey[selected]!;
    final path = ref.sourcePath, ordinal = ref.sourceOrdinal;
    if (path == null || ordinal == null)
      throw const FormatException('Referencia sin identidad de catálogo.');
    if (!await confirm(
      context,
      'Recurso compartido',
      '$path · registro $ordinal\n\nCambiar sus mallas, texturas, anclajes o animaciones afecta a todos los objetos que utilicen este registro. '
          'Los nombres globales de una MLT/ITM pueden compartirse con otros registros. Los cambios se incluyen en el MISMO lote, no se escriben todavía. ¿Editar?',
    )) {
      return;
    }
    final d = await session!.catalog(widget.library, path);
    final row = d.rows.indexWhere(
      (r) =>
          r.ordinal == ordinal &&
          {'Material', 'Equipo', 'Modelo animado'}.contains(r.kind),
    );
    if (row < 0)
      throw const FormatException('No existe el registro del catálogo.');
    final fields = <PropertyBinding>[
      for (final f in d.fields(row)) PropertyBinding(d, row, f),
    ];
    final values = ItemWorkspace.values(d, row);
    for (final pair in [
      ('meshindex', d.meshes),
      ('textureindex', d.textures),
    ]) {
      final index = int.tryParse(values[pair.$1] ?? '');
      if (index == null || index < 0 || index >= pair.$2.length) continue;
      final span = pair.$2[index],
          owner = d.rows.indexWhere(
            (r) => r.offset <= span.start && span.start < r.end,
          );
      if (owner >= 0) fields.add(PropertyBinding(d, owner, span));
    }
    if (!mounted) return;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ItemPropertiesDialog(
        session: session!,
        images: images,
        entry: capturedEntry,
        bindings: fields,
        title: 'Recurso asociado · ${ref.label}',
      ),
    );
    if (accepted == true && mounted) changed();
  }

  Future<void> export() async {
    final s = session!;
    if (!await confirm(
      context,
      'Publicar lote de ítems',
      '${s.documents.values.fold<int>(0, (n, d) => n + d.changeCount)} cambios de campos. '
          'Se validará y releerá cada tabla. El DATA y la base del servidor NO se sobrescriben; '
          'el resultado incluirá COPIAR_EN_DATA, manifiesto y LEEME.',
    )) {
      return;
    }
    final parent = await getDirectoryPath(
      confirmButtonText: 'Elegir carpeta de exportación',
    );
    if (parent == null) return;
    final out = await s.export(
      widget.library,
      Directory('$parent/Items_${DateTime.now().microsecondsSinceEpoch}'),
    );
    if (mounted)
      setState(
        () => message =
            'Exportado y verificado: ${out.path}. El borrador se conserva; DATA sigue intacta.',
      );
  }

  @override
  Widget build(BuildContext context) {
    final s = session;
    return PopScope(
      canPop: leaving,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(leave());
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            onPressed: leave,
            icon: const Icon(Icons.arrow_back),
          ),
          title: const Text('Ítems · SData'),
          actions: [
            IconButton(
              tooltip: 'Deshacer lote',
              onPressed: busy || s?.canUndo != true
                  ? null
                  : () {
                      s!.undo();
                      changed();
                    },
              icon: const Icon(Icons.undo),
            ),
            IconButton(
              tooltip: 'Rehacer lote',
              onPressed: busy || s?.canRedo != true
                  ? null
                  : () {
                      s!.redo();
                      changed();
                    },
              icon: const Icon(Icons.redo),
            ),
            TextButton.icon(
              onPressed: busy || s?.dirty != true ? null : () => run(export),
              icon: const Icon(Icons.save_alt),
              label: const Text('Exportar lote'),
            ),
          ],
        ),
        body: s == null
            ? Center(
                child: error == null
                    ? const CircularProgressIndicator()
                    : SelectableText(error!),
              )
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      key: const ValueKey('item-search'),
                      controller: search,
                      onChanged: (_) {
                        debounce?.cancel();
                        debounce = Timer(
                          const Duration(milliseconds: 180),
                          filter,
                        );
                      },
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        labelText:
                            'Buscar nombre, descripción, Type:TypeId o propiedades',
                        hintText:
                            'manzana   /   "lapisia" Level>=50   /   ConstStr>0',
                        errorText: filterError,
                        suffixIcon: IconButton(
                          tooltip: 'Ayuda y campos de búsqueda',
                          icon: const Icon(Icons.help_outline),
                          onPressed: () => showDialog<void>(
                            context: context,
                            builder: (c) => AlertDialog(
                              title: const Text('Búsqueda de ítems'),
                              content: SingleChildScrollView(
                                child: SelectableText(
                                  'Las palabras se combinan. Se ignoran tildes al buscar, no se cambian los nombres originales.\n'
                                  'Comparaciones: Campo=10, Campo!=0, Campo>=50. Excluir: -palabra. Frase: "dos palabras".\n\n'
                                  'Campos reales de esta tabla:\n${s.fieldNames.join(', ')}\n\n'
                                  'Un tipo desconocido conserva TODOS sus campos editables; no se inventa su función.',
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(c),
                                  child: const Text('Cerrar'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Wrap(
                      spacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        DropdownButton<String>(
                          value: category ?? '',
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('Todos los ítems'),
                            ),
                            for (final c
                                in (s.entries
                                    .map((e) => e.category)
                                    .toSet()
                                    .toList()
                                  ..sort()))
                              DropdownMenuItem(value: c, child: Text(c)),
                          ],
                          onChanged: (v) {
                            category = v == '' ? null : v;
                            filter();
                          },
                        ),
                        FilterChip(
                          label: const Text('Sin nombre legible'),
                          selected: onlyUnnamed,
                          onSelected: (v) {
                            onlyUnnamed = v;
                            filter();
                          },
                        ),
                        Text('${visible.length} / ${s.entries.length}'),
                        const Text(
                          'Iconos: perfil ps0032 · fuente DATA',
                          style: TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  if (busy) const LinearProgressIndicator(),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, box) {
                        final wide = box.maxWidth >= 820;
                        final list = ListView.builder(
                          key: const ValueKey('item-results'),
                          itemExtent: 76,
                          itemCount: visible.length,
                          itemBuilder: (context, index) {
                            final e = visible[index];
                            return ListTile(
                              key: ValueKey('item-${e.key}'),
                              selected: selected == e.key,
                              leading: DataIcon(
                                images: images,
                                path: s.data.path,
                                summary: e.summary,
                                size: 42,
                              ),
                              title: Text(
                                e.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${e.key} · ${e.category} · Nv. ${e.values['level'] ?? e.values['reqlv'] ?? '—'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: IconButton(
                                tooltip: 'Editar TODAS las propiedades',
                                onPressed: busy
                                    ? null
                                    : () => run(() => edit(e)),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              onTap: busy
                                  ? null
                                  : () {
                                      select(e.key);
                                      if (!wide)
                                        setState(() => mobileDetail = true);
                                    },
                            );
                          },
                        );
                        if (!wide)
                          return mobileDetail && selected != null
                              ? detail(s.byKey[selected]!)
                              : list;
                        return Row(
                          children: [
                            Expanded(flex: 5, child: list),
                            const VerticalDivider(width: 1),
                            Expanded(
                              flex: 6,
                              child: selected == null
                                  ? const Center(
                                      child: Text('Selecciona un ítem'),
                                    )
                                  : detail(s.byKey[selected]!),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    child: SelectableText(
                      message,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget detail(ItemEntry e) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            DataIcon(
              images: images,
              path: session!.data.path,
              summary: e.summary,
              size: 64,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.title, style: Theme.of(context).textTheme.titleLarge),
                  Text('${e.key} · ${e.category}'),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SelectableText(
          e.description.isEmpty
              ? 'Sin descripción en la tabla seleccionada.'
              : e.description,
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const ValueKey('edit-item-properties'),
          onPressed: busy ? null : () => run(() => edit(e)),
          icon: const Icon(Icons.tune),
          label: const Text('Editar propiedades, nombre e icono'),
        ),
        const SizedBox(height: 16),
        Text(
          'Aspecto y recursos',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const Text(
          'Image es un índice del catálogo, no un ID de objeto. Elige la variante de personaje o MON explícitamente. Una poción o un material pueden no tener modelo equipable.',
          style: TextStyle(fontSize: 12),
        ),
        TextButton.icon(
          onPressed: busy
              ? null
              : () => run(
                  () => showEditorModel(
                    context,
                    session!.view(widget.library),
                    session!.data,
                    e.row,
                  ),
                ),
          icon: const Icon(Icons.view_in_ar_outlined),
          label: const Text('Inspeccionar modelo 3D y texturas'),
        ),
        FutureBuilder<List<ModelReference>>(
          key: ValueKey('${e.key}-${session!.revision}'),
          future: references,
          builder: (context, snap) {
            if (snap.hasError)
              return SelectableText('Referencia no resuelta: ${snap.error}');
            final refs = snap.data;
            if (refs == null) return const LinearProgressIndicator();
            if (refs.isEmpty)
              return const Text(
                'Sin referencia equipable demostrada para este tipo/Image. El icono y todos los campos SData siguen editables.',
              );
            return Column(
              children: [
                for (final ref in refs)
                  Card(
                    child: ListTile(
                      title: Text(ref.label),
                      subtitle: Text(
                        [
                          for (final p in ref.parts) '${p.$1}\n${p.$2}',
                        ].join('\n'),
                      ),
                      trailing: IconButton(
                        tooltip:
                            'Editar modelo, textura, anclajes y ANI del catálogo',
                        onPressed: busy
                            ? null
                            : () => run(() => editReference(ref)),
                        icon: const Icon(Icons.edit_note),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        ExpansionTile(
          title: Text('Todos los campos nativos (${e.values.length})'),
          children: [
            for (final v in e.values.entries)
              ListTile(
                dense: true,
                title: Text(
                  '${ItemFieldProfile.meaning(e, v.key).label} · ${v.key}',
                ),
                trailing: Text(v.value),
              ),
          ],
        ),
        ExpansionTile(
          title: const Text('Origen, advertencias y alcance'),
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: SelectableText(
                '${session!.data.path}\n${session!.text?.path ?? 'Sin texto localizado'}\n\n${session!.warnings.toSet().join('\n')}\n'
                'Los nombres ???? pertenecen al archivo: no se sustituyen por traducciones inventadas.\n'
                'Iconos originales por tipo y por índice 1-based; un atlas ausente no se reemplaza por el de otro tipo.\n'
                'Cambiar DATA no sincroniza por sí solo el daño/consumo/restricciones en la base del servidor.',
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

Future<bool> confirm(BuildContext context, String title, String body) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    ) ??
    false;

class PropertyBinding {
  final EditDocument document;
  final int row;
  final FieldSpan field;
  PropertyBinding(this.document, this.row, this.field);
  String get key => '${document.path}:$row:${field.start}';
  bool get editable =>
      field.spec.editable &&
      field.spec.type != 'opaque' &&
      !{
        'type',
        'typeid',
        'itemtype',
        'itemtypeid',
      }.contains(field.spec.name.toLowerCase());
}

class ItemPropertiesDialog extends StatefulWidget {
  final ItemWorkspace session;
  final EditorImages images;
  final ItemEntry entry;
  final List<PropertyBinding> bindings;
  final String? title;
  const ItemPropertiesDialog({
    super.key,
    required this.session,
    required this.images,
    required this.entry,
    required this.bindings,
    this.title,
  });
  @override
  State<ItemPropertiesDialog> createState() => _ItemPropertiesDialogState();
}

class _ItemPropertiesDialogState extends State<ItemPropertiesDialog> {
  final controls = <String, TextEditingController>{},
      errors = <String, String>{};
  final original = <String, String>{};
  String query = '', group = 'Todos';
  bool leaving = false;
  @override
  void initState() {
    super.initState();
    for (final b in widget.bindings) {
      original[b.key] = b.document.read(b.field);
      controls[b.key] = TextEditingController(text: original[b.key]);
    }
  }

  @override
  void dispose() {
    for (final c in controls.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool get dirty =>
      controls.entries.any((e) => e.value.text != original[e.key]);
  Future<void> close(bool applied) async {
    if (!applied &&
        dirty &&
        !await confirm(
          context,
          'Descartar edición',
          'Los campos aún no aplicados se descartarán.',
        ))
      return;
    if (!mounted) return;
    setState(() => leaving = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context, applied);
  }

  Future<void> apply() async {
    errors.clear();
    final batch = <EditDocument, List<(int, FieldSpan, String)>>{};
    for (final b in widget.bindings.where((b) => b.editable)) {
      final value = controls[b.key]!.text;
      if (value == original[b.key]) continue;
      try {
        if (b.document.read(b.field) != original[b.key])
          throw const FormatException('Este campo cambió mientras se editaba.');
        b.document.validate(b.field, value);
        if (b.field.spec.name.toLowerCase() == 'icon' &&
            (int.tryParse(value) == null ||
                int.parse(value) < 1 ||
                int.parse(value) > 255)) {
          throw const FormatException('Icon debe ser 1..255 en ps0032.');
        }
        batch.putIfAbsent(b.document, () => []).add((b.row, b.field, value));
      } catch (e) {
        errors[b.key] = '$e';
      }
    }
    if (errors.isNotEmpty) {
      setState(() {
        group = 'Todos';
        query = '';
      });
      return;
    }
    try {
      widget.session.apply(batch);
      await close(true);
    } catch (e) {
      setState(() => errors['batch'] = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bindings = widget.bindings.where((b) {
      final m = ItemFieldProfile.meaning(widget.entry, b.field.spec.name);
      return (group == 'Todos' || m.group == group) &&
          foldedSearch(
            '${m.label} ${b.field.spec.name}',
          ).contains(foldedSearch(query));
    }).toList();
    return PopScope(
      canPop: leaving,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(close(false));
      },
      child: AlertDialog(
        title: Text(
          widget.title ?? '${widget.entry.title} · ${widget.entry.key}',
        ),
        content: SizedBox(
          width: 820,
          height: 560,
          child: Column(
            children: [
              const Text(
                'Edición nativa en borrador · parámetros según tipo · ninguna columna se oculta permanentemente',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              TextField(
                onChanged: (v) => setState(() => query = v),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Buscar propiedad',
                ),
              ),
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final g in [
                      'Todos',
                      ...widget.bindings
                          .map(
                            (b) => ItemFieldProfile.meaning(
                              widget.entry,
                              b.field.spec.name,
                            ).group,
                          )
                          .toSet(),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(g),
                          selected: group == g,
                          onSelected: (_) => setState(() => group = g),
                        ),
                      ),
                  ],
                ),
              ),
              if (errors.isNotEmpty)
                Text(
                  '${errors.length} error(es). ${errors['batch'] ?? 'Corrige los campos señalados antes de aplicar.'}',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              Expanded(
                child: ListView.builder(
                  itemCount: bindings.length,
                  itemBuilder: (context, index) {
                    final b = bindings[index],
                        f = b.field,
                        m = ItemFieldProfile.meaning(widget.entry, f.spec.name),
                        n = f.spec.name.toLowerCase();
                    final options = fieldChoices(b.document, f.spec.name);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: TextField(
                                  key: ValueKey('property-${b.key}'),
                                  controller: controls[b.key],
                                  readOnly: !b.editable,
                                  maxLines:
                                      f.spec.text &&
                                          (n == 'text' ||
                                              n.contains('description'))
                                      ? 4
                                      : 1,
                                  onChanged: (_) => setState(() {
                                    errors.remove(b.key);
                                  }),
                                  decoration: InputDecoration(
                                    labelText: '${m.label} · ${f.spec.name}',
                                    errorText: errors[b.key],
                                    helperText:
                                        '${f.spec.type} · ${b.document.path.split('/').last} · ${b.editable ? 'valor original' : 'identidad / estructura protegida'}',
                                  ),
                                ),
                              ),
                              if (b.editable && n == 'icon')
                                IconButton(
                                  tooltip: 'Elegir icono original del juego',
                                  icon: const Icon(Icons.grid_view),
                                  onPressed: () async {
                                    final value = await showDialog<int>(
                                      context: context,
                                      builder: (_) => NativeItemIconPicker(
                                        images: widget.images,
                                        type: widget.entry.type,
                                        current:
                                            int.tryParse(
                                              controls[b.key]!.text,
                                            ) ??
                                            0,
                                      ),
                                    );
                                    if (value != null && mounted)
                                      setState(
                                        () => controls[b.key]!.text = '$value',
                                      );
                                  },
                                ),
                              if (b.editable && isAssetField(n))
                                IconButton(
                                  tooltip: 'Elegir archivo DATA',
                                  icon: const Icon(Icons.folder_open),
                                  onPressed: () async {
                                    final value = await pickAsset(
                                      context,
                                      widget.images,
                                      n,
                                      controls[b.key]!.text,
                                    );
                                    if (value != null && mounted)
                                      setState(
                                        () => controls[b.key]!.text = value,
                                      );
                                  },
                                ),
                              if (b.editable && options != null)
                                PopupMenuButton<String>(
                                  tooltip: 'Valores conocidos',
                                  onSelected: (v) =>
                                      setState(() => controls[b.key]!.text = v),
                                  itemBuilder: (_) => [
                                    for (final o in options.entries)
                                      PopupMenuItem(
                                        value: o.key,
                                        child: Text('${o.key} · ${o.value}'),
                                      ),
                                  ],
                                ),
                            ],
                          ),
                          if (b.editable && n == 'icon')
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: DataIcon(
                                images: widget.images,
                                path: widget.session.data.path,
                                summary: RecordSummary(
                                  0,
                                  widget.entry.key,
                                  'Vista previa',
                                  '',
                                  {
                                    'itemtype': '${widget.entry.type}',
                                    'icon': controls[b.key]!.text,
                                  },
                                ),
                                size: 40,
                              ),
                            ),
                          if (f.spec.type != 'opaque')
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                m.help,
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => close(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: apply,
            child: const Text('Aplicar al borrador'),
          ),
        ],
      ),
    );
  }
}

class NativeItemIconPicker extends StatelessWidget {
  final EditorImages images;
  final int type, current;
  const NativeItemIconPicker({
    super.key,
    required this.images,
    required this.type,
    required this.current,
  });
  @override
  Widget build(BuildContext context) {
    final icons = [
      for (var i = 1; i <= 255; i++)
        if (ItemIconLayout.resolve(type, i)?.inBounds == true) i,
    ];
    return AlertDialog(
      title: Text('Iconos originales · tipo $type · ps0032'),
      content: SizedBox(
        width: 700,
        height: 500,
        child: icons.isEmpty
            ? const Text(
                'Tipo no soportado por este perfil nativo. No se asigna un atlas inventado.',
              )
            : GridView.builder(
                itemCount: icons.length,
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 76,
                  mainAxisExtent: 72,
                ),
                itemBuilder: (context, index) {
                  final icon = icons[index],
                      summary = RecordSummary(0, '', 'Icon $icon', '', {
                        'itemtype': '$type',
                        'icon': '$icon',
                      });
                  final available =
                      images.icon('dbitemdata.sdata', summary) != null;
                  return InkWell(
                    onTap: !available
                        ? null
                        : () => Navigator.pop(context, icon),
                    child: Card(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          DataIcon(
                            images: images,
                            path: 'dbitemdata.sdata',
                            summary: summary,
                            size: 36,
                          ),
                          Text(
                            '$icon${icon == current ? ' ✓' : ''}${available ? '' : ' · ?'}',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}
