import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../data/spk_source.dart';

class SpkBrowserPage extends StatefulWidget {
  final SpkSource source;
  const SpkBrowserPage({super.key, required this.source});

  @override
  State<SpkBrowserPage> createState() => _SpkBrowserPageState();
}

class _SpkBrowserPageState extends State<SpkBrowserPage> {
  String search = '';
  String folder = 'all';
  int? selectedOrdinal;
  bool extracting = false;
  bool cancelExtraction = false;
  SpkExtractionProgress? extraction;
  final Map<String, String> detectedExtensions = {};

  SpkSource get source => widget.source;

  List<SpkRecord> get visible {
    Iterable<SpkRecord> rows = source.records;
    if (folder == 'simple') {
      rows = rows.where((r) => r.type == 1);
    } else if (folder == 'chunked') {
      rows = rows.where((r) => r.type == 3);
    } else if (folder == 'special') {
      rows = rows.where((r) => r.type != 1 && r.type != 3);
    } else if (folder.startsWith('bucket:')) {
      final prefix = folder.substring(7);
      rows = rows.where((r) => r.entryId.startsWith(prefix));
    }
    final q = search.trim().toLowerCase();
    if (q.isNotEmpty) {
      rows = rows.where(
        (r) =>
            r.entryId.contains(q) ||
            r.ordinal.toString().contains(q) ||
            r.technicalName.toLowerCase().contains(q),
      );
    }
    return rows.toList(growable: false);
  }

  SpkRecord? get selected {
    final id = selectedOrdinal;
    if (id == null || id < 0 || id >= source.records.length) return null;
    return source.records[id];
  }

  List<MapEntry<String, int>> get buckets {
    final counts = <String, int>{};
    for (final r in source.resources) {
      counts.update(r.entryId.substring(0, 2), (n) => n + 1, ifAbsent: () => 1);
    }
    final rows = counts.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return rows;
  }

  Future<void> preview(SpkRecord record) async {
    if (record.type != 1) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(record.technicalName),
          content: SelectableText(
            'Recurso fragmentado en ${record.chunks.length} bloques.\n\n'
            'Offset: ${record.dataOffset}\n'
            'Almacenado: ${record.storedBytes} bytes\n'
            'Decodificado: ${record.decodedBytes} bytes\n'
            'ID: ${record.entryId}\n\n'
            'Se conserva en el catálogo y manifiesto; esta revisión todavía '
            'no inventa el nonce implícito de sus fragmentos.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
      return;
    }

    Uint8List bytes;
    try {
      bytes = await source.read(record.entryId, limit: 64 * 1024 * 1024);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
      return;
    }
    final ext = detectSpkExtension(bytes);
    detectedExtensions[record.entryId] = ext;
    if (mounted) setState(() {});

    Widget body;
    if (ext == '.txt' || ext == '.xml') {
      String text;
      if (bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xfe) {
        final d = ByteData.sublistView(bytes, 2);
        final units = <int>[
          for (var i = 0; i + 1 < d.lengthInBytes; i += 2)
            d.getUint16(i, Endian.little),
        ];
        text = String.fromCharCodes(units);
      } else {
        text = utf8.decode(bytes, allowMalformed: true);
      }
      body = SelectableText(
        text.length > 30000 ? '${text.substring(0, 30000)}\n\n[…]' : text,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
      );
    } else if (ext == '.png' || ext == '.jpg' || ext == '.bmp') {
      body = InteractiveViewer(child: Image.memory(bytes, fit: BoxFit.contain));
    } else {
      final head = bytes
          .take(256)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(' ');
      body = SelectableText(
        'Formato detectado: ${ext}\n'
        'Bytes: ${bytes.length}\n'
        'SHA/ID técnico: ${record.entryId}\n\n'
        'Primeros 256 bytes:\n${head}',
        style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
      );
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${record.technicalName}${ext}'),
        content: SizedBox(
          width: 800,
          height: 560,
          child: SingleChildScrollView(child: body),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              extractOne(record, bytes: bytes, knownExtension: ext);
            },
            child: const Text('Extraer…'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<void> extractOne(
    SpkRecord record, {
    Uint8List? bytes,
    String? knownExtension,
  }) async {
    if (record.type != 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Este recurso fragmentado aún no es extraíble.'),
        ),
      );
      return;
    }
    bytes ??= await source.read(record.entryId, limit: 256 * 1024 * 1024);
    final ext = knownExtension ?? detectSpkExtension(bytes);
    final chosen = await getSaveLocation(
      suggestedName: '${record.technicalName}${ext}',
    );
    if (chosen == null) return;
    final target = File(chosen.path);
    if (await target.exists()) {
      if (!mounted) return;
      final replace = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('El archivo ya existe'),
          content: Text('¿Reemplazar ${target.path}?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Reemplazar'),
            ),
          ],
        ),
      );
      if (replace != true) return;
    }
    await target.writeAsBytes(bytes, flush: true);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Extraído: ${target.path}')));
    }
  }

  Future<void> extractAll() async {
    if (extracting) return;
    final parent = await getDirectoryPath(
      confirmButtonText: 'Guardar extracción SPK aquí',
    );
    if (parent == null || !mounted) return;
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '')
        .replaceAll('-', '')
        .split('.')
        .first;
    final destination = Directory(
      '${parent}${Platform.pathSeparator}DATA_SPK_${stamp}',
    );
    setState(() {
      extracting = true;
      cancelExtraction = false;
      extraction = SpkExtractionProgress(
        completed: 0,
        total: source.simpleCount + source.chunkedCount,
        extracted: 0,
        skipped: 0,
        failed: 0,
      );
    });
    Map<String, Object?>? report;
    Object? error;
    try {
      report = await source.extractAll(
        destination,
        cancelled: () => cancelExtraction,
        progress: (p) {
          if (mounted) setState(() => extraction = p);
        },
      );
    } catch (e) {
      error = e;
    } finally {
      if (mounted) setState(() => extracting = false);
    }
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
      return;
    }
    final result = report!['result'] as Map;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Extracción terminada'),
        content: SelectableText(
          'Carpeta: ${destination.path}\n\n'
          'Extraídos: ${result['extracted']}\n'
          'Fragmentados pendientes: ${result['skippedChunked']}\n'
          'Fallidos: ${result['failed']}\n\n'
          'SPK_MANIFEST.json conserva cada ID, offset, tamaño y resultado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<void> exportDiagnostics() async {
    final location = await getSaveLocation(
      suggestedName: 'Shaiya_SPK_diagnostico.json',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'JSON', extensions: ['json']),
      ],
    );
    if (location == null) return;
    await File(location.path).writeAsString(
      const JsonEncoder.withIndent('  ').convert(source.diagnostics()),
      flush: true,
    );
  }

  Widget folderTile(String id, String title, int count, IconData icon) =>
      ListTile(
        dense: true,
        selected: folder == id,
        leading: Icon(icon, size: 17),
        title: Text(title, style: const TextStyle(fontSize: 11)),
        trailing: Text('$count', style: const TextStyle(fontSize: 9)),
        onTap: () => setState(() => folder = id),
      );

  Widget leftTree() => Material(
    color: const Color(0xff131b27),
    child: Column(
      children: [
        ListTile(
          leading: const Icon(Icons.inventory_2_outlined),
          title: const Text(
            'data.spk',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            '${source.resources.length} recursos',
            style: const TextStyle(fontSize: 9),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            children: [
              folderTile(
                'all',
                'Todos los registros',
                source.records.length,
                Icons.folder_open,
              ),
              folderTile(
                'simple',
                'Recursos directos',
                source.simpleCount,
                Icons.description_outlined,
              ),
              folderTile(
                'chunked',
                'Fragmentados',
                source.chunkedCount,
                Icons.call_split,
              ),
              folderTile(
                'special',
                'Registros especiales',
                source.specialCount,
                Icons.settings_ethernet,
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 14, 8, 5),
                child: Text(
                  'CARPETAS TÉCNICAS POR ID',
                  style: TextStyle(fontSize: 9, color: Color(0xff8190a6)),
                ),
              ),
              for (final b in buckets)
                folderTile(
                  'bucket:${b.key}',
                  b.key.toUpperCase(),
                  b.value,
                  Icons.folder_outlined,
                ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget table() {
    final rows = visible;
    return Column(
      children: [
        Container(
          height: 34,
          color: const Color(0xff182231),
          child: const Row(
            children: [
              SizedBox(width: 38),
              Expanded(
                flex: 4,
                child: Text('Nombre / ID', style: TextStyle(fontSize: 10)),
              ),
              SizedBox(
                width: 74,
                child: Text('Tipo', style: TextStyle(fontSize: 10)),
              ),
              SizedBox(
                width: 104,
                child: Text('Guardado', style: TextStyle(fontSize: 10)),
              ),
              SizedBox(
                width: 104,
                child: Text('Decodificado', style: TextStyle(fontSize: 10)),
              ),
              SizedBox(
                width: 120,
                child: Text('Offset', style: TextStyle(fontSize: 10)),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: rows.length,
            itemExtent: 42,
            itemBuilder: (ctx, i) {
              final r = rows[i];
              final ext = detectedExtensions[r.entryId] ?? '';
              final selected = selectedOrdinal == r.ordinal;
              return InkWell(
                onTap: () => setState(() => selectedOrdinal = r.ordinal),
                onDoubleTap: () => preview(r),
                child: Container(
                  color: selected ? const Color(0xff273753) : null,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 34,
                        child: Icon(
                          r.type == 3
                              ? Icons.call_split
                              : r.type == 1
                              ? Icons.insert_drive_file_outlined
                              : Icons.settings_ethernet,
                          size: 16,
                          color: r.type == 3
                              ? const Color(0xffd7b779)
                              : const Color(0xffa7b8d2),
                        ),
                      ),
                      Expanded(
                        flex: 4,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '${r.technicalName}${ext}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 10),
                            ),
                            Text(
                              r.entryId,
                              style: const TextStyle(
                                fontSize: 9,
                                color: Color(0xff8292aa),
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 74,
                        child: Text(
                          r.type == 1
                              ? 'Directo'
                              : r.type == 3
                              ? '${r.chunks.length} bloques'
                              : 'Especial',
                          style: const TextStyle(fontSize: 9),
                        ),
                      ),
                      SizedBox(
                        width: 104,
                        child: Text(
                          _bytes(r.storedBytes),
                          style: const TextStyle(fontSize: 9),
                        ),
                      ),
                      SizedBox(
                        width: 104,
                        child: Text(
                          _bytes(r.decodedBytes),
                          style: const TextStyle(fontSize: 9),
                        ),
                      ),
                      SizedBox(
                        width: 120,
                        child: Text(
                          '0x${r.dataOffset.toRadixString(16).toUpperCase()}',
                          style: const TextStyle(
                            fontSize: 9,
                            fontFamily: 'monospace',
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

  Widget inspector() {
    final r = selected;
    if (r == null) {
      return const Center(
        child: Text(
          'Selecciona un recurso',
          style: TextStyle(fontSize: 11, color: Color(0xff8d9bb0)),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(
          r.technicalName,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        SelectableText(
          'ID: ${r.entryId}\n'
          'Ordinal: ${r.ordinal}\n'
          'Tipo: ${r.type}\n'
          'Offset: ${r.dataOffset}\n'
          'Almacenado: ${r.storedBytes}\n'
          'Decodificado: ${r.decodedBytes}\n'
          'Fragmentos: ${r.chunks.length}',
          style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: r.type == 1 ? () => preview(r) : null,
          icon: const Icon(Icons.visibility_outlined, size: 16),
          label: const Text('Abrir / previsualizar'),
        ),
        const SizedBox(height: 7),
        OutlinedButton.icon(
          onPressed: r.type == 1 ? () => extractOne(r) : null,
          icon: const Icon(Icons.save_alt, size: 16),
          label: const Text('Extraer este recurso'),
        ),
        if (r.type == 3) ...[
          const SizedBox(height: 12),
          const Text(
            'Este recurso está íntegramente enumerado, pero la extracción '
            'se mantiene bloqueada hasta validar el nonce de sus fragmentos. '
            'No se descarta ni se oculta.',
            style: TextStyle(
              fontSize: 10,
              height: 1.5,
              color: Color(0xffd3bd8e),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = extraction;
    return Scaffold(
      backgroundColor: const Color(0xff101722),
      appBar: AppBar(
        title: const Text('Explorador DATA.SPK'),
        actions: [
          TextButton.icon(
            onPressed: extracting ? null : extractAll,
            icon: const Icon(Icons.unarchive_outlined, size: 17),
            label: const Text('Extraer todo'),
          ),
          IconButton(
            tooltip: 'Exportar diagnóstico',
            onPressed: exportDiagnostics,
            icon: const Icon(Icons.receipt_long_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: const Color(0xff182231),
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search, size: 17),
                      hintText: 'Buscar ID, ordinal o nombre técnico',
                    ),
                    onChanged: (v) => setState(() => search = v),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${visible.length} elementos · '
                  '${_bytes(source.decodedBytesTotal)} decodificados',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xff91a2bb),
                  ),
                ),
              ],
            ),
          ),
          if (extracting && p != null)
            Container(
              color: const Color(0xff202a38),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Column(
                children: [
                  LinearProgressIndicator(
                    value: p.total == 0 ? null : p.completed / p.total,
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Extrayendo ${p.completed}/${p.total} · '
                          '${p.extracted} OK · ${p.skipped} pendientes · '
                          '${p.failed} fallidos',
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            setState(() => cancelExtraction = true),
                        child: const Text('Cancelar'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          Expanded(
            child: Row(
              children: [
                SizedBox(width: 214, child: leftTree()),
                const VerticalDivider(width: 1),
                Expanded(child: table()),
                const VerticalDivider(width: 1),
                SizedBox(width: 235, child: inspector()),
              ],
            ),
          ),
          Container(
            height: 30,
            color: const Color(0xff111823),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.centerLeft,
            child: Text(
              'Perfil ${source.profile.id} · índice autenticado · '
              '${source.simpleCount} directos · ${source.chunkedCount} fragmentados · '
              'las rutas originales no aparecen en claro en este índice',
              style: const TextStyle(fontSize: 9, color: Color(0xff8fa0b7)),
            ),
          ),
        ],
      ),
    );
  }
}

String _bytes(int value) {
  const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
  var x = value.toDouble();
  var unit = 0;
  while (x >= 1024 && unit < units.length - 1) {
    x /= 1024;
    unit++;
  }
  final digits = x >= 100 || unit == 0
      ? 0
      : x >= 10
      ? 1
      : 2;
  return '${x.toStringAsFixed(digits)} ${units[unit]}';
}
