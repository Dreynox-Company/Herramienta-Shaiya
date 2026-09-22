import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../core/client_locale.dart';
import '../core/game_text_codec.dart';
import '../editor/document.dart';
import '../editor/schema_reader.dart';
import '../editor/field_semantics.dart';
import '../editor/relations.dart';
import '../editor/workbench_model.dart';
import 'editor_icons.dart';
import 'editor_style.dart';

class RelatedRow {
  final String path, relation;
  final int row;
  final RecordSummary summary;
  RelatedRow(this.path, this.row, this.relation, this.summary);
}

Future<RelatedRow?> showEditorRelations(
  BuildContext context,
  EditorImages images,
  EditDocument doc,
  int row,
  Map<String, EditDocument> cache,
) => showDialog<RelatedRow>(
  context: context,
  builder: (c) =>
      _RelationsDialog(images: images, document: doc, row: row, cache: cache),
);
EditDocument _parse((Uint8List, String, GameTextEncoding) data) =>
    EditorReader.open(data.$1, data.$2, encoding: data.$3);

class _RelationsDialog extends StatefulWidget {
  final EditorImages images;
  final EditDocument document;
  final int row;
  final Map<String, EditDocument> cache;
  const _RelationsDialog({
    required this.images,
    required this.document,
    required this.row,
    required this.cache,
  });
  @override
  State<_RelationsDialog> createState() => _RelationsDialogState();
}

class _RelationsDialogState extends State<_RelationsDialog> {
  final search = TextEditingController();
  final result = <RelatedRow>[], warnings = <String>[];
  bool loading = true, closed = false;
  int budget = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    closed = true;
    search.dispose();
    super.dispose();
  }

  Future<EditDocument> read(String path) async {
    final existing = widget.cache[path];
    if (existing != null) return existing;
    final bytes = await widget.images.library.read(
      path,
      limit: 64 * 1024 * 1024,
    );
    budget += bytes.length;
    if (budget > 128 * 1024 * 1024) {
      throw const FormatException(
        'Presupuesto de lectura de referencias alcanzado (128 MiB).',
      );
    }
    return compute(_parse, (
      bytes,
      path,
      ClientLocale.encodingForPath(
        path,
        fallback: widget.document.codec.encoding,
      ),
    ));
  }

  Future<void> load() async {
    try {
      final relations = recordRelations(widget.document, widget.row),
          files = widget.images.library.files.keys.toList();
      if (relations.isEmpty) {
        warnings.add(
          'Este registro no contiene referencias tipadas conocidas. Los números sin contrato de referencia no se interpretan como IDs.',
        );
      }
      for (final family in relations.map((r) => r.family).toSet()) {
        if (closed) break;
        final name = family == 'item' || family == 'grade'
            ? 'dbitemdata.sdata'
            : family == 'monster'
            ? 'dbmonsterdata.sdata'
            : family == 'npcskill'
            ? 'dbnpcskilldata.sdata'
            : 'dbskilldata.sdata';
        final available = files
            .where((p) => p.split('/').last == name)
            .toList();
        final local = available
            .where(
              (p) =>
                  ClientLocale.directory(p) ==
                  ClientLocale.directory(widget.document.path),
            )
            .toList();
        final candidates = local.isNotEmpty ? local : available;
        if (candidates.isEmpty) {
          warnings.add('No se encontró $name para resolver $family.');
          continue;
        }
        for (final path in candidates) {
          if (closed) break;
          try {
            final d = await read(path), names = <String, String>{};
            final prefix = ClientLocale.nameFamily(path);
            final text = prefix == null
                ? <String>[]
                : ClientLocale.tableCandidates(files, prefix, beside: path);
            if (text.isNotEmpty) {
              try {
                final n = await read(text.first);
                for (var i = 0; i < n.rows.length; i++) {
                  final fs = n.fields(i),
                      f = fs.where((s) => s.spec.text).firstOrNull;
                  if (f == null) continue;
                  final v = {
                    for (final field in fs)
                      if (field.spec.type != 'opaque')
                        field.spec.name.toLowerCase(): n.read(field),
                  };
                  names[editorIdentityKey(v, n.rows[i])] = n.read(f).trim();
                }
              } catch (e) {
                warnings.add('Nombres de $path: $e');
              }
            }
            final requests = relations
                .where((r) => r.family == family)
                .toList();
            for (var i = 0; i < d.rows.length; i++) {
              final s = RecordSummary.from(d, i);
              final links = requests
                  .where((r) => matchesRelation(r, s.values, d.rows[i]))
                  .toList();
              if (links.isEmpty) continue;
              result.add(
                RelatedRow(
                  path,
                  i,
                  links.map((r) => '${r.label} ${r.key}').join(' · '),
                  RecordSummary.from(d, i, name: names[s.id]),
                ),
              );
              if (result.length >= 5000) {
                warnings.add(
                  'Se muestran los primeros 5.000 resultados. Acota el registro de origen.',
                );
                break;
              }
            }
          } catch (e) {
            warnings.add('$path: $e');
          }
          if (result.length >= 5000) break;
        }
      }
    } catch (e) {
      warnings.add('$e');
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final q = foldedSearch(search.text),
        visible = result
            .where(
              (r) =>
                  q.isEmpty ||
                  foldedSearch(
                    '${r.summary.id} ${r.summary.name} ${r.path}',
                  ).contains(q),
            )
            .toList();
    return AlertDialog(
      title: const Text('Referencias del registro'),
      content: SizedBox(
        width: 820,
        height: 540,
        child: Column(
          children: [
            const Text(
              'Los grupos de botín se relacionan por Grade; las tablas del cliente no sustituyen las reglas del servidor. Se muestra la ruta de cada origen.',
              style: TextStyle(color: EditorStyle.muted, fontSize: 11),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Buscar en referencias…',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            if (loading) const LinearProgressIndicator(),
            Expanded(
              child: ListView.builder(
                itemCount: visible.length,
                itemBuilder: (c, i) {
                  final r = visible[i];
                  return ListTile(
                    dense: true,
                    leading: DataIcon(
                      images: widget.images,
                      path: r.path,
                      summary: r.summary,
                    ),
                    title: Text(
                      '${r.summary.id} · ${r.summary.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${r.relation}\n${r.path}',
                      style: const TextStyle(fontSize: 10),
                    ),
                    onTap: () => Navigator.pop(context, r),
                  );
                },
              ),
            ),
            if (warnings.isNotEmpty)
              SizedBox(
                height: 80,
                child: SingleChildScrollView(
                  child: Text(
                    warnings.join('\n'),
                    style: const TextStyle(fontSize: 10, color: Colors.orange),
                  ),
                ),
              ),
            Text(
              '${visible.length} referencias · selecciona una para abrir su editor',
              style: const TextStyle(fontSize: 10),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}
