import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:three_js/three_js.dart' as t;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/formats.dart';
import '../core/spk_archive.dart';
import '../core/textures.dart';
import '../data/library.dart';
import '../data/spk_source.dart';
import '../data/spk_table_discovery.dart';
import '../editor/schema_reader.dart';
import 'data_editor.dart';
import '../render/native_view.dart';

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
      final value = await readSpkJsonFile(file);
      if (value is! Map) continue;
      final data = Map<String, dynamic>.from(value);
      final declared = (data['indexSha256'] ?? data['spkIndexSha256'])
          ?.toString()
          .toLowerCase();
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
      final value = await readSpkJsonFile(file);
      if (value is! Map) continue;
      final map = Map<String, dynamic>.from(value);
      final declared = map['spkIndexSha256']?.toString().toLowerCase();
      if (declared != null &&
          declared.isNotEmpty &&
          declared != source.index.encryptedIndexSha256.toLowerCase()) {
        continue;
      }
      source.names = SpkNameMap.fromJson(map);
      final removed = source.names.removeAmbiguousHints();
      if (removed > 0) {
        await file.writeAsString(
          const JsonEncoder.withIndent('  ').convert({
            ...map,
            ...source.names.toJson(),
            'spkIndexSha256': source.index.encryptedIndexSha256,
            'sanitizedAmbiguousHints': removed,
          }),
          flush: true,
        );
      }
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
    final raw = await readSpkJsonFile(file);
    if (raw is! Map) return false;
    final restored = source.restoreFullResourceValidation(
      Map<String, dynamic>.from(raw),
    );
    if (restored) {
      final nameValidation = source.validateInferredNamesByFormat();
      await File('$spkPath.names.json').writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          ...source.names.toJson(),
          'spkIndexSha256': source.index.encryptedIndexSha256,
          'nameFormatValidation': nameValidation,
        }),
        flush: true,
      );
    }
    return restored;
  } catch (_) {
    return false;
  }
}

Future<dynamic> readSpkJsonFile(File file) async {
  final bytes = await file.readAsBytes();
  return jsonDecode(utf8.decode(bytes, allowMalformed: true));
}

String spkFriendlyErrorMessage(Object error) {
  if (error is SpkFailure) {
    final output = error.report['output']?.toString();
    final consoleLog = error.report['consoleLog']?.toString();
    final diagnosisFile = error.report['diagnosisFile']?.toString();
    final failure = error.report['failure']?.toString();
    final details = <String>[
      if (failure != null && failure.isNotEmpty) failure,
      if (diagnosisFile != null && diagnosisFile.isNotEmpty)
        'Diagnóstico: $diagnosisFile',
      if (consoleLog != null && consoleLog.isNotEmpty)
        'Log: $consoleLog'
      else if (output != null && output.isNotEmpty)
        'Diagnóstico: $output',
    ];
    return '${error.code}: ${error.message}'
        '${details.isEmpty ? '' : ' · ${details.join(' · ')}'}';
  }
  if (error is FormatException) {
    final message = error.message.toString();
    if (message.contains('Missing extension byte') ||
        message.contains('Unexpected extension byte')) {
      return 'SPK_TEXT_ENCODING_INVALID: un decodificador de texto recibió '
          'bytes incompletos o una codificación distinta de UTF-8. Studio '
          'detuvo la operación y no modificó DATA.SPK. Si ocurrió al '
          'inspeccionar un recurso, usa HEX/ASCII o la codificación legacy.';
    }
    return message;
  }
  return error.toString();
}

class _SpkMeshPreview extends StatefulWidget {
  final MeshData mesh;
  final String label;
  final Uint8List? texturePng;

  const _SpkMeshPreview({
    required this.mesh,
    required this.label,
    this.texturePng,
  });

  @override
  State<_SpkMeshPreview> createState() => _SpkMeshPreviewState();
}

class _SpkMeshPreviewState extends State<_SpkMeshPreview> {
  late final NativeView view;
  t.Mesh? object;
  t.Texture? previewTexture;
  bool ready = false;
  late bool wireframe;
  double yaw = .45;
  double pitch = .18;
  double zoom = 1;
  double centerY = 0;
  double distance = 1;

  @override
  void initState() {
    super.initState();
    wireframe = widget.texturePng == null;
    view = NativeView(
      settings: t.Settings(
        clearColor: 0x0b1018,
        antialias: true,
        toneMapping: t.NoToneMapping,
      ),
      setup: _setup,
      onSetupComplete: () {
        if (mounted) setState(() => ready = true);
      },
    );
  }

  Future<void> _setup() async {
    final mesh = widget.mesh;
    if (mesh.vertices == 0 || mesh.triangles == 0) {
      throw const FormatException('La malla no contiene geometría visible.');
    }

    view.scene = t.Scene();
    view.scene.background = t.Color.fromHex32(0x0b1018);
    view.camera = t.PerspectiveCamera(
      42,
      view.width / view.height,
      .001,
      100000,
    );

    final geometry = t.BufferGeometry();
    geometry.setAttributeFromString(
      'position',
      t.Float32BufferAttribute.fromList(mesh.positions.toList(), 3),
    );
    if (mesh.normals.length == mesh.positions.length) {
      geometry.setAttributeFromString(
        'normal',
        t.Float32BufferAttribute.fromList(mesh.normals.toList(), 3),
      );
    }
    geometry.setIndex(mesh.indices.toList());

    if (widget.texturePng != null) {
      previewTexture = await t.TextureLoader(
        flipY: false,
      ).fromBytes(widget.texturePng!);
      if (previewTexture != null) {
        previewTexture!.colorSpace = t.SRGBColorSpace;
        previewTexture!.wrapS = t.RepeatWrapping;
        previewTexture!.wrapT = t.RepeatWrapping;
      }
    }
    final material = t.MeshBasicMaterial.fromMap({
      if (previewTexture != null) 'map': previewTexture,
      'color': previewTexture == null ? 0xb8c7df : 0xffffff,
      'side': t.DoubleSide,
      'wireframe': wireframe,
      'toneMapped': false,
    });
    object = t.Mesh(geometry, material)..frustumCulled = false;
    view.scene.add(object!);

    var minX = double.infinity;
    var minY = double.infinity;
    var minZ = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    var maxZ = -double.infinity;
    for (var i = 0; i < mesh.positions.length; i += 3) {
      final x = mesh.positions[i];
      final y = mesh.positions[i + 1];
      final z = mesh.positions[i + 2];
      minX = math.min(minX, x);
      minY = math.min(minY, y);
      minZ = math.min(minZ, z);
      maxX = math.max(maxX, x);
      maxY = math.max(maxY, y);
      maxZ = math.max(maxZ, z);
    }
    final centerX = (minX + maxX) / 2;
    centerY = (minY + maxY) / 2;
    final centerZ = (minZ + maxZ) / 2;
    object!.position.setValues(-centerX, 0, -centerZ);
    final span = math.max(maxX - minX, math.max(maxY - minY, maxZ - minZ));
    distance = math.max(.02, span * 1.7);
    _camera();
    view.addAnimationEvent((_) => _camera());
  }

  void _camera() {
    final d = distance * zoom;
    view.camera.position.setValues(
      math.sin(yaw) * math.cos(pitch) * d,
      centerY + math.sin(pitch) * d,
      math.cos(yaw) * math.cos(pitch) * d,
    );
    view.camera.lookAt(t.Vector3(0, centerY, 0));
  }

  @override
  void dispose() {
    object?.geometry?.dispose();
    object?.material?.dispose();
    previewTexture?.dispose();
    view.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(widget.label, style: const TextStyle(fontSize: 11)),
      const SizedBox(height: 8),
      Expanded(
        child: Stack(
          children: [
            Positioned.fill(
              child: Listener(
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent) {
                    setState(() {
                      zoom = (zoom * math.exp(event.scrollDelta.dy * .0015))
                          .clamp(.12, 12.0);
                    });
                  }
                },
                child: GestureDetector(
                  onPanUpdate: (details) => setState(() {
                    yaw += details.delta.dx * .01;
                    pitch = (pitch + details.delta.dy * .01).clamp(-1.45, 1.45);
                  }),
                  child: view.build(),
                ),
              ),
            ),
            if (!ready)
              const Positioned(
                right: 16,
                bottom: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ),
      const SizedBox(height: 6),
      Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilterChip(
            label: const Text('Malla'),
            selected: wireframe,
            onSelected: (value) {
              setState(() => wireframe = value);
              object?.material?.wireframe = value;
            },
          ),
          TextButton(
            onPressed: () => setState(() {
              yaw = 0;
              pitch = 0;
              zoom = 1;
            }),
            child: const Text('Frente'),
          ),
          TextButton(
            onPressed: () => setState(() {
              yaw = math.pi / 2;
              pitch = 0;
              zoom = 1;
            }),
            child: const Text('Perfil'),
          ),
          const Text(
            'Arrastra para girar · rueda para zoom',
            style: TextStyle(fontSize: 10, color: Color(0xff8e9bb0)),
          ),
        ],
      ),
    ],
  );
}

class SpkArchiveBrowserPage extends StatefulWidget {
  final SpkArchiveSource source;
  final Future<void> Function(SpkArchiveSource source)? onMount;
  const SpkArchiveBrowserPage({super.key, required this.source, this.onMount});

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
            content: Text(spkFriendlyErrorMessage(error)),
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
        final value = await readSpkJsonFile(file);
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
    final value = await readSpkJsonFile(File(profileFile.path));
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
  String formatFilter = '';
  bool recursiveSearch = false;
  SpkRecord? selected;
  bool busy = false;
  String operation = '';
  int operationDone = 0;
  int operationTotal = 0;
  String studioBuildLabel = '';
  Directory? referenceDataDirectory;

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
  void initState() {
    super.initState();
    _loadStudioBuildLabel();
  }

  Future<void> _loadStudioBuildLabel() async {
    try {
      final executable = File(Platform.resolvedExecutable);
      final provenance = File(
        p.join(executable.parent.path, 'build-provenance.json'),
      );
      if (!await provenance.exists()) return;
      final raw = await readSpkJsonFile(provenance);
      if (raw is! Map) return;
      final version = raw['version']?.toString() ?? '';
      final commit = raw['commit']?.toString() ?? '';
      if (version.isEmpty && commit.isEmpty) return;
      final shortCommit = commit.length > 12 ? commit.substring(0, 12) : commit;
      if (!mounted) return;
      setState(() {
        studioBuildLabel = [
          if (version.isNotEmpty) 'v$version',
          if (shortCommit.isNotEmpty) shortCommit,
        ].join(' · ');
      });
    } catch (_) {
      // Debug builds do not need packaged provenance.
    }
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

  List<SpkRecord> visibleEntries() {
    final rows = source.entriesInFolder(
      currentFolder,
      search: search,
      recursive: recursiveSearch || search.isNotEmpty,
    );
    if (formatFilter.isEmpty) return rows;
    return rows
        .where((record) => source.displayType(record) == formatFilter)
        .toList(growable: false);
  }

  List<String> availableFormatFilters() {
    final values = <String>{};
    for (final record in source.entriesInFolder(
      currentFolder,
      recursive: recursiveSearch || search.isNotEmpty,
    )) {
      values.add(source.displayType(record));
    }
    final sorted = values.toList()..sort();
    return sorted;
  }

  String fileName(SpkRecord record) {
    final path = source.technicalPath(record).replaceAll('\\', '/');
    return path.split('/').last;
  }

  Future<void> _showProbeFailure(SpkFailure error) async {
    if (!mounted) return;
    final diagnosis = error.report['diagnosis'];
    final output = error.report['output']?.toString();
    final consoleLog = error.report['consoleLog']?.toString();
    final diagnosisFile = error.report['diagnosisFile']?.toString();

    final lines = <String>[
      error.message,
      if (diagnosis is Map) ...[
        '',
        'Capturas: ${diagnosis['rows'] ?? 0}',
        'Simples detectados: ${diagnosis['simpleHits'] ?? 0}',
        'Chunks detectados: ${diagnosis['chunkHits'] ?? 0}',
        'Con clave: ${diagnosis['rowsWithKey'] ?? 0}',
        'Con nonce/tag: ${diagnosis['rowsWithAuth'] ?? 0}',
        'Autenticación offline válida: ${diagnosis['offlineValid'] ?? 0}',
        'Claves candidatas probadas: ${diagnosis['candidateKeysTested'] ?? 0}',
        'Claves candidatas autenticadas: ${diagnosis['candidateKeysAuthenticated'] ?? 0}',
        'Barrido estático V13: ${diagnosis['staticCandidatesTested'] ?? 0} '
            'candidatas · profundas: ${diagnosis['staticDeepCandidatesTested'] ?? 0} '
            '· módulos: ${diagnosis['staticModulesScanned'] ?? 0}',
        if (diagnosis['staticMatchSource'] != null)
          'Coincidencia estática: ${diagnosis['staticMatchSource']}',
        if (diagnosis['events'] is List)
          'Eventos: ${(diagnosis['events'] as List).join(', ')}',
      ],
      if (diagnosisFile != null && diagnosisFile.isNotEmpty) ...[
        '',
        'Diagnóstico: $diagnosisFile',
      ],
      if (consoleLog != null && consoleLog.isNotEmpty) 'Log: $consoleLog',
      if (output != null && output.isNotEmpty && diagnosisFile == null)
        'Carpeta: $output',
    ];
    final text = lines.join('\n');

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('AutoPerfil SPK no pudo cerrar el perfil'),
        content: SizedBox(
          width: 650,
          child: SelectableText(
            text,
            style: const TextStyle(fontFamily: 'Consolas', fontSize: 11),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (dialogContext.mounted) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('Diagnóstico copiado.')),
                );
              }
            },
            icon: const Icon(Icons.copy_all_outlined, size: 17),
            label: const Text('Copiar diagnóstico'),
          ),
          if (Platform.isWindows && output != null && output.isNotEmpty)
            TextButton.icon(
              onPressed: () async {
                await Process.run('explorer.exe', [output]);
              },
              icon: const Icon(Icons.folder_open_outlined, size: 17),
              label: const Text('Abrir carpeta'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  String _friendlyError(Object error) => spkFriendlyErrorMessage(error);

  Future<void> runAction(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        if (error is SpkFailure && error.code.startsWith('SPK_PROBE_')) {
          await _showProbeFailure(error);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_friendlyError(error)),
              duration: const Duration(seconds: 9),
            ),
          );
        }
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

  Future<void> chooseReferenceDataDirectory() => runAction(() async {
    final folder = await getDirectoryPath(
      confirmButtonText: 'Usar DATA para preview',
    );
    if (folder == null || !mounted) return;
    final directory = Directory(folder);
    if (!await directory.exists()) {
      throw const FileSystemException(
        'La carpeta DATA de referencia no existe.',
      );
    }
    if (!mounted) return;
    setState(() => referenceDataDirectory = directory);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'DATA de referencia activa. Doble clic en una ruta candidata para '
          'ver su recurso sin afirmar que el payload SPK esté descifrado.',
        ),
      ),
    );
  });

  Future<void> resolveNamesFromReferenceData() => runAction(() async {
    final folder = await getDirectoryPath(
      confirmButtonText: 'Usar DATA como referencia',
    );
    if (folder == null || !mounted) return;

    setState(() => referenceDataDirectory = Directory(folder));

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
    final nameValidation = archive.validateInferredNamesByFormat();
    await File('${archive.file.path}.names.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        ...archive.names.toJson(),
        'spkIndexSha256': archive.index.encryptedIndexSha256,
        'nameFormatValidation': nameValidation,
      }),
      flush: true,
    );

    final audited = <String, Object?>{
      ...result,
      'nameFormatValidation': nameValidation,
    };
    final evidence = File('${archive.file.path}.audit.json');
    await evidence.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'schema': 2,
        'source': archive.file.path,
        'indexSha256': archive.index.encryptedIndexSha256,
        'profileId': archive.profile.profileId,
        'resourceKeySha256': archive.profile.effectiveResourceSecret == null
            ? null
            : sha256
                  .convert(archive.profile.effectiveResourceSecret!)
                  .toString(),
        'chunkNonceRule': archive.profile.chunkNonceRule,
        'validation': audited,
        'resourceFormats': archive.validatedFormatsJson,
        'diagnostics': archive.diagnostics(),
      }),
      flush: true,
    );
    return audited;
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
          '${result['decodedBytes']} bytes decodificados · '
          '${(result['nameFormatValidation'] as Map?)?['validated'] ?? 0} '
          'rutas inferidas validadas · 0 fallos.',
        ),
        duration: const Duration(seconds: 10),
      ),
    );
  });

  Future<void> mountInStudio() => runAction(() async {
    final callback = widget.onMount;
    if (callback == null) return;
    if (!source.canReadSimpleResources) {
      throw const SpkFailure(
        'SPK_STUDIO_MOUNT_PROFILE',
        'Autentica primero el perfil de recursos simples.',
      );
    }
    operation =
        'Montando recursos legibles; los nombres inferidos no se usan como rutas nativas…';
    if (mounted) setState(() {});
    await callback(source);
    if (mounted) Navigator.of(context).pop();
  });

  Future<Map<String, Object?>> _diagnoseProbeFailure(
    Directory output,
    Map<String, dynamic> profile,
  ) async {
    final observations = File(
      p.join(output.path, 'resource-observations.json'),
    );
    List<dynamic> rows = const [];
    List<dynamic> events = const [];
    if (await observations.exists()) {
      try {
        final raw = await readSpkJsonFile(observations);
        if (raw is Map) {
          rows = (raw['rows'] as List?) ?? const [];
          events = (raw['events'] as List?) ?? const [];
        }
      } catch (_) {}
    }

    final eventCodes = <String>{
      for (final event in events.whereType<Map>())
        if (event['code'] != null) event['code'].toString(),
    };

    var candidateKeysTested = 0;
    var candidateKeysAuthenticated = 0;
    final candidateEvidence = File(p.join(output.path, 'candidate-keys.json'));
    if (await candidateEvidence.exists()) {
      try {
        final raw = await readSpkJsonFile(candidateEvidence);
        if (raw is Map) {
          candidateKeysTested = (raw['tested'] as num?)?.toInt() ?? 0;
          candidateKeysAuthenticated =
              (raw['authenticated'] as num?)?.toInt() ?? 0;
        }
      } catch (_) {}
    }

    var staticCandidatesTested = 0;
    var staticDeepCandidatesTested = 0;
    var staticModulesScanned = 0;
    var staticDeepModulesScanned = 0;
    String? staticMatchSource;
    final staticEvidence = File(p.join(output.path, 'static-key-sweep.json'));
    if (await staticEvidence.exists()) {
      try {
        final raw = await readSpkJsonFile(staticEvidence);
        if (raw is Map) {
          staticCandidatesTested = (raw['tested'] as num?)?.toInt() ?? 0;
          staticDeepCandidatesTested =
              (raw['deepTested'] as num?)?.toInt() ?? 0;
          staticModulesScanned = (raw['modules'] as List?)?.length ?? 0;
          staticDeepModulesScanned =
              (raw['deepModulesScanned'] as num?)?.toInt() ?? 0;
          final match = raw['match'];
          if (match is Map && match['source'] != null) {
            staticMatchSource = match['source'].toString();
          }
        }
      } catch (_) {}
    }

    var withKey = 0;
    var withAuth = 0;
    var offlineValid = 0;
    var simpleHits = 0;
    var chunkHits = 0;
    for (final raw in rows.whereType<Map>()) {
      final row = Map<String, dynamic>.from(raw);
      final key = row['key'];
      if (key is Map && key['secretHex']?.toString().isNotEmpty == true) {
        withKey++;
      }
      final auth = row['auth'];
      if (auth is Map &&
          auth['nonceHex']?.toString().isNotEmpty == true &&
          auth['tagHex']?.toString().isNotEmpty == true) {
        withAuth++;
      }
      if (row['offlineValid'] == true) offlineValid++;
      final target = row['target'];
      if (target is Map && target['kind'] == 'simple') simpleHits++;
      if (target is Map && target['kind'] == 'chunk') chunkHits++;
    }

    final simpleValidated = (profile['simpleValidated'] as num?)?.toInt() ?? 0;

    String reason;
    if (!eventCodes.contains('HOOK_READY') &&
        !eventCodes.contains('CANDIDATE_HOOK_READY')) {
      reason =
          'ResourceProbe no confirmó hooks criptográficos compatibles dentro '
          'del proceso de game.exe.';
    } else if (candidateKeysAuthenticated > 0) {
      reason =
          'Se autenticó una clave candidata contra payloads reales, pero el '
          'perfil final no quedó marcado como listo; conserva la evidencia '
          'para revisar esta inconsistencia.';
    } else if (rows.isEmpty && candidateKeysTested > 0) {
      reason =
          'Se observaron $candidateKeysTested claves candidatas dinámicas, '
          'pero ninguna autenticó los payloads AES-GCM reales del DATA.SPK. '
          'El barrido estático probó $staticCandidatesTested candidatas '
          '($staticDeepCandidatesTested en secciones PE de datos).';
    } else if (rows.isEmpty &&
        (staticCandidatesTested > 0 || staticDeepCandidatesTested > 0)) {
      reason =
          'El barrido estático V13 probó $staticCandidatesTested candidatas '
          '($staticDeepCandidatesTested profundas en $staticDeepModulesScanned '
          'módulos PE) sin autenticar la clave; el cliente tampoco expuso una '
          'candidata dinámica válida durante la captura.';
    } else if (rows.isEmpty) {
      reason =
          'El cliente no expuso ninguno de los 55.457 ciphertexts objetivo ni '
          'una clave candidata autenticable durante la ventana de captura.';
    } else if (withKey == 0) {
      reason =
          'Se observaron payloads del SPK, pero no se pudo recuperar la clave '
          'AES del handle criptográfico usado por el cliente.';
    } else if (withAuth == 0) {
      reason =
          'Se observaron payloads y claves, pero la llamada no expuso un '
          'nonce/tag GCM completo reproducible.';
    } else if (offlineValid == 0) {
      reason =
          'Se capturaron clave y parámetros GCM, pero no autentican offline '
          'el ciphertext exacto del DATA.SPK.';
    } else if (simpleValidated < 2) {
      reason =
          'Hay evidencia AES-GCM válida, pero faltan al menos dos recursos '
          'simples consistentes para cerrar el perfil.';
    } else {
      reason =
          'La evidencia es parcial o usa más de una clave/AAD; el perfil se '
          'mantiene bloqueado para evitar falsos positivos.';
    }

    final diagnosis = <String, Object?>{
      'schema': 1,
      'reason': reason,
      'rows': rows.length,
      'simpleHits': simpleHits,
      'chunkHits': chunkHits,
      'rowsWithKey': withKey,
      'rowsWithAuth': withAuth,
      'offlineValid': offlineValid,
      'candidateKeysTested': candidateKeysTested,
      'candidateKeysAuthenticated': candidateKeysAuthenticated,
      'staticCandidatesTested': staticCandidatesTested,
      'staticDeepCandidatesTested': staticDeepCandidatesTested,
      'staticModulesScanned': staticModulesScanned,
      'staticDeepModulesScanned': staticDeepModulesScanned,
      'events': eventCodes.toList()..sort(),
      'profileReadyForSimple': profile['readyForSimple'] == true,
      'profileResourceKeys': profile['resourceKeys'],
      'profileModes': profile['modes'],
      'profileAadRule': profile['aadRule'],
    };
    if (staticMatchSource != null) {
      diagnosis['staticMatchSource'] = staticMatchSource;
    }
    await File(p.join(output.path, 'probe-diagnosis.json')).writeAsString(
      const JsonEncoder.withIndent('  ').convert(diagnosis),
      flush: true,
    );
    return diagnosis;
  }

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
            'Shaiya Studio abrirá game.exe de esa instalación e instrumentará '
            'solo ese proceso. ResourceProbe V13 combina CNG/OpenSSL, BoringSSL, '
            'mbedTLS, wolfSSL, barrido PE acotado y candidatos runtime. Ninguna '
            'clave se acepta hasta autenticar ciphertexts AES-GCM reales del '
            'DATA.SPK ya indexado.\n\n'
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
    operation = 'Preparando ResourceProbe V13…';
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
        'Shaiya Studio ResourceProbe V13',
        'exitCode=$exitCode',
        'game=${game.path}',
        'data=${source.file.path}',
        '',
        ...console,
        '',
      ].join('\n'),
      flush: true,
    );

    final profileFile = File(
      p.join(output.path, 'derived-resource-profile.json'),
    );
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
    final raw = await readSpkJsonFile(profileFile);
    if (raw is! Map) {
      throw const FormatException('ResourceProbe produjo un JSON inválido.');
    }
    final data = Map<String, dynamic>.from(raw);
    if (data['readyForSimple'] != true) {
      final diagnosis = await _diagnoseProbeFailure(output, data);
      throw SpkFailure(
        'SPK_PROBE_NO_VALID_KEY',
        diagnosis['reason']?.toString() ??
            'ResourceProbe no obtuvo un perfil de recursos válido.',
        {
          'output': output.path,
          if (data['failure'] != null) 'failure': data['failure'],
          'diagnosis': diagnosis,
          'diagnosisFile': p.join(output.path, 'probe-diagnosis.json'),
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
        const JsonEncoder.withIndent(
          '  ',
        ).convert({...data, 'studioValidation': simpleValidation}),
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
    final raw = await readSpkJsonFile(File(picked.path));
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
    Map<String, dynamic>? studioBuild;
    try {
      final executable = File(Platform.resolvedExecutable);
      final provenance = File(
        p.join(executable.parent.path, 'build-provenance.json'),
      );
      if (await provenance.exists()) {
        final raw = await readSpkJsonFile(provenance);
        if (raw is Map) {
          studioBuild = Map<String, dynamic>.from(raw);
        }
      }
    } catch (_) {
      // En debug o instalaciones manuales puede no existir provenance.
    }
    final body = const JsonEncoder.withIndent('  ').convert({
      'schema': 3,
      'source': source.file.path,
      'studioBuild': studioBuild,
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
        ),
      );
    }
  });

  String _hexAsciiDump(Uint8List bytes, {int maxBytes = 4096}) {
    final limit = math.min(bytes.length, maxBytes);
    final rows = <String>[];
    for (var offset = 0; offset < limit; offset += 16) {
      final end = math.min(offset + 16, limit);
      final chunk = bytes.sublist(offset, end);
      final hex = chunk
          .map((value) => value.toRadixString(16).padLeft(2, '0'))
          .join(' ')
          .padRight(47);
      final printable = String.fromCharCodes(
        chunk.map((value) => value >= 32 && value <= 126 ? value : 46),
      );
      rows.add(
        '${offset.toRadixString(16).padLeft(8, '0')}  $hex  |$printable|',
      );
    }
    if (limit < bytes.length) {
      rows.add('');
      rows.add('… vista HEX limitada a $limit de ${bytes.length} bytes …');
    }
    return rows.join('\n');
  }

  List<String> _embeddedBinaryStrings(
    Uint8List bytes, {
    int maxScanBytes = 1024 * 1024,
    int maxStrings = 120,
  }) {
    final limit = math.min(bytes.length, maxScanBytes);
    final found = <String>{};

    void add(List<int> values) {
      if (values.length < 4 || found.length >= maxStrings) return;
      final value = String.fromCharCodes(values).trim();
      if (value.length >= 4) found.add(value);
    }

    var current = <int>[];
    for (var i = 0; i < limit && found.length < maxStrings; i++) {
      final value = bytes[i];
      if (value >= 32 && value <= 126) {
        current.add(value);
      } else {
        add(current);
        current = <int>[];
      }
    }
    add(current);

    for (final phase in const [0, 1]) {
      current = <int>[];
      for (var i = phase; i + 1 < limit && found.length < maxStrings; i += 2) {
        final low = bytes[i];
        final high = bytes[i + 1];
        if (high == 0 && low >= 32 && low <= 126) {
          current.add(low);
        } else {
          add(current);
          current = <int>[];
        }
      }
      add(current);
    }

    return found.take(maxStrings).toList(growable: false);
  }

  Widget _binaryInspectionPreview(
    SpkReadResult result,
    String path, {
    String? warning,
  }) {
    final strings = _embeddedBinaryStrings(result.bytes);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${result.format} · ${result.bytes.length} bytes · visor HEX + ASCII',
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
        if (warning != null && warning.isNotEmpty) ...[
          const SizedBox(height: 7),
          Text(
            warning,
            style: const TextStyle(fontSize: 10, color: Color(0xffd7ad63)),
          ),
        ],
        const SizedBox(height: 8),
        Expanded(
          child: Scrollbar(
            child: SingleChildScrollView(
              child: SelectableText(
                [
                  'Ruta: $path',
                  '',
                  'CADENAS DETECTADAS'
                      '${strings.isEmpty ? ' · ninguna en la muestra' : ''}',
                  if (strings.isNotEmpty) ...strings.map((value) => '  $value'),
                  '',
                  'HEX + ASCII',
                  _hexAsciiDump(result.bytes),
                ].join('\n'),
                style: const TextStyle(
                  fontFamily: 'Consolas',
                  fontSize: 10,
                  height: 1.35,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _inspectionPreview(
    SpkReadResult result,
    String path, {
    Uint8List? meshTexturePng,
  }) {
    Widget preview;
    try {
      switch (result.format) {
        case 'DDS':
        case 'PNG':
        case 'BMP':
        case 'JPEG':
        case 'GIF':
        case 'TGA':
          final pixels = Pixels.decode(result.bytes, path);
          preview = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${pixels.width} × ${pixels.height} píxeles',
                style: const TextStyle(fontSize: 11),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: DecoratedBox(
                  decoration: const BoxDecoration(color: Color(0xff0b1018)),
                  child: InteractiveViewer(
                    minScale: .25,
                    maxScale: 8,
                    child: Center(
                      child: Image.memory(
                        pixels.png(),
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
          break;
        case 'XML':
        case 'JSON':
        case 'INI':
        case 'TXT':
          final limit = result.bytes.length < 262144
              ? result.bytes.length
              : 262144;
          final text = utf8.decode(
            result.bytes.sublist(0, limit),
            allowMalformed: true,
          );
          preview = Scrollbar(
            child: SingleChildScrollView(
              child: SelectableText(
                text +
                    (limit < result.bytes.length
                        ? '\n\n… vista limitada a 256 KiB …'
                        : ''),
                style: const TextStyle(fontFamily: 'Consolas', fontSize: 11),
              ),
            ),
          );
          break;
        case 'MLT':
          final rows = readMlt(result.bytes, path);
          preview = SelectableText(
            [
              'Materiales: ${rows.length}',
              '',
              ...rows
                  .take(300)
                  .map(
                    (row) =>
                        '#${row.id} · ${row.mesh} → ${row.texture} · alpha=${row.alpha}',
                  ),
              if (rows.length > 300) '… ${rows.length - 300} registros más …',
            ].join('\n'),
            style: const TextStyle(fontFamily: 'Consolas', fontSize: 11),
          );
          break;
        case 'ITM':
          final rows = readItm(result.bytes, path);
          preview = SelectableText(
            [
              'Modelos de objetos/armas: ${rows.length}',
              '',
              ...rows
                  .take(300)
                  .map(
                    (row) =>
                        '#${row.id} · ${row.mesh} → ${row.texture} · '
                        'transformaciones=${row.transforms.length}',
                  ),
              if (rows.length > 300) '… ${rows.length - 300} registros más …',
            ].join('\n'),
            style: const TextStyle(fontFamily: 'Consolas', fontSize: 11),
          );
          break;
        case 'MON':
          final rows = readMon(result.bytes, path);
          preview = SelectableText(
            [
              'Criaturas/modelos: ${rows.length}',
              '',
              ...rows
                  .take(300)
                  .map(
                    (row) =>
                        '#${row.id} · ${row.name} · partes=${row.parts.length} · '
                        'animaciones=${row.animations.length}',
                  ),
              if (rows.length > 300) '… ${rows.length - 300} registros más …',
            ].join('\n'),
            style: const TextStyle(fontFamily: 'Consolas', fontSize: 11),
          );
          break;
        case 'WTR':
          final water = WtrData.parse(result.bytes, path);
          preview = SelectableText(
            [
              'Tabla de agua WTR',
              '',
              'Tile size: ${water.tileSize}',
              'Texturas: ${water.textures.length}',
              ...water.textures.take(200).map((texture) => '• $texture'),
              if (water.textures.length > 200)
                '… ${water.textures.length - 200} texturas más …',
            ].join('\n'),
            style: const TextStyle(fontFamily: 'Consolas', fontSize: 11),
          );
          break;
        case 'MANI':
          final mani = ManiData.parse(result.bytes, path);
          preview = SelectableText(
            'MAni válida\n\n'
            'Versión: 0x${mani.version.toRadixString(16)}\n'
            'Rotación habilitada: ${mani.enableRotation}\n'
            'Rotación: ${mani.rotation.x.toStringAsFixed(4)}, '
            '${mani.rotation.y.toStringAsFixed(4)}, '
            '${mani.rotation.z.toStringAsFixed(4)}\n'
            'Velocidad: ${mani.animationSpeed.toStringAsFixed(4)}',
            style: const TextStyle(fontFamily: 'Consolas', fontSize: 11),
          );
          break;
        case 'VANI':
          final vani = VaniData.parse(result.bytes, path);
          preview = SelectableText(
            [
              'VAni válida',
              '',
              'Frames: ${vani.frameCount}',
              'Mallas: ${vani.meshes.length}',
              'Radio: ${vani.radius.toStringAsFixed(3)}',
              ...vani.meshes
                  .take(100)
                  .map(
                    (mesh) =>
                        '• ${mesh.texture} · ${mesh.vertices} vértices · '
                        '${mesh.indices.length ~/ 3} triángulos · '
                        '${mesh.frameCount} frames',
                  ),
              if (vani.meshes.length > 100)
                '… ${vani.meshes.length - 100} mallas más …',
            ].join('\n'),
            style: const TextStyle(fontFamily: 'Consolas', fontSize: 11),
          );
          break;
        case 'SMOD':
          final smod = readSmodData(result.bytes, path);
          final triangles = smod.collisions.fold<int>(
            0,
            (sum, collision) => sum + collision.triangles,
          );
          preview = SelectableText(
            [
              'SMOD válido',
              '',
              'Partes visuales: ${smod.parts.length}',
              'Mallas de colisión: ${smod.collisions.length}',
              'Triángulos de colisión: $triangles',
              'Radio: ${smod.radius.toStringAsFixed(3)}',
              ...smod.parts
                  .take(100)
                  .map(
                    (part) =>
                        '• ${part.texture} · ${part.mesh.vertices} vértices · '
                        '${part.mesh.triangles} triángulos',
                  ),
            ].join('\n'),
            style: const TextStyle(fontFamily: 'Consolas', fontSize: 11),
          );
          break;
        case 'DG':
          final dg = DgData.parse(result.bytes, path);
          final triangles = dg.collisions.fold<int>(
            0,
            (sum, collision) => sum + collision.triangles,
          );
          preview = SelectableText(
            [
              'Dungeon DG válido',
              '',
              'Partes visuales: ${dg.parts.length}',
              'Lightmaps declarados: ${dg.lightmapCount}',
              'Mallas de colisión: ${dg.collisions.length}',
              'Triángulos de colisión: $triangles',
              ...dg.parts
                  .take(100)
                  .map(
                    (part) =>
                        '• ${part.texture} · ${part.mesh.vertices} vértices · '
                        '${part.mesh.triangles} triángulos',
                  ),
            ].join('\n'),
            style: const TextStyle(fontFamily: 'Consolas', fontSize: 11),
          );
          break;
        case 'SVMAP':
          final map = SvmapData.parse(result.bytes, path);
          preview = SelectableText(
            [
              'SVMAP válido',
              '',
              'Tamaño de mapa: ${map.mapSize}',
              'Tamaño de celda: ${map.cellSize}',
              'NPC/rutas: ${map.npcs.length}',
              'Áreas de mobs: ${map.mobAreas.length}',
              'Portales: ${map.portals.length}',
              'Spawns: ${map.spawns.length}',
              'Áreas con nombre: ${map.namedAreas.length}',
            ].join('\n'),
            style: const TextStyle(fontFamily: 'Consolas', fontSize: 11),
          );
          break;
        case '3DC':
          final mesh = MeshData.skinned(result.bytes, path);
          preview = _SpkMeshPreview(
            mesh: mesh,
            texturePng: meshTexturePng,
            label:
                '3DC · ${mesh.vertices} vértices · ${mesh.triangles} triángulos · '
                '${mesh.requiredBones} huesos'
                '${meshTexturePng == null ? ' · sin textura asociada' : ' · textura DDS asociada'}',
          );
          break;
        case '3DO':
          final mesh = MeshData.object(result.bytes, path);
          preview = _SpkMeshPreview(
            mesh: mesh,
            texturePng: meshTexturePng,
            label:
                '3DO · ${mesh.vertices} vértices · ${mesh.triangles} triángulos'
                '${meshTexturePng == null ? ' · sin textura asociada' : ' · textura DDS asociada'}',
          );
          break;
        case 'ANI':
          final clip = ClipData.parse(result.bytes, path);
          preview = SelectableText(
            'Animación válida\n\n'
            'Duración: ${clip.duration.toStringAsFixed(3)} s\n'
            'Huesos/pistas: ${clip.bones.length}',
            style: const TextStyle(fontFamily: 'Consolas', fontSize: 11),
          );
          break;
        case 'SDATA':
          final document = EditorReader.open(result.bytes, path);
          if (!document.complete || document.rows.isEmpty) {
            preview = SelectableText(
              'SData autenticada, pero todavía no hay un esquema completo '
              'para esta tabla.\n\n'
              'Perfil detectado: ${document.profile}\n'
              'Filas parciales: ${document.rows.length}\n'
              'Advertencias: ${document.warnings.join(' · ')}\n\n'
              'El payload permanece disponible sin modificaciones en el '
              'workspace SPK.',
              style: const TextStyle(fontFamily: 'Consolas', fontSize: 11),
            );
            break;
          }

          final visibleRows = math.min(document.rows.length, 100);
          final firstFields = document.fields(0);
          final visibleColumns = math.min(firstFields.length, 32);
          preview = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'SData · perfil ${document.profile} · '
                '${document.rows.length} filas · '
                '${firstFields.length} columnas'
                '${document.rows.length > visibleRows ? ' · mostrando 100' : ''}',
                style: const TextStyle(fontSize: 11),
              ),
              if (document.warnings.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  document.warnings.take(3).join(' · '),
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xffd7ad63),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Expanded(
                child: Scrollbar(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: math.max(760, visibleColumns * 150.0),
                      child: ListView.builder(
                        itemCount: visibleRows + 1,
                        itemBuilder: (_, index) {
                          if (index == 0) {
                            return Container(
                              height: 34,
                              color: const Color(0xff1d2938),
                              child: Row(
                                children: [
                                  const SizedBox(
                                    width: 55,
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 9,
                                      ),
                                      child: Text(
                                        '#',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                  for (var col = 0; col < visibleColumns; col++)
                                    SizedBox(
                                      width: 150,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 9,
                                        ),
                                        child: Text(
                                          firstFields[col].spec.name,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          }
                          final rowIndex = index - 1;
                          final fields = document.fields(rowIndex);
                          return Container(
                            height: 31,
                            decoration: BoxDecoration(
                              color: rowIndex.isEven
                                  ? const Color(0xff111923)
                                  : const Color(0xff151f2c),
                              border: const Border(
                                bottom: BorderSide(
                                  color: Color(0xff263344),
                                  width: .5,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 55,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    child: Text(
                                      rowIndex.toString(),
                                      style: const TextStyle(
                                        fontFamily: 'Consolas',
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                                ),
                                for (var col = 0; col < visibleColumns; col++)
                                  SizedBox(
                                    width: 150,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                      ),
                                      child: SelectableText(
                                        col < fields.length
                                            ? document.read(fields[col])
                                            : '',
                                        maxLines: 1,
                                        style: const TextStyle(
                                          fontFamily: 'Consolas',
                                          fontSize: 10,
                                        ),
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
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Vista de inspección. Para editar campos y relaciones usa '
                'Preparar Studio; los cambios se guardan en el overlay.',
                style: TextStyle(fontSize: 10, color: Color(0xff8e9bb0)),
              ),
            ],
          );
          break;
        default:
          preview = _binaryInspectionPreview(result, path);
      }
    } catch (error) {
      preview = _binaryInspectionPreview(
        result,
        path,
        warning:
            'El payload fue autenticado, pero la vista estructurada falló: '
            '$error',
      );
    }
    return preview;
  }

  bool _recordHasStructuredEditor(SpkRecord record) {
    final format = source.validatedFormat(record.entryId);
    return const {
      'SDATA',
      'MLT',
      'ITM',
      'MON',
      'XML',
      'TXT',
      'INI',
    }.contains(format);
  }

  String _editorActionLabel(SpkRecord record) {
    return source.validatedFormat(record.entryId) == 'SDATA'
        ? 'Editar tabla'
        : 'Editar recurso';
  }

  String _editableLibraryPath(SpkRecord record) {
    if (source.names.isConfirmed(record.entryId)) {
      return canon(source.names[record.entryId]!);
    }
    if (!source.fullyValidatedResources) {
      throw const SpkFailure(
        'SPK_EDIT_AUDIT_REQUIRED',
        'Para editar un recurso sin nombre confirmado primero debe completarse '
            'la auditoría integral del SPK.',
      );
    }
    final format = source.validatedFormat(record.entryId) ?? 'BIN';
    return canon(
      '_SPK_SinNombre/${record.idHex}'
      '${SpkArchiveSource.extensionFor(format)}',
    );
  }

  Future<void> openCoreTableEditor(
    String path,
    String label, {
    String? fieldGroup,
  }) => runAction(() async {
    if (!source.canExtractAll) {
      throw const SpkFailure(
        'SPK_CORE_EDITOR_PROFILE',
        'Primero deben estar autenticados los recursos simples y fragmentados.',
      );
    }
    if (!source.fullyValidatedResources) {
      operation = 'Auditando DATA.SPK antes de abrir $label…';
      if (mounted) setState(() {});
      await _auditAllResources(source);
    }

    final canonical = canon(path);
    final alreadyConfirmed = source.names.paths.values.any(
      (value) => canon(value) == canonical,
    );
    if (!alreadyConfirmed) {
      operation = 'Identificando $label por estructura…';
      if (mounted) setState(() {});
      await _discoverCoreTables(source);
    }
    final confirmed = source.names.paths.values.any(
      (value) => canon(value) == canonical,
    );
    if (!confirmed) {
      throw SpkFailure(
        'SPK_CORE_TABLE_NOT_CONFIRMED',
        'No se pudo confirmar $label de forma inequívoca en este DATA.SPK.',
        {'path': path},
      );
    }

    final library = await Library.fromSpk(
      source,
      requireCharacter: false,
      progress: (message) {
        if (mounted) setState(() => operation = message);
      },
    );
    try {
      if (!library.files.containsKey(canonical)) {
        throw FormatException(
          'La tabla confirmada no quedó montada en Studio: $path',
        );
      }
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => DataEditorPage(
            library: library,
            initialPath: canonical,
            initialFieldGroup: fieldGroup,
          ),
        ),
      );
    } finally {
      library.dispose();
    }
  });

  Future<void> openRecordInEditor(SpkRecord record) => runAction(() async {
    if (!source.canExtractAll) {
      throw const SpkFailure(
        'SPK_EDITOR_PROFILE',
        'El editor requiere recursos simples y fragmentados autenticados.',
      );
    }
    if (!source.fullyValidatedResources) {
      operation = 'Auditando DATA.SPK antes de habilitar edición…';
      if (mounted) setState(() {});
      await _auditAllResources(source);
    }
    if (source.validatedFormat(record.entryId) == 'SDATA' &&
        !source.names.isConfirmed(record.entryId)) {
      operation = 'Identificando la tabla SData por estructura…';
      if (mounted) setState(() {});
      await _discoverCoreTables(source);
    }
    final path = _editableLibraryPath(record);
    final library = await Library.fromSpk(
      source,
      requireCharacter: false,
      progress: (message) {
        if (mounted) {
          setState(() => operation = message);
        }
      },
    );
    try {
      if (!library.files.containsKey(path)) {
        throw FormatException(
          'El recurso no quedó montado en la biblioteca editable: $path',
        );
      }
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => DataEditorPage(library: library, initialPath: path),
        ),
      );
    } finally {
      library.dispose();
    }
  });

  Future<void> replaceRecordInOverlay(SpkRecord record) => runAction(() async {
    if (!source.canExtractAll) {
      throw const SpkFailure(
        'SPK_OVERLAY_PROFILE',
        'Para reemplazar un recurso deben estar autenticados los recursos '
            'simples y fragmentados.',
      );
    }
    if (!source.fullyValidatedResources) {
      operation = 'Auditando DATA.SPK antes de habilitar el reemplazo…';
      if (mounted) setState(() {});
      await _auditAllResources(source);
    }

    final path = _editableLibraryPath(record);
    final picked = await openFile(confirmButtonText: 'Usar como reemplazo');
    if (picked == null) return;

    final replacementFile = File(picked.path);
    const maxReplacementBytes = 128 * 1024 * 1024;
    final replacementLength = await replacementFile.length();
    if (replacementLength > maxReplacementBytes) {
      throw const FormatException(
        'El reemplazo supera el límite de 128 MiB del workspace SPK.',
      );
    }
    final replacementBytes = await replacementFile.readAsBytes();

    final expectedFormat = source.validatedFormat(record.entryId) ?? 'BIN';
    final replacementFormat = SpkArchiveSource.detectFormat(replacementBytes);
    final expectedExtension = p.extension(path).toLowerCase();
    final replacementExtension = p.extension(picked.path).toLowerCase();
    final binaryExtensionMismatch =
        expectedFormat == 'BIN' &&
        expectedExtension.isNotEmpty &&
        expectedExtension != '.bin' &&
        replacementExtension != expectedExtension;
    if ((expectedFormat != 'BIN' && replacementFormat != expectedFormat) ||
        binaryExtensionMismatch) {
      throw SpkFailure(
        'SPK_REPLACEMENT_FORMAT',
        'El archivo elegido no conserva el formato autenticado o la extensión '
            'técnica del recurso.',
        {
          'expectedFormat': expectedFormat,
          'replacementFormat': replacementFormat,
          'expectedExtension': expectedExtension,
          'replacementExtension': replacementExtension,
          'path': path,
        },
      );
    }

    operation = 'Montando overlay editable para $path…';
    if (mounted) setState(() {});
    final library = await Library.fromSpk(
      source,
      requireCharacter: false,
      progress: (message) {
        if (mounted) setState(() => operation = message);
      },
    );
    try {
      final current = await library.read(path, limit: maxReplacementBytes);
      final expectedHash = sha256.convert(current).toString();
      await library.writeSpkOverlay(
        {path: replacementBytes},
        expectedHashes: {path: expectedHash},
      );
    } finally {
      library.dispose();
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Reemplazo guardado en overlay · $replacementFormat · '
          '${bytesLabel(replacementBytes.length)} · $path. '
          'DATA.SPK original permanece intacto.',
        ),
        duration: const Duration(seconds: 10),
      ),
    );
  });

  Future<Uint8List?> _matchingTexturePng(
    SpkRecord meshRecord,
    String meshPath,
    String meshFormat,
  ) async {
    if (meshFormat != '3DC' && meshFormat != '3DO') return null;
    final normalized = meshPath.replaceAll('\\', '/');
    final dot = normalized.lastIndexOf('.');
    if (dot < 0) return null;
    final stem = normalized.substring(0, dot);
    final candidates = <String>{
      '$stem.dds',
      if (normalized.toLowerCase().contains('/3dc/'))
        '${stem.replaceFirst(RegExp(r'/3dc/', caseSensitive: false), '/DDS/')}.dds',
      if (normalized.toLowerCase().contains('/3do/'))
        '${stem.replaceFirst(RegExp(r'/3do/', caseSensitive: false), '/DDS/')}.dds',
    }.map((value) => value.toLowerCase()).toSet();

    for (final record in source.index.resources) {
      if (record.entryId == meshRecord.entryId ||
          !source.canReadRecord(record)) {
        continue;
      }
      final path = source.technicalPath(record).replaceAll('\\', '/');
      if (!candidates.contains(path.toLowerCase())) continue;
      try {
        final result = await source.readEntry(record);
        if (!const {
          'DDS',
          'PNG',
          'BMP',
          'JPEG',
          'GIF',
          'TGA',
        }.contains(result.format)) {
          continue;
        }
        return Pixels.decode(result.bytes, path).png();
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  File? _referenceFileFor(SpkRecord record) {
    final root = referenceDataDirectory;
    final relative = source.names[record.entryId];
    if (root == null || relative == null || relative.isEmpty) return null;
    final segments = relative.replaceAll('\\', '/').split('/');
    final candidate = p.normalize(p.joinAll([root.path, ...segments]));
    final normalizedRoot = p.normalize(root.path);
    if (candidate != normalizedRoot && !p.isWithin(normalizedRoot, candidate)) {
      return null;
    }
    return File(candidate);
  }

  Future<Uint8List?> _matchingReferenceTexturePng(
    String meshPath,
    String meshFormat,
  ) async {
    final root = referenceDataDirectory;
    if (root == null || (meshFormat != '3DC' && meshFormat != '3DO')) {
      return null;
    }
    final normalized = meshPath.replaceAll('\\', '/');
    final dot = normalized.lastIndexOf('.');
    if (dot < 0) return null;
    final stem = normalized.substring(0, dot);
    final stems = <String>{
      stem,
      if (normalized.toLowerCase().contains('/3dc/'))
        stem.replaceFirst(RegExp(r'/3dc/', caseSensitive: false), '/DDS/'),
      if (normalized.toLowerCase().contains('/3do/'))
        stem.replaceFirst(RegExp(r'/3do/', caseSensitive: false), '/DDS/'),
    };
    final candidates = <String>[
      for (final value in stems) ...['$value.dds', '$value.tga'],
    ];

    for (final relative in candidates) {
      final file = File(
        p.normalize(p.joinAll([root.path, ...relative.split('/')])),
      );
      if (!await file.exists()) continue;
      try {
        if (await file.length() > 64 * 1024 * 1024) continue;
        final bytes = await file.readAsBytes();
        final format = SpkArchiveSource.detectFormat(bytes);
        if (!const {
          'DDS',
          'PNG',
          'BMP',
          'JPEG',
          'GIF',
          'TGA',
        }.contains(format)) {
          continue;
        }
        return Pixels.decode(bytes, relative).png();
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  Future<void> inspectReferenceResource(
    SpkRecord record,
  ) => runAction(() async {
    final file = _referenceFileFor(record);
    if (file == null || !await file.exists()) {
      throw const SpkFailure(
        'SPK_REFERENCE_FILE_MISSING',
        'La ruta inferida no existe dentro de la DATA de referencia seleccionada.',
      );
    }
    const maxBytes = 128 * 1024 * 1024;
    final length = await file.length();
    if (length > maxBytes) {
      throw const FormatException(
        'La copia de referencia supera el límite de inspección de 128 MiB.',
      );
    }
    final bytes = await file.readAsBytes();
    final format = SpkArchiveSource.detectFormat(bytes);
    final result = SpkReadResult(record, bytes, format);
    if (!mounted) return;
    final candidatePath = source.names[record.entryId]!;
    final meshTexturePng = await _matchingReferenceTexturePng(
      candidatePath,
      format,
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Referencia · ${fileName(record)}'),
        content: SizedBox(
          width: 820,
          height: 620,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: const Color(0xff2a2115),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xff6f542c)),
                ),
                child: const Text(
                  'COPIA DATA DE REFERENCIA · este visor NO afirma que el '
                  'payload del SPK esté descifrado ni permite escribirlo. '
                  'Sirve para trabajar visualmente mientras AutoPerfil cierra '
                  'la clave real del contenedor.',
                  style: TextStyle(fontSize: 10, color: Color(0xffe1b86e)),
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(
                'ID SPK: ${record.idHex} · Formato referencia: $format · '
                'Bytes: ${bytesLabel(bytes.length)}\n'
                'SHA-256 referencia: ${sha256.convert(bytes)}\n'
                'Ruta candidata: $candidatePath',
                style: const TextStyle(fontFamily: 'Consolas', fontSize: 10),
              ),
              const Divider(height: 20),
              Expanded(
                child: _inspectionPreview(
                  result,
                  candidatePath,
                  meshTexturePng: meshTexturePng,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
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
    final path = source.technicalPath(record);
    final meshTexturePng = await _matchingTexturePng(
      record,
      path,
      result.format,
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(fileName(record)),
        content: SizedBox(
          width: 820,
          height: 620,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SelectableText(
                'ID: ${record.idHex} · Formato: ${result.format} · '
                'Almacenado: ${bytesLabel(record.storedBytes)} · '
                'Decodificado: ${bytesLabel(result.bytes.length)}\n'
                'SHA-256: ${sha256.convert(result.bytes)}\n'
                'Ruta: $path',
                style: const TextStyle(fontFamily: 'Consolas', fontSize: 10),
              ),
              const Divider(height: 20),
              Expanded(
                child: _inspectionPreview(
                  result,
                  path,
                  meshTexturePng: meshTexturePng,
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (_recordHasStructuredEditor(record))
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(c);
                openRecordInEditor(record);
              },
              icon: const Icon(Icons.edit_note_outlined),
              label: Text(_editorActionLabel(record)),
            ),
          if (source.canExtractAll)
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(c);
                replaceRecordInOverlay(record);
              },
              icon: const Icon(Icons.swap_horiz_outlined),
              label: const Text('Reemplazar en overlay'),
            ),
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
            formatFilter = '';
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
                  source.canReadSimpleResources ? 'Formato' : 'Tipo estimado',
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
                    formatFilter = '';
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
                onDoubleTap: busy
                    ? null
                    : source.canReadRecord(record)
                    ? () => inspectResource(record)
                    : referenceDataDirectory != null &&
                          source.names[record.entryId] != null
                    ? () => inspectReferenceResource(record)
                    : captureResourceProfile,
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
                            final inferred = source.names.inferredPath(
                              record.entryId,
                            );
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
        if (!source.names.isConfirmed(record.entryId)) ...[
          const SizedBox(height: 6),
          const Text(
            'RUTA INFERIDA · todavía no confirmada por contenido',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: Color(0xffd9b66f),
            ),
          ),
        ],
        const SizedBox(height: 12),
        property('ID', record.idHex),
        property('Tipo', record.recordType.toString()),
        property('Offset', record.dataOffset.toString()),
        property('Almacenado', bytesLabel(record.storedBytes)),
        property('Decodificado', bytesLabel(record.decodedBytes)),
        property('Fragmentos', record.chunkCount.toString()),
        property(
          source.names.isConfirmed(record.entryId) ? 'Ruta' : 'Ruta inferida',
          source.technicalPath(record),
        ),
        property(
          'Estado',
          source.canReadRecord(record)
              ? 'payload autenticado y legible'
              : 'cifrado / no autenticado',
        ),
        property('Confianza', source.nameConfidence(record)),
        property('Evidencia', source.nameEvidence(record)),
        const Divider(height: 26),
        if (!source.canReadRecord(record)) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xff202637),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xff6b5b3e)),
            ),
            child: Text(
              source.names.isConfirmed(record.entryId)
                  ? 'PAYLOAD NO LEÍDO: el registro existe en el índice, pero '
                        'su contenido AES-GCM todavía no está autenticado.'
                  : 'PAYLOAD NO LEÍDO: la ruta mostrada es '
                        '${source.nameConfidence(record)}. Hasta autenticar '
                        'el payload no se habilitan visor ni edición.',
              style: const TextStyle(fontSize: 10, color: Color(0xffd9b66f)),
            ),
          ),
          const SizedBox(height: 7),
          FilledButton.icon(
            onPressed: busy ? null : captureResourceProfile,
            icon: const Icon(Icons.key_outlined, size: 17),
            label: const Text('Desbloquear con AutoPerfil SPK'),
          ),
          if (referenceDataDirectory != null &&
              source.names[record.entryId] != null) ...[
            const SizedBox(height: 7),
            OutlinedButton.icon(
              onPressed: busy ? null : () => inspectReferenceResource(record),
              icon: const Icon(Icons.visibility_outlined, size: 17),
              label: const Text('Ver copia DATA de referencia'),
            ),
          ],
        ] else
          FilledButton.tonalIcon(
            onPressed: busy ? null : () => inspectResource(record),
            icon: const Icon(Icons.manage_search, size: 17),
            label: const Text('Leer / inspeccionar'),
          ),
        const SizedBox(height: 7),
        if (source.canReadRecord(record) &&
            _recordHasStructuredEditor(record)) ...[
          const SizedBox(height: 7),
          FilledButton.icon(
            onPressed: busy ? null : () => openRecordInEditor(record),
            icon: const Icon(Icons.edit_note_outlined, size: 17),
            label: Text(_editorActionLabel(record)),
          ),
        ],
        if (source.canReadRecord(record) && source.canExtractAll) ...[
          const SizedBox(height: 7),
          OutlinedButton.icon(
            onPressed: busy ? null : () => replaceRecordInOverlay(record),
            icon: const Icon(Icons.swap_horiz_outlined, size: 17),
            label: const Text('Reemplazar en overlay'),
          ),
        ],
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('DATA.SPK', style: TextStyle(fontSize: 14)),
            Text(
              source.canExtractAll
                  ? 'Original protegido · overlay editable'
                  : source.canReadSimpleResources
                  ? 'Lectura parcial · fragmentos pendientes'
                  : 'Explorador · contenido cifrado',
              style: const TextStyle(fontSize: 9, color: Color(0xff8e9bb0)),
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
          if (widget.onMount != null && source.canReadSimpleResources)
            TextButton.icon(
              onPressed: busy ? null : mountInStudio,
              icon: const Icon(Icons.view_in_ar_outlined, size: 17),
              label: Text(
                source.canExtractAll
                    ? 'Usar en Studio'
                    : 'Usar recursos legibles',
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
              if (value == 'coreItem') {
                openCoreTableEditor(
                  'BinarySData/DBItemData.SData',
                  'Objetos / trade',
                  fieldGroup: 'Requisitos',
                );
              }
              if (value == 'coreMonster') {
                openCoreTableEditor(
                  'BinarySData/DBMonsterData.SData',
                  'Mobs / drops',
                  fieldGroup: 'Botín y oro',
                );
              }
              if (value == 'coreSkill') {
                openCoreTableEditor(
                  'BinarySData/DBSkillData.SData',
                  'Skills',
                  fieldGroup: 'Habilidades',
                );
              }
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
              if (source.canExtractAll) ...[
                const PopupMenuItem(
                  value: 'coreItem',
                  child: ListTile(
                    leading: Icon(Icons.inventory_2_outlined),
                    title: Text('Editar Objetos / trade'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'coreMonster',
                  child: ListTile(
                    leading: Icon(Icons.pest_control_outlined),
                    title: Text('Editar Mobs / drops'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'coreSkill',
                  child: ListTile(
                    leading: Icon(Icons.auto_fix_high_outlined),
                    title: Text('Editar Skills'),
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'discover',
                  child: ListTile(
                    leading: Icon(Icons.table_view_outlined),
                    title: Text('Descubrir tablas'),
                  ),
                ),
              ],
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
          if (source.canExtractAll)
            Container(
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: const BoxDecoration(
                color: Color(0xff12251d),
                border: Border(bottom: BorderSide(color: Color(0xff285c46))),
              ),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 7,
                runSpacing: 5,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(right: 5),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.verified_outlined,
                          size: 18,
                          color: Color(0xff83c69d),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'DATOS SPK',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: busy
                        ? null
                        : () => openCoreTableEditor(
                            'BinarySData/DBItemData.SData',
                            'Objetos / trade',
                            fieldGroup: 'Requisitos',
                          ),
                    icon: const Icon(Icons.inventory_2_outlined, size: 16),
                    label: const Text('Objetos / trade'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: busy
                        ? null
                        : () => openCoreTableEditor(
                            'BinarySData/DBMonsterData.SData',
                            'Mobs / drops',
                            fieldGroup: 'Botín y oro',
                          ),
                    icon: const Icon(Icons.pest_control_outlined, size: 16),
                    label: const Text('Mobs / drops'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: busy
                        ? null
                        : () => openCoreTableEditor(
                            'BinarySData/DBSkillData.SData',
                            'Skills',
                            fieldGroup: 'Habilidades',
                          ),
                    icon: const Icon(Icons.auto_fix_high_outlined, size: 16),
                    label: const Text('Skills'),
                  ),
                  if (widget.onMount != null)
                    TextButton.icon(
                      onPressed: busy ? null : mountInStudio,
                      icon: const Icon(Icons.view_in_ar_outlined, size: 16),
                      label: const Text('Abrir Studio 3D'),
                    ),
                ],
              ),
            ),
          if (!source.canReadSimpleResources)
            Container(
              constraints: const BoxConstraints(minHeight: 42),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: const BoxDecoration(
                color: Color(0xff2a2115),
                border: Border(bottom: BorderSide(color: Color(0xff6f542c))),
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
                  const SizedBox(width: 6),
                  OutlinedButton.icon(
                    onPressed: busy ? null : chooseReferenceDataDirectory,
                    icon: const Icon(Icons.folder_open_outlined, size: 16),
                    label: Text(
                      referenceDataDirectory == null
                          ? 'Usar DATA de referencia'
                          : 'Cambiar DATA de referencia',
                    ),
                  ),
                ],
              ),
            ),
          if (referenceDataDirectory != null)
            Container(
              constraints: const BoxConstraints(minHeight: 34),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: const BoxDecoration(
                color: Color(0xff172337),
                border: Border(bottom: BorderSide(color: Color(0xff365070))),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.visibility_outlined,
                    size: 16,
                    color: Color(0xff9dbbdf),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'PREVIEW DE REFERENCIA ACTIVO: doble clic en una ruta '
                      'candidata para visualizar su archivo de la DATA externa. '
                      'El SPK sigue fail-closed hasta autenticar sus payloads.',
                      style: TextStyle(fontSize: 10),
                    ),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => setState(() => referenceDataDirectory = null),
                    child: const Text('Desactivar'),
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
                SizedBox(
                  width: 145,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(formatFilter),
                    initialValue: formatFilter.isEmpty ? null : formatFilter,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.filter_alt_outlined, size: 17),
                      hintText: 'Formato',
                    ),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('Todos')),
                      for (final value in availableFormatFilters())
                        DropdownMenuItem(
                          value: value,
                          child: Text(value, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => formatFilter = value ?? ''),
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
                      if (studioBuildLabel.isNotEmpty) ...[
                        Text(
                          studioBuildLabel,
                          style: const TextStyle(
                            fontSize: 9,
                            color: Color(0xff728198),
                            fontFamily: 'Consolas',
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
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
                        Text(
                          'Índice validado · ${source.reads} payloads leídos · '
                          'rutas aún no confirmadas por contenido · '
                          'ejecuta AutoPerfil SPK',
                          style: const TextStyle(
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
