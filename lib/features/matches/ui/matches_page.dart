import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design/design.dart';
import '../../../shared/format.dart';
import '../../player/player_pages.dart';
import '../../tournaments/data/tournaments.dart' show PlaceFilter;
import '../data/match.dart';
import '../data/match_feed.dart';
import 'filter_widgets.dart';
import 'match_card.dart';
import 'match_filter_sheet.dart';

enum MatchesTab {
  all('All'),
  live('Live'),
  upcoming('Upcoming'),
  completed('Completed'),
  tournaments('Tournaments');

  const MatchesTab(this.label);
  final String label;

  MatchStatus? get status => switch (this) {
        MatchesTab.live => MatchStatus.live,
        MatchesTab.upcoming => MatchStatus.upcoming,
        MatchesTab.completed => MatchStatus.completed,
        _ => null,
      };
}

/// The SkorX match universe: every match on SkorX, in every city and
/// country, live first. Not the player's own matches; those live in My
/// Paddle. Filtering and search happen on the server, a page at a time.
class MatchesPage extends ConsumerStatefulWidget {
  const MatchesPage({super.key, this.view});

  /// `live`, `upcoming`, `completed` (or the old `results`), `tournaments`.
  final String? view;

  @override
  ConsumerState<MatchesPage> createState() => _MatchesPageState();
}

class _MatchesPageState extends ConsumerState<MatchesPage> {
  final _scroll = ScrollController();
  final _search = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  bool _tournaments = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
    _focus.addListener(() => setState(() {}));
    _applyView(widget.view);
    _search.text = ref.read(matchQueryProvider).text;
  }

  @override
  void didUpdateWidget(MatchesPage old) {
    super.didUpdateWidget(old);
    if (old.view != widget.view) _applyView(widget.view);
  }

  void _applyView(String? view) {
    final tab = switch (view) {
      'results' => MatchesTab.completed,
      _ => MatchesTab.values.asNameMap()[view],
    };
    if (tab == null) return;
    // After the first frame: providers must not change while building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _select(tab);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _search.dispose();
    _focus.dispose();
    super.dispose();
  }

  MatchQuery get _query => ref.read(matchQueryProvider);
  void _update(MatchQuery Function(MatchQuery) change) => ref.read(matchQueryProvider.notifier).update(change);

  MatchesTab _tab(MatchQuery q) => _tournaments
      ? MatchesTab.tournaments
      : switch (q.status) {
          MatchStatus.live => MatchesTab.live,
          MatchStatus.upcoming => MatchesTab.upcoming,
          MatchStatus.completed => MatchesTab.completed,
          _ => MatchesTab.all,
        };

  void _select(MatchesTab tab) {
    setState(() => _tournaments = tab == MatchesTab.tournaments);
    _update((q) => q.copyWith(status: () => tab.status));
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  /// The list that grows as the page scrolls.
  MatchQuery? _pagedQuery(MatchQuery q) => switch (_tab(q)) {
        MatchesTab.all => q.copyWith(status: () => MatchStatus.completed),
        MatchesTab.tournaments => null,
        _ => q,
      };

  void _maybeLoadMore() {
    if (_scroll.position.extentAfter > 700) return;
    final q = _pagedQuery(_query);
    if (q != null) ref.read(matchFeedProvider(q).notifier).loadMore();
  }

  void _onSearchChanged(String text) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _update((q) => q.copyWith(text: text.trim())));
  }

  void _submitSearch(String text) {
    _debounce?.cancel();
    _update((q) => q.copyWith(text: text.trim()));
    ref.read(recentMatchSearchesProvider.notifier).add(text);
    _focus.unfocus();
  }

  void _clearSearch() {
    _search.clear();
    _debounce?.cancel();
    _update((q) => q.copyWith(text: ''));
    setState(() {});
  }

  void _applySuggestion(SearchSuggestion s) {
    ref.read(recentMatchSearchesProvider.notifier).add(s.label);
    _focus.unfocus();
    if (s.kind == SuggestionKind.match) {
      context.push('/player/matches/${s.value}');
      return;
    }
    _search.clear();
    _update((q) => switch (s.kind) {
          SuggestionKind.player => q.copyWith(text: s.value),
          SuggestionKind.tournament => q.copyWith(text: '', tournament: () => (s.value, s.label)),
          SuggestionKind.venue => q.copyWith(text: '', venue: () => s.value),
          SuggestionKind.city => q.copyWith(text: '', place: PlaceFilter(city: s.value)),
          SuggestionKind.match => q,
        });
    if (s.kind == SuggestionKind.player) _search.text = s.value;
  }

  Future<void> _refresh() async {
    ref.invalidate(matchFeedProvider);
    ref.invalidate(tournamentActivityProvider);
    ref.invalidate(matchPlacesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final q = ref.watch(matchQueryProvider);
    final tab = _tab(q);
    final liveQuery = q.copyWith(status: () => MatchStatus.live);
    final live = ref.watch(matchFeedProvider(liveQuery)).value;
    final liveCount = live?.matches.length;
    final searching = _focus.hasFocus;

    return PlayerTabList(
      controller: _scroll,
      onRefresh: _refresh,
      header: Column(
        children: [
          SxTitleBar(
            title: 'Matches',
            actions: [
              SxIconAction(
                key: const Key('scoreMatch'),
                icon: Icons.add_rounded,
                label: 'Score a match',
                onTap: () => context.push('/player/match/new'),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Sx.gutter, 0, Sx.gutter, Sx.s8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('matchSearch'),
                    controller: _search,
                    focusNode: _focus,
                    onChanged: _onSearchChanged,
                    onSubmitted: _submitSearch,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Player, tournament, venue, city, match ID',
                      prefixIcon: Icon(Icons.search_rounded, color: c.inkMuted),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              key: const Key('clearSearch'),
                              tooltip: 'Clear search',
                              icon: Icon(Icons.close_rounded, color: c.inkMuted),
                              onPressed: _clearSearch,
                            ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: Sx.s8),
                _FilterButton(
                  count: q.activeCount,
                  onTap: () => showSxSheet<void>(context, builder: (_) => const MatchFilterSheet()),
                ),
              ],
            ),
          ),
          if (!searching) ...[
            ActiveFilters(
              chips: activeMatchFilterChips(q, (change) {
                _update(change);
                // Keep the search box in step when its chip is removed.
                if (_query.text.isEmpty) _search.clear();
              }),
              onClear: () {
                _search.clear();
                _update((q) => q.cleared().copyWith(text: ''));
              },
            ),
            SxTabs<MatchesTab>(
              tabs: [
                for (final t in MatchesTab.values) (t, t.label, t == MatchesTab.live ? liveCount : null),
              ],
              selected: tab,
              onSelect: _select,
            ),
          ],
        ],
      ),
      children: searching
          ? [_SearchPanel(text: _search.text, onPick: _applySuggestion, onRecent: (s) {
              _search.text = s;
              _submitSearch(s);
            })]
          : [
              const SizedBox(height: Sx.s8),
              ...switch (tab) {
                MatchesTab.all => _all(context, q),
                MatchesTab.tournaments => [_TournamentList(query: q)],
                _ => _paged(context, q, grouped: tab != MatchesTab.live),
              },
            ],
    );
  }

  /// Live now, from tournaments, coming up, then the latest results.
  List<Widget> _all(BuildContext context, MatchQuery q) {
    final live = ref.watch(matchFeedProvider(q.copyWith(status: () => MatchStatus.live)));
    final upcoming = ref.watch(matchFeedProvider(q.copyWith(status: () => MatchStatus.upcoming)));
    final results = ref.watch(matchFeedProvider(q.copyWith(status: () => MatchStatus.completed)));
    final tournaments = ref.watch(tournamentActivityProvider(q));
    final loaded = live.hasValue && upcoming.hasValue && results.hasValue;
    if (loaded && live.value!.matches.isEmpty && upcoming.value!.matches.isEmpty && results.value!.matches.isEmpty) {
      return [_empty(q)];
    }
    return [
      if (live.isLoading && !live.hasValue) ...[
        const SxSection('Live now'),
        const Skeleton(height: 188, radius: Sx.radius),
        const SizedBox(height: Sx.section),
      ] else if (live.value?.matches.isNotEmpty ?? false) ...[
        SxSection('Live now', action: 'All ${live.value!.matches.length}${live.value!.hasMore ? '+' : ''}',
            onAction: () => _select(MatchesTab.live)),
        _Strip(
          key: const Key('liveNow'),
          height: 188,
          children: [for (final m in live.value!.matches.take(10)) LiveMatchCard(match: m)],
        ),
        const SizedBox(height: Sx.section),
      ],
      if (tournaments.value?.isNotEmpty ?? false) ...[
        SxSection('From tournaments', action: 'All', onAction: () => _select(MatchesTab.tournaments)),
        _Strip(
          key: const Key('fromTournaments'),
          height: 218,
          children: [for (final t in tournaments.value!.take(8)) TournamentActivityCard(activity: t, width: 256)],
        ),
        const SizedBox(height: Sx.section),
      ],
      if (upcoming.value?.matches.isNotEmpty ?? false) ...[
        SxSection('Coming up', action: 'See all', onAction: () => _select(MatchesTab.upcoming)),
        for (final m in upcoming.value!.matches.take(3))
          Padding(padding: const EdgeInsets.only(bottom: Sx.s12), child: MatchCard(match: m)),
        const SizedBox(height: Sx.s20),
      ],
      const SxSection('Latest results'),
      ..._pagedList(context, results, q.copyWith(status: () => MatchStatus.completed), grouped: true),
    ];
  }

  List<Widget> _paged(BuildContext context, MatchQuery q, {required bool grouped}) {
    final feed = ref.watch(matchFeedProvider(q));
    if (feed.value?.matches.isEmpty ?? false) return [_empty(q)];
    return _pagedList(context, feed, q, grouped: grouped);
  }

  List<Widget> _pagedList(BuildContext context, AsyncValue<MatchFeedPage> feed, MatchQuery q, {required bool grouped}) {
    final c = context.sx;
    return switch (feed) {
      AsyncData(:final value) when value.matches.isEmpty => [
          Text('No results yet for these filters.', style: SxType.body(c.inkMuted)),
        ],
      AsyncData(:final value) => [
          ..._cards(value.matches, grouped: grouped),
          if (value.hasMore)
            LoadMoreTrigger(
              key: ValueKey('more-${value.matches.length}'),
              rowHeight: 150,
              onLoad: () => ref.read(matchFeedProvider(q).notifier).loadMore(),
            )
          else
            Padding(
              padding: const EdgeInsets.all(Sx.s24),
              child: Center(child: Text('${value.matches.length} matches', style: SxType.label(c.inkFaint))),
            ),
        ],
      AsyncError() => [ErrorBlock(message: 'Matches did not load.', onRetry: () => ref.invalidate(matchFeedProvider(q)))],
      _ => const [MatchCardSkeleton()],
    };
  }

  /// Cards, under a day heading when the day changes.
  List<Widget> _cards(List<Match> matches, {required bool grouped}) {
    final now = DateTime.now();
    final out = <Widget>[];
    String? day;
    for (final m in matches) {
      if (grouped && !m.isLive) {
        final label = relativeDay(m.isCompleted ? m.playedAt : m.scheduledAt, now);
        if (label != day) {
          day = label;
          out.add(Padding(
            padding: EdgeInsets.only(top: out.isEmpty ? 0 : Sx.s12, bottom: Sx.s8),
            child: Text(label.toUpperCase(), style: SxType.label(context.sx.inkMuted, size: 12)),
          ));
        }
      }
      out.add(Padding(padding: const EdgeInsets.only(bottom: Sx.s12), child: MatchCard(match: m, now: now)));
    }
    return out;
  }

  Widget _empty(MatchQuery q) => EmptyBlock(
        key: const Key('noMatches'),
        icon: Icons.search_off_rounded,
        title: 'No matches found',
        message: q.isFiltered ? 'Try changing location, date or match type.' : 'Matches played on SkorX show up here as they happen.',
        action: q.isFiltered
            ? SxButton.secondary(
                key: const Key('clearMatchFilters'),
                label: 'Clear filters',
                expand: false,
                onPressed: () {
                  _search.clear();
                  _update((q) => q.cleared().copyWith(text: ''));
                },
              )
            : SxButton(
                key: const Key('playFirstMatch'),
                label: 'Score a match',
                expand: false,
                onPressed: () => context.push('/player/match/new'),
              ),
      );
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Semantics(
      button: true,
      label: count == 0 ? 'Filters' : 'Filters, $count on',
      excludeSemantics: true,
      child: Tappable(
        key: const Key('matchFilters'),
        onTap: onTap,
        radius: Sx.radius,
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            gradient: count > 0 ? c.brand : null,
            color: count > 0 ? null : c.surface,
            borderRadius: BorderRadius.circular(Sx.radius),
            border: Border.all(color: count > 0 ? Colors.transparent : c.cardEdge),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(Icons.tune_rounded, color: count > 0 ? c.onVolt : c.ink),
              if (count > 0)
                Positioned(
                  right: 6,
                  top: 5,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(color: c.onVolt, borderRadius: BorderRadius.circular(8)),
                    child: Text('$count', style: SxType.number(11, c.voltFill, weight: FontWeight.w800)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A horizontal strip of cards that bleeds to the screen edges.
class _Strip extends StatelessWidget {
  const _Strip({super.key, required this.height, required this.children});

  final double height;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          itemCount: children.length,
          separatorBuilder: (_, _) => const SizedBox(width: Sx.s12),
          itemBuilder: (_, i) => children[i],
        ),
      );
}

class _TournamentList extends ConsumerWidget {
  const _TournamentList({required this.query});

  final MatchQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(tournamentActivityProvider(query));
    return switch (list) {
      AsyncData(:final value) when value.isEmpty => EmptyBlock(
          key: const Key('noTournamentMatches'),
          icon: Icons.emoji_events_outlined,
          title: 'No tournament matches found',
          message: 'Try another tournament or location.',
          action: query.isFiltered
              ? SxButton.secondary(
                  label: 'Clear filters',
                  expand: false,
                  onPressed: () => ref.read(matchQueryProvider.notifier).update((q) => q.cleared().copyWith(text: '')),
                )
              : null,
        ),
      AsyncData(:final value) => Column(
          children: [
            for (final t in value) Padding(padding: const EdgeInsets.only(bottom: Sx.s12), child: TournamentActivityCard(activity: t)),
          ],
        ),
      AsyncError() => ErrorBlock(message: 'Tournaments did not load.', onRetry: () => ref.invalidate(tournamentActivityProvider(query))),
      _ => const SkeletonList(rows: 3, rowHeight: 200),
    };
  }
}

/// While typing: suggestions from the server; before typing: recent searches.
class _SearchPanel extends ConsumerWidget {
  const _SearchPanel({required this.text, required this.onPick, required this.onRecent});

  final String text;
  final ValueChanged<SearchSuggestion> onPick;
  final ValueChanged<String> onRecent;

  static IconData _icon(SuggestionKind k) => switch (k) {
        SuggestionKind.player => Icons.person_outline_rounded,
        SuggestionKind.tournament => Icons.emoji_events_outlined,
        SuggestionKind.venue => Icons.stadium_outlined,
        SuggestionKind.city => Icons.place_outlined,
        SuggestionKind.match => Icons.scoreboard_outlined,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    if (text.trim().length < 2) {
      final recent = ref.watch(recentMatchSearchesProvider);
      return Column(
        key: const Key('recentSearches'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: Sx.s8),
          if (recent.isEmpty)
            Text('Search a player, a tournament like "SPT 2026", a venue, a city or a match ID.', style: SxType.body(c.inkMuted))
          else ...[
            SxSection('Recent searches', action: 'Clear', onAction: () => ref.read(recentMatchSearchesProvider.notifier).clear()),
            Wrap(
              spacing: Sx.s8,
              runSpacing: Sx.s8,
              children: [for (final s in recent) SxChip(label: s, icon: Icons.history_rounded, selected: false, onTap: () => onRecent(s))],
            ),
          ],
        ],
      );
    }
    final suggestions = ref.watch(searchSuggestionsProvider(text.trim()));
    return switch (suggestions) {
      AsyncData(:final value) when value.isEmpty => Padding(
          padding: const EdgeInsets.only(top: Sx.s16),
          child: Text('No suggestions. Press search to look through every match.', style: SxType.body(c.inkMuted)),
        ),
      AsyncData(:final value) => SxRows(
          key: const Key('searchSuggestions'),
          children: [
            for (final s in value)
              SxRow(
                key: Key('suggest-${s.value}'),
                icon: _icon(s.kind),
                label: s.label,
                subtitle: s.detail,
                onTap: () => onPick(s),
              ),
          ],
        ),
      _ => const Padding(padding: EdgeInsets.only(top: Sx.s8), child: SkeletonList(rows: 3, rowHeight: 52)),
    };
  }
}
