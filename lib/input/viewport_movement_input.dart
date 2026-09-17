import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

typedef MovementChanged = void Function(double x, double z, bool running);

class ViewportMovementInput extends StatefulWidget {
  final FocusNode focusNode;
  final MovementChanged onChanged;
  final Widget child;
  final void Function(LogicalKeyboardKey)? onAction;
  const ViewportMovementInput({
    super.key,
    required this.focusNode,
    required this.onChanged,
    required this.child,
    this.onAction,
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
    final keyboard = HardwareKeyboard.instance;
    final pressed = keyboard.logicalKeysPressed;
    final x =
        (pressed.contains(LogicalKeyboardKey.keyD) ? 1.0 : 0.0) -
        (pressed.contains(LogicalKeyboardKey.keyA) ? 1.0 : 0.0);
    final z =
        (pressed.contains(LogicalKeyboardKey.keyS) ? 1.0 : 0.0) -
        (pressed.contains(LogicalKeyboardKey.keyW) ? 1.0 : 0.0);
    widget.onChanged(x, z, keyboard.isShiftPressed);
    return KeyEventResult.handled;
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
      if (!hasFocus) _clear();
    },
    onKeyEvent: _key,
    child: widget.child,
  );
}
