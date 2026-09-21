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
  State<SpkBrowserPage> createState() => _SpkBrowserState();
}

class _SpkBrowserState extends State<SpkBrowserPage> {
  String scope = 'all', search = '';
  String? idRange;
  SpkRecord? current;
  final selected = <String>{};
  final typeCache = <String, String>{};
  bool working = false, cancelRequested = false;
  double progress = 0;
  String status = 'Catálogo SPK listo.';

  SpkSource get source => widget.source;

  List<SpkRecord> get visible {
    final q = search.trim().toLowerCase();
    final rows = source.records
        .where((r) {
          if (scope == 'simple' && r.type != 1) return false;
          if (scope == 'chunked' && r.type != 3) return false;
          if (scope == 'special' && (r.type == 1 || r.type == 3)) return false;
          if (idRange != null && !r.entryId.startsWith(idRange!)) return false;
          if (q.isNotEmpty &&
              !r.entryId.contains(q) &&
              !r.ordinal.toString().contains(q) &&
              !(typeCache[r.entryId] ?? '').contains(q)) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
    return rows;
  }

  String _bytes(int value) {
    const units = ['B', 'KiB', 'MiB', 'GiB'];
    var n = value.toDouble(), i = 0;
    while (n >= 1024 && i < units.length - 1) {
      n /= 1024;
      i++;
    }
    return '${n.toStringAsFixed(i == 0 ? 0 : 1)} ${units[i]}';
  }

  String _kind(SpkRecord r) {
    if (r.type == 1) return 'Recurso';
    if (r.type == 3) return 'Fragmentado · ${r.chunks.length} bloques';
    return 'Especial · tipo ${r.type}';
  }

  Future<void> _preview(SpkRecord record) async {
    if (working) return;
    setState(() {
      working = true;
      status = 'Leyendo ${record.entryId}…';
    });
    try {
      if (record.type != 1) {
        throw SpkFailure(
          'SPK_PREVIEW_FRAGMENTED',
          'La vista decodificada de recursos fragmentados se habilitará cuando '
              'su nonce implícito quede validado. Puedes extraer su bloque RAW sin perderlo.',
          {'chunks': record.chunks.length},
        );
      }
      final bytes = await source.read(record.entryId, limit: 64 * 1024 * 1024);
      final ext = detectSpkExtension(bytes);
      typeCache[record.entryId] = ext;
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${record.technicalName}$ext'),
          content: SizedBox(
            width: 820,
            height: 520,
            child: _previewBody(bytes, ext),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
      if (mounted)
        setState(() => status = 'Recurso autenticado y decodificado.');
    } catch (e) {
      _error(e);
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Widget _previewBody(Uint8List bytes, String ext) {
    if (['.txt', '.xml'].contains(ext)) {
      return SingleChildScrollView(
        child: SelectableText(
          _decodeText(bytes),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
        ),
      );
    }
    if (['.png', '.jpg'].contains(ext)) {
      return InteractiveViewer(
        minScale: .25,
        maxScale: 8,
        child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
      );
    }
    final head = bytes.take(4096).toList();
    final hex = StringBuffer();
    for (var i = 0; i < head.length; i += 16) {
      final row = head.skip(i).take(16).toList();
      hex.write('${i.toRadixString(16).padLeft(8, '0')}  ');
      hex.write(row.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' '));
      hex.write('\n');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${_bytes(bytes.length)} · formato detectado $ext · primeros ${_bytes(head.length)}',
          style: const TextStyle(fontSize: 11, color: Color(0xff9fb0c8)),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: SingleChildScrollView(
            child: SelectableText(
              hex.toString(),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
            ),
          ),
        ),
      ],
    );
  }

  String _decodeText(Uint8List bytes) {
    if (bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xfe) {
      final out = <int>[];
      for (var i = 2; i + 1 < bytes.length; i += 2) {
        out.add(bytes[i] | (bytes[i + 1] << 8));
      }
      return String.fromCharCodes(out);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  Future<Directory?> _newOutput(String prefix) async {
    final root = await getDirectoryPath(confirmButtonText: 'Usar esta carpeta');
    if (root == null) return null;
    final stamp = DateTime.now().toIso8601String().replaceAll(
      RegExp(r'[:.]'),
      '-',
    );
    final dir = Directory('$root${Platform.pathSeparator}${prefix}_$stamp');
    if (await dir.exists()) {
      throw const SpkFailure(
        'SPK_OUTPUT_EXISTS',
        'La carpeta de salida ya existe.',
      );
    }
    await dir.create(recursive: true);
    return dir;
  }

  Future<void> _extractSelection() async {
    if (working || selected.isEmpty) return;
    final output = await _newOutput('Shaiya_SPK_Seleccion');
    if (output == null) return;
    final data = Directory('${output.path}${Platform.pathSeparator}DATA');
    await data.create();
    setState(() {
      working = true;
      cancelRequested = false;
      progress = 0;
      status = 'Extrayendo ${selected.length} elementos…';
    });
    var done = 0, decoded = 0, raw = 0, failed = 0;
    final manifest = <Map<String, Object?>>[];
    try {
      for (final id in selected.toList()) {
        if (cancelRequested) break;
        final r = source.byId[id];
        if (r == null) continue;
        try {
          String relative;
          if (r.type == 1) {
            final bytes = await source.read(r.entryId, limit: 64 * 1024 * 1024);
            final ext = detectSpkExtension(bytes);
            typeCache[r.entryId] = ext;
            relative =
                'Recursos/${r.entryId.substring(0, 2)}/${r.technicalName}$ext';
            await _writeRelative(data, relative, bytes);
            decoded++;
          } else if (r.type == 3) {
            final bytes = await source.readRaw(r);
            relative =
                'Fragmentados_RAW/${r.entryId.substring(0, 2)}/${r.technicalName}.spkraw';
            await _writeRelative(data, relative, bytes);
            raw++;
          } else {
            relative = 'Especiales/${r.technicalName}.json';
            await _writeRelative(
              data,
              relative,
              Uint8List.fromList(
                utf8.encode(
                  const JsonEncoder.withIndent('  ').convert(r.toJson()),
                ),
              ),
            );
          }
          manifest.add({
            ...r.toJson(),
            'output': relative,
            'status': r.type == 3 ? 'raw' : 'decoded',
          });
        } catch (e) {
          failed++;
          manifest.add({
            ...r.toJson(),
            'status': 'failed',
            'error': e.toString(),
          });
        }
        done++;
        if (mounted) {
          setState(() {
            progress = done / selected.length;
            status =
                'Extracción: $done/${selected.length} · decodificados $decoded · RAW $raw · fallos $failed';
          });
        }
      }
      await File(
        '${output.path}${Platform.pathSeparator}SPK_MANIFEST.json',
      ).writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'schema': 1,
          'source': source.diagnostics(),
          'result': {
            'requested': selected.length,
            'completed': done,
            'decoded': decoded,
            'rawFragmented': raw,
            'failed': failed,
            'cancelled': cancelRequested,
          },
          'entries': manifest,
        }),
        flush: true,
      );
      if (mounted) {
        setState(() => status = 'Extracción terminada en ${output.path}');
      }
    } catch (e) {
      _error(e);
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> _extractAll() async {
    if (working) return;
    final output = await _newOutput('Shaiya_SPK_Extraido');
    if (output == null) return;
    final data = Directory('${output.path}${Platform.pathSeparator}DATA');
    await data.create();
    setState(() {
      working = true;
      cancelRequested = false;
      progress = 0;
      status = 'Extrayendo catálogo completo…';
    });
    try {
      final result = await source.extractAll(
        data,
        cancelled: () => cancelRequested,
        progress: (p) {
          if (!mounted) return;
          setState(() {
            progress = p.total == 0 ? 0 : p.completed / p.total;
            status =
                'Extracción ${p.completed}/${p.total} · decodificados ${p.extracted} · RAW ${p.skipped} · fallos ${p.failed}';
          });
        },
      );
      await File(
        '${output.path}${Platform.pathSeparator}SPK_RESUMEN.json',
      ).writeAsString(
        const JsonEncoder.withIndent('  ').convert(result),
        flush: true,
      );
      if (mounted)
        setState(() => status = 'Extracción completa: ${output.path}');
    } catch (e) {
      _error(e);
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> _writeRelative(
    Directory root,
    String relative,
    Uint8List bytes,
  ) async {
    final file = File(
      '${root.path}${Platform.pathSeparator}${relative.replaceAll('/', Platform.pathSeparator)}',
    );
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: false);
  }

  Future<void> _exportCatalog() async {
    final location = await getSaveLocation(
      suggestedName: 'catalogo_spk.json',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'JSON', extensions: ['json']),
      ],
    );
    if (location == null) return;
    final payload = {
      'schema': 1,
      'source': source.diagnostics(),
      'records': source.records.map((r) => r.toJson()).toList(),
    };
    await File(location.path).writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      flush: true,
    );
    if (mounted)
      setState(() => status = 'Catálogo exportado: ${location.path}');
  }

  void _error(Object e) {
    if (!mounted) return;
    setState(() => status = e.toString());
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(e.toString())));
  }

  @override
  Widget build(BuildContext context) {
    final rows = visible;
    return Scaffold(
      backgroundColor: const Color(0xff0f1621),
      appBar: AppBar(
        title: const Text('Explorador DATA.SPK'),
        actions: [
          IconButton(
            tooltip: 'Exportar catálogo JSON',
            onPressed: working ? null : _exportCatalog,
            icon: const Icon(Icons.data_object),
          ),
          IconButton(
            tooltip: 'Extraer selección',
            onPressed: working || selected.isEmpty ? null : _extractSelection,
            icon: const Icon(Icons.file_download_outlined),
          ),
          FilledButton.icon(
            onPressed: working ? null : _extractAll,
            icon: const Icon(Icons.inventory_2_outlined, size: 17),
            label: const Text('Extraer todo a DATA'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(
        children: [
          _summary(),
          if (working)
            LinearProgressIndicator(value: progress == 0 ? null : progress),
          Expanded(
            child: Row(
              children: [
                _folders(),
                const VerticalDivider(width: 1),
                Expanded(child: _listing(rows)),
              ],
            ),
          ),
          _footer(),
        ],
      ),
    );
  }

  Widget _summary() => Container(
    padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
    color: const Color(0xff151e2b),
    child: Row(
      children: [
        const Icon(Icons.archive_outlined, size: 20, color: Color(0xffa9bfff)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                source.fileName,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                '${_bytes(source.fileSize)} · ${source.profile.id} · índice autenticado AES-GCM + Zstandard',
                style: const TextStyle(fontSize: 10, color: Color(0xff92a2ba)),
              ),
            ],
          ),
        ),
        _metric('${source.simpleCount}', 'directos'),
        _metric('${source.chunkedCount}', 'fragmentados'),
        _metric('${source.specialCount}', 'especiales'),
      ],
    ),
  );

  Widget _metric(String value, String label) => Padding(
    padding: const EdgeInsets.only(left: 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 9, color: Color(0xff8190a7)),
        ),
      ],
    ),
  );

  Widget _folders() => SizedBox(
    width: 245,
    child: ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _scopeTile(
          'all',
          'Todo el archivo',
          source.records.length,
          Icons.folder_copy_outlined,
        ),
        _scopeTile(
          'simple',
          'Recursos decodificables',
          source.simpleCount,
          Icons.folder_outlined,
        ),
        _scopeTile(
          'chunked',
          'Recursos fragmentados',
          source.chunkedCount,
          Icons.call_split_outlined,
        ),
        _scopeTile(
          'special',
          'Registros especiales',
          source.specialCount,
          Icons.settings_input_component_outlined,
        ),
        const Divider(height: 22),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 5),
          child: Text(
            'RANGOS DE ID',
            style: TextStyle(
              fontSize: 9,
              letterSpacing: 1.1,
              color: Color(0xff798aa5),
            ),
          ),
        ),
        ListTile(
          dense: true,
          selected: idRange == null,
          leading: const Icon(Icons.grid_view, size: 16),
          title: const Text('Todos los rangos', style: TextStyle(fontSize: 11)),
          onTap: () => setState(() => idRange = null),
        ),
        for (final c in '0123456789abcdef'.split(''))
          ListTile(
            dense: true,
            selected: idRange == c,
            leading: const Icon(Icons.folder_open, size: 16),
            title: Text(
              '$c…',
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            ),
            onTap: () => setState(() => idRange = c),
          ),
      ],
    ),
  );

  Widget _scopeTile(String id, String label, int count, IconData icon) =>
      ListTile(
        dense: true,
        selected: scope == id,
        leading: Icon(icon, size: 17),
        title: Text(label, style: const TextStyle(fontSize: 11)),
        trailing: Text(
          '$count',
          style: const TextStyle(fontSize: 9, color: Color(0xff8190a7)),
        ),
        onTap: () => setState(() => scope = id),
      );

  Widget _listing(List<SpkRecord> rows) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search, size: 18),
                  hintText: 'Buscar ID, ordinal o formato detectado…',
                ),
                onChanged: (v) => setState(() => search = v),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${rows.length} elementos',
              style: const TextStyle(fontSize: 10, color: Color(0xff8fa0b8)),
            ),
          ],
        ),
      ),
      Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        color: const Color(0xff141d29),
        child: const Row(
          children: [
            SizedBox(width: 38),
            Expanded(
              flex: 4,
              child: Text('Nombre / ID', style: TextStyle(fontSize: 10)),
            ),
            Expanded(
              flex: 3,
              child: Text('Tipo', style: TextStyle(fontSize: 10)),
            ),
            SizedBox(
              width: 90,
              child: Text('Almacenado', style: TextStyle(fontSize: 10)),
            ),
            SizedBox(
              width: 90,
              child: Text('Decodificado', style: TextStyle(fontSize: 10)),
            ),
            SizedBox(
              width: 110,
              child: Text('Offset', style: TextStyle(fontSize: 10)),
            ),
          ],
        ),
      ),
      Expanded(
        child: ListView.builder(
          itemCount: rows.length,
          itemExtent: 48,
          itemBuilder: (ctx, i) {
            final r = rows[i], checked = selected.contains(r.entryId);
            final ext = typeCache[r.entryId];
            return Material(
              color: identical(current, r)
                  ? const Color(0xff202f44)
                  : Colors.transparent,
              child: InkWell(
                onTap: () => setState(() => current = r),
                onDoubleTap: r.type == 1 ? () => _preview(r) : null,
                child: Row(
                  children: [
                    SizedBox(
                      width: 38,
                      child: Checkbox(
                        value: checked,
                        onChanged: (_) => setState(() {
                          if (!selected.add(r.entryId))
                            selected.remove(r.entryId);
                        }),
                      ),
                    ),
                    Expanded(
                      flex: 4,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${r.technicalName}${ext ?? ''}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                          ),
                          Text(
                            '#${r.ordinal} · ${r.entryId}',
                            style: const TextStyle(
                              fontSize: 9,
                              color: Color(0xff7e8fa8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        _kind(r),
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                    SizedBox(
                      width: 90,
                      child: Text(
                        _bytes(r.storedBytes),
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                    SizedBox(
                      width: 90,
                      child: Text(
                        _bytes(r.decodedBytes),
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                    SizedBox(
                      width: 110,
                      child: Text(
                        '0x${r.dataOffset.toRadixString(16)}',
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
      if (current != null) _details(current!),
    ],
  );

  Widget _details(SpkRecord r) => Container(
    padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
    decoration: const BoxDecoration(
      color: Color(0xff141d29),
      border: Border(top: BorderSide(color: Color(0xff29384c))),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            '${r.entryId} · ${_kind(r)} · offset ${r.dataOffset} · almacenado ${_bytes(r.storedBytes)} · esperado ${_bytes(r.decodedBytes)}',
            style: const TextStyle(fontSize: 10, color: Color(0xff9dafc8)),
          ),
        ),
        OutlinedButton.icon(
          onPressed: working || r.type != 1 ? null : () => _preview(r),
          icon: const Icon(Icons.visibility_outlined, size: 15),
          label: const Text('Abrir / previsualizar'),
        ),
        const SizedBox(width: 7),
        FilledButton.tonalIcon(
          onPressed: working
              ? null
              : () {
                  setState(() => selected.add(r.entryId));
                  _extractSelection();
                },
          icon: const Icon(Icons.save_alt, size: 15),
          label: Text(r.type == 3 ? 'Guardar RAW' : 'Extraer'),
        ),
      ],
    ),
  );

  Widget _footer() => Container(
    minHeight: 36,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
    color: const Color(0xff111925),
    child: Row(
      children: [
        Icon(
          working ? Icons.sync : Icons.lock_outline,
          size: 13,
          color: working ? const Color(0xffd7bd80) : const Color(0xff8eb9a1),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            status,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10),
          ),
        ),
        if (working)
          TextButton.icon(
            onPressed: () => setState(() => cancelRequested = true),
            icon: const Icon(Icons.stop_circle_outlined, size: 15),
            label: const Text('Cancelar'),
          ),
      ],
    ),
  );
}
