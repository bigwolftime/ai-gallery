import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// One palette feeds both themes, including photo placeholders and input chrome.
abstract final class AppTheme {
  static const _seed = Color(0xff73d7ff);
  static ThemeData build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final ios = defaultTargetPlatform == TargetPlatform.iOS;
    final scheme =
        ColorScheme.fromSeed(seedColor: _seed, brightness: brightness).copyWith(
      surface: dark
          ? (ios ? const Color(0xff1c1c1e) : const Color(0xff131722))
          : Colors.white,
      surfaceContainerHighest:
          dark ? const Color(0xff1a1d2b) : const Color(0xffe9edf3),
    );
    final colors = ios
        ? scheme.copyWith(
            primary: dark ? const Color(0xff0a84ff) : const Color(0xff007aff),
            onPrimary: Colors.white,
            primaryContainer:
                dark ? const Color(0xff122b4a) : const Color(0xffe4f0ff),
            onPrimaryContainer:
                dark ? const Color(0xffabd2ff) : const Color(0xff0054a7),
            onSurface: dark ? const Color(0xfff5f5f7) : const Color(0xff1c1c1e),
            onSurfaceVariant:
                dark ? const Color(0xffaeaeb2) : const Color(0xff636366),
          )
        : scheme;
    return ThemeData(
      brightness: brightness,
      colorScheme: colors,
      cupertinoOverrideTheme: ios
          ? CupertinoThemeData(
              brightness: brightness,
              primaryColor: colors.primary,
              primaryContrastingColor: Colors.white)
          : null,
      splashFactory: ios ? NoSplash.splashFactory : null,
      bottomSheetTheme: ios
          ? const BottomSheetThemeData(
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              elevation: 0)
          : null,
      scaffoldBackgroundColor: ios
          ? (dark ? const Color(0xff09090d) : const Color(0xfff2f2f7))
          : dark
              ? const Color(0xff090b13)
              : const Color(0xfff6f7fa),
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
