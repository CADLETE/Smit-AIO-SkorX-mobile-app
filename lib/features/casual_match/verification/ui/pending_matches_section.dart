import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../design/design.dart';
import '../../../../shared/format.dart';
import '../../../matches/data/match.dart';
import '../../../matches/data/match_repository.dart';
import '../../played_matches.dart';
import '../verification_controller.dart';
import 'verification_widgets.dart';

/// Verified against pending casual matches, the matches still waiting for
/// players, and the requests waiting for this player. Pending matches are
/// listed here only; they never reach stats, rating or history.
class PendingMatchesSection extends ConsumerStatefulWidget {
  const PendingMatchesSection({super.key});

  @override
  ConsumerState<PendingMatchesSection> createState() => _PendingMatchesSectionState();
}

class _PendingMatchesSectionState extends ConsumerState<PendingMatchesSection> {
  @override
  void initState() {
    super.initState();
    // Anything scored offline is sent now, and every waiting match is checked again.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final sync = ref.read(casualSyncProvider.notifier);
      await ref.read(playedMatchesProvider.notifier).ready;
      if (!mounted) return;
      final played = ref.read(playedMatchesProvider);
      await sync.run();
      for (final m in played) {
        if (!mounted) return;
        if (ref.read(casualSyncProvider)[m.id]?.lifecycle.waiting ?? false) await sync.refresh(m.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final pending = ref.watch(pendingCasualMatchesProvider);
    final requests = ref.watch(matchRequestCountProvider);
    final record = ref.watch(playerRecordProvider).value;
    final verified = record?.finished.where((m) => m.category == MatchCategory.casual).length;
    final waiting = pending.length + requests;

    return Column(
      key: const Key('pendingMatches'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _Count(label: 'Verified', value: verified, color: c.isDark ? c.volt : c.olive, icon: Icons.verified_rounded)),
            const SizedBox(width: Sx.s12),
            Expanded(child: _Count(label: 'Pending', value: waiting, color: c.caution, icon: Icons.hourglass_top_rounded)),
          ],
        ),
        if (requests > 0) ...[
          const SizedBox(height: Sx.s12),
          SxBlock(
            key: const Key('requestsLink'),
            onTap: () => context.push('/player/notifications?tab=requests'),
            semanticLabel: '$requests match ${requests == 1 ? 'request' : 'requests'} waiting for you',
            child: Row(
              children: [
                Icon(Icons.fact_check_outlined, color: c.caution),
                const SizedBox(width: Sx.s12),
                Expanded(
                  child: Text(
                    '$requests match ${requests == 1 ? 'request' : 'requests'} waiting for you',
                    style: SxType.heading(c.ink, size: 15),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: c.inkFaint),
              ],
            ),
          ),
        ],
        if (pending.isNotEmpty) ...[
          const SizedBox(height: Sx.s16),
          Text('PENDING VERIFICATION', style: SxType.label(c.inkMuted, size: 11.5)),
          const SizedBox(height: Sx.s8),
          SxRows(children: [
            for (final m in pending.take(5))
              SxRow(
                key: Key('pending-${m.id}'),
                label: '${sideLabel(m.mine)} vs ${sideLabel(m.theirs)}',
                subtitle: [
                  if (m.games.isNotEmpty) m.games.map((g) => '${g.$1}–${g.$2}').join(', '),
                  dayDate(m.playedAt),
                ].join(' · '),
                trailing: VerificationChip(lifecycle: m.verification!, compact: true),
                onTap: () => context.push('/player/matches/${m.id}'),
              ),
          ]),
          const SizedBox(height: Sx.s8),
          Text("Pending matches don't count toward stats, rating or rankings until every player confirms.",
              style: SxType.caption(c.inkMuted, size: 12.5)),
        ],
      ],
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.label, required this.value, required this.color, required this.icon});

  final String label;
  final int? value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Semantics(
      label: '$label matches: ${value ?? 'loading'}',
      excludeSemantics: true,
      child: SxBlock(
        padding: const EdgeInsets.symmetric(horizontal: Sx.s16, vertical: Sx.s12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: Sx.s8),
            Expanded(child: Text(label, style: SxType.caption(c.inkMuted))),
            Text(value == null ? '—' : '$value', style: SxType.number(22, c.ink, weight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}
