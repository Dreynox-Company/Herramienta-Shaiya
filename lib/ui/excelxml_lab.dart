import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/excelxml_document.dart';
import '../data/library.dart';

class ExcelXmlLabPage extends StatefulWidget {
  final Library library;
  final String? initialPath;

  const ExcelXmlLabPage({
    super.key,
    required this.library,
    this.initialPath,
  });

  @override
  State<ExcelXmlLabPage> createState() => _ExcelXmlLabPageState();
}

class _ExcelXmlLabPageState extends State<ExcelXmlLabPage> {
  @override
  void initState() {
    super.initState();
    final initial = widget.initialPath;
    if (initial != null && widget.library.files.containsKey(initial)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) openPath(initial);
      });
    }
  }

  String filter = '';
  String rowFilter = '';
  String? selectedPath;
  ExcelXmlDocument? document;
  Uint8List? sourceBytes;
  String? rawText;
  bool rawDirty = false;
  String? loadError;
  bool busy = false;
  int sheetIndex = 0;
  int? selectedRow;
  int revision = 0;

  List<String> get paths {
    final values =
        widget.library.files.keys
            .where(
              (path) => path.startsWith('excelxml/') && path.endsWith('.xml'),
            )
            .where(
              (path) =>
                  filter.isEmpty ||
                  path.toLowerCase().contains(filter.toLowerCase()) ||
                  excelXmlPurpose(
                    path,
                  ).toLowerCase().contains(filter.toLowerCase()),
            )
            .toList()
          ..sort();
    return values;
  }

  Future<void> openPath(String path) async {
    if (busy) return;
    setState(() {
      busy = true;
      selectedPath = path;
      document = null;
      sourceBytes = null;
      rawText = null;
      rawDirty = false;
      loadError = null;
      selectedRow = null;
      sheetIndex = 0;
      rowFilter = '';
    });
    try {
      final bytes = await widget.library.read(
        path,
        limit: ExcelXmlDocument.maxBytes,
      );
      ExcelXmlDocument? parsed;
      String? error;
      try {
        parsed = ExcelXmlDocument.parse(bytes, path);
      } catch (e) {
        error = e.toString();
      }
      if (!mounted) return;
      setState(() {
        sourceBytes = bytes;
        document = parsed;
        rawText =
            parsed != null && !parsed.tabular && bytes.length <= 2 * 1024 * 1024
            ? utf8.decode(bytes, allowMalformed: false)
            : null;
        rawDirty = false;
        loadError = error;
      });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  List<int> visibleRows(ExcelXmlSheet sheet) {
    final query = rowFilter.trim().toLowerCase();
    if (query.isEmpty) {
      return List<int>.generate(sheet.rows.length, (i) => i);
    }
    final out = <int>[];
    for (var i = 0; i < sheet.rows.length; i++) {
      final row = sheet.rows[i];
      if (sheet.columns.any(
        (column) => row.value(column.index).toLowerCase().contains(query),
      )) {
        out.add(i);
      }
    }
    return out;
  }

  Future<void> saveRawXml() async {
    final path = selectedPath;
    final text = rawText;
    if (path == null || text == null || !rawDirty) return;
    setState(() => busy = true);
    try {
      final bytes = Uint8List.fromList(utf8.encode(text));
      final parsed = ExcelXmlDocument.parse(bytes, path);
      if (parsed.tabular) {
        throw const FormatException(
          'El XML ahora contiene una tabla SpreadsheetML; vuelve a abrirlo '
          'para editarla en modo estructurado.',
        );
      }
      parsed.validateEncoded(bytes);
      await widget.library.writeResource(path, bytes);
      if (!mounted) return;
      setState(() {
        sourceBytes = bytes;
        document = parsed;
        rawDirty = false;
        revision++;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${path.split('/').last} guardado como XML válido y revalidado.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    final doc = document;
    final path = selectedPath;
    if (doc == null || path == null) return;
    setState(() => busy = true);
    try {
      final encoded = doc.encode();
      doc.validateEncoded(encoded);
      await widget.library.writeResource(path, encoded);
      final reparsed = ExcelXmlDocument.parse(encoded, path);
      if (!mounted) return;
      setState(() {
        document = reparsed;
        sourceBytes = encoded;
        revision++;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${path.split('/').last} guardado y revalidado. '
            'Backup/overlay según la fuente DATA activa.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget fileList() => Material(
    color: const Color(0xff131b26),
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Buscar ExcelXml o función…',
              prefixIcon: Icon(Icons.search, size: 18),
            ),
            onChanged: (value) => setState(() => filter = value),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: paths.length,
            itemBuilder: (_, index) {
              final path = paths[index];
              final active = path == selectedPath;
              return ListTile(
                dense: true,
                selected: active,
                leading: Icon(
                  path.endsWith('wingposition.xml')
                      ? Icons.flight_outlined
                      : Icons.table_view_outlined,
                  size: 17,
                ),
                title: Text(
                  path.split('/').last,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
                subtitle: Text(
                  excelXmlPurpose(path),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 9),
                ),
                onTap: busy ? null : () => openPath(path),
              );
            },
          ),
        ),
      ],
    ),
  );

  Widget emptyPanel() {
    if (busy) {
      return const Center(
        child: SizedBox(width: 260, child: LinearProgressIndicator()),
      );
    }
    if (selectedPath == null) {
      return const Center(
        child: Text(
          'Selecciona una tabla de DATA/ExcelXml.',
          style: TextStyle(color: Color(0xff93a2ba)),
        ),
      );
    }
    final raw = sourceBytes;
    if (document == null) {
      final editable = rawText != null;
      final preview = raw == null
          ? ''
          : utf8.decode(
              raw.sublist(0, raw.length.clamp(0, 256 * 1024).toInt()),
              allowMalformed: true,
            );
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    loadError ?? 'XML no tabular.',
                    style: const TextStyle(
                      color: Color(0xffffb6a7),
                      fontSize: 11,
                    ),
                  ),
                ),
                if (editable)
                  FilledButton.icon(
                    onPressed: busy || !rawDirty ? null : saveRawXml,
                    icon: const Icon(Icons.build_outlined, size: 16),
                    label: const Text('Validar y guardar reparación'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              editable
                  ? 'El XML original no parsea. Puedes corregir el texto; '
                        'Studio solo permitirá guardarlo cuando el documento '
                        'completo vuelva a ser XML válido.'
                  : 'Vista de diagnóstico en solo lectura.',
              style: const TextStyle(fontSize: 9, color: Color(0xff8fa0b8)),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: editable
                  ? TextFormField(
                      key: ValueKey('repair-$revision-$selectedPath'),
                      initialValue: rawText,
                      enabled: !busy,
                      expands: true,
                      maxLines: null,
                      minLines: null,
                      textAlignVertical: TextAlignVertical.top,
                      style: const TextStyle(
                        fontFamily: 'Consolas',
                        fontSize: 10,
                      ),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        rawText = value;
                        if (!rawDirty) setState(() => rawDirty = true);
                      },
                    )
                  : SingleChildScrollView(
                      child: SelectableText(
                        preview,
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
    }

    if (!document!.tabular) {
      final editable = rawText != null;
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${selectedPath!.split('/').last} · '
                    '${excelXmlPurpose(selectedPath!)}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (editable)
                  FilledButton.icon(
                    onPressed: busy || !rawDirty ? null : saveRawXml,
                    icon: const Icon(Icons.save_outlined, size: 16),
                    label: const Text('Guardar XML'),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              editable
                  ? 'XML no tabular · edición de texto validada antes de '
                        'escribir. Studio no reordena nodos ni inventa campos.'
                  : 'XML válido no tabular. Vista de solo lectura porque supera '
                        'el límite de 2 MiB para edición textual segura.',
              style: const TextStyle(fontSize: 9, color: Color(0xff8fa0b8)),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: editable
                  ? TextFormField(
                      key: ValueKey('raw-$revision-$selectedPath'),
                      initialValue: rawText,
                      enabled: !busy,
                      expands: true,
                      maxLines: null,
                      minLines: null,
                      textAlignVertical: TextAlignVertical.top,
                      style: const TextStyle(
                        fontFamily: 'Consolas',
                        fontSize: 10,
                      ),
                      decoration: const InputDecoration(
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        rawText = value;
                        if (!rawDirty) setState(() => rawDirty = true);
                      },
                    )
                  : SingleChildScrollView(
                      child: SelectableText(
                        sourceBytes == null
                            ? ''
                            : utf8.decode(
                                sourceBytes!.sublist(
                                  0,
                                  sourceBytes!.length
                                      .clamp(0, 512 * 1024)
                                      .toInt(),
                                ),
                                allowMalformed: true,
                              ),
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
    }
    return const SizedBox.shrink();
  }

  Widget tablePanel() {
    final doc = document;
    if (doc == null || !doc.tabular) return emptyPanel();
    final sheet =
        doc.sheets[sheetIndex.clamp(0, doc.sheets.length - 1).toInt()];
    final rows = visibleRows(sheet);
    final visibleColumns = sheet.columns.take(7).toList(growable: false);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          color: const Color(0xff172131),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${selectedPath!.split('/').last} · '
                  '${excelXmlPurpose(selectedPath!)}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (doc.sheets.length > 1)
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<int>(
                    key: ValueKey('sheet-$revision-$sheetIndex'),
                    initialValue: sheetIndex,
                    items: [
                      for (var i = 0; i < doc.sheets.length; i++)
                        DropdownMenuItem(
                          value: i,
                          child: Text(doc.sheets[i].name),
                        ),
                    ],
                    onChanged: (value) => setState(() {
                      sheetIndex = value ?? 0;
                      selectedRow = null;
                    }),
                  ),
                ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: busy ? null : save,
                icon: const Icon(Icons.save_outlined, size: 16),
                label: Text(
                  widget.library.isSpkWorkspace
                      ? 'Guardar overlay'
                      : 'Guardar XML',
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
          child: TextField(
            decoration: InputDecoration(
              hintText:
                  'Filtrar ${sheet.rows.length} filas en todas las columnas…',
              prefixIcon: const Icon(Icons.filter_alt_outlined, size: 18),
            ),
            onChanged: (value) => setState(() => rowFilter = value),
          ),
        ),
        Container(
          height: 30,
          color: const Color(0xff182231),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              const SizedBox(width: 54, child: Text('#')),
              for (final column in visibleColumns)
                Expanded(
                  child: Text(
                    column.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 9),
                  ),
                ),
              if (sheet.columns.length > visibleColumns.length)
                SizedBox(
                  width: 72,
                  child: Text(
                    '+${sheet.columns.length - visibleColumns.length}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 9),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: rows.length,
            itemExtent: 34,
            itemBuilder: (_, index) {
              final rowIndex = rows[index];
              final row = sheet.rows[rowIndex];
              final active = selectedRow == rowIndex;
              return InkWell(
                onTap: () => setState(() => selectedRow = rowIndex),
                child: Container(
                  color: active ? const Color(0xff29384f) : null,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 54,
                        child: Text(
                          row.sourceRow.toString(),
                          style: const TextStyle(
                            fontFamily: 'Consolas',
                            fontSize: 9,
                          ),
                        ),
                      ),
                      for (final column in visibleColumns)
                        Expanded(
                          child: Text(
                            row.value(column.index),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 10),
                          ),
                        ),
                      if (sheet.columns.length > visibleColumns.length)
                        const SizedBox(width: 72),
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

  Widget rowEditor() {
    final doc = document;
    if (doc == null || !doc.tabular || selectedRow == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'Selecciona una fila para editar sus celdas existentes.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, color: Color(0xff93a2ba)),
          ),
        ),
      );
    }
    final sheet = doc.sheets[sheetIndex];
    final rowIndex = selectedRow!;
    final row = sheet.rows[rowIndex];
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(
          'Fila ${row.sourceRow} · ${sheet.name}',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        ),
        const SizedBox(height: 6),
        Text(
          '${sheet.columns.length} columnas · cabecera XML fila '
          '${sheet.headerRow}',
          style: const TextStyle(fontSize: 9, color: Color(0xff8fa0b8)),
        ),
        const Divider(height: 20),
        for (final column in sheet.columns)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: TextFormField(
              key: ValueKey(
                '$revision-$sheetIndex-$rowIndex-${column.index}-'
                '${row.value(column.index)}',
              ),
              initialValue: row.value(column.index),
              enabled: row.hasCell(column.index) && !busy,
              maxLines: null,
              style: const TextStyle(fontSize: 10),
              decoration: InputDecoration(
                labelText: column.label,
                helperText: row.hasCell(column.index)
                    ? 'C${column.index}'
                    : 'Celda ausente · no se inventa',
                helperStyle: const TextStyle(fontSize: 8),
              ),
              onChanged: row.hasCell(column.index)
                  ? (value) {
                      doc.setCell(sheetIndex, rowIndex, column.index, value);
                    }
                  : null,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xff101722),
    appBar: AppBar(
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ExcelXml Lab', style: TextStyle(fontSize: 14)),
          Text(
            'Tablas reales de DATA · edición transaccional',
            style: TextStyle(fontSize: 9, color: Color(0xff8e9bb0)),
          ),
        ],
      ),
    ),
    body: Row(
      children: [
        SizedBox(width: 290, child: fileList()),
        const VerticalDivider(width: 1),
        Expanded(child: document == null ? emptyPanel() : tablePanel()),
        if (document?.tabular == true) ...[
          const VerticalDivider(width: 1),
          SizedBox(width: 340, child: rowEditor()),
        ],
      ],
    ),
  );
}
