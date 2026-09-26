import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_angle/flutter_angle.dart' show AngleOptions;
import 'package:flutter_angle/desktop/lib_egl.dart';
import 'package:three_js/three_js.dart' as three;

/// A native surface belongs to its viewport, not to the whole desktop window.
/// Resize and render are serialized. While ANGLE changes the backing texture,
/// the last completed image is contained, never stretched to a different aspect.
class NativeView extends three.ThreeJS {
  NativeView({
    super.settings,
    required super.setup,
    required super.onSetupComplete,
  });

  final _viewportKey = GlobalKey();
  final surfaceSize = ValueNotifier<Size?>(null);
  Size? _requestedSize;
  double? _requestedDpr;
  double? _surfaceDpr;
  bool _released = false, _frameActive = false;
  int renderedFrames = 0, frameFailures = 0, surfaceResizes = 0;
  String framePhase = 'idle';
  Map<String, Object?> get frameDiagnostics => {
    'frames': renderedFrames,
    'failures': frameFailures,
    'resizes': surfaceResizes,
    'phase': framePhase,
    'active': _frameActive,
    'mounted': mounted,
    'visible': visible,
    'onScreen': isVisibleOnScreen,
    'pause': pause,
    'requestedWidth': _requestedSize?.width,
    'requestedHeight': _requestedSize?.height,
    'surfaceWidth': surfaceSize.value?.width,
    'surfaceHeight': surfaceSize.value?.height,
    'dpr': dpr,
  };

  @override
  bool get updating => _frameActive;

  static Size? validViewport(Size size) {
    if (!size.width.isFinite ||
        !size.height.isFinite ||
        size.width < 1 ||
        size.height < 1) {
      return null;
    }
    return Size(size.width.floorToDouble(), size.height.floorToDouble());
  }

  void requestViewport(Size size, double pixelRatio) {
    final checked = validViewport(size);
    if (_released ||
        checked == null ||
        !pixelRatio.isFinite ||
        pixelRatio <= 0) {
      return;
    }
    _requestedSize = checked;
    _requestedDpr = settings.screenResolution ?? pixelRatio;
  }

  /// The inherited metrics observer uses MediaQuery's window size and races
  /// child layout resizes. The viewport widget supplies both constraints and DPI.
  @override
  void didChangeMetrics() {}

  Future<void> _resizeIfNeeded() async {
    final size = _requestedSize, ratio = _requestedDpr;
    if (_released ||
        size == null ||
        ratio == null ||
        texture == null ||
        renderer == null) {
      return;
    }
    if (surfaceSize.value == size && _surfaceDpr == ratio) return;
    // Every Studio view uses the native surface directly (no separate target).
    // Refuse an unsupported target instead of resizing only half of its buffers.
    if (sourceTexture != null) {
      throw StateError(
        'NativeView requiere una superficie sin useSourceTexture.',
      );
    }
    angle?.activateTexture(texture!);
    await angle?.resize(
      texture!,
      AngleOptions(
        width: size.width.toInt(),
        height: size.height.toInt(),
        dpr: ratio,
      ),
    );
    if (_released) return;
    screenSize = size;
    setResolution(ratio);
    camera.aspect = size.width / size.height;
    camera.updateProjectionMatrix();
    if (_surfaceDpr != ratio) renderer!.setPixelRatio(ratio);
    renderer!.setSize(size.width, size.height);
    windowResizeUpdate?.call(size);
    _surfaceDpr = ratio;
    surfaceResizes++;
    surfaceSize.value = size;
  }

  @override
  Future<void> animate(Duration duration) async {
    if (_released ||
        !mounted ||
        _frameActive ||
        !isVisibleOnScreen ||
        !visible) {
      return;
    }
    _frameActive = true;
    try {
      framePhase = 'resize';
      await _resizeIfNeeded();
      if (_released || texture == null) return;
      final dt = clock.getDelta();
      if (settings.animate) {
        framePhase = 'render';
        await (customRenderer?.call(scene, camera, texture!, dt) ??
            render(scene, camera, texture!, dt));
        if (_released) return;
        framePhase = 'events';
        if (!pause) {
          for (final callback in List<Function(double)>.of(events)) {
            if (_released) break;
            callback(dt);
          }
        }
        renderedFrames++;
      }
    } catch (error, stack) {
      frameFailures++;
      // Report the first failing frame instead of silently freezing forever or
      // flooding logs at refresh rate. The counter remains available to QA.
      if (frameFailures == 1) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'ShStudio NativeView',
            context: ErrorDescription('al actualizar el visor 3D'),
          ),
        );
      }
    } finally {
      _frameActive = false;
      framePhase = 'idle';
    }
  }

  Widget _buildSurface() => super.build();

  @override
  Widget build() => _NativeViewport(key: _viewportKey, view: this);

  @override
  void dispose() {
    if (_released) return;
    _released = true;
    visible = false;
    pause = true;
    ticker?.stop();
    if (texture != null) angle?.activateTexture(texture!);
    try {
      super.dispose();
    } finally {
      surfaceSize.dispose();
      // Preserve other open viewers' function table in flutter_angle 0.4.2.
      if (Platform.isWindows) EGL.loadEGL(useAngle: false);
    }
  }
}

class _NativeViewport extends StatelessWidget {
  final NativeView view;
  const _NativeViewport({super.key, required this.view});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final size = NativeView.validViewport(Size(box.maxWidth, box.maxHeight));
      if (size == null) return const SizedBox.shrink();
      final media = MediaQuery.of(context);
      view.requestViewport(size, media.devicePixelRatio);
      return ClipRect(
        child: ColoredBox(
          color: const Color(0xff10151d),
          child: ValueListenableBuilder<Size?>(
            valueListenable: view.surfaceSize,
            builder: (context, committed, _) {
              final actual = committed ?? view.screenSize ?? size;
              return Center(
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(
                    width: actual.width,
                    height: actual.height,
                    child: MediaQuery(
                      data: media.copyWith(size: actual),
                      child: view._buildSurface(),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
    },
  );
}
