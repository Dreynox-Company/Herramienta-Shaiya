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
import '../editor/document.dart';
import '../editor/schema_reader.dart';
import '../editor/csv_document.dart';
import '../editor/field_semantics.dart';
import '../core/client_locale.dart';

EditDocument parseEditorDocument(Map<String, Object?> args) {
  final bytes = args['bytes']! as Uint8List,
      path = args['path']! as String,
      chosen = GameTextEncoding.values.byName(args['encoding']! as String);
  final encoding = chosen == GameTextEncoding.automatic
      ? ClientLocale.encodingForPath(path)
      : chosen;
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

/// Dedicated, full-page editor. Source libraries are borrowed read-only;
/// export always creates a copy or a completely new verified archive pair.
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
            (p) => ['.sdata', '.svmap', '.csv'].any(p.toLowerCase().endsWith),
          )
          .toList()
        ..sort();
  bool get dirty => _cache.values.any((d) => d.dirty);
  @override
  void initState() {
    super.initState();
    encoding = widget.initialEncoding;
  }

  @override
  void dispose() {
    debounce?.cancel();
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
    if (dirty &&
        !await _confirm(
          'Cambios sin exportar',
          'Los originales siguen intactos. Volver al visor descarta los cambios de esta sesión. ¿Continuar?',
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
    selected = 0;
    group = 'Todos';
    _labels.clear();
    _rowsQuery.clear();
    _fieldQuery.clear();
    classFilter = 'Todas';
    factionFilter = 'Todas';
    _filter();
    _note(
      '${doc!.rows.length} registros · ${doc!.profile} · original protegido',
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
    if (!baseName(path).toLowerCase().startsWith('db')) {
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
    final q = _rowsQuery.text.trim().toLowerCase();
    final out = <int>[];
    for (var i = 0; i < d.rows.length; i++) {
      if (q.isNotEmpty && !_label(i).toLowerCase().contains(q)) continue;
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
    final check = d is CsvDocument
        ? CsvDocument.open(bytes, d.path, d.exportEncoding)
        : EditorReader.open(
            bytes,
            d.path,
            encoding: d.codec.encoding,
            forceProfile: d.profile,
          );
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
          label: 'Tablas SData, SVMAP o CSV',
          extensions: ['sdata', 'svmap', 'csv'],
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
            final read = EditorReader.open(
              bytes,
              d.path,
              encoding: d.codec.encoding,
              forceProfile: d.profile,
            );
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
      'version': '0.5.0',
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
              style: Theme.of(context).textTheme.bodySmall,
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
            'Importar SData / CSV',
            _importTable,
          ),
        ],
      ),
    );
  }

  Widget _records() {
    final d = doc!;
    return Material(
      color: const Color(0xff111b28),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              controller: _rowsQuery,
              onChanged: (_) => _queueFilter(),
              decoration: const InputDecoration(
                hintText: 'Nombre / identificador…',
                prefixIcon: Icon(Icons.search, size: 16),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButton<String>(
                    value: classFilter,
                    isExpanded: true,
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
                              (s) => DropdownMenuItem(
                                value: s,
                                child: Text(
                                  s == 'Todas'
                                      ? 'Todas las clases'
                                      : FieldMeaning.of(s).label,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 10),
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
                const SizedBox(width: 6),
                DropdownButton<String>(
                  value: factionFilter,
                  items: ['Todas', '0', '1', '2', '3']
                      .map(
                        (s) => DropdownMenuItem(
                          value: s,
                          child: Text(
                            s == 'Todas' ? 'Facción' : 'Código $s',
                            style: const TextStyle(fontSize: 10),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    factionFilter = v!;
                    _filter();
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(6),
            child: Text(
              '${visible.length} / ${d.rows.length} registros · filtro de facción por código original',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemExtent: 54,
              itemCount: visible.length,
              itemBuilder: (c, i) {
                final row = visible[i];
                return ListTile(
                  dense: true,
                  selected: row == selected,
                  title: Text(
                    _label(row),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${d.rows[row].kind} · #${row + 1}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => setState(() => selected = row),
                );
              },
            ),
          ),
        ],
      ),
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
            style: Theme.of(context).textTheme.bodySmall,
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
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
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
              'Ningún original se sobrescribe. Deshacer/rehacer, edición múltiple, parches verificados, copias SData y pares SAH/SAF nuevos.',
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
    canPop: leaving || (!dirty && !busy),
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
                doc?.undo();
                _refresh();
              }
              return null;
            },
          ),
          _EditorRedo: CallbackAction<_EditorRedo>(
            onInvoke: (_) {
              if (!busy) {
                doc?.redo();
                _refresh();
              }
              return null;
            },
          ),
          _EditorSave: CallbackAction<_EditorSave>(
            onInvoke: (_) {
              if (doc != null && !busy) _exportDocument();
              return null;
            },
          ),
        },
        child: LayoutBuilder(
          builder: (context, box) {
            final narrow = box.maxWidth < 1000;
            return Scaffold(
              key: _scaffold,
              drawer: narrow ? Drawer(child: SafeArea(child: _files())) : null,
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
                                      v.label,
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
                                  doc!.undo();
                                  _refresh();
                                }
                              : null,
                        ),
                        _smallButton(
                          Icons.redo,
                          'Rehacer',
                          doc?.canRedo == true
                              ? () {
                                  doc!.redo();
                                  _refresh();
                                }
                              : null,
                        ),
                        _smallButton(
                          Icons.save_as_outlined,
                          'Guardar copia',
                          doc == null ? null : _exportDocument,
                          key: const ValueKey('editor-save-copy'),
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
                  Expanded(
                    child: Row(
                      children: [
                        if (!narrow && showFiles)
                          SizedBox(width: 230, child: _files()),
                        if (doc == null)
                          Expanded(child: _empty())
                        else ...[
                          if (box.maxWidth > 660)
                            SizedBox(
                              width: (box.maxWidth * .24).clamp(215, 295),
                              child: _records(),
                            ),
                          Expanded(
                            child: tab == 1
                                ? _audit()
                                : Column(
                                    children: [
                                      if (box.maxWidth <= 660)
                                        SizedBox(
                                          height: 190,
                                          child: _records(),
                                        ),
                                      Expanded(child: _details()),
                                    ],
                                  ),
                          ),
                        ],
                      ],
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
            );
          },
        ),
      ),
    ),
  );
}
