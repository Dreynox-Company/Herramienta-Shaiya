import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../core/item_atlas.dart';
import '../core/native_item_icons.dart';
import '../core/textures.dart';
import '../data/file_save.dart';
import '../data/item_workspace.dart';
import 'editor_icons.dart';

Future<int?> pickNativeItemIcon(
  BuildContext context,
  EditorImages images,
  int type,
  int current,
) => showDialog<int>(
  context: context,
  builder: (_) => _IconPicker(images: images, type: type, current: current),
);

class _IconPicker extends StatefulWidget {
  final EditorImages images;
  final int type, current;
  const _IconPicker({
    required this.images,
    required this.type,
    required this.current,
  });
  @override
  State<_IconPicker> createState() => _IconPickerState();
}

class _IconPickerState extends State<_IconPicker> {
  late final options = NativeItemIcons.choices(
    widget.type,
    widget.images.iconFiles,
  );
  int? selected;
  @override
  void initState() {
    super.initState();
    selected = widget.current;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Icono · tipo ${widget.type} · perfil ps0032'),
    content: SizedBox(
      width: 720,
      height: 470,
      child: Column(
        children: [
          const Text(
            'Selecciona una celda real. Se guarda Icon desde 1, no el índice visual desde 0. '
            'Las hojas y bancos corresponden al tipo del objeto.',
          ),
          const SizedBox(height: 12),
          Expanded(
            child: options.isEmpty
                ? const Center(
                    child: Text(
                      'No hay una hoja nativa resoluble para este tipo en la DATA conectada.',
                    ),
                  )
                : GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 74,
                          mainAxisExtent: 72,
                          crossAxisSpacing: 4,
                          mainAxisSpacing: 4,
                        ),
                    itemCount: options.length,
                    itemBuilder: (_, i) {
                      final ref = options[i];
                      return Tooltip(
                        message:
                            '${ref.path}\nIcon ${ref.nativeValue} · celda ${ref.index}',
                        child: InkWell(
                          onTap: () =>
                              setState(() => selected = ref.nativeValue),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: selected == ref.nativeValue
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).dividerColor,
                                width: selected == ref.nativeValue ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                NativeItemIconTile(
                                  images: widget.images,
                                  reference: ref,
                                  size: 36,
                                ),
                                Text(
                                  '${ref.nativeValue}',
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
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
        onPressed: !options.any((o) => o.nativeValue == selected)
            ? null
            : () => Navigator.pop(context, selected),
        child: const Text('Usar este icono'),
      ),
    ],
  );
}

class NativeItemIconTile extends StatelessWidget {
  final EditorImages images;
  final NativeItemIcon reference;
  final double size;
  const NativeItemIconTile({
    super.key,
    required this.images,
    required this.reference,
    this.size = 36,
  });
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: FutureBuilder<ui.Image?>(
      future: images.image(reference.path),
      builder: (_, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(
            child: SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1),
            ),
          );
        }
        if (snap.data == null) {
          return const Tooltip(
            message: 'La hoja no pudo decodificarse',
            child: Icon(Icons.broken_image_outlined),
          );
        }
        return CustomPaint(
          painter: NativeIconPainter(
            snap.data!,
            reference.index,
            reference.columns,
            reference.rows,
          ),
        );
      },
    ),
  );
}

bool _overlap(NativeItemIcon a, NativeItemIcon b) {
  if (a.path != b.path) return false;
  final ax = a.index % a.columns,
      ay = a.index ~/ a.columns,
      bx = b.index % b.columns,
      by = b.index ~/ b.columns;
  return ax / a.columns < (bx + 1) / b.columns &&
      bx / b.columns < (ax + 1) / a.columns &&
      ay / a.rows < (by + 1) / b.rows &&
      by / b.rows < (ay + 1) / a.rows;
}

/// Replace exactly the addressed atlas tile, preserving other base-level pixels.
/// Cross-type aliases and overlapping grids are included in the impact list.
Future<void> replaceItemThumbnail(
  BuildContext context,
  ItemWorkspace workspace,
  ItemEntry item,
) async {
  final files = workspace.preview.files.keys.toSet();
  final target = NativeItemIcons.resolve(item.type, item.icon, files);
  if (target == null)
    throw const FormatException('Selecciona primero un Icon nativo resoluble.');
  final users = workspace.items.where((other) {
    final ref = NativeItemIcons.resolve(other.type, other.icon, files);
    return ref != null && _overlap(target, ref);
  }).toList();
  final input = await openFile(
    acceptedTypeGroups: [
      const XTypeGroup(
        label: 'Miniatura',
        extensions: ['png', 'jpg', 'jpeg', 'webp'],
      ),
    ],
  );
  if (input == null) return;
  if (await input.length() > 8 * 1024 * 1024)
    throw const FormatException('Miniatura mayor de 8 MiB.');
  final data = await input.readAsBytes(),
      original = await workspace.preview.read(target.path);
  final expectedHash = FileSave.hash(original);
  final pixels = Pixels.decode(original, target.path);
  if (pixels.width % target.columns != 0 || pixels.height % target.rows != 0) {
    throw const FormatException(
      'La hoja no coincide con la cuadrícula nativa.',
    );
  }
  final width = pixels.width ~/ target.columns,
      height = pixels.height ~/ target.rows;
  final buffer = await ui.ImmutableBuffer.fromUint8List(data);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? source;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    if (descriptor.width * descriptor.height > 4194304) {
      throw const FormatException('Miniatura mayor de 4 millones de píxeles.');
    }
    codec = await descriptor.instantiateCodec();
    final sourceImage = (await codec.getNextFrame()).image;
    source = sourceImage;
    if (!context.mounted) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reemplazar miniatura compartida'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: SizedBox(
                    width: 96,
                    height: 96,
                    child: RawImage(image: source, fit: BoxFit.contain),
                  ),
                ),
                SelectableText(
                  '\n${target.path}\nIcon ${target.nativeValue} · ${width}×$height px\n\n'
                  '${users.length} ítems usan una celda que se verá afectada.\n'
                  '${users.take(20).map((u) => '${u.key} · ${u.displayName}').join('\n')}'
                  '${users.length > 20 ? '\n… y ${users.length - 20} más' : ''}\n\n'
                  'La imagen se ajusta sin deformar sobre fondo transparente. '
                  'Se reescribe DDS RGBA sin compresión y se regeneran sus mipmaps. '
                  'Pueden existir usos externos a DBItemData. No se sobrescribe DATA: se prepara un parche.',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar impacto y preparar'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    final recorder = ui.PictureRecorder(), canvas = Canvas(recorder);
    final rect = applyBoxFit(
      BoxFit.contain,
      Size(sourceImage.width.toDouble(), sourceImage.height.toDouble()),
      Size(width.toDouble(), height.toDouble()),
    );
    canvas.drawImageRect(
      sourceImage,
      Rect.fromLTWH(
        0,
        0,
        sourceImage.width.toDouble(),
        sourceImage.height.toDouble(),
      ),
      Alignment.center.inscribe(
        rect.destination,
        Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ),
      Paint()..filterQuality = FilterQuality.high,
    );
    final picture = recorder.endRecording();
    final tile = await picture.toImage(width, height);
    picture.dispose();
    final tileData = await tile.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    tile.dispose();
    if (tileData == null)
      throw const FormatException('No se pudo rasterizar la miniatura.');
    final rgba = ItemAtlas.replaceCell(
      pixels.rgba,
      pixels.width,
      pixels.height,
      target.columns,
      target.rows,
      target.index,
      tileData.buffer.asUint8List(),
    );
    final declaredMips =
        original.length >= 128 &&
            ByteData.sublistView(original).getUint32(0, Endian.little) ==
                0x20534444
        ? ByteData.sublistView(original).getUint32(28, Endian.little)
        : 1;
    final dds = ItemAtlas.encodeDds(
      rgba,
      pixels.width,
      pixels.height,
      mipLevels: declaredMips == 0 ? 1 : declaredMips,
    );
    final check = Pixels.decode(dds, target.path);
    if (check.width != pixels.width ||
        check.height != pixels.height ||
        !listEqualsBytes(check.rgba, rgba)) {
      throw const FormatException('La relectura DDS no coincide.');
    }
    await workspace.stageAsset(
      target.path,
      dds,
      expectedHash: expectedHash,
      title: 'Miniatura ${item.key} · ${users.length} usos afectados',
    );
  } finally {
    source?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}

bool listEqualsBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
