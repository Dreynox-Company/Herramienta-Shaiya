import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../core/client_locale.dart';
import '../core/equipment_rules.dart';
import '../core/game_text_codec.dart';
import '../core/item_icon_layout.dart';
import '../data/file_save.dart';
import '../data/library.dart';
import 'catalog_document.dart';
import 'document.dart';
import 'schema_reader.dart';
import 'workbench_model.dart';

class ItemEntry {
  final int row, type, id;
  final int? textRow;
  final Map<String, String> values;
  final String name, description, category, searchText;
  ItemEntry(
    this.row,
    this.type,
    this.id,
    this.textRow,
    this.values,
    this.name,
    this.description,
  ) : category = itemFamilyLabel(type),
      searchText = foldedSearch(
        '$name $description $type:$id ${itemFamilyLabel(type)}',
      );
  String get key => '$type:$id';
  bool get named =>
      name.trim().isNotEmpty &&
      !RegExp(r'^[?\s]+$').hasMatch(name) &&
      !name.contains('\uFFFD');
  String get title => named ? name : 'Sin nombre legible · $key';
  RecordSummary get summary => RecordSummary(row, key, title, category, values);
}

String itemFamilyLabel(int type) {
  if ({121, 122}.contains(type)) return 'Alas';
  if ({42, 125}.contains(type)) return 'Monturas';
  if ({120, 123}.contains(type)) return 'Mascotas';
  if ({150, 151}.contains(type)) return 'Trajes';
  final f = ItemIconLayout.family(type);
  if (f >= 1 && f <= 15) return 'Armas';
  if ({19, 34}.contains(f)) return 'Escudos';
  if (equipmentSlotsForItemType(type).any((s) => s >= 0 && s <= 4)) {
    return 'Armaduras';
  }
  if ({22, 23, 24, 39, 40}.contains(f)) return 'Accesorios';
  if (type == 95) return 'Lapisias';
  if (type == 94) return 'Lingotes de gremio';
  if ({30, 98}.contains(type)) return 'Lapis y materiales';
  if ({27, 28, 29, 99, 128, 129}.contains(type)) return 'Misiones / materiales';
  if (f == 25 || {100, 101, 102, 103, 130, 131}.contains(type)) {
    return 'Consumibles / especiales';
  }
  return 'Otros · tipo $type';
}

/// Terms are ANDed. Names ignore accents; numeric comparisons use BigInt,
/// never double, preserving every 64-bit table value. Unknown fields are errors.
class ItemQuery {
  final List<bool Function(ItemEntry)> _tests;
  ItemQuery._(this._tests);
  factory ItemQuery.parse(String input, Iterable<String> fields) {
    if (input.length > 4096) {
      throw const FormatException('Consulta demasiado larga.');
    }
    final known = fields.map((s) => s.toLowerCase()).toSet();
    final tests = <bool Function(ItemEntry)>[];
    for (final m in RegExp(r'"([^"]*)"|(\S+)').allMatches(input)) {
      final token = m[1] ?? m[2]!;
      final cmp = RegExp(
        r'^([A-Za-z][A-Za-z0-9_]*)(>=|<=|!=|=|>|<)(-?\d+)$',
      ).firstMatch(token);
      if (cmp != null) {
        final field = cmp[1]!.toLowerCase(),
            op = cmp[2]!,
            value = BigInt.parse(cmp[3]!);
        if (!known.contains(field)) {
          throw FormatException('Campo desconocido: $field');
        }
        tests.add((item) {
          final actual = BigInt.tryParse(item.values[field] ?? '');
          if (actual == null) return false;
          final n = actual.compareTo(value);
          return switch (op) {
            '>=' => n >= 0,
            '<=' => n <= 0,
            '!=' => n != 0,
            '>' => n > 0,
            '<' => n < 0,
            _ => n == 0,
          };
        });
      } else {
        if (RegExp(r'^[A-Za-z]\w*[<>=!]').hasMatch(token)) {
          throw FormatException('Filtro numérico inválido: $token');
        }
        final exclude = token.startsWith('-') && token.length > 1;
        final text = foldedSearch(exclude ? token.substring(1) : token);
        tests.add((item) => item.searchText.contains(text) != exclude);
      }
    }
    return ItemQuery._(tests);
  }
  bool matches(ItemEntry entry) => _tests.every((test) => test(entry));
}

/// A working copy. No keystroke, preview, or Apply mutates the connected DATA.
/// All native table fields stay available even for unknown item categories.
class ItemWorkspace {
  final EditDocument data;
  final EditDocument? text;
  final Map<String, EditDocument> documents;
  final List<List<EditDocument>> _undo = [], _redo = [];
  late List<ItemEntry> entries;
  late Map<String, ItemEntry> byKey;
  int revision = 0;
  Library? _view;
  Library view(Library source) => _view ??= _ItemView(this, source);
  ItemWorkspace(this.data, this.text)
    : documents = {data.path: data, text.path: ?text} {
    if (!data.complete || (text != null && !text!.complete)) {
      throw const FormatException(
        'El editor de ítems requiere tablas completas.',
      );
    }
    rebuild();
  }
  static Future<ItemWorkspace> load(Library library, {String? textPath}) async {
    const path = 'binarysdata/dbitemdata.sdata';
    if (!library.files.containsKey(path)) {
      throw const FormatException(
        'Falta BinarySData/DBItemData.SData. No se sustituye por otra familia de tablas.',
      );
    }
    final choices = ClientLocale.tableCandidates(
      library.files.keys,
      'dbitemtext',
      beside: path,
    );
    final chosen = textPath ?? choices.firstOrNull;
    if (chosen != null && !choices.contains(chosen)) {
      throw const FormatException('Texto de otra familia.');
    }
    return compute(parse, <String, Object?>{
      'data': await library.read(path),
      'path': path,
      'text': chosen == null ? null : await library.read(chosen),
      'textPath': chosen,
    });
  }

  static ItemWorkspace parse(Map<String, Object?> input) => ItemWorkspace(
    EditorReader.open(input['data'] as Uint8List, input['path'] as String),
    input['text'] == null
        ? null
        : EditorReader.open(
            input['text'] as Uint8List,
            input['textPath'] as String,
            encoding: ClientLocale.encodingForPath(input['textPath'] as String),
          ),
  );
  static Map<String, String> values(EditDocument d, int row) => {
    for (final f in d.fields(row))
      if (f.spec.type != 'opaque') f.spec.name.toLowerCase(): d.read(f),
  };
  static String identity(Map<String, String> v) {
    final type = BigInt.tryParse(v['itemtype'] ?? v['type'] ?? ''),
        id = BigInt.tryParse(v['itemtypeid'] ?? v['typeid'] ?? '');
    if (type == null ||
        id == null ||
        type < BigInt.one ||
        type > BigInt.from(255) ||
        id < BigInt.one ||
        id > BigInt.from(65535)) {
      throw const FormatException('Identidad de ítem inválida.');
    }
    return '$type:$id';
  }

  void rebuild() {
    final names = <String, (int, Map<String, String>)>{};
    if (text != null)
      for (var row = 0; row < text!.rows.length; row++) {
        final v = values(text!, row), key = identity(v);
        if (names.containsKey(key)) {
          throw FormatException('Texto duplicado: $key');
        }
        names[key] = (row, v);
      }
    final next = <ItemEntry>[], keys = <String>{};
    for (var row = 0; row < data.rows.length; row++) {
      final v = values(data, row), key = identity(v);
      if (!keys.add(key)) throw FormatException('Objeto duplicado: $key');
      final ids = key.split(':'), n = names[key];
      next.add(
        ItemEntry(
          row,
          int.parse(ids[0]),
          int.parse(ids[1]),
          n?.$1,
          v,
          n?.$2['itemname'] ?? v['itemname'] ?? '',
          n?.$2['text'] ?? v['text'] ?? '',
        ),
      );
    }
    entries = next;
    byKey = {for (final e in next) e.key: e};
  }

  bool get dirty => documents.values.any((d) => d.dirty);
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  List<String> get fieldNames =>
      data.rows.isEmpty ? [] : data.fields(0).map((f) => f.spec.name).toList();
  List<String> get warnings => [
    for (final d in documents.values) ...d.warnings,
    if (text == null)
      'Sin DBItemText de esta familia: las propiedades numéricas siguen disponibles.',
  ];

  /// Each edit uses the exact field span; all documents validate before the
  /// first mutation. Identity remapping is intentionally a separate operation.
  void apply(Map<EditDocument, List<(int, FieldSpan, String)>> changes) {
    for (final pair in changes.entries) {
      if (documents[pair.key.path] != pair.key) {
        throw const FormatException('Documento ajeno a la sesión.');
      }
      for (final (row, f, value) in pair.value) {
        if ({
          'itemtype',
          'itemtypeid',
          'type',
          'typeid',
        }.contains(f.spec.name.toLowerCase())) {
          throw const FormatException(
            'La identidad requiere migrar sus referencias; no es una propiedad.',
          );
        }
        if (!pair.key
            .fields(row)
            .any((x) => x.start == f.start && x.spec.name == f.spec.name)) {
          throw const FormatException('Campo ajeno al registro.');
        }
        pair.key.validate(f, value);
      }
    }
    final applied = <EditDocument>[];
    try {
      for (final pair in changes.entries) {
        final before = pair.key.revision;
        pair.key.editMany(pair.value, title: 'Editar ítem / recurso asociado');
        if (pair.key.revision != before) applied.add(pair.key);
      }
    } catch (_) {
      for (final d in applied.reversed) {
        d.undo();
      }
      rethrow;
    }
    if (applied.isEmpty) return;
    _undo.add(applied);
    _redo.clear();
    revision++;
    rebuild();
  }

  void undo() {
    if (!canUndo) return;
    final batch = _undo.removeLast();
    for (final d in batch.reversed) {
      d.undo();
    }
    _redo.add(batch);
    revision++;
    rebuild();
  }

  void redo() {
    if (!canRedo) return;
    final batch = _redo.removeLast();
    for (final d in batch) {
      d.redo();
    }
    _undo.add(batch);
    revision++;
    rebuild();
  }

  Future<CatalogDocument> catalog(Library lib, String path) async {
    final present = documents[path];
    if (present is CatalogDocument) return present;
    final d = CatalogDocument.open(
      await lib.read(path, limit: 64 * 1024 * 1024),
      path,
      GameTextEncoding.automatic,
    );
    documents[path] = d;
    return d;
  }

  /// Includes original pair members, but encodes only changed documents.
  Future<Directory> export(Library lib, Directory destination) async {
    if (!dirty) throw const FormatException('No hay cambios que publicar.');
    if (await FileSystemEntity.type(destination.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw const FileSystemException(
        'El destino ya existe; elige una carpeta nueva.',
      );
    }
    final outputs = <String, Uint8List>{};
    for (final d in documents.values.where(
      (d) => d == data || d == text || d.dirty,
    )) {
      final bytes = d.exportBytes();
      final check = d is CatalogDocument
          ? CatalogDocument.open(bytes, d.path, d.codec.encoding)
          : EditorReader.open(bytes, d.path, encoding: d.codec.encoding);
      if (!check.complete || check.rows.length != d.rows.length) {
        throw FormatException('Relectura fallida: ${d.path}');
      }
      for (final change in d.changes) {
        final f = check
            .fields(change.row)
            .where((f) => f.spec.name == change.field.spec.name)
            .single;
        if (check.read(f) != d.read(change.field)) {
          throw FormatException('Cambio perdido: ${d.path} / ${f.spec.name}');
        }
      }
      outputs[d.path] = bytes;
    }
    Future<void> conflicts() async {
      for (final path in outputs.keys) {
        if (FileSave.hash(await lib.read(path)) != documents[path]!.sha) {
          throw FormatException('DATA cambió: $path. No se publicó el lote.');
        }
      }
    }

    await conflicts();
    await destination.parent.create(recursive: true);
    final stage = await destination.parent.createTemp('.items-stage-');
    try {
      for (final pair in outputs.entries) {
        final f = File('${stage.path}/COPIAR_EN_DATA/${canon(pair.key)}');
        await f.parent.create(recursive: true);
        await f.writeAsBytes(pair.value, flush: true);
        if (FileSave.hash(await f.readAsBytes()) != FileSave.hash(pair.value)) {
          throw const FileSystemException('Fallo de integridad.');
        }
      }
      final manifest = {
        'schema': 1,
        'kind': 'shaiya-studio-item-workspace',
        'iconProfile': ItemIconLayout.profile,
        'sourceDataModified': false,
        'serverDatabaseModified': false,
        'gameExecutableModified': false,
        'textSource': text?.path,
        'warnings': warnings,
        'files': [
          for (final pair in outputs.entries)
            {
              'path': pair.key,
              'beforeSha256': documents[pair.key]!.sha,
              'afterSha256': FileSave.hash(pair.value),
              'bytes': pair.value.length,
            },
        ],
        'changes': [
          for (final d in documents.values)
            for (final c in d.changes)
              {
                'path': d.path,
                'row': c.row,
                'field': c.field.spec.name,
                'before': c.beforeText,
                'after': d.read(c.field),
              },
        ],
      };
      await File('${stage.path}/manifest.json').writeAsString(
        const JsonEncoder.withIndent('  ').convert(manifest),
        flush: true,
      );
      await File('${stage.path}/LEEME.txt').writeAsString(
        'Ítems — exportación verificada, DATA original intacta\n\n'
        'Cierra juego y servidor local. Respalda los archivos enumerados en manifest.json.\n'
        'Verifica beforeSha256. Copia TODO el contenido de COPIAR_EN_DATA a la DATA de origen.\n'
        'No mezcles tablas de otra versión. Reabre DATA en Studio para verificar el lote.\n'
        'Los cambios de MLT/ITM/MON pueden afectar varios ítems que comparten referencias.\n'
        'Los parámetros desconocidos mantienen su nombre y unidad originales.\n'
        'Los valores efectivos del servidor necesitan sincronizarse con su base de datos.\n'
        'Esto no modifica game.exe, no instala vuelo nativo ni descifra recursos SPK no autenticados.\n',
        flush: true,
      );
      await conflicts();
      if (await destination.exists()) {
        throw const FileSystemException('Conflicto de destino.');
      }
      return await stage.rename(destination.path);
    } finally {
      if (await stage.exists()) await stage.delete(recursive: true);
    }
  }
}

/// Read-only overlay used by the existing model renderer; keeps the original
/// archive/SPK reader as the authority for every untouched resource.
class _ItemView extends Library {
  final ItemWorkspace workspace;
  final Library source;
  _ItemView(this.workspace, this.source)
    : super(source.location, source.saf, source.files);
  @override
  Future<Uint8List> read(String path, {int limit = 64 * 1024 * 1024}) async {
    final d = workspace.documents[canon(path)];
    if (d == null || !d.dirty) return source.read(path, limit: limit);
    final bytes = d.exportBytes();
    if (bytes.length > limit) {
      throw const FormatException('Recurso fuera de límite.');
    }
    return bytes;
  }

  @override
  void dispose() {}
}
