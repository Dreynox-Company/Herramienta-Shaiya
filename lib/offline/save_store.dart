import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Storage for the proposed local runtime, not a replacement for that runtime.
/// No networking, client patching, SQL execution or synthetic gameplay occurs.
/// Snapshots are immutable. A flushed staging file is renamed to commit a new
/// revision; an interrupted staging file cannot replace the last committed save.
class SaveSnapshot {
  final String id, title, faction, corpusSha256, createdAt, updatedAt, checksum;
  final int revision;
  final bool deleted;
  final Map<String, Object?> state;
  const SaveSnapshot({
    required this.id,
    required this.title,
    required this.faction,
    required this.corpusSha256,
    required this.createdAt,
    required this.updatedAt,
    required this.revision,
    required this.deleted,
    required this.state,
    required this.checksum,
  });
  Map<String, Object?> get metadata => {
    'id': id,
    'title': title,
    'faction': faction,
    'corpusSha256': corpusSha256,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'revision': revision,
    'deleted': deleted,
    'checksum': checksum,
  };
}

class SaveConflict implements Exception {
  final String message;
  const SaveConflict(this.message);
  @override
  String toString() => 'SaveConflict: $message';
}

class SaveListing {
  final List<SaveSnapshot> saves;
  final Map<String, String> unreadable;
  const SaveListing(this.saves, this.unreadable);
}

class SaveStore {
  static const maxSnapshotBytes = 8 * 1024 * 1024;
  static final _idPattern = RegExp(r'^[0-9a-f]{32}$');
  static final _hashPattern = RegExp(r'^[0-9a-f]{64}$');
  static final _revisionPattern = RegExp(r'^([0-9]{12})\.json$');
  static final _queues = <String, Future<void>>{};
  final Directory directory;
  final DateTime Function() now;
  final void Function(String stage)? faultInjector;
  SaveStore(this.directory, {DateTime Function()? clock, this.faultInjector})
    : now = clock ?? DateTime.now;

  String _id() => List.generate(
    16,
    (_) => Random.secure().nextInt(256),
  ).map((n) => n.toRadixString(16).padLeft(2, '0')).join();
  void _checkId(String id) {
    if (!_idPattern.hasMatch(id)) {
      throw const FormatException('ID de partida no válido.');
    }
  }

  static void _jsonValue(Object? v, [int depth = 0]) {
    if (depth > 48) throw const FormatException('Estado demasiado anidado.');
    if (v == null || v is bool || v is String || v is int) return;
    if (v is double && v.isFinite) return;
    if (v is List) {
      for (final x in v) {
        _jsonValue(x, depth + 1);
      }
      return;
    }
    if (v is Map && v.keys.every((k) => k is String)) {
      for (final x in v.values) {
        _jsonValue(x, depth + 1);
      }
      return;
    }
    throw const FormatException('Estado no serializable sin pérdidas (JSON).');
  }

  static void _validateMeta(String title, String faction, String corpus) {
    if (title.trim().isEmpty ||
        title.runes.length > 120 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(title)) {
      throw const FormatException(
        'Nombre vacío, demasiado largo o con controles.',
      );
    }
    if (!['luz', 'furia'].contains(faction)) {
      throw const FormatException(
        'Facción no declarada por este contrato de partidas.',
      );
    }
    if (!_hashPattern.hasMatch(corpus)) {
      throw const FormatException('Falta la huella del conjunto de datos.');
    }
  }

  Future<Directory> _root() async {
    await directory.create(recursive: true);
    if (await FileSystemEntity.type(directory.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const FormatException(
        'El directorio de partidas no puede ser un enlace.',
      );
    }
    return Directory(await directory.resolveSymbolicLinks());
  }

  Future<Directory> _saveDir(
    Directory root,
    String id, {
    bool create = false,
  }) async {
    _checkId(id);
    final dir = Directory(p.join(root.path, id));
    if (create) await dir.create();
    if (await FileSystemEntity.type(dir.path, followLinks: false) !=
            FileSystemEntityType.directory ||
        !p.equals(await dir.resolveSymbolicLinks(), dir.path)) {
      throw const FormatException('Carpeta de partida ausente o redirigida.');
    }
    return dir;
  }

  Future<T> _locked<T>(Future<T> Function(Directory root) work) async {
    final root = await _root(), key = root.path;
    final previous = _queues[key] ?? Future<void>.value();
    final release = Completer<void>();
    _queues[key] = release.future;
    await previous;
    RandomAccessFile? lock;
    bool acquired = false;
    try {
      final path = p.join(root.path, '.writer.lock');
      final kind = await FileSystemEntity.type(path, followLinks: false);
      if (kind != FileSystemEntityType.file &&
          kind != FileSystemEntityType.notFound) {
        throw const FormatException('Archivo de bloqueo inválido.');
      }
      lock = await File(path).open(mode: FileMode.append);
      try {
        await lock.lock(FileLock.exclusive);
        acquired = true;
      } on FileSystemException {
        throw const SaveConflict('Otra instancia está guardando.');
      }
      return await work(root);
    } finally {
      if (lock != null) {
        try {
          if (acquired) await lock.unlock();
        } finally {
          await lock.close();
        }
      }
      release.complete();
      if (identical(_queues[key], release.future)) _queues.remove(key);
    }
  }

  Future<List<File>> _revisions(Directory dir) async {
    final files = <File>[];
    await for (final e in dir.list(followLinks: false)) {
      if (_revisionPattern.hasMatch(p.basename(e.path))) {
        if (e is! File) {
          throw const FormatException('Una revisión no puede ser un enlace.');
        }
        files.add(e);
      }
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  Future<SaveSnapshot> _readFile(File file, String expectedId) async {
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
            FileSystemEntityType.file ||
        await file.length() > maxSnapshotBytes) {
      throw const FormatException('Revisión ilegible o fuera de límite.');
    }
    final envelope = jsonDecode(await file.readAsString());
    if (envelope is! Map ||
        envelope['schema'] != 1 ||
        envelope['payload'] is! String ||
        envelope['sha256'] is! String) {
      throw const FormatException('Formato de partida no reconocido.');
    }
    final payload = envelope['payload'] as String;
    if (sha256.convert(utf8.encode(payload)).toString() != envelope['sha256']) {
      throw const FormatException(
        'La partida no supera la comprobación de integridad. No se restaura otra revisión silenciosamente.',
      );
    }
    final value = jsonDecode(payload);
    if (value is! Map ||
        value['id'] != expectedId ||
        value['state'] is! Map ||
        value['revision'] is! int ||
        value['deleted'] is! bool ||
        value['title'] is! String ||
        value['faction'] is! String ||
        value['corpusSha256'] is! String ||
        value['createdAt'] is! String ||
        value['updatedAt'] is! String) {
      throw const FormatException('Metadatos de partida incompletos.');
    }
    final revision = value['revision'] as int;
    if (p.basename(file.path) !=
            '${revision.toString().padLeft(12, '0')}.json' ||
        revision < 1) {
      throw const FormatException('Identidad de revisión incoherente.');
    }
    _validateMeta(value['title'], value['faction'], value['corpusSha256']);
    DateTime.parse(value['createdAt']);
    DateTime.parse(value['updatedAt']);
    _jsonValue(value['state']);
    return SaveSnapshot(
      id: expectedId,
      title: value['title'],
      faction: value['faction'],
      corpusSha256: value['corpusSha256'],
      createdAt: value['createdAt'],
      updatedAt: value['updatedAt'],
      revision: revision,
      deleted: value['deleted'],
      state: Map<String, Object?>.from(value['state']),
      checksum: envelope['sha256'],
    );
  }

  Future<SaveSnapshot> _latest(Directory dir, String id) async {
    final files = await _revisions(dir);
    if (files.isEmpty) {
      throw const FormatException(
        'La partida no tiene ninguna revisión confirmada.',
      );
    }
    return _readFile(files.last, id);
  }

  Future<SaveSnapshot> _write(Directory dir, Map<String, Object?> value) async {
    _jsonValue(value['state']);
    final payload = jsonEncode(value);
    final envelope = jsonEncode({
      'schema': 1,
      'sha256': sha256.convert(utf8.encode(payload)).toString(),
      'payload': payload,
    });
    final bytes = utf8.encode(envelope);
    if (bytes.length > maxSnapshotBytes) {
      throw const FormatException('La partida excede 8 MiB.');
    }
    final destination = File(
      p.join(
        dir.path,
        '${(value['revision'] as int).toString().padLeft(12, '0')}.json',
      ),
    );
    if (await FileSystemEntity.type(destination.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw const SaveConflict('La revisión ya existe; no se sobrescribe.');
    }
    final staging = File(p.join(dir.path, '.pending-${_id()}'));
    try {
      await staging.writeAsBytes(bytes, flush: true);
      faultInjector?.call('beforeCommit');
      await staging.rename(destination.path);
      return await _readFile(destination, value['id'] as String);
    } finally {
      if (await staging.exists()) await staging.delete();
    }
  }

  Future<SaveSnapshot> create({
    required String title,
    required String faction,
    required String corpusSha256,
    Map<String, Object?> state = const {},
  }) {
    _validateMeta(title, faction, corpusSha256);
    _jsonValue(state);
    final snapshot = Map<String, Object?>.from(jsonDecode(jsonEncode(state)));
    return _locked((root) async {
      final id = _id(),
          dir = await _saveDir(root, id, create: true),
          date = now().toUtc().toIso8601String();
      return _write(dir, {
        'id': id,
        'title': title.trim(),
        'faction': faction,
        'corpusSha256': corpusSha256,
        'createdAt': date,
        'updatedAt': date,
        'revision': 1,
        'deleted': false,
        'state': snapshot,
      });
    });
  }

  Future<SaveSnapshot> load(String id, {String? expectedCorpus}) =>
      _locked((root) async {
        final value = await _latest(await _saveDir(root, id), id);
        if (value.deleted) {
          throw const SaveConflict('La partida está en la papelera.');
        }
        if (expectedCorpus != null && expectedCorpus != value.corpusSha256) {
          throw const SaveConflict(
            'Esta partida pertenece a otro conjunto de datos.',
          );
        }
        return value;
      });
  Future<SaveSnapshot> update(
    String id, {
    required int expectedRevision,
    required String expectedCorpus,
    required Map<String, Object?> state,
    String? title,
  }) {
    _jsonValue(state);
    final snapshot = Map<String, Object?>.from(jsonDecode(jsonEncode(state)));
    return _locked((root) async {
      final dir = await _saveDir(root, id), old = await _latest(dir, id);
      if (old.deleted ||
          old.revision != expectedRevision ||
          old.corpusSha256 != expectedCorpus) {
        throw const SaveConflict(
          'Partida eliminada, revisión desactualizada o datos distintos.',
        );
      }
      _validateMeta(title ?? old.title, old.faction, old.corpusSha256);
      return _write(dir, _next(old, state: snapshot, title: title));
    });
  }

  Map<String, Object?> _next(
    SaveSnapshot old, {
    Map<String, Object?>? state,
    String? title,
    bool? deleted,
  }) => {
    'id': old.id,
    'title': title?.trim() ?? old.title,
    'faction': old.faction,
    'corpusSha256': old.corpusSha256,
    'createdAt': old.createdAt,
    'updatedAt': now().toUtc().toIso8601String(),
    'revision': old.revision + 1,
    'deleted': deleted ?? old.deleted,
    'state': state ?? old.state,
  };

  /// Tombstones preserve all prior snapshots; deletion is intentionally reversible.
  Future<SaveSnapshot> trash(
    String id, {
    required int expectedRevision,
    bool restore = false,
  }) => _locked((root) async {
    final dir = await _saveDir(root, id), old = await _latest(dir, id);
    if (old.revision != expectedRevision || old.deleted != restore) {
      throw const SaveConflict('El estado de la papelera cambió.');
    }
    return _write(dir, _next(old, deleted: !restore));
  });
  Future<SaveListing> list({bool includeDeleted = false}) =>
      _locked((root) async {
        final saves = <SaveSnapshot>[], problems = <String, String>{};
        await for (final entry in root.list(followLinks: false)) {
          final id = p.basename(entry.path);
          if (!_idPattern.hasMatch(id)) continue;
          try {
            final save = await _latest(await _saveDir(root, id), id);
            if (!save.deleted || includeDeleted) saves.add(save);
          } catch (e) {
            problems[id] = e.toString();
          }
        }
        saves.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        return SaveListing(saves, problems);
      });
}
