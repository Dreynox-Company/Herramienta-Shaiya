import 'package:flutter/material.dart';

abstract final class DreynoxGameStyle {
  static const Color background = Color(0xff07101f);
  static const Color panel = Color(0xe6111d31);
  static const Color panelSoft = Color(0xc9142239);
  static const Color panelStrong = Color(0xf20a1425);
  static const Color surface = Color(0xd9182a45);
  static const Color surfaceSelected = Color(0xe6244268);
  static const Color border = Color(0xff365c86);
  static const Color borderStrong = Color(0xff5aa9e6);
  static const Color accent = Color(0xff51b8ff);
  static const Color accentSoft = Color(0xff86d0ff);
  static const Color text = Color(0xffedf7ff);
  static const Color textMuted = Color(0xff9fb6cd);
  static const Color success = Color(0xff6fe6b7);
  static const Color warning = Color(0xffffcf70);
  static const Color danger = Color(0xffff7d87);

  static BorderRadius get radius => BorderRadius.circular(10);

  static BoxDecoration panelDecoration({
    bool selected = false,
    double opacity = 1,
  }) => BoxDecoration(
    color: (selected ? surfaceSelected : panel).withValues(alpha: opacity),
    borderRadius: radius,
    border: Border.all(
      color: selected ? borderStrong : border,
      width: selected ? 1.35 : 1,
    ),
    boxShadow: const <BoxShadow>[
      BoxShadow(
        color: Color(0x66000000),
        blurRadius: 18,
        offset: Offset(0, 8),
      ),
    ],
  );

  static BoxDecoration headerDecoration() => const BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[Color(0xff1b3a60), Color(0xff0b1a2e)],
    ),
    borderRadius: BorderRadius.vertical(top: Radius.circular(9)),
  );

  static BoxDecoration buttonDecoration({bool active = true}) => BoxDecoration(
    borderRadius: BorderRadius.circular(8),
    border: Border.all(
      color: active ? borderStrong : const Color(0xff29435f),
    ),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: active
          ? const <Color>[Color(0xff245d8f), Color(0xff102a49)]
          : const <Color>[Color(0xff1b2838), Color(0xff101927)],
    ),
    boxShadow: active
        ? const <BoxShadow>[
            BoxShadow(
              color: Color(0x442d9ce0),
              blurRadius: 10,
              offset: Offset(0, 3),
            ),
          ]
        : const <BoxShadow>[],
  );
}
