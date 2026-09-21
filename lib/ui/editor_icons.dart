import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../core/textures.dart';
import '../data/library.dart';
import '../editor/workbench_model.dart';
import 'editor_style.dart';

class EditorIconRef {
  final String path;
  final int index;
  final bool sheet;
  const EditorIconRef(this.path, this.index, {this.sheet = true});
}

class EditorImages {
  final Library library;
  final cache = <String, Future<ui.Image?>>{};
  final retained = <ui.Image>[];
  bool closed = false;
  int bytes = 0;
  EditorImages(this.library);
  Future<ui.Image?> image(String path) => cache.putIfAbsent(path, () async {
    if (closed || cache.length > 64) return null;
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
      final number = type.toString().padLeft(2, '0');
      for (final ext in ['dds', 'tga']) {
        final path = 'interface/icon/$number.$ext';
        if (library.files.containsKey(path)) return EditorIconRef(path, index);
      }
      final base = type <= 15
          ? 'weapon'
          : const {19, 34, 69, 84}.contains(type)
          ? 'shield'
          : const {16, 31}.contains(type)
          ? 'helmet'
          : const {17, 32, 67, 82}.contains(type)
          ? 'upper'
          : const {18, 33, 68, 83}.contains(type)
          ? 'lower'
          : const {20, 35, 70, 85}.contains(type)
          ? 'hand'
          : const {21, 36, 71, 86}.contains(type)
          ? 'foot'
          : type == 25
          ? 'gem'
          : const {22, 23, 24}.contains(type)
          ? 'acc'
          : type == 42
          ? 'vehicle'
          : 'somo';
      final candidates = [
        'interface/icon/icon_$base.dds',
        'interface/icon/icon_${base}1.dds',
      ];
      for (final p in candidates) {
        if (library.files.containsKey(p)) return EditorIconRef(p, index);
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
          ? fallback
          : FutureBuilder<ui.Image?>(
              future: images.image(ref.path),
              builder: (c, s) {
                final image = s.data;
                if (image == null) return fallback;
                final columns = image.width ~/ 32, rows = image.height ~/ 32;
                if (ref.index < 0 || ref.index >= columns * rows) {
                  return Tooltip(
                    message: 'Índice ${ref.index} fuera de ${ref.path}',
                    child: fallback,
                  );
                }
                return Tooltip(
                  message: '${ref.path} · icono ${ref.index}',
                  child: CustomPaint(
                    painter: _IconPainter(image, ref.index, columns),
                  ),
                );
              },
            ),
    );
  }
}

class _IconPainter extends CustomPainter {
  final ui.Image image;
  final int index, columns;
  _IconPainter(this.image, this.index, this.columns);
  @override
  void paint(Canvas c, Size s) {
    c.drawImageRect(
      image,
      Rect.fromLTWH(
        (index % columns) * 32.0,
        (index ~/ columns) * 32.0,
        32,
        32,
      ),
      Offset.zero & s,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(covariant _IconPainter o) =>
      o.image != image || o.index != index;
}
