import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A floating panel inside the application, not a second OS process/window.
/// It overlays the workspace and therefore never steals width from its camera.
class StudioFloatingPanel extends StatefulWidget {
  final String side, title;
  final Size bounds;
  final Widget child;
  final VoidCallback onDock, onClose;
  const StudioFloatingPanel({super.key, required this.side, required this.title,
    required this.bounds, required this.child, required this.onDock, required this.onClose});
  @override
  State<StudioFloatingPanel> createState() => _FloatingPanelState();
}

class _FloatingPanelState extends State<StudioFloatingPanel> {
  Offset? position;
  Size extent = const Size(310, 570);
  bool maximized = false;

  Rect get area {
    final available = widget.bounds;
    final width = math.min(maximized ? available.width - 16 : extent.width, available.width);
    final height = math.min(maximized ? available.height - 16 : extent.height, available.height);
    final initial = position ?? Offset(widget.side == 'left' ? 54 : available.width - width - 16, 16);
    final origin = maximized ? const Offset(8, 8) : initial;
    return Rect.fromLTWH(origin.dx.clamp(0.0, math.max(0, available.width - width)).toDouble(),
      origin.dy.clamp(0.0, math.max(0, available.height - height)).toDouble(),
      math.max(1, width), math.max(1, height));
  }

  @override
  Widget build(BuildContext context) {
    final rect = area;
    return Positioned.fromRect(rect: rect, child: Material(
      key: ValueKey('floating-${widget.side}'), elevation: 14,
      color: const Color(0xff171e29),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: Color(0xff536078))),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        Column(children: [
          GestureDetector(
            key: ValueKey('floating-drag-${widget.side}'),
            behavior: HitTestBehavior.opaque,
            onPanUpdate: maximized ? null : (e) => setState(() => position = rect.topLeft + e.delta),
            child: MouseRegion(cursor: maximized ? SystemMouseCursors.basic : SystemMouseCursors.move,
              child: SizedBox(height: 34, child: Row(children: [
                const SizedBox(width: 10),
                Expanded(child: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                IconButton(key: ValueKey('maximize-${widget.side}'),
                  tooltip: maximized ? 'Restaurar panel' : 'Expandir panel flotante',
                  onPressed: () => setState(() => maximized = !maximized),
                  icon: Icon(maximized ? Icons.filter_none : Icons.crop_square, size: 15)),
                IconButton(key: ValueKey('dock-${widget.side}'), tooltip: 'Acoplar panel',
                  onPressed: widget.onDock, icon: const Icon(Icons.vertical_split, size: 16)),
                IconButton(key: ValueKey('close-floating-${widget.side}'), tooltip: 'Cerrar panel',
                  onPressed: widget.onClose, icon: const Icon(Icons.close, size: 16)),
              ])),
            ),
          ),
          const Divider(height: 1),
          Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(8, 8, 8, 16), child: widget.child)),
        ]),
        if (!maximized)
          Positioned(right: 0, bottom: 0, child: MouseRegion(
            cursor: SystemMouseCursors.resizeUpLeftDownRight,
            child: GestureDetector(key: ValueKey('floating-resize-${widget.side}'),
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (e) => setState(() {
                position = rect.topLeft;
                extent = Size((rect.width + e.delta.dx).clamp(240.0, math.max(240, widget.bounds.width - rect.left)).toDouble(),
                  (rect.height + e.delta.dy).clamp(160.0, math.max(160, widget.bounds.height - rect.top)).toDouble());
              }),
              child: const SizedBox(width: 22, height: 18,
                child: Icon(Icons.drag_handle, size: 15)),
            ),
          )),
      ]),
    ));
  }
}
