import 'package:flutter/material.dart';

/// Stable per-object numeric editor. The owner supplies a key containing the
/// selected resource identity, NOT the current numeric value.
class InspectorNumberControl extends StatefulWidget {
  final String title;
  final double value, min, max, step;
  final int decimals;
  final bool enabled;
  final ValueChanged<double> onChanged;
  const InspectorNumberControl({
    super.key, required this.title, required this.value,
    required this.min, required this.max, required this.onChanged,
    this.step = .01, this.decimals = 3, this.enabled = true,
  });
  @override
  State<InspectorNumberControl> createState() => _InspectorNumberState();
}

class _InspectorNumberState extends State<InspectorNumberControl> {
  late final TextEditingController text;
  final focus = FocusNode();
  String? error;
  double get safe => widget.value.isFinite
      ? widget.value.clamp(widget.min, widget.max).toDouble() : widget.min;
  String format(double value) => value.toStringAsFixed(widget.decimals);

  @override
  void initState() {
    super.initState();
    text = TextEditingController(text: format(safe));
    focus.addListener(_focusChanged);
  }

  void _focusChanged() {
    if (!focus.hasFocus && mounted) {
      // Losing focus discards an unsubmitted edit, so switching resources can
      // never apply a value captured from the previous wing to the new wing.
      text.text = format(safe);
      if (error != null) setState(() => error = null);
    }
  }

  @override
  void didUpdateWidget(covariant InspectorNumberControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!focus.hasFocus || !widget.enabled) {
      final current = format(safe);
      if (text.text != current) text.text = current;
      error = null;
    }
  }

  void commit(String input) {
    if (!widget.enabled) return;
    final value = double.tryParse(input.trim().replaceAll(',', '.'));
    if (value == null || !value.isFinite || value < widget.min || value > widget.max) {
      setState(() => error = 'Introduce un número entre ${widget.min} y ${widget.max}.');
      return;
    }
    publish(value);
  }

  void publish(double value) {
    if (!widget.enabled || !value.isFinite) return;
    final bounded = value.clamp(widget.min, widget.max).toDouble();
    text.value = TextEditingValue(text: format(bounded),
      selection: TextSelection.collapsed(offset: format(bounded).length));
    setState(() => error = null);
    widget.onChanged(bounded);
  }

  @override
  void dispose() {
    focus.removeListener(_focusChanged);
    focus.dispose();
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(children: [
        Expanded(child: Text(widget.title,
          style: const TextStyle(fontSize: 10, color: Color(0xffaebbd0)))),
        IconButton(tooltip: '-${widget.step}', visualDensity: VisualDensity.compact,
          onPressed: widget.enabled ? () => publish(safe - widget.step) : null,
          icon: const Icon(Icons.remove, size: 14)),
        SizedBox(width: 78, height: 30, child: TextField(
          key: const ValueKey('inspector-number-input'),
          controller: text, focusNode: focus, enabled: widget.enabled,
          textAlign: TextAlign.right,
          keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
          style: const TextStyle(fontSize: 10),
          decoration: InputDecoration(isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
            enabledBorder: error == null ? null : const OutlineInputBorder(
              borderSide: BorderSide(color: Colors.redAccent))),
          onSubmitted: commit,
          // Submission applies without handing keyboard focus to the game.
          onEditingComplete: () {},
        )),
        IconButton(tooltip: '+${widget.step}', visualDensity: VisualDensity.compact,
          onPressed: widget.enabled ? () => publish(safe + widget.step) : null,
          icon: const Icon(Icons.add, size: 14)),
      ]),
      if (error != null) Text(error!, style: const TextStyle(fontSize: 10, color: Colors.redAccent)),
      SizedBox(height: 26, child: Slider(
        value: safe, min: widget.min, max: widget.max,
        onChanged: widget.enabled ? publish : null)),
    ],
  );
}
