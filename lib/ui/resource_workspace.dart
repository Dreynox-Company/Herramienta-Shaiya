import 'dart:async';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/textures.dart';
import '../data/library.dart';
import '../data/resource_index.dart';
import '../editor/catalog_document.dart';
import '../editor/document.dart';
import '../editor/model_reference.dart';
import '../core/game_text_codec.dart';
import 'data_editor.dart';
import 'editor_model_preview.dart';

class ResourceSidebar extends StatefulWidget {
  final ResourceIndex index;
  final VoidCallback? onBrowseArchive, onResolveNames;
  const ResourceSidebar({
    super.key,
    required this.index,
    this.onBrowseArchive,
    this.onResolveNames,
  });
  @override
  State<ResourceSidebar> createState() => _ResourceSidebarState();
}

class _ResourceSidebarState extends State<ResourceSidebar> {
  String query = '', group = 'Todos';
  final search = TextEditingController();
  final scroll = ScrollController();
  @override
  void dispose() {
    search.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.index,
    builder: (context, _) {
      final index = widget.index, rows = index.filter(query, group);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${index.entries.length} entradas · ${index.readableCount} legibles',
            key: const ValueKey('resource-count'),
          ),
          if (index.blockedCount > 0)
            Text(
              '${index.blockedCount} bloqueadas: visibles, sin acceso a sus bytes.',
            ),
          const SizedBox(height: 8),
          TextField(
            controller: search,
            key: const ValueKey('resource-query'),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search, size: 17),
              hintText: 'Ruta, nombre o Entry ID',
            ),
            onChanged: (value) => setState(() {
              query = value;
              if (scroll.hasClients) scroll.jumpTo(0);
            }),
          ),
          DropdownButton<String>(
            value: group,
            isExpanded: true,
            items: [
              for (final value in const [
                'Todos',
                'Modelos',
                'Texturas',
                'Animaciones',
                'Tablas / texto',
                'Bloqueados',
                'Errores',
              ])
                DropdownMenuItem(value: value, child: Text(value)),
            ],
            onChanged: (value) => setState(() {
              group = value!;
              if (scroll.hasClients) scroll.jumpTo(0);
            }),
          ),
          if (index.library.spk != null) ...[
            Text(
              'Los nombres con ? son pistas, no rutas confirmadas.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Wrap(
              spacing: 2,
              children: [
                TextButton.icon(
                  onPressed: index.indexing
                      ? () => index.cancelled = true
                      : () => unawaited(index.scan(selection: rows)),
                  icon: Icon(
                    index.indexing ? Icons.stop : Icons.manage_search,
                    size: 16,
                  ),
                  label: Text(index.indexing ? 'Detener' : 'Indexar tipos'),
                ),
                if (widget.onBrowseArchive != null)
                  TextButton(
                    onPressed: index.indexing ? null : widget.onBrowseArchive,
                    child: const Text('Explorador SPK'),
                  ),
                if (widget.onResolveNames != null)
                  TextButton(
                    onPressed: index.indexing ? null : widget.onResolveNames,
                    child: const Text('Confirmar rutas'),
                  ),
              ],
            ),
          ],
          if (index.indexing) const LinearProgressIndicator(minHeight: 2),
          if (index.status.isNotEmpty)
            Text(index.status, maxLines: 2, overflow: TextOverflow.ellipsis),
          const Divider(),
          Text('${rows.length} resultados'),
          Expanded(
            child: rows.isEmpty
                ? const Center(
                    child: Text('Sin coincidencias. Cambia el filtro.'),
                  )
                : ListView.builder(
                    key: const ValueKey('resource-index-list'),
                    controller: scroll,
                    itemCount: rows.length,
                    itemExtent:
                        (MediaQuery.textScalerOf(context).scale(11) * 3 + 24)
                            .clamp(58, 180),
                    itemBuilder: (context, i) {
                      final entry = rows[i];
                      return Tooltip(
                        message:
                            '${entry.displayPath}\nID: ${entry.key}\n${entry.state}',
                        child: ListTile(
                          key: ValueKey('resource-${entry.key}'),
                          dense: true,
                          selected: identical(entry, index.selected),
                          leading: Icon(
                            !entry.readable
                                ? Icons.lock_outline
                                : entry.isModel
                                ? Icons.view_in_ar
                                : entry.isImage
                                ? Icons.image_outlined
                                : Icons.description_outlined,
                            size: 17,
                          ),
                          title: Text(
                            '${entry.confirmed ? '' : '? '}${entry.name}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${entry.kind} · ${entry.state}\n${entry.folder}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => index.select(entry),
                        ),
                      );
                    },
                  ),
          ),
        ],
      );
    },
  );
}

class ResourceDetails extends StatelessWidget {
  final ResourceIndex index;
  const ResourceDetails({super.key, required this.index});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: index,
    builder: (_, _) {
      final e = index.selected;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            index.library.sourceLabel,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const Divider(),
          if (e == null)
            const Text(
              'Selecciona un archivo a la izquierda. No es necesario un personaje completo para inspeccionar o editar recursos.',
            )
          else ...[
            SelectableText(e.displayPath),
            const SizedBox(height: 8),
            SelectableText(
              'Identidad: ${e.key}\nEstado: ${e.state}\nTipo: ${e.format ?? 'No verificado (${e.expectedFormat} sugerido)'}',
            ),
            if (e.record != null)
              Text(
                'Almacenado: ${e.record!.storedBytes} B\nDeclarado: ${e.record!.decodedBytes} B',
              ),
            const SizedBox(height: 8),
            if (!e.confirmed)
              const Text(
                'El nombre es orientativo. El editor usa el Entry ID real; no se renombra el archivo ni se confirma una ruta por su tamaño.',
              ),
            if (!e.readable)
              const Text(
                'Falta validar el perfil de lectura de este recurso. Los otros registros legibles permanecen disponibles.',
              ),
            if (e.error != null) SelectableText(e.error!),
            if (index.library.isSpkWorkspace) ...[
              const Divider(),
              const Text(
                'Los cambios se guardan en un overlay. DATA.SPK permanece intacto.',
              ),
              SelectableText(index.library.spkOverlayRoot ?? ''),
            ],
          ],
        ],
      );
    },
  );
}

class ResourcePreview extends StatefulWidget {
  final ResourceIndex index;
  final ResourceEntry? entry;
  final VoidCallback? onEdited;
  const ResourcePreview({
    super.key,
    required this.index,
    required this.entry,
    this.onEdited,
  });
  @override
  State<ResourcePreview> createState() => _ResourcePreviewState();
}

class _ResourcePreviewState extends State<ResourcePreview> {
  Future<ResourceRead>? load;
  Future<Uint8List>? image;
  Future<List<ModelReference>>? models;
  EditDocument? document;
  ResourceRead? current;
  ResourceEntry? texture;
  int row = 0, request = 0;
  bool busy = false, allowHints = false;
  String? error;

  @override
  void initState() {
    super.initState();
    start();
  }

  @override
  void didUpdateWidget(ResourcePreview old) {
    super.didUpdateWidget(old);
    if (old.entry != widget.entry || old.index != widget.index) start();
  }

  void start() {
    final generation = ++request;
    image = null;
    models = null;
    current = null;
    document = null;
    texture = null;
    row = 0;
    error = null;
    allowHints = false;
    final e = widget.entry;
    load = e == null || !e.readable
        ? null
        : widget.index.read(e).then((r) async {
            if (!mounted || generation != request) return r;
            current = r;
            if (const {
              'DDS',
              'PNG',
              'TGA',
              'BMP',
              'JPEG',
              'GIF',
            }.contains(r.format)) {
              image = compute(_resourcePng, (r.bytes, r.format));
            }
            if (const {
              'MLT',
              'ITM',
              'MON',
              'SDATA',
              'XML',
              'TXT',
              'INI',
              'JSON',
              'BIN',
            }.contains(r.format)) {
              final parsed = await compute(parseEditorDocument, {
                'bytes': r.bytes,
                'path': e.path!,
                'encoding': GameTextEncoding.automatic.name,
              });
              if (!mounted || generation != request) return r;
              document = parsed;
              final doc = parsed;
              if (doc is CatalogDocument) {
                for (var i = 0; i < doc.rows.length; i++) {
                  if (doc.materials(i).isNotEmpty) {
                    row = i;
                    break;
                  }
                }
                models = resolveModels(doc);
              }
            }
            return r;
          });
  }

  Future<List<ModelReference>> resolveModels(CatalogDocument doc) async {
    final e = widget.entry!;
    if (e.confirmed) {
      return ModelReferences.resolve(widget.index.library, doc, row);
    }
    final pairs = doc.materials(row);
    final root = directoryName(e.displayPath).toLowerCase();
    String locate(String name, bool mesh) {
      final roots = mesh
          ? ['$root/3dc', '$root/3do', root]
          : ['$root/dds', root];
      final canonical = widget.index.library.resolve(
        name,
        roots,
        uniqueFallback: false,
      );
      if (canonical != null) return canonical;
      if (allowHints) {
        final paths = {
          canon(name),
          for (final dir in roots) canon('$dir/$name'),
        };
        final candidates = widget.index.entries.where((c) {
          try {
            return c.readable && paths.contains(canon(c.displayPath));
          } catch (_) {
            return false;
          }
        }).toList();
        if (candidates.length == 1) return candidates.single.path!;
      }
      return name;
    }

    return [
      ModelReference('Registro #${doc.rows[row].ordinal}', [
        for (final p in pairs) (locate(p.$1, true), locate(p.$2, false), p.$3),
      ]),
    ];
  }

  Future<void> edit() async {
    if (busy || current == null || widget.entry?.path == null) return;
    setState(() => busy = true);
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => DataEditorPage(
          library: widget.index.library,
          initialPath: widget.entry!.path,
        ),
      ),
    );
    if (mounted) {
      setState(() {
        busy = false;
        start();
      });
      widget.onEdited?.call();
    }
  }

  Future<void> replace() async {
    final original = current;
    if (busy || original == null) return;
    setState(() => busy = true);
    try {
      final file = await openFile(confirmButtonText: 'Comprobar reemplazo');
      if (file == null || !mounted) return;
      if (await file.length() > 64 * 1024 * 1024) {
        throw const FormatException('Archivo mayor de 64 MiB.');
      }
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      final accept = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Reemplazar recurso'),
          content: Text(
            'Se reemplazará el recurso ID ${original.entry.key}.\n${original.entry.displayPath}\n\n'
            '${widget.index.library.isSpkWorkspace ? 'Se guarda en overlay; el SPK no se modifica.' : 'Se conserva una copia de respaldo.'}'
            '\nLos objetos que compartan este recurso también usarán el cambio. No se convierten esqueletos.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar reemplazo'),
            ),
          ],
        ),
      );
      if (accept != true) return;
      await widget.index.replace(original, bytes);
      if (mounted) {
        setState(start);
        widget.onEdited?.call();
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    request++;
    super.dispose();
  }

  Widget rawMesh(ResourceRead r) => Column(
    children: [
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('Malla directa · sin asociación automática de textura'),
          TextButton.icon(
            icon: const Icon(Icons.image_outlined),
            label: const Text('Elegir textura para esta vista'),
            onPressed: () async {
              final selected = await showDialog<ResourceEntry>(
                context: context,
                builder: (_) => _TextureChooser(index: widget.index),
              );
              if (mounted && selected != null) {
                setState(() => texture = selected);
              }
            },
          ),
        ],
      ),
      Expanded(
        child: NativeModelPreview(
          key: ValueKey('${r.entry.key}:${r.hash}:${texture?.key}'),
          library: widget.index.library,
          model: ModelReference(r.entry.name, [
            (r.entry.path!, texture?.path ?? '', 0),
          ]),
        ),
      ),
    ],
  );

  Widget catalog(CatalogDocument doc) {
    final rows = [
      for (var i = 0; i < doc.rows.length; i++)
        if (doc.materials(i).isNotEmpty) i,
    ];
    return Column(
      children: [
        if (rows.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: DropdownButton<int>(
              isExpanded: true,
              value: rows.contains(row) ? row : rows.first,
              items: [
                for (final i in rows)
                  DropdownMenuItem(
                    value: i,
                    child: Text(
                      '#${doc.rows[i].ordinal} · ${doc.materials(i).map((p) => p.$1).join(' + ')}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) => setState(() {
                row = v!;
                models = resolveModels(doc);
              }),
            ),
          ),
        if (!widget.entry!.confirmed)
          CheckboxListTile(
            dense: true,
            value: allowHints,
            title: const Text(
              'Usar pistas de nombres únicamente para previsualizar',
            ),
            subtitle: const Text(
              'Asociaciones provisionales por rutas exactas y únicas. No confirma nombres ni guarda estos enlaces.',
            ),
            onChanged: (v) => setState(() {
              allowHints = v!;
              models = resolveModels(doc);
            }),
          ),
        Expanded(
          child: FutureBuilder<List<ModelReference>>(
            future: models,
            builder: (_, s) {
              if (s.hasError) {
                return Center(child: SelectableText('${s.error}'));
              }
              if (!s.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (s.data!.isEmpty || s.data!.first.parts.isEmpty) {
                return const Center(
                  child: Text(
                    'Esta fila no contiene geometría. Puedes editar sus campos.',
                  ),
                );
              }
              final model = s.data!.first;
              final missing = [
                for (final p in model.parts)
                  for (final path in [p.$1, p.$2])
                    if (!widget.index.library.files.containsKey(path)) path,
              ];
              if (missing.isNotEmpty) {
                return Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      'Referencias pendientes de resolución:\n${missing.join('\n')}\n\nEl catálogo sigue siendo editable por Entry ID. No se inventan las dependencias.',
                    ),
                  ),
                );
              }
              return NativeModelPreview(
                key: ValueKey(
                  '${widget.entry!.key}:${current?.hash}:$row:$allowHints',
                ),
                library: widget.index.library,
                model: model,
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    if (e == null) {
      return const Center(
        child: Text('Selecciona un recurso en el panel izquierdo.'),
      );
    }
    if (!e.readable) {
      return const Center(
        child: Text(
          'Recurso indexado, todavía bloqueado por su perfil de lectura.',
        ),
      );
    }
    return FutureBuilder<ResourceRead>(
      future: load,
      builder: (context, s) {
        if (s.hasError) {
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: SelectableText('No se pudo abrir el recurso.\n${s.error}'),
            ),
          );
        }
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final r = s.data!, doc = document;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('${e.name} · ${r.format} · ${r.bytes.length} B'),
                  if (doc != null)
                    TextButton.icon(
                      key: const ValueKey('resource-edit'),
                      onPressed: busy ? null : edit,
                      icon: const Icon(Icons.edit_note),
                      label: const Text('Abrir editor'),
                    ),
                  if (widget.index.writable &&
                      const {
                        '3DC',
                        '3DO',
                        'ANI',
                        'DDS',
                        'PNG',
                        'TGA',
                        'BMP',
                        'JPEG',
                        'GIF',
                        'MLT',
                        'ITM',
                        'MON',
                      }.contains(r.format))
                    TextButton.icon(
                      onPressed: busy ? null : replace,
                      icon: const Icon(Icons.file_upload_outlined),
                      label: const Text('Reemplazar archivo'),
                    ),
                  IconButton(
                    tooltip: 'Releer y comprobar',
                    onPressed: busy ? null : () => setState(start),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
            if (busy) const LinearProgressIndicator(minHeight: 2),
            if (error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: SelectableText(error!),
              ),
            Expanded(
              child: r.format == '3DC' || r.format == '3DO'
                  ? rawMesh(r)
                  : doc is CatalogDocument
                  ? catalog(doc)
                  : image != null
                  ? FutureBuilder<Uint8List>(
                      future: image,
                      builder: (_, pixels) {
                        if (pixels.hasError) {
                          return Center(
                            child: SelectableText('${pixels.error}'),
                          );
                        }
                        return !pixels.hasData
                            ? const Center(child: CircularProgressIndicator())
                            : InteractiveViewer(
                                maxScale: 16,
                                child: Center(
                                  child: Image.memory(
                                    pixels.data!,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              );
                      },
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: SelectableText(
                        'SHA-256: ${r.hash}\n${doc == null ? '' : '${doc.rows.length} filas · perfil ${doc.profile}\n'}'
                        '${doc?.complete == true ? 'Abre el editor para modificar los campos.' : 'Inspección de bytes; no se inventa un esquema.'}\n\n'
                        '${r.bytes.take(512).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}',
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _TextureChooser extends StatefulWidget {
  final ResourceIndex index;
  const _TextureChooser({required this.index});
  @override
  State<_TextureChooser> createState() => _TextureChooserState();
}

class _TextureChooserState extends State<_TextureChooser> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final rows = widget.index
        .filter(query, 'Texturas')
        .where((e) => e.readable)
        .toList();
    return AlertDialog(
      title: const Text('Textura de previsualización'),
      content: SizedBox(
        width: 520,
        height: 420,
        child: Column(
          children: [
            const Text(
              'Elección manual para este visor. No cambia el MLT/ITM/MON.',
            ),
            TextField(
              onChanged: (v) => setState(() => query = v),
              decoration: const InputDecoration(
                hintText: 'Buscar nombre, ruta o ID',
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: rows.length,
                itemBuilder: (_, i) => ListTile(
                  title: Text(
                    '${rows[i].confirmed ? '' : '? '}${rows[i].name}',
                  ),
                  subtitle: Text(rows[i].key),
                  onTap: () => Navigator.pop(context, rows[i]),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}

Uint8List _resourcePng((Uint8List, String) arg) =>
    Pixels.decode(arg.$1, 'resource.${arg.$2.toLowerCase()}').png();
