import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// One palette feeds both themes, including photo placeholders and input chrome.
/// The violet → cyan accent marks AI actions (search, analysis, best match).
abstract final class AppTheme {
  static const _seed = Color(0xff6d4cff);
  static const accentStart = Color(0xff7b61ff);
  static const accentEnd = Color(0xff22c3ee);
  static const accent = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [accentStart, accentEnd]);

  static ThemeData build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final ios = defaultTargetPlatform == TargetPlatform.iOS;
    final scheme =
        ColorScheme.fromSeed(seedColor: _seed, brightness: brightness).copyWith(
      primary: dark ? const Color(0xffa594ff) : const Color(0xff6d4cff),
      onPrimary: dark ? const Color(0xff1a1033) : Colors.white,
      primaryContainer:
          dark ? const Color(0xff2a2350) : const Color(0xffece8ff),
      onPrimaryContainer:
          dark ? const Color(0xffd9d2ff) : const Color(0xff2f1d8f),
      surface: dark ? const Color(0xff17171f) : Colors.white,
      onSurface: dark ? const Color(0xfff3f2f8) : const Color(0xff15141c),
      onSurfaceVariant:
          dark ? const Color(0xff9d9bab) : const Color(0xff6b6979),
      surfaceContainerHighest:
          dark ? const Color(0xff23232d) : const Color(0xffeeedf4),
      outlineVariant: dark ? const Color(0xff2e2e3a) : const Color(0xffe3e1ec),
    );
    final background = dark ? const Color(0xff0c0c11) : const Color(0xfff6f5fa);
    final base = ThemeData(brightness: brightness, useMaterial3: true);
    final text = base.textTheme.copyWith(
      titleLarge: base.textTheme.titleLarge
          ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -.4),
      titleMedium: base.textTheme.titleMedium
          ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -.2),
      titleSmall: base.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: .2,
          color: scheme.onSurfaceVariant),
    );
    return ThemeData(
      brightness: brightness,
      colorScheme: scheme,
      textTheme: text,
      // Cupertino-built controls (segmented control, text actions) follow the
      // same palette on both platforms.
      cupertinoOverrideTheme: CupertinoThemeData(
          brightness: brightness,
          primaryColor: scheme.primary,
          primaryContrastingColor: scheme.onPrimary),
      // Touch feedback stays native: ripples on Android, none on iOS.
      splashFactory: ios ? NoSplash.splashFactory : null,
      // The floating search dock is a transparent bottom sheet.
      bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0),
      scaffoldBackgroundColor: background,
      appBarTheme: AppBarTheme(
          backgroundColor: background,
          foregroundColor: scheme.onSurface,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleTextStyle: text.titleLarge?.copyWith(
              color: scheme.onSurface, fontSize: 22, letterSpacing: -.5)),
      inputDecorationTheme: InputDecorationTheme(
          filled: true, fillColor: scheme.surfaceContainerHighest),
      cardTheme: CardThemeData(
          color: scheme.surface,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: scheme.outlineVariant))),
      listTileTheme: ListTileThemeData(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
              minimumSize: const Size(0, 48),
              shape: const StadiumBorder(),
              textStyle: const TextStyle(fontWeight: FontWeight.w600))),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 48),
              shape: const StadiumBorder(),
              side: BorderSide(color: scheme.outlineVariant))),
      progressIndicatorTheme: ProgressIndicatorThemeData(
          color: scheme.primary,
          linearTrackColor: scheme.surfaceContainerHighest,
          linearMinHeight: 4),
      snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor:
              dark ? const Color(0xff2a2a35) : const Color(0xff1f1e27),
          contentTextStyle: const TextStyle(color: Colors.white),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
      dialogTheme: DialogThemeData(
          backgroundColor: scheme.surface,
          surfaceTintColor: Colors.transparent,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))),
    );
  }
}
