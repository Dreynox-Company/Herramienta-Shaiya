import 'package:flutter/material.dart';

class EditorStyle {
  static const background = Color(0xff10151e),
      surface = Color(0xff181f2a),
      panel = Color(0xff1d2633),
      line = Color(0xff303d50),
      accent = Color(0xff9fbbff),
      muted = Color(0xffa0acc1),
      text = Color(0xffe3eaf6);
  static ThemeData theme(ThemeData base) {
    final textTheme = base.textTheme.apply(
      fontFamily: 'Segoe UI',
      fontFamilyFallback: const [
        'Microsoft YaHei',
        'Yu Gothic',
        'Malgun Gothic',
        'Noto Sans CJK SC',
        'Arial',
      ],
      bodyColor: text,
      displayColor: text,
    );
    return base.copyWith(
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.dark,
        surface: surface,
      ),
      scaffoldBackgroundColor: background,
      textTheme: textTheme.copyWith(
        bodyLarge: textTheme.bodyLarge!.copyWith(fontSize: 12),
        bodyMedium: textTheme.bodyMedium!.copyWith(fontSize: 12),
        bodySmall: textTheme.bodySmall!.copyWith(fontSize: 11),
        titleMedium: textTheme.titleMedium!.copyWith(fontSize: 13),
        titleSmall: textTheme.titleSmall!.copyWith(fontSize: 12),
        labelLarge: textTheme.labelLarge!.copyWith(fontSize: 11),
      ),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      appBarTheme: const AppBarTheme(
        toolbarHeight: 44,
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: background,
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(4)),
          borderSide: BorderSide(color: line),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: panel,
        selectedColor: const Color(0xff304468),
        disabledColor: panel,
        side: const BorderSide(color: line),
        labelStyle: textTheme.labelLarge!.copyWith(fontSize: 11),
        secondaryLabelStyle: textTheme.labelLarge!.copyWith(fontSize: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      ),
      iconTheme: const IconThemeData(size: 17, color: muted),
      dividerColor: line,
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(30, 30),
          padding: const EdgeInsets.all(6),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          textStyle: textTheme.labelLarge!.copyWith(fontSize: 11),
          minimumSize: const Size(36, 30),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          textStyle: textTheme.labelLarge!.copyWith(fontSize: 11),
          minimumSize: const Size(36, 30),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: textTheme.labelLarge!.copyWith(fontSize: 11),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          minimumSize: const Size(36, 30),
        ),
      ),
    );
  }
}
