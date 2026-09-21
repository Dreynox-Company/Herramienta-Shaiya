import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../core/game_text_codec.dart';
import '../data/library.dart';
import '../data/archive_export.dart';
import '../data/archive_write.dart';
import '../data/file_save.dart';
import '../data/directory_pack.dart';
import '../editor/document.dart';
import '../editor/schema_reader.dart';
import '../editor/csv_document.dart';
import '../editor/catalog_document.dart';
import '../editor/text_document.dart';
import '../editor/field_semantics.dart';
import '../core/client_locale.dart';
import '../editor/workbench_model.dart';
import '../editor/structure_editor.dart';
import 'editor_style.dart';
import 'editor_icons.dart';
import 'editor_catalog.dart';
import 'editor_map.dart';
import 'editor_relations.dart';
import 'record_editor.dart';

EditDocument parseEditorDocument(Map<String, Object?> args) {
  final bytes = args['bytes']! as Uint8List,
      path = args['path']! as String,
      chosen = GameTextEncoding.values.byName(args['encoding']! as String);
  final encoding = chosen == GameTextEncoding.automatic
      ? ClientLocale.encodingForPath(path)
      : chosen;
  if (RegExp(r'\.(mlt|itm|mon)$', caseSensitive: false).hasMatch(path)) {
    return CatalogDocument.open(bytes, path, encoding);
  }
  if (RegExp(r'\.(ini|cfg|txt|xml)$', caseSensitive: false).hasMatch(path)) {
    return TextDocument.open(bytes, path, encoding);
  }
  return path.toLowerCase().endsWith('.csv')
      ? CsvDocument.open(bytes, path, encoding)
      : EditorReader.open(bytes, path, encoding: encoding);
}

class _EditorUndo extends Intent {
  const _EditorUndo();
}

class _EditorRedo extends Intent {
  const _EditorRedo();
}

class _EditorSave extends Intent {
  const _EditorSave();
}

/// Dedicated multi-document editor. Changes are explicit, version checked and
/// committed transactionally; Save As retains the original source.
class DataEditorPage extends StatefulWidget {
  final Library library;
  final GameTextEncoding initialEncoding;
  const DataEditorPage({
    super.key,
    required this.library,
    this.initialEncoding = GameTextEncoding.automatic,
  });
  @override
  State<DataEditorPage> createState() => _DataEditorPageState();
}

class _DataEditorPageState extends State<DataEditorPage> {
  final _filesQuery = TextEditingController(),
      _rowsQuery = TextEditingController(),
      _fieldQuery = TextEditingController();
  final _cache = <String, EditDocument>{};
  final _views = <String, (String, int, String, String)>{};
  final _summaries = <int, RecordSummary>{};
  final _windows = <RecordWindowState>[];
  late final EditorImages _images;
  String sortColumn = '@id';
  bool descending = false, showInspector = true;
  double explorerWidth = 220, inspectorWidth = 290;
  Size workspaceSize = const Size(1200, 700);
  bool get hasDrafts => _windows.any((w) => w.draft.dirty);
  RecordSummary _summary(int row) => _summaries.putIfAbsent(row, () {
    final base = RecordSummary.from(doc!, row);
    return RecordSummary.from(doc!, row, name: _lookup[base.id]);
  });
  void _remember() {
    if (doc != null) {
      _views[doc!.path] = (
        _rowsQuery.text,
        selected,
        classFilter,
        factionFilter,
      );
    }
  }

  void _openRecord(int row) {
    if (doc == null || row < 0 || row >= doc!.rows.length) return;
    final existing = _windows
        .where((w) => w.document == doc && w.row == row)
        .firstOrNull;
    if (existing != null) {
      setState(() {
        _windows.remove(existing);
        existing.minimized = false;
        _windows.add(existing);
      });
      return;
    }
    if (_windows.length >= 12) {
      _note(
        'Hay 12 registros abiertos. Cierra una ventana antes de abrir otra.',
      );
      return;
    }
    final x = workspaceSize.width > 800
        ? 110.0 + (_windows.length % 5) * 22
        : 8.0;
    final width = (workspaceSize.width - 32).clamp(280.0, 1000.0),
        height = (workspaceSize.height - 32).clamp(250.0, 680.0);
    setState(
      () => _windows.add(
        RecordWindowState(
          doc!,
          row,
          _label(row),
          Rect.fromLTWH(
            x.clamp(8, workspaceSize.width - width - 8),
            16,
            width,
            height,
          ),
        ),
      ),
    );
  }

  Rect _bound(Rect r) {
    final w = r.width.clamp(
          280.0,
          (workspaceSize.width - 16).clamp(280.0, 1600.0),
        ),
        h = r.height.clamp(
          280.0,
          (workspaceSize.height - 16).clamp(280.0, 1000.0),
        );
    return Rect.fromLTWH(
      r.left.clamp(8.0, (workspaceSize.width - w - 8).clamp(8.0, 2000.0)),
      r.top.clamp(8.0, (workspaceSize.height - h - 8).clamp(8.0, 2000.0)),
      w,
      h,
    );
  }

  final _labels = <int, String>{};
  final _lookup = <String, String>{};
  final _scaffold = GlobalKey<ScaffoldState>();
  EditDocument? doc;
  GameTextEncoding encoding = GameTextEncoding.automatic;
  List<int> visible = [];
  int selected = 0, tab = 0, _generation = 0;
  bool busy = false, showFiles = true, leaving = false;
  String status =
          'Abre una tabla de la biblioteca o importa un CSV del servidor.',
      group = 'Todos',
      fileCategory = 'Todos',
      classFilter = 'Todas',
      factionFilter = 'Todas';
  ExportControl? exporting;
  ExportProgress? progress;
  Timer? debounce;
  List<String> get paths =>
      {...widget.library.files.keys, ..._cache.keys}
          .where(
            (p) => [
              '.sdata',
              '.svmap',
              '.csv',
              '.mlt',
              '.itm',
              '.mon',
              '.ini',
              '.cfg',
              '.txt',
              '.xml',
            ].any(p.toLowerCase().endsWith),
          )
          .toList()
        ..sort();
  bool get dirty => _cache.values.any((d) => d.dirty);
  bool keepBackup = false;
  @override
  void initState() {
    super.initState();
    encoding = widget.initialEncoding;
    _images = EditorImages(widget.library);
  }

  @override
  void dispose() {
    debounce?.cancel();
    _images.dispose();
    _generation++;
    exporting?.cancelled = true;
    _filesQuery.dispose();
    _rowsQuery.dispose();
    _fieldQuery.dispose();
    super.dispose();
  }

  void _note(String s) {
    if (mounted) setState(() => status = s);
  }

  Future<void> _job(Future<void> Function() fn) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await fn();
    } catch (e) {
      _note('No se aplicó la operación: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), duration: const Duration(seconds: 8)),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<bool> _confirm(String title, String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(text),
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
  Future<void> _leave() async {
    if (busy) {
      _note('Espera la operación o cancela la exportación antes de cerrar.');
      return;
    }
    if ((dirty || hasDrafts) &&
        !await _confirm(
          'Cambios sin guardar',
          'Hay cambios recientes que todavía no se han guardado. Volver al visor los descarta; los guardados anteriormente se conservan. ¿Descartar y continuar?',
        )) {
      return;
    }
    if (mounted) {
      setState(() => leaving = true);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> openTable(String path, {bool reload = false}) => _job(() async {
    _remember();
    final generation = ++_generation;
    if (!reload && _cache.containsKey(path)) {
      doc = _cache[path];
    } else {
      final bytes = await widget.library.read(path, limit: 128 * 1024 * 1024);
      final cachedBytes = _cache.values.fold<int>(
        0,
        (n, d) => n + d.payload.length + d.original.length,
      );
      if (cachedBytes + bytes.length * 2 > 512 * 1024 * 1024) {
        throw const FormatException(
          'La sesión alcanza 512 MiB de tablas. Exporta y vuelve a abrir el editor para liberar memoria.',
        );
      }
      final parsed = await compute(parseEditorDocument, {
        'bytes': bytes,
        'path': path,
        'encoding': encoding.name,
      });
      if (!mounted || generation != _generation) return;
      _cache[path] = parsed;
      doc = parsed;
    }
    await _loadNames(path);
    final view = _views[path];
    selected = view?.$2 ?? 0;
    group = 'Todos';
    _labels.clear();
    _summaries.clear();
    _rowsQuery.text = view?.$1 ?? '';
    _fieldQuery.clear();
    classFilter = view?.$3 ?? 'Todas';
    factionFilter = view?.$4 ?? 'Todas';
    _filter();
    _note(
      '${doc!.rows.length} registros · ${doc!.profile} · ${doc!.codec.encoding.label}',
    );
    if (_scaffold.currentState?.isDrawerOpen ?? false) {
      _scaffold.currentState!.closeDrawer();
    }
  });
  Future<void> _loadNames(String path) async {
    _lookup.clear();
    final prefix = ClientLocale.nameFamily(path);
    if (prefix == null) return;
    var beside = path;
    // Classic Item/Skill/Monster tables have implicit IDs and separate binary
    // tables. Their localized names are a reference, not a schema conversion.
    if (!baseName(path).toLowerCase().startsWith('db') &&
        prefix != 'npcquesttrans') {
      beside = 'binarysdata/reference.sdata';
    }
    final candidates = ClientLocale.tableCandidates(
      widget.library.files.keys,
      prefix,
      beside: beside,
    );
    if (candidates.isEmpty) return;
    try {
      final textDoc = await compute(parseEditorDocument, {
        'bytes': await widget.library.read(candidates.first),
        'path': candidates.first,
        'encoding': ClientLocale.encodingForPath(
          candidates.first,
          fallback: encoding,
        ).name,
      });
      for (var i = 0; i < textDoc.rows.length; i++) {
        final fs = textDoc.fields(i);
        final name = fs.where((f) => f.spec.text).firstOrNull;
        if (name == null) continue;
        final values = {
          for (final f in fs)
            if (!f.spec.text && f.spec.type != 'opaque')
              f.spec.name.toLowerCase(): textDoc.read(f),
        };
        final key = editorIdentityKey(values, textDoc.rows[i]);
        _lookup[key] = textDoc.read(name);
      }
    } catch (e) {
      _note('La tabla es editable; no se pudo cargar su tabla de nombres: $e');
    }
  }

  Map<String, String> _values(int row) {
    final d = doc!;
    return {
      for (final f in d.fields(row))
        if (f.spec.type != 'opaque') f.spec.name.toLowerCase(): d.read(f),
    };
  }

  String _label(int row) => _labels.putIfAbsent(row, () {
    final d = doc!, rec = d.rows[row], fs = d.fields(row);
    String? pick(List<String> names) {
      for (final n in names) {
        final f = fs.where((f) => f.spec.name.toLowerCase() == n).firstOrNull;
        if (f != null) return d.read(f);
      }
      return null;
    }

    final name = pick([
      'name',
      'productname',
      'mobname',
      'itemname',
      'skillname',
    ]);
    final id = editorIdentityKey(_values(row), rec);
    final mapped = _lookup[id];
    return '$id · ${name?.isNotEmpty == true ? name : mapped ?? rec.kind}';
  });
  void _filter() {
    final d = doc;
    if (d == null) return;
    final q = foldedSearch(_rowsQuery.text.trim());
    final out = <int>[];
    for (var i = 0; i < d.rows.length; i++) {
      if (q.isNotEmpty && !foldedSearch(_label(i)).contains(q)) continue;
      if (classFilter != 'Todas' || factionFilter != 'Todas') {
        final v = _values(i);
        if (classFilter != 'Todas') {
          if (!editorMatchesClass(v, classFilter)) continue;
        }
        if (factionFilter != 'Todas') {
          final value = v['country'] ?? v['faction'];
          if (value == null || value != factionFilter) continue;
        }
      }
      out.add(i);
    }
    out.sort((a, b) {
      String val(int row) {
        final v = _summary(row);
        return switch (sortColumn) {
          '@id' => v.id,
          '@name' => v.name,
          '@category' => v.category,
          _ => v.values[sortColumn] ?? '',
        };
      }

      final c = compareEditorValues(val(a), val(b));
      return (descending ? -c : c);
    });
    visible = out;
    if (out.isNotEmpty && !out.contains(selected)) selected = out.first;
    if (mounted) setState(() {});
  }

  void _queueFilter() {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 220), _filter);
  }

  void _refresh() {
    _labels.clear();
    _summaries.clear();
    _filter();
  }

  Future<void> _encoding(GameTextEncoding next) async {
    if (next == encoding) return;
    if (dirty &&
        !await _confirm(
          'Cambiar codificación',
          'Hay cambios sin exportar. Reinterpretar las tablas los descartará. Exporta primero si necesitas conservarlos.',
        )) {
      return;
    }
    final path = doc?.path;
    if (hasDrafts) {
      _note('Aplica o cierra los borradores antes de cambiar la codificación.');
      return;
    }
    _windows.clear();
    _views.clear();
    _summaries.clear();
    _cache.clear();
    doc = null;
    _lookup.clear();
    _labels.clear();
    visible = [];
    setState(() => encoding = next);
    if (path != null && widget.library.files.containsKey(path)) {
      await openTable(path, reload: true);
    }
  }

  Future<void> _edit(FieldSpan field) async {
    final d = doc!;
    if (!field.spec.editable || field.spec.type == 'opaque') {
      _binaryDialog(field);
      return;
    }
    final controller = TextEditingController(text: d.read(field));
    String? error;
    var all = false;
    final dialogRoute = DialogRoute<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: Text(FieldMeaning.of(field.spec.name).label),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    '${field.spec.name} · ${field.spec.type} · byte ${field.start}',
                    style: Theme.of(c).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Text(field.spec.limits),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('editor-field-input'),
                    controller: controller,
                    autofocus: true,
                    maxLines: field.spec.text ? 6 : 1,
                    decoration: InputDecoration(
                      labelText: 'Valor',
                      errorText: error,
                    ),
                    keyboardType: field.spec.text
                        ? TextInputType.multiline
                        : const TextInputType.numberWithOptions(
                            signed: true,
                            decimal: true,
                          ),
                  ),
                  const SizedBox(height: 10),
                  Text(FieldMeaning.of(field.spec.name).help),
                  if (visible.length > 1)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: all,
                      onChanged: (v) => update(() => all = v!),
                      title: Text(
                        'Aplicar a ${visible.length} registros filtrados que contienen este campo',
                      ),
                    ),
                  if (d.profile == 'server-csv')
                    const Text(
                      'Al exportar cambios, este CSV se guarda como UTF-8. No ejecuta SQL ni actualiza el servidor.',
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              key: const ValueKey('editor-apply'),
              onPressed: () {
                try {
                  final edits = <(int, FieldSpan, String)>[];
                  for (final row in all ? visible : [selected]) {
                    final f = d
                        .fields(row)
                        .where(
                          (s) =>
                              s.spec.name == field.spec.name &&
                              s.spec.type == field.spec.type,
                        )
                        .firstOrNull;
                    if (f != null) edits.add((row, f, controller.text));
                  }
                  d.editMany(
                    edits,
                    title: all
                        ? 'Edición de ${edits.length} registros'
                        : 'Editar ${field.spec.name}',
                  );
                  _refresh();
                  Navigator.pop(c);
                } catch (e) {
                  update(() => error = '$e');
                }
              },
              child: const Text('Aplicar'),
            ),
          ],
        ),
      ),
    );
    await Navigator.of(context, rootNavigator: true).push(dialogRoute);
    await dialogRoute.completed;
    controller.dispose();
  }

  Future<void> _binaryDialog(FieldSpan field) async {
    final d = doc!;
    var page = 0;
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) {
          final start = field.start + page * 1024,
              end = (start + 1024).clamp(start, field.start + field.length),
              b = d.payload.sublist(start, end);
          final lines = <String>[];
          for (var i = 0; i < b.length; i += 16) {
            final part = b.sublist(i, (i + 16).clamp(i, b.length));
            lines.add(
              '${(start + i).toRadixString(16).padLeft(8, '0')}  ${part.map((v) => v.toRadixString(16).padLeft(2, '0')).join(' ')}',
            );
          }
          return AlertDialog(
            title: Text('Bytes conservados · ${field.length} bytes'),
            content: SizedBox(
              width: 700,
              height: 470,
              child: SingleChildScrollView(
                child: SelectableText(
                  lines.join('\n'),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: page == 0 ? null : () => update(() => page--),
                child: const Text('Anterior'),
              ),
              Text(
                '${page + 1} / ${(field.length / 1024).ceil().clamp(1, 1000000)}',
              ),
              TextButton(
                onPressed: end >= field.start + field.length
                    ? null
                    : () => update(() => page++),
                child: const Text('Siguiente'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Cerrar'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _duplicateSelected() async {
    final d = doc;
    if (d == null || !StructureEditor.supported(d) || visible.isEmpty) return;
    if (_windows.any((w) => w.document == d && w.draft.dirty)) {
      _note(
        'Aplica o cancela los borradores de esta tabla antes de crear filas.',
      );
      return;
    }
    final row = selected, ids = StructureEditor.identity(d, row);
    final controls = {
      for (final f in ids) f.spec.name: TextEditingController(text: d.read(f)),
    };
    String? error;
    final route = DialogRoute<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: const Text('Duplicar como registro nuevo'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'La nueva clave debe estar libre. Se conservan los parámetros del registro. Las tablas de nombres y las referencias del servidor se editan por separado.',
                ),
                const SizedBox(height: 16),
                ...ids.map(
                  (f) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      controller: controls[f.spec.name],
                      decoration: InputDecoration(
                        labelText: FieldMeaning.of(f.spec.name).label,
                        helperText: f.spec.name,
                      ),
                    ),
                  ),
                ),
                if (error != null)
                  Text(error!, style: const TextStyle(color: Colors.orange)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                try {
                  StructureEditor.duplicate(d, row, {
                    for (final e in controls.entries) e.key: e.value.text,
                  });
                  _windows.removeWhere((w) => w.document == d);
                  selected = d.rows.length - 1;
                  _refresh();
                  Navigator.pop(c, true);
                } catch (e) {
                  update(() => error = '$e');
                }
              },
              child: const Text('Crear registro'),
            ),
          ],
        ),
      ),
    );
    final created = await Navigator.of(context).push(route);
    await route.completed;
    for (final c in controls.values) {
      c.dispose();
    }
    if (created == true && mounted) _openRecord(selected);
  }

  Future<void> _deleteSelected() async {
    final d = doc;
    if (d == null || !StructureEditor.supported(d) || visible.isEmpty) return;
    if (_windows.any((w) => w.document == d && w.draft.dirty)) {
      _note('Aplica o cancela los borradores antes de eliminar filas.');
      return;
    }
    if (!await _confirm(
      'Eliminar ${_summary(selected).id}',
      'Se elimina esta fila de la tabla con ID explícito. No se eliminan automáticamente objetos de tiendas, botín ni otras referencias. Puedes deshacer antes de guardar. ¿Continuar?',
    )) {
      return;
    }
    try {
      StructureEditor.delete(d, selected);
      _windows.removeWhere((w) => w.document == d);
      _refresh();
    } catch (e) {
      _note('$e');
    }
  }

  Future<void> _saveChanges() => _job(() async {
    if (hasDrafts) {
      throw const FormatException(
        'Aplica o cancela los borradores de las ventanas antes de guardar.',
      );
    }
    final changed = _cache.values.where((d) => d.dirty).toList();
    if (changed.isEmpty) {
      _note('No hay cambios nuevos para guardar.');
      return;
    }
    final library = widget.library, source = library.archive;
    if (library.saf || source != null && source.sahPath == null) {
      throw const FormatException(
        'El proveedor Android concede solo lectura. Exporta una copia o abre los archivos en Windows para guardarlos en su ubicación.',
      );
    }
    if (changed.any((d) => !library.files.containsKey(d.path))) {
      throw const FormatException(
        'Hay archivos importados externos. Guárdalos como copia antes de guardar esta biblioteca.',
      );
    }
    final saveMessage = library.isSpkWorkspace
        ? '${changed.length} archivos modificados. Se guardarán en un overlay '
              'editable asociado a este DATA.SPK; el SPK original permanece '
              'intacto. Studio releerá el overlay inmediatamente para que los '
              'cambios se reflejen en tablas y vista 3D. Los datos del servidor '
              'se gestionan por separado.'
        : '${changed.length} archivos modificados. Se guardarán en la '
              'biblioteca que abriste, no en una copia adicional. Cierra el '
              'juego antes de continuar. Los datos del servidor se gestionan '
              'por separado.';
    if (!await _confirm('Guardar cambios', saveMessage)) {
      return;
    }
    final output = <String, Uint8List>{};
    final fresh = <String, EditDocument>{};
    for (final d in changed) {
      final b = d.exportBytes(), check = reopenDocument(d, b);
      if (!check.complete ||
          check.profile != d.profile ||
          check.rows.length != d.rows.length) {
        throw FormatException('Relectura fallida: ${d.path}');
      }
      for (final c in d.changes) {
        final f = check
            .fields(c.row)
            .singleWhere((f) => f.spec.name == c.field.spec.name);
        if (check.read(f) != c.afterText) {
          throw FormatException('Valor no conservado: ${c.field.spec.name}');
        }
      }
      output[d.path] = b;
      fresh[d.path] = check;
    }
    if (library.isSpkWorkspace) {
      progress = 'Verificando y escribiendo overlay SPK…';
      if (mounted) setState(() {});
      try {
        await library.writeSpkOverlay(
          output,
          expectedHashes: {for (final d in changed) d.path: d.sha},
          keepBackup: keepBackup,
        );
      } finally {
        progress = null;
      }
      for (final d in changed) {
        _cache[d.path] = fresh[d.path]!;
      }
    } else if (source != null) {
      final archiveOutput = <String, Uint8List>{
        for (final entry in output.entries)
          library.files[entry.key]!: entry.value,
      };
      final control = ExportControl();
      exporting = control;
      try {
        await ArchiveWriter.writeInPlace(
          source,
          archiveOutput,
          expectedHashes: {
            for (final d in changed) library.files[d.path]!: d.sha,
          },
          control: control,
          keepBackup: keepBackup,
          progress: (p) {
            if (mounted) setState(() => progress = p);
          },
        );
      } finally {
        exporting = null;
        progress = null;
      }
      for (final d in changed) {
        _cache[d.path] = fresh[d.path]!;
      }
    } else {
      // Each file is an independent atomic save. A later failure does not roll
      // back an earlier completed file: its in-memory baseline is updated now.
      for (final d in changed) {
        await FileSave.replace(
          library.files[d.path]!,
          output[d.path]!,
          expectedHash: d.sha,
          keepBackup: keepBackup,
        );
        _cache[d.path] = fresh[d.path]!;
        _windows.removeWhere((w) => w.document == d);
        if (doc == d) doc = fresh[d.path]!;
        library.revision++;
        _refresh();
      }
    }
    _windows.removeWhere((w) => changed.contains(w.document));
    if (doc != null) doc = _cache[doc!.path];
    library.revision++;
    _refresh();
    _note(
      library.isSpkWorkspace
          ? '${changed.length} archivos guardados en el overlay SPK y '
                'releídos. El DATA.SPK original no fue modificado.'
          : '${changed.length} archivos guardados y releídos en la biblioteca original.',
    );
  });
  Future<void> _buildDirectory() => _job(() async {
    if (hasDrafts) {
      throw const FormatException(
        'Aplica los borradores antes de construir el archivo.',
      );
    }
    if (widget.library.isSpkWorkspace) {
      throw const FormatException(
        'El workspace SPK usa un overlay editable. Para construir SAH/SAF, '
        'extrae primero una DATA completa desde el explorador SPK.',
      );
    }
    if (widget.library.archive != null || widget.library.saf) {
      throw const FormatException('Se necesita una carpeta DATA local.');
    }
    final parent = await getDirectoryPath(
      confirmButtonText: 'Construir SAH/SAF aquí',
    );
    if (parent == null) return;
    final c = ExportControl();
    exporting = c;
    try {
      final replacements = <String, Uint8List>{};
      for (final d in _cache.values.where((d) => d.dirty)) {
        if (!widget.library.files.containsKey(d.path)) {
          throw const FormatException(
            'Una tabla importada no pertenece a DATA.',
          );
        }
        final b = d.exportBytes(), check = reopenDocument(d, b);
        if (!check.complete ||
            check.profile != d.profile ||
            check.rows.length != d.rows.length) {
          throw const FormatException(
            'Una tabla editada no supera la relectura.',
          );
        }
        replacements[d.path] = b;
      }
      final r = await DirectoryPack.build(
        Directory(widget.library.location),
        Directory(parent),
        replacements: replacements,
        control: c,
        progress: (p) {
          if (mounted) setState(() => progress = p);
        },
      );
      _note(
        'Construido y verificado: ${r.folder} · ${r.files} recursos, incluidos los formatos no visualizables.',
      );
    } finally {
      exporting = null;
      progress = null;
    }
  });
  Future<void> _recoverArchive() => _job(() async {
    final s = widget.library.archive;
    if (s?.sahPath == null) {
      throw const FormatException('Abre un par SAH/SAF local.');
    }
    final outcome = await ArchiveWriter.recover(s!.sahPath!, s.safPath!);
    await s.refreshAfterWrite();
    _note(outcome);
  });

  Future<String?> _save(String name, Uint8List bytes) async {
    if (Platform.isAndroid) {
      // Scoped application folder, never all-files storage permission.
      final base = await getApplicationDocumentsDirectory();
      final folder = Directory('${base.path}/ShaiyaEditor/Exportaciones');
      await folder.create(recursive: true);
      final file = File(
        '${folder.path}/${DateTime.now().microsecondsSinceEpoch}_$name',
      );
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    }
    final target = await getSaveLocation(
      suggestedName: name,
      confirmButtonText: 'Guardar copia',
    );
    if (target == null) return null;
    // Even file-selector overwrite acceptance does not overwrite input files.
    final path = target.path;
    for (final input in widget.library.files.values) {
      if (input.replaceAll('\\', '/').toLowerCase() ==
          path.replaceAll('\\', '/').toLowerCase()) {
        throw const FormatException(
          'Elige una ruta de copia, no el archivo original de DATA.',
        );
      }
    }
    if (await File(path).exists()) {
      throw const FormatException(
        'El destino ya existe. Usa un nombre nuevo para conservar las copias anteriores.',
      );
    }
    final temp = File('$path.${DateTime.now().microsecondsSinceEpoch}.partial');
    try {
      await temp.writeAsBytes(bytes, flush: true);
      final saved = await temp.readAsBytes();
      if (!listEquals(saved, bytes)) {
        throw const FormatException('La copia escrita no coincide.');
      }
      if (await File(path).exists()) {
        throw const FormatException('El destino fue creado por otro proceso.');
      }
      await temp.rename(path);
    } catch (_) {
      if (await temp.exists()) await temp.delete();
      rethrow;
    }
    return path;
  }

  Future<void> _exportDocument() => _job(() async {
    final d = doc!;
    final warnings = d.changes
        .map((c) => c.row)
        .toSet()
        .expand((r) => rowWarnings(d, r))
        .take(30)
        .toList();
    if (!await _confirm(
      'Exportar copia verificada',
      '${d.changeCount} campos modificados. El original no se sobrescribe.\n\n${warnings.isEmpty ? 'La copia del cliente NO actualiza el servidor. Instálala solo en un entorno de prueba con datos compatibles.' : warnings.join('\n')}',
    )) {
      return;
    }
    final bytes = d.exportBytes();
    final check = reopenDocument(d, bytes);
    if (check.profile != d.profile || check.rows.length != d.rows.length) {
      throw const FormatException(
        'La relectura cambió el perfil o la cantidad de registros.',
      );
    }
    for (final c in d.changes) {
      final f = check
          .fields(c.row)
          .where((f) => f.spec.name == c.field.spec.name)
          .single;
      if (check.read(f) != c.afterText) {
        throw FormatException(
          'No se conservó el valor de ${c.field.spec.name}.',
        );
      }
    }
    final target = await _save(baseName(d.path), bytes);
    if (target != null) {
      _note(
        'Copia verificada: $target · ${d.changeCount} cambios siguen en la sesión para revisión.',
      );
    }
  });
  Future<void> _patch(bool import) => _job(() async {
    final d = doc!;
    if (import) {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(label: 'Parche de editor', extensions: ['json']),
        ],
      );
      if (file == null) return;
      if (await file.length() > 32 * 1024 * 1024) {
        throw const FormatException('Parche demasiado grande.');
      }
      d.importPatch(await file.readAsString());
      _refresh();
      _note('Parche aplicado de forma atómica y reversible.');
    } else {
      final p = await _save(
        '${baseName(d.path)}.patch.json',
        Uint8List.fromList(utf8.encode(d.exportPatch())),
      );
      if (p != null) _note('Parche con SHA-256 guardado: $p');
    }
  });
  Future<void> _importTable() => _job(() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: 'Tablas, catálogos y configuración',
          extensions: [
            'sdata',
            'svmap',
            'csv',
            'mlt',
            'itm',
            'mon',
            'ini',
            'cfg',
            'txt',
            'xml',
          ],
        ),
      ],
    );
    if (file == null) return;
    if (await file.length() > 128 * 1024 * 1024) {
      throw const FormatException('Archivo demasiado grande.');
    }
    final retainedBytes = _cache.values.fold<int>(
      0,
      (n, d) => n + d.original.length + d.payload.length,
    );
    if (retainedBytes + (await file.length()) * 2 > 512 * 1024 * 1024) {
      throw const FormatException(
        'La sesión alcanza el límite de memoria. Exporta y vuelve a abrir el editor.',
      );
    }
    final path = 'Importado/${file.name}',
        data = await compute(parseEditorDocument, {
          'bytes': await file.readAsBytes(),
          'path': path,
          'encoding': encoding.name,
        });
    if (_cache[path]?.dirty == true) {
      throw const FormatException(
        'Ya hay una tabla importada con ese nombre y cambios pendientes.',
      );
    }
    _cache[path] = data;
    doc = data;
    selected = 0;
    _lookup.clear();
    _rowsQuery.clear();
    _fieldQuery.clear();
    _labels.clear();
    group = 'Todos';
    classFilter = 'Todas';
    factionFilter = 'Todas';
    _filter();
    _note('Tabla importada · ${data.authority}');
  });
  Future<void> _exportArchive(bool pack) => _job(() async {
    final source = widget.library.archive!;
    if (!await _confirm(
      pack ? 'Construir SAH/SAF editado' : 'Extraer todos los recursos',
      pack
          ? 'Se crea un par estándar nuevo con las tablas modificadas de esta sesión. Los originales permanecen intactos. Un cliente con protecciones personalizadas puede necesitar su formato específico.'
          : 'Se extraen TODOS los archivos del índice en una carpeta DATA nueva. Incluye formatos que el visor no interpreta. No se sobrescribe ninguna carpeta existente.',
    )) {
      return;
    }
    final parent = await getDirectoryPath(
      confirmButtonText: 'Elegir carpeta de salida',
    );
    if (parent == null) return;
    final control = ExportControl();
    exporting = control;
    var last = DateTime.fromMillisecondsSinceEpoch(0);
    void notify(ExportProgress p) {
      if (!mounted) return;
      final now = DateTime.now();
      if (now.difference(last).inMilliseconds > 90 || p.done == p.total) {
        last = now;
        setState(() => progress = p);
      }
    }

    try {
      final changes = <String, Uint8List>{};
      if (pack) {
        for (final entry in _cache.entries) {
          if (entry.value.dirty) {
            final id = widget.library.files[entry.key];
            if (id == null || !source.index.entries.containsKey(id)) {
              throw FormatException(
                '${entry.key}: importación externa; expórtala por separado, no pertenece al SAH.',
              );
            }
            final d = entry.value, bytes = d.exportBytes();
            final read = reopenDocument(d, bytes);
            if (read.rows.length != d.rows.length ||
                read.profile != d.profile) {
              throw FormatException('Relectura fallida: ${d.path}');
            }
            for (final c in d.changes) {
              final field = read
                  .fields(c.row)
                  .where((f) => f.spec.name == c.field.spec.name)
                  .single;
              if (read.read(field) != c.afterText) {
                throw FormatException(
                  'Valor no conservado: ${d.path}/${c.field.spec.name}',
                );
              }
            }
            changes[id] = bytes;
          }
        }
      }
      final result = pack
          ? await ArchiveExport.repack(
              source,
              Directory(parent),
              replacements: changes,
              control: control,
              progress: notify,
            )
          : await ArchiveExport.extract(
              source,
              Directory(parent),
              control: control,
              progress: notify,
            );
      _note('${result.files} archivos verificados · ${result.folder}');
    } finally {
      exporting = null;
      if (mounted) setState(() => progress = null);
    }
  });
  Future<void> _exportReport() => _job(() async {
    final report = {
      'version': '0.6.1',
      'source': widget.library.sourceDiagnostics,
      'tables': _cache.values.map((d) => d.report()).toList(),
      'privacy':
          'Sin contenido de tablas ni credenciales. No se envía automáticamente.',
      'status': status,
    };
    final p = await _save(
      'auditoria_editor.json',
      Uint8List.fromList(
        utf8.encode(const JsonEncoder.withIndent('  ').convert(report)),
      ),
    );
    if (p != null) _note('Informe guardado: $p');
  });
  Future<void> _csv() => _job(() async {
    final d = doc!;
    if (d.rows.isEmpty) return;
    final union = <String>{};
    for (final row in visible) {
      union.addAll(d.fields(row).map((f) => f.spec.name));
    }
    if (union.length > 5000) {
      throw const FormatException(
        'La vista combina más de 5.000 columnas diferentes. Filtra un tipo de registro o usa el parche sin pérdida.',
      );
    }
    final names = union.toList();
    String q(String s) => '"${s.replaceAll('"', '""')}"';
    final out = StringBuffer('\uFEFF');
    out.writeln(['row', ...names].map(q).join(','));
    for (final row in visible) {
      final map = {for (final f in d.fields(row)) f.spec.name: d.read(f)};
      out.writeln(
        [row.toString(), ...names.map((n) => map[n] ?? '')].map(q).join(','),
      );
    }
    final path = await _save(
      '${baseName(d.path)}.csv',
      Uint8List.fromList(utf8.encode(out.toString())),
    );
    if (path != null) {
      _note(
        'Vista filtrada exportada como CSV UTF-8: $path. Es una vista de consulta; usa el parche JSON para intercambio sin pérdida.',
      );
    }
  });
  Widget _smallButton(
    IconData icon,
    String label,
    VoidCallback? onPressed, {
    Key? key,
  }) => TextButton.icon(
    key: key,
    onPressed: busy ? null : onPressed,
    icon: Icon(icon, size: 16),
    label: Text(label, style: const TextStyle(fontSize: 11)),
  );
  Widget _files() {
    final q = _filesQuery.text.toLowerCase();
    final list = paths
        .where(
          (p) =>
              p.toLowerCase().contains(q) &&
              (fileCategory == 'Todos' ||
                  (fileCategory == 'Monstruos'
                      ? p.toLowerCase().contains('monster')
                      : fileCategory == 'Habilidades'
                      ? p.toLowerCase().contains('skill')
                      : fileCategory == 'Mapas'
                      ? p.toLowerCase().endsWith('.svmap')
                      : fileCategory == 'NPC'
                      ? p.toLowerCase().contains('npc')
                      : fileCategory == 'Tiendas'
                      ? p.toLowerCase().contains('sell') ||
                            p.toLowerCase().contains('cash')
                      : p.toLowerCase().contains('item'))),
        )
        .toList();
    return Material(
      color: const Color(0xff151e2b),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: TextField(
              controller: _filesQuery,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Buscar archivo…',
                prefixIcon: Icon(Icons.search, size: 16),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: DropdownButton<String>(
              value: fileCategory,
              isExpanded: true,
              items: [
                'Todos',
                'Monstruos',
                'Objetos',
                'Tiendas',
                'Habilidades',
                'NPC',
                'Mapas',
              ].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (v) => setState(() => fileCategory = v!),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              '${list.length} tablas · ${_cache.values.where((d) => d.dirty).length} con cambios',
              style: const TextStyle(fontSize: 11, color: EditorStyle.muted),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (c, i) {
                final p = list[i];
                return ListTile(
                  dense: true,
                  selected: doc?.path == p,
                  leading: Icon(
                    _cache[p]?.dirty == true
                        ? Icons.edit_note
                        : p.endsWith('.svmap')
                        ? Icons.map_outlined
                        : Icons.table_chart_outlined,
                    size: 18,
                  ),
                  title: Text(
                    baseName(p),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    directoryName(p),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: busy ? null : () => openTable(p),
                );
              },
            ),
          ),
          _smallButton(
            Icons.file_open_outlined,
            'Importar archivo…',
            _importTable,
          ),
        ],
      ),
    );
  }

  Widget _records() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('record-search'),
                  controller: _rowsQuery,
                  onChanged: (_) => _queueFilter(),
                  decoration: const InputDecoration(
                    hintText: 'Buscar nombre, ID…',
                    prefixIcon: Icon(Icons.search, size: 16),
                  ),
                ),
              ),
              const SizedBox(width: 7),
              IconButton(
                key: const ValueKey('edit-selected-record'),
                tooltip: 'Editar registro completo',
                onPressed: visible.isEmpty ? null : () => _openRecord(selected),
                icon: const Icon(Icons.open_in_new),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Wrap(
            spacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 160,
                child: DropdownButton<String>(
                  value: classFilter,
                  isExpanded: true,
                  isDense: true,
                  items:
                      [
                            'Todas',
                            'Fighter',
                            'Defender',
                            'Ranger',
                            'Archer',
                            'Mage',
                            'Priest',
                          ]
                          .map(
                            (v) => DropdownMenuItem(
                              value: v,
                              child: Text(
                                v == 'Todas'
                                    ? 'Todas las clases'
                                    : const {
                                        'Fighter': 'Luchador / Guerrero',
                                        'Defender': 'Defensor / Guardián',
                                        'Ranger': 'Ranger / Asesino',
                                        'Archer': 'Arquero / Cazador',
                                        'Mage': 'Mago / Pagano',
                                        'Priest': 'Sacerdote / Oráculo',
                                      }[v]!,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                          )
                          .toList(),
                  onChanged: (v) {
                    classFilter = v!;
                    _filter();
                  },
                ),
              ),
              SizedBox(
                width: 124,
                child: DropdownButton<String>(
                  value: factionFilter,
                  isExpanded: true,
                  isDense: true,
                  items: ['Todas', '0', '1', '2', '3', '4', '5', '6']
                      .map(
                        (v) => DropdownMenuItem(
                          value: v,
                          child: Text(
                            v == 'Todas'
                                ? 'Todas las facciones'
                                : editorDomain(doc!.path) == EditorDomain.items
                                ? itemCountryLabel(v)
                                : 'Código $v',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    factionFilter = v!;
                    _filter();
                  },
                ),
              ),
            ],
          ),
        ),
        if (doc!.profile == 'svmap')
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => mapView = !mapView),
              icon: Icon(
                mapView ? Icons.table_rows_outlined : Icons.map_outlined,
              ),
              label: Text(
                mapView
                    ? 'Ver tabla de ubicaciones'
                    : 'Ver plano de ubicaciones',
              ),
            ),
          ),
        Expanded(
          child: doc!.profile == 'svmap' && mapView
              ? EditorMapView(
                  document: doc!,
                  images: _images,
                  rows: visible,
                  selected: selected,
                  onSelect: (r) => setState(() => selected = r),
                  onEdit: _openRecord,
                )
              : EditorCatalog(
                  key: ValueKey('catalog-${doc!.path}'),
                  document: doc!,
                  rows: visible,
                  selected: selected,
                  summary: _summary,
                  images: _images,
                  onSelect: (r) => setState(() => selected = r),
                  onEdit: _openRecord,
                  onDuplicate: StructureEditor.supported(doc!)
                      ? _duplicateSelected
                      : null,
                  onDelete: StructureEditor.supported(doc!)
                      ? _deleteSelected
                      : null,
                  onSort: (key, desc) {
                    sortColumn = key;
                    descending = desc;
                    _filter();
                  },
                ),
        ),
      ],
    );
  }

  bool mapView = true;
  void _history(bool redo) {
    final d = doc;
    if (d == null) return;
    if (_windows.any((w) => w.document == d && w.draft.dirty)) {
      _note(
        'Aplica o cancela los borradores de esta tabla antes de usar el historial.',
      );
      return;
    }
    _windows.removeWhere((w) => w.document == d);
    if (redo) {
      d.redo();
    } else {
      d.undo();
    }
    _refresh();
  }

  Widget _tabs() => SizedBox(
    height: 34,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _cache.entries
            .map(
              (e) => Container(
                decoration: BoxDecoration(
                  color: doc == e.value
                      ? EditorStyle.panel
                      : EditorStyle.background,
                  border: Border(
                    bottom: BorderSide(
                      color: doc == e.value
                          ? EditorStyle.accent
                          : Colors.transparent,
                      width: 2,
                    ),
                    right: const BorderSide(color: EditorStyle.line),
                  ),
                ),
                child: InkWell(
                  onTap: busy ? null : () => openTable(e.key),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 2, 0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(domainIcon(editorDomain(e.key)), size: 13),
                        const SizedBox(width: 6),
                        Text(
                          '${e.value.dirty ? '● ' : ''}${baseName(e.key)}',
                          style: const TextStyle(fontSize: 10),
                        ),
                        IconButton(
                          tooltip: 'Cerrar tabla',
                          icon: const Icon(Icons.close, size: 13),
                          onPressed: busy
                              ? null
                              : () async {
                                  if (_windows.any(
                                    (w) => w.document == e.value,
                                  )) {
                                    _note(
                                      'Cierra primero las ventanas de registros de esta tabla.',
                                    );
                                    return;
                                  }
                                  if (e.value.dirty &&
                                      !await _confirm(
                                        'Cerrar tabla',
                                        'Hay cambios sin guardar. ¿Descartarlos?',
                                      )) {
                                    return;
                                  }
                                  setState(() {
                                    _cache.remove(e.key);
                                    _views.remove(e.key);
                                    if (doc == e.value) {
                                      doc = null;
                                      _labels.clear();
                                      _summaries.clear();
                                      visible = [];
                                    }
                                  });
                                },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    ),
  );
  Widget _workbench(BoxConstraints box) {
    workspaceSize = Size(box.maxWidth, box.maxHeight);
    final narrow = box.maxWidth < 1000;
    final content = Row(
      children: [
        if (!narrow && showFiles)
          SizedBox(width: explorerWidth, child: _files()),
        if (!narrow && showFiles)
          GestureDetector(
            onHorizontalDragUpdate: (d) => setState(
              () =>
                  explorerWidth = (explorerWidth + d.delta.dx).clamp(170, 350),
            ),
            child: const MouseRegion(
              cursor: SystemMouseCursors.resizeLeftRight,
              child: SizedBox(width: 5, child: VerticalDivider(width: 1)),
            ),
          ),
        Expanded(
          child: doc == null
              ? _empty()
              : tab == 1
              ? _audit()
              : _records(),
        ),
        if (doc != null &&
            tab == 0 &&
            showInspector &&
            box.maxWidth >= 1150) ...[
          GestureDetector(
            onHorizontalDragUpdate: (d) => setState(
              () => inspectorWidth = (inspectorWidth - d.delta.dx).clamp(
                240,
                420,
              ),
            ),
            child: const MouseRegion(
              cursor: SystemMouseCursors.resizeLeftRight,
              child: SizedBox(width: 5, child: VerticalDivider(width: 1)),
            ),
          ),
          SizedBox(width: inspectorWidth, child: _details()),
        ],
      ],
    );
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        Positioned.fill(child: content),
        for (final w in _windows.where((w) => !w.minimized))
          Positioned.fromRect(
            rect: _bound(w.rect),
            child: RecordEditorWindow(
              key: ValueKey(w.key),
              window: w,
              images: _images,
              onReference: () async {
                try {
                  final selected = await showEditorRelations(
                    context,
                    _images,
                    w.draft.previewDocument(),
                    w.row,
                    _cache,
                  );
                  if (selected == null || !mounted) return;
                  await openTable(selected.path);
                  if (mounted && doc?.path == selected.path) {
                    _openRecord(selected.row);
                  }
                } catch (e) {
                  _note('$e');
                }
              },
              onApply: _refresh,
              onClose: () => setState(() => _windows.remove(w)),
              onFocus: () {
                if (_windows.last != w) {
                  setState(() {
                    _windows.remove(w);
                    _windows.add(w);
                  });
                }
              },
              onMinimize: () => setState(() => w.minimized = true),
              onMove: (delta) =>
                  setState(() => w.rect = _bound(w.rect.shift(delta))),
              onResize: (delta) => setState(
                () => w.rect = _bound(
                  Rect.fromLTWH(
                    w.rect.left,
                    w.rect.top,
                    w.rect.width + delta.dx,
                    w.rect.height + delta.dy,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _details() {
    final d = doc!;
    if (visible.isEmpty) {
      return const Center(
        child: Text('No hay registros con los filtros elegidos.'),
      );
    }
    final fs = d.fields(selected), q = _fieldQuery.text.toLowerCase();
    final fields = fs.where((f) {
      final m = FieldMeaning.of(f.spec.name);
      return (group == 'Todos' || m.group == group) &&
          (q.isEmpty ||
              f.spec.name.toLowerCase().contains(q) ||
              m.label.toLowerCase().contains(q));
    }).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
          child: SelectableText(
            _label(selected),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            '${fs.length} campos · registro ${d.rows[selected].offset}–${d.rows[selected].end} · ${d.authority}',
            style: const TextStyle(fontSize: 11, color: EditorStyle.muted),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _fieldQuery,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Buscar cualquier parámetro…',
                    prefixIcon: Icon(Icons.tune, size: 16),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              DropdownButton<String>(
                value: group,
                items: FieldMeaning.groups
                    .map(
                      (s) => DropdownMenuItem(
                        value: s,
                        child: Text(s, style: const TextStyle(fontSize: 11)),
                      ),
                    )
                    .toList(),
                onChanged: (s) => setState(() => group = s!),
              ),
            ],
          ),
        ),
        if (rowWarnings(d, selected).isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              rowWarnings(d, selected).take(2).join('\n'),
              style: const TextStyle(color: Color(0xffffcc8c), fontSize: 11),
            ),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: fields.length,
            itemBuilder: (c, i) {
              final f = fields[i],
                  meaning = FieldMeaning.of(f.spec.name),
                  value = d.read(f),
                  changed = d.isChanged(f);
              return Material(
                color: changed
                    ? const Color(0xff21364a)
                    : i.isEven
                    ? const Color(0xff152031)
                    : const Color(0xff111a27),
                child: ListTile(
                  dense: true,
                  onTap: busy ? null : () => _edit(f),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          meaning.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        f.spec.type,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xff93a7c2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        f.spec.editable && f.spec.type != 'opaque'
                            ? Icons.edit_outlined
                            : Icons.lock_outline,
                        size: 14,
                      ),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        f.spec.name,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xff8294b0),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        value.length > 350
                            ? '${value.substring(0, 350)}…'
                            : value,
                        maxLines: f.spec.text ? 3 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: changed
                              ? const Color(0xffc7e6ff)
                              : const Color(0xffdae1eb),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _audit() {
    final d = doc!;
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text(
          d.complete
              ? 'Esquema estructural reconocido'
              : 'Cobertura parcial / inspección conservadora',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 10),
        SelectableText(
          '${d.path}\n${d.profile}\nSHA-256: ${d.sha}\nCodificación: ${d.codec.encoding.label}\n${d.authority}',
        ),
        const SizedBox(height: 16),
        const Text(
          'Los bytes desconocidos no se omiten ni reciben significados inventados. Una exportación válida no garantiza que el servidor adopte los parámetros del cliente.',
        ),
        ...d.warnings.map(
          (w) => Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(w, style: const TextStyle(color: Color(0xffffcc8c))),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          '${d.changeCount} campos pendientes',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        ...d.changes
            .take(1000)
            .map(
              (c) => ListTile(
                dense: true,
                title: Text('#${c.row + 1} · ${c.field.spec.name}'),
                subtitle: SelectableText('${c.beforeText}\n→ ${c.afterText}'),
              ),
            ),
        if (d.changeCount > 1000)
          const Text(
            'La lista visual limita a 1.000 cambios; el parche exportado incluye todos.',
          ),
      ],
    );
  }

  Widget _empty() => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 670),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.tune, size: 36),
            const SizedBox(height: 16),
            const Text(
              'Editor de datos del juego',
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            const Text(
              'Objetos, monstruos, habilidades, tiendas, NPC y ubicaciones. Abre una tabla para ver sus campos reales, sus rangos y la procedencia de los valores.',
            ),
            const SizedBox(height: 12),
            const Text(
              'Cliente y servidor no son lo mismo. SAH/SAF contiene los archivos del cliente. Los cambios de oro, botín o balance pueden requerir una actualización equivalente del servidor. Puedes importar un CSV del servidor para examinarlo y editarlo por separado.',
            ),
            const SizedBox(height: 16),
            const Text(
              'Catálogos visuales, ventanas de registro independientes, borradores, deshacer y exportación verificada. Abre una tabla del explorador para empezar.',
              style: TextStyle(color: Color(0xffa8c4ef)),
            ),
            const SizedBox(height: 20),
            _smallButton(
              Icons.file_open,
              'Importar tabla externa',
              _importTable,
            ),
          ],
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: leaving || (!dirty && !hasDrafts && !busy),
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _leave();
    },
    child: Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyZ, control: true): _EditorUndo(),
        SingleActivator(LogicalKeyboardKey.keyY, control: true): _EditorRedo(),
        SingleActivator(LogicalKeyboardKey.keyS, control: true): _EditorSave(),
      },
      child: Actions(
        actions: {
          _EditorUndo: CallbackAction<_EditorUndo>(
            onInvoke: (_) {
              if (!busy) {
                _history(false);
              }
              return null;
            },
          ),
          _EditorRedo: CallbackAction<_EditorRedo>(
            onInvoke: (_) {
              if (!busy) {
                _history(true);
              }
              return null;
            },
          ),
          _EditorSave: CallbackAction<_EditorSave>(
            onInvoke: (_) {
              if (doc != null && !busy) _saveChanges();
              return null;
            },
          ),
        },
        child: LayoutBuilder(
          builder: (context, box) {
            final narrow = box.maxWidth < 1000;
            return Theme(
              data: EditorStyle.theme(Theme.of(context)),
              child: Scaffold(
                key: _scaffold,
                drawer: narrow
                    ? Drawer(child: SafeArea(child: _files()))
                    : null,
                appBar: AppBar(
                  leading: IconButton(
                    onPressed: _leave,
                    icon: const Icon(Icons.arrow_back),
                  ),
                  title: const Text(
                    'EDITOR DE DATOS',
                    style: TextStyle(fontSize: 15, letterSpacing: 1),
                  ),
                  actions: [
                    IconButton(
                      tooltip: 'Mostrar / ocultar inspector',
                      onPressed: () =>
                          setState(() => showInspector = !showInspector),
                      icon: const Icon(Icons.view_sidebar_outlined),
                    ),
                    if (narrow)
                      IconButton(
                        onPressed: () => _scaffold.currentState?.openDrawer(),
                        icon: const Icon(Icons.folder_open),
                      ),
                    PopupMenuButton<String>(
                      tooltip: 'Exportar / herramientas',
                      onSelected: (action) {
                        if (busy) return;
                        switch (action) {
                          case 'file':
                            _exportDocument();
                          case 'patch':
                            _patch(false);
                          case 'importPatch':
                            _patch(true);
                          case 'csv':
                            _csv();
                          case 'import':
                            _importTable();
                          case 'audit':
                            _exportReport();
                          case 'extract':
                            _exportArchive(false);
                          case 'pack':
                            _exportArchive(true);
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'import',
                          child: Text('Importar tabla / CSV servidor'),
                        ),
                        if (doc != null) ...[
                          const PopupMenuItem(
                            value: 'file',
                            child: Text('Exportar archivo verificado'),
                          ),
                          const PopupMenuItem(
                            value: 'patch',
                            child: Text('Guardar parche JSON'),
                          ),
                          const PopupMenuItem(
                            value: 'importPatch',
                            child: Text('Aplicar parche verificado'),
                          ),
                          const PopupMenuItem(
                            value: 'csv',
                            child: Text('Exportar vista a CSV UTF-8'),
                          ),
                        ],
                        if (widget.library.archive != null &&
                            !Platform.isAndroid) ...[
                          const PopupMenuItem(
                            value: 'extract',
                            child: Text('Extraer todo a carpeta DATA'),
                          ),
                          const PopupMenuItem(
                            value: 'pack',
                            child: Text('Construir nuevo SAH + SAF'),
                          ),
                        ],
                        const PopupMenuItem(
                          value: 'audit',
                          child: Text('Exportar informe de auditoría'),
                        ),
                      ],
                    ),
                  ],
                ),
                body: Column(
                  children: [
                    Container(
                      color: const Color(0xff1a2536),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 4,
                        children: [
                          SizedBox(
                            width: (box.maxWidth - 24).clamp(160.0, 320.0),
                            child: DropdownButton<GameTextEncoding>(
                              isExpanded: true,
                              value: encoding,
                              items: GameTextEncoding.values
                                  .map(
                                    (v) => DropdownMenuItem(
                                      value: v,
                                      child: Text(
                                        v == GameTextEncoding.automatic
                                            ? 'Codificación automática por archivo'
                                            : v.label,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: busy ? null : (e) => _encoding(e!),
                            ),
                          ),
                          _smallButton(
                            Icons.undo,
                            'Deshacer',
                            doc?.canUndo == true
                                ? () {
                                    _history(false);
                                  }
                                : null,
                          ),
                          _smallButton(
                            Icons.redo,
                            'Rehacer',
                            doc?.canRedo == true
                                ? () {
                                    _history(true);
                                  }
                                : null,
                          ),
                          _smallButton(
                            Icons.save_outlined,
                            'Guardar',
                            dirty ? _saveChanges : null,
                            key: const ValueKey('editor-save'),
                          ),
                          if (widget.library.archive == null &&
                              !widget.library.saf)
                            _smallButton(
                              Icons.inventory_2_outlined,
                              'Construir SAH/SAF',
                              _buildDirectory,
                            ),
                          Tooltip(
                            message:
                                'Respaldo opcional; el guardado utiliza una transacción temporal incluso sin esta opción.',
                            child: FilterChip(
                              label: const Text(
                                'Respaldo',
                                style: TextStyle(fontSize: 10),
                              ),
                              selected: keepBackup,
                              onSelected: (v) => setState(() => keepBackup = v),
                            ),
                          ),
                          _smallButton(
                            Icons.save_as_outlined,
                            'Guardar copia',
                            doc == null ? null : _exportDocument,
                            key: const ValueKey('editor-save-copy'),
                          ),
                          if (widget.library.archive?.sahPath != null)
                            _smallButton(
                              Icons.restore_page_outlined,
                              'Recuperar transacción',
                              _recoverArchive,
                            ),
                          if (doc != null)
                            _smallButton(
                              tab == 0
                                  ? Icons.fact_check_outlined
                                  : Icons.table_rows_outlined,
                              tab == 0 ? 'Auditoría / cambios' : 'Registros',
                              () => setState(() => tab = 1 - tab),
                            ),
                          if (doc?.dirty == true)
                            _smallButton(
                              Icons.restore,
                              'Descartar cambios',
                              () async {
                                if (await _confirm(
                                  'Descartar cambios',
                                  'Se revierten los cambios de esta tabla, no los originales.',
                                )) {
                                  doc!.discard();
                                  _refresh();
                                }
                              },
                            ),
                        ],
                      ),
                    ),
                    if (busy && progress == null)
                      const LinearProgressIndicator(minHeight: 2),
                    if (_cache.isNotEmpty) _tabs(),
                    if (_windows.isNotEmpty)
                      SizedBox(
                        height: 30,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: _windows
                                .map(
                                  (w) => TextButton.icon(
                                    onPressed: () => setState(() {
                                      w.minimized = !w.minimized;
                                      _windows.remove(w);
                                      _windows.add(w);
                                    }),
                                    icon: Icon(
                                      w.minimized
                                          ? Icons.open_in_new
                                          : Icons.remove,
                                      size: 13,
                                    ),
                                    label: Text(
                                      '${w.draft.dirty ? '● ' : ''}${w.title}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, area) => AbsorbPointer(
                          absorbing: busy,
                          child: _workbench(area),
                        ),
                      ),
                    ),
                    if (progress != null)
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${progress!.phase} · ${progress!.done}/${progress!.total} · ${progress!.path}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  LinearProgressIndicator(
                                    value: progress!.ratio?.clamp(0, 1),
                                  ),
                                ],
                              ),
                            ),
                            TextButton(
                              onPressed: () => exporting?.cancelled = true,
                              child: const Text('Cancelar'),
                            ),
                          ],
                        ),
                      ),
                    Container(
                      width: double.infinity,
                      color: const Color(0xff111a26),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      child: SelectableText(
                        status,
                        maxLines: 2,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xff9db2cc),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}
