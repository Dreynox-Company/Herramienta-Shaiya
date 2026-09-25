import 'package:flutter/material.dart';

import '../data/item_workspace.dart';
import '../data/library.dart';
import '../editor/catalog_document.dart';
import '../editor/item_model_catalog.dart';
import '../editor/model_reference.dart';
import '../editor/workbench_model.dart';
import 'editor_model_preview.dart';
import 'editor_style.dart';

typedef ModelPickerPreviewBuilder =
    Widget Function(
      BuildContext context,
      Library library,
      ModelReference model,
      ValueChanged<bool> onReady,
    );

Future<ItemModelChoice?> pickItemModel(
  BuildContext context,
  ItemWorkspace workspace, {
  ItemEntry? item,
  CatalogDocument? document,
  int? currentOrdinal,
  String? currentSource,
}) => showDialog<ItemModelChoice>(
  context: context,
  barrierDismissible: false,
  builder: (_) => ItemModelPicker(
    library: workspace.preview,
    catalog: ItemModelCatalog.load(workspace, item: item, document: document),
    currentOrdinal: currentOrdinal ?? item?.image,
    currentSource: currentSource ?? document?.path,
    validSession: () => !workspace.exporting && !workspace.sourceChanged,
    imageMode: item != null,
  ),
);

/// Selection never mutates the item, catalogue, filesystem or mounted actor.
/// The caller receives a confirmed native choice only after a successful 3D
/// load. Cancel/Escape leave the parent draft unchanged.
class ItemModelPicker extends StatefulWidget {
  final Library library;
  final Future<ItemModelCatalog> catalog;
  final int? currentOrdinal;
  final String? currentSource;
  final bool imageMode;
  final bool Function()? validSession;
  final ModelPickerPreviewBuilder? previewBuilder;
  const ItemModelPicker({
    super.key,
    required this.library,
    required this.catalog,
    this.currentOrdinal,
    this.currentSource,
    this.imageMode = true,
    this.validSession,
    this.previewBuilder,
  });
  @override
  State<ItemModelPicker> createState() => _ItemModelPickerState();
}

class _ItemModelPickerState extends State<ItemModelPicker> {
  final search = TextEditingController();
  final listScroll = ScrollController();
  double rowExtent = 58;

  List<ItemModelChoice> get filtered =>
      catalog?.choices
          .where(
            (c) =>
                c.source == source &&
                (query.isEmpty || c.searchText.contains(foldedSearch(query))),
          )
          .toList() ??
      [];

  void revealSelection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !listScroll.hasClients) return;
      final rows = filtered;
      final index = rows.indexWhere((c) => c.key == selected?.key);
      final top = (index < 0 ? 0 : index) * rowExtent;
      final position = listScroll.position;
      var target = position.pixels;
      if (top < target) target = top;
      if (top + rowExtent > target + position.viewportDimension) {
        target = top + rowExtent - position.viewportDimension;
      }
      listScroll.jumpTo(target.clamp(0.0, position.maxScrollExtent));
    });
  }

  ItemModelCatalog? catalog;
  ItemModelChoice? selected;
  String source = '', query = '';
  String? error;
  bool ready = false;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final result = await widget.catalog;
      if (!mounted) return;
      setState(() {
        catalog = result;
        final sources = result.choices.map((c) => c.source).toSet();
        source = sources.contains(widget.currentSource)
            ? widget.currentSource!
            : sources.firstOrNull ?? '';
        selected =
            result.choices
                .where(
                  (c) =>
                      c.source == source && c.ordinal == widget.currentOrdinal,
                )
                .firstOrNull ??
            result.choices.where((c) => c.source == source).firstOrNull;
      });
      revealSelection();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  void select(ItemModelChoice? value) {
    if (selected?.key == value?.key) return;
    setState(() {
      generation++;
      selected = value;
      ready = false;
    });
    revealSelection();
  }

  void confirm() {
    if (!ready || selected?.available != true) return;
    if (widget.validSession?.call() == false) {
      setState(
        () =>
            error = 'La sesión cambió. Cierra el selector y vuelve a abrirlo.',
      );
      return;
    }
    Navigator.pop(context, selected);
  }

  @override
  void dispose() {
    listScroll.dispose();
    search.dispose();
    super.dispose();
  }

  Widget preview() {
    final choice = selected;
    if (choice == null) {
      return const Center(child: Text('Selecciona un modelo.'));
    }
    final request = generation;
    void onReady(bool value) {
      if (mounted && request == generation && selected?.key == choice.key) {
        setState(() => ready = value);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 80),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Image ${choice.ordinal} · ${baseName(choice.source)}',
                    key: const ValueKey('model-selected-identity'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  for (final part in choice.model.parts)
                    Text(
                      '${baseName(part.$1)} + ${baseName(part.$2)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: !choice.available
              ? Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(
                      'Faltan recursos asociados:\n${choice.missing.join('\n')}\n'
                      'No se aplica una malla sin su textura nativa.',
                    ),
                  ),
                )
              : KeyedSubtree(
                  key: ValueKey('preview-${choice.key}'),
                  child:
                      widget.previewBuilder?.call(
                        context,
                        widget.library,
                        choice.model,
                        onReady,
                      ) ??
                      NativeModelPreview(
                        library: widget.library,
                        model: choice.model,
                        onReadyChanged: onReady,
                      ),
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final sources =
        catalog?.choices.map((c) => c.source).toSet().toList() ?? <String>[];
    final rows = filtered;
    rowExtent = (MediaQuery.textScalerOf(context).scale(11) * 3 + 22)
        .clamp(58, 160)
        .toDouble();
    return Dialog(
      backgroundColor: EditorStyle.surface,
      insetPadding: const EdgeInsets.all(12),
      child: SizedBox(
        width: 1080,
        height: MediaQuery.sizeOf(context).height * .86,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
              child: Row(
                children: [
                  const Icon(Icons.view_in_ar_outlined, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Elegir modelo 3D y textura',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('cancel-model-picker'),
                    tooltip: 'Cancelar',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.imageMode
                          ? 'Cambia Image; conserva Icon e ID.'
                          : 'Cambia el par malla y textura compartido.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Alcance del cambio de modelo',
                    icon: const Icon(Icons.info_outline, size: 17),
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Qué cambia al elegir un modelo'),
                        content: SingleChildScrollView(
                          child: Text(
                            widget.imageMode
                                ? 'Aplica Image al ítem, no su Icon ni su ID. La familia elegida es una vista previa; '
                                      'el cliente usa ese mismo Image en las variantes de cuerpo correspondientes. '
                                      'Seleccionar no modifica datos. Usar modelo prepara el cambio; Aplicar lo confirma en la sesión.'
                                : 'Reasigna el par malla/textura del catálogo. Los ítems que compartan esa entrada también cambiarán. '
                                      'No se sustituyen animaciones ni anclajes de otro modelo automáticamente.',
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Entendido'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: SelectableText(error!),
              ),
            Expanded(
              child: catalog == null
                  ? error == null
                        ? const Center(child: CircularProgressIndicator())
                        : const SizedBox()
                  : catalog!.choices.isEmpty
                  ? const Center(
                      child: Text(
                        'No hay modelos nativos compatibles y resolubles en esta biblioteca.',
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.all(8),
                      child: LayoutBuilder(
                        builder: (ctx, box) {
                          final list = Column(
                            children: [
                              DropdownButtonFormField<String>(
                                key: ValueKey('model-source-$source'),
                                initialValue: source,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Familia / catálogo nativo',
                                ),
                                items: [
                                  for (final path in sources)
                                    DropdownMenuItem(
                                      value: path,
                                      child: Text(
                                        path,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                                onChanged: (value) {
                                  if (value == null) return;
                                  setState(() => source = value);
                                  select(
                                    catalog!.choices
                                            .where(
                                              (c) =>
                                                  c.source == value &&
                                                  c.ordinal ==
                                                      selected?.ordinal,
                                            )
                                            .firstOrNull ??
                                        catalog!.choices
                                            .where((c) => c.source == value)
                                            .firstOrNull,
                                  );
                                },
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                key: const ValueKey('model-picker-search'),
                                controller: search,
                                onChanged: (text) {
                                  setState(() => query = text);
                                  revealSelection();
                                },
                                decoration: const InputDecoration(
                                  prefixIcon: Icon(Icons.search, size: 17),
                                  hintText: 'Nombre, 016, archivo o Image…',
                                ),
                              ),
                              const SizedBox(height: 4),
                              Expanded(
                                child: rows.isEmpty
                                    ? const Center(
                                        child: Text('Sin coincidencias.'),
                                      )
                                    : ListView.builder(
                                        key: const ValueKey(
                                          'model-picker-list',
                                        ),
                                        controller: listScroll,
                                        itemCount: rows.length,
                                        itemExtent: rowExtent,
                                        itemBuilder: (_, i) {
                                          final choice = rows[i];
                                          return ListTile(
                                            key: ValueKey(
                                              'model-choice-${choice.key}',
                                            ),
                                            dense: true,
                                            selected:
                                                selected?.key == choice.key,
                                            leading: Icon(
                                              choice.available
                                                  ? Icons.view_in_ar_outlined
                                                  : Icons.warning_amber,
                                              size: 18,
                                            ),
                                            title: Text(
                                              choice.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            subtitle: Text(
                                              'Image ${choice.ordinal} · ${choice.model.parts.length} partes',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            onTap: () => select(choice),
                                          );
                                        },
                                      ),
                              ),
                              Text(
                                '${rows.length} modelos · ${catalog!.warnings.length} catálogos con advertencias',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          );
                          return box.maxWidth >= 700
                              ? Row(
                                  children: [
                                    SizedBox(
                                      width: box.maxWidth * .4,
                                      child: list,
                                    ),
                                    const VerticalDivider(width: 12),
                                    Expanded(child: preview()),
                                  ],
                                )
                              : Column(
                                  children: [
                                    Expanded(flex: 5, child: list),
                                    const Divider(height: 8),
                                    Expanded(flex: 6, child: preview()),
                                  ],
                                );
                        },
                      ),
                    ),
            ),
            if (catalog?.warnings.isNotEmpty == true)
              TextButton.icon(
                icon: const Icon(Icons.warning_amber, size: 16),
                label: const Text('Diagnóstico de catálogos'),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Catálogos no disponibles'),
                    content: SingleChildScrollView(
                      child: SelectableText(catalog!.warnings.join('\n')),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cerrar'),
                      ),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    ready
                        ? 'Vista 3D cargada · sin cambios aplicados'
                        : 'Selecciona un recurso y espera su validación 3D',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  OverflowBar(
                    alignment: MainAxisAlignment.end,
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancelar'),
                      ),
                      FilledButton.icon(
                        key: const ValueKey('confirm-model-picker'),
                        onPressed: ready && selected?.available == true
                            ? confirm
                            : null,
                        icon: const Icon(Icons.check, size: 16),
                        label: const Text('Usar modelo'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
