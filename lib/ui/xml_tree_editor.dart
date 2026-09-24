import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/xml_tree_document.dart';
import '../data/library.dart';

class XmlTreeEditorPanel extends StatefulWidget {
  final Library library;
  final String path;
  final Uint8List initialBytes;

  const XmlTreeEditorPanel({
    super.key,
    required this.library,
    required this.path,
    required this.initialBytes,
  });

  @override
  State<XmlTreeEditorPanel> createState() => _XmlTreeEditorPanelState();
}

class _XmlTreeEditorPanelState extends State<XmlTreeEditorPanel> {
  late XmlTreeDocument document;
  int selected = 0;
  int revision = 0;
  bool dirty = false;
  bool busy = false;
  String filter = '';
  final Map<String, String> errors = {};

  @override
  void initState() {
    super.initState();
    document = XmlTreeDocument.parse(widget.initialBytes, widget.path);
  }

  List<XmlTreeNode> get visibleNodes {
    final query = filter.trim().toLowerCase();
    if (query.isEmpty) return document.nodes;
    return document.nodes
        .where(
          (node) =>
              node.name.toLowerCase().contains(query) ||
              node.path.toLowerCase().contains(query) ||
              node.attributes.entries.any(
                (entry) =>
                    entry.key.toLowerCase().contains(query) ||
                    entry.value.toLowerCase().contains(query),
              ) ||
              (node.leaf && node.text.toLowerCase().contains(query)),
        )
        .toList(growable: false);
  }

  Future<void> save() async {
    if (!dirty || busy) return;
    setState(() => busy = true);
    try {
      final encoded = document.encode();
      document.validateEncoded(encoded);
      await widget.library.writeResource(widget.path, encoded);
      final reparsed = XmlTreeDocument.parse(encoded, widget.path);
      if (!mounted) return;
      setState(() {
        document = reparsed;
        selected = selected.clamp(0, reparsed.nodes.length - 1).toInt();
        dirty = false;
        errors.clear();
        revision++;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${widget.path.split('/').last} guardado y revalidado '
            'sin cambiar la estructura XML.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget nodeList() {
    final nodes = visibleNodes;
    return Material(
      color: const Color(0xff131b26),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Buscar nodo, atributo o valor…',
                prefixIcon: Icon(Icons.search, size: 18),
              ),
              onChanged: (value) => setState(() => filter = value),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: nodes.length,
              itemBuilder: (_, index) {
                final node = nodes[index];
                final active = node.index == selected;
                final attrs = node.attributes.entries
                    .take(2)
                    .map((entry) => '${entry.key}=${entry.value}')
                    .join(' · ');
                return InkWell(
                  onTap: () => setState(() => selected = node.index),
                  child: Container(
                    color: active ? const Color(0xff29384f) : null,
                    padding: EdgeInsets.fromLTRB(
                      8 + node.depth.clamp(0, 12) * 11.0,
                      6,
                      8,
                      6,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          node.leaf
                              ? Icons.data_object_outlined
                              : Icons.account_tree_outlined,
                          size: 14,
                          color: const Color(0xff8ea3c4),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                node.name,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (attrs.isNotEmpty)
                                Text(
                                  attrs,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 8,
                                    color: Color(0xff8495ae),
                                  ),
                                ),
                            ],
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
      ),
    );
  }

  Widget inspector() {
    if (document.nodes.isEmpty) {
      return const Center(child: Text('XML sin elementos.'));
    }
    final node = document.nodes[selected.clamp(0, document.nodes.length - 1)];
    final attrs = node.attributes;
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                node.name,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Copiar ruta XML',
              onPressed: () => Clipboard.setData(
                ClipboardData(text: node.path),
              ),
              icon: const Icon(Icons.copy_all_outlined, size: 17),
            ),
          ],
        ),
        SelectableText(
          node.path,
          style: const TextStyle(
            fontFamily: 'Consolas',
            fontSize: 9,
            color: Color(0xff8fa0b8),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${attrs.length} atributos · ${node.childElements} hijos',
          style: const TextStyle(fontSize: 9, color: Color(0xff8fa0b8)),
        ),
        const Divider(height: 22),
        if (attrs.isEmpty)
          const Text(
            'Sin atributos editables.',
            style: TextStyle(fontSize: 10, color: Color(0xff8fa0b8)),
          ),
        for (final entry in attrs.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TextFormField(
              key: ValueKey(
                'attr-$revision-${node.index}-${entry.key}-${entry.value}',
              ),
              initialValue: entry.value,
              enabled: !busy,
              maxLines: null,
              style: const TextStyle(fontSize: 10),
              decoration: InputDecoration(
                labelText: '@${entry.key}',
                errorText: errors['${node.index}/${entry.key}'],
                errorMaxLines: 2,
              ),
              onChanged: (value) {
                final key = '${node.index}/${entry.key}';
                try {
                  document.setAttribute(node.index, entry.key, value);
                  setState(() {
                    dirty = true;
                    errors.remove(key);
                  });
                } catch (error) {
                  setState(() {
                    errors[key] = error
                        .toString()
                        .replaceFirst('FormatException: ', '');
                  });
                }
              },
            ),
          ),
        const Divider(height: 22),
        if (node.leaf)
          TextFormField(
            key: ValueKey('text-$revision-${node.index}-${node.text}'),
            initialValue: node.text,
            enabled: !busy,
            minLines: 1,
            maxLines: 8,
            style: const TextStyle(fontSize: 10),
            decoration: InputDecoration(
              labelText: 'Texto del nodo',
              helperText:
                  'Solo texto de hoja; Studio no sustituye nodos hijos.',
              helperStyle: const TextStyle(fontSize: 8),
              errorText: errors['${node.index}/#text'],
            ),
            onChanged: (value) {
              final key = '${node.index}/#text';
              try {
                document.setLeafText(node.index, value);
                setState(() {
                  dirty = true;
                  errors.remove(key);
                });
              } catch (error) {
                setState(() {
                  errors[key] = error
                      .toString()
                      .replaceFirst('FormatException: ', '');
                });
              }
            },
          )
        else
          const Text(
            'Este nodo contiene hijos. Su contenido se edita nodo por nodo.',
            style: TextStyle(fontSize: 9, color: Color(0xff8fa0b8)),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        color: const Color(0xff172131),
        child: Row(
          children: [
            const Icon(Icons.account_tree_outlined, size: 17),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                '${widget.path.split('/').last} · raíz <${document.rootName}> · '
                '${document.nodes.length} nodos',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: busy || !dirty || errors.isNotEmpty ? null : save,
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
      const Padding(
        padding: EdgeInsets.fromLTRB(12, 7, 12, 7),
        child: Text(
          'Editor estructurado: modifica únicamente valores existentes. '
          'Nombres de nodos, jerarquía y atributos disponibles permanecen '
          'bloqueados para no inventar un schema del cliente.',
          style: TextStyle(fontSize: 9, color: Color(0xff8fa0b8)),
        ),
      ),
      Expanded(
        child: Row(
          children: [
            SizedBox(width: 360, child: nodeList()),
            const VerticalDivider(width: 1),
            Expanded(child: inspector()),
          ],
        ),
      ),
    ],
  );
}
