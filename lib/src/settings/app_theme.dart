import 'package:flutter/material.dart';

/// One palette feeds both themes, including photo placeholders and input chrome.
abstract final class AppTheme {
  static const _seed = Color(0xff73d7ff);
  static ThemeData build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(seedColor: _seed, brightness: brightness).copyWith(
      surface: dark ? const Color(0xff131722) : Colors.white,
      surfaceContainerHighest:
          dark ? const Color(0xff1a1d2b) : const Color(0xffe9edf3),
    );
    return ThemeData(
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          dark ? const Color(0xff090b13) : const Color(0xfff6f7fa),
      appBarTheme: AppBarTheme(
          backgroundColor:
              dark ? const Color(0xff090b13) : const Color(0xfff6f7fa),
          foregroundColor: scheme.onSurface,
          surfaceTintColor: Colors.transparent),
      inputDecorationTheme: InputDecorationTheme(
          filled: true, fillColor: scheme.surfaceContainerHighest),
      cardTheme: CardThemeData(
          color: scheme.surface,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(
                  color: scheme.outlineVariant
                      .withValues(alpha: dark ? .4 : .65)))),
      dialogTheme: DialogThemeData(
          backgroundColor: scheme.surface,
          surfaceTintColor: Colors.transparent,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
      useMaterial3: true,
    );
  }
}
