import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../design/design.dart';
import '../../../shared/format.dart';
import '../../matches/data/match_repository.dart';
import '../../matches/ui/match_card.dart' show LoadMoreTrigger;
import '../../subscription/data/plans.dart';
import '../../subscription/subscription_controller.dart';
import '../../subscription/ui/pro_widgets.dart';
import '../data/player_stats.dart';
import 'player_quick_view.dart';

/// A player's full stats: overview, form, trend, tournaments, rivals and
/// every match. The same page for the signed-in player and anyone else.
class PlayerStatsPage extends ConsumerStatefulWidget {
  const PlayerStatsPage({super.key, required this.playerId});

  final String playerId;

  @override
  ConsumerState<PlayerStatsPage> createState() => _PlayerStatsPageState();
}

class _PlayerStatsPageState extends ConsumerState<PlayerStatsPage> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 500) ref.read(playerMatchesProvider(widget.playerId).notifier).loadMore();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final id = widget.playerId;
    ref.invalidate(playerProfileProvider(id));
    ref.invalidate(playerStatsProvider(id));
    ref.invalidate(playerCardProvider(id));
    ref.invalidate(playerRivalsProvider(id));
    ref.invalidate(playerMatchesProvider(id));
    await ref.read(playerStatsProvider(id).future);
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.playerId;
    final profile = ref.watch(playerProfileProvider(id));
    final stats = ref.watch(playerStatsProvider(id));
    final c = context.sx;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: SxWidth(
          child: Column(
            children: [
              SxBackBar(
                title: profile.value?.isMe ?? false ? 'My stats' : 'Player stats',
                onBack: () => context.canPop() ? context.pop() : context.go('/player/matches'),
              ),
              Expanded(
                child: switch ((profile, stats)) {
                  (AsyncError(:final error), _) || (_, AsyncError(:final error)) => EmptyBlock(
                      icon: Icons.person_off_outlined,
                      title: 'Player not found',
                      message: error is ApiException ? error.message : 'This player did not load.',
                      action: SxButton.secondary(label: 'Try again', expand: false, onPressed: _refresh),
                    ),
                  (AsyncData(value: final p), AsyncData(value: final s)) => RefreshIndicator(
                      onRefresh: _refresh,
                      color: c.onVolt,
                      backgroundColor: c.voltFill,
                      child: ListView(
                        key: const Key('playerStats'),
                        controller: _scroll,
                        padding: EdgeInsets.fromLTRB(Sx.gutter, Sx.s8, Sx.gutter, Sx.s48 + MediaQuery.paddingOf(context).bottom),
                        children: [
                          for (final (i, child) in _sections(context, p, s).indexed) SxReveal(index: i, child: child),
                        ],
                      ),
                    ),
                  _ => const _StatsSkeleton(),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _sections(BuildContext context, PlayerProfile p, PlayerStats s) {
    final c = context.sx;
    final history = p.isMe ? ref.watch(ratingHistoryProvider).value ?? const [] : const [];
    // Another player's full record is Rival Player Stats; my own trends are
    // Match Analytics. Both are SkorX Pro.
    final rivals = ref.watch(canAccessProvider(ProFeature.rivalStats));
    final analytics = ref.watch(canAccessProvider(ProFeature.matchAnalytics));
    if (!p.isMe && !rivals) {
      return [
        _Overview(profile: p, stats: s),
        const SizedBox(height: Sx.section),
        ProLockedPanel(
          feature: ProFeature.rivalStats,
          message: 'See ${p.name.split(' ').first}’s full record, form, tournaments, rivals and every match, and your head-to-head.',
        ),
      ];
    }
    return [
      _Overview(profile: p, stats: s),
      if (s.formats.isNotEmpty) ...[const SizedBox(height: Sx.s16), FormatTiles(formats: s.formats)],
      if (s.career.played == 0)
        EmptyBlock(
          icon: Icons.sports_tennis_rounded,
          title: p.isMe ? 'No matches yet' : 'No matches on SkorX yet',
          message: p.isMe
              ? 'Play your first match and start building your SkorX record.'
              : 'Their stats appear here after their first finished match.',
        )
      else ...[
        const SizedBox(height: Sx.section),
        _FormSection(stats: s),
        const SizedBox(height: Sx.section),
        const SxSection('Win / loss trend'),
        if (!analytics)
          const ProLockedPanel(
            feature: ProFeature.matchAnalytics,
            message: 'Your win / loss trend, points graph and splits by format, partner and opponent.',
          )
        else ...[
          TrendBars(form: s.form),
          if (history.length > 1) ...[
            const SizedBox(height: Sx.s24),
            Text('SKORX RATING', style: SxType.label(c.inkMuted, size: 12)),
            const SizedBox(height: Sx.s8),
            RatingGraph(
              values: [for (final h in history.skip(history.length > 20 ? history.length - 20 : 0)) h.rating],
              height: 96,
              minSpan: 4,
              label: 'SkorX Rating',
            ),
          ],
          const SizedBox(height: Sx.section),
          _SplitSection(stats: s),
        ],
        if (s.tournaments.isNotEmpty) ...[
          const SizedBox(height: Sx.section),
          _TournamentsSection(runs: s.tournaments),
        ],
        const SizedBox(height: Sx.section),
        if (rivals)
          _RivalsSection(playerId: p.id, name: p.name)
        else ...[
          const SxSection('Rivals'),
          const ProLockedPanel(
            feature: ProFeature.rivalStats,
            message: 'The players you meet most, your record against each, and every match you played them.',
          ),
        ],
        const SizedBox(height: Sx.section),
        const SxSection('Recent matches'),
        _RecentMatches(playerId: p.id),
      ],
    ];
  }
}

/// The hero: who they are, their SkorX Points and their record.
class _Overview extends StatelessWidget {
  const _Overview({required this.profile, required this.stats});

  final PlayerProfile profile;
  final PlayerStats stats;

  @override
  Widget build(BuildContext context) {
    final s = stats.career;
    return SxHeroCard(
      key: const Key('playerOverview'),
      padding: const EdgeInsets.all(Sx.s20),
      child: SxOnHero(
        child: Builder(builder: (context) {
          final c = context.sx;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(padding: const EdgeInsets.only(right: 56), child: PlayerHeader(profile: profile, size: 60)),
              const SizedBox(height: Sx.s20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.bottomLeft,
                      child: Text(profile.rating == null ? '—' : ratingText(profile.rating!),
                          style: SxType.hero(72, c.ink)),
                    ),
                  ),
                  const SizedBox(width: Sx.s12),
                  Padding(
                    padding: const EdgeInsets.only(bottom: Sx.s8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('SKORX\nRATING', style: SxType.label(c.inkMuted, size: 12)),
                        if (profile.points != null) ...[
                          const SizedBox(height: Sx.s4),
                          Text('${sxpText(profile.points!)} SkorX Points', style: SxType.caption(c.inkMuted, size: 12)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Sx.s16),
              SizedBox(height: 8, child: NetLine(color: Colors.white.withValues(alpha: 0.3), markColor: c.voltFill)),
              const SizedBox(height: Sx.s16),
              Row(
                children: [
                  Expanded(child: Stat(value: '${s.played}', label: 'Matches', size: 26)),
                  Expanded(child: Stat(value: '${s.wins}', label: 'Won', size: 26, color: s.wins > 0 ? c.volt : null)),
                  Expanded(child: Stat(value: '${s.losses}', label: 'Lost', size: 26)),
                  Expanded(child: Stat(value: s.winRate == null ? '—' : '${s.winRate}%', label: 'Win %', size: 26)),
                ],
              ),
            ],
          );
        }),
      ),
    );
  }
}

class _FormSection extends StatelessWidget {
  const _FormSection({required this.stats});

  final PlayerStats stats;

  @override
  Widget build(BuildContext context) {
    final s = stats;
    String pct(int? v) => v == null ? '—' : '$v%';
    return Column(
      key: const Key('currentForm'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SxSection('Current form'),
        FormStrip(form: s.form.take(10).toList(), size: 28),
        const SizedBox(height: Sx.s20),
        Row(
          children: [
            Expanded(child: Stat(value: pct(s.winRateOfLast(5)), label: 'Last 5', size: 24)),
            Expanded(child: Stat(value: pct(s.winRateOfLast(10)), label: 'Last 10', size: 24)),
            Expanded(child: Stat(value: s.streakLabel ?? '—', label: 'Streak', size: 24)),
            Expanded(child: Stat(value: '${s.bestWinStreak}', label: 'Best run', size: 24)),
          ],
        ),
      ],
    );
  }
}

/// The last results as bars above (win) or below (loss) a line, oldest on
/// the left. Nothing to read but the shape.
class TrendBars extends StatelessWidget {
  const TrendBars({super.key, required this.form, this.height = 72});

  /// Newest first, as [PlayerStats.form] keeps it.
  final List<bool> form;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final oldestFirst = form.reversed.toList();
    final wins = form.where((w) => w).length;
    return Semantics(
      label: 'Last ${form.length} results: $wins won, ${form.length - wins} lost',
      excludeSemantics: true,
      child: Column(
        children: [
          SizedBox(
            height: height,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, won) in oldestFirst.indexed) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: won
                                ? Container(
                                    decoration: BoxDecoration(gradient: c.brand, borderRadius: BorderRadius.circular(4)),
                                    height: height * 0.42,
                                  )
                                : null,
                          ),
                        ),
                        Container(height: 2, color: c.line),
                        Expanded(
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: won
                                ? null
                                : Container(
                                    decoration: BoxDecoration(color: c.inkFaint.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(4)),
                                    height: height * 0.3,
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                // Keep bars a sensible width when there are only a few.
                for (var i = oldestFirst.length; i < 10; i++) ...[const SizedBox(width: 6), const Expanded(child: SizedBox())],
              ],
            ),
          ),
          const SizedBox(height: Sx.s8),
          Row(
            children: [
              Text('OLDER', style: SxType.label(c.inkFaint, size: 10.5)),
              const Spacer(),
              Text('LATEST', style: SxType.label(c.inkFaint, size: 10.5)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Casual play against tournament play.
class _SplitSection extends StatelessWidget {
  const _SplitSection({required this.stats});

  final PlayerStats stats;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    Widget half(WinLoss w) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(w.label.toUpperCase(), style: SxType.label(c.inkMuted, size: 12)),
              const SizedBox(height: Sx.s8),
              Text('${w.wins}–${w.losses}', style: SxType.number(28, c.ink, weight: FontWeight.w800)),
              const SizedBox(height: Sx.s4),
              RecordBar(wins: w.wins, losses: w.losses, height: 5),
              const SizedBox(height: Sx.s4),
              Text(w.played == 0 ? 'No matches' : '${w.winRate}% won · ${w.played} played', style: SxType.caption(c.inkMuted, size: 12)),
            ],
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SxSection('Casual and tournament'),
        Row(children: [half(stats.casual), const SizedBox(width: Sx.s24), half(stats.tournament)]),
      ],
    );
  }
}

class _TournamentsSection extends StatelessWidget {
  const _TournamentsSection({required this.runs});

  final List<TournamentRun> runs;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return SxRows(
      title: 'Recent tournaments',
      children: [
        for (final r in runs.take(4))
          SxRow(
            icon: r.result == 'Champion' ? Icons.emoji_events_rounded : Icons.emoji_events_outlined,
            label: r.name,
            subtitle: '${r.result} · ${relativeDay(r.lastPlayed, DateTime.now())}',
            trailing: Text('${r.wins}–${r.losses}', style: SxType.number(20, c.ink, weight: FontWeight.w800)),
            onTap: () => context.push('/player/tournament/${r.id}?view=matches'),
          ),
      ],
    );
  }
}

class _RivalsSection extends ConsumerStatefulWidget {
  const _RivalsSection({required this.playerId, required this.name});

  final String playerId;
  final String name;

  @override
  ConsumerState<_RivalsSection> createState() => _RivalsSectionState();
}

class _RivalsSectionState extends ConsumerState<_RivalsSection> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final rivals = ref.watch(playerRivalsProvider(widget.playerId));
    return Column(
      key: const Key('rivals'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SxSection(
          'Rivals',
          action: (rivals.value?.length ?? 0) > 4 && !_all ? 'All ${rivals.value!.length}' : null,
          onAction: () => setState(() => _all = true),
        ),
        switch (rivals) {
          AsyncData(:final value) when value.isEmpty =>
            Text('Rivals show up once they have played someone twice.', style: SxType.body(context.sx.inkMuted)),
          AsyncData(:final value) => Column(
              children: [
                for (final r in value.take(_all ? value.length : 4))
                  Padding(
                    padding: const EdgeInsets.only(bottom: Sx.s8),
                    child: RivalRow(rival: r, onTap: () => context.push(headToHeadPath(widget.playerId, r.player.id))),
                  ),
              ],
            ),
          AsyncError() => ErrorBlock(message: 'Rivals did not load.', onRetry: () => ref.invalidate(playerRivalsProvider(widget.playerId))),
          _ => const SkeletonList(rows: 3, rowHeight: 64),
        },
      ],
    );
  }
}

/// A rival: who, how often, and the head-to-head from the player's side.
class RivalRow extends StatelessWidget {
  const RivalRow({super.key, required this.rival, required this.onTap});

  final Rival rival;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final r = rival.record;
    final ahead = r.wins > r.losses;
    return SxBlock(
      key: Key('rival-${rival.player.id}'),
      onTap: onTap,
      semanticLabel: 'Versus ${rival.player.name}: ${r.played} matches, ${r.wins} won, ${r.losses} lost. Open head-to-head',
      padding: const EdgeInsets.symmetric(horizontal: Sx.s16, vertical: Sx.s12),
      child: Row(
        children: [
          PlayerTap(name: rival.player.matchName, child: PlayerDp(name: rival.player.matchName, size: 40)),
          const SizedBox(width: Sx.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('vs ${rival.player.isMe ? 'You' : rival.player.name}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.heading(c.ink, size: 15)),
                const SizedBox(height: 2),
                Text(
                  '${r.played} matches · last ${relativeDay(rival.last.playedAt, DateTime.now()).toLowerCase()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SxType.caption(c.inkMuted, size: 12),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${r.wins}–${r.losses}', style: SxType.number(22, ahead ? c.volt : c.ink, weight: FontWeight.w800)),
              Text('${r.winRate}% WON', style: SxType.label(c.inkFaint, size: 10)),
            ],
          ),
          Icon(Icons.chevron_right_rounded, color: c.inkFaint),
        ],
      ),
    );
  }
}

class _RecentMatches extends ConsumerWidget {
  const _RecentMatches({required this.playerId});

  final String playerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final page = ref.watch(playerMatchesProvider(playerId));
    return switch (page) {
      AsyncData(:final value) => Column(
          key: const Key('recentMatches'),
          children: [
            for (final (i, m) in value.matches.indexed) ...[
              if (i > 0) Divider(height: 1, color: c.line),
              MatchRow(match: m, onTap: () => context.push('/player/matches/${m.id}')),
            ],
            if (value.hasMore)
              LoadMoreTrigger(
                key: ValueKey('more-${value.matches.length}'),
                onLoad: () => ref.read(playerMatchesProvider(playerId).notifier).loadMore(),
              )
            else
              Padding(
                padding: const EdgeInsets.all(Sx.s24),
                child: Center(child: Text('${value.matches.length} matches', style: SxType.label(c.inkFaint))),
              ),
          ],
        ),
      AsyncError() => ErrorBlock(message: 'Matches did not load.', onRetry: () => ref.invalidate(playerMatchesProvider(playerId))),
      _ => const SkeletonList(rows: 4, rowHeight: 72),
    };
  }
}

class _StatsSkeleton extends StatelessWidget {
  const _StatsSkeleton();

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s8, Sx.gutter, Sx.s48),
        children: const [
          Skeleton(height: 250, radius: Sx.radiusLg),
          SizedBox(height: Sx.s16),
          Row(
            children: [
              Expanded(child: Skeleton(height: 96, radius: Sx.radius)),
              SizedBox(width: Sx.s8),
              Expanded(child: Skeleton(height: 96, radius: Sx.radius)),
              SizedBox(width: Sx.s8),
              Expanded(child: Skeleton(height: 96, radius: Sx.radius)),
            ],
          ),
          SizedBox(height: Sx.section),
          Skeleton(height: 18, width: 140),
          SizedBox(height: Sx.s12),
          Skeleton(height: 28),
          SizedBox(height: Sx.section),
          SkeletonList(rows: 3, rowHeight: 64),
        ],
      );
}

/// Two players, every time they have met.
class HeadToHeadPage extends ConsumerWidget {
  const HeadToHeadPage({super.key, required this.a, required this.b});

  final String a;
  final String b;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h2h = ref.watch(headToHeadProvider((a, b)));
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: SxWidth(
          child: Column(
            children: [
              SxBackBar(title: 'Head-to-head', onBack: () => context.canPop() ? context.pop() : context.go(playerStatsPath(a))),
              Expanded(
                child: switch (h2h) {
                  AsyncData(:final value) => ProGate(
                      feature: ProFeature.rivalStats,
                      locked: const Padding(
                        padding: EdgeInsets.all(Sx.gutter),
                        child: ProLockedPanel(feature: ProFeature.rivalStats),
                      ),
                      child: _HeadToHeadBody(h2h: value),
                    ),
                  AsyncError() => ErrorBlock(message: 'This head-to-head did not load.', onRetry: () => ref.invalidate(headToHeadProvider((a, b)))),
                  _ => const Padding(
                      padding: EdgeInsets.all(Sx.gutter),
                      child: Column(children: [Skeleton(height: 220, radius: Sx.radiusLg), SizedBox(height: Sx.s24), SkeletonList(rows: 3)]),
                    ),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeadToHeadBody extends StatelessWidget {
  const _HeadToHeadBody({required this.h2h});

  final HeadToHead h2h;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final h = h2h;
    final aName = h.a.isMe ? 'You' : h.a.name.split(' ').first;
    final bName = h.b.isMe ? 'You' : h.b.name.split(' ').first;
    final verdict = h.played == 0
        ? 'Never met'
        : h.aWins == h.bWins
            ? 'Level at ${h.aWins}–${h.bWins}'
            : '${h.aWins > h.bWins ? aName : bName} ${h.aWins > h.bWins && h.a.isMe || h.bWins > h.aWins && h.b.isMe ? 'lead' : 'leads'} '
                '${h.aWins > h.bWins ? '${h.aWins}–${h.bWins}' : '${h.bWins}–${h.aWins}'}';

    Widget side(PlayerProfile p, CrossAxisAlignment align) => Expanded(
          child: PlayerTap(
            name: p.matchName,
            child: Column(
              crossAxisAlignment: align,
              children: [
                PlayerDp(name: p.matchName, size: 56, edge: Colors.white.withValues(alpha: 0.9)),
                const SizedBox(height: Sx.s8),
                Text(p.isMe ? 'You' : p.name,
                    maxLines: 2,
                    textAlign: align == CrossAxisAlignment.start ? TextAlign.left : TextAlign.right,
                    style: SxType.heading(Colors.white, size: 16)),
                if (p.placeLabel != null)
                  Text(p.city ?? '', style: SxType.caption(Colors.white.withValues(alpha: 0.7), size: 12)),
              ],
            ),
          ),
        );

    return ListView(
      key: const Key('headToHead'),
      padding: EdgeInsets.fromLTRB(Sx.gutter, Sx.s8, Sx.gutter, Sx.s48 + MediaQuery.paddingOf(context).bottom),
      children: [
        SxHeroCard(
          padding: const EdgeInsets.all(Sx.s20),
          child: SxOnHero(
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    side(h.a, CrossAxisAlignment.start),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Sx.s8, vertical: Sx.s12),
                      child: Column(
                        children: [
                          Text('${h.aWins}–${h.bWins}', key: const Key('h2hScore'), style: SxType.hero(56, Colors.white)),
                          const SizedBox(height: Sx.s4),
                          Text('WINS', style: SxType.label(Colors.white.withValues(alpha: 0.7), size: 11)),
                        ],
                      ),
                    ),
                    side(h.b, CrossAxisAlignment.end),
                  ],
                ),
                const SizedBox(height: Sx.s16),
                if (h.played > 0) RecordBar(wins: h.aWins, losses: h.bWins, height: 6),
                const SizedBox(height: Sx.s12),
                Text(verdict.toUpperCase(), style: SxType.label(Colors.white, size: 13)),
              ],
            ),
          ),
        ),
        if (h.played == 0)
          EmptyBlock(
            icon: Icons.compare_arrows_rounded,
            title: 'No meetings yet',
            message: 'When $aName and $bName play each other, every result shows up here.',
          )
        else ...[
          const SizedBox(height: Sx.s24),
          Row(
            children: [
              Expanded(child: Stat(value: '${h.played}', label: 'Matches', size: 26)),
              Expanded(child: Stat(value: '${h.aWinRate}%', label: '$aName won', size: 26)),
              Expanded(child: Stat(value: relativeDay(h.last!.playedAt, DateTime.now()), label: 'Last meeting', size: 20)),
            ],
          ),
          const SizedBox(height: Sx.section),
          const SxSection('Recent meetings'),
          Row(
            children: [
              Text(aName.toUpperCase(), style: SxType.label(c.inkMuted, size: 12)),
              const SizedBox(width: Sx.s12),
              Expanded(child: FormStrip(form: [for (final m in h.meetings.take(5)) m.won])),
            ],
          ),
          const SizedBox(height: Sx.section),
          const SxSection('Match history'),
          for (final (i, m) in h.meetings.indexed) ...[
            if (i > 0) Divider(height: 1, color: c.line),
            MatchRow(match: m, onTap: () => context.push('/player/matches/${m.id}')),
          ],
        ],
      ],
    );
  }
}
