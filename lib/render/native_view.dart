import 'dart:io';

import 'package:flutter_angle/desktop/lib_egl.dart';
import 'package:three_js/three_js.dart' as three;

/// Scoped surface ownership for three_js 0.3.0 / flutter_angle 0.4.2.
///
/// EGL.dispose() in that pinned binding clears a process-wide function table,
/// even when a second viewer still owns an EGL context. Restore the binding
/// table after disposal on Windows; contexts and textures are still released
/// normally. Never terminate the shared EGL display or swallow graphics errors.
class NativeView extends three.ThreeJS {
  NativeView({
    super.settings,
    required super.setup,
    required super.onSetupComplete,
  });

  bool _released = false;

  @override
  void dispose() {
    if (_released) return;
    _released = true;
    visible = false;
    pause = true;
    ticker?.stop();
    // Do not dispose another view's GL resources under this view's context.
    if (texture != null) angle?.activateTexture(texture!);
    try {
      super.dispose();
    } finally {
      if (Platform.isWindows) EGL.loadEGL(useAngle: false);
    }
  }
}
