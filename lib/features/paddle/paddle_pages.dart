import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../design/design.dart';
import '../../shared/format.dart';
import '../auth/auth_controller.dart';
import '../casual_match/verification/ui/pending_matches_section.dart';
import '../matches/data/match.dart';
import '../matches/data/match_repository.dart';
import '../player/data/player_repository.dart';
import '../player/data/player_stats.dart' show WinLoss;
import '../player/data/x_code.dart';
import '../player/player_pages.dart';
import '../player/ui/player_quick_view.dart' show playerStatsPath;
import '../rating/arc_career.dart';
import '../rating/arc_engine.dart' show ArcWeights;
import '../rating/ui/arc_widgets.dart';
import '../subscription/data/plans.dart';
import '../subscription/subscription_controller.dart';
import '../subscription/ui/pro_widgets.dart';
import 'data/my_play.dart';
import 'my_play_pages.dart';
import 'paddle_sections.dart';
import '../casual_match/offline/ui/offline_ui.dart';

/// My playing journey, and only mine: what is next, my casual and
/// tournament matches, my tournaments, my SkorX Points, ranking and badges.
/// Everyone else's matches live in the Matches tab.
class MyPaddlePage extends ConsumerWidget {
  const MyPaddlePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(playerOverviewProvider);
    final record = ref.watch(playerRecordProvider).value;
    final user = ref.watch(currentUserProvider);
    final c = context.sx;

    final o = overview.value;
    final favourite = _favouriteFormat(record);

    return PlayerTabList(
      onRefresh: () async {
        ref.invalidate(playerOverviewProvider);
        ref.invalidate(playerRecordProvider);
        ref.invalidate(ratingHistoryProvider);
        ref.invalidate(achievementsProvider);
        ref.invalidate(activeMatchesProvider);
        ref.invalidate(myPlaySummaryProvider);
        ref.invalidate(myMatchesProvider);
        ref.invalidate(myPlayedTournamentsProvider);
      },
      header: SxTitleBar(
        title: 'My Paddle',
        actions: [
          SxIconAction(
            key: const Key('myFullStats'),
            icon: Icons.insights_rounded,
            label: 'My full stats',
            onTap: () => context.push(playerStatsPath('me')),
          ),
        ],
      ),
      children: [
        // ── Identity: opens my full stats ──
        Tappable(
          key: const Key('myIdentity'),
          onTap: () => context.push(playerStatsPath('me')),
          child: Row(
          children: [
            PlayerDp(name: user?.name ?? 'You', size: 60, edge: c.voltFill),
            const SizedBox(width: Sx.s16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(child: Text(user?.name ?? '', overflow: TextOverflow.ellipsis, style: SxType.heading(c.ink, size: 19))),
                      if (ref.watch(isProProvider)) ...[const SizedBox(width: Sx.s8), const ProBadge(key: Key('paddlePro'), size: 10)],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (user?.xCode != null) XCode.display(user!.xCode!),
                      if (o?.arc != null) '${o!.arc!.band.label} · ${ratingText(o.arc!.rating)}',
                      ?favourite,
                    ].where((s) => s.isNotEmpty).join(' · '),
                    style: SxType.caption(c.inkMuted),
                  ),
                  if (record != null && record.played > 0) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${record.played} matches · ${record.winRate}% won${record.winStreak > 1 ? ' · ${record.winStreak} in a row' : ''}',
                      style: SxType.caption(c.ink, size: 12.5).copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: c.inkFaint),
          ],
        ),
        ),
        const _UpNext(),
        const SizedBox(height: Sx.section),
        // Casual matches only count once every player confirms: verified vs
        // pending, and what is still waiting.
        const SxSection('Casual matches'),
        const OfflineMatchesRow(),
        const PendingMatchesSection(),
        const SizedBox(height: Sx.section),
        const _MyMatchesSection(category: MatchCategory.casual),
        const SizedBox(height: Sx.section),
        const _MyMatchesSection(category: MatchCategory.tournament),
        const SizedBox(height: Sx.section),
        // Badges get their own highlighted card, where they are seen.
        const _AchievementsSection(),
        const SizedBox(height: Sx.section),
        const _MyTournamentsSection(),
        const SizedBox(height: Sx.section),
        if (overview.isLoading && o == null)
          const Skeleton(height: 220, radius: Sx.radiusLg)
        else ...[
          _RatingSection(arc: o?.arc),
          const SizedBox(height: Sx.section),
          ProGate(
            feature: ProFeature.localRanking,
            locked: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SxSection('Ranking', action: 'Leaderboards', onAction: () => context.push('/player/rankings')),
                const ProLockedPanel(feature: ProFeature.localRanking),
              ],
            ),
            child: _RankingSection(rankings: o?.rankings ?? const [], favourite: favourite),
          ),
          if (o?.arc != null) ...[
            const SizedBox(height: Sx.section),
            _PointsSection(arc: o!.arc!),
          ],
        ],
      ],
    );
  }

  static String? _favouriteFormat(PlayerRecord? r) =>
      r == null || r.played == 0 ? null : r.preferredFormat.label;
}

/// SkorX Rating: skill now. Before any rated match, what it is and how to
/// get one.
class _RatingSection extends StatelessWidget {
  const _RatingSection({this.arc});

  final ArcSummary? arc;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final a = arc;
    return Column(
      key: Key(a == null ? 'unrated' : 'ratingSection'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SxSection('SkorX Rating', action: 'How it works', onAction: () => showArcExplainer(context)),
        if (a == null) ...[
          Text('NOT RATED YET', style: SxType.title(c.inkFaint, size: 28)),
          const SizedBox(height: Sx.s8),
          Text(
            'Your SkorX Rating shows how good you are right now, from 0 to 100. Finish a scored match to get yours.',
            style: SxType.body(c.inkMuted),
          ),
          const SizedBox(height: Sx.s16),
          SkorxBandBar(rating: ArcWeights.newPlayerSpi),
        ] else
          SkorxRatingPanel(summary: a),
      ],
    );
  }
}

/// SkorX Points: everything earned, and the level they unlock.
class _PointsSection extends StatelessWidget {
  const _PointsSection({required this.arc});

  final ArcSummary arc;

  @override
  Widget build(BuildContext context) => Column(
        key: const Key('pointsSection'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SxSection('SkorX Points', action: 'How it works', onAction: () => showArcExplainer(context)),
          SkorxPointsPanel(summary: arc),
        ],
      );
}

/// My live and next matches, when there are any.
class _UpNext extends ConsumerWidget {
  const _UpNext();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeMatchesProvider).value ?? const <Match>[];
    if (active.isEmpty) return const SizedBox.shrink();
    return Padding(
      key: const Key('upNext'),
      padding: const EdgeInsets.only(top: Sx.section),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SxSection(active.first.isLive ? 'Playing now' : 'Up next'),
          PlayingNowCards(matches: active),
        ],
      ),
    );
  }
}

/// My casual or my tournament matches: the record, then the latest three.
class _MyMatchesSection extends ConsumerWidget {
  const _MyMatchesSection({required this.category});

  final MatchCategory category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(myPlaySummaryProvider(category));
    final page = ref.watch(myMatchesProvider(category));
    final title = category == MatchCategory.casual ? 'My casual matches' : 'My tournament matches';
    final open = '/player/paddle/matches?category=${category.name}';
    return Column(
      key: Key('my-${category.name}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SxSection(title),
        switch ((summary, page)) {
          (AsyncData(value: final WinLoss s), AsyncData(value: final MatchPage p)) when s.played == 0 && p.matches.isEmpty =>
            MyMatchesEmpty(category: category, compact: true),
          (AsyncData(value: final WinLoss s), AsyncData(value: final MatchPage p)) => MyMatchesCard(
              category: category,
              record: s,
              matches: p.matches,
              onAll: () => context.push(open),
            ),
          (AsyncError(), _) || (_, AsyncError()) => ErrorBlock(
              message: 'Your matches did not load.',
              onRetry: () {
                ref.invalidate(myPlaySummaryProvider(category));
                ref.invalidate(myMatchesProvider(category));
              },
            ),
          _ => const Column(children: [Skeleton(height: 48), SizedBox(height: Sx.s12), SkeletonList(rows: 2)]),
        },
      ],
    );
  }
}

/// Tournaments I entered or played, as banner cards.
class _MyTournamentsSection extends ConsumerWidget {
  const _MyTournamentsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(myPlayedTournamentsProvider);
    return Column(
      key: const Key('myTournaments'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SxSection('My tournaments',
            action: (list.value?.isNotEmpty ?? false) ? 'All' : null, onAction: () => context.push('/player/tournaments/mine')),
        switch (list) {
          AsyncData(:final value) when value.isEmpty => const NoTournamentsYet(compact: true),
          AsyncData(:final value) => SizedBox(
              height: 186,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                itemCount: value.length,
                separatorBuilder: (_, _) => const SizedBox(width: Sx.s12),
                itemBuilder: (_, i) => MyTournamentCard(play: value[i], width: 250),
              ),
            ),
          AsyncError() => ErrorBlock(message: 'Your tournaments did not load.', onRetry: () => ref.invalidate(myPlayedTournamentsProvider)),
          _ => const Skeleton(height: 186, radius: Sx.radius),
        },
      ],
    );
  }
}

class _RankingSection extends StatelessWidget {
  const _RankingSection({required this.rankings, required this.favourite});

  final List<Ranking> rankings;
  final String? favourite;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final cat = PlayCategory.values.where((p) => p.label == favourite).firstOrNull ?? PlayCategory.doubles;
    final mine = rankings.where((r) => r.category == cat).toList();
    final city = mine.where((r) => r.scope == RankScope.city).firstOrNull;
    if (city == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SxSection('Ranking', action: 'Leaderboards', onAction: () => context.push('/player/rankings')),
          Text('NOT RANKED YET', style: SxType.title(c.inkFaint, size: 28)),
          const SizedBox(height: Sx.s8),
          Text('You join the rankings once you have a SkorX Rating.', style: SxType.body(c.inkMuted)),
        ],
      );
    }
    return Column(
      key: const Key('rankingSection'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SxSection('Ranking · ${cat.label}', action: 'Rankings', onAction: () => context.push('/player/rankings')),
        Semantics(
          button: true,
          label: 'Ranked ${city.rank} in ${city.place}. Open rankings',
          excludeSemantics: true,
          child: Tappable(
            onTap: () => context.push('/player/rankings'),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('#${city.rank}', style: SxType.hero(72, c.ink)),
                const SizedBox(width: Sx.s16),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: Sx.s8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('in ${city.place}', style: SxType.heading(c.ink, size: 16)),
                        Text('of ${city.of} players · ${_moved(city.change)}', style: SxType.caption(c.inkMuted)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Sx.s20),
        Row(
          children: [
            for (final r in mine.where((r) => r.scope != RankScope.city))
              Expanded(child: Stat(value: '#${_compact(r.rank)}', label: r.scope.label, size: 24)),
          ],
        ),
        const SizedBox(height: Sx.s12),
        Text('Rankings are by SkorX Rating.', style: SxType.caption(c.inkMuted, size: 12)),
      ],
    );
  }
}

String _moved(int change) => change == 0 ? 'no change' : change > 0 ? 'up $change' : 'down ${change.abs()}';

String _compact(int n) => n >= 10000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';

class _AchievementsSection extends ConsumerWidget {
  const _AchievementsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(achievementsProvider).value;
    if (all == null) return const Skeleton(height: 320, radius: Sx.radiusLg);
    return Column(
      key: const Key('achievementsSection'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SxSection('Achievements'),
        TrophyRoomCard(
          all: all,
          onOpen: () => context.push('/player/achievements'),
          onBadge: (a) => showAchievement(context, a),
        ),
      ],
    );
  }
}

Future<void> showAchievement(BuildContext context, Achievement a) => showSxSheet<void>(
      context,
      builder: (ctx) {
        final c = ctx.sx;
        return Padding(
          padding: const EdgeInsets.fromLTRB(Sx.gutter, 0, Sx.gutter, Sx.s32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AchievementCoin(achievement: a, size: 120),
              const SizedBox(height: Sx.s20),
              Text(a.title.toUpperCase(), style: SxType.title(c.ink, size: 30)),
              const SizedBox(height: Sx.s4),
              Text(tierLabel(a.tier).toUpperCase(), style: SxType.label(c.inkMuted)),
              const SizedBox(height: Sx.s16),
              Text(a.description, textAlign: TextAlign.center, style: SxType.body(c.ink)),
              const SizedBox(height: Sx.s16),
              if (a.unlocked)
                StateMark(SxState.won, word: 'UNLOCKED ${longDate(a.unlockedAt!).toUpperCase()}')
              else ...[
                RecordBar(wins: (a.progress * 100).round(), losses: 100 - (a.progress * 100).round(), height: 6),
                const SizedBox(height: Sx.s8),
                Text(a.progressLabel ?? 'Not started', style: SxType.caption(c.inkMuted)),
              ],
            ],
          ),
        );
      },
    );

/// Where the player ranks, by format and scope, with the leaderboard.
class RankingsPage extends ConsumerStatefulWidget {
  const RankingsPage({super.key, this.scope, this.category});

  /// Where to open, e.g. the leaderboard Explore was showing.
  final RankScope? scope;
  final PlayCategory? category;

  @override
  ConsumerState<RankingsPage> createState() => _RankingsPageState();
}

class _RankingsPageState extends ConsumerState<RankingsPage> {
  late PlayCategory _cat = widget.category ?? PlayCategory.doubles;
  late RankScope _scope = widget.scope ?? RankScope.city;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final rankings = ref.watch(playerOverviewProvider).value?.rankings ?? const [];
    final board = ref.watch(leaderboardProvider((scope: _scope, category: _cat, gender: 'All', age: 'All')));
    return Scaffold(
      body: SafeArea(
        child: SxWidth(
          child: Column(
            children: [
              SxBackBar(onBack: () => context.canPop() ? context.pop() : context.go('/player/paddle')),
              const SxTitleBar(title: 'Rankings'),
              SxTabs<PlayCategory>(
                tabs: [for (final p in PlayCategory.values) (p, p.label, null)],
                selected: _cat,
                onSelect: (p) => setState(() => _cat = p),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s16, Sx.gutter, Sx.s48),
                  children: [
                    // My place in each scope; tap to see that leaderboard.
                    ProGate(
                      feature: ProFeature.localRanking,
                      locked: const ProLockedPanel(
                        feature: ProFeature.localRanking,
                        message: 'Your rank in your city, state, country and the world, and how it moves.',
                      ),
                      child: Row(
                        children: [
                          for (final s in RankScope.values)
                            Expanded(
                              child: _ScopeTile(
                                scope: s,
                                ranking: rankings.where((r) => r.scope == s && r.category == _cat).firstOrNull,
                                selected: s == _scope,
                                onTap: () => setState(() => _scope = s),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: Sx.section),
                    SxSection('${_scope.label} leaderboard · ${_cat.label}'),
                    if (!ref.watch(canAccessProvider(ProFeature.leaderboard)))
                      const ProLockedPanel(
                        feature: ProFeature.leaderboard,
                        message: 'The top players in every scope and format, and where you sit among them.',
                      )
                    else switch (board) {
                      AsyncData(:final value) when value.isEmpty => const EmptyBlock(
                          icon: Icons.leaderboard_outlined,
                          title: 'No rankings yet',
                          message: 'Leaderboards appear once rated matches are played here.',
                          compact: true,
                        ),
                      AsyncData(:final value) => Column(
                          children: [
                            for (final (i, e) in value.indexed) ...[
                              if (i > 0 && e.isMe && e.rank > value[i - 1].rank + 1)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: Sx.s8),
                                  child: Text('· · ·', style: SxType.label(c.inkFaint)),
                                )
                              else if (i > 0)
                                Divider(height: 1, color: c.line),
                              _LeaderRow(entry: e),
                            ],
                          ],
                        ),
                      _ => const SkeletonList(rows: 6, rowHeight: 48),
                    },
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScopeTile extends StatelessWidget {
  const _ScopeTile({required this.scope, required this.ranking, required this.selected, required this.onTap});

  final RankScope scope;
  final Ranking? ranking;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Semantics(
      button: true,
      selected: selected,
      label: '${scope.label}, ${ranking == null ? 'not ranked' : 'rank ${ranking!.rank}'}',
      excludeSemantics: true,
      child: Tappable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Sx.fast,
          margin: const EdgeInsets.only(right: Sx.s8),
          padding: const EdgeInsets.symmetric(vertical: Sx.s12, horizontal: Sx.s8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Sx.radius),
            border: Border.all(color: selected ? c.ink : c.line, width: selected ? 1.5 : 1),
          ),
          child: Column(
            children: [
              FittedBox(
                child: Text(ranking == null ? '—' : '#${_compact(ranking!.rank)}',
                    style: SxType.number(24, c.ink, weight: FontWeight.w800)),
              ),
              const SizedBox(height: 4),
              Text(scope.label.toUpperCase(), style: SxType.label(c.inkMuted, size: 10.5)),
              if (ranking != null) ...[
                const SizedBox(height: 2),
                Text(
                  ranking!.change == 0 ? '—' : '${ranking!.change > 0 ? '▲' : '▼'} ${ranking!.change.abs()}',
                  style: SxType.caption(ranking!.change > 0 ? c.volt : c.inkMuted, size: 11),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LeaderRow extends StatelessWidget {
  const _LeaderRow({required this.entry});

  final LeaderboardEntry entry;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final e = entry;
    return PlayerTap(
      name: e.isMe ? 'You' : e.name,
      child: Container(
      height: 56,
      decoration: BoxDecoration(
        color: e.isMe ? c.surface : null,
        border: e.isMe ? Border(left: BorderSide(color: c.voltFill, width: 3)) : null,
      ),
      padding: EdgeInsets.only(left: e.isMe ? Sx.s12 : 0, right: e.isMe ? Sx.s12 : 0),
      child: Row(
        children: [
          SizedBox(width: 48, child: Text('${e.rank}', style: SxType.number(18, e.rank <= 3 ? c.ink : c.inkMuted, weight: FontWeight.w800))),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.isMe ? '${e.name} (you)' : e.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: SxType.heading(c.ink, size: 15).copyWith(fontWeight: e.isMe ? FontWeight.w700 : FontWeight.w500)),
                Text(e.city, style: SxType.caption(c.inkMuted, size: 12)),
              ],
            ),
          ),
          Text(ratingText(e.rating), style: SxType.number(18, c.ink, weight: FontWeight.w800)),
        ],
      ),
      ),
    );
  }
}

enum _BadgeFilter { all, unlocked, inProgress }

/// Every badge, on shelves by what they are for: wins, streaks, tournaments
/// and so on. The top shows the collection and what is closest.
class AchievementsPage extends ConsumerStatefulWidget {
  const AchievementsPage({super.key});

  @override
  ConsumerState<AchievementsPage> createState() => _AchievementsPageState();
}

class _AchievementsPageState extends ConsumerState<AchievementsPage> {
  _BadgeFilter _filter = _BadgeFilter.all;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final all = ref.watch(achievementsProvider);
    return Scaffold(
      body: SafeArea(
        child: SxWidth(
          child: Column(
            children: [
              SxBackBar(onBack: () => context.canPop() ? context.pop() : context.go('/player/paddle')),
              const SxTitleBar(title: 'Achievements'),
              Expanded(
                child: switch (all) {
                  AsyncData(:final value) => () {
                      final unlocked = value.where((a) => a.unlocked).toList();
                      final score = unlocked.fold<int>(0, (s, a) => s + a.score);
                      final shown = [
                        for (final a in value)
                          if (switch (_filter) {
                            _BadgeFilter.all => true,
                            _BadgeFilter.unlocked => a.unlocked,
                            _BadgeFilter.inProgress => !a.unlocked && a.progress > 0,
                          })
                            a,
                      ];
                      // Shelves keep the catalogue's order.
                      final shelves = <String, List<Achievement>>{};
                      for (final a in shown) {
                        (shelves[a.category] ??= []).add(a);
                      }
                      final tiers = {
                        for (final t in AchievementTier.values) t: unlocked.where((a) => a.tier == t).length,
                      };
                      return ListView(
                        padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s8, Sx.gutter, Sx.s48),
                        children: [
                          SxHeroCard(
                            ballColor: const Color(0xFFF2C94C),
                            padding: const EdgeInsets.all(Sx.s20),
                            child: SxOnHero(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text('${unlocked.length}', style: SxType.hero(64, Colors.white)),
                                      const SizedBox(width: Sx.s8),
                                      Flexible(child: Padding(
                                        padding: const EdgeInsets.only(bottom: Sx.s8),
                                        child: Text('of ${value.length} unlocked',
                                            style: SxType.body(Colors.white.withValues(alpha: 0.8))),
                                      )),
                                    ],
                                  ),
                                  const SizedBox(height: Sx.s8),
                                  Text('Badge score $score',
                                      style: SxType.heading(const Color(0xFFF2C94C), size: 16).copyWith(fontWeight: FontWeight.w800)),
                                  const SizedBox(height: Sx.s16),
                                  Row(
                                    children: [
                                      for (final t in AchievementTier.values)
                                        Expanded(
                                          child: Row(
                                            children: [
                                              Container(
                                                width: 14,
                                                height: 14,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  gradient: LinearGradient(colors: tierMetal(t)),
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Flexible(
                                                child: Text('${tiers[t]} ${tierLabel(t)}',
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: SxType.caption(Colors.white, size: 12.5)),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: Sx.s20),
                          Wrap(
                            runSpacing: Sx.s8,
                            children: [
                              for (final (f, label) in [
                                (_BadgeFilter.all, 'All ${value.length}'),
                                (_BadgeFilter.unlocked, 'Unlocked ${unlocked.length}'),
                                (_BadgeFilter.inProgress, 'In progress'),
                              ])
                                Padding(
                                  padding: const EdgeInsets.only(right: Sx.s8),
                                  child: SxChip(
                                    key: Key('badgeFilter-${f.name}'),
                                    label: label,
                                    selected: _filter == f,
                                    onTap: () => setState(() => _filter = f),
                                  ),
                                ),
                            ],
                          ),
                          if (shown.isEmpty)
                            const EmptyBlock(
                              icon: Icons.military_tech_outlined,
                              title: 'Nothing here yet',
                              message: 'Play a match and your first badges start filling up.',
                              compact: true,
                            ),
                          for (final MapEntry(key: shelf, value: list) in shelves.entries) ...[
                            const SizedBox(height: Sx.section),
                            SxSection('$shelf · ${list.where((a) => a.unlocked).length}/${list.length}'),
                            GridView.count(
                              crossAxisCount: 3,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              mainAxisSpacing: Sx.s16,
                              crossAxisSpacing: Sx.s12,
                              childAspectRatio: 0.7,
                              children: [
                                for (final a in list)
                                  Tappable(
                                    onTap: () => showAchievement(context, a),
                                    child: Column(
                                      children: [
                                        AchievementCoin(achievement: a, size: 74),
                                        const SizedBox(height: Sx.s8),
                                        Text(a.title,
                                            textAlign: TextAlign.center,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: SxType.caption(a.unlocked ? c.ink : c.inkMuted, size: 12.5)
                                                .copyWith(fontWeight: FontWeight.w700)),
                                        if (!a.unlocked && a.progressLabel != null)
                                          Text(a.progressLabel!,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: SxType.caption(c.inkFaint, size: 11)),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      );
                    }(),
                  _ => const Padding(padding: EdgeInsets.all(Sx.gutter), child: SkeletonList()),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
