import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../design/design.dart';
import '../../../shared/format.dart';
import '../../rating/ui/arc_widgets.dart';
import '../data/live_feed.dart';
import '../data/match.dart';
import '../data/match_repository.dart';
import 'live_match_view.dart';
import '../../casual_match/verification/ui/verification_widgets.dart';
import '../../casual_match/verification/verification.dart' show MatchLifecycle;
import '../../casual_match/verification/verification_controller.dart';

/// Everything about one match, and the way back into its tournament.
class MatchDetailPage extends ConsumerWidget {
  const MatchDetailPage({super.key, required this.matchId});

  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final match = ref.watch(matchProvider(matchId));
    return Scaffold(
      body: SafeArea(
        child: SxWidth(
          child: Column(
            children: [
              SxBackBar(title: match.value?.kind.label ?? 'Match', onBack: () => _back(context)),
              Expanded(
                child: switch (match) {
                  AsyncData(:final value) => _Body(match: value),
                  AsyncError(:final error) => EmptyBlock(
                      icon: Icons.search_off_rounded,
                      title: 'Match not found',
                      message: error is ApiException ? error.message : 'This match did not load.',
                      action: SxButton.secondary(
                        label: 'My matches',
                        expand: false,
                        onPressed: () => context.go('/player/matches'),
                      ),
                    ),
                  _ => const Padding(padding: EdgeInsets.all(Sx.gutter), child: SkeletonList(rows: 3, rowHeight: 120)),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  static void _back(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/player/matches');
    }
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.match});

  final Match match;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final m = match;
    final now = DateTime.now();
    final state = matchState(m);
    final soon = startsIn(m, now);
    // On court now: rally by rally, when the scorer's feed is there.
    final feed = m.isLive ? ref.watch(liveFeedProvider(m.id)).value : null;

    return ListView(
      padding: EdgeInsets.fromLTRB(Sx.gutter, Sx.s8, Sx.gutter, Sx.s48 + MediaQuery.paddingOf(context).bottom),
      children: [
        // A casual match from this phone that does not count yet, or does now.
        if (m.verification case final lifecycle?) ...[
          _VerificationBanner(matchId: m.id, lifecycle: lifecycle),
          const SizedBox(height: Sx.s16),
        ],
        if (feed != null)
          LiveMatchView(summary: m, match: feed)
        else ...[
          // ── Header ──
          Row(
            children: [
              Expanded(child: Align(alignment: Alignment.centerLeft, child: StateMark(
                state,
                size: 14,
                word: switch (state) {
                  SxState.live => 'LIVE · GAME ${m.live?.number ?? ''}',
                  SxState.won => 'WON ${m.gamesWon}–${m.gamesLost}',
                  SxState.lost => 'LOST ${m.gamesWon}–${m.gamesLost}',
                  SxState.upcoming => soon ?? 'UPCOMING',
                  _ => null,
                },
              ))),
              const SizedBox(width: Sx.s12),
              if (m.pointsEarned != null && m.involvesMe) RatingDelta(m.pointsEarned!, size: 18, digits: 2, unit: ' SXP', what: 'SkorX Points'),
            ],
          ),
          const SizedBox(height: Sx.s16),
          Semantics(header: true, child: Text(m.stageLabel.toUpperCase(), style: SxType.title(c.ink, size: 36))),
          const SizedBox(height: Sx.s4),
          if (m.tournament != null)
            Tappable(
              key: const Key('headerTournament'),
              onTap: () => context.push('/player/tournament/${m.tournament!.id}'),
              radius: 0,
              child: Text(
                '${m.tournament!.name} · ${m.tournament!.category}',
                style: SxType.body(c.ink, size: 15).copyWith(decoration: TextDecoration.underline, decorationColor: c.line),
              ),
            ),
          const SizedBox(height: Sx.s4),
          Text(
            [
              '${dayDate(m.scheduledAt)} · ${time12(m.scheduledAt)}',
              ?m.venue,
              ?m.court,
            ].join(' · '),
            style: SxType.caption(c.inkMuted),
          ),

          if (m.isCancelled) ...[
            const SizedBox(height: Sx.s24),
            SxBlock(
              child: Row(
                children: [
                  Icon(Icons.cloud_off_outlined, color: c.inkMuted),
                  const SizedBox(width: Sx.s12),
                  Expanded(child: Text(m.cancelReason ?? 'This match was cancelled.', style: SxType.body(c.ink))),
                ],
              ),
            ),
          ],

          // ── Score ──
          const SizedBox(height: Sx.s32),
          const SxSection('Score'),
          SxBlock(padding: const EdgeInsets.all(Sx.s20), child: Scoreboard(match: m)),
          if (m.isUpcoming) ...[
            const SizedBox(height: Sx.s12),
            Text(
              m.tournament != null ? 'Report to the desk 30 minutes before your match.' : 'Your court is booked. Arrive 10 minutes early.',
              style: SxType.caption(c.inkMuted),
            ),
          ],
        ],

        // ── SkorX Rating and SkorX Points: what moved and why ──
        if (m.involvesMe && m.pointsBefore != null && m.pointsEarned != null) ...[
          const SizedBox(height: Sx.section),
          SxSection('Rating and Points', action: 'How it works', onAction: () => showArcExplainer(context)),
          if (m.arc != null)
            SxBlock(
              key: const Key('matchImpact'),
              padding: const EdgeInsets.all(Sx.s20),
              child: ArcBreakdown(impact: m.arc!),
            )
          else
            _RatingChange(match: m),
        ],

        // ── Info ──
        const SizedBox(height: Sx.section),
        SxRows(
          title: 'Match information',
          children: [
            SxRow(label: 'Format', value: m.format.label),
            SxRow(label: 'Category', value: m.tournament?.category ?? m.kind.label),
            if (m.tournament != null) SxRow(label: 'Round', value: m.tournament!.round),
            SxRow(label: 'Scoring', value: 'Best of ${m.bestOf} · to ${m.pointsToWin}, win by 2'),
            if (m.court != null) SxRow(label: 'Court', value: m.court),
            if (m.venue != null) SxRow(label: 'Venue', value: m.venue),
            if (m.duration != null) SxRow(label: 'Duration', value: '${m.duration!.inMinutes} min'),
          ],
        ),

        // ── Timeline ──
        if (m.isCompleted || (m.isLive && feed == null)) ...[
          const SizedBox(height: Sx.section),
          const SxSection('Timeline'),
          _Timeline(match: m),
        ],

        // ── Tournament ──
        if (m.tournament != null) ...[
          const SizedBox(height: Sx.section),
          _TournamentLink(match: m),
        ],
      ],
    );
  }
}

/// SkorX Points before and after, for a rated match without the breakdown.
class _RatingChange extends StatelessWidget {
  const _RatingChange({required this.match});

  final Match match;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final m = match;
    return SxBlock(
      key: const Key('matchImpact'),
      padding: const EdgeInsets.all(Sx.s20),
      onTap: () => context.go('/player/paddle'),
      semanticLabel: 'SkorX Points ${sxpText(m.pointsBefore!)} to ${sxpText(m.pointsAfter!)}',
      child: Row(
        children: [
          Expanded(child: Stat(value: sxpText(m.pointsBefore!), label: 'Before', color: c.inkMuted)),
          Icon(Icons.arrow_forward_rounded, color: c.inkFaint),
          const SizedBox(width: Sx.s16),
          Expanded(child: Stat(value: sxpText(m.pointsAfter!), label: 'After')),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              RatingDelta(m.pointsEarned!, size: 28, digits: 2, unit: ' SXP', what: 'SkorX Points'),
              const SizedBox(height: 4),
              Text('CHANGE', style: SxType.label(c.inkMuted, size: 11)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.match});

  final Match match;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final m = match;
    final items = <(String, String?, bool)>[
      ('Match started', m.startedAt == null ? null : time12(m.startedAt!), false),
      for (final (i, g) in m.games.indexed)
        ('Game ${i + 1} · ${g.$1 > g.$2 ? 'won' : 'lost'}', '${g.$1}–${g.$2}', false),
      if (m.live != null) ('Game ${m.live!.number} · in play', '${m.live!.mine}–${m.live!.theirs}', true),
      if (m.isCompleted) ('Match completed', m.completedAt == null ? null : time12(m.completedAt!), false),
    ];
    return Column(
      children: [
        for (final (i, (label, value, live)) in items.indexed)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 20,
                  child: Column(
                    children: [
                      Container(width: 2, height: 14, color: i == 0 ? Colors.transparent : c.line),
                      live
                          ? LivePulse(size: 8, color: c.live)
                          : Container(width: 8, height: 8, decoration: BoxDecoration(color: c.ink, shape: BoxShape.circle)),
                      Expanded(child: Container(width: 2, color: i == items.length - 1 ? Colors.transparent : c.line)),
                    ],
                  ),
                ),
                const SizedBox(width: Sx.s12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: Sx.s8),
                    child: Text(label, style: SxType.body(live ? c.live : c.ink, size: 15)),
                  ),
                ),
                if (value != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: Sx.s8),
                    child: Text(value, style: SxType.number(17, c.inkMuted)),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The match's place in its tournament: the journey strip and one tap in.
class _TournamentLink extends ConsumerWidget {
  const _TournamentLink({required this.match});

  final Match match;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final t = match.tournament!;
    final journey = match.involvesMe ? ref.watch(journeyProvider(t.id)).value : null;
    return SxBlock(
      padding: const EdgeInsets.all(Sx.s20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(journey == null ? 'TOURNAMENT' : 'YOUR JOURNEY', style: SxType.label(c.inkMuted)),
          const SizedBox(height: Sx.s8),
          Text(t.name.toUpperCase(), style: SxType.title(c.ink, size: 24)),
          if (journey != null) ...[
            const SizedBox(height: 2),
            Text(journey.headline, style: SxType.body(c.inkMuted, size: 14)),
            const SizedBox(height: Sx.s16),
            JourneyStrip(journey: journey),
          ],
          const SizedBox(height: Sx.s20),
          SxButton.secondary(
            key: const Key('viewTournament'),
            label: 'View tournament',
            icon: Icons.emoji_events_outlined,
            onPressed: () => context.push('/player/tournament/${t.id}'),
          ),
        ],
      ),
    );
  }
}

/// Where a casual match scored on this phone stands with its players, and
/// the way to the confirmation details.
class _VerificationBanner extends ConsumerWidget {
  const _VerificationBanner({required this.matchId, required this.lifecycle});

  final String matchId;
  final MatchLifecycle lifecycle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final sync = ref.watch(casualSyncProvider)[matchId];
    final v = sync?.record?.verification;
    return SxBlock(
      key: const Key('verificationBanner'),
      onTap: sync?.serverId == null ? null : () => context.push('/player/match-requests/${sync!.serverId}'),
      semanticLabel: 'Verification: ${lifecycle.label}',
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                VerificationChip(lifecycle: lifecycle),
                const SizedBox(height: Sx.s8),
                Text(
                  v == null ? 'Not sent to SkorX yet. It does not count toward stats until every player confirms it.' : lifecycleExplainer(v),
                  style: SxType.caption(c.inkMuted),
                ),
              ],
            ),
          ),
          if (sync?.serverId != null) Icon(Icons.chevron_right_rounded, color: c.inkFaint),
        ],
      ),
    );
  }
}
