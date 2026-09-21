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
      return await SpkArchiveSource.open(
        spkPath,
        profile,
        names: source.names,
      );
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

  static Future<void> pickAndOpen(BuildContext context) async {
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
      progress.value = 'Buscando perfil validado de recursos…';
      source = await loadAutomaticSpkResourceProfile(source, picked.path);
      progress.value = 'Validando fragmentación AES-GCM offline…';
      source = await deriveAutomaticFragmentProfile(source, picked.path);
      progress.value = 'Resolviendo nombres y rutas conocidas…';
      await loadAutomaticSpkNameMap(source, picked.path);
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      await Navigator.of(context).push<void>(
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
    final persistent = File('${source.file.path}.resources.json');
    await persistent.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
      flush: true,
    );
    var next = await SpkArchiveSource.open(
      source.file.path,
      nextProfile,
      names: source.names,
    );
    operation = 'Validando nonces de fragmentos contra AES-GCM…';
    if (mounted) setState(() {});
    next = await deriveAutomaticFragmentProfile(next, source.file.path);
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
    await Navigator.of(context).pushReplacement<void, void>(
      MaterialPageRoute(builder: (_) => SpkArchiveBrowserPage(source: next)),
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
    next = await deriveAutomaticFragmentProfile(next, source.file.path);

    final persistent = File('${source.file.path}.profile.json');
    await persistent.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'profileId': nextProfile.profileId,
        'indexSha256': nextProfile.indexSha256,
        'index': {
          'algorithm': 'AES-GCM',
          'secretHex': spkHex(nextProfile.indexSecret),
        },
        'resources': {
          'algorithm': 'AES-GCM',
          if (nextProfile.effectiveResourceSecret != null)
            'secretHex': spkHex(nextProfile.effectiveResourceSecret!),
          if (nextProfile.resourceAad.isNotEmpty)
            'aadHex': spkHex(nextProfile.resourceAad),
          'useIndexKey': nextProfile.resourceKeyIsIndexKey,
          'chunkNonceRule': nextProfile.chunkNonceRule,
        },
      }),
      flush: true,
    );

    if (!mounted) return;
    await Navigator.of(context).pushReplacement<void, void>(
      MaterialPageRoute(builder: (_) => SpkArchiveBrowserPage(source: next)),
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
        ),