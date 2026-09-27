import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design/design.dart';
import '../data/plans.dart';
import '../subscription_controller.dart';

/// The Pro mark: a small volt tag. Used sparingly: next to the player's name
/// once they are Pro, and on features a Free player has not unlocked yet.
class ProBadge extends StatelessWidget {
  const ProBadge({super.key, this.size = 11, this.locked = false});

  final double size;

  /// On a locked feature: a lock before the word.
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Semantics(
      label: locked ? 'Pro feature' : 'SkorX Pro',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: size * 0.6, vertical: size * 0.22),
        decoration: BoxDecoration(gradient: c.brand, borderRadius: BorderRadius.circular(size)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (locked) ...[Icon(Icons.lock_rounded, size: size + 1, color: c.onVolt), SizedBox(width: size * 0.3)],
            Text('PRO', style: SxType.label(c.onVolt, size: size, weight: FontWeight.w900).copyWith(letterSpacing: 1.2, height: 1.2)),
          ],
        ),
      ),
    );
  }
}

/// Shows [child] when the player has [feature], and [locked] (a
/// [ProLockedPanel] by default) when not. The feature stays visible either
/// way, so a Free player sees what Pro would give them.
class ProGate extends ConsumerWidget {
  const ProGate({super.key, required this.feature, required this.child, this.locked});

  final ProFeature feature;
  final Widget child;
  final Widget? locked;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(canAccessProvider(feature)) ? child : locked ?? ProLockedPanel(feature: feature);
}

/// In place of a Pro feature for a Free player: what it is, the PRO mark,
/// and the way in. Tapping anywhere opens the upgrade prompt.
class ProLockedPanel extends StatelessWidget {
  const ProLockedPanel({super.key, required this.feature, this.message, this.compact = false});

  final ProFeature feature;

  /// What this spot would show; defaults to the feature's pitch.
  final String? message;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return SxBlock(
      key: Key('proLocked-${feature.name}'),
      semanticLabel: '${feature.title}, a SkorX Pro feature. Unlock',
      onTap: () => showProUpsell(context, feature),
      padding: EdgeInsets.all(compact ? Sx.s16 : Sx.s20),
      child: Row(
        children: [
          Container(
            width: compact ? 40 : 48,
            height: compact ? 40 : 48,
            decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(Sx.radiusSm)),
            child: Icon(feature.icon, color: c.inkMuted, size: compact ? 20 : 24),
          ),
          const SizedBox(width: Sx.s16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(feature.title, maxLines: 2, style: SxType.heading(c.ink, size: compact ? 15 : 16)),
                    ),
                    const SizedBox(width: Sx.s8),
                    const ProBadge(locked: true, size: 10),
                  ],
                ),
                const SizedBox(height: Sx.s4),
                Text(message ?? feature.pitch, style: SxType.caption(c.inkMuted, size: 12.5)),
                if (!compact) ...[
                  const SizedBox(height: Sx.s8),
                  Text('Unlock with Pro', style: SxType.caption(c.isDark ? c.cyan : c.blue, size: 13).copyWith(fontWeight: FontWeight.w700)),
                ],
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: c.inkFaint),
        ],
      ),
    );
  }
}

/// A button for a Pro action. For a Free player it wears the PRO mark and
/// opens the upgrade prompt instead of [onPressed].
class ProButton extends ConsumerWidget {
  const ProButton({super.key, required this.feature, required this.label, required this.onPressed, this.icon, this.secondary = false});

  final ProFeature feature;
  final String label;
  final IconData? icon;
  final VoidCallback onPressed;
  final bool secondary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allowed = ref.watch(canAccessProvider(feature));
    final tap = allowed ? onPressed : () => showProUpsell(context, feature);
    final button = secondary
        ? SxButton.secondary(label: label, icon: allowed ? icon : Icons.lock_outline_rounded, onPressed: tap)
        : SxButton(label: label, icon: allowed ? icon : Icons.lock_outline_rounded, onPressed: tap);
    if (allowed) return button;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        button,
        const Positioned(right: 10, top: -7, child: ExcludeSemantics(child: ProBadge(size: 10))),
      ],
    );
  }
}

/// Runs [action] when the player has [feature]; otherwise the upgrade prompt.
void whenPro(BuildContext context, WidgetRef ref, ProFeature feature, VoidCallback action) {
  if (ref.read(canAccessProvider(feature))) {
    action();
  } else {
    showProUpsell(context, feature);
  }
}

/// "Unlock Match Analytics": what the feature gives, everything else Pro
/// adds, and the way to the plans.
Future<void> showProUpsell(BuildContext context, ProFeature feature) {
  final router = GoRouter.of(context);
  return showSxSheet<void>(
    context,
    gradientBorder: true,
    builder: (ctx) {
      final c = ctx.sx;
      return SingleChildScrollView(
        key: const Key('proUpsell'),
        padding: const EdgeInsets.fromLTRB(Sx.gutter, 0, Sx.gutter, Sx.s24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [const ProBadge(size: 12), const SizedBox(width: Sx.s8), Text('SKORX PRO', style: SxType.label(c.inkMuted))]),
            const SizedBox(height: Sx.s12),
            Text('Unlock ${feature.title}', style: SxType.title(c.ink, size: 30)),
            const SizedBox(height: Sx.s8),
            Text(feature.pitch, style: SxType.body(c.inkMuted)),
            const SizedBox(height: Sx.s20),
            for (final f in _pitchOrder(feature)) _Check(label: f.short, strong: f == feature),
            const SizedBox(height: Sx.s8),
            Text('From ₹${ProPlan.monthly.price} + GST a month, or ₹${ProPlan.annual.price} + GST a year.',
                style: SxType.caption(c.inkMuted)),
            const SizedBox(height: Sx.s24),
            SxButton(
              key: const Key('viewProPlans'),
              label: 'View Pro Plans',
              icon: Icons.bolt_rounded,
              onPressed: () {
                Navigator.of(ctx).pop();
                router.push('/player/pro?feature=${feature.name}');
              },
            ),
            const SizedBox(height: Sx.s8),
            Center(child: SxButton.quiet(key: const Key('maybeLater'), label: 'Maybe Later', onPressed: () => Navigator.of(ctx).pop())),
          ],
        ),
      );
    },
  );
}

/// The feature asked about first, then the rest in the pricing sheet's order.
List<ProFeature> _pitchOrder(ProFeature first) => [first, ...ProFeature.values.where((f) => f != first)];

class _Check extends StatelessWidget {
  const _Check({required this.label, this.strong = false});

  final String label;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Padding(
      padding: const EdgeInsets.only(bottom: Sx.s12),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded, size: 20, color: c.volt),
          const SizedBox(width: Sx.s12),
          Expanded(
            child: Text(label, style: SxType.body(c.ink, size: 15).copyWith(fontWeight: strong ? FontWeight.w700 : FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

/// A ✓ list of what Pro unlocks, for the plan cards and the welcome screen.
class ProFeatureList extends StatelessWidget {
  const ProFeatureList({super.key, this.titles = false});

  /// The full names from the pricing sheet rather than the short ones.
  final bool titles;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final f in ProFeature.values) _Check(label: titles ? f.title : f.short)],
      );
}
