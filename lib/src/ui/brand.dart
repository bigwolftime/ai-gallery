import 'package:flutter/material.dart';
import '../settings/app_theme.dart';

/// Paints an icon with the AI accent gradient.
class GradientIcon extends StatelessWidget {
  const GradientIcon(this.icon, {super.key, this.size = 22});
  final IconData icon;
  final double size;
  @override
  Widget build(BuildContext context) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) => AppTheme.accent.createShader(bounds),
        child: Icon(icon, size: size, color: Colors.white),
      );
}

/// Circular gradient action, used for submitting a natural-language search.
class GradientCircleButton extends StatelessWidget {
  const GradientCircleButton(
      {super.key,
      required this.icon,
      required this.onPressed,
      this.tooltip,
      this.size = 36});
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  @override
  Widget build(BuildContext context) {
    final button = AnimatedOpacity(
      opacity: onPressed == null ? .35 : 1,
      duration: const Duration(milliseconds: 150),
      child: Material(
        type: MaterialType.transparency,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: const BoxDecoration(
              gradient: AppTheme.accent, shape: BoxShape.circle),
          child: InkWell(
            onTap: onPressed,
            child: SizedBox.square(
                dimension: size,
                child: Icon(icon, size: size * .52, color: Colors.white)),
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// Soft gradient disc holding an icon; anchors empty and onboarding states.
class BrandBadge extends StatelessWidget {
  const BrandBadge({super.key, required this.icon, this.size = 72});
  final IconData icon;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.accentStart.withValues(alpha: .18),
                AppTheme.accentEnd.withValues(alpha: .18),
              ]),
        ),
        child: Center(child: GradientIcon(icon, size: size * .46)),
      );
}

/// Centered illustration + copy + actions for loading, empty and error states.
class StateMessage extends StatelessWidget {
  const StateMessage(
      {super.key,
      required this.icon,
      required this.title,
      this.body,
      this.children = const []});
  final IconData icon;
  final String title;
  final String? body;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            BrandBadge(icon: icon),
            const SizedBox(height: 22),
            Text(title,
                textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
            if (body != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(body!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.5)),
              ),
            if (children.isNotEmpty) const SizedBox(height: 24),
            ...children,
          ]),
        ),
      ),
    );
  }
}
