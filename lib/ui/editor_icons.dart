import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../core/textures.dart';
import '../core/native_item_icons.dart';
import '../data/library.dart';
import '../editor/workbench_model.dart';
import 'editor_style.dart';

class EditorIconRef {
  final String path;
  final int index;
  final bool sheet;
  final int? columns, rows;
  final int? nativeType;
  const EditorIconRef(
    this.path,
    this.index, {
    this.sheet = true,
    this.columns,
    this.rows,
    this.nativeType,
  });
}

class EditorImages {
  final Library library;
  final cache = <String, Future<ui.Image?>>{};
  final retained = <ui.Image>[];
  bool closed = false;
  int bytes = 0;
  late final Set<String> iconFiles = library.files.keys.toSet();
  EditorImages(this.library);
  Future<ui.Image?> image(String path) => cache.putIfAbsent(path, () async {
    if (closed || cache.length > 128) return null;
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
      final ref = NativeItemIcons.resolve(type, index, iconFiles);
      return ref == null
          ? null
          : EditorIconRef(
              ref.path,
              ref.index,
              columns: ref.columns,
              rows: ref.rows,
              nativeType: type,
            );
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
                  'Icono no resuelto · perfil ps0032. No se sustituye por otro objeto.',
              child: fallback,
            )
          : FutureBuilder<ui.Image?>(
              future: images.image(ref.path),
              builder: (c, s) {
                final image = s.data;
                if (image == null) {
                  return Tooltip(
                    message: s.connectionState == ConnectionState.done
                        ? 'No se pudo decodificar ${ref.path}'
                        : 'Cargando miniatura…',
                    child: fallback,
                  );
                }
                final columns = ref.columns ?? image.width ~/ 32,
                    rows = ref.rows ?? image.height ~/ 32;
                if (columns < 1 ||
                    rows < 1 ||
                    ref.index < 0 ||
                    ref.index >= columns * rows) {
                  return Tooltip(
                    message: 'Índice ${ref.index} fuera de ${ref.path}',
                    child: fallback,
                  );
                }
                return Tooltip(
                  message:
                      '${ref.path} · celda ${ref.index}${ref.nativeType == null ? '' : ' · Icon nativo ${summary.values['icon'] ?? '?'}'}',
                  child: CustomPaint(
                    painter: NativeIconPainter(image, ref.index, columns, rows),
                  ),
                );
              },
            ),
    );
  }
}

class NativeIconPainter extends CustomPainter {
  final ui.Image image;
  final int index, columns, rows;
  NativeIconPainter(this.image, this.index, this.columns, this.rows);
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
  bool shouldRepaint(covariant NativeIconPainter o) =>
      o.image != image ||
      o.index != index ||
      o.columns != columns ||
      o.rows != rows;
}
