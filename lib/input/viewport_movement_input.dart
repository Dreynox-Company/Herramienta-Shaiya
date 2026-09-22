import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

typedef MovementChanged = void Function(double x, double z, bool running);

class ViewportMovementInput extends StatefulWidget {
  final FocusNode focusNode;
  final MovementChanged onChanged;
  final Widget child;
  final void Function(LogicalKeyboardKey)? onAction;
  final VoidCallback? onFlightToggle;
  const ViewportMovementInput({
    super.key,
    required this.focusNode,
    required this.onChanged,
    required this.child,
    this.onAction,
    this.onFlightToggle,
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
    LogicalKeyboardKey.space,
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
    if (!node.hasPrimaryFocus) return KeyEventResult.ignored;
    // The ISO key beside Z (< / > on a Spanish layout), not Shift+comma.
    // Use its location so it also works while Shift is held for sprinting.
    if (event.physicalKey == PhysicalKeyboardKey.intlBackslash) {
      final keyboard = HardwareKeyboard.instance;
      if (!_active ||
          event.synthesized ||
          keyboard.isControlPressed ||
          keyboard.isAltPressed ||
          keyboard.isMetaPressed ||
          widget.onFlightToggle == null) {
        return KeyEventResult.ignored;
      }
      // One toggle per press; holding the key must not alternate repeatedly.
      if (event is KeyDownEvent) widget.onFlightToggle!.call();
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
    if (!_active) return;
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
