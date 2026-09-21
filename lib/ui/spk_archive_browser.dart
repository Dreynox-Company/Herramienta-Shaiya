import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../core/spk_archive.dart';
import '../data/spk_source.dart';

String _spkParentPath(String value, String separator) {
  final normalized = value
      .replaceAll('\\', separator)
      .replaceAll('/', separator);
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
  final separator = separatorOverride ?? Platform.pathSeparator;
  final spkDir = _spkParentPath(spkPath, separator);
  final exeDir = _spkParentPath(
    executablePath ?? Platform.resolvedExecutable,
    separator,
  );
  return <String>[
    '$spkPath.profile.json',
    '$spkDir${separator}data.spk.profile.json',
    '$spkDir${separator}spk-crypto-profile.json',
    '$exeDir${separator}profiles${separator}data.spk.profile.json',
    '$exeDir${separator}profiles${separator}spk-crypto-profile.json',
    '$exeDir${separator}data.spk.profile.json',
    '$exeDir${separator}spk-crypto-profile.json',
  ];
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
      final source = await SpkArchiveSource.open(
        picked.path,
        profile,
        progress: (message, done, total) => progress.value = message,
      );
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
    if (folder == null) return;

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
              : '${result['inferred']} rutas inferidas por tamaño único. '
                    'Se muestran como inferidas hasta confirmarlas.',
        ),
        duration: const Duration(seconds: 7),
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
    final nextProfile = SpkCryptoProfile.fromJson(
      Map<String, dynamic>.from(raw),
    );
    final next = await SpkArchiveSource.open(
      source.file.path,
      nextProfile,
      names: source.names,
    );
    if (!context.mounted) return;
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
                      const Icon(Icons.insert_drive_file_outlined, size: 15),
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
          TextButton.icon(
            onPressed: busy ? null : resolveNamesFromReferenceData,
            icon: const Icon(Icons.account_tree_outlined, size: 17),
            label: const Text('Reconstruir nombres'),
          ),
          TextButton.icon(
            onPressed: busy ? null : loadResourceProfile,
            icon: const Icon(Icons.key_outlined, size: 17),
            label: const Text('Perfil de recursos'),
          ),
          TextButton.icon(
            onPressed: busy ? null : importNameMap,
            icon: const Icon(Icons.drive_file_rename_outline, size: 17),
            label: const Text('Mapa de nombres'),
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
                        '${source.names.hints.length} inferidos · '
                        '${summary['resources'] as int - source.names.paths.length - source.names.hints.length} sin resolver',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xff92a0b7),
                        ),
                      ),
                      const Spacer(),
                      if (!source.canExtractAll)
                        const Text(
                          'Extraer todo requiere clave de recursos y regla de fragmentación validadas',
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
