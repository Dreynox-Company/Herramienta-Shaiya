import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../editor/document.dart';
import 'editor_icons.dart';
import 'editor_style.dart';

class MapMarker {
  final int row;
  final String label, kind;
  final double x, z;
  final double? endX, endZ;
  const MapMarker(
    this.row,
    this.label,
    this.kind,
    this.x,
    this.z, {
    this.endX,
    this.endZ,
  });
  bool get area => endX != null && endZ != null;
}

List<MapMarker> mapMarkers(EditDocument doc, Iterable<int> rows) {
  final result = <MapMarker>[];
  for (final row in rows) {
    final v = {
      for (final f in doc.fields(row)) f.spec.name.toLowerCase(): doc.read(f),
    };
    double? n(String key) {
      final x = double.tryParse(v[key] ?? '');
      return x != null && x.isFinite ? x : null;
    }

    final rec = doc.rows[row], x = n('min.x'), z = n('min.z');
    if (x != null && z != null) {
      result.add(
        MapMarker(
          row,
          '${rec.kind} #${rec.ordinal + 1}',
          rec.kind,
          x,
          z,
          endX: n('max.x'),
          endZ: n('max.z'),
        ),
      );
      continue;
    }
    for (final key in v.keys.where(
      (k) => k == 'position.x' || RegExp(r'^positions\[\d+\]\.x$').hasMatch(k),
    )) {
      final prefix = key.substring(0, key.length - 1),
          x = n(key),
          z = n('${prefix}z');
      if (x != null && z != null) {
        result.add(
          MapMarker(
            row,
            '${rec.kind} · ${v['npcid'] ?? rec.ordinal + 1}',
            rec.kind,
            x,
            z,
          ),
        );
      }
    }
  }
  return result;
}

class EditorMapView extends StatefulWidget {
  final EditDocument document;
  final EditorImages images;
  final List<int> rows;
  final int selected;
  final ValueChanged<int> onSelect, onEdit;
  const EditorMapView({
    super.key,
    required this.document,
    required this.images,
    required this.rows,
    required this.selected,
    required this.onSelect,
    required this.onEdit,
  });
  @override
  State<EditorMapView> createState() => _EditorMapViewState();
}

class _EditorMapViewState extends State<EditorMapView> {
  final transform = TransformationController();
  String imagePath = '', pointer = '';
  bool invertZ = true;
  late List<String> sheets;
  @override
  void initState() {
    super.initState();
    sheets =
        widget.images.library.files.keys
            .where(
              (p) =>
                  p.contains('/minimap/') &&
                  ['.dds', '.tga', '.png', '.bmp'].any(p.endsWith),
            )
            .toList()
          ..sort();
    _reset();
  }

  void _reset() {
    final id = int.tryParse(
      widget.document.path.split('/').last.split('.').first,
    );
    imagePath = id == null
        ? ''
        : sheets
                  .where(
                    (p) => RegExp(
                      '(^|/)minimap_0*$id\\.(dds|tga|png|bmp)\$',
                    ).hasMatch(p),
                  )
                  .firstOrNull ??
              '';
    transform.value = Matrix4.identity();
  }

  @override
  void didUpdateWidget(covariant EditorMapView old) {
    super.didUpdateWidget(old);
    if (old.document != widget.document) _reset();
  }

  @override
  void dispose() {
    transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final doc = widget.document,
        extent = doc.payload.length >= 4
            ? ByteData.sublistView(
                doc.payload,
              ).getUint32(0, Endian.little).toDouble()
            : 0.0;
    if (doc.profile != 'svmap' || extent < 1 || extent > 16384) {
      return const Center(child: Text('El plano necesita un SVMAP validado.'));
    }
    final markers = mapMarkers(doc, widget.rows);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Wrap(
            spacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 205,
                child: DropdownButton<String>(
                  value: imagePath,
                  isExpanded: true,
                  isDense: true,
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Solo coordenadas'),
                    ),
                    for (final p in sheets)
                      DropdownMenuItem(
                        value: p,
                        child: Text(
                          p.split('/').last,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (p) => setState(() => imagePath = p!),
                ),
              ),
              IconButton(
                tooltip: 'Restablecer vista',
                onPressed: () => transform.value = Matrix4.identity(),
                icon: const Icon(Icons.center_focus_strong),
              ),
              TextButton(
                onPressed: () => setState(() => invertZ = !invertZ),
                child: Text(invertZ ? 'Z arriba' : 'Z abajo'),
              ),
              Text(
                '${markers.length} ubicaciones · ${extent.toInt()} × ${extent.toInt()}',
                style: const TextStyle(color: EditorStyle.muted, fontSize: 10),
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (c, b) {
              final side = math.max(160.0, math.min(b.maxWidth, b.maxHeight));
              void hit(Offset p, bool edit) {
                final x = p.dx / side * extent,
                    z = (invertZ ? 1 - p.dy / side : p.dy / side) * extent;
                setState(
                  () => pointer =
                      'X ${x.toStringAsFixed(1)} · Z ${z.toStringAsFixed(1)}',
                );
                MapMarker? chosen;
                double best = extent * .025;
                for (final m in markers.where((m) => !m.area)) {
                  final d = math.sqrt(
                    math.pow(m.x - x, 2) + math.pow(m.z - z, 2),
                  );
                  if (d < best) {
                    chosen = m;
                    best = d;
                  }
                }
                chosen ??= markers
                    .where(
                      (m) =>
                          m.area &&
                          x >= math.min(m.x, m.endX!) &&
                          x <= math.max(m.x, m.endX!) &&
                          z >= math.min(m.z, m.endZ!) &&
                          z <= math.max(m.z, m.endZ!),
                    )
                    .firstOrNull;
                if (chosen != null) {
                  if (edit) {
                    widget.onEdit(chosen.row);
                  } else {
                    widget.onSelect(chosen.row);
                  }
                }
              }

              return ClipRect(
                child: InteractiveViewer(
                  transformationController: transform,
                  minScale: .5,
                  maxScale: 10,
                  boundaryMargin: const EdgeInsets.all(120),
                  child: Center(
                    child: GestureDetector(
                      onTapUp: (d) => hit(d.localPosition, false),
                      onDoubleTapDown: (d) => hit(d.localPosition, true),
                      child: SizedBox(
                        width: side,
                        height: side,
                        child: Stack(
                          children: [
                            const Positioned.fill(
                              child: ColoredBox(color: Color(0xff111e28)),
                            ),
                            if (imagePath.isNotEmpty)
                              Positioned.fill(
                                child: FutureBuilder(
                                  future: widget.images.image(imagePath),
                                  builder: (c, s) => s.data == null
                                      ? const SizedBox()
                                      : RawImage(
                                          image: s.data,
                                          fit: BoxFit.fill,
                                        ),
                                ),
                              ),
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _MapPainter(
                                  markers,
                                  widget.selected,
                                  extent,
                                  invertZ,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            '$pointer · Rueda: zoom · arrastra: desplazar · clic: seleccionar · doble clic: editar\nPosiciones del SVMAP del servidor. La imagen de minimapa no modifica la geometría WLD.',
            style: const TextStyle(fontSize: 10, color: EditorStyle.muted),
          ),
        ),
      ],
    );
  }
}

class _MapPainter extends CustomPainter {
  final List<MapMarker> markers;
  final int selected;
  final double extent;
  final bool invertZ;
  _MapPainter(this.markers, this.selected, this.extent, this.invertZ);
  @override
  void paint(Canvas canvas, Size size) {
    Offset at(double x, double z) => Offset(
      x / extent * size.width,
      (invertZ ? 1 - z / extent : z / extent) * size.height,
    );
    final grid = Paint()
      ..color = const Color(0x344c7180)
      ..strokeWidth = .6;
    for (var i = 0; i <= 16; i++) {
      final t = i / 16;
      canvas.drawLine(
        Offset(t * size.width, 0),
        Offset(t * size.width, size.height),
        grid,
      );
      canvas.drawLine(
        Offset(0, t * size.height),
        Offset(size.width, t * size.height),
        grid,
      );
    }
    for (final m in [
      ...markers.where((m) => m.row != selected),
      ...markers.where((m) => m.row == selected),
    ]) {
      final chosen = m.row == selected,
          color = chosen
              ? Colors.white
              : m.kind.contains('NPC')
              ? const Color(0xff87d5ff)
              : m.kind.contains('Portal')
              ? const Color(0xffc298ff)
              : m.kind.contains('criaturas')
              ? const Color(0xffeac080)
              : const Color(0xff8cdcaf);
      if (m.area) {
        final rect = Rect.fromPoints(at(m.x, m.z), at(m.endX!, m.endZ!));
        canvas.drawRect(
          rect,
          Paint()..color = color.withValues(alpha: chosen ? .22 : .08),
        );
        canvas.drawRect(
          rect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = chosen ? 2 : 1
            ..color = color,
        );
      } else {
        canvas.drawCircle(
          at(m.x, m.z),
          chosen ? 6 : 4,
          Paint()..color = const Color(0xff0d1823),
        );
        canvas.drawCircle(
          at(m.x, m.z),
          chosen ? 4.5 : 2.5,
          Paint()..color = color,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter old) => true;
}
