import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../core/textures.dart';
import '../core/item_icon_layout.dart';
import '../data/library.dart';
import '../editor/workbench_model.dart';
import 'editor_style.dart';

class EditorIconRef {
  final String path;
  final int index;
  final bool sheet;
  final int? columns, rows;
  final int pageBase;
  const EditorIconRef(
    this.path,
    this.index, {
    this.sheet = true,
    this.columns,
    this.rows,
    this.pageBase = 0,
  });
}

class EditorImages {
  final Library library;
  final cache = <String, Future<ui.Image?>>{};
  final retained = <ui.Image>[];
  bool closed = false;
  int bytes = 0;
  EditorImages(this.library);
  Future<ui.Image?> image(String path) => cache.putIfAbsent(path, () async {
    if (closed) return null;
    try {
      final b = await library.read(path, limit: 32 * 1024 * 1024);
      final pixels = await compute(_decode, (b, path));
      if (closed ||
          pixels.width * pixels.height > 4194304 ||
          bytes + pixels.width * pixels.height * 4 > 96 * 1024 * 1024) {
        return null;
      }
      final buffer = await ui.ImmutableBuffer.fromUint8List(pixels.rgba);
      final descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: pixels.width,
        height: pixels.height,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      final codec = await descriptor.instantiateCodec();
      final frame = await codec.getNextFrame();
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
      if (closed) {
        frame.image.dispose();
        return null;
      }
      retained.add(frame.image);
      bytes += pixels.rgba.length;
      return frame.image;
    } catch (_) {
      return null;
    }
  });
  void dispose() {
    closed = true;
    for (final im in retained) {
      im.dispose();
    }
    retained.clear();
    cache.clear();
  }

  EditorIconRef? icon(String path, RecordSummary row) {
    final domain = editorDomain(path), v = row.values;
    final type = int.tryParse(v['itemtype'] ?? v['type'] ?? '');
    final index = int.tryParse(v['icon'] ?? v['iconid'] ?? '');
    if (domain == EditorDomain.items && index != null && type != null) {
      final layout = ItemIconLayout.resolve(type, index);
      if (layout == null || !layout.inBounds) return null;
      for (final ext in ['dds', 'tga']) {
        final path = 'interface/icon/${layout.stem}.$ext';
        if (library.files.containsKey(path)) {
          return EditorIconRef(
            path,
            layout.tile,
            columns: layout.columns,
            rows: layout.rows,
            pageBase: layout.pageBase,
          );
        }
      }
    }

    if (domain == EditorDomain.skills && index != null) {
      final page = index ~/ 256 + 1, tile = index % 256;
      for (final ext in ['dds', 'tga']) {
        final p = 'interface/icon/icon_skill${page == 1 ? '' : page}.$ext';
        if (library.files.containsKey(p)) return EditorIconRef(p, tile);
      }
    }
    if (domain == EditorDomain.shops && index != null) {
      final p = 'interface/icon/icon_somo2.dds';
      if (library.files.containsKey(p)) return EditorIconRef(p, index);
    }
    return null;
  }
}

Pixels _decode((Uint8List, String) args) => Pixels.decode(args.$1, args.$2);
IconData domainIcon(EditorDomain d) => switch (d) {
  EditorDomain.items => Icons.shield_outlined,
  EditorDomain.skills => Icons.bolt,
  EditorDomain.creatures => Icons.pets_outlined,
  EditorDomain.shops => Icons.storefront_outlined,
  EditorDomain.npcs => Icons.people_outline,
  EditorDomain.maps => Icons.map_outlined,
  EditorDomain.models => Icons.view_in_ar_outlined,
  EditorDomain.configuration => Icons.settings_outlined,
  _ => Icons.table_chart_outlined,
};

class DataIcon extends StatelessWidget {
  final EditorImages images;
  final String path;
  final RecordSummary summary;
  final double size;
  const DataIcon({
    super.key,
    required this.images,
    required this.path,
    required this.summary,
    this.size = 28,
  });
  @override
  Widget build(BuildContext context) {
    final ref = images.icon(path, summary);
    final fallback = Icon(
      domainIcon(editorDomain(path)),
      size: size * .65,
      color: EditorStyle.muted,
    );
    return SizedBox(
      width: size,
      height: size,
      child: ref == null
          ? Tooltip(
              message:
                  'Icono ausente, fuera de rango o tipo no soportado por ps0032. No se sustituye por otro objeto.',
              child: fallback,
            )
          : FutureBuilder<ui.Image?>(
              future: images.image(ref.path),
              builder: (c, s) {
                final image = s.connectionState == ConnectionState.done
                    ? s.data
                    : null;
                if (image == null) return fallback;
                final columns = ref.columns ?? image.width ~/ 32,
                    rows = ref.rows ?? image.height ~/ 32;
                if (ref.index < 0 || ref.index >= columns * rows) {
                  return Tooltip(
                    message: 'Índice ${ref.index} fuera de ${ref.path}',
                    child: fallback,
                  );
                }
                return Tooltip(
                  message:
                      '${ref.path} · Icon ${ref.index + ref.pageBase} · celda ${ref.index} · ps0032',
                  child: CustomPaint(
                    painter: _IconPainter(image, ref.index, columns, rows),
                  ),
                );
              },
            ),
    );
  }
}

class _IconPainter extends CustomPainter {
  final ui.Image image;
  final int index, columns, rows;
  _IconPainter(this.image, this.index, this.columns, this.rows);
  @override
  void paint(Canvas c, Size s) {
    c.drawImageRect(
      image,
      Rect.fromLTWH(
        (index % columns) * image.width / columns,
        (index ~/ columns) * image.height / rows,
        image.width / columns,
        image.height / rows,
      ),
      Offset.zero & s,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(covariant _IconPainter o) =>
      o.image != image ||
      o.index != index ||
      o.columns != columns ||
      o.rows != rows;
}
