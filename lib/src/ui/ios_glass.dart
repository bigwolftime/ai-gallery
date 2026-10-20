import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

bool usesIosStyle(BuildContext context) =>
    Theme.of(context).platform == TargetPlatform.iOS;

/// Samples and blurs the content behind the chrome as photos scroll under it.
/// A thin tint preserves photo colors; high contrast uses an opaque material.
class IosGlassSurface extends StatelessWidget {
  const IosGlassSurface({super.key, required this.child, this.radius = 26});
  final Widget child;
  final double radius;
  static const blurSigma = 24.0;
  static const lightTintOpacity = .28;
  static const darkTintOpacity = .38;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final opaque = MediaQuery.highContrastOf(context);
    final borderRadius = BorderRadius.circular(radius);
    final surface = DecoratedBox(
      decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(
              alpha: opaque
                  ? 1
                  : dark
                      ? darkTintOpacity
                      : lightTintOpacity),
          borderRadius: borderRadius),
      child: Material(type: MaterialType.transparency, child: child),
    );
    // Clip only the output so the Gaussian filter can sample adjacent photos.
    // No drop shadow or outline: separation comes from the blurred backdrop.
    return ClipRRect(
      borderRadius: borderRadius,
      child: opaque
          ? surface
          : BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
              child: surface),
    );
  }
}

class AdaptiveGlassCard extends StatelessWidget {
  const AdaptiveGlassCard({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => usesIosStyle(context)
      ? IosGlassSurface(child: child)
      : Card(margin: EdgeInsets.zero, child: child);
}

/// Cupertino navigation chrome without requiring an additional icon-font asset.
class AdaptiveNavigationBar extends StatelessWidget
    implements PreferredSizeWidget {
  const AdaptiveNavigationBar(
      {super.key,
      required this.platform,
      required this.title,
      this.actions = const []});
  final TargetPlatform platform;
  final String title;
  final List<Widget> actions;
  static const iosHeight = 44.0;
  @override
  Size get preferredSize => Size.fromHeight(
      platform == TargetPlatform.iOS ? iosHeight : kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    if (platform != TargetPlatform.iOS) {
      return AppBar(title: Text(title), actions: actions);
    }
    final theme = Theme.of(context);
    final opaque = MediaQuery.highContrastOf(context);
    return CupertinoNavigationBar(
      automaticallyImplyLeading: false,
      automaticBackgroundVisibility: false,
      transitionBetweenRoutes: false,
      enableBackgroundFilterBlur: !opaque,
      backgroundColor: theme.colorScheme.surface.withValues(
          alpha: opaque
              ? 1
              : theme.brightness == Brightness.dark
                  ? IosGlassSurface.darkTintOpacity
                  : IosGlassSurface.lightTintOpacity),
      border: null,
      middle: Text(title,
          style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontSize: 17,
              fontWeight: FontWeight.w600)),
      leading: Navigator.canPop(context)
          ? Tooltip(
              message: MaterialLocalizations.of(context).backButtonTooltip,
              child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(44, 44),
                  onPressed: () => Navigator.maybePop(context),
                  child: const BackButtonIcon()))
          : null,
      trailing: actions.isEmpty
          ? null
          : Row(mainAxisSize: MainAxisSize.min, children: actions),
    );
  }
}

Widget adaptiveTextAction(BuildContext context,
        {required String label, required VoidCallback? onPressed}) =>
    usesIosStyle(context)
        ? CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(44, 44),
            onPressed: onPressed,
            child: Text(label))
        : TextButton(onPressed: onPressed, child: Text(label));

Widget adaptivePrimaryAction(BuildContext context,
        {required Widget child, required VoidCallback? onPressed}) =>
    usesIosStyle(context)
        ? CupertinoButton.filled(
            borderRadius: BorderRadius.circular(16),
            onPressed: onPressed,
            child: child)
        : FilledButton(onPressed: onPressed, child: child);
