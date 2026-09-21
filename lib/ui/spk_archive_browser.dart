import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/spk_archive.dart';
import '../data/spk_source.dart';

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
      return;
    } catch (_) {
      // Un mapa opcional dañado no impide abrir un SPK válido.
    }
  }
}

class SpkArchiveBrowserPage extends StatefulWidget {
  final SpkArchiveSource source;
  const SpkArchiveBrowserPage({super.key, required this.source});

  static Future<SpkArchiveSource?> pickAndOpen(BuildContext context) async {
    final picked = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Archivo DATA.SPK', extensions: ['spk']),
      ],
      confirmButtonText: 'Abrir DATA.SPK',
    );
    if (picked == null || !context.mounted) return null;

    final profile = await _chooseProfile(context, picked.path);
    if (profile == null || !context.mounted) return null;

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
        progress.value = 'Autenticando perfil de payloads contra muestras reales…';
        await source.validateSimpleResourceProfile();
      }
      progress.value = 'Buscando perfil validado de recursos…';
      source = await loadAutomaticSpkResourceProfile(source, picked.path);
      progress.value = 'Validando fragmentación AES-GCM offline…';
      source = await deriveAutomaticFragmentProfile(source, picked.path);
      progress.value = 'Resolviendo nombres y rutas conocidas…';
      await loadAutomaticSpkNameMap(source, picked.path);
      if (!context.mounted) return null;
      Navigator.of(context, rootNavigator: true).pop();
      return await Navigator.of(context).push<SpkArchiveSource>(
        MaterialPageRoute(
          builder: (_) => SpkArchiveBrowserPage(source: source),
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
      return null;
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
  late SpkArchiveSource _source;

  SpkArchiveSource get source => _source;

  @override
  void initState() {
    super.initState();
    _source = widget.source;
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

  Future<void> runAction(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString()),
            duration: const Duration(seconds: 7),
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

  Future<void> persistNameMapSidecar() async {
    final target = File('${source.file.path}.names.json');
    final temporary = File('${target.path}.tmp');
    final body = <String, Object?>{
      ...source.names.toJson(),
      'spkIndexSha256': source.index.encryptedIndexSha256,
    };
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert(body),
      flush: true,
    );
    if (await target.exists()) await target.delete();
    await temporary.rename(target.path);
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
    final list = source.entriesInFolder(currentFolder, recursive: true);
    if (list.isEmpty) {
      throw const FormatException('La carpeta no contiene recursos.');
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
    await persistNameMapSidecar();
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
                  'La verificación es más lenta, pero produce nombres confirmados. '
                  'Si la fragmentación ya fue autenticada también confirma recursos fragmentados.',
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
    await persistNameMapSidecar();
    if (!mounted) return;
    setState(() {
      currentFolder = '';
      selected = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          verify == true
              ? '${result['confirmed']} rutas confirmadas por SHA-256 · '
                    '${result['simpleVerified']} simples · '
                    '${result['fragmentedVerified']} fragmentadas'
                    '${(result['fragmentedSkipped'] as int) > 0 ? ' · ${result['fragmentedSkipped']} fragmentadas pendientes' : ''}.'
              : '${result['strongInferred']} rutas con evidencia Zstandard + '
                    '${result['sizeOnlyInferred']} por tamaño único. '
                    'Se muestran como inferidas hasta confirmarlas.',
        ),
        duration: const Duration(seconds: 7),
      ),
    );
  });

  Future<void> captureResourceProfile() => runAction(() async {
    if (!Platform.isWindows) {
      throw const SpkFailure(
        'SPK_PROBE_WINDOWS_ONLY',
        'La captura automática del perfil de payloads requiere Windows x64.',
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
    operation = 'Preparando ResourceProbe V8…';
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
    );
    final recent = <String>[];
    void reportLine(String line) {
      final clean = line.trim();
      if (clean.isEmpty) return;
      recent.add(clean);
      if (recent.length > 12) recent.removeAt(0);
      if (mounted) {
        setState(() => operation = clean);
      }
    }

    final stdoutDone = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach(reportLine);
    final stderrDone = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach(reportLine);
    final exitCode = await process.exitCode;
    await Future.wait([stdoutDone, stderrDone]);

    final profileFile = File(p.join(output.path, 'derived-resource-profile.json'));
    if (!await profileFile.exists()) {
      throw SpkFailure(
        'SPK_PROBE_NO_PROFILE',
        'El helper terminó sin producir un perfil criptográfico validado.',
        {
          'exitCode': exitCode,
          'output': output.path,
          'logTail': recent,
        },
      );
    }
    final raw = jsonDecode(await profileFile.readAsString());
    if (raw is! Map) {
      throw const FormatException('ResourceProbe produjo un JSON inválido.');
    }
    final data = Map<String, dynamic>.from(raw);
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

    if (!mounted) return;
    final full = next.canExtractAll;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          full
              ? 'Perfil validado: simples + fragmentados. Extraer todo habilitado.'
              : 'Perfil simple validado. Los fragmentados siguen bloqueados hasta validarlos.',
        ),
        duration: const Duration(seconds: 8),
      ),
    );
    setState(() {
      _source = next;
      currentFolder = '';
      selected = null;
    });
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
    setState(() {
      _source = next;
      currentFolder = '';
      selected = null;
    });
  });

  Future<void> exportInventory() => runAction(() async {
    final location = await getSaveLocation(
      suggestedName: 'spk-inventario.json',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Inventario JSON', extensions: ['json']),
      ],
    );
    if (location == null) return;
    final body = const JsonEncoder.withIndent('  ').convert({
      'schema': 1,
      'source': source.file.path,
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
    return Column(
      children: [
        Container(
          height: 34,
          color: const Color(0xff182231),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: const Row(
            children: [
              Expanded(flex: 5, child: Text('Nombre')),
              SizedBox(width: 95, child: Text('Tipo')),
              SizedBox(width: 105, child: Text('Almacenado')),
              SizedBox(width: 105, child: Text('Decodificado')),
              SizedBox(width: 145, child: Text('ID')),
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
                onDoubleTap: () => inspectResource(record),
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
                          fileName(record),
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
        property('Nombre', source.nameConfidence(record)),
        property('Evidencia', source.nameEvidence(record)),
        const Divider(height: 26),
        FilledButton.tonalIcon(
          onPressed: busy ? null : () => inspectResource(record),
          icon: const Icon(Icons.manage_search, size: 17),
          label: const Text('Leer / inspeccionar'),
        ),
        const SizedBox(height: 7),
        OutlinedButton.icon(
          onPressed: busy ? null : extractSelected,
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
    final strongInferred = source.names.hints.values
        .where((hint) => hint.confidence == 'strong-inferred')
        .length;
    final weakInferred = source.names.hints.length - strongInferred;
    return Scaffold(
      backgroundColor: const Color(0xff101722),
      appBar: AppBar(
        titleSpacing: 12,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Explorador DATA.SPK', style: TextStyle(fontSize: 14)),
            Text(
              'Archivo montado en solo lectura',
              style: TextStyle(fontSize: 9, color: Color(0xff8e9bb0)),
            ),
          ],
        ),
        actions: [
          if (source.canExtractAll &&
              (source.names.paths.isNotEmpty || strongInferred > 0))
            FilledButton.tonalIcon(
              onPressed: busy
                  ? null
                  : () => Navigator.of(context).pop<SpkArchiveSource>(source),
              icon: const Icon(Icons.hub_outlined, size: 17),
              label: const Text('Usar en Studio'),
            ),
          if (Platform.isWindows && !source.canExtractAll)
            TextButton.icon(
              onPressed: busy ? null : captureResourceProfile,
              icon: const Icon(Icons.security_outlined, size: 17),
              label: const Text('AutoPerfil SPK'),
            ),
          TextButton.icon(
            onPressed: busy ? null : loadResourceProfile,
            icon: const Icon(Icons.key_outlined, size: 17),
            label: const Text('Perfil de recursos'),
          ),
          PopupMenuButton<String>(
            enabled: !busy,
            tooltip: 'Nombres y rutas',
            icon: const Icon(Icons.drive_file_rename_outline, size: 18),
            onSelected: (value) {
              if (value == 'resolve') resolveNamesFromReferenceData();
              if (value == 'import') importNameMap();
              if (value == 'export') exportNameMap();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'resolve',
                child: ListTile(
                  leading: Icon(Icons.auto_awesome_outlined),
                  title: Text('Resolver con DATA de referencia'),
                  subtitle: Text('Tamaño + Zstandard nivel 3'),
                ),
              ),
              PopupMenuItem(
                value: 'import',
                child: ListTile(
                  leading: Icon(Icons.file_open_outlined),
                  title: Text('Importar mapa de nombres'),
                ),
              ),
              PopupMenuItem(
                value: 'export',
                child: ListTile(
                  leading: Icon(Icons.save_alt_outlined),
                  title: Text('Exportar mapa actual'),
                ),
              ),
            ],
          ),
          TextButton.icon(
            onPressed: busy ? null : exportInventory,
            icon: const Icon(Icons.receipt_long_outlined, size: 17),
            label: const Text('Inventario'),
          ),
          TextButton.icon(
            onPressed: busy || selected == null ? null : extractSelected,
            icon: const Icon(Icons.file_download_outlined, size: 17),
            label: const Text('Extraer'),
          ),
          TextButton.icon(
            onPressed: busy || currentFolder.isEmpty
                ? null
                : extractCurrentFolder,
            icon: const Icon(Icons.drive_folder_upload_outlined, size: 17),
            label: const Text('Extraer carpeta'),
          ),
          if (!source.canExtractAll)
            TextButton.icon(
              onPressed: busy || !source.canReadSimpleResources
                  ? null
                  : extractReadable,
              icon: const Icon(Icons.rule_folder_outlined, size: 17),
              label: const Text('Extraer legibles'),
            ),
          FilledButton.icon(
            onPressed: busy || !source.canExtractAll ? null : extractAll,
            icon: const Icon(Icons.folder_copy_outlined, size: 17),
            label: const Text('Extraer todo'),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: Column(
        children: [
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
                        '$strongInferred inferidos fuertes · '
                        '$weakInferred aproximados · '
                        '${(summary['resources'] as int) - source.names.paths.length - source.names.hints.length} sin resolver',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xff92a0b7),
                        ),
                      ),
                      const Spacer(),
                      if (source.canExtractAll)
                        const Text(
                          'Lectura SPK completa validada · Extraer todo habilitado',
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
                          'Índice listo · falta perfil criptográfico de payloads',
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