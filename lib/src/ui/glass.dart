import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One visual language on iOS and Android. Platform checks are reserved for
/// behavior and copy (for example iCloud downloads), never for styling.
bool isApplePlatform(BuildContext context) =>
    Theme.of(context).platform == TargetPlatform.iOS;

/// Samples and blurs the content behind the chrome as photos scroll under it.
/// A thin tint preserves photo colors; high contrast uses an opaque material.
class GlassSurface extends StatelessWidget {
  const GlassSurface({super.key, required this.child, this.radius = 26});
  final Widget child;
  final double radius;
  static const blurSigma = 24.0;
  static const lightTintOpacity = .28;
  static const darkTintOpacity = .38;

  static Color tint(BuildContext context) {
    final theme = Theme.of(context);
    return theme.colorScheme.surface.withValues(
        alpha: MediaQuery.highContrastOf(context)
            ? 1
            : theme.brightness == Brightness.dark
                ? darkTintOpacity
                : lightTintOpacity);
  }

  @override
  Widget build(BuildContext context) {
    final opaque = MediaQuery.highContrastOf(context);
    final borderRadius = BorderRadius.circular(radius);
    final surface = DecoratedBox(
      decoration:
          BoxDecoration(color: tint(context), borderRadius: borderRadius),
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

/// Solid grouped-content card used by settings and banners.
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      Card(margin: EdgeInsets.zero, clipBehavior: Clip.antiAlias, child: child);
}

/// Translucent navigation bar with a centered title, shared by every page.
class GlassNavigationBar extends StatelessWidget
    implements PreferredSizeWidget {
  const GlassNavigationBar(
      {super.key, required this.title, this.actions = const []});
  final String title;
  final List<Widget> actions;
  static const height = 44.0;
  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // AppBar/CupertinoNavigationBar used to pick the status bar icon color;
    // do the same so it stays readable on dark pages such as photo detail.
    final overlay = (theme.brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark)
        .copyWith(statusBarColor: Colors.transparent);
    return AnnotatedRegion<SystemUiOverlayStyle>(
        value: overlay, child: bar(context, scheme));
  }

  Widget bar(BuildContext context, ColorScheme scheme) {
    return GlassSurface(
      radius: 0,
      child: Padding(
        padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
        child: SizedBox(
          height: height,
          child: NavigationToolbar(
            middleSpacing: 8,
            leading: Navigator.canPop(context)
                ? Tooltip(
                    message:
                        MaterialLocalizations.of(context).backButtonTooltip,
                    child: CupertinoButton(
                        padding: const EdgeInsets.only(left: 8),
                        minimumSize: const Size(44, 44),
                        onPressed: () => Navigator.maybePop(context),
                        child: Icon(Icons.arrow_back_ios_new_rounded,
                            size: 21, color: scheme.primary)))
                : null,
            middle: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 17,
                    fontWeight: FontWeight.w600)),
            trailing: actions.isEmpty
                ? null
                : Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child:
                        Row(mainAxisSize: MainAxisSize.min, children: actions)),
          ),
        ),
      ),
    );
  }
}

/// Plain text action in the accent color, used in bars and inline headers.
class AppTextAction extends StatelessWidget {
  const AppTextAction({super.key, required this.label, this.onPressed});
  final String label;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(44, 44),
        onPressed: onPressed,
        child: Text(label,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: onPressed == null
                    ? scheme.onSurfaceVariant
                    : scheme.primary)));
  }
}
