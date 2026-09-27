import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design/design.dart';
import '../data/looking_for.dart';
import '../looking_for_controller.dart';

const _nearby = LfQuery(tab: LfTab.nearby);

/// Home's way into Looking For: the one thing worth knowing now (new
/// responses to my request, or what is open near me), else the prompt to post.
class LookingForHomeCard extends ConsumerWidget {
  const LookingForHomeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final pending = ref.watch(lfCountsProvider).value?.pendingResponses ?? 0;
    final near = ref.watch(lfFeedProvider(_nearby)).value?.posts ?? const <LfPost>[];
    final (title, subtitle, route) = pending > 0
        ? (
            pending == 1 ? '1 new response' : '$pending new responses',
            'People answered your Looking For. Accept or decline.',
            '/player/looking-for?tab=mine',
          )
        : near.isNotEmpty
            ? (
                near.length == 1 ? '1 request near you' : '${near.length}${near.length >= 20 ? '+' : ''} requests near you',
                near.first.title,
                '/player/looking-for?tab=nearby',
              )
            : ('Looking for 2 players tonight?', 'Post what you need. SkorX finds people who fit.', '/player/looking-for/new');
    return Semantics(
      button: true,
      label: 'Looking For: $title',
      excludeSemantics: true,
      child: Tappable(
        key: const Key('homeLookingFor'),
        onTap: () => context.push(route),
        child: Container(
          padding: const EdgeInsets.all(Sx.s16),
          decoration: BoxDecoration(
            gradient: c.card,
            borderRadius: BorderRadius.circular(Sx.radiusLg),
            border: Border.all(color: pending > 0 ? c.volt.withValues(alpha: 0.6) : c.cardEdge),
            boxShadow: c.cardShadow,
          ),
          child: Row(
            children: [
              SxIconTile(icon: Icons.radar_rounded, size: 44, solid: pending > 0, colors: [c.voltFill, c.olive]),
              const SizedBox(width: Sx.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('LOOKING FOR', style: SxType.label(c.inkMuted, size: 11)),
                    const SizedBox(height: 2),
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.heading(c.ink, size: 16)),
                    Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.caption(c.inkMuted)),
                  ],
                ),
              ),
              const SizedBox(width: Sx.s8),
              Text(pending > 0 || near.isNotEmpty ? 'Open' : 'Explore', style: SxType.label(c.volt, size: 12)),
              Icon(Icons.chevron_right_rounded, color: c.volt),
            ],
          ),
        ),
      ),
    );
  }
}
