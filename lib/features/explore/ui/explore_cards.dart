import 'package:flutter/material.dart';

import '../../../design/design.dart';
import '../explore_modules.dart';
import '../explore_signals.dart';

/// Open modules, two to a row, every card in a row the same height.
class ExploreGrid extends StatelessWidget {
  const ExploreGrid({super.key, required this.modules, required this.signalOf, required this.onOpen});

  final List<ExploreModule> modules;
  final ExploreSignal? Function(ExploreModule) signalOf;
  final ValueChanged<ExploreModule> onOpen;

  @override
  Widget build(BuildContext context) {
    final rows = [for (var i = 0; i < modules.length; i += 2) modules.sublist(i, (i + 2).clamp(0, modules.length))];
    return Column(
      children: [
        for (final (r, row) in rows.indexed) ...[
          if (r > 0) const SizedBox(height: Sx.s12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, m) in row.indexed) ...[
                  if (i > 0) const SizedBox(width: Sx.s12),
                  Expanded(child: ExploreModuleCard(module: m, signal: signalOf(m), onTap: () => onOpen(m))),
                ],
                // An odd one out keeps its half width.
                if (row.length == 1) ...[const SizedBox(width: Sx.s12), const Expanded(child: SizedBox())],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// An open module: its mark, name and what it is for, with a live fact
/// when there is one. The module's icon sits large and faint in the corner,
/// so each card has its own texture without extra colour.
class ExploreModuleCard extends StatelessWidget {
  const ExploreModuleCard({super.key, required this.module, required this.onTap, this.signal});

  final ExploreModule module;
  final ExploreSignal? signal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final m = module;
    final colors = m.tone.colors(c);
    return Semantics(
      button: true,
      label: [m.title, m.tagline, ?signal?.text].join(', '),
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Tappable(
          key: Key('explore-${m.id}'),
          onTap: onTap,
          haptic: true,
          radius: Sx.radiusLg,
          child: Container(
            constraints: const BoxConstraints(minHeight: 156),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              gradient: c.card,
              borderRadius: BorderRadius.circular(Sx.radiusLg),
              border: Border.all(color: c.cardEdge),
              boxShadow: c.cardShadow,
            ),
            child: Stack(
              children: [
                Positioned(
                  right: -18,
                  bottom: -22,
                  child: ExcludeSemantics(
                    child: Icon(m.icon, size: 108, color: colors.first.withValues(alpha: c.isDark ? 0.07 : 0.09)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(Sx.s16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SxIconTile(icon: m.icon, size: 42, solid: true, colors: colors),
                          const Spacer(),
                          const _Arrow(),
                        ],
                      ),
                      const Spacer(),
                      const SizedBox(height: Sx.s20),
                      if (signal != null) ...[
                        ExploreSignalPill(signal: signal!),
                        const SizedBox(height: Sx.s8),
                      ],
                      Text(
                        m.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SxType.heading(c.ink, size: 18).copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(m.tagline, maxLines: 2, overflow: TextOverflow.ellipsis, style: SxType.caption(c.inkMuted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow();

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(color: c.ink.withValues(alpha: c.isDark ? 0.08 : 0.05), shape: BoxShape.circle),
      child: Icon(Icons.arrow_outward_rounded, size: 16, color: c.inkMuted),
    );
  }
}

/// "2 live", "Live now": a module's fact, red only when something is on.
class ExploreSignalPill extends StatelessWidget {
  const ExploreSignalPill({super.key, required this.signal});

  final ExploreSignal signal;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final tint = signal.live ? c.live : c.inkMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: c.isDark ? 0.16 : 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (signal.live) ...[
            Container(width: 6, height: 6, decoration: BoxDecoration(color: c.live, shape: BoxShape.circle)),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              signal.text.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SxType.label(tint, size: 10.5, weight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

/// Modules on the way, grouped on one quiet surface: fully shown, lighter
/// than the open ones, each marked SOON.
class ComingSoonList extends StatelessWidget {
  const ComingSoonList({super.key, required this.modules, required this.onTap});

  final List<ExploreModule> modules;
  final ValueChanged<ExploreModule> onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Container(
      decoration: BoxDecoration(
        color: c.surface.withValues(alpha: c.isDark ? 0.6 : 0.75),
        borderRadius: BorderRadius.circular(Sx.radiusLg),
        border: Border.all(color: c.cardEdge),
      ),
      child: Column(
        children: [
          for (final (i, m) in modules.indexed) ...[
            if (i > 0) Divider(height: 1, thickness: 1, indent: 72, endIndent: Sx.s16, color: c.line.withValues(alpha: 0.7)),
            ComingSoonTile(module: m, onTap: () => onTap(m)),
          ],
        ],
      ),
    );
  }
}

class ComingSoonTile extends StatelessWidget {
  const ComingSoonTile({super.key, required this.module, required this.onTap});

  final ExploreModule module;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final m = module;
    return Semantics(
      button: true,
      label: '${m.title}, coming soon. ${m.tagline}',
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Tappable(
          key: Key('explore-${m.id}'),
          onTap: onTap,
          radius: Sx.radiusLg,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 68),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Sx.s16, vertical: Sx.s12),
              child: Row(
                children: [
                  SxIconTile(icon: m.icon, size: 40, colors: m.tone.colors(c)),
                  const SizedBox(width: Sx.s16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(m.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.heading(c.ink, size: 16)),
                        const SizedBox(height: 1),
                        Text(m.tagline, maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.caption(c.inkMuted)),
                      ],
                    ),
                  ),
                  const SizedBox(width: Sx.s8),
                  const SoonBadge(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// SkorX's mark for something on the way: a small outlined volt tag.
class SoonBadge extends StatelessWidget {
  const SoonBadge({super.key, this.text = 'SOON'});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final ink = c.isDark ? c.volt : c.ink;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.voltFill.withValues(alpha: c.isDark ? 0.1 : 0.28),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.voltFill.withValues(alpha: c.isDark ? 0.4 : 0.8)),
      ),
      child: Text(text, style: SxType.label(ink, size: 10.5, weight: FontWeight.w800)),
    );
  }
}
