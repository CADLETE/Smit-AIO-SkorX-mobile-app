import 'package:flutter/material.dart';

import '../app/theme/app_theme.dart';
import '../app/theme/tokens.dart';

/// The SkorX brand logo (transparent PNG with its own dark outline, so it
/// reads on both light and dark surfaces).
class SkorxLogo extends StatelessWidget {
  const SkorxLogo({super.key, this.height = 32, this.glow = false});

  static const asset = 'assets/brand/skorx_logo.png';

  /// Source is 3523x1222.
  static const aspectRatio = 3523 / 1222;

  final double height;

  /// A soft volt-and-blue light behind the mark, for the starting screens
  /// where the logo is the hero.
  final bool glow;

  @override
  Widget build(BuildContext context) {
    // Decode at display size instead of the full 3.5k source. The first frame
    // on Android can report a zero-sized view (pixel ratio 0); decode at full
    // size then rather than asking for a 0 px image.
    final cacheHeight = (height * MediaQuery.devicePixelRatioOf(context)).round();
    final image = Image.asset(
      asset,
      height: height,
      width: height * aspectRatio,
      cacheHeight: cacheHeight > 0 ? cacheHeight : null,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      semanticLabel: 'SkorX',
    );
    if (!glow) return image;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Positioned(
          left: -height * 0.6,
          right: -height * 0.6,
          top: -height * 0.9,
          bottom: -height * 0.9,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  radius: 0.62,
                  colors: [
                    SkorxColors.dark.lime.withValues(alpha: 0.22),
                    SkorxColors.dark.blue.withValues(alpha: 0.10),
                    SkorxColors.dark.blue.withValues(alpha: 0),
                  ],
                  stops: const [0, 0.5, 1],
                ),
              ),
            ),
          ),
        ),
        image,
      ],
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: SkorxSpace.xl, bottom: SkorxSpace.md),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w800,
                    color: context.skorx.colors.textMuted,
                  ),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

/// What a list shows when there is nothing in it yet: what it is for and,
/// where there is one, the next thing to do.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.action});

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(SkorxSpace.xl),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(SkorxRadius.lg),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          Icon(icon, size: 32, color: colors.textMuted),
          const SizedBox(height: SkorxSpace.md),
          Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: SkorxSpace.xs),
          Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.textMuted),
            textAlign: TextAlign.center,
          ),
          if (action != null) ...[const SizedBox(height: SkorxSpace.lg), action!],
        ],
      ),
    );
  }
}

/// A shown-once banner when the app is working from cached data.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: SkorxSpace.lg, vertical: SkorxSpace.sm),
        color: colors.surfaceInteractive,
        child: Row(
          children: [
            Icon(Icons.cloud_off_rounded, size: 18, color: colors.textMuted),
            const SizedBox(width: SkorxSpace.sm),
            Expanded(
              child: Text(
                'Offline. Showing what was saved on this phone.',
                style: TextStyle(color: colors.textMuted, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
