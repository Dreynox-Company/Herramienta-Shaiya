import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../core/archive_index.dart';
import 'archive_source.dart';
import 'spk_source.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

String baseName(String path) => path.replaceAll('\\', '/').split('/').last;
String directoryName(String path) {
  final x = path.replaceAll('\\', '/');
  final i = x.lastIndexOf('/');
  return i < 0 ? '' : x.substring(0, i);
}

String canon(String path) {
  final value = path.replaceAll('\\', '/').replaceAll(RegExp(r'/+'), '/');
  if (value.startsWith('/') ||
      value.contains(':') ||
      value.split('/').contains('..')) {
    throw FormatException('Ruta no relativa: $path');
  }
  return value.replaceFirst(RegExp(r'^\./'), '').toLowerCase();
}

const supportedExtensions = {
  '.sdata',
  '.txt',
  '.csv',
  '.svmap',
  '.env',
  '.seff',
  '.wtr',
  '.vani',
  '.3de',
  '.ini',
  '.xml',
  '.cfg',
  '.3dc',
  '.3do',
  '.ani',
  '.mlt',
  '.alt',
  '.itm',
  '.mon',
  '.dds',
  '.png',
  '.jpg',
  '.jpeg',
  '.tga',
  '.bmp',
  '.wav',
  '.mp3',
  '.ogg',
  '.wld',
  '.smod',
  '.dg',
  '.eft',
};
bool supportedPath(String p) {
  final i = p.lastIndexOf('.');
  return i >= 0 && supportedExtensions.contains(p.substring(i).toLowerCase());
}

class Library {
  static const channel = MethodChannel('dreynox.shaiya/data');
  final String location;
  final bool saf;
  final ArchiveSource? archive;
  final SpkArchiveSource? spkArchive;
  static Map<String, Object?>? lastArchiveReport;
  Map<String, Object?> get sourceDiagnostics =>
      spkArchive?.diagnostics() ??
      archive?.diagnostics() ??
      {
        'sourceMode': saf ? 'carpeta Android' : 'carpeta local',
        'files': files.length,
      };
  String get sourceLabel => spkArchive != null
      ? 'DATA.SPK · payloads autenticados'
      : archive == null
      ? 'Carpeta DATA'
      : 'Par SAH + SAF · lectura por rangos';
  void dispose() {
    archive?.close();
  }

  final Map<String, String> files;
  int revision = 0;
  final Map<String, List<String>> _names = {};
  Library(
    this.location,
    this.saf,
    this.files, {
    this.archive,
    this.spkArchive,
  }) {
    for (final p in files.keys) {
      _names.putIfAbsent(baseName(p), () => []).add(p);
    }
  }
  static Future<Library?> choose(void Function(String) progress) async {
    if (Platform.isAndroid) {
      final uri = await channel.invokeMethod<String>('chooseTree');
      if (uri == null) return null;
      progress('Indexando DATA con acceso de solo lectura…');
      final rows = await channel.invokeMethod<Map>('index', {'tree': uri});
      if (rows == null) {
        throw const FormatException('No se pudo leer la carpeta seleccionada.');
      }
      return _normalise(
        uri,
        true,
        rows.map((k, v) => MapEntry(k.toString(), v.toString())),
      );
    }
    final dir = await getDirectoryPath(confirmButtonText: 'Usar carpeta DATA');
    if (dir == null) return null;
    return fromDirectory(dir, progress);
  }

  static Future<Library?> chooseArchive(void Function(String) progress) async {
    lastArchiveReport = null;
    try {
      ArchiveSource source;
      if (Platform.isAndroid) {
        final pair = await channel.invokeMethod<Map>('chooseArchive');
        if (pair == null) return null;
        final sah = Map<String, dynamic>.from(pair['sah'] as Map),
            saf = Map<String, dynamic>.from(pair['saf'] as Map);
        progress(
          'Leyendo índice SAH… El SAF no se copia ni se carga completo.',
        );
        final size = (sah['size'] as num).toInt();
        if (size < 0 || size > ArchiveIndex.maxIndexBytes) {
          throw const ArchiveFailure(
            'INDEX_SIZE',
            'No se puede leer el tamaño del índice o supera 64 MiB',
            {'schema': 1},
          );
        }
        final bytes = await channel.invokeMethod<Uint8List>('archiveRead', {
          'uri': sah['uri'],
          'offset': 0,
          'length': size,
        });
        if (bytes == null) {
          throw const FormatException('El proveedor no entregó el índice.');
        }
        final index = await compute(parseArchiveIndex, {
          'bytes': bytes,
          'length': (saf['size'] as num).toInt(),
        });
        source = ArchiveSource(index, (offset, length) async {
          final b = await channel.invokeMethod<Uint8List>('archiveRead', {
            'uri': saf['uri'],
            'offset': offset,
            'length': length,
          });
          if (b == null) {
            throw const FormatException('No se pudo leer el rango SAF.');
          }
          return b;
        });
      } else {
        final selected = await openFiles(
          acceptedTypeGroups: [
            const XTypeGroup(
              label: 'Archivo Shaiya SAH/SAF',
              extensions: ['sah', 'saf'],
            ),
          ],
          confirmButtonText: 'Abrir par SAH + SAF',
        );
        if (selected.isEmpty) return null;
        final paths = <String, String>{};
        for (final f in selected) {
          final ext = f.path.split('.').last.toLowerCase();
          if (!['sah', 'saf'].contains(ext) || paths.containsKey(ext)) {
            throw const FormatException(
              'Selecciona un solo SAH y un solo SAF del mismo cliente.',
            );
          }
          paths[ext] = f.path;
        }
        if (paths.length == 1) {
          final first = paths.values.single,
              ext = paths.containsKey('sah') ? 'saf' : 'sah';
          final wanted =
              '${baseName(first).substring(0, baseName(first).length - 4)}.$ext'
                  .toLowerCase();
          await for (final f in Directory(
            directoryName(first),
          ).list(followLinks: false)) {
            if (f is File && baseName(f.path).toLowerCase() == wanted) {
              paths[ext] = f.path;
            }
          }
          if (!paths.containsKey(ext)) {
            final companion = await openFile(
              acceptedTypeGroups: [
                XTypeGroup(label: 'Archivo compañero .$ext', extensions: [ext]),
              ],
              confirmButtonText: 'Seleccionar .$ext',
            );
            if (companion == null) return null;
            paths[ext] = companion.path;
          }
        }
        if (paths.length != 2) {
          throw const FormatException(
            'Se necesitan los dos archivos, SAH y SAF.',
          );
        }
        progress('Validando índice, rutas y offsets SAH/SAF…');
        source = await ArchiveSource.fromFiles(paths['sah']!, paths['saf']!);
      }
      lastArchiveReport = source.diagnostics();
      try {
        final lib = _normalise('SAH+SAF', false, {
          for (final path in source.index.entries.keys) path: path,
        }, archive: source);
        progress(
          'Archivo indexado: ${lib.files.length} recursos compatibles · solo lectura',
        );
        return lib;
      } catch (_) {
        source.close();
        rethrow;
      }
    } on ArchiveFailure catch (e) {
      lastArchiveReport = e.report;
      rethrow;
    } catch (e) {
      lastArchiveReport = {
        ...?lastArchiveReport,
        'status': 'connection_failed',
        'error': e is FileSystemException
            ? e.osError?.message ?? 'No se pudo acceder al archivo'
            : e.toString(),
      };
      rethrow;
    }
  }

  static Future<Library> fromArchive(String sah, String saf) async {
    final source = await ArchiveSource.fromFiles(sah, saf);
    try {
      return _normalise('SAH+SAF', false, {
        for (final p in source.index.entries.keys) p: p,
      }, archive: source);
    } catch (_) {
      source.close();
      rethrow;
    }
  }

  static Library fromSpkSource(
    SpkArchiveSource source, {
    bool includeApproximateHints = false,
  }) {
    if (!source.canExtractAll) {
      throw const FormatException(
        'DATA.SPK todavía no tiene lectura completa validada. Ejecuta AutoPerfil SPK y valida simples + fragmentados antes de usarlo como biblioteca.',
      );
    }

    final mapped = <String, String>{};
    var confirmed = 0;
    var strongInferred = 0;
    var approximateInferred = 0;
    for (final record in source.index.resources) {
      String? path = source.names.confirmedPath(record.entryId);
      if (path != null) {
        confirmed++;
      } else {
        final hint = source.names.hints[record.entryId];
        if (hint == null) continue;
        if (hint.confidence == 'strong-inferred') {
          path = hint.path;
          strongInferred++;
        } else if (includeApproximateHints) {
          path = hint.path;
          approximateInferred++;
        }
      }
      if (path == null || !supportedPath(path)) continue;
      final key = canon(path);
      final previous = mapped[key];
      if (previous != null && previous != record.ordinal.toString()) {
        throw FormatException(
          'Dos recursos SPK intentan usar la misma ruta: $path',
        );
      }
      mapped[key] = record.ordinal.toString();
    }

    if (mapped.isEmpty) {
      throw const FormatException(
        'El SPK está validado criptográficamente, pero todavía no tiene rutas utilizables para montar la biblioteca.',
      );
    }

    final library = _normalise(
      source.file.path,
      false,
      mapped,
      spkArchive: source,
    );
    lastArchiveReport = {
      ...source.diagnostics(),
      'mountedAsLibrary': true,
      'mappedResources': library.files.length,
      'confirmedRoutes': confirmed,
      'strongInferredRoutes': strongInferred,
      'approximateInferredRoutes': approximateInferred,
      'approximateHintsIncluded': includeApproximateHints,
    };
    return library;
  }

  static Future<Library> fromDirectory(
    String dir,
    void Function(String) progress,
  ) async {
    var root = Directory(dir);
    if (!await root.exists()) {
      throw const FormatException('La carpeta DATA no existe.');
    }
    final child = await root
        .list(followLinks: false)
        .where(
          (e) => e is Directory && baseName(e.path).toLowerCase() == 'data',
        )
        .toList();
    if (child.length == 1) root = Directory(child.first.path);
    final map = <String, String>{};
    var n = 0;
    await for (final entry in root.list(recursive: true, followLinks: false)) {
      if (entry is! File || !supportedPath(entry.path)) continue;
      final rel = entry.path
          .substring(root.path.length + 1)
          .replaceAll('\\', '/');
      if (map.containsKey(canon(rel))) {
        throw FormatException(
          'Hay dos archivos que solo difieren en mayúsculas: $rel',
        );
      }
      map[canon(rel)] = entry.path;
      if (++n % 1000 == 0) progress('Indexando… $n recursos');
      if (n > 200000) {
        throw const FormatException(
          'La carpeta supera el límite de 200.000 recursos.',
        );
      }
    }
    return _normalise(root.path, false, map);
  }

  static Library _normalise(
    String location,
    bool saf,
    Map<String, String> source, {
    ArchiveSource? archive,
    SpkArchiveSource? spkArchive,
  }) {
    final map = <String, String>{};
    for (final entry in source.entries) {
      if (supportedPath(entry.key)) map[canon(entry.key)] = entry.value;
    }
    final hasCharacter = map.keys.any((p) => p.startsWith('character/'));
    if (!hasCharacter) {
      final nested = map.keys.where((p) => p.contains('/character/')).toList();
      if (nested.isEmpty) {
        throw const FormatException(
          'Selecciona DATA: no se encuentra Character.',
        );
      }
      final prefixes = nested
          .map((p) => p.substring(0, p.indexOf('/character/') + 1))
          .toSet();
      if (prefixes.length != 1) {
        throw const FormatException(
          'Hay varias bibliotecas DATA. Selecciona una sola.',
        );
      }
      final prefix = prefixes.single, trimmed = <String, String>{};
      for (final e in map.entries) {
        if (e.key.startsWith(prefix)) {
          trimmed[e.key.substring(prefix.length)] = e.value;
        }
      }
      return Library(
        location,
        saf,
        trimmed,
        archive: archive,
        spkArchive: spkArchive,
      );
    }
    return Library(
      location,
      saf,
      map,
      archive: archive,
      spkArchive: spkArchive,
    );
  }

  String? resolve(
    String name,
    List<String> directories, {
    bool uniqueFallback = false,
  }) {
    if (name.isEmpty || baseName(name).toLowerCase().startsWith('null.')) {
      return null;
    }
    final n = canon(name);
    final variants = {n};
    if (n.endsWith('.tga')) variants.add('${n.substring(0, n.length - 4)}.dds');
    for (final root in directories) {
      for (final v in variants) {
        final key = canon(root.isEmpty ? v : '$root/$v');
        if (files.containsKey(key)) return key;
      }
    }
    for (final v in variants) {
      if (files.containsKey(v)) return v;
    }
    if (uniqueFallback) {
      for (final v in variants) {
        final hits = _names[baseName(v)] ?? [];
        if (hits.length == 1) return hits.single;
        if (hits.length > 1) {
          throw FormatException(
            'Nombre ambiguo: $name (${hits.length} rutas).',
          );
        }
      }
    }
    return null;
  }

  Future<Uint8List> read(
    String path, {
    int limit = 64 * 1024 * 1024,
  }) async {
    final id = files[canon(path)];
    if (id == null) throw FormatException('Recurso ausente: $path');
    if (spkArchive != null) {
      final ordinal = int.tryParse(id);
      if (ordinal == null ||
          ordinal < 0 ||
          ordinal >= spkArchive!.index.records.length) {
        throw FormatException('Referencia SPK inválida para $path');
      }
      final record = spkArchive!.index.records[ordinal];
      if (!record.resource) {
        throw FormatException('La ruta SPK no apunta a un recurso: $path');
      }
      return (await spkArchive!.readEntry(record, limit: limit)).bytes;
    }
    if (archive != null) return archive!.read(id, limit: limit);
    if (saf) {
      final b = await channel.invokeMethod<Uint8List>('read', {
        'tree': location,
        'uri': id,
        'limit': limit,
      });
      if (b == null) throw FormatException('No se pudo leer $path');
      return b;
    }
    final f = File(id);
    if (await f.length() > limit) {
      throw FormatException('$path supera el límite de lectura.');
    }
    return f.readAsBytes();
  }
}