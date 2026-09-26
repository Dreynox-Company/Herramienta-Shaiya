import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Camera-only state. Never changes vertices, attachment transforms or DATA.
class ModelOrbit extends ChangeNotifier {
  double yaw = .35, pitch = .18, zoom = 1;
  double targetX = 0, targetY = 0, targetZ = 0;
  double distance = 1;
  List<double> get snapshot => [yaw, pitch, zoom, targetX, targetY, targetZ];

  void rotate(Offset delta) {
    if (!delta.dx.isFinite || !delta.dy.isFinite) return;
    yaw = (yaw - delta.dx * .009) % (math.pi * 2);
    pitch = (pitch + delta.dy * .009).clamp(
      -math.pi / 2 + .005,
      math.pi / 2 - .005,
    );
    notifyListeners();
  }

  void dolly(double logarithm) {
    if (!logarithm.isFinite) return;
    zoom = (zoom * math.exp(logarithm.clamp(-4, 4))).clamp(.03, 30);
    notifyListeners();
  }

  void pan(Offset delta, double height) {
    if (height <= 0 ||
        !height.isFinite ||
        !delta.dx.isFinite ||
        !delta.dy.isFinite) {
      return;
    }
    final units = 2 * distance * zoom * math.tan(21 * math.pi / 180) / height;
    // Camera right and camera up; pan remains screen-relative after orbiting.
    targetX +=
        (-math.cos(yaw) * delta.dx -
            math.sin(yaw) * math.sin(pitch) * delta.dy) *
        units;
    targetY += math.cos(pitch) * delta.dy * units;
    targetZ +=
        (math.sin(yaw) * delta.dx -
            math.cos(yaw) * math.sin(pitch) * delta.dy) *
        units;
    notifyListeners();
  }

  void reset({double azimuth = .35, double elevation = .18}) {
    yaw = azimuth;
    pitch = elevation;
    zoom = 1;
    targetX = targetY = targetZ = 0;
    notifyListeners();
  }
}

/// An input surface ABOVE the renderer, not a parent recognizer competing
/// with three_js' internal peripherals. Only presses starting here are owned.
/// The renderer still owns its GL lifecycle, but receives no duplicate input.
class ModelOrbitInput extends StatefulWidget {
  final ModelOrbit orbit;
  final Widget child;
  const ModelOrbitInput({super.key, required this.orbit, required this.child});
  @override
  State<ModelOrbitInput> createState() => _ModelOrbitInputState();
}

class _ModelOrbitInputState extends State<ModelOrbitInput> {
  final focus = FocusNode(debugLabel: 'model-preview-camera');
  final touches = <int, Offset>{};
  int? mouse;
  int buttons = 0;
  double trackpadScale = 1;
  bool dragging = false;

  void clear() {
    mouse = null;
    buttons = 0;
    touches.clear();
    trackpadScale = 1;
    if (mounted && dragging) setState(() => dragging = false);
  }

  void down(PointerDownEvent e) {
    focus.requestFocus();
    if (e.kind == PointerDeviceKind.touch) {
      touches[e.pointer] = e.localPosition;
    } else if (mouse == null &&
        e.buttons &
                (kPrimaryMouseButton |
                    kSecondaryMouseButton |
                    kMiddleMouseButton) !=
            0) {
      mouse = e.pointer;
      buttons = e.buttons;
    }
    if (!dragging) setState(() => dragging = true);
  }

  void move(PointerMoveEvent e, double height) {
    if (e.kind == PointerDeviceKind.touch) {
      if (!touches.containsKey(e.pointer)) return;
      final before = touches.values.take(2).toList();
      touches[e.pointer] = e.localPosition;
      final after = touches.values.take(2).toList();
      if (before.length == 1) {
        widget.orbit.rotate(e.localDelta);
      } else {
        widget.orbit.pan(
          (after[0] + after[1] - before[0] - before[1]) / 2,
          height,
        );
        final oldSpan = (before[0] - before[1]).distance;
        final newSpan = (after[0] - after[1]).distance;
        if (oldSpan > 1 && newSpan > 1) {
          widget.orbit.dolly(math.log(oldSpan / newSpan));
        }
      }
    } else if (e.pointer == mouse) {
      if (e.buttons == 0) {
        clear();
        return;
      }
      buttons = e.buttons;
      final translate =
          buttons & (kSecondaryMouseButton | kMiddleMouseButton) != 0 ||
          HardwareKeyboard.instance.isShiftPressed;
      if (translate) {
        widget.orbit.pan(e.localDelta, height);
      } else if (buttons & kPrimaryMouseButton != 0) {
        widget.orbit.rotate(e.localDelta);
      }
    }
  }

  void up(PointerEvent e) {
    touches.remove(e.pointer);
    if (mouse == e.pointer) {
      mouse = null;
      buttons = 0;
    }
    if (mouse == null && touches.isEmpty && dragging) {
      setState(() => dragging = false);
    }
  }

  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: focus,
    onFocusChange: (hasFocus) {
      if (!hasFocus) clear();
    },
    onKeyEvent: (_, e) {
      if (e is KeyUpEvent) return KeyEventResult.ignored;
      if (e.logicalKey == LogicalKeyboardKey.keyF ||
          e.logicalKey == LogicalKeyboardKey.home) {
        widget.orbit.reset();
        return KeyEventResult.handled;
      }
      if (e.logicalKey == LogicalKeyboardKey.escape) {
        clear();
        focus.unfocus();
      }
      return KeyEventResult.ignored;
    },
    child: LayoutBuilder(
      builder: (context, bounds) => Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(child: widget.child),
          Positioned.fill(
            child: MouseRegion(
              cursor: dragging
                  ? SystemMouseCursors.grabbing
                  : SystemMouseCursors.grab,
              child: Listener(
                key: const ValueKey('model-orbit-input'),
                behavior: HitTestBehavior.opaque,
                onPointerDown: down,
                onPointerMove: (e) => move(e, bounds.maxHeight),
                onPointerUp: up,
                onPointerCancel: up,
                onPointerSignal: (e) {
                  if (e is PointerScrollEvent) {
                    GestureBinding.instance.pointerSignalResolver.register(e, (
                      _,
                    ) {
                      widget.orbit.dolly(e.scrollDelta.dy * .0015);
                    });
                  }
                },
                onPointerPanZoomStart: (_) {
                  focus.requestFocus();
                  trackpadScale = 1;
                },
                onPointerPanZoomUpdate: (e) {
                  widget.orbit.pan(e.panDelta, bounds.maxHeight);
                  if (e.scale > 0 && trackpadScale > 0) {
                    widget.orbit.dolly(math.log(trackpadScale / e.scale));
                  }
                  trackpadScale = e.scale;
                },
                onPointerPanZoomEnd: (_) => trackpadScale = 1,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
