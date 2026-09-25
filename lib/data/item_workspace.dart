import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/client_locale.dart';
import '../core/game_text_codec.dart';
import '../editor/document.dart';
import '../editor/catalog_document.dart';
import '../editor/schema_reader.dart';
import '../editor/workbench_model.dart';
import 'equipment_registry.dart';
import 'file_save.dart';
import 'library.dart';

/// One staging area per connected DATA. Both Equipment and Items use this
/// instance: names/stats/icons cannot diverge between two independent editors.
/// Nothing is silently written to active DATA, an SPK, or a server database.
class ItemWorkspace extends ChangeNotifier {
  static final _sessions = Expando<Future<ItemWorkspace>>('item-workspaces');
  final Library source;
  int sourceRevision;
  int _generation = 0;
  final Map<String, EditDocument> documents;
  final String dataPath;
  final String? textPath;
  final Map<String, ItemEntry> byKey;
  final Map<String, Uint8List> _assets = {};
  final Map<String, String> _assetSources = {};
  final List<_ItemOperation> _undo = [], _redo = [];
  final Map<String, Future<EditDocument>> _opening = {};
  final List<String> warnings;
  late final Library preview = _ItemPreviewLibrary(this);
  int revision = 0;
  bool _exporting = false;
  EquipmentRegistry? _registry;
  late final Map<int, String> _dataKeys = {
    for (final e in byKey.values) e.row: e.key,
  };
  late final Map<int, String> _textKeys = {
    for (final e in byKey.values)
      if (e.textRow != null) e.textRow!: e.key,
  };

  ItemWorkspace._(
    this.source,
    this.documents,
    this.dataPath,
    this.textPath,
    this.byKey,
    this.warnings,
  ) : sourceRevision = source.revision;

  static Future<ItemWorkspace> forLibrary(Library library) async {
    if (library is _ItemPreviewLibrary) return library.workspace;
    var pending = _sessions[library];
    if (pending != null) {
      final current = await pending;
      if (current.sourceRevision == library.revision) return current;
      // Keep the old staging session reachable so the user can inspect or
      // explicitly discard it. Its write guards refuse the changed source.
      if (current.dirty) return current;
      _sessions[library] = null;
    }
    pending = _sessions[library] ??= _load(library).catchError((Object error) {
      _sessions[library] = null;
      throw error;
    });
    return pending;
  }

  /// Reload the existing shared object, rather than leaving another view
  /// subscribed to a stale session. Dirty work must be explicitly discarded.
  Future<void> reloadFromSource() async {
    if (_exporting || dirty) {
      throw StateError('Descarta o exporta los borradores antes de recargar.');
    }
    _exporting = true;
    _generation++;
    notifyListeners();
    try {
      final loaded = await _load(source);
      if (loaded.textPath != textPath || loaded.dataPath != dataPath) {
        throw const FormatException(
          'La tabla de idioma cambió. Reconecta DATA para elegir la nueva fuente.',
        );
      }
      documents
        ..clear()
        ..addAll(loaded.documents);
      byKey
        ..clear()
        ..addAll(loaded.byKey);
      warnings
        ..clear()
        ..addAll(loaded.warnings);
      _dataKeys
        ..clear()
        ..addEntries(byKey.values.map((e) => MapEntry(e.row, e.key)));
      _textKeys
        ..clear()
        ..addEntries(
          byKey.values
              .where((e) => e.textRow != null)
              .map((e) => MapEntry(e.textRow!, e.key)),
        );
      sourceRevision = loaded.sourceRevision;
      _opening.clear();
      _undo.clear();
      _redo.clear();
      _assetSources.clear();
      _registry = null;
      (preview as _ItemPreviewLibrary).invalidate();
      _refresh(documents.keys.toList());
    } finally {
      _exporting = false;
      notifyListeners();
    }
  }

  void _requireCurrentSource() {
    if (source.revision != sourceRevision) {
      throw const FormatException(
        'La DATA conectada cambió fuera de esta sesión. '
        'Reabre Ítems; no se aplican borradores sobre tablas antiguas.',
      );
    }
  }

  static Future<ItemWorkspace> _load(Library library) async {
    final revisionAtStart = library.revision;
    const data = 'binarysdata/dbitemdata.sdata';
    if (!library.files.containsKey(data)) {
      throw const FormatException(
        'Falta BinarySData/DBItemData.SData. '
        'El catálogo no mezcla tablas de otra carpeta ni nombres inferidos del SPK.',
      );
    }
    final candidates = ClientLocale.tableCandidates(
      library.files.keys,
      'dbitemtext',
      beside: data,
    );
    // Two equally preferred localized tables require a choice outside this
    // session instead of silently binding the wrong language variant.
    final text = candidates.firstOrNull;
    if (text != null &&
        candidates
            .skip(1)
            .any(
              (e) =>
                  ClientLocale.languageOf(e) == ClientLocale.languageOf(text),
            )) {
      throw const FormatException(
        'Hay varias tablas de texto para el mismo idioma. '
        'Conecta una DATA con una única tabla activa por idioma.',
      );
    }
    final parsed = await compute(_parseItems, <String, Object?>{
      'data': await library.read(data, limit: 128 * 1024 * 1024),
      'dataPath': data,
      'text': text == null ? null : await library.read(text),
      'textPath': text,
    });
    if (library.revision != revisionAtStart) {
      throw const FormatException(
        'La DATA cambió durante la lectura del catálogo.',
      );
    }
    return ItemWorkspace._(
      library,
      parsed.documents,
      data,
      text,
      parsed.entries,
      parsed.warnings,
    );
  }

  @visibleForTesting
  factory ItemWorkspace.fromBytes(
    Library library,
    Uint8List data, {
    Uint8List? text,
    String? textPath,
  }) {
    if ((text == null) != (textPath == null)) {
      throw ArgumentError('text y textPath deben proporcionarse juntos.');
    }
    final parsed = _parseItems({
      'data': data,
      'dataPath': 'binarysdata/dbitemdata.sdata',
      'text': text,
      'textPath': textPath,
    });
    return ItemWorkspace._(
      library,
      parsed.documents,
      'binarysdata/dbitemdata.sdata',
      textPath,
      parsed.entries,
      parsed.warnings,
    );
  }

  bool get sourceChanged => source.revision != sourceRevision;
  bool get dirty => documents.values.any((d) => d.dirty) || _assets.isNotEmpty;
  bool get canUndo => !_exporting && _undo.isNotEmpty;
  bool get canRedo => !_exporting && _redo.isNotEmpty;
  bool get exporting => _exporting;
  int get pendingFiles =>
      documents.values.where((d) => d.dirty).length + _assets.length;
  List<String> get history => _undo.map((e) => e.title).toList(growable: false);
  List<ItemEntry> get items => byKey.values.toList(growable: false);
  EditDocument get data => documents[dataPath]!;
  EditDocument? get text => textPath == null ? null : documents[textPath];
  EquipmentRegistry get registry => _registry ??= EquipmentRegistry.fromItems(
    source,
    dataPath,
    textPath,
    byKey.values.map((i) => i.registered).toList(),
  );

  Future<EditDocument> openDocument(String path) async {
    _requireCurrentSource();
    _safePath(path);
    if (documents[path] case final EditDocument doc) return doc;
    final generation = _generation;
    return _opening.putIfAbsent(path, () async {
      try {
        final bytes = await source.read(path, limit: 128 * 1024 * 1024);
        final doc = await compute(_openItemDocument, (bytes, path));
        if (!doc.complete) {
          throw FormatException(
            '$path: esquema incompleto; no se permite escritura.',
          );
        }
        _requireCurrentSource();
        if (generation != _generation) {
          throw StateError('La sesión se recargó durante la lectura.');
        }
        documents[path] = doc;
        return doc;
      } finally {
        if (generation == _generation) _opening.remove(path);
      }
    });
  }

  void validateField(EditDocument doc, FieldSpan field, String value) {
    doc.validate(field, value);
    final name = field.spec.name.toLowerCase();
    if (doc.path == dataPath && name == 'icon') {
      final icon = BigInt.tryParse(value.trim());
      if (icon == null || icon < BigInt.zero || icon > BigInt.from(255)) {
        throw const FormatException(
          'ps0032 consume Icon como byte: 0..255; 0 no resuelve miniatura.',
        );
      }
    }
    if (doc is! CatalogDocument || !field.spec.text) return;
    final texture = name == 'texture' || name.endsWith('.texture');
    final mesh = name == 'mesh' || name.endsWith('.mesh');
    final animation = name.startsWith('animation.');
    final sound = name.startsWith('sound.');
    final effect = name.startsWith('effect.');
    if (!texture && !mesh && !animation && !sound && !effect) return;
    final relative = value.replaceAll('\\', '/').toLowerCase();
    if (relative.isEmpty || relative == 'null') {
      if (animation &&
          doc.read(field).trim().isNotEmpty &&
          doc.read(field).toLowerCase() != 'null') {
        throw const FormatException(
          'No se vacía un slot ANI activo. Selecciona una animación compatible.',
        );
      }
      return;
    }
    _safePath(relative);
    var root = ClientLocale.directory(doc.path);
    if (root.endsWith('/mlt')) root = ClientLocale.directory(root);
    final roots = sound
        ? ['sound']
        : effect
        ? ['effect']
        : texture
        ? ['$root/dds']
        : animation
        ? ['$root/ani']
        : ['$root/3dc', '$root/3do'];
    if (!roots.any((prefix) => source.files.containsKey('$prefix/$relative'))) {
      throw FormatException(
        'Referencia inexistente en ${roots.join(' o ')}: $value. '
        'Guarda un nombre relativo al directorio nativo, no una ruta completa duplicada.',
      );
    }
  }

  /// Validate every span and detect stale drafts BEFORE touching any document.
  /// Each document receives a single atomic batch; a later failure is undone.
  void apply(List<ItemFieldEdit> edits, {required String title}) {
    _requireCurrentSource();
    if (_exporting) throw StateError('La exportación está en curso.');
    final grouped = <String, List<(int, FieldSpan, String)>>{};
    final seen = <String>{};
    for (final edit in edits) {
      final doc = documents[edit.path];
      if (doc == null || !doc.complete) {
        throw StateError('Documento no abierto: ${edit.path}');
      }
      if (edit.row < 0 || edit.row >= doc.rows.length) {
        throw const FormatException('Registro inexistente.');
      }
      final field = doc
          .fields(edit.row)
          .where((f) => f.spec.name == edit.field)
          .firstOrNull;
      if (field == null) {
        throw FormatException('Campo inexistente: ${edit.field}');
      }
      if (!seen.add('${edit.path}:${field.start}')) {
        throw const FormatException('Edición duplicada.');
      }
      if (doc.read(field) != edit.before) {
        throw FormatException(
          '${edit.field} cambió en otra vista. Reabre el borrador.',
        );
      }
      if (edit.value == edit.before) continue;
      if ((edit.path == dataPath || edit.path == textPath) &&
          const {
            'itemtype',
            'itemtypeid',
            'type',
            'typeid',
          }.contains(edit.field.toLowerCase())) {
        throw const FormatException(
          'Type:TypeId es identidad referenciada. '
          'No se renumera sin migrar misiones, tiendas y servidor.',
        );
      }
      validateField(doc, field, edit.value);
      grouped.putIfAbsent(edit.path, () => []).add((
        edit.row,
        field,
        edit.value,
      ));
    }
    final applied = <String>[];
    try {
      for (final group in grouped.entries) {
        final doc = documents[group.key]!, before = doc.revision;
        doc.editMany(group.value, title: title);
        if (doc.revision != before) applied.add(group.key);
      }
    } catch (_) {
      for (final path in applied.reversed) {
        documents[path]!.undo();
      }
      rethrow;
    }
    if (applied.isEmpty) return;
    final affected = <String>{};
    for (final path in applied) {
      final index = path == dataPath
          ? _dataKeys
          : path == textPath
          ? _textKeys
          : const <int, String>{};
      for (final edit in grouped[path]!) {
        final key = index[edit.$1];
        if (key != null) affected.add(key);
      }
    }
    _undo.add(_ItemOperation(title, applied, affected));
    _redo.clear();
    _refresh(applied, keys: affected);
  }

  /// Replacing a texture changes every use of that resource. UI must display
  /// shared-use impact and collect explicit confirmation before this method.
  Future<void> stageAsset(
    String path,
    Uint8List bytes, {
    required String expectedHash,
    required String title,
  }) async {
    if (_exporting) throw StateError('La exportación está en curso.');
    _requireCurrentSource();
    _safePath(path);
    if (!source.files.containsKey(path)) {
      throw const FormatException('No se inventa una ruta nativa.');
    }
    if (bytes.isEmpty || bytes.length > 32 * 1024 * 1024) {
      throw const FormatException(
        'El recurso debe tener entre 1 byte y 32 MiB.',
      );
    }
    if (documents.containsKey(path)) {
      throw const FormatException(
        'Este recurso ya tiene un editor estructurado.',
      );
    }
    final current = await preview.read(path);
    if (FileSave.hash(current) != expectedHash) {
      throw const FormatException('La textura cambió mientras se editaba.');
    }
    final original = await source.read(path);
    if (_exporting) throw StateError('La exportación está en curso.');
    // Recheck after the async reads: another view may have staged this sheet.
    if (FileSave.hash(await preview.read(path)) != expectedHash) {
      throw const FormatException('Conflicto de recurso entre vistas.');
    }
    _requireCurrentSource();
    if (_exporting) throw StateError('La exportación está en curso.');
    if (FileSave.hash(current) == FileSave.hash(bytes)) return;
    final before = _assets[path];
    final replacement = FileSave.hash(original) == FileSave.hash(bytes)
        ? null
        : Uint8List.fromList(bytes);
    _assetSources.putIfAbsent(path, () => FileSave.hash(original));
    if (replacement == null) {
      _assets.remove(path);
    } else {
      _assets[path] = replacement;
    }
    _undo.add(_ItemOperation.asset(title, path, before, replacement));
    _redo.clear();
    _refresh(const []);
  }

  void undo() {
    if (!canUndo) return;
    final operation = _undo.removeLast();
    for (final path in operation.documents.reversed) {
      documents[path]!.undo();
    }
    _restoreAsset(operation, false);
    _redo.add(operation);
    _refresh(operation.documents, keys: operation.keys);
  }

  void redo() {
    if (!canRedo) return;
    final operation = _redo.removeLast();
    for (final path in operation.documents) {
      documents[path]!.redo();
    }
    _restoreAsset(operation, true);
    _undo.add(operation);
    _refresh(operation.documents, keys: operation.keys);
  }

  void _restoreAsset(_ItemOperation op, bool forward) {
    if (op.assetPath == null) return;
    final bytes = forward ? op.afterAsset : op.beforeAsset;
    if (bytes == null) {
      _assets.remove(op.assetPath);
    } else {
      _assets[op.assetPath!] = bytes;
    }
  }

  void discard() {
    if (_exporting) throw StateError('La exportación está en curso.');
    for (final d in documents.values) {
      d.discard();
    }
    _assets.clear();
    _assetSources.clear();
    _undo.clear();
    _redo.clear();
    _refresh(documents.keys.toList());
  }

  void _refresh(List<String> changed, {Set<String>? keys}) {
    if (changed.contains(dataPath) || changed.contains(textPath)) {
      final entries = keys == null
          ? byKey.values
          : keys.map((key) => byKey[key]!);
      for (final entry in entries) {
        entry.refresh(data, text);
      }
      _registry = null;
    }
    revision++;
    preview.revision = source.revision + revision;
    notifyListeners();
  }

  /// Export one new, verified patch directory. There is no partial installation
  /// into active DATA: all files are re-read and the manifest commits last.
  Future<Directory> exportPatch(Directory destination) async {
    if (_exporting || !dirty) {
      throw StateError('No hay cambios exportables o ya se exporta.');
    }
    _requireCurrentSource();
    _exporting = true;
    notifyListeners();
    Directory? scratch;
    try {
      if (await destination.exists()) {
        throw const FormatException('El destino debe ser nuevo.');
      }
      final parent = destination.parent;
      // Resolve the existing ancestor before creating any directory. Reject
      // exports inside active DATA even when the destination parents are new.
      var ancestor = parent.absolute;
      final missing = <String>[];
      while (!await ancestor.exists()) {
        missing.insert(0, p.basename(ancestor.path));
        final up = ancestor.parent;
        if (p.equals(up.path, ancestor.path)) {
          throw const FormatException(
            'No se encuentra un directorio de destino válido.',
          );
        }
        ancestor = up;
      }
      final parentCandidate = p.normalize(
        p.joinAll([await ancestor.resolveSymbolicLinks(), ...missing]),
      );
      if (!source.saf && source.archive == null && !source.isSpkWorkspace) {
        final sourceReal = await Directory(
          source.location,
        ).resolveSymbolicLinks();
        if (p.equals(parentCandidate, sourceReal) ||
            p.isWithin(sourceReal, parentCandidate)) {
          throw const FormatException(
            'Exporta fuera de DATA para no contaminar el catálogo.',
          );
        }
      }
      await Directory(parentCandidate).create(recursive: true);
      final parentReal = await Directory(
        parentCandidate,
      ).resolveSymbolicLinks();
      if (!source.saf && source.archive == null && !source.isSpkWorkspace) {
        final sourceReal = await Directory(
          source.location,
        ).resolveSymbolicLinks();
        if (p.equals(parentReal, sourceReal) ||
            p.isWithin(sourceReal, parentReal)) {
          throw const FormatException(
            'El directorio de destino cambió y apunta dentro de DATA.',
          );
        }
      }
      scratch = await Directory(parentReal).createTemp('.studio-items-');
      final bytes = <String, Uint8List>{};
      final origins = <String, String>{};
      final changed = documents.entries.where((e) => e.value.dirty).toList();
      // Include the localized pair together whenever either table changed.
      final paths = {for (final e in changed) e.key};
      if (paths.contains(dataPath) || paths.contains(textPath)) {
        paths.add(dataPath);
        if (textPath != null) paths.add(textPath!);
      }
      for (final path in paths) {
        final doc = documents[path]!, encoded = doc.exportBytes();
        final reopened = await compute(_openItemDocument, (encoded, path));
        _verifyDocument(doc, reopened);
        bytes[path] = encoded;
        origins[path] = doc.sha;
      }
      for (final e in _assets.entries) {
        bytes[e.key] = e.value;
        origins[e.key] = _assetSources[e.key]!;
      }
      Future<void> verifySources() async {
        for (final entry in origins.entries) {
          if (FileSave.hash(
                await source.read(entry.key, limit: 128 * 1024 * 1024),
              ) !=
              entry.value) {
            throw FormatException(
              '${entry.key} cambió fuera de esta sesión. No se exporta una versión obsoleta.',
            );
          }
        }
      }

      await verifySources();
      final manifest = <Map<String, Object>>[];
      for (final entry in bytes.entries) {
        _safePath(entry.key);
        final file = File(p.join(scratch.path, 'COPIAR_EN_DATA', entry.key));
        await file.parent.create(recursive: true);
        await file.writeAsBytes(entry.value, flush: true);
        final hash = FileSave.hash(entry.value);
        if (FileSave.hash(await file.readAsBytes()) != hash) {
          throw StateError('Falló la verificación de ${entry.key}.');
        }
        manifest.add({
          'path': entry.key,
          'bytes': entry.value.length,
          'sourceSha256': origins[entry.key]!,
          'sha256': hash,
        });
      }
      await verifySources();
      await File(p.join(scratch.path, 'LEEME.txt')).writeAsString(
        'PARCHE DE ITEMS - SHAIYA STUDIO\n\n'
        '1. Cierra el juego y conserva una copia de seguridad de los archivos originales.\n'
        '2. Comprueba los sourceSha256 del manifiesto contra tu DATA.\n'
        '3. Copia el CONTENIDO de COPIAR_EN_DATA a tu carpeta DATA. No copies la carpeta contenedora.\n'
        '4. Reinicia el cliente y verifica iconos, textos y recursos.\n\n'
        'Este parche modifica archivos del CLIENTE. Daño efectivo, comercio, misiones, '
        'probabilidades y efectos pueden requerir cambios equivalentes en el servidor. '
        'No incluye un game.exe nuevo, una migración del servidor ni descifra un SPK bloqueado.\n'
        'Las referencias de modelos y las celdas de un atlas pueden ser compartidas por varios ítems.\n'
        'Perfil de iconos: ps0032. Otros clientes deben auditar su asignación.\n',
        flush: true,
      );
      await File(p.join(scratch.path, 'manifest.json')).writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'schema': 1,
          'kind': 'shaiya-studio-items-patch',
          'clientOnly': true,
          'sessionRevision': revision,
          'files': manifest,
          'operations': history,
          'warnings': warnings,
        }),
        flush: true,
      );
      if (await destination.exists()) {
        throw const FormatException(
          'El destino apareció durante la exportación.',
        );
      }
      _requireCurrentSource();
      return await scratch.rename(
        p.join(parentReal, p.basename(destination.path)),
      );
    } finally {
      try {
        if (scratch != null && await scratch.exists()) {
          await scratch.delete(recursive: true);
        }
      } finally {
        _exporting = false;
        notifyListeners();
      }
    }
  }

  static void _verifyDocument(EditDocument before, EditDocument after) {
    if (!after.complete || before.rows.length != after.rows.length) {
      throw FormatException(
        '${before.path}: cambió la estructura al serializar.',
      );
    }
    for (var row = 0; row < before.rows.length; row++) {
      final a = before.fields(row), b = after.fields(row);
      if (a.length != b.length) {
        throw const FormatException('Número de campos distinto.');
      }
      for (var i = 0; i < a.length; i++) {
        if (a[i].spec.name != b[i].spec.name ||
            a[i].spec.type != b[i].spec.type ||
            before.read(a[i]) != after.read(b[i])) {
          throw FormatException(
            '${before.path} fila $row: relectura distinta en ${a[i].spec.name}.',
          );
        }
      }
    }
  }

  static void _safePath(String path) {
    if (path != ClientLocale.canonicalPath(path) ||
        path.startsWith('/') ||
        path.contains(':') ||
        path.contains('\u0000') ||
        path.split('/').any((s) => s.isEmpty || s == '.' || s == '..')) {
      throw const FormatException(
        'Ruta de recurso no canónica o fuera de DATA.',
      );
    }
  }
}

class ItemEntry {
  final String key;
  final int row;
  final int? textRow;
  late Map<String, String> values;
  late String name, description, searchText;
  RegisteredItem? _registered;
  ItemEntry(
    this.key,
    this.row,
    this.textRow,
    EditDocument data,
    EditDocument? text,
  ) {
    refresh(data, text);
  }
  void refresh(EditDocument data, EditDocument? text) {
    values = {
      for (final f in data.fields(row)) f.spec.name.toLowerCase(): data.read(f),
    };
    final names = text == null || textRow == null
        ? const <String, String>{}
        : {
            for (final f in text.fields(textRow!))
              f.spec.name.toLowerCase(): text.read(f),
          };
    name = names['itemname'] ?? values['name'] ?? '';
    description = names['text'] ?? values['description'] ?? '';
    searchText = foldedSearch('$name $description $key');
    _registered = null;
  }

  int get type => int.parse(values['itemtype']!);
  int get typeId => int.parse(values['itemtypeid']!);
  int get icon => int.tryParse(values['icon'] ?? '') ?? 0;
  int get image => int.tryParse(values['image'] ?? '') ?? 0;
  bool get hasName =>
      name.trim().isNotEmpty &&
      !RegExp(r'^[?\s]+$').hasMatch(name) &&
      !name.contains('\uFFFD');
  String get displayName => hasName ? name : 'Sin nombre localizado · $key';
  RegisteredItem get registered => _registered ??= RegisteredItem(
    {
      for (final e in values.entries)
        if (int.tryParse(e.value) != null) e.key: int.parse(e.value),
    },
    name,
    description,
  );
  RecordSummary get summary =>
      RecordSummary(row, key, displayName, 'Tipo $type', values);
}

class ItemFieldEdit {
  final String path, field, before, value;
  final int row;
  const ItemFieldEdit(this.path, this.row, this.field, this.before, this.value);
}

class _ItemOperation {
  final String title;
  final List<String> documents;
  final String? assetPath;
  final Set<String> keys;
  final Uint8List? beforeAsset, afterAsset;
  _ItemOperation(this.title, this.documents, this.keys)
    : assetPath = null,
      beforeAsset = null,
      afterAsset = null;
  _ItemOperation.asset(
    this.title,
    this.assetPath,
    this.beforeAsset,
    this.afterAsset,
  ) : documents = const [],
      keys = const {};
}

class _ParsedItems {
  final Map<String, EditDocument> documents;
  final Map<String, ItemEntry> entries;
  final List<String> warnings;
  _ParsedItems(this.documents, this.entries, this.warnings);
}

EditDocument _openItemDocument((Uint8List, String) args) => EditorReader.open(
  args.$1,
  args.$2,
  encoding: ClientLocale.encodingForPath(
    args.$2,
    fallback: GameTextEncoding.windows1252,
  ),
);
_ParsedItems _parseItems(Map<String, Object?> args) {
  final dataPath = args['dataPath'] as String,
      textPath = args['textPath'] as String?;
  final data = _openItemDocument((args['data'] as Uint8List, dataPath));
  final text = textPath == null
      ? null
      : _openItemDocument((args['text'] as Uint8List, textPath));
  if (!data.complete || (text != null && !text.complete)) {
    throw const FormatException(
      'La tabla no tiene un esquema completo; no se adivinan registros.',
    );
  }
  Map<String, int> identities(EditDocument d) {
    final index = <String, int>{};
    for (var row = 0; row < d.rows.length; row++) {
      final fs = {for (final f in d.fields(row)) f.spec.name.toLowerCase(): f};
      if (!fs.containsKey('itemtype') || !fs.containsKey('itemtypeid')) {
        throw FormatException('${d.path}: falta Type:TypeId.');
      }
      final key = '${d.read(fs['itemtype']!)}:${d.read(fs['itemtypeid']!)}';
      if (index.containsKey(key)) {
        throw FormatException('${d.path}: identidad duplicada $key.');
      }
      index[key] = row;
    }
    return index;
  }

  if (data.rows.isNotEmpty) {
    final columns = {for (final f in data.fields(0)) f.spec.name.toLowerCase()};
    if (!columns.containsAll({'itemtype', 'itemtypeid', 'image', 'icon'})) {
      throw const FormatException(
        'DBItemData carece de las columnas nativas de identidad/aspecto.',
      );
    }
  }
  final rows = identities(data),
      names = text == null ? <String, int>{} : identities(text);
  final warnings = [...data.warnings, ...?text?.warnings];
  final missing = rows.keys.where((k) => !names.containsKey(k)).length;
  final orphan = names.keys.where((k) => !rows.containsKey(k)).length;
  if (missing != 0) {
    warnings.add(
      '$missing objetos no tienen fila localizada. No se ocultan ni se inventan nombres.',
    );
  }
  if (orphan != 0) {
    warnings.add(
      '$orphan filas de texto no tienen objeto numérico correspondiente.',
    );
  }
  if (textPath != null && ClientLocale.languageOf(textPath) != 'es') {
    warnings.add(
      'No hay tabla española activa; se muestra el idioma real de $textPath.',
    );
  }
  return _ParsedItems(
    {dataPath: data, textPath!: ?text},
    {
      for (final e in rows.entries)
        e.key: ItemEntry(e.key, e.value, names[e.key], data, text),
    },
    warnings,
  );
}

class _ItemPreviewLibrary extends Library {
  final ItemWorkspace workspace;
  final Map<String, (int, Uint8List)> _encoded = {};
  _ItemPreviewLibrary(this.workspace)
    : super(
        workspace.source.location,
        workspace.source.saf,
        Map.of(workspace.source.files),
      );
  @override
  Future<Uint8List> read(String path, {int limit = 64 * 1024 * 1024}) async {
    workspace._requireCurrentSource();
    final doc = workspace.documents[path];
    Uint8List bytes;
    if (workspace._assets[path] case final Uint8List asset) {
      bytes = asset;
    } else if (doc != null && doc.dirty) {
      if (_encoded[path]?.$1 != doc.revision) {
        _encoded[path] = (doc.revision, doc.exportBytes());
      }
      bytes = _encoded[path]!.$2;
    } else {
      return workspace.source.read(path, limit: limit);
    }
    if (bytes.length > limit) {
      throw const FormatException('Recurso supera el límite solicitado.');
    }
    return Uint8List.fromList(bytes);
  }

  void invalidate() {
    _encoded.clear();
    files
      ..clear()
      ..addAll(workspace.source.files);
  }

  @override
  void dispose() {
    _encoded.clear();
  }
}
