import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../editor/document.dart';
import '../editor/workbench_model.dart';
import 'editor_icons.dart';
import 'editor_style.dart';

Map<String, String>? fieldChoices(EditDocument document, String name) {
  final n = name.toLowerCase();
  if ({
    'attackfighter',
    'defensefighter',
    'patrolrogue',
    'shootrogue',
    'attackmage',
    'defensemage',
    'malesex',
    'femalesex',
    'male',
    'female',
  }.contains(n)) {
    return const {'0': 'No permitido', '1': 'Permitido'};
  }
  if (n == 'country' && editorDomain(document.path) == EditorDomain.items) {
    return {for (var i = 0; i <= 6; i++) '$i': itemCountryLabel('$i')};
  }
  if (editorDomain(document.path) == EditorDomain.items &&
      (n == 'reqog' || n == 'og')) {
    return const {
      '0': 'Intercambiable',
      '1': 'No intercambiable',
      '2': 'Vinculado al personaje (si el servidor lo soporta)',
    };
  }
  return null;
}

bool isAssetField(String name) {
  final n = name.toLowerCase();
  return n == 'mesh' ||
      n == 'texture' ||
      n.endsWith('.mesh') ||
      n.endsWith('.texture') ||
      n.startsWith('animation.') ||
      n.startsWith('sound.');
}

Future<String?> pickAsset(
  BuildContext context,
  EditorImages images,
  String field,
  String current,
) async {
  final n = field.toLowerCase(),
      extensions = n.contains('texture')
          ? ['.dds', '.tga', '.png', '.bmp']
          : n.contains('animation')
          ? ['.ani']
          : n.contains('sound')
          ? ['.wav', '.mp3', '.ogg']
          : ['.3dc', '.3do'];
  final files =
      images.library.files.keys
          .where((p) => extensions.any(p.endsWith))
          .toList()
        ..sort(compareEditorValues);
  return showDialog<String>(
    context: context,
    builder: (c) =>
        _AssetDialog(images: images, files: files, current: current),
  );
}

class _AssetDialog extends StatefulWidget {
  final EditorImages images;
  final List<String> files;
  final String current;
  const _AssetDialog({
    required this.images,
    required this.files,
    required this.current,
  });
  @override
  State<_AssetDialog> createState() => _AssetDialogState();
}

class _AssetDialogState extends State<_AssetDialog> {
  final search = TextEditingController();
  String? selected;
  @override
  void initState() {
    super.initState();
    selected = widget.files
        .where(
          (p) =>
              p == widget.current.toLowerCase() ||
              p.endsWith('/${widget.current.toLowerCase()}'),
        )
        .firstOrNull;
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = foldedSearch(search.text),
        files = widget.files
            .where((p) => q.isEmpty || foldedSearch(p).contains(q))
            .toList();
    return AlertDialog(
      title: const Text('Elegir recurso de DATA'),
      content: SizedBox(
        width: 820,
        height: 510,
        child: Column(
          children: [
            TextField(
              controller: search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Filtrar ${widget.files.length} recursos…',
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) => Row(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        itemExtent: 42,
                        itemCount: files.length,
                        itemBuilder: (c, i) {
                          final p = files[i];
                          return ListTile(
                            dense: true,
                            selected: selected == p,
                            title: Text(
                              p.split('/').last,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              p.substring(0, p.lastIndexOf('/') + 1),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 10),
                            ),
                            onTap: () => setState(() => selected = p),
                          );
                        },
                      ),
                    ),
                    if (box.maxWidth > 580 && selected != null)
                      SizedBox(
                        width: 240,
                        child: Column(
                          children: [
                            Expanded(
                              child:
                                  [
                                    '.dds',
                                    '.png',
                                    '.tga',
                                    '.bmp',
                                  ].any(selected!.endsWith)
                                  ? FutureBuilder(
                                      future: widget.images.image(selected!),
                                      builder: (c, s) => s.data == null
                                          ? const Center(
                                              child: Text(
                                                'Sin imagen decodificada',
                                              ),
                                            )
                                          : RawImage(
                                              image: s.data,
                                              fit: BoxFit.contain,
                                            ),
                                    )
                                  : const Center(
                                      child: Icon(
                                        Icons.view_in_ar_outlined,
                                        size: 54,
                                      ),
                                    ),
                            ),
                            Text(
                              selected!,
                              style: const TextStyle(fontSize: 10),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'La ruta se asigna al campo del catálogo. La compatibilidad de UV y esqueleto no se deduce del nombre: comprueba el modelo antes de guardar.',
                style: TextStyle(color: EditorStyle.muted, fontSize: 10),
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
        FilledButton(
          onPressed: selected == null
              ? null
              : () => Navigator.pop(context, selected),
          child: const Text('Usar recurso'),
        ),
      ],
    );
  }
}

Future<int?> pickIcon(
  BuildContext context,
  EditorImages images,
  EditorIconRef ref,
  int current,
) async {
  final image = await images.image(ref.path);
  if (image == null || !context.mounted) return null;
  return showDialog<int>(
    context: context,
    builder: (c) => _IconDialog(image: image, path: ref.path, current: current),
  );
}

class _IconDialog extends StatefulWidget {
  final ui.Image image;
  final String path;
  final int current;
  const _IconDialog({
    required this.image,
    required this.path,
    required this.current,
  });
  @override
  State<_IconDialog> createState() => _IconDialogState();
}

class _IconDialogState extends State<_IconDialog> {
  late int selected = widget.current;
  @override
  Widget build(BuildContext context) {
    final cols = widget.image.width ~/ 32,
        count = cols * (widget.image.height ~/ 32);
    return AlertDialog(
      title: const Text('Iconos originales del juego'),
      content: SizedBox(
        width: 620,
        height: 440,
        child: Column(
          children: [
            Text(widget.path, style: const TextStyle(fontSize: 11)),
            const SizedBox(height: 10),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 66,
                  mainAxisExtent: 64,
                  crossAxisSpacing: 5,
                  mainAxisSpacing: 5,
                ),
                itemCount: count,
                itemBuilder: (c, i) => InkWell(
                  onTap: () => setState(() => selected = i),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: i == selected
                            ? EditorStyle.accent
                            : EditorStyle.line,
                        width: i == selected ? 2 : 1,
                      ),
                      color: EditorStyle.background,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 32,
                          height: 32,
                          child: CustomPaint(
                            painter: IconTilePainter(widget.image, i, cols),
                          ),
                        ),
                        Text(
                          '$i',
                          style: const TextStyle(
                            fontSize: 10,
                            color: EditorStyle.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Índice seleccionado: $selected · el formato valida su rango al aplicar',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: selected < 0 || selected >= count
              ? null
              : () => Navigator.pop(context, selected),
          child: const Text('Usar icono'),
        ),
      ],
    );
  }
}

class IconTilePainter extends CustomPainter {
  final ui.Image image;
  final int index, columns;
  IconTilePainter(this.image, this.index, this.columns);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(index % columns * 32.0, index ~/ columns * 32.0, 32, 32),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(covariant IconTilePainter old) =>
      image != old.image || index != old.index;
}
