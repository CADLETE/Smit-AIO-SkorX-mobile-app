import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../design/design.dart';
import '../../shared/format.dart';
import '../auth/auth_controller.dart';
import '../matches/data/match.dart';
import '../matches/data/match_repository.dart';
import '../player/data/player_repository.dart';
import '../player/data/player_stats.dart' show WinLoss;
import '../player/data/x_code.dart';
import '../player/player_pages.dart';
import '../player/ui/player_quick_view.dart' show playerStatsPath;
import '../rating/arc_career.dart';
import '../rating/ui/arc_widgets.dart';
import 'data/my_play.dart';
import 'my_play_pages.dart';

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
            SxAvatar(name: user?.name ?? '', size: 60, ring: true),
            const SizedBox(width: Sx.s16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user?.name ?? '', style: SxType.heading(c.ink, size: 19)),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (user?.xCode != null) XCode.display(user!.xCode!),
                      o?.level ?? '',
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
        const _MyMatchesSection(category: MatchCategory.casual),
        const SizedBox(height: Sx.section),
        const _MyMatchesSection(category: MatchCategory.tournament),
        const SizedBox(height: Sx.section),
        const _MyTournamentsSection(),
        const SizedBox(height: Sx.section),
        if (overview.isLoading && o == null)
          const Skeleton(height: 220, radius: Sx.radiusLg)
        else ...[
          _RatingSection(rating: o?.rating, arc: o?.arc),
          const SizedBox(height: Sx.section),
          _RankingSection(rankings: o?.rankings ?? const [], favourite: favourite),
          const SizedBox(height: Sx.section),
          const _AchievementsSection(),
        ],
      ],
    );
  }

  static String? _favouriteFormat(PlayerRecord? r) =>
      r == null || r.played == 0 ? null : r.preferredFormat.label;
}

class _RatingSection extends ConsumerWidget {
  const _RatingSection({required this.rating, this.arc});

  final int? rating;

  /// Level, Power Index, Heat and formats, when the player is rated.
  final ArcSummary? arc;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final history = ref.watch(ratingHistoryProvider).value ?? const [];
    if (rating == null) {
      return Column(
        key: const Key('unrated'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SxSection('SkorX Points'),
          Text('UNRATED', style: SxType.hero(64, c.inkFaint)),
          const SizedBox(height: Sx.s12),
          Text('Play 3 rated matches to get your SkorX rating. It moves with every result after that.',
              style: SxType.body(c.inkMuted)),
          const SizedBox(height: Sx.s16),
          const RecordBar(wins: 0, losses: 0, height: 6),
          const SizedBox(height: Sx.s8),
          Text('0 of 3 rated matches', style: SxType.caption(c.inkMuted)),
        ],
      );
    }
    final now = DateTime.now();
    final monthAgo = history.where((p) => now.difference(p.date).inDays >= 30).lastOrNull ?? history.firstOrNull;
    final change = monthAgo == null ? 0 : rating! - monthAgo.rating;
    final values = [for (final p in history) p.rating];
    final shown = values.length > 30 ? values.sublist(values.length - 30) : values;
    final hi = values.isEmpty ? rating! : values.reduce((a, b) => a > b ? a : b);
    return Column(
      key: const Key('ratingSection'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SxSection('SkorX Points', action: 'How it works', onAction: () => showArcExplainer(context)),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.bottomLeft,
                child: CountUp(value: rating!, style: SxType.hero(88, c.ink)),
              ),
            ),
            const SizedBox(width: Sx.s16),
            Padding(
              padding: const EdgeInsets.only(bottom: Sx.s8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RatingDelta(change, size: 22),
                  Text('last 30 days', style: SxType.caption(c.inkMuted)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: Sx.s16),
        RatingGraph(values: shown, height: 110),
        const SizedBox(height: Sx.s8),
        Row(
          children: [
            Expanded(child: Text('Last ${shown.length} rated matches', style: SxType.caption(c.inkMuted, size: 12))),
            Text('Best $hi', style: SxType.caption(c.inkMuted, size: 12)),
          ],
        ),
        if (arc != null) ...[
          const SizedBox(height: Sx.s20),
          ArcLevelBar(summary: arc!),
          const SizedBox(height: Sx.s16),
          ArcSkillStrip(summary: arc!),
          const SizedBox(height: Sx.s16),
          ArcFormats(summary: arc!),
        ],
      ],
    );
  }
}

/// My live and next matches, when there are any.
class _UpNext extends ConsumerWidget {
  const _UpNext();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final active = ref.watch(activeMatchesProvider).value ?? const <Match>[];
    if (active.isEmpty) return const SizedBox.shrink();
    final now = DateTime.now();
    return Padding(
      key: const Key('upNext'),
      padding: const EdgeInsets.only(top: Sx.section),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SxSection(active.first.isLive ? 'Playing now' : 'Up next'),
          for (final (i, m) in active.take(2).indexed) ...[
            if (i > 0) Divider(height: 1, color: c.line),
            MatchRow(match: m, now: now, onTap: () => context.push('/player/matches/${m.id}')),
          ],
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
    final c = context.sx;
    final summary = ref.watch(myPlaySummaryProvider(category));
    final page = ref.watch(myMatchesProvider(category));
    final title = category == MatchCategory.casual ? 'My casual matches' : 'My tournament matches';
    final open = '/player/paddle/matches?category=${category.name}';
    return Column(
      key: Key('my-${category.name}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SxSection(title,
            action: (summary.value?.played ?? 0) > 0 ? 'All' : null, onAction: () => context.push(open)),
        switch ((summary, page)) {
          (AsyncData(value: final WinLoss s), AsyncData(value: final MatchPage p)) when s.played == 0 && p.matches.isEmpty =>
            MyMatchesEmpty(category: category, compact: true),
          (AsyncData(value: final WinLoss s), AsyncData(value: final MatchPage p)) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                WinLossRow(record: s, size: 24),
                const SizedBox(height: Sx.s12),
                RecordBar(wins: s.wins, losses: s.losses, height: 5),
                const SizedBox(height: Sx.s8),
                for (final (i, m) in p.matches.take(3).indexed) ...[
                  if (i > 0) Divider(height: 1, color: c.line),
                  MatchRow(match: m, onTap: () => context.push('/player/matches/${m.id}')),
                ],
              ],
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
          Text('You join the rankings with your first rating.', style: SxType.body(c.inkMuted)),
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
    final c = context.sx;
    final all = ref.watch(achievementsProvider).value;
    if (all == null) return const Skeleton(height: 100);
    final unlocked = all.where((a) => a.unlocked).toList()..sort((a, b) => b.unlockedAt!.compareTo(a.unlockedAt!));
    final shown = unlocked.isEmpty ? all.take(4).toList() : unlocked.take(4).toList();
    return Column(
      key: const Key('achievementsSection'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SxSection('Achievements · ${unlocked.length} of ${all.length}',
            action: 'All', onAction: () => context.push('/player/achievements')),
        Row(
          children: [
            for (final a in shown)
              Expanded(
                child: Tappable(
                  onTap: () => showAchievement(context, a),
                  child: Column(
                    children: [
                      AchievementCoin(achievement: a, size: 64),
                      const SizedBox(height: Sx.s8),
                      Text(a.title, textAlign: TextAlign.center, maxLines: 2, style: SxType.caption(a.unlocked ? c.ink : c.inkMuted, size: 12)),
                    ],
                  ),
                ),
              ),
          ],
        ),
        if (unlocked.isEmpty) ...[
          const SizedBox(height: Sx.s12),
          Text('Your first badge comes with your first match.', style: SxType.caption(c.inkMuted)),
        ],
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
  const RankingsPage({super.key});

  @override
  ConsumerState<RankingsPage> createState() => _RankingsPageState();
}

class _RankingsPageState extends ConsumerState<RankingsPage> {
  PlayCategory _cat = PlayCategory.doubles;
  RankScope _scope = RankScope.city;

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
                    Row(
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
                    const SizedBox(height: Sx.section),
                    SxSection('${_scope.label} leaderboard · ${_cat.label}'),
                    switch (board) {
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
          Text('${e.rating}', style: SxType.number(18, c.ink, weight: FontWeight.w800)),
        ],
      ),
      ),
    );
  }
}

/// Every badge: earned ones first, then what to go after next.
class AchievementsPage extends ConsumerWidget {
  const AchievementsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                      final locked = value.where((a) => !a.unlocked).toList()
                        ..sort((a, b) => b.progress.compareTo(a.progress));
                      Widget grid(List<Achievement> list) => GridView.count(
                            crossAxisCount: 3,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            mainAxisSpacing: Sx.s16,
                            crossAxisSpacing: Sx.s12,
                            childAspectRatio: 0.72,
                            children: [
                              for (final a in list)
                                Tappable(
                                  onTap: () => showAchievement(context, a),
                                  child: Column(
                                    children: [
                                      AchievementCoin(achievement: a, size: 76),
                                      const SizedBox(height: Sx.s8),
                                      Text(a.title,
                                          textAlign: TextAlign.center,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: SxType.caption(a.unlocked ? c.ink : c.inkMuted, size: 12.5)),
                                      if (!a.unlocked && a.progressLabel != null)
                                        Text(a.progressLabel!,
                                            maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.caption(c.inkFaint, size: 11)),
                                    ],
                                  ),
                                ),
                            ],
                          );
                      return ListView(
                        padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s8, Sx.gutter, Sx.s48),
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('${unlocked.length}', style: SxType.hero(64, c.ink)),
                              const SizedBox(width: Sx.s8),
                              Padding(
                                padding: const EdgeInsets.only(bottom: Sx.s8),
                                child: Text('of ${value.length} unlocked', style: SxType.body(c.inkMuted)),
                              ),
                            ],
                          ),
                          const SizedBox(height: Sx.s8),
                          Text('Rings show the tier: one for bronze, up to four for elite.', style: SxType.caption(c.inkMuted)),
                          if (unlocked.isNotEmpty) ...[
                            const SizedBox(height: Sx.section),
                            const SxSection('Unlocked'),
                            grid(unlocked),
                          ],
                          const SizedBox(height: Sx.section),
                          const SxSection('Up next'),
                          grid(locked),
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
