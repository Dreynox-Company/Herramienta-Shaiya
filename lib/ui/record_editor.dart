import 'package:flutter/material.dart';

import '../editor/document.dart';
import '../editor/field_semantics.dart';
import '../editor/workbench_model.dart';
import 'editor_icons.dart';
import 'editor_style.dart';
import 'editor_model_preview.dart';
import 'editor_pickers.dart';

class RecordWindowState {
  final EditDocument document;
  final int row;
  final RecordDraft draft;
  final String title;
  Rect rect;
  bool minimized = false;
  RecordWindowState(this.document, this.row, this.title, this.rect)
    : draft = RecordDraft(document, row);
  String get key => '${document.path}#$row';
}

class RecordEditorWindow extends StatefulWidget {
  final RecordWindowState window;
  final EditorImages images;
  final VoidCallback onApply, onClose, onFocus, onMinimize;
  final VoidCallback? onReference;
  final ValueChanged<Offset> onMove, onResize;
  const RecordEditorWindow({
    super.key,
    required this.window,
    required this.images,
    required this.onApply,
    required this.onClose,
    required this.onFocus,
    required this.onMinimize,
    this.onReference,
    required this.onMove,
    required this.onResize,
  });
  @override
  State<RecordEditorWindow> createState() => _RecordEditorWindowState();
}

class _RecordEditorWindowState extends State<RecordEditorWindow> {
  late final Map<String, TextEditingController> controls;
  final search = TextEditingController();
  String section = 'Todos';
  String? error;
  bool changesOnly = false;
  RecordDraft get draft => widget.window.draft;
  @override
  void initState() {
    super.initState();
    controls = {
      for (final e in draft.values.entries)
        e.key: TextEditingController(text: e.value),
    };
  }

  @override
  void dispose() {
    for (final c in controls.values) {
      c.dispose();
    }
    search.dispose();
    super.dispose();
  }

  void apply(bool close) {
    try {
      draft.apply();
      for (final e in controls.entries) {
        e.value.text = draft.values[e.key]!;
      }
      setState(() => error = null);
      widget.onApply();
      if (close) widget.onClose();
    } catch (e) {
      setState(() => error = e.toString());
    }
  }

  Future<void> close() async {
    if (draft.dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Borrador sin aplicar'),
          content: const Text(
            'Este registro tiene cambios de formulario sin aplicar. ¿Descartarlos y cerrar esta ventana?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Seguir editando'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Descartar borrador'),
            ),
          ],
        ),
      );
      if (discard != true) return;
    }
    if (mounted) widget.onClose();
  }

  RecordSummary get currentSummary {
    final old = RecordSummary.from(draft.document, draft.row);
    return RecordSummary(old.row, old.id, old.name, old.category, {
      for (final e in draft.values.entries) e.key.toLowerCase(): e.value,
    });
  }

  void _set(String name, String value) {
    setState(() {
      draft.values[name] = value;
      controls[name]!.text = value;
    });
  }

  Future<void> _asset(String name) async {
    final current = draft.values[name]!,
        path = await pickAsset(context, widget.images, name, current);
    if (path != null && mounted) {
      _set(
        name,
        current.contains('/') || current.contains('\\')
            ? path
            : path.split('/').last,
      );
    }
  }

  Future<void> _icon(String name) async {
    final ref = widget.images.icon(draft.document.path, currentSummary);
    if (ref == null) {
      setState(
        () => error =
            'No se encontró la hoja de iconos para este tipo de registro.',
      );
      return;
    }
    final value = await pickIcon(context, widget.images, ref, ref.index);
    if (value != null && mounted) {
      final old = int.tryParse(draft.values[name]!) ?? 0;
      _set(
        name,
        '${editorDomain(draft.document.path) == EditorDomain.skills ? (old ~/ 256) * 256 + value : value}',
      );
    }
  }

  Widget field(FieldSpan f) {
    final name = f.spec.name,
        meaning = FieldMeaning.of(name),
        changed = draft.values[name] != draft.before[name];
    if (!f.spec.editable || f.spec.type == 'opaque') {
      return Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(border: Border.all(color: EditorStyle.line)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(meaning.label, style: const TextStyle(fontSize: 11)),
            Text(
              '${f.spec.type} · ${f.length} bytes conservados',
              style: const TextStyle(color: EditorStyle.muted, fontSize: 10),
            ),
          ],
        ),
      );
    }
    return Tooltip(
      message:
          '${f.spec.name} · ${f.spec.type}\n${f.spec.limits}\n${meaning.help}',
      waitDuration: const Duration(milliseconds: 600),
      child: TextField(
        key: ValueKey('record-field-$name'),
        controller: controls[name],
        style: const TextStyle(fontSize: 12),
        minLines: 1,
        maxLines: f.spec.text ? 3 : 1,
        keyboardType: f.spec.text
            ? TextInputType.multiline
            : const TextInputType.numberWithOptions(
                signed: true,
                decimal: true,
              ),
        onChanged: (v) => setState(() => draft.values[name] = v),
        decoration: InputDecoration(
          labelText: meaning.label,
          labelStyle: TextStyle(
            fontSize: 11,
            color: changed ? EditorStyle.accent : EditorStyle.muted,
          ),
          helperText: name == meaning.label
              ? f.spec.type
              : '$name · ${f.spec.type}',
          helperStyle: const TextStyle(fontSize: 9),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (fieldChoices(draft.document, name) case final choices?)
                PopupMenuButton<String>(
                  tooltip: 'Opciones del campo',
                  icon: const Icon(Icons.expand_more, size: 17),
                  onSelected: (v) => _set(name, v),
                  itemBuilder: (c) => [
                    for (final e in choices.entries)
                      PopupMenuItem(
                        value: e.key,
                        child: Text('${e.value} (${e.key})'),
                      ),
                  ],
                ),
              if (isAssetField(name) && f.spec.text)
                IconButton(
                  tooltip: 'Elegir recurso de DATA',
                  onPressed: () => _asset(name),
                  icon: const Icon(Icons.folder_open, size: 16),
                ),
              if (name.toLowerCase() == 'icon' ||
                  name.toLowerCase() == 'iconid')
                IconButton(
                  tooltip: 'Elegir icono visualmente',
                  onPressed: () => _icon(name),
                  icon: const Icon(Icons.image_outlined, size: 16),
                ),
              if (changed)
                IconButton(
                  tooltip: 'Restaurar este campo',
                  icon: const Icon(Icons.undo, size: 15),
                  onPressed: () => _set(name, draft.before[name]!),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => widget.onFocus(),
    child: Material(
      elevation: 18,
      shadowColor: Colors.black54,
      color: EditorStyle.surface,
      borderRadius: BorderRadius.circular(7),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: EditorStyle.line),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Column(
          children: [
            GestureDetector(
              onPanUpdate: (d) => widget.onMove(d.delta),
              child: Container(
                height: 40,
                color: EditorStyle.panel,
                padding: const EdgeInsets.only(left: 12, right: 5),
                child: Row(
                  children: [
                    Icon(
                      domainIcon(editorDomain(widget.window.document.path)),
                      size: 17,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${draft.dirty ? '● ' : ''}${widget.window.title}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Minimizar ventana',
                      onPressed: widget.onMinimize,
                      icon: const Icon(Icons.remove),
                    ),
                    IconButton(
                      tooltip: 'Cerrar registro',
                      onPressed: close,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  DataIcon(
                    images: widget.images,
                    path: draft.document.path,
                    summary: currentSummary,
                    size: 42,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.window.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '${draft.document.profile} · ${draft.fields.length} campos · ${draft.document.authority}',
                          maxLines: 2,
                          style: const TextStyle(
                            fontSize: 10,
                            color: EditorStyle.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: TextButton.icon(
                  icon: const Icon(Icons.view_in_ar_outlined, size: 16),
                  label: const Text('Ver modelo / animaciones'),
                  onPressed: () {
                    try {
                      showEditorModel(
                        context,
                        widget.images.library,
                        draft.previewDocument(),
                        draft.row,
                      );
                    } catch (e) {
                      setState(() => error = '$e');
                    }
                  },
                ),
              ),
            ),
            if (widget.onReference != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TextButton.icon(
                    icon: const Icon(Icons.link, size: 16),
                    label: const Text(
                      'Objetos, botín y habilidades relacionados',
                    ),
                    onPressed: widget.onReference,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: search,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        hintText: 'Buscar parámetro…',
                        prefixIcon: Icon(Icons.search, size: 16),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Mostrar solo los campos que has cambiado',
                    child: FilterChip(
                      label: Text('Cambios ${draft.changes}'),
                      selected: changesOnly,
                      onSelected: (v) => setState(() => changesOnly = v),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  final groups = [
                    'Todos',
                    ...FieldMeaning.groups.where(
                      (g) =>
                          g != 'Todos' &&
                          draft.fields.values.any(
                            (f) => FieldMeaning.of(f.spec.name).group == g,
                          ),
                    ),
                  ];
                  final q = foldedSearch(search.text);
                  final fs = draft.fields.values.where((f) {
                    final m = FieldMeaning.of(f.spec.name);
                    return (section == 'Todos' || m.group == section) &&
                        (!changesOnly ||
                            draft.before[f.spec.name] !=
                                draft.values[f.spec.name]) &&
                        (q.isEmpty ||
                            foldedSearch('${m.label} ${f.spec.name}')
                                .contains(q));
                  }).toList();
                  final narrow = box.maxWidth < 620;
                  final menu = narrow
                      ? SizedBox(
                          height: 40,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: groups
                                  .map(
                                    (g) => Padding(
                                      padding: const EdgeInsets.only(left: 5),
                                      child: ChoiceChip(
                                        label: Text(g),
                                        selected: section == g,
                                        onSelected: (_) =>
                                            setState(() => section = g),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                        )
                      : SizedBox(
                          width: 160,
                          child: ListView(
                            children: groups
                                .map(
                                  (g) => ListTile(
                                    dense: true,
                                    selected: section == g,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    title: Text(
                                      g,
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    onTap: () => setState(() => section = g),
                                  ),
                                )
                                .toList(),
                          ),
                        );
                  final form = Expanded(
                    child: LayoutBuilder(
                      builder: (c, b) {
                        final columns = b.maxWidth < 390
                            ? 1
                            : b.maxWidth < 740
                            ? 2
                            : 3;
                        final width =
                            (b.maxWidth - 32 - (columns - 1) * 14) / columns;
                        return SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Wrap(
                            spacing: 14,
                            runSpacing: 16,
                            children: fs
                                .map(
                                  (f) => SizedBox(
                                    width: f.spec.text
                                        ? b.maxWidth - 32
                                        : width,
                                    child: field(f),
                                  ),
                                )
                                .toList(),
                          ),
                        );
                      },
                    ),
                  );
                  return narrow
                      ? Column(children: [menu, form])
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            menu,
                            const VerticalDivider(width: 1),
                            form,
                          ],
                        );
                },
              ),
            ),
            if (error != null)
              Container(
                width: double.infinity,
                color: const Color(0xff492b27),
                padding: const EdgeInsets.all(9),
                child: Text(
                  error!,
                  maxLines: 3,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xffffc6aa),
                  ),
                ),
              ),
            Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: EditorStyle.line)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${draft.changes} cambios sin aplicar',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: EditorStyle.muted,
                        fontSize: 10,
                      ),
                    ),
                  ),
                  TextButton(onPressed: close, child: const Text('Cancelar')),
                  const SizedBox(width: 5),
                  OutlinedButton(
                    key: const ValueKey('record-apply'),
                    onPressed: () => apply(false),
                    child: const Text('Aplicar'),
                  ),
                  const SizedBox(width: 5),
                  FilledButton(
                    key: const ValueKey('record-accept'),
                    onPressed: () => apply(true),
                    child: const Text('Aceptar'),
                  ),
                  GestureDetector(
                    onPanUpdate: (d) => widget.onResize(d.delta),
                    child: const MouseRegion(
                      cursor: SystemMouseCursors.resizeDownRight,
                      child: Padding(
                        padding: EdgeInsets.only(left: 5),
                        child: Icon(Icons.drag_handle, size: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
