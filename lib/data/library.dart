import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../core/archive_index.dart';
import '../core/spk_archive.dart';
import 'archive_source.dart';
import 'spk_source.dart';
import 'spk_writer.dart';
import 'file_save.dart';

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
  '.json',
  '.bin',
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
  '.gif',
  '.zip',
  '.exe',
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
  final SpkArchiveSource? spk;
  final String? spkOverlayRoot;
  final Map<String, Object?> _spkMountReport;
  static Map<String, Object?>? lastArchiveReport;

  Map<String, Object?> get sourceDiagnostics {
    if (spk != null) {
      return {
        ...spk!.diagnostics(),
        'sourceMode': 'spk-v3-workspace',
        'mountedFiles': files.length,
        'overlayRoot': spkOverlayRoot,
        ..._spkMountReport,
      };
    }
    return archive?.diagnostics() ??
        {
          'sourceMode': saf ? 'carpeta Android' : 'carpeta local',
          'files': files.length,
        };
  }

  String get sourceLabel {
    if (spk != null) {
      if (!spk!.canReadSimpleResources) {
        return 'DATA.SPK · índice abierto · perfil de lectura pendiente';
      }
      return spk!.canExtractAll
          ? 'DATA.SPK · lectura autenticada + overlay editable'
          : 'DATA.SPK · acceso parcial autenticado · fragmentos bloqueados · overlay editable';
    }
    return archive == null
        ? 'Carpeta DATA'
        : 'Par SAH + SAF · lectura por rangos';
  }

  bool get isSpkWorkspace => spk != null;

  void dispose() {
    archive?.close();
  }

  final Map<String, String> files;
  int revision = 0;
  final Map<String, List<String>> _names = {};
  final Map<String, SpkRecord> _spkRecords = {};

  Library(
    this.location,
    this.saf,
    this.files, {
    this.archive,
    this.spk,
    this.spkOverlayRoot,
    Map<String, Object?> spkMountReport = const {},
  }) : _spkMountReport = Map<String, Object?>.from(spkMountReport) {
    for (final p in files.keys) {
      _names.putIfAbsent(baseName(p), () => []).add(p);
    }
    if (spk != null) {
      for (final record in spk!.index.resources) {
        _spkRecords[record.idHex] = record;
      }
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

  /// Mount readable resources lazily. Only confirmed paths enter semantic
  /// Character/Item catalogs; inferred names remain technical Entry IDs.
  /// No whole-archive extraction or decryption is triggered by opening Studio.
  static Future<Library> fromSpkEditable(
    SpkArchiveSource source, {
    bool allowLocked = false,
    void Function(String)? progress,
    String? overlayRoot,
  }) async {
    if (!source.canReadSimpleResources && !allowLocked) {
      throw const SpkFailure(
        'SPK_WORKSPACE_PROFILE',
        'Autentica primero el perfil de recursos simples.',
      );
    }
    final files = <String, String>{};
    var blocked = 0, confirmed = 0, technical = 0;
    for (final record in source.index.resources) {
      if (!source.canReadRecord(record)) {
        blocked++;
        continue;
      }
      final hasName =
          source.names.isConfirmed(record.entryId) &&
          supportedPath(source.names[record.entryId]!);
      final path = hasName
          ? canon(SpkArchiveSource.safeRelative(source.names[record.entryId]!))
          : canon(
              '_SPK_SinNombre/${record.idHex}${SpkArchiveSource.extensionFor(source.validatedFormat(record.entryId) ?? 'BIN')}',
            );
      if (!supportedPath(path)) continue;
      if (files.containsKey(path) && files[path] != record.idHex) {
        throw FormatException(
          'Dos Entry IDs reclaman la misma ruta confirmada: $path',
        );
      }
      files[path] = record.idHex;
      if (hasName) {
        confirmed++;
      } else {
        technical++;
      }
    }
    if (files.isEmpty && !allowLocked) {
      throw const FormatException('No hay recursos legibles para montar.');
    }
    progress?.call(
      'SPK: $confirmed rutas confirmadas, $technical Entry IDs, $blocked recursos bloqueados.',
    );
    return _normalise(
      source.file.path,
      false,
      files,
      spk: source,
      spkOverlayRoot: overlayRoot ?? '${source.file.path}.studio-overlay',
      requireCharacter: false,
      spkMountReport: {
        'selectiveMount': true,
        'confirmedMounted': confirmed,
        'technicalMounted': technical,
        'blockedResources': blocked,
        'inferredMounted': 0,
        'completePayloadAccess': source.canExtractAll,
      },
    );
  }

  static Future<Library> fromSpk(
    SpkArchiveSource source, {
    void Function(String)? progress,
    bool requireComplete = true,
    bool requireCharacter = true,
    String? overlayRoot,
  }) async {
    if (!source.canReadSimpleResources) {
      throw const SpkFailure(
        'SPK_WORKSPACE_PROFILE',
        'El DATA.SPK necesita primero un perfil de payloads autenticado.',
      );
    }
    if (requireComplete && !source.canExtractAll) {
      throw const SpkFailure(
        'SPK_WORKSPACE_FRAGMENT_PROFILE',
        'Para montar el SPK en la herramienta 3D deben estar validados también los recursos fragmentados.',
      );
    }

    final mounted = <String, String>{};
    final confirmedByPath = <String, bool>{};
    final ambiguousInferredPaths = <String>{};
    var unnamed = 0;
    var unsupported = 0;
    var unsafe = 0;
    var collisions = 0;
    var ambiguousExcluded = 0;
    var inferred = 0;
    var confirmed = 0;
    var technical = 0;

    for (final record in source.index.resources) {
      var raw = source.names[record.entryId];
      var technicalPath = false;
      if (raw == null) {
        if (!source.fullyValidatedResources) {
          unnamed++;
          continue;
        }
        final format = source.validatedFormat(record.entryId) ?? 'BIN';
        raw =
            '_SPK_SinNombre/${record.idHex}'
            '${SpkArchiveSource.extensionFor(format)}';
        technicalPath = true;
      }
      String normalized;
      try {
        normalized = SpkArchiveSource.safeRelative(raw).replaceAll('\\', '/');
        normalized = canon(normalized);
      } catch (_) {
        unsafe++;
        continue;
      }
      if (!supportedPath(normalized)) {
        unsupported++;
        continue;
      }
      final isConfirmed = source.names.isConfirmed(record.entryId);
      if (ambiguousInferredPaths.contains(normalized) && !isConfirmed) {
        collisions++;
        continue;
      }
      if (mounted.containsKey(normalized)) {
        collisions++;
        final previousConfirmed = confirmedByPath[normalized] == true;
        if (previousConfirmed) continue;
        if (!isConfirmed) {
          mounted.remove(normalized);
          confirmedByPath.remove(normalized);
          ambiguousInferredPaths.add(normalized);
          ambiguousExcluded++;
          if (inferred > 0) inferred--;
          continue;
        }
        if (inferred > 0) inferred--;
      }
      if (isConfirmed) ambiguousInferredPaths.remove(normalized);
      mounted[normalized] = record.idHex;
      confirmedByPath[normalized] = isConfirmed;
      if (isConfirmed) {
        confirmed++;
      } else if (technicalPath) {
        technical++;
      } else {
        inferred++;
      }
    }

    if (source.fullyValidatedResources) {
      for (final record in source.index.resources) {
        if (source.names.isConfirmed(record.entryId)) continue;
        final format = source.validatedFormat(record.entryId) ?? 'BIN';
        final alias = canon(
          '_SPK_SinNombre/${record.idHex}'
          '${SpkArchiveSource.extensionFor(format)}',
        );
        if (!supportedPath(alias)) continue;
        final existing = mounted[alias];
        if (existing == null) {
          mounted[alias] = record.idHex;
          confirmedByPath[alias] = false;
          technical++;
        } else if (existing != record.idHex) {
          throw FormatException(
            'Colisión imposible de ruta técnica SPK: $alias.',
          );
        }
      }
    }

    if (mounted.isEmpty) {
      throw const FormatException(
        'El SPK no tiene todavía rutas utilizables para montar una biblioteca.',
      );
    }

    final root = overlayRoot ?? '${source.file.path}.studio-overlay';
    final report = <String, Object?>{
      'confirmedMounted': confirmed,
      'inferredMounted': inferred,
      'technicalMounted': technical,
      'unresolvedSkipped': unnamed,
      'unsupportedSkipped': unsupported,
      'unsafeSkipped': unsafe,
      'pathCollisions': collisions,
      'ambiguousInferredPathsExcluded': ambiguousExcluded,
      'completePayloadAccess': source.canExtractAll,
    };
    progress?.call(
      'Montando SPK en Studio: ${mounted.length} recursos '
      '(incluidos $technical por Entry ID técnico)…',
    );
    return _normalise(
      source.file.path,
      false,
      mounted,
      spk: source,
      spkOverlayRoot: root,
      spkMountReport: report,
      requireCharacter: requireCharacter,
    );
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
    SpkArchiveSource? spk,
    String? spkOverlayRoot,
    Map<String, Object?> spkMountReport = const {},
    bool requireCharacter = true,
  }) {
    final map = <String, String>{};
    for (final entry in source.entries) {
      if (supportedPath(entry.key)) map[canon(entry.key)] = entry.value;
    }
    final hasCharacter = map.keys.any((p) => p.startsWith('character/'));
    if (!hasCharacter && requireCharacter) {
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
        spk: spk,
        spkOverlayRoot: spkOverlayRoot,
        spkMountReport: spkMountReport,
      );
    }
    return Library(
      location,
      saf,
      map,
      archive: archive,
      spk: spk,
      spkOverlayRoot: spkOverlayRoot,
      spkMountReport: spkMountReport,
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

  bool _isTechnicalSpkPath(String canonical, SpkRecord record) {
    final source = spk;
    if (source == null || !source.canReadRecord(record)) return false;
    final format = source.validatedFormat(record.entryId) ?? 'BIN';
    final technical = canon(
      '_SPK_SinNombre/${record.idHex}'
      '${SpkArchiveSource.extensionFor(format)}',
    );
    return canonical == technical ||
        canonical == canon('_SPK_SinNombre/${record.idHex}.bin');
  }

  File _spkOverlayFile(String path) {
    final root = spkOverlayRoot;
    if (root == null) {
      throw StateError('El workspace SPK no tiene overlay configurado.');
    }
    final relative = canon(path).replaceAll('/', Platform.pathSeparator);
    return File('$root${Platform.pathSeparator}$relative');
  }

  Future<({Uint8List bytes, String baseSha})> _spkSnapshot(
    String path,
    int limit,
  ) async {
    final id = files[path], source = spk!;
    final record = _spkRecords[id];
    if (record == null) throw FormatException('Registro SPK ausente: $path');
    final original = (await source.readEntry(record, limit: limit)).bytes;
    final baseSha = sha256.convert(original).toString();
    final manifestFile = File(
      '$spkOverlayRoot${Platform.pathSeparator}_SPK_OVERLAY.json',
    );
    if (!await manifestFile.exists()) {
      if (await _spkOverlayFile(path).exists()) {
        throw const FormatException(
          'Overlay sin manifiesto: no se cargan cambios no confirmados.',
        );
      }
      return (bytes: original, baseSha: baseSha);
    }
    if (await manifestFile.length() > 64 * 1024 * 1024) {
      throw const FormatException('Manifiesto overlay demasiado grande.');
    }
    final manifest = jsonDecode(await manifestFile.readAsString());
    if (manifest is! Map ||
        manifest['indexSha256'] != source.index.encryptedIndexSha256 ||
        manifest['entries'] is! Map) {
      throw const FormatException(
        'El manifiesto overlay no corresponde al SPK abierto.',
      );
    }
    final hits = (manifest['entries'] as Map).entries
        .where((e) => e.value is Map && e.value['entryId'] == id)
        .toList();
    if (hits.isEmpty) return (bytes: original, baseSha: baseSha);
    if (hits.length != 1) {
      throw const FormatException(
        'El overlay contiene dos cambios para el mismo Entry ID.',
      );
    }
    final entry = hits.single;
    if (entry.value['originalSha256'] != baseSha) {
      throw const FormatException(
        'El recurso SPK original cambió desde la edición.',
      );
    }
    final file = _spkOverlayFile(
      canon((entry.value['file'] ?? entry.key).toString()),
    );
    if (!await file.exists()) {
      throw const FormatException('Falta el archivo del overlay.');
    }
    if (await file.length() > limit) {
      throw FormatException('$path supera el presupuesto de lectura.');
    }
    final bytes = await file.readAsBytes();
    if (bytes.length != entry.value['bytes'] ||
        sha256.convert(bytes).toString() != entry.value['overlaySha256']) {
      throw const FormatException(
        'Los bytes del overlay no coinciden con su manifiesto.',
      );
    }
    return (bytes: bytes, baseSha: baseSha);
  }

  Future<void> _overlayTail = Future<void>.value();
  Future<void> writeSpkOverlay(
    Map<String, Uint8List> replacements, {
    required Map<String, String> expectedHashes,
    bool keepBackup = true,
  }) {
    final copy = {
      for (final entry in replacements.entries)
        entry.key: Uint8List.fromList(entry.value),
    };
    final hashes = Map<String, String>.from(expectedHashes);
    final result = _overlayTail.then(
      (_) => _writeSpkOverlay(
        copy,
        expectedHashes: hashes,
        keepBackup: keepBackup,
      ),
    );
    _overlayTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<void> _writeSpkOverlay(
    Map<String, Uint8List> replacements, {
    required Map<String, String> expectedHashes,
    bool keepBackup = true,
  }) async {
    if (spk == null || spkOverlayRoot == null) {
      throw const FormatException(
        'La biblioteca abierta no es un workspace SPK.',
      );
    }
    if (!spk!.canReadSimpleResources) {
      throw const SpkFailure(
        'SPK_OVERLAY_PROFILE',
        'El overlay editable requiere un perfil autenticado. Cada recurso se valida al leerlo.',
      );
    }
    if (replacements.isEmpty) return;

    // Capture the manifest BEFORE resource validation. An external edit during
    // asynchronous decryption must not become a new baseline we overwrite.
    final manifestFile = File(
      '$spkOverlayRoot${Platform.pathSeparator}_SPK_OVERLAY.json',
    );
    if (await manifestFile.exists() &&
        await manifestFile.length() > 64 * 1024 * 1024) {
      throw const FormatException('Manifiesto overlay demasiado grande.');
    }
    final oldManifest = await manifestFile.exists()
        ? await manifestFile.readAsBytes()
        : null;
    final verified =
        <String, ({String canonical, Uint8List bytes, String originalSha})>{};
    for (final entry in replacements.entries) {
      final canonical = canon(entry.key);
      if (!files.containsKey(canonical)) {
        throw FormatException(
          'El recurso no pertenece al SPK montado: ${entry.key}',
        );
      }
      final record = _spkRecords[files[canonical]];
      if (record == null) {
        throw FormatException(
          'No se encontró el registro SPK de ${entry.key}.',
        );
      }
      final confirmedName = spk!.names.isConfirmed(record.entryId);
      final technicalIdPath = _isTechnicalSpkPath(canonical, record);
      if (!confirmedName && !technicalIdPath) {
        throw FormatException(
          'La ruta ${entry.key} todavía es inferida. Antes de editarla, '
          'confírmala por SHA-256 o con el descubrimiento estructural de tablas. '
          'Los recursos sin nombre sí pueden editarse por su ruta técnica '
          'Entry ID después de autenticar su lectura.',
        );
      }
      final expected = expectedHashes[entry.key] ?? expectedHashes[canonical];
      if (expected == null || expected.isEmpty) {
        throw FormatException('Falta el hash esperado de ${entry.key}.');
      }
      final snapshot = await _spkSnapshot(canonical, 128 * 1024 * 1024);
      final actual = sha256.convert(snapshot.bytes).toString();
      if (actual != expected) {
        throw FormatException(
          'El recurso cambió desde que se abrió el editor: ${entry.key}. '
          'Esperado $expected, actual $actual.',
        );
      }
      verified[canonical] = (
        canonical: canonical,
        bytes: Uint8List.fromList(entry.value),
        originalSha: snapshot.baseSha,
      );
    }

    final root = Directory(spkOverlayRoot!);
    await root.create(recursive: true);
    final stamp = DateTime.now().toUtc().toIso8601String();
    final currentManifest = await manifestFile.exists()
        ? await manifestFile.readAsBytes()
        : null;
    if ((oldManifest == null) != (currentManifest == null) ||
        (oldManifest != null &&
            FileSave.hash(oldManifest) != FileSave.hash(currentManifest!))) {
      throw const FormatException(
        'El overlay cambió durante la verificación. Vuelve a abrir el recurso.',
      );
    }
    Map<String, dynamic> manifest = {
      'schema': 1,
      'sourceSpk': spk!.file.path,
      'indexSha256': spk!.index.encryptedIndexSha256,
      'entries': <String, dynamic>{},
    };
    if (oldManifest != null) {
      try {
        final raw = jsonDecode(utf8.decode(oldManifest));
        if (raw is! Map ||
            raw['entries'] is! Map ||
            raw['indexSha256']?.toString().toLowerCase() !=
                spk!.index.encryptedIndexSha256.toLowerCase()) {
          throw const FormatException('El manifiesto no corresponde al SPK.');
        }
        manifest = Map<String, dynamic>.from(raw);
      } catch (_) {
        throw const FormatException(
          'No se puede guardar sobre un manifiesto overlay inválido.',
        );
      }
    }
    final entries = Map<String, dynamic>.from(
      (manifest['entries'] as Map?) ?? const {},
    );

    for (final item in verified.values) {
      final contentHash = sha256.convert(item.bytes).toString();
      final contentPath = '_versions/${files[item.canonical]}/$contentHash.bin';
      final target = _spkOverlayFile(contentPath);
      await target.parent.create(recursive: true);
      final temp = File(
        '${target.path}.${DateTime.now().microsecondsSinceEpoch}.partial',
      );
      await temp.writeAsBytes(item.bytes, flush: true);
      final writtenSha = sha256.convert(await temp.readAsBytes()).toString();
      final expectedWritten = sha256.convert(item.bytes).toString();
      if (writtenSha != expectedWritten) {
        await temp.delete();
        throw FormatException(
          'La verificación del overlay falló para ${item.canonical}.',
        );
      }
      if (await target.exists()) {
        if (sha256.convert(await target.readAsBytes()).toString() !=
            expectedWritten) {
          await temp.delete();
          throw const FormatException(
            'Generación de overlay alterada externamente.',
          );
        }
        await temp.delete();
      } else {
        await temp.rename(target.path);
      }
      final record = _spkRecords[files[item.canonical]];
      entries.removeWhere(
        (_, info) => info is Map && info['entryId'] == files[item.canonical],
      );
      entries[item.canonical] = {
        'entryId': files[item.canonical],
        'file': contentPath,
        'nameAuthority':
            record != null && spk!.names.isConfirmed(record.entryId)
            ? 'confirmed-path'
            : 'technical-entry-id',
        'originalSha256': item.originalSha,
        'overlaySha256': expectedWritten,
        'bytes': item.bytes.length,
        'updatedAt': stamp,
      };
    }

    manifest = {
      ...manifest,
      'schema': 1,
      'sourceSpk': spk!.file.path,
      'indexSha256': spk!.index.encryptedIndexSha256,
      'updatedAt': stamp,
      'entries': entries,
    };
    final manifestBytes = Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(manifest)),
    );
    if (oldManifest != null) {
      await FileSave.replace(
        manifestFile.path,
        manifestBytes,
        expectedHash: sha256.convert(oldManifest).toString(),
        keepBackup: keepBackup,
      );
    } else {
      // An exclusive creation is the first publication. An interrupted first
      // save is reported, never interpreted as an empty successful manifest.
      await manifestFile.create(exclusive: true);
      await manifestFile.writeAsBytes(manifestBytes, flush: true);
    }
  }

  Future<Map<String, Object?>> exportSpkWorkspace(
    Directory parent, {
    required void Function(String message, int done, int total) progress,
  }) async {
    final source = spk;
    final overlayRoot = spkOverlayRoot;
    if (source == null || overlayRoot == null) {
      throw const FormatException(
        'La biblioteca abierta no es un workspace DATA.SPK.',
      );
    }
    if (!source.fullyValidatedResources) {
      throw const SpkFailure(
        'SPK_WORKSPACE_EXPORT_AUDIT',
        'Antes de materializar DATA deben estar auditados todos los recursos.',
      );
    }

    final extracted = await source.extract(
      parent,
      control: SpkExtractControl(),
      progress: progress,
      requireComplete: true,
    );
    final folderValue = extracted['folder']?.toString();
    if (folderValue == null || folderValue.isEmpty) {
      throw const FormatException('La extracción SPK no publicó una carpeta.');
    }
    final folder = Directory(folderValue);
    try {
      final manifestFile = File(
        '${folder.path}${Platform.pathSeparator}_SPK_MANIFEST.json',
      );
      if (!await manifestFile.exists()) {
        throw const FormatException(
          'La extracción terminó sin manifiesto de integridad.',
        );
      }

      final rawManifest = jsonDecode(await manifestFile.readAsString());
      if (rawManifest is! Map) {
        throw const FormatException('Manifiesto SPK de salida inválido.');
      }
      final manifest = Map<String, dynamic>.from(rawManifest);
      final rows = ((manifest['files'] as List?) ?? const <Object?>[])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      final rowsByPath = <String, Map<String, dynamic>>{};
      for (final row in rows) {
        final value = row['path']?.toString();
        if (value == null) continue;
        try {
          rowsByPath[canon(value)] = row;
        } catch (_) {
          // La extracción original ya valida la ruta. Una entrada anómala del
          // manifiesto no se usa para aplicar un overlay.
        }
      }

      final overlayManifest = File(
        '$overlayRoot${Platform.pathSeparator}_SPK_OVERLAY.json',
      );
      var applied = 0;
      if (await overlayManifest.exists()) {
        final rawOverlay = jsonDecode(await overlayManifest.readAsString());
        if (rawOverlay is! Map) {
          throw const FormatException('Manifiesto del overlay SPK inválido.');
        }
        final overlay = Map<String, dynamic>.from(rawOverlay);
        if (overlay['indexSha256']?.toString().toLowerCase() !=
            source.index.encryptedIndexSha256.toLowerCase()) {
          throw const FormatException('El overlay pertenece a otro DATA.SPK.');
        }
        final entries = Map<String, dynamic>.from(
          (overlay['entries'] as Map?) ?? const {},
        );
        final list = entries.entries.toList();
        for (var i = 0; i < list.length; i++) {
          final entry = list[i];
          final canonical = canon(entry.key);
          final info = entry.value is Map
              ? Map<String, dynamic>.from(entry.value as Map)
              : <String, dynamic>{};
          final expectedId = info['entryId']?.toString();
          if (expectedId == null || !_spkRecords.containsKey(expectedId)) {
            throw FormatException('Overlay inconsistente para ${entry.key}.');
          }
          final overlayFile = _spkOverlayFile(
            canon((info['file'] ?? canonical).toString()),
          );
          if (!await overlayFile.exists()) {
            throw FormatException(
              'Falta el recurso editado del overlay: ${entry.key}.',
            );
          }
          final edited = await overlayFile.readAsBytes();
          final editedSha = sha256.convert(edited).toString();
          if (editedSha != info['overlaySha256']?.toString()) {
            throw FormatException(
              'El overlay cambió fuera de Studio: ${entry.key}.',
            );
          }

          final row =
              rows
                  .where((r) => r['entryId']?.toString() == expectedId)
                  .firstOrNull ??
              rowsByPath[canonical];
          if (row == null) {
            throw FormatException(
              'La extracción completa no contiene ${entry.key}.',
            );
          }
          final relative = SpkArchiveSource.safeRelative(
            row['path']!.toString(),
          );
          final target = File(
            '${folder.path}${Platform.pathSeparator}$relative',
          );
          if (!await target.exists()) {
            throw FormatException(
              'Falta el destino extraído para ${entry.key}.',
            );
          }

          final temp = File(
            '${target.path}.${DateTime.now().microsecondsSinceEpoch}.partial',
          );
          await temp.writeAsBytes(edited, flush: true);
          if (sha256.convert(await temp.readAsBytes()).toString() !=
              editedSha) {
            await temp.delete();
            throw FormatException(
              'Falló la verificación al aplicar ${entry.key}.',
            );
          }
          await target.delete();
          await temp.rename(target.path);

          row['sha256'] = editedSha;
          row['decodedBytes'] = edited.length;
          row['workspaceOverlay'] = true;
          row['originalSha256'] = info['originalSha256'];
          applied++;
          progress('Aplicando overlay ${entry.key}', i + 1, list.length);
        }
      }

      manifest['files'] = rows;
      manifest['workspaceOverlayApplied'] = applied;
      manifest['workspaceIndexSha256'] = source.index.encryptedIndexSha256;
      manifest['workspaceExportedAt'] = DateTime.now()
          .toUtc()
          .toIso8601String();
      final manifestTemp = File('${manifestFile.path}.partial');
      await manifestTemp.writeAsString(
        const JsonEncoder.withIndent('  ').convert(manifest),
        flush: true,
      );
      await manifestFile.delete();
      await manifestTemp.rename(manifestFile.path);

      return {
        ...extracted,
        'folder': folder.path,
        'overlayFiles': applied,
        'complete': true,
      };
    } catch (_) {
      if (await folder.exists()) {
        await folder.delete(recursive: true);
      }
      rethrow;
    }
  }

  Future<SpkWriterResult> rebuildSpkWorkspace(
    File target, {
    required void Function(String message, int done, int total) progress,
  }) async {
    final source = spk;
    final overlayRoot = spkOverlayRoot;
    if (source == null || overlayRoot == null) {
      throw const FormatException(
        'La biblioteca abierta no es un workspace DATA.SPK.',
      );
    }
    if (!source.fullyValidatedResources) {
      throw const SpkFailure(
        'SPK_WRITER_AUDIT',
        'Antes de construir un nuevo DATA.SPK debe completarse la auditoría '
            'integral.',
      );
    }

    final replacements = <int, Uint8List>{};
    final manifestFile = File(
      '$overlayRoot${Platform.pathSeparator}_SPK_OVERLAY.json',
    );
    if (await manifestFile.exists()) {
      final raw = jsonDecode(await manifestFile.readAsString());
      if (raw is! Map) {
        throw const FormatException('Manifiesto overlay SPK inválido.');
      }
      final manifest = Map<String, dynamic>.from(raw);
      if (manifest['indexSha256']?.toString().toLowerCase() !=
          source.index.encryptedIndexSha256.toLowerCase()) {
        throw const FormatException('El overlay pertenece a otro DATA.SPK.');
      }
      final entries = Map<String, dynamic>.from(
        (manifest['entries'] as Map?) ?? const {},
      );
      final list = entries.entries.toList();
      for (var i = 0; i < list.length; i++) {
        final entry = list[i];
        final canonical = canon(entry.key);
        final savedInfo = entry.value is Map ? entry.value as Map : const {};
        final idHex = savedInfo['entryId']?.toString();
        final record = idHex == null ? null : _spkRecords[idHex];
        if (record == null) {
          throw FormatException(
            'El overlay referencia un recurso ajeno: ${entry.key}.',
          );
        }
        final info = entry.value is Map
            ? Map<String, dynamic>.from(entry.value as Map)
            : <String, dynamic>{};
        if (info['entryId']?.toString() != record.idHex) {
          throw FormatException(
            'Entry ID inconsistente en overlay: ${entry.key}.',
          );
        }
        final editedFile = _spkOverlayFile(
          canon((info['file'] ?? canonical).toString()),
        );
        if (!await editedFile.exists()) {
          throw FormatException(
            'Falta el archivo editado del overlay: ${entry.key}.',
          );
        }
        final edited = await editedFile.readAsBytes();
        final editedSha = sha256.convert(edited).toString();
        if (editedSha != info['overlaySha256']?.toString()) {
          throw FormatException(
            'El archivo overlay cambió fuera de Studio: ${entry.key}.',
          );
        }
        final original = (await source.readEntry(
          record,
          limit: 128 * 1024 * 1024,
        )).bytes;
        final originalSha = sha256.convert(original).toString();
        if (originalSha != info['originalSha256']?.toString()) {
          throw FormatException(
            'El DATA.SPK original ya no coincide con el overlay: '
            '${entry.key}.',
          );
        }
        replacements[record.entryId] = Uint8List.fromList(edited);
        progress('Verificando overlay ${entry.key}', i + 1, list.length);
      }
    }

    return SpkWriter.rebuild(
      source,
      target,
      replacements: replacements,
      control: SpkExtractControl(),
      progress: progress,
    );
  }

  Future<void> writeResource(
    String path,
    Uint8List bytes, {
    bool keepBackup = true,
  }) async {
    final canonical = canon(path);
    final id = files[canonical];
    if (id == null) throw FormatException('Recurso ausente: $path');

    if (spk != null) {
      final current = await read(canonical, limit: 128 * 1024 * 1024);
      await writeSpkOverlay(
        {canonical: bytes},
        expectedHashes: {canonical: sha256.convert(current).toString()},
        keepBackup: keepBackup,
      );
      revision++;
      return;
    }
    if (archive != null) {
      throw const FormatException(
        'El par SAH/SAF está montado en solo lectura. Extrae o usa DATA.SPK con overlay.',
      );
    }
    if (saf) {
      throw const FormatException(
        'La carpeta DATA de Android está montada en solo lectura.',
      );
    }

    final target = File(id);
    if (!await target.exists()) {
      throw FormatException('Recurso local ausente: $path');
    }
    if (keepBackup) {
      final backup = File('$id.shaiya-studio.bak');
      if (!await backup.exists()) {
        await target.copy(backup.path);
      }
    }

    final temp = File('$id.shaiya-studio.tmp');
    await temp.writeAsBytes(bytes, flush: true);
    final expected = sha256.convert(bytes).toString();
    final staged = sha256.convert(await temp.readAsBytes()).toString();
    if (staged != expected) {
      await temp.delete();
      throw FormatException('La verificación previa de escritura falló: $path');
    }

    try {
      if (await target.exists()) await target.delete();
      await temp.rename(target.path);
      final actual = sha256.convert(await target.readAsBytes()).toString();
      if (actual != expected) {
        throw FormatException(
          'La verificación posterior de escritura falló: $path',
        );
      }
      revision++;
    } catch (_) {
      if (await temp.exists()) await temp.delete();
      final backup = File('$id.shaiya-studio.bak');
      if (!await target.exists() && await backup.exists()) {
        await backup.copy(target.path);
      }
      rethrow;
    }
  }

  /// Writes a Studio-owned loose DATA resource, creating it when absent.
  ///
  /// This is intentionally unavailable for SAH/SAF, Android SAF and DATA.SPK:
  /// VehiclePosition.ini is an external contract consumed by the patched
  /// ps0032 client and must remain directly visible under DATA/ExcelXml.
  Future<void> writeOrCreateLooseResource(
    String path,
    Uint8List bytes, {
    bool keepBackup = true,
  }) async {
    final canonical = canon(path);
    if (spk != null) {
      throw const FormatException(
        'Este recurso del puente debe guardarse como archivo suelto en DATA, '
        'no dentro del overlay DATA.SPK.',
      );
    }
    if (archive != null) {
      throw const FormatException(
        'El par SAH/SAF está montado en solo lectura. Abre la carpeta DATA '
        'descomprimida para guardar el recurso del puente.',
      );
    }
    if (saf) {
      throw const FormatException(
        'La carpeta DATA de Android está montada en solo lectura.',
      );
    }

    final existing = files[canonical];
    final relative = canonical.replaceAll('/', Platform.pathSeparator);
    final target = existing == null
        ? File('${Directory(location).path}${Platform.pathSeparator}$relative')
        : File(existing);
    await target.parent.create(recursive: true);

    if (keepBackup && await target.exists()) {
      final backup = File('${target.path}.shaiya-studio.bak');
      if (!await backup.exists()) await target.copy(backup.path);
    }

    final temp = File('${target.path}.shaiya-studio.tmp');
    await temp.writeAsBytes(bytes, flush: true);
    final expected = sha256.convert(bytes).toString();
    final staged = sha256.convert(await temp.readAsBytes()).toString();
    if (staged != expected) {
      await temp.delete();
      throw FormatException(
        'La verificación previa de escritura falló: $canonical',
      );
    }

    try {
      if (await target.exists()) await target.delete();
      await temp.rename(target.path);
      final actual = sha256.convert(await target.readAsBytes()).toString();
      if (actual != expected) {
        throw FormatException(
          'La verificación posterior de escritura falló: $canonical',
        );
      }
      if (existing == null) {
        files[canonical] = target.path;
        _names.putIfAbsent(baseName(canonical), () => []).add(canonical);
      }
      revision++;
    } catch (_) {
      if (await temp.exists()) await temp.delete();
      final backup = File('${target.path}.shaiya-studio.bak');
      if (!await target.exists() && await backup.exists()) {
        await backup.copy(target.path);
      }
      rethrow;
    }
  }

  Future<Uint8List> read(String path, {int limit = 64 * 1024 * 1024}) async {
    final canonical = canon(path);
    final id = files[canonical];
    if (id == null) throw FormatException('Recurso ausente: $path');
    if (spk != null) return (await _spkSnapshot(canonical, limit)).bytes;
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
