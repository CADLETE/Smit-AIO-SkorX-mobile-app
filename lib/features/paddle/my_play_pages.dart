import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../design/design.dart';
import '../../shared/format.dart';
import '../matches/data/match.dart';
import '../matches/data/match_repository.dart';
import '../matches/ui/match_card.dart' show LoadMoreTrigger;
import '../player/data/player_stats.dart' show WinLoss;
import '../tournaments/data/tournaments.dart';
import '../tournaments/ui/tournament_banner.dart';
import 'data/my_play.dart';

String myTournamentPath(String id) => '/player/paddle/tournament/$id';

/// Matches, won, lost, win %: one line of numbers.
class WinLossRow extends StatelessWidget {
  const WinLossRow({super.key, required this.record, this.size = 26});

  final WinLoss record;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final r = record;
    return Row(
      children: [
        Expanded(child: Stat(value: '${r.played}', label: 'Matches', size: size)),
        Expanded(child: Stat(value: '${r.wins}', label: 'Won', size: size, color: r.wins > 0 ? c.volt : null)),
        Expanded(child: Stat(value: '${r.losses}', label: 'Lost', size: size)),
        Expanded(child: Stat(value: r.winRate == null ? '—' : '${r.winRate}%', label: 'Win %', size: size)),
      ],
    );
  }
}

/// A tournament the player entered: banner, where and when, their record.
class MyTournamentCard extends StatelessWidget {
  const MyTournamentCard({super.key, required this.play, this.width});

  final MyTournamentPlay play;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final t = play.tournament;
    final now = DateTime.now();
    final phase = t.phase(now);
    final record = play.played == 0
        ? switch (phase) {
            TournamentPhase.upcoming => 'Starts ${relativeDay(t.start, now).toLowerCase()}',
            _ => 'No matches played yet',
          }
        : '${play.played} played · ${play.wins}W ${play.losses}L';
    final card = Semantics(
      button: true,
      label: '${t.name}, ${t.city}, $record. Open my matches',
      excludeSemantics: true,
      child: Tappable(
        key: Key('myTournament-${t.id}'),
        onTap: () => context.push(myTournamentPath(t.id)),
        radius: Sx.radius + 2,
        child: Container(
          decoration: BoxDecoration(
            gradient: c.card,
            borderRadius: BorderRadius.circular(Sx.radius + 2),
            border: Border.all(color: c.cardEdge),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TournamentBanner.of(
                t,
                height: 92,
                radius: Sx.radius + 1,
                child: Positioned(
                  left: Sx.s12,
                  top: Sx.s12,
                  child: BannerTag(
                    text: switch (phase) {
                      TournamentPhase.live => 'LIVE',
                      TournamentPhase.upcoming => 'UPCOMING',
                      TournamentPhase.completed => 'COMPLETED',
                    },
                    live: phase == TournamentPhase.live,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(Sx.s12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.heading(c.ink, size: 16)),
                    const SizedBox(height: 2),
                    Text('${t.city} · ${dateRange(t.start, t.end)}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.caption(c.inkMuted, size: 12)),
                    const SizedBox(height: Sx.s8),
                    Row(
                      children: [
                        if (play.played > 0) ...[
                          StateGlyph(play.wins >= play.losses ? SxState.won : SxState.lost, size: 8,
                              color: play.wins >= play.losses ? c.volt : c.inkMuted),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(record, maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.heading(c.ink, size: 13.5)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return width == null ? card : SizedBox(width: width, child: card);
  }
}

/// Every tournament the player entered or played.
class MyTournamentsPlayedPage extends ConsumerWidget {
  const MyTournamentsPlayedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(myPlayedTournamentsProvider);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: SxWidth(
          child: Column(
            children: [
              SxBackBar(onBack: () => context.canPop() ? context.pop() : context.go('/player/paddle')),
              const SxTitleBar(title: 'My tournaments'),
              Expanded(
                child: switch (list) {
                  AsyncData(:final value) when value.isEmpty => ListView(
                      padding: const EdgeInsets.all(Sx.gutter),
                      children: [const NoTournamentsYet()],
                    ),
                  AsyncData(:final value) => ListView(
                      padding: EdgeInsets.fromLTRB(Sx.gutter, Sx.s8, Sx.gutter, Sx.s48 + MediaQuery.paddingOf(context).bottom),
                      children: [
                        for (final p in value) Padding(padding: const EdgeInsets.only(bottom: Sx.s12), child: MyTournamentCard(play: p)),
                      ],
                    ),
                  AsyncError() => ErrorBlock(message: 'Your tournaments did not load.', onRetry: () => ref.invalidate(myPlayedTournamentsProvider)),
                  _ => const Padding(padding: EdgeInsets.all(Sx.gutter), child: SkeletonList(rows: 3, rowHeight: 170)),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class NoTournamentsYet extends StatelessWidget {
  const NoTournamentsYet({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) => EmptyBlock(
        key: const Key('noTournamentsYet'),
        icon: Icons.emoji_events_outlined,
        title: 'No tournament participation yet',
        message: 'Your tournament journey starts here.',
        compact: compact,
        action: SxButton.secondary(
          label: 'Find a tournament',
          expand: false,
          onPressed: () => context.go('/player/explore?view=tournaments'),
        ),
      );
}

/// Only the player's own matches in one tournament, never the rest of the draw.
class MyTournamentMatchesPage extends ConsumerWidget {
  const MyTournamentMatchesPage({super.key, required this.tournamentId});

  final String tournamentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final detail = ref.watch(tournamentDetailProvider(tournamentId));
    final matches = ref.watch(myTournamentMatchesProvider(tournamentId));
    final journey = ref.watch(journeyProvider(tournamentId)).value;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: SxWidth(
          child: Column(
            children: [
              SxBackBar(title: 'My matches', onBack: () => context.canPop() ? context.pop() : context.go('/player/paddle')),
              Expanded(
                child: switch (detail) {
                  AsyncError(:final error) => EmptyBlock(
                      icon: Icons.search_off_rounded,
                      title: 'Not available',
                      message: error is ApiException ? error.message : 'This tournament did not load.',
                    ),
                  AsyncData(value: final d) => ListView(
                      key: const Key('myTournamentMatches'),
                      padding: EdgeInsets.fromLTRB(Sx.gutter, Sx.s8, Sx.gutter, Sx.s48 + MediaQuery.paddingOf(context).bottom),
                      children: [
                        TournamentBanner.of(d.tournament, height: 140),
                        const SizedBox(height: Sx.s16),
                        Semantics(header: true, child: Text(d.tournament.name.toUpperCase(), style: SxType.title(c.ink, size: 30))),
                        const SizedBox(height: Sx.s4),
                        Text(
                          [
                            '${dateRange(d.tournament.start, d.tournament.end)} · ${d.tournament.venue}, ${d.tournament.city}',
                            if (d.myRegistration != null) d.myRegistration!.categoryName,
                          ].join('\n'),
                          style: SxType.body(c.inkMuted, size: 14),
                        ),
                        if (journey != null) ...[
                          const SizedBox(height: Sx.s12),
                          Row(
                            children: [
                              Container(width: 3, height: 18, color: c.voltFill),
                              const SizedBox(width: Sx.s8),
                              Expanded(child: Text(journey.headline.toUpperCase(), style: SxType.label(c.ink, size: 14))),
                            ],
                          ),
                        ],
                        const SizedBox(height: Sx.s24),
                        ...switch (matches) {
                          AsyncData(:final value) when value.isEmpty => [
                              EmptyBlock(
                                key: const Key('noMyTournamentMatches'),
                                icon: Icons.account_tree_outlined,
                                title: 'No matches yet',
                                message: 'Your matches in this tournament show up here once the draw is out.',
                                compact: true,
                              ),
                            ],
                          AsyncData(:final value) => () {
                              final done = value.where((m) => m.isCompleted).toList();
                              final won = done.where((m) => m.won).length;
                              return [
                                WinLossRow(record: WinLoss('Tournament', played: done.length, wins: won)),
                                const SizedBox(height: Sx.section),
                                SxSection('My matches · ${value.length}'),
                                for (final (i, m) in value.indexed) ...[
                                  if (i > 0) Divider(height: 1, color: c.line),
                                  _NumberedMatch(number: i + 1, match: m),
                                ],
                              ];
                            }(),
                          AsyncError() => [
                              ErrorBlock(message: 'Your matches did not load.', onRetry: () => ref.invalidate(myTournamentMatchesProvider(tournamentId))),
                            ],
                          _ => const [SkeletonList(rows: 3)],
                        },
                        const SizedBox(height: Sx.s24),
                        SxButton.secondary(
                          key: const Key('viewWholeTournament'),
                          label: 'View the whole tournament',
                          icon: Icons.emoji_events_outlined,
                          onPressed: () => context.push('/player/tournament/$tournamentId'),
                        ),
                      ],
                    ),
                  _ => const Padding(padding: EdgeInsets.all(Sx.gutter), child: SkeletonList(rows: 4, rowHeight: 90)),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NumberedMatch extends StatelessWidget {
  const _NumberedMatch({required this.number, required this.match});

  final int number;
  final Match match;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: Sx.s12, left: 15),
          child: Text('MATCH ${number.toString().padLeft(2, '0')}', style: SxType.label(c.inkFaint, size: 11)),
        ),
        MatchRow(match: match, showContext: false, onTap: () => context.push('/player/matches/${match.id}')),
      ],
    );
  }
}

/// The player's own casual or tournament matches, a page at a time.
class MyMatchesPage extends ConsumerStatefulWidget {
  const MyMatchesPage({super.key, this.category});

  /// `casual` or `tournament`.
  final String? category;

  @override
  ConsumerState<MyMatchesPage> createState() => _MyMatchesPageState();
}

class _MyMatchesPageState extends ConsumerState<MyMatchesPage> {
  late MatchCategory _category = MatchCategory.values.asNameMap()[widget.category] ?? MatchCategory.casual;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 600) ref.read(myMatchesProvider(_category).notifier).loadMore();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final page = ref.watch(myMatchesProvider(_category));
    final summary = ref.watch(myPlaySummaryProvider(_category)).value;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: SxWidth(
          child: Column(
            children: [
              SxBackBar(onBack: () => context.canPop() ? context.pop() : context.go('/player/paddle')),
              const SxTitleBar(title: 'My matches'),
              SxTabs<MatchCategory>(
                tabs: [for (final k in MatchCategory.values) (k, k.label, null)],
                selected: _category,
                onSelect: (k) {
                  setState(() => _category = k);
                  if (_scroll.hasClients) _scroll.jumpTo(0);
                },
              ),
              Expanded(
                child: ListView(
                  key: const Key('myMatchesList'),
                  controller: _scroll,
                  padding: EdgeInsets.fromLTRB(Sx.gutter, Sx.s16, Sx.gutter, Sx.s48 + MediaQuery.paddingOf(context).bottom),
                  children: [
                    if (summary != null && summary.played > 0) ...[WinLossRow(record: summary), const SizedBox(height: Sx.s24)],
                    ...switch (page) {
                      AsyncData(:final value) when value.matches.isEmpty => [MyMatchesEmpty(category: _category)],
                      AsyncData(:final value) => [
                          ..._grouped(context, value.matches),
                          if (value.hasMore)
                            LoadMoreTrigger(
                              key: ValueKey('more-${value.matches.length}'),
                              onLoad: () => ref.read(myMatchesProvider(_category).notifier).loadMore(),
                            )
                          else
                            Padding(
                              padding: const EdgeInsets.all(Sx.s24),
                              child: Center(child: Text('${value.matches.length} matches', style: SxType.label(c.inkFaint))),
                            ),
                        ],
                      AsyncError() => [
                          ErrorBlock(message: 'Your matches did not load.', onRetry: () => ref.invalidate(myMatchesProvider(_category))),
                        ],
                      _ => const [SkeletonList(rows: 6)],
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

  /// By month, newest first.
  List<Widget> _grouped(BuildContext context, List<Match> matches) {
    final c = context.sx;
    final now = DateTime.now();
    final out = <Widget>[];
    String? month;
    for (final m in matches) {
      final label = m.playedAt.year == now.year && m.playedAt.month == now.month
          ? 'This month'
          : '${monthsShort[m.playedAt.month - 1]} ${m.playedAt.year}';
      if (label != month) {
        month = label;
        out.add(Padding(
          padding: EdgeInsets.only(top: out.isEmpty ? 0 : Sx.s24, bottom: Sx.s4),
          child: SxSection(label, padding: EdgeInsets.zero),
        ));
      } else {
        out.add(Divider(height: 1, color: c.line));
      }
      out.add(MatchRow(match: m, now: now, onTap: () => context.push('/player/matches/${m.id}')));
    }
    return out;
  }
}

class MyMatchesEmpty extends StatelessWidget {
  const MyMatchesEmpty({super.key, required this.category, this.compact = false});

  final MatchCategory category;
  final bool compact;

  @override
  Widget build(BuildContext context) => category == MatchCategory.casual
      ? EmptyBlock(
          key: const Key('noCasualMatches'),
          icon: Icons.sports_tennis_rounded,
          title: 'No casual matches yet',
          message: 'Play your first match and start building your SkorX record.',
          compact: compact,
          action: SxButton(
            key: const Key('playFirstMatch'),
            label: 'Play your first match',
            expand: false,
            onPressed: () => context.push('/player/match/new'),
          ),
        )
      : EmptyBlock(
          key: const Key('noTournamentMatches'),
          icon: Icons.emoji_events_outlined,
          title: 'No tournament matches yet',
          message: 'Your tournament journey starts here.',
          compact: compact,
          action: SxButton.secondary(
            label: 'Find a tournament',
            expand: false,
            onPressed: () => context.go('/player/explore?view=tournaments'),
          ),
        );
}
