import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/spk_archive.dart';
import '../data/spk_source.dart';
import '../data/spk_table_discovery.dart';

String _spkNormalizePath(String value, String separator) {
  final alternate = separator == '\\' ? '/' : '\\';
  var normalized = value.replaceAll(alternate, separator);
  final doubled = '$separator$separator';
  while (normalized.contains(doubled)) {
    normalized = normalized.replaceAll(doubled, separator);
  }
  return normalized;
}

String _spkParentPath(String value, String separator) {
  final normalized = _spkNormalizePath(value, separator);
  final index = normalized.lastIndexOf(separator);
  if (index < 0) return '.';
  if (index == 0) return separator;
  return normalized.substring(0, index);
}

List<String> spkProfileCandidatePaths(
  String spkPath, {
  String? executablePath,
  String? separatorOverride,
}) {
  final separator = separatorOverride == null || separatorOverride.isEmpty
      ? Platform.pathSeparator
      : separatorOverride.substring(0, 1);
  final normalizedSpk = _spkNormalizePath(spkPath, separator);
  final spkDir = _spkParentPath(normalizedSpk, separator);
  final exeDir = _spkParentPath(
    executablePath ?? Platform.resolvedExecutable,
    separator,
  );
  return <String>[
    '$normalizedSpk.profile.json',
    '$spkDir${separator}data.spk.profile.json',
    '$spkDir${separator}spk-crypto-profile.json',
    '$exeDir${separator}profiles${separator}data.spk.profile.json',
    '$exeDir${separator}profiles${separator}spk-crypto-profile.json',
    '$exeDir${separator}data.spk.profile.json',
    '$exeDir${separator}spk-crypto-profile.json',
  ];
}

List<String> spkNameMapCandidatePaths(
  String spkPath,
  String indexSha256, {
  String? executablePath,
  String? separatorOverride,
}) {
  final separator = separatorOverride == null || separatorOverride.isEmpty
      ? Platform.pathSeparator
      : separatorOverride.substring(0, 1);
  final normalizedSpk = _spkNormalizePath(spkPath, separator);
  final spkDir = _spkParentPath(normalizedSpk, separator);
  final exeDir = _spkParentPath(
    executablePath ?? Platform.resolvedExecutable,
    separator,
  );
  final shortHash = indexSha256.length >= 8
      ? indexSha256.substring(0, 8)
      : indexSha256;
  return <String>[
    '$normalizedSpk.names.json',
    '$spkDir${separator}spk-name-map.json',
    '$spkDir${separator}spk-name-map-$shortHash.json',
    '$exeDir${separator}profiles${separator}spk-name-map.json',
    '$exeDir${separator}profiles${separator}spk-name-map-$shortHash.json',
    '$exeDir${separator}spk-name-map.json',
  ];
}


List<String> spkResourceProfileCandidatePaths(
  String spkPath,
  String indexSha256, {
  String? executablePath,
  String? separatorOverride,
}) {
  final separator = separatorOverride == null || separatorOverride.isEmpty
      ? Platform.pathSeparator
      : separatorOverride.substring(0, 1);
  final normalizedSpk = _spkNormalizePath(spkPath, separator);
  final spkDir = _spkParentPath(normalizedSpk, separator);
  final exeDir = _spkParentPath(
    executablePath ?? Platform.resolvedExecutable,
    separator,
  );
  final shortHash = indexSha256.length >= 8
      ? indexSha256.substring(0, 8)
      : indexSha256;
  return <String>[
    '$normalizedSpk.resources.json',
    '$spkDir${separator}data.spk.resources.json',
    '$spkDir${separator}derived-resource-profile.json',
    '$spkDir${separator}spk-resource-profile.json',
    '$exeDir${separator}profiles${separator}spk-resource-profile-$shortHash.json',
    '$exeDir${separator}profiles${separator}spk-resource-profile.json',
    '$exeDir${separator}profiles${separator}derived-resource-profile.json',
  ];
}

String spkResourceProbeExecutablePath({
  String? executablePath,
  String? separatorOverride,
}) {
  final separator = separatorOverride == null || separatorOverride.isEmpty
      ? Platform.pathSeparator
      : separatorOverride.substring(0, 1);
  final exeDir = _spkParentPath(
    executablePath ?? Platform.resolvedExecutable,
    separator,
  );
  return '$exeDir${separator}Extras${separator}SPK$separator'
      'Shaiya_SPK_ResourceProbe.exe';
}

SpkCryptoProfile mergeSpkResourceProfile(
  SpkArchiveSource source,
  Map<String, dynamic> data,
) {
  if (data['resourceSecretHex'] is String) {
    return source.profile.mergeResourceProbe(data);
  }

  final keyInfo = data['keyInfo'];
  if (keyInfo is Map && keyInfo['secretHex'] is String) {
    final resourceSecret = spkResourceSecret(keyInfo['secretHex']);
    var chunkRule = source.profile.chunkNonceRule;
    final target = data['target'];
    final auth = data['authenticatedCipherInfo'];
    if (target is Map &&
        target['kind'] == 'chunk' &&
        auth is Map &&
        auth['nonceHex'] is String) {
      final parentOrdinal = int.tryParse(
        target['parentOrdinal']?.toString() ?? '',
      );
      final auxiliaryOrdinal = int.tryParse(
        target['ordinal']?.toString() ?? '',
      );
      if (parentOrdinal != null && auxiliaryOrdinal != null) {
        chunkRule = source.identifyChunkNonceRule(
          parentOrdinal: parentOrdinal,
          auxiliaryOrdinal: auxiliaryOrdinal,
          observedNonce: spkHexBytes(
            auth['nonceHex'].toString(),
            expectedBytes: 12,
          ),
        );
      }
    }
    final authDataHex = auth is Map && auth['authDataHex'] is String
        ? auth['authDataHex'].toString()
        : null;
    return SpkCryptoProfile(
      profileId: '${source.profile.profileId}-resources',
      indexSha256: source.profile.indexSha256,
      indexSecret: source.profile.indexSecret,
      resourceSecret: resourceSecret,
      resourceAad: spkResourceAad(authDataHex),
      resourceKeyIsIndexKey: false,
      chunkNonceRule: chunkRule,
    );
  }

  return SpkCryptoProfile.fromJson(data);
}

Future<SpkArchiveSource> loadAutomaticSpkResourceProfile(
  SpkArchiveSource source,
  String spkPath,
) async {
  for (final candidate in spkResourceProfileCandidatePaths(
    spkPath,
    source.index.encryptedIndexSha256,
  )) {
    final file = File(candidate);
    if (!await file.exists()) continue;
    try {
      final value = jsonDecode(await file.readAsString());
      if (value is! Map) continue;
      final data = Map<String, dynamic>.from(value);
      final declared =
          (data['indexSha256'] ?? data['spkIndexSha256'])?.toString().toLowerCase();
      if (declared != null &&
          declared.isNotEmpty &&
          declared != source.index.encryptedIndexSha256.toLowerCase()) {
        continue;
      }
      final profile = mergeSpkResourceProfile(source, data);
      if (profile.effectiveResourceSecret == null) continue;
      final candidate = await SpkArchiveSource.open(
        spkPath,
        profile,
        names: source.names,
      );
      await candidate.validateSimpleResourceProfile();
      return candidate;
    } catch (_) {
      // Un perfil opcional incompatible no debe impedir abrir el índice.
    }
  }
  return source;
}

Future<SpkArchiveSource> deriveAutomaticFragmentProfile(
  SpkArchiveSource source,
  String spkPath, {
  bool persist = true,
}) async {
  if (!source.canReadSimpleResources ||
      source.canReadFragmentedResources ||
      source.index.fragmentedResources.isEmpty) {
    return source;
  }
  final rule = await source.deriveChunkNonceRuleOffline();
  if (rule == 'unsupported') return source;

  final profile = source.profile.withChunkNonceRule(rule);
  final next = await SpkArchiveSource.open(
    spkPath,
    profile,
    names: source.names,
  );
  await next.validateSimpleResourceProfile();
  await next.validateFragmentedResourceProfile();
  if (persist) {
    final sidecar = File('$spkPath.resources.json');
    await sidecar.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'schema': 4,
        'profileId': profile.profileId,
        'indexSha256': profile.indexSha256,
        'readyForSimple': true,
        'readyForFragmented': true,
        'readyForAll': true,
        'resourceSecretHex': spkHex(profile.effectiveResourceSecret!),
        'resourceSecretBytes': profile.effectiveResourceSecret!.length,
        'algorithm': 'AES-GCM',
        'aadRule': profile.resourceAad.isEmpty ? 'none' : 'constant',
        if (profile.resourceAad.isNotEmpty)
          'aadHex': spkHex(profile.resourceAad),
        'chunkNonceRule': rule,
        'fragmentRuleEvidence': 'offline-aes-gcm-authentication',
      }),
      flush: true,
    );
  }
  return next;
}

Future<void> loadAutomaticSpkNameMap(
  SpkArchiveSource source,
  String spkPath,
) async {
  for (final candidate in spkNameMapCandidatePaths(
    spkPath,
    source.index.encryptedIndexSha256,
  )) {
    final file = File(candidate);
    if (!await file.exists()) continue;
    try {
      final value = jsonDecode(await file.readAsString());
      if (value is! Map) continue;
      final map = Map<String, dynamic>.from(value);
      final declared = map['spkIndexSha256']?.toString().toLowerCase();
      if (declared != null &&
          declared.isNotEmpty &&
          declared != source.index.encryptedIndexSha256.toLowerCase()) {
        continue;
      }
      source.names = SpkNameMap.fromJson(map);
      source.names.removeAmbiguousHints();
      return;
    } catch (_) {
      // Un mapa opcional dañado no impide abrir un SPK válido.
    }
  }
}

Future<bool> loadAutomaticSpkFullAudit(
  SpkArchiveSource source,
  String spkPath,
) async {
  final file = File('$spkPath.audit.json');
  if (!await file.exists()) return false;
  try {
    final raw = jsonDecode(await file.readAsString());
    if (raw is! Map) return false;
    return source.restoreFullResourceValidation(
      Map<String, dynamic>.from(raw),
    );
  } catch (_) {
    return false;
  }
}


class SpkArchiveBrowserPage extends StatefulWidget {
  final SpkArchiveSource source;
  final Future<void> Function(SpkArchiveSource source)? onMount;
  const SpkArchiveBrowserPage({
    super.key,
    required this.source,
    this.onMount,
  });

  static Future<void> pickAndOpen(
    BuildContext context, {
    Future<void> Function(SpkArchiveSource source)? onMount,
  }) async {
    final picked = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Archivo DATA.SPK', extensions: ['spk']),
      ],
      confirmButtonText: 'Abrir DATA.SPK',
    );
    if (picked == null || !context.mounted) return;

    final profile = await _chooseProfile(context, picked.path);
    if (profile == null || !context.mounted) return;

    final progress = ValueNotifier<String>('Abriendo DATA.SPK…');
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Montando DATA.SPK'),
        content: SizedBox(
          width: 430,
          child: ValueListenableBuilder<String>(
            valueListenable: progress,
            builder: (_, value, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const LinearProgressIndicator(),
                const SizedBox(height: 14),
                Text(value),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      var source = await SpkArchiveSource.open(
        picked.path,
        profile,
        progress: (message, done, total) => progress.value = message,
      );
      if (source.profile.effectiveResourceSecret != null) {
        progress.value =
            'Autenticando perfil de payloads contra muestras reales…';
        await source.validateSimpleResourceProfile();
      } else {
        progress.value =
            'Probando de forma autenticada si el índice comparte clave con payloads…';
        source = await source.tryIndexKeyAsResourceProfile() ?? source;
      }
      progress.value = 'Buscando perfil validado de recursos…';
      source = await loadAutomaticSpkResourceProfile(source, picked.path);
      progress.value = 'Validando fragmentación AES-GCM offline…';
      source = await deriveAutomaticFragmentProfile(source, picked.path);
      progress.value = 'Resolviendo nombres y rutas conocidas…';
      await loadAutomaticSpkNameMap(source, picked.path);
      if (source.canExtractAll) {
        progress.value = 'Restaurando evidencia de auditoría integral…';
        await loadAutomaticSpkFullAudit(source, picked.path);
      }
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) =>
              SpkArchiveBrowserPage(source: source, onMount: onMount),
        ),
      );
    } catch (error) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString()),
            duration: const Duration(seconds: 7),
          ),
        );
      }
    } finally {
      progress.dispose();
    }
  }

  static Future<SpkCryptoProfile?> _chooseProfile(
    BuildContext context,
    String spkPath,
  ) async {
    final candidates = spkProfileCandidatePaths(
      spkPath,
    ).map(File.new).toList(growable: false);
    for (final file in candidates) {
      if (!await file.exists()) continue;
      try {
        final value = jsonDecode(await file.readAsString());
        if (value is Map) {
          return SpkCryptoProfile.fromJson(Map<String, dynamic>.from(value));
        }
      } catch (_) {}
    }
    if (!context.mounted) return null;

    final action = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Perfil SPK local'),
        content: const SizedBox(
          width: 470,
          child: Text(
            'No se encontró un perfil compatible junto a DATA.SPK ni junto a '
            'Shaiya Studio. Selecciona el perfil JSON validado para este '
            'archivo. Si lo guardas como data.spk.profile.json o dentro de '
            'la carpeta profiles del programa, se detectará automáticamente.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(c, true),
            icon: const Icon(Icons.key_outlined),
            label: const Text('Seleccionar perfil'),
          ),
        ],
      ),
    );
    if (action != true) return null;

    final profileFile = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Perfil SPK', extensions: ['json']),
      ],
      confirmButtonText: 'Usar perfil',
    );
    if (profileFile == null) return null;
    final value = jsonDecode(await File(profileFile.path).readAsString());
    if (value is! Map) {
      throw const FormatException('Perfil SPK JSON inválido.');
    }
    return SpkCryptoProfile.fromJson(Map<String, dynamic>.from(value));
  }

  @override
  State<SpkArchiveBrowserPage> createState() => _SpkArchiveBrowserState();
}

class _SpkArchiveBrowserState extends State<SpkArchiveBrowserPage> {
  final searchController = TextEditingController();
  final extractControl = SpkExtractControl();

  String currentFolder = '';
  String search = '';
  bool recursiveSearch = false;
  SpkRecord? selected;
  bool busy = false;
  String operation = '';
  int operationDone = 0;
  int operationTotal = 0;

  SpkArchiveSource get source => widget.source;

  bool get hasConfirmedCoreTables {
    final paths = source.names.paths.values.map((p) => p.toLowerCase());
    return paths.any(
      (p) =>
          p.endsWith('/dbitemdata.sdata') ||
          p.endsWith('/dbmonsterdata.sdata') ||
          p.endsWith('/dbskilldata.sdata') ||
          p == 'item/item.sdata' ||
          p == 'monster/monster.sdata' ||
          p == 'skill/skill.sdata',
    );
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  String bytesLabel(int value) {
    if (value < 1024) return '$value B';
    if (value < 1024 * 1024) {
      return '${(value / 1024).toStringAsFixed(1)} KiB';
    }
    if (value < 1024 * 1024 * 1024) {
      return '${(value / (1024 * 1024)).toStringAsFixed(1)} MiB';
    }
    return '${(value / (1024 * 1024 * 1024)).toStringAsFixed(2)} GiB';
  }

  List<String> childFolders() {
    final prefix = currentFolder.isEmpty ? '' : '$currentFolder/';
    final out = <String>{};
    for (final path in source.folders()) {
      if (path.isEmpty || path == currentFolder || !path.startsWith(prefix)) {
        continue;
      }
      final rest = path.substring(prefix.length);
      final child = rest.split('/').first;
      if (child.isNotEmpty) out.add(prefix + child);
    }
    return out.toList()..sort();
  }

  List<SpkRecord> visibleEntries() => source.entriesInFolder(
    currentFolder,
    search: search,
    recursive: recursiveSearch || search.isNotEmpty,
  );

  String fileName(SpkRecord record) {
    final path = source.technicalPath(record).replaceAll('\\', '/');
    return path.split('/').last;
  }

  String _friendlyError(Object error) {
    if (error is SpkFailure) {
      final output = error.report['output']?.toString();
      final consoleLog = error.report['consoleLog']?.toString();
      final failure = error.report['failure']?.toString();
      final details = <String>[
        if (failure != null && failure.isNotEmpty) failure,
        if (consoleLog != null && consoleLog.isNotEmpty)
          'Log: $consoleLog'
        else if (output != null && output.isNotEmpty)
          'Diagnóstico: $output',
      ];
      return '${error.code}: ${error.message}'
          '${details.isEmpty ? '' : ' · ${details.join(' · ')}'}';
    }
    if (error is FormatException) {
      return error.message;
    }
    return error.toString();
  }

  Future<void> runAction(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_friendlyError(error)),
            duration: const Duration(seconds: 9),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          operation = '';
          operationDone = 0;
          operationTotal = 0;
        });
      }
    }
  }

  Future<void> exportNameMap() => runAction(() async {
    final location = await getSaveLocation(
      suggestedName: 'spk-name-map.json',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Mapa de nombres SPK', extensions: ['json']),
      ],
    );
    if (location == null) return;
    final body = <String, Object?>{
      ...source.names.toJson(),
      'spkIndexSha256': source.index.encryptedIndexSha256,
    };
    await File(location.path).writeAsString(
      const JsonEncoder.withIndent('  ').convert(body),
      flush: true,
    );
  });

  Future<void> extractCurrentFolder() => runAction(() async {
    if (currentFolder.isEmpty) {
      throw const FormatException(
        'Selecciona una carpeta concreta o usa Extraer todo.',
      );
    }
    final folder = await getDirectoryPath(
      confirmButtonText: 'Extraer carpeta aquí',
    );
    if (folder == null) return;
    final list = source
        .entriesInFolder(currentFolder, recursive: true)
        .where(source.canReadRecord)
        .toList();
    if (list.isEmpty) {
      throw const SpkFailure(
        'SPK_FOLDER_LOCKED',
        'La carpeta no contiene recursos legibles todavía. Ejecuta AutoPerfil '
            'SPK antes de extraer contenido.',
      );
    }
    final result = await source.extract(
      Directory(folder),
      selection: list,
      requireComplete: false,
      control: extractControl,
      progress: (message, done, total) {
        if (!mounted) return;
        setState(() {
          operation = message;
          operationDone = done;
          operationTotal = total;
        });
      },
    );
    if (mounted) {
      final extractedFolder = result['folder'];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Carpeta extraída: $extractedFolder')),
      );
    }
  });
  Future<void> importNameMap() => runAction(() async {
    final picked = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Mapa de nombres SPK', extensions: ['json']),
      ],
      confirmButtonText: 'Importar mapa',
    );
    if (picked == null) return;
    await source.importNameMap(await File(picked.path).readAsString());
    if (mounted) {
      setState(() {
        currentFolder = '';
        selected = null;
      });
    }
  });

  Future<void> resolveNamesFromReferenceData() => runAction(() async {
    final folder = await getDirectoryPath(
      confirmButtonText: 'Usar DATA como referencia',
    );
    if (folder == null || !mounted) return;

    final verify = source.canReadSimpleResources
        ? await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('Reconstruir nombres SPK'),
              content: const SizedBox(
                width: 500,
                child: Text(
                  'Puedes inferir rápidamente rutas cuando el tamaño decodificado '
                  'es único, o confirmar rutas leyendo el recurso SPK y comparando '
                  'SHA-256 byte por byte contra la DATA de referencia.\n\n'
                  'La verificación es más lenta, pero produce nombres confirmados.',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('Inferir por tamaño'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text('Confirmar por SHA-256'),
                ),
              ],
            ),
          )
        : false;
    if (!mounted) return;

    final result = verify == true
        ? await source.verifyNamesFromDirectory(
            Directory(folder),
            control: extractControl,
            progress: (message, done, total) {
              if (!mounted) return;
              setState(() {
                operation = message;
                operationDone = done;
                operationTotal = total;
              });
            },
          )
        : await source.inferNamesFromDirectory(
            Directory(folder),
            progress: (message, done, total) {
              if (!mounted) return;
              setState(() {
                operation = message;
                operationDone = done;
                operationTotal = total;
              });
            },
          );
    if (!mounted) return;
    setState(() {
      currentFolder = '';
      selected = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          verify == true
              ? '${result['confirmed']} rutas confirmadas por SHA-256.'
              : '${result['strongInferred']} rutas con evidencia Zstandard + '
                    '${result['sizeOnlyInferred']} por tamaño único. '
                    'Se muestran como inferidas hasta confirmarlas.',
        ),
        duration: const Duration(seconds: 7),
      ),
    );
  });

  Future<Map<String, Object?>> _discoverCoreTables([
    SpkArchiveSource? target,
  ]) async {
    final archive = target ?? source;
    if (!archive.canExtractAll) {
      throw const SpkFailure(
        'SPK_TABLE_DISCOVERY_PROFILE',
        'Primero valida el perfil completo de payloads con AutoPerfil SPK.',
      );
    }
    if (!archive.fullyValidatedResources) {
      operation =
          'Auditando todos los payloads antes del descubrimiento estructural…';
      if (mounted) setState(() {});
      await _auditAllResources(archive);
    }
    final result = await SpkCoreTableDiscovery.discover(
      archive,
      control: extractControl,
      progress: (message, done, total) {
        if (!mounted) return;
        setState(() {
          operation = message;
          operationDone = done;
          operationTotal = total;
        });
      },
    );
    final persistent = File('${archive.file.path}.names.json');
    await persistent.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        ...archive.names.toJson(),
        'spkIndexSha256': archive.index.encryptedIndexSha256,
        'discovery': result,
      }),
      flush: true,
    );
    if (mounted) {
      setState(() {
        currentFolder = '';
        selected = null;
      });
    }
    return result;
  }

  Future<void> discoverCoreTables() => runAction(() async {
    final result = await _discoverCoreTables();
    if (!mounted) return;
    final tables = Map<String, dynamic>.from(
      (result['confirmedTables'] as Map?) ?? const {},
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Descubrimiento estructural terminado: ${tables.length} tablas '
          'confirmadas y mapa persistido.',
        ),
        duration: const Duration(seconds: 8),
      ),
    );
  });

  Future<Map<String, Object?>> _auditAllResources(
    SpkArchiveSource archive,
  ) async {
    final result = await archive.validateAllResources(
      control: extractControl,
      progress: (message, done, total) {
        if (!mounted) return;
        setState(() {
          operation = message;
          operationDone = done;
          operationTotal = total;
        });
      },
    );
    final evidence = File('${archive.file.path}.audit.json');
    await evidence.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'schema': 1,
        'source': archive.file.path,
        'indexSha256': archive.index.encryptedIndexSha256,
        'profileId': archive.profile.profileId,
        'resourceKeySha256': archive.profile.effectiveResourceSecret == null
            ? null
            : sha256.convert(archive.profile.effectiveResourceSecret!).toString(),
        'chunkNonceRule': archive.profile.chunkNonceRule,
        'validation': result,
        'resourceFormats': archive.validatedFormatsJson,
        'diagnostics': archive.diagnostics(),
      }),
      flush: true,
    );
    return result;
  }

  Future<void> auditAllResources() => runAction(() async {
    if (!source.canExtractAll) {
      throw const SpkFailure(
        'SPK_FULL_VALIDATION_PROFILE',
        'Primero valida simples y fragmentados con AutoPerfil SPK.',
      );
    }
    operation = 'Auditando todos los payloads del DATA.SPK…';
    if (mounted) setState(() {});
    final result = await _auditAllResources(source);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Auditoría total OK: ${result['validatedResources']} recursos · '
          '${result['decodedBytes']} bytes decodificados · 0 fallos.',
        ),
        duration: const Duration(seconds: 10),
      ),
    );
  });

  Future<void> mountInStudio() => runAction(() async {
    final callback = widget.onMount;
    if (callback == null) return;
    if (!source.canExtractAll) {
      throw const SpkFailure(
        'SPK_STUDIO_MOUNT_PROFILE',
        'Para usar DATA.SPK en el editor y la herramienta 3D deben estar '
            'autenticados los recursos simples y fragmentados.',
      );
    }
    if (!source.fullyValidatedResources) {
      operation = 'Auditando todos los payloads antes de montar Studio…';
      if (mounted) setState(() {});
      await _auditAllResources(source);
    }
    if (!hasConfirmedCoreTables) {
      operation = 'Identificando tablas editables antes de montar Studio…';
      if (mounted) setState(() {});
      await _discoverCoreTables();
    }
    operation = 'Montando DATA.SPK como biblioteca de Studio…';
    if (mounted) setState(() {});
    await callback(source);
    if (mounted) Navigator.of(context).pop();
  });

  Future<void> captureResourceProfile() => runAction(() async {
    if (!Platform.isWindows) {
      throw const SpkFailure(
        'SPK_PROBE_WINDOWS_ONLY',
        'La captura automática del perfil de payloads requiere Windows. '
            'El cliente Shaiya puede ser x86 o x64.',
      );
    }
    final helper = File(spkResourceProbeExecutablePath());
    if (!await helper.exists()) {
      throw SpkFailure(
        'SPK_PROBE_MISSING',
        'Esta compilación no incluye Shaiya_SPK_ResourceProbe.exe.',
        {'expected': helper.path},
      );
    }

    var game = File(p.join(source.file.parent.path, 'game.exe'));
    if (!await game.exists()) {
      final picked = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Cliente Shaiya', extensions: ['exe']),
        ],
        confirmButtonText: 'Usar game.exe',
      );
      if (picked == null) return;
      game = File(picked.path);
    }
    if (!await game.exists()) {
      throw const FileSystemException('No se encontró game.exe.');
    }

    if (source.profile.effectiveResourceSecret == null) {
      operation =
          'Probando primero la clave del índice contra payloads reales…';
      if (mounted) setState(() {});
      var offline = await source.tryIndexKeyAsResourceProfile();
      if (offline != null) {
        offline = await deriveAutomaticFragmentProfile(
          offline,
          source.file.path,
        );
        if (offline.canExtractAll) {
          await loadAutomaticSpkNameMap(offline, source.file.path);
          operation =
              'La clave compartida autenticó el SPK. Auditando todos los recursos…';
          if (mounted) setState(() {});
          final audit = await _auditAllResources(offline);
          operation = 'Identificando tablas y rutas estructurales…';
          if (mounted) setState(() {});
          final discovery = await _discoverCoreTables(offline);
          if (!mounted) return;
          final tables = Map<String, dynamic>.from(
            (discovery['confirmedTables'] as Map?) ?? const {},
          ).length;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'AutoPerfil offline completado: '
                '${audit['validatedResources']} recursos auditados, '
                '0 fallos y $tables tablas núcleo confirmadas.',
              ),
              duration: const Duration(seconds: 10),
            ),
          );
          await Navigator.of(context).pushReplacement<void, void>(
            MaterialPageRoute(
              builder: (_) => SpkArchiveBrowserPage(
                source: offline!,
                onMount: widget.onMount,
              ),
            ),
          );
          return;
        }
      }
    }

    final siblingSpk = File(p.join(game.parent.path, 'data.spk'));
    if (!await siblingSpk.exists()) {
      throw const SpkFailure(
        'SPK_PROBE_PAIR',
        'game.exe y data.spk deben pertenecer a la misma instalación.',
      );
    }

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Capturar perfil de recursos SPK'),
        content: const SizedBox(
          width: 520,
          child: Text(
            'Shaiya Studio abrirá una copia de game.exe e instrumentará solo '
            'ese proceso para observar las llamadas AES-GCM que corresponden '
            'exactamente a recursos del DATA.SPK ya validado.\n\n'
            'Desconecta Internet antes de continuar. No inicies sesión ni '
            'escribas credenciales. El aviso de servidor sin conexión es '
            'esperado. DATA.SPK y game.exe no se modifican.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(c, true),
            icon: const Icon(Icons.security_outlined),
            label: const Text('Capturar offline'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final support = await getApplicationSupportDirectory();
    final output = Directory(
      p.join(
        support.path,
        'spk_probe',
        DateTime.now().millisecondsSinceEpoch.toString(),
      ),
    );
    operation = 'Preparando ResourceProbe V10…';
    if (mounted) setState(() {});

    final process = await Process.start(
      helper.path,
      [
        '--client',
        game.path,
        '--out',
        output.path,
        '--seconds',
        '150',
        '--noninteractive',
      ],
      workingDirectory: game.parent.path,
      runInShell: false,
      environment: {
        ...Platform.environment,
        'PYTHONUTF8': '1',
        'PYTHONIOENCODING': 'utf-8',
      },
    );
    final recent = <String>[];
    final console = <String>[];
    void reportLine(String line) {
      final clean = line.trim();
      if (clean.isEmpty) return;
      console.add(clean);
      if (console.length > 5000) console.removeAt(0);
      recent.add(clean);
      if (recent.length > 12) recent.removeAt(0);
      if (mounted) {
        setState(() => operation = clean);
      }
    }

    final stdoutDone = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .forEach(reportLine);
    final stderrDone = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .forEach(reportLine);
    final exitCode = await process.exitCode;
    await Future.wait([stdoutDone, stderrDone]);
    if (!await output.exists()) {
      await output.create(recursive: true);
    }
    await File(p.join(output.path, 'probe-console.log')).writeAsString(
      [
        'Shaiya Studio ResourceProbe V10',
        'exitCode=$exitCode',
        'game=${game.path}',
        'data=${source.file.path}',
        '',
        ...console,
        '',
      ].join('\n'),
      flush: true,
    );

    final profileFile = File(p.join(output.path, 'derived-resource-profile.json'));
    if (!await profileFile.exists()) {
      throw SpkFailure(
        'SPK_PROBE_NO_PROFILE',
        'El helper terminó sin producir un perfil criptográfico validado.',
        {
          'exitCode': exitCode,
          'output': output.path,
          'logTail': recent,
          'consoleLog': p.join(output.path, 'probe-console.log'),
        },
      );
    }
    final raw = jsonDecode(await profileFile.readAsString());
    if (raw is! Map) {
      throw const FormatException('ResourceProbe produjo un JSON inválido.');
    }
    final data = Map<String, dynamic>.from(raw);
    if (data['readyForSimple'] != true) {
      throw SpkFailure(
        'SPK_PROBE_NO_VALID_KEY',
        'ResourceProbe terminó, pero todavía no obtuvo una clave AES-GCM '
            'que autentique recursos simples reales.',
        {
          'output': output.path,
          if (data['failure'] != null) 'failure': data['failure'],
          'logTail': recent,
          'consoleLog': p.join(output.path, 'probe-console.log'),
        },
      );
    }
    final declared = data['indexSha256']?.toString().toLowerCase();
    if (declared != source.index.encryptedIndexSha256.toLowerCase()) {
      throw const SpkFailure(
        'SPK_PROBE_HASH',
        'El perfil capturado no corresponde al SPK abierto.',
      );
    }
    final nextProfile = mergeSpkResourceProfile(source, data);
    var next = await SpkArchiveSource.open(
      source.file.path,
      nextProfile,
      names: source.names,
    );
    operation = 'Revalidando payloads simples contra DATA.SPK…';
    if (mounted) setState(() {});
    final simpleValidation = await next.validateSimpleResourceProfile();

    operation = 'Validando nonces y reconstrucción de fragmentos…';
    if (mounted) setState(() {});
    next = await deriveAutomaticFragmentProfile(next, source.file.path);

    if (!next.canExtractAll) {
      final persistent = File('${source.file.path}.resources.json');
      await persistent.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          ...data,
          'studioValidation': simpleValidation,
        }),
        flush: true,
      );
    }
    await loadAutomaticSpkNameMap(next, source.file.path);

    Map<String, Object?>? fullAudit;
    Map<String, Object?>? discovery;
    if (next.canExtractAll) {
      operation = 'Auditoría total: autenticando y decodificando cada recurso…';
      if (mounted) setState(() {});
      fullAudit = await _auditAllResources(next);

      operation = 'Identificando tablas y validando rutas estructurales…';
      if (mounted) setState(() {});
      discovery = await _discoverCoreTables(next);
    }

    if (!mounted) return;
    final full = next.canExtractAll;
    final audited = next.fullyValidatedResources;
    final confirmedTables = Map<String, dynamic>.from(
      (discovery?['confirmedTables'] as Map?) ?? const {},
    ).length;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          audited
              ? 'DATA.SPK auditado completo: '
                    '${fullAudit?['validatedResources']} recursos decodificados, '
                    '0 fallos y $confirmedTables tablas núcleo confirmadas.'
              : full
              ? 'Perfil validado: simples + fragmentados. La auditoría total quedó pendiente.'
              : 'Perfil simple validado. Los fragmentados siguen bloqueados hasta validarlos.',
        ),
        duration: const Duration(seconds: 10),
      ),
    );
    await Navigator.of(context).pushReplacement<void, void>(
      MaterialPageRoute(
        builder: (_) =>
            SpkArchiveBrowserPage(source: next, onMount: widget.onMount),
      ),
    );
  });

  Future<void> loadResourceProfile() => runAction(() async {
    final picked = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Perfil criptográfico SPK', extensions: ['json']),
      ],
      confirmButtonText: 'Aplicar perfil de recursos',
    );
    if (picked == null) return;
    final raw = jsonDecode(await File(picked.path).readAsString());
    if (raw is! Map) {
      throw const FormatException('Perfil SPK JSON inválido.');
    }
    final data = Map<String, dynamic>.from(raw);
    final nextProfile = mergeSpkResourceProfile(source, data);

    var next = await SpkArchiveSource.open(
      source.file.path,
      nextProfile,
      names: source.names,
    );
    final simpleValidation = await next.validateSimpleResourceProfile();
    next = await deriveAutomaticFragmentProfile(next, source.file.path);
    await loadAutomaticSpkNameMap(next, source.file.path);
    if (next.canExtractAll) {
      operation = 'Auditando todos los payloads con el perfil importado…';
      if (mounted) setState(() {});
      await _auditAllResources(next);
      operation = 'Descubriendo tablas y rutas estructurales…';
      if (mounted) setState(() {});
      await _discoverCoreTables(next);
    }

    final finalProfile = next.profile;
    final persistent = File('${source.file.path}.profile.json');
    await persistent.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'profileId': finalProfile.profileId,
        'indexSha256': finalProfile.indexSha256,
        'index': {
          'algorithm': 'AES-GCM',
          'secretHex': spkHex(finalProfile.indexSecret),
        },
        'resources': {
          'algorithm': 'AES-GCM',
          if (finalProfile.effectiveResourceSecret != null)
            'secretHex': spkHex(finalProfile.effectiveResourceSecret!),
          if (finalProfile.resourceAad.isNotEmpty)
            'aadHex': spkHex(finalProfile.resourceAad),
          'useIndexKey': finalProfile.resourceKeyIsIndexKey,
          'chunkNonceRule': finalProfile.chunkNonceRule,
          'validation': simpleValidation,
        },
      }),
      flush: true,
    );

    if (!mounted) return;
    await Navigator.of(context).pushReplacement<void, void>(
      MaterialPageRoute(
        builder: (_) =>
            SpkArchiveBrowserPage(source: next, onMount: widget.onMount),
      ),
    );
  });

  Future<void> exportInventory() => runAction(() async {
    final location = await getSaveLocation(
      suggestedName: 'spk-inventario.json',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Inventario JSON', extensions: ['json']),
      ],
    );
    if (location == null) return;
    final footer = await SpkArchiveSource.readRange(
      source.file,
      source.fileBytes - spkFooterBytes,
      spkFooterBytes,
      source.fileBytes,
    );
    final headerRaw = await SpkArchiveSource.readRange(
      source.file,
      0,
      spkHeaderBytes,
      source.fileBytes,
    );
    final body = const JsonEncoder.withIndent('  ').convert({
      'schema': 2,
      'source': source.file.path,
      'containerEvidence': {
        'headerBytes': spkHeaderBytes,
        'headerSha256': sha256.convert(headerRaw).toString(),
        'headerHex': spkHex(headerRaw),
        'footerBytes': spkFooterBytes,
        'footerSha256': sha256.convert(footer).toString(),
        'footerHex': spkHex(footer),
      },
      'diagnostics': source.diagnostics(),
      'nameMap': source.names.toJson(),
      'records': source.index.records
          .map(
            (record) => {
              ...record.toJson(),
              'path': source.technicalPath(record),
            },
          )
          .toList(),
    });
    await File(location.path).writeAsString(body, flush: true);
  });

  Future<void> extractSelected() => runAction(() async {
    final record = selected;
    if (record == null) return;
    if (!source.canReadRecord(record)) {
      throw const SpkFailure(
        'SPK_CONTENT_LOCKED',
        'El recurso sigue cifrado. Ejecuta AutoPerfil SPK antes de extraerlo.',
      );
    }
    final folder = await getDirectoryPath(
      confirmButtonText: 'Extraer recurso aquí',
    );
    if (folder == null) return;
    final result = await source.extract(
      Directory(folder),
      selection: [record],
      requireComplete: false,
      control: extractControl,
      progress: (message, done, total) {
        if (!mounted) return;
        setState(() {
          operation = message;
          operationDone = done;
          operationTotal = total;
        });
      },
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Recurso extraído en ${result['folder']}')),
      );
    }
  });

  Future<void> extractReadable() => runAction(() async {
    if (!source.canReadSimpleResources) {
      throw const SpkFailure(
        'SPK_RESOURCE_PROFILE_REQUIRED',
        'Aún no existe una clave de recursos validada.',
      );
    }
    final folder = await getDirectoryPath(
      confirmButtonText: 'Extraer recursos legibles aquí',
    );
    if (folder == null) return;
    final readable = <SpkRecord>[
      ...source.index.simpleResources,
      if (source.canReadFragmentedResources)
        ...source.index.fragmentedResources,
    ];
    final result = await source.extract(
      Directory(folder),
      selection: readable,
      requireComplete: false,
      continueOnError: true,
      control: extractControl,
      progress: (message, done, total) {
        if (!mounted) return;
        setState(() {
          operation = message;
          operationDone = done;
          operationTotal = total;
        });
      },
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${result['files']} recursos legibles extraídos · '
            '${result['failures']} omitidos · ${result['folder']}',
          ),
          duration: const Duration(seconds: 9),
        ),
      );
    }
  });

  Future<void> extractAll() => runAction(() async {
    final folder = await getDirectoryPath(
      confirmButtonText: 'Extraer DATA.SPK aquí',
    );
    if (folder == null) return;
    final result = await source.extract(
      Directory(folder),
      control: extractControl,
      progress: (message, done, total) {
        if (!mounted) return;
        setState(() {
          operation = message;
          operationDone = done;
          operationTotal = total;
        });
      },
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${result['files']} recursos extraídos en ${result['folder']}',
          ),
          duration: const Duration(seconds: 8),
        ),      );
    }
  });

  Future<void> inspectResource(SpkRecord record) => runAction(() async {
    if (!source.canReadRecord(record)) {
      throw const SpkFailure(
        'SPK_CONTENT_LOCKED',
        'El recurso sigue cifrado. Ejecuta AutoPerfil SPK y espera a que '
            'la clave de payloads quede autenticada antes de inspeccionarlo.',
      );
    }
    final result = await source.readEntry(record);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(fileName(record)),
        content: SizedBox(
          width: 590,
          child: SelectableText(
            'ID: ${record.idHex}\nFormato: ${result.format}\nOffset: ${record.dataOffset}\nAlmacenado: ${bytesLabel(record.storedBytes)}\nDecodificado: ${bytesLabel(result.bytes.length)}\nSHA-256: ${sha256.convert(result.bytes)}\n\nPrimeros 64 bytes:\n${spkHex(result.bytes.take(64))}',
            style: const TextStyle(fontFamily: 'Consolas', fontSize: 11),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  });

  Widget folderTree() {
    final all = source.folders();
    final roots =
        all.where((path) => path.isNotEmpty && !path.contains('/')).toList()
          ..sort();

    Widget node(String path, int depth) {
      final children = all.where((candidate) {
        if (!candidate.startsWith('$path/')) return false;
        final rest = candidate.substring(path.length + 1);
        return rest.isNotEmpty && !rest.contains('/');
      }).toList()..sort();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() {
              currentFolder = path;
              selected = null;
            }),
            child: Container(
              height: 31,
              padding: EdgeInsets.only(left: 10 + depth * 14, right: 8),
              color: currentFolder == path ? const Color(0xff29384f) : null,
              child: Row(
                children: [
                  Icon(
                    currentFolder == path
                        ? Icons.folder_open
                        : Icons.folder_outlined,
                    size: 16,
                    color: const Color(0xffd4b97f),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      path.split('/').last,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ),
          for (final child in children) node(child, depth + 1),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() {
            currentFolder = '';
            selected = null;
          }),
          child: Container(
            height: 35,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            color: currentFolder.isEmpty ? const Color(0xff29384f) : null,
            child: const Row(
              children: [
                Icon(
                  Icons.inventory_2_outlined,
                  size: 17,
                  color: Color(0xffa9c0ff),
                ),
                SizedBox(width: 7),
                Text('data.spk', style: TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
        for (final root in roots) node(root, 0),
      ],
    );
  }

  Widget resourceTable() {
    final folders = search.isEmpty ? childFolders() : <String>[];
    final entries = visibleEntries();
    final inferredPathCounts = <String, int>{};
    for (final record in entries) {
      final path = source.names.inferredPath(record.entryId);
      if (path == null) continue;
      final key = path.replaceAll('\\', '/').toLowerCase();
      inferredPathCounts[key] = (inferredPathCounts[key] ?? 0) + 1;
    }
    return Column(
      children: [
        Container(
          height: 34,
          color: const Color(0xff182231),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              const Expanded(flex: 5, child: Text('Nombre / ruta')),
              SizedBox(
                width: 95,
                child: Text(
                  source.canReadSimpleResources
                      ? 'Formato'
                      : 'Tipo estimado',
                ),
              ),
              const SizedBox(width: 105, child: Text('Almacenado')),
              SizedBox(
                width: 105,
                child: Text(
                  source.canReadSimpleResources
                      ? 'Decodificado'
                      : 'Decl. decod.',
                ),
              ),
              const SizedBox(width: 78, child: Text('Estado')),
              const SizedBox(width: 145, child: Text('ID')),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemExtent: 32,
            itemCount: folders.length + entries.length,
            itemBuilder: (_, index) {
              if (index < folders.length) {
                final path = folders[index];
                return InkWell(
                  onTap: () => setState(() {
                    currentFolder = path;
                    selected = null;
                  }),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.folder,
                          size: 16,
                          color: Color(0xffd4b97f),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            path.split('/').last,
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              final record = entries[index - folders.length];
              final active = identical(selected, record);
              return InkWell(
                onTap: () => setState(() => selected = record),
                onDoubleTap: source.canReadRecord(record)
                    ? () => inspectResource(record)
                    : null,
                child: Container(
                  color: active ? const Color(0xff29384f) : null,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      Icon(
                        source.names.isConfirmed(record.entryId)
                            ? Icons.verified_outlined
                            : source.names.confidence(record.entryId) ==
                                  'strong-inferred'
                            ? Icons.auto_awesome_outlined
                            : source.names.isInferred(record.entryId)
                            ? Icons.lightbulb_outline
                            : Icons.insert_drive_file_outlined,
                        size: 15,
                        color: source.names.isConfirmed(record.entryId)
                            ? const Color(0xff83c69d)
                            : source.names.confidence(record.entryId) ==
                                  'strong-inferred'
                            ? const Color(0xffd9b66f)
                            : source.names.isInferred(record.entryId)
                            ? const Color(0xff88a9d8)
                            : null,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        flex: 5,
                        child: Text(
                          (() {
                            final base = fileName(record);
                            final inferred =
                                source.names.inferredPath(record.entryId);
                            if (inferred == null) return base;
                            final key = inferred
                                .replaceAll('\\', '/')
                                .toLowerCase();
                            if ((inferredPathCounts[key] ?? 0) < 2) return base;
                            return '$base · candidato ${record.idHex.substring(0, 6)}';
                          })(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(
                        width: 95,
                        child: Text(
                          source.displayType(record),
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                      SizedBox(
                        width: 105,
                        child: Text(
                          bytesLabel(record.storedBytes),
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                      SizedBox(
                        width: 105,
                        child: Text(
                          bytesLabel(record.decodedBytes),
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                      SizedBox(
                        width: 78,
                        child: Row(
                          children: [
                            Icon(
                              source.canReadRecord(record)
                                  ? Icons.lock_open_outlined
                                  : Icons.lock_outline,
                              size: 13,
                              color: source.canReadRecord(record)
                                  ? const Color(0xff83c69d)
                                  : const Color(0xffd3ac76),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              source.canReadRecord(record)
                                  ? 'Legible'
                                  : 'Cifrado',
                              style: const TextStyle(fontSize: 9),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 145,
                        child: Text(
                          record.idHex,
                          style: const TextStyle(
                            fontFamily: 'Consolas',
                            fontSize: 10,
                            color: Color(0xff9eb1cf),
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
      ],
    );
  }

  Widget detailsPanel(SpkRecord record) => Material(
    color: const Color(0xff151e2a),
    child: ListView(
      padding: const EdgeInsets.all(14),
      children: [
        const Text(
          'PROPIEDADES',
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 1.2,
            color: Color(0xff9eadc5),
          ),
        ),
        const SizedBox(height: 12),
        SelectableText(
          fileName(record),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        property('ID', record.idHex),
        property('Tipo', record.recordType.toString()),
        property('Offset', record.dataOffset.toString()),
        property('Almacenado', bytesLabel(record.storedBytes)),
        property('Decodificado', bytesLabel(record.decodedBytes)),
        property('Fragmentos', record.chunkCount.toString()),
        property('Ruta', source.technicalPath(record)),
        property(
          'Estado',
          source.canReadRecord(record)
              ? 'payload autenticado y legible'
              : 'cifrado / no autenticado',
        ),
        property('Confianza', source.nameConfidence(record)),
        property('Evidencia', source.nameEvidence(record)),
        const Divider(height: 26),
        FilledButton.tonalIcon(
          onPressed: busy || !source.canReadRecord(record)
              ? null
              : () => inspectResource(record),
          icon: Icon(
            source.canReadRecord(record)
                ? Icons.manage_search
                : Icons.lock_outline,
            size: 17,
          ),
          label: Text(
            source.canReadRecord(record)
                ? 'Leer / inspeccionar'
                : 'Contenido cifrado',
          ),
        ),
        const SizedBox(height: 7),
        OutlinedButton.icon(
          onPressed: busy || !source.canReadRecord(record)
              ? null
              : extractSelected,
          icon: const Icon(Icons.file_download_outlined, size: 17),
          label: const Text('Extraer recurso'),
        ),
      ],
    ),
  );

  Widget property(String name, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 78,
          child: Text(
            name,
            style: const TextStyle(fontSize: 9, color: Color(0xff7f8ea6)),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: const TextStyle(fontFamily: 'Consolas', fontSize: 10),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final summary = source.index.summary();
    final validatedInferred = source.names.hints.values
        .where((hint) => hint.confidence == 'validated-inferred')
        .length;
    final strongInferred = source.names.hints.values
        .where((hint) => hint.confidence == 'strong-inferred')
        .length;
    final weakInferred =
        source.names.hints.length - strongInferred - validatedInferred;
    return Scaffold(
      backgroundColor: const Color(0xff101722),
      appBar: AppBar(
        titleSpacing: 12,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('DATA.SPK', style: TextStyle(fontSize: 14)),
            Text(
              'Explorador · solo lectura',
              style: TextStyle(fontSize: 9, color: Color(0xff8e9bb0)),
            ),
          ],
        ),
        actions: [
          if (Platform.isWindows && !source.canExtractAll)
            TextButton.icon(
              onPressed: busy ? null : captureResourceProfile,
              icon: const Icon(Icons.security_outlined, size: 17),
              label: const Text('Desbloquear SPK'),
            ),
          if (widget.onMount != null && source.canExtractAll)
            TextButton.icon(
              onPressed: busy ? null : mountInStudio,
              icon: const Icon(Icons.view_in_ar_outlined, size: 17),
              label: Text(
                hasConfirmedCoreTables ? 'Usar en Studio' : 'Preparar Studio',
              ),
            ),
          if (source.canExtractAll)
            FilledButton.icon(
              onPressed: busy ? null : extractAll,
              icon: const Icon(Icons.folder_copy_outlined, size: 17),
              label: const Text('Extraer todo'),
            ),
          PopupMenuButton<String>(
            enabled: !busy,
            tooltip: 'Más acciones SPK',
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'profile') loadResourceProfile();
              if (value == 'discover') discoverCoreTables();
              if (value == 'audit') auditAllResources();
              if (value == 'resolve') resolveNamesFromReferenceData();
              if (value == 'import') importNameMap();
              if (value == 'exportNames') exportNameMap();
              if (value == 'inventory') exportInventory();
              if (value == 'extractFolder') extractCurrentFolder();
              if (value == 'extractReadable') extractReadable();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'profile',
                child: ListTile(
                  leading: Icon(Icons.key_outlined),
                  title: Text('Perfil de recursos'),
                ),
              ),
              if (source.canExtractAll)
                const PopupMenuItem(
                  value: 'discover',
                  child: ListTile(
                    leading: Icon(Icons.table_view_outlined),
                    title: Text('Descubrir tablas'),
                  ),
                ),
              if (source.canExtractAll && !source.fullyValidatedResources)
                const PopupMenuItem(
                  value: 'audit',
                  child: ListTile(
                    leading: Icon(Icons.fact_check_outlined),
                    title: Text('Auditar todos los payloads'),
                  ),
                ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'resolve',
                child: ListTile(
                  leading: Icon(Icons.auto_awesome_outlined),
                  title: Text('Resolver nombres con DATA de referencia'),
                ),
              ),
              const PopupMenuItem(
                value: 'import',
                child: ListTile(
                  leading: Icon(Icons.file_open_outlined),
                  title: Text('Importar mapa de nombres'),
                ),
              ),
              const PopupMenuItem(
                value: 'exportNames',
                child: ListTile(
                  leading: Icon(Icons.save_alt_outlined),
                  title: Text('Exportar mapa de nombres'),
                ),
              ),
              const PopupMenuItem(
                value: 'inventory',
                child: ListTile(
                  leading: Icon(Icons.receipt_long_outlined),
                  title: Text('Exportar inventario / diagnóstico'),
                ),
              ),
              if (currentFolder.isNotEmpty &&
                  (source.canReadSimpleResources ||
                      source.canReadFragmentedResources))
                const PopupMenuItem(
                  value: 'extractFolder',
                  child: ListTile(
                    leading: Icon(Icons.drive_folder_upload_outlined),
                    title: Text('Extraer carpeta actual'),
                  ),
                ),
              if (!source.canExtractAll && source.canReadSimpleResources)
                const PopupMenuItem(
                  value: 'extractReadable',
                  child: ListTile(
                    leading: Icon(Icons.rule_folder_outlined),
                    title: Text('Extraer recursos legibles'),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          if (!source.canReadSimpleResources)
            Container(
              constraints: const BoxConstraints(minHeight: 42),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: const BoxDecoration(
                color: Color(0xff2a2115),
                border: Border(
                  bottom: BorderSide(color: Color(0xff6f542c)),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.lock_outline,
                    size: 18,
                    color: Color(0xffe1b86e),
                  ),
                  const SizedBox(width: 9),
                  const Expanded(
                    child: Text(
                      'CONTENIDO CIFRADO: las rutas, nombres y formatos visibles '
                      'son inferencias del índice; todavía no son recursos '
                      'abiertos ni editables.',
                      style: TextStyle(fontSize: 10),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: busy ? null : captureResourceProfile,
                    icon: const Icon(Icons.security_outlined, size: 16),
                    label: const Text('Desbloquear con AutoPerfil'),
                  ),
                ],
              ),
            ),
          Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: const BoxDecoration(
              color: Color(0xff141d29),
              border: Border(bottom: BorderSide(color: Color(0xff303a4b))),
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Subir un nivel',
                  onPressed: currentFolder.isEmpty
                      ? null
                      : () => setState(() {
                          final i = currentFolder.lastIndexOf('/');
                          currentFolder = i < 0
                              ? ''
                              : currentFolder.substring(0, i);
                          selected = null;
                        }),
                  icon: const Icon(Icons.arrow_upward, size: 18),
                ),
                Expanded(
                  child: Container(
                    height: 34,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xff0e1621),
                      border: Border.all(color: const Color(0xff334056)),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      currentFolder.isEmpty
                          ? 'data.spk:/'
                          : 'data.spk:/$currentFolder',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Consolas',
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 300,
                  child: TextField(
                    controller: searchController,
                    decoration: const InputDecoration(
                      hintText: 'Buscar nombre o ID…',
                      prefixIcon: Icon(Icons.search, size: 18),
                    ),
                    onChanged: (value) => setState(() => search = value),
                  ),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text(
                    'Recursivo',
                    style: TextStyle(fontSize: 10),
                  ),
                  selected: recursiveSearch,
                  onSelected: (value) =>
                      setState(() => recursiveSearch = value),
                ),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                SizedBox(
                  width: 255,
                  child: Material(
                    color: const Color(0xff131b26),
                    child: SingleChildScrollView(child: folderTree()),
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: resourceTable()),
                if (selected != null) ...[
                  const VerticalDivider(width: 1),
                  SizedBox(width: 255, child: detailsPanel(selected!)),
                ],
              ],
            ),
          ),
          Container(
            height: busy ? 48 : 30,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              color: Color(0xff121a25),
              border: Border(top: BorderSide(color: Color(0xff30394a))),
            ),
            child: busy
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      LinearProgressIndicator(
                        value: operationTotal == 0
                            ? null
                            : operationDone / operationTotal,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              operation.isEmpty ? 'Procesando…' : operation,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 9),
                            ),
                          ),
                          Text(
                            operationTotal == 0
                                ? ''
                                : '$operationDone / $operationTotal',
                            style: const TextStyle(fontSize: 9),
                          ),
                        ],
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Text(
                        '${summary['resources']} recursos · ${summary['fragmentedResources']} fragmentados · '
                        '${source.names.paths.length} confirmados · '
                        '$validatedInferred inferidos validados · '
                        '$strongInferred inferidos fuertes · '
                        '$weakInferred aproximados · '
                        '${(summary['resources'] as int) - source.names.paths.length - source.names.hints.length} sin resolver',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xff92a0b7),
                        ),
                      ),
                      const Spacer(),
                      if (source.fullyValidatedResources)
                        Text(
                          '${source.index.resources.length}/'
                          '${source.index.resources.length} recursos · '
                          'lectura total validada',
                          style: const TextStyle(
                            fontSize: 9,
                            color: Color(0xff83c69d),
                          ),
                        )
                      else if (source.canExtractAll)
                        const Text(
                          'Criptografía validada · falta auditoría total de payloads',
                          style: TextStyle(
                            fontSize: 9,
                            color: Color(0xff83c69d),
                          ),
                        )
                      else if (source.canReadSimpleResources)
                        const Text(
                          'Recursos simples legibles · fragmentados pendientes',
                          style: TextStyle(
                            fontSize: 9,
                            color: Color(0xffd3ac76),
                          ),
                        )
                      else
                        const Text(
                          'Índice y rutas listos · contenido aún cifrado · ejecuta AutoPerfil SPK',
                          style: TextStyle(
                            fontSize: 9,
                            color: Color(0xffd3ac76),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}