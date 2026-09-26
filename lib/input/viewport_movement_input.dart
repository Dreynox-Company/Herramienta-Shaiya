import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

typedef MovementChanged = void Function(double x, double z, bool running);

class ViewportMovementInput extends StatefulWidget {
  final FocusNode focusNode;
  final MovementChanged onChanged;
  final Widget child;
  final void Function(LogicalKeyboardKey)? onAction;
  final VoidCallback? onFlightToggle;
  final bool enabled;
  const ViewportMovementInput({
    super.key,
    required this.focusNode,
    required this.onChanged,
    required this.child,
    this.onAction,
    this.onFlightToggle,
    this.enabled = true,
  });
  @override
  State<ViewportMovementInput> createState() => _ViewportMovementInputState();
}

class _ViewportMovementInputState extends State<ViewportMovementInput>
    with WidgetsBindingObserver {
  static final _movementKeys = <LogicalKeyboardKey>{
    LogicalKeyboardKey.keyW,
    LogicalKeyboardKey.keyA,
    LogicalKeyboardKey.keyS,
    LogicalKeyboardKey.keyD,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
  };
  static final _actionKeys = <LogicalKeyboardKey>{
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.keyR,
    LogicalKeyboardKey.escape,
    LogicalKeyboardKey.tab,
  };
  bool _active = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _clear() => widget.onChanged(0, 0, false);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (!_active) _clear();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    // A viewport can contain focused controls: never intercept their typing.
    if (!widget.enabled || !node.hasPrimaryFocus) return KeyEventResult.ignored;
    // ISO Spanish < > shares one physical key. Logical symbols also work on
    // other layouts, but an unshifted comma/period is not a flight shortcut.
    final angleKey =
        event.physicalKey == PhysicalKeyboardKey.intlBackslash ||
        event.logicalKey == LogicalKeyboardKey.less ||
        event.logicalKey == LogicalKeyboardKey.greater;
    if (angleKey) {
      final keyboard = HardwareKeyboard.instance;
      if (!_active ||
          event.synthesized ||
          keyboard.isControlPressed ||
          keyboard.isAltPressed ||
          keyboard.isMetaPressed) {
        return KeyEventResult.ignored;
      }
      if (event is KeyDownEvent) widget.onFlightToggle?.call();
      return KeyEventResult.handled;
    }
    // Flight follows the requested Shaiya Studio contract:
    // Space alone = terrestrial jump; Shift+Space = land/fly toggle.
    // A held/repeated Space must never alternate flight repeatedly.
    if (event.logicalKey == LogicalKeyboardKey.space) {
      final keyboard = HardwareKeyboard.instance;
      if (!_active ||
          event.synthesized ||
          keyboard.isControlPressed ||
          keyboard.isAltPressed ||
          keyboard.isMetaPressed) {
        return KeyEventResult.ignored;
      }
      if (event is KeyDownEvent) {
        if (keyboard.isShiftPressed) {
          widget.onFlightToggle?.call();
        } else {
          widget.onAction?.call(LogicalKeyboardKey.space);
        }
      }
      return KeyEventResult.handled;
    }
    if (!_movementKeys.contains(event.logicalKey)) {
      if (event is KeyDownEvent &&
          !event.synthesized &&
          _active &&
          _actionKeys.contains(event.logicalKey)) {
        widget.onAction?.call(event.logicalKey);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (!_active || event.synthesized) {
      _clear();
      return KeyEventResult.handled;
    }
    _samplePressed();
    return KeyEventResult.handled;
  }

  void _samplePressed() {
    if (!_active || !widget.enabled) return;
    final keyboard = HardwareKeyboard.instance;
    final pressed = keyboard.logicalKeysPressed;
    final x =
        (pressed.contains(LogicalKeyboardKey.keyD) ? 1.0 : 0.0) -
        (pressed.contains(LogicalKeyboardKey.keyA) ? 1.0 : 0.0);
    final z =
        (pressed.contains(LogicalKeyboardKey.keyS) ? 1.0 : 0.0) -
        (pressed.contains(LogicalKeyboardKey.keyW) ? 1.0 : 0.0);
    widget.onChanged(x, z, keyboard.isShiftPressed);
  }

  @override
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
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    focusNode: widget.focusNode,
    onFocusChange: (hasFocus) {
      if (!hasFocus || !widget.focusNode.hasPrimaryFocus) {
        _clear();
      } else {
        _samplePressed();
      }
    },
    onKeyEvent: _key,
    child: widget.child,
  );
}
