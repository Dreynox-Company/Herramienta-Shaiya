"""Gate controls on completed library mounting and retain native failure evidence."""
from pathlib import Path
import subprocess
ROOT = Path(__file__).resolve().parents[1]
MARKER = ROOT / '.studio-r28-ready-input-applied'


def apply(root):
    changes = {}
    def replace(path, old, new, count=1):
        text = changes.get(path, (root / path).read_text(encoding='utf-8'))
        if text.count(old) != count:
            raise RuntimeError(f'Ready input anchor: {path}: {old[:100]}')
        changes[path] = text.replace(old, new)
    path = 'lib/input/viewport_movement_input.dart'
    replace(path, '  final VoidCallback? onFlightToggle;', '  final VoidCallback? onFlightToggle;\n  final bool enabled;')
    replace(path, '    this.onFlightToggle,', '    this.onFlightToggle,\n    this.enabled = true,')
    replace(path, '    if (!node.hasPrimaryFocus) return KeyEventResult.ignored;',
        '    if (!widget.enabled || !node.hasPrimaryFocus) return KeyEventResult.ignored;')
    replace(path, '    if (!_active) return;', '    if (!_active || !widget.enabled) return;')
    replace(path, '  @override\n  void dispose() {', '''  @override
  void didUpdateWidget(covariant ViewportMovementInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) {
      // Mounting clears movement while resources are awaited. Resume held
      // movement only AFTER the completed mount has been published.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!widget.enabled) {
          _clear();
        } else if (widget.focusNode.hasPrimaryFocus) {
          _samplePressed();
        }
      });
    }
  }

  @override
  void dispose() {''')
    path = 'lib/main.dart'
    replace(path, '          child: ViewportMovementInput(\n            focusNode: focus,',
        '          child: ViewportMovementInput(\n            focusNode: focus,\n            enabled: !importing,')
    path = 'lib/render/native_view.dart'
    replace(path, '  int renderedFrames = 0, frameFailures = 0, surfaceResizes = 0;', '''  int renderedFrames = 0, frameFailures = 0, surfaceResizes = 0;
  String framePhase = 'idle';
  Map<String, Object?> get frameDiagnostics => {
    'frames': renderedFrames, 'failures': frameFailures, 'resizes': surfaceResizes,
    'phase': framePhase, 'active': _frameActive, 'mounted': mounted,
    'visible': visible, 'onScreen': isVisibleOnScreen, 'pause': pause,
    'requestedWidth': _requestedSize?.width, 'requestedHeight': _requestedSize?.height,
    'surfaceWidth': surfaceSize.value?.width, 'surfaceHeight': surfaceSize.value?.height,
    'dpr': dpr,
  };''')
    replace(path, '    renderer!.setSize(size.width, size.height);',
        '    if (_surfaceDpr != ratio) renderer!.setPixelRatio(ratio);\n    renderer!.setSize(size.width, size.height);')
    replace(path, '      await _resizeIfNeeded();', "      framePhase = 'resize';\n      await _resizeIfNeeded();")
    replace(path, '      if (settings.animate) {', "      if (settings.animate) {\n        framePhase = 'render';")
    replace(path, '        if (!pause) {', "        framePhase = 'events';\n        if (!pause) {")
    replace(path, '      _frameActive = false;', "      _frameActive = false;\n      framePhase = 'idle';")
    path = 'integration_test/native_studio_test.dart'
    replace(path, '      () => scene.character != null && !scene.busy && state.catalog != null,', '''      () => scene.character != null && !scene.busy && state.catalog != null &&
          !state.importing && !state.working,''')
    replace(path, "      'Loaded native mesh, texture, catalog and skeletal clips',", "      'Loaded native mesh, texture, catalog and skeletal clips; mount fully published',")
    replace(path, "      expect(condition(), isTrue, reason: '$name; ${scene.status}');", '''      if (!condition()) {
        final debug = <String, Object?>{
          'check': name, 'status': scene.status, 'importing': state.importing,
          'working': state.working, 'focus': (state.focus as FocusNode).hasPrimaryFocus,
          'walkX': scene.walkX, 'walkZ': scene.walkZ,
          'clip': scene.character?.clip?.source,
          'expectedWalk': scene.character?.walk?.source,
          'renderer': (state.renderer as NativeView).frameDiagnostics,
          'passed': passed,
        };
        await File('${output.path}/failure-state.json').writeAsString(jsonEncode(debug));
        try {
          final boundary = (state.captureKey as GlobalKey).currentContext!.findRenderObject() as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          if (bytes != null) await File('${output.path}/failure-viewport.png').writeAsBytes(bytes.buffer.asUint8List());
        } catch (captureError) {
          await File('${output.path}/failure-capture.txt').writeAsString('$captureError');
        }
        debugPrint(jsonEncode(debug));
      }
      expect(condition(), isTrue, reason: '$name; ${scene.status}');''')
    if "import 'dart:convert';" not in changes[path]:
        changes[path] = "import 'dart:convert';\n" + changes[path]
    for path, text in changes.items():
        (root / path).write_text(text, encoding='utf-8')


def main():
    if subprocess.check_output(['git', 'branch', '--show-current'], cwd=ROOT, text=True).strip() != 'fix/studio-0628-startup-spk-recovery':
        raise RuntimeError('Refusing a different branch.')
    if MARKER.exists():
        return
    apply(ROOT)
    MARKER.write_text('R28 mounting input lifecycle and native frame diagnostics\n')


if __name__ == '__main__':
    main()
