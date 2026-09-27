import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../design/design.dart';
import '../../shared/format.dart';
import '../courts/data/courts.dart';
import '../matches/data/match_feed.dart';
import '../matches/ui/filter_widgets.dart';
import '../player/data/player_repository.dart';
import '../player/data/x_code.dart';
import '../player/player_pages.dart';
import '../player/ui/player_quick_view.dart';
import '../tournaments/data/tournaments.dart';
import '../tournaments/ui/tournament_banner.dart';

enum ExploreView { tournaments, courts, players }

/// Discovery: where can I play, and who with? Tournaments to enter, courts
/// to book, players to find.
class ExplorePage extends ConsumerStatefulWidget {
  const ExplorePage({super.key, this.view});

  final String? view;

  @override
  ConsumerState<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends ConsumerState<ExplorePage> {
  late ExploreView _view = ExploreView.values.asNameMap()[widget.view] ?? ExploreView.tournaments;
  final _search = TextEditingController();
  Timer? _debounce;
  String _courtQuery = '';
  String _playerQuery = '';

  @override
  void didUpdateWidget(ExplorePage old) {
    super.didUpdateWidget(old);
    final v = ExploreView.values.asNameMap()[widget.view];
    if (old.view != widget.view && v != null) _view = v;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String text) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _onSearch(text));
  }

  void _onSearch(String text) {
    switch (_view) {
      case ExploreView.tournaments:
        ref.read(tournamentFiltersProvider.notifier).search(text);
      case ExploreView.courts:
        setState(() => _courtQuery = text.trim().toLowerCase());
      case ExploreView.players:
        setState(() => _playerQuery = text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return PlayerTabList(
      onRefresh: () async {
        ref.invalidate(discoverTournamentsProvider);
        ref.invalidate(venueSearchProvider);
        ref.invalidate(myTournamentsProvider);
        ref.invalidate(playerSearchProvider);
      },
      header: Column(
        children: [
          const SxTitleBar(title: 'Explore'),
          Padding(
            padding: const EdgeInsets.fromLTRB(Sx.gutter, 0, Sx.gutter, Sx.s12),
            child: TextField(
              key: const Key('exploreSearch'),
              controller: _search,
              onChanged: _onSearchChanged,
              onSubmitted: _onSearch,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: Icon(Icons.close_rounded, color: c.inkMuted),
                        onPressed: () {
                          _search.clear();
                          _debounce?.cancel();
                          _onSearch('');
                        },
                      ),
                hintText: switch (_view) {
                  ExploreView.tournaments => 'Search tournament, organiser, venue, city',
                  ExploreView.courts => 'Search venues',
                  ExploreView.players => 'Search players by name, X code or city',
                },
                prefixIcon: Icon(Icons.search_rounded, color: c.inkMuted),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          SxTabs<ExploreView>(
            tabs: const [
              (ExploreView.tournaments, 'Tournaments', null),
              (ExploreView.courts, 'Courts', null),
              (ExploreView.players, 'Players', null),
            ],
            selected: _view,
            onSelect: (v) {
              setState(() => _view = v);
              _search.clear();
              _onSearch('');
            },
          ),
        ],
      ),
      children: [
        const SizedBox(height: Sx.s16),
        switch (_view) {
          ExploreView.tournaments => const _TournamentsView(),
          ExploreView.courts => _CourtsView(query: _courtQuery),
          ExploreView.players => _PlayersView(query: _playerQuery),
        },
      ],
    );
  }
}

class _TournamentsView extends ConsumerWidget {
  const _TournamentsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final filters = ref.watch(tournamentFiltersProvider);
    final results = ref.watch(filteredTournamentsProvider);
    final mine = ref.watch(myTournamentsProvider).value ?? const [];
    final registered = {for (final m in mine) m.tournament.id};
    final ctl = ref.read(tournamentFiltersProvider.notifier);
    // Matches played so far, per tournament, for the cards.
    final matchCounts = {
      for (final a in ref.watch(tournamentActivityProvider(const MatchQuery())).value ?? const <TournamentActivity>[]) a.id: a.total,
    };
    bool phaseOn(TournamentPhase p) => filters.phases.contains(p);

    Widget chip(String label, bool on, TournamentFilters Function(TournamentFilters) change, {IconData? icon}) =>
        Padding(
          padding: const EdgeInsets.only(right: Sx.s8),
          child: SxChip(label: label, icon: icon, selected: on, onTap: () => ctl.update(change)),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (mine.isNotEmpty) ...[
          SxBlock(
            key: const Key('yourTournaments'),
            padding: const EdgeInsets.symmetric(horizontal: Sx.s16, vertical: Sx.s12),
            onTap: () => context.push('/player/tournaments/mine'),
            semanticLabel: 'Your tournaments, ${mine.length}',
            child: Row(
              children: [
                const StateGlyph(SxState.registered, size: 10),
                const SizedBox(width: Sx.s12),
                Expanded(child: Text('Your tournaments', style: SxType.heading(c.ink, size: 15))),
                Text('${mine.length}', style: SxType.number(18, c.ink, weight: FontWeight.w800)),
                Icon(Icons.chevron_right_rounded, color: c.inkFaint),
              ],
            ),
          ),
          const SizedBox(height: Sx.s16),
        ],
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: Sx.s8),
                child: SxChip(
                  key: const Key('filterButton'),
                  label: filters.activeCount == 0 ? 'Filters' : 'Filters · ${filters.activeCount}',
                  icon: Icons.tune_rounded,
                  selected: filters.activeCount > 0,
                  onTap: () => showSxSheet<void>(context, builder: (_) => const _FilterSheet()),
                ),
              ),
              chip('Live', phaseOn(TournamentPhase.live), (f) => f.copyWith(phases: _toggle(f.phases, TournamentPhase.live)),
                  icon: Icons.circle),
              chip('Upcoming', phaseOn(TournamentPhase.upcoming),
                  (f) => f.copyWith(phases: _toggle(f.phases, TournamentPhase.upcoming))),
              chip('Completed', phaseOn(TournamentPhase.completed),
                  (f) => f.copyWith(phases: _toggle(f.phases, TournamentPhase.completed))),
              chip('This week', filters.dates == DateWindow.thisWeek,
                  (f) => f.copyWith(dates: f.dates == DateWindow.thisWeek ? DateWindow.any : DateWindow.thisWeek)),
              chip('Near me', filters.nearby, (f) => f.copyWith(nearby: !f.nearby)),
              chip('Doubles', filters.formats.contains(PlayCategory.doubles),
                  (f) => f.copyWith(formats: _toggle(f.formats, PlayCategory.doubles))),
            ],
          ),
        ),
        if (_activeChips(filters, ctl).isNotEmpty) ...[
          const SizedBox(height: Sx.s8),
          Wrap(
            spacing: Sx.s8,
            runSpacing: Sx.s8,
            children: [
              ..._activeChips(filters, ctl),
              if (_activeChips(filters, ctl).length > 1)
                Tappable(
                  onTap: () => ctl.update((f) => f.cleared()),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Sx.s8, vertical: Sx.s8),
                    child: Text('Clear all', style: SxType.caption(c.isDark ? c.cyan : c.blue).copyWith(fontWeight: FontWeight.w700)),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: Sx.s20),
        switch (results) {
          AsyncData(:final value) when value.isEmpty => EmptyBlock(
              icon: Icons.search_off_rounded,
              title: 'No tournaments found',
              message: 'Try another location, date or status.',
              action: SxButton.secondary(
                label: 'Clear filters',
                expand: false,
                onPressed: () => ctl.update((f) => f.cleared()),
              ),
            ),
          AsyncData(:final value) => Column(
              children: [
                for (final t in value)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Sx.s12),
                    child: TournamentBannerCard(
                      tournament: t,
                      registered: registered.contains(t.id),
                      matchCount: matchCounts[t.id],
                      onTap: () => context.push('/player/tournament/${t.id}'),
                    ),
                  ),
              ],
            ),
          AsyncError() => ErrorBlock(message: 'Tournaments did not load.', onRetry: () => ref.invalidate(discoverTournamentsProvider)),
          _ => const SkeletonList(rows: 3, rowHeight: 260),
        },
      ],
    );
  }

  static Set<T> _toggle<T>(Set<T> set, T value) => set.contains(value) ? ({...set}..remove(value)) : {...set, value};

  /// Everything filtered on, each removable.
  static List<Widget> _activeChips(TournamentFilters f, TournamentFiltersController ctl) => [
        if (!f.place.isAny)
          RemovableChip(icon: Icons.place_outlined, label: f.place.label!, onRemove: () => ctl.update((f) => f.copyWith(place: const PlaceFilter()))),
        for (final p in f.phases)
          RemovableChip(
            label: switch (p) {
              TournamentPhase.live => 'Live',
              TournamentPhase.upcoming => 'Upcoming',
              TournamentPhase.completed => 'Completed',
            },
            onRemove: () => ctl.update((f) => f.copyWith(phases: _toggle(f.phases, p))),
          ),
        if (f.dates != DateWindow.any)
          RemovableChip(icon: Icons.event_outlined, label: f.dates.label, onRemove: () => ctl.update((f) => f.copyWith(dates: DateWindow.any))),
        if (f.nearby) RemovableChip(label: 'Near me', onRemove: () => ctl.update((f) => f.copyWith(nearby: false))),
        for (final l in f.levels) RemovableChip(label: l, onRemove: () => ctl.update((f) => f.copyWith(levels: _toggle(f.levels, l)))),
        for (final p in f.formats)
          RemovableChip(label: p.label, onRemove: () => ctl.update((f) => f.copyWith(formats: _toggle(f.formats, p)))),
        if (f.maxFee != null)
          RemovableChip(
            label: f.maxFee == 0 ? 'Free' : 'Up to ${formatInr(f.maxFee!)}',
            onRemove: () => ctl.update((f) => f.copyWith(maxFee: () => null)),
          ),
      ];
}

class _FilterSheet extends ConsumerWidget {
  const _FilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final f = ref.watch(tournamentFiltersProvider);
    final ctl = ref.read(tournamentFiltersProvider.notifier);
    Widget group(String title, List<Widget> chips) => Padding(
          padding: const EdgeInsets.only(bottom: Sx.s24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [SxSection(title), Wrap(spacing: Sx.s8, runSpacing: Sx.s8, children: chips)],
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sx.gutter, 0, Sx.gutter, Sx.s24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('FILTER TOURNAMENTS', style: SxType.title(c.ink, size: 28)),
            const SizedBox(height: Sx.s24),
            const SxSection('Location'),
            PlacePicker(
              options: ref.watch(tournamentPlacesProvider),
              value: f.place,
              onChanged: (p) => ctl.update((f) => f.copyWith(place: p)),
            ),
            const SizedBox(height: Sx.s24),
            group('Status', [
              for (final (p, label) in const [
                (TournamentPhase.live, 'Live'),
                (TournamentPhase.upcoming, 'Upcoming'),
                (TournamentPhase.completed, 'Completed'),
              ])
                SxChip(
                  key: Key('phase-${p.name}'),
                  label: label,
                  selected: f.phases.contains(p),
                  onTap: () => ctl.update((f) => f.copyWith(phases: _TournamentsView._toggle(f.phases, p))),
                ),
            ]),
            group('Skill level', [
              for (final l in skillLevels)
                SxChip(
                  label: l,
                  selected: f.levels.contains(l),
                  onTap: () => ctl.update((f) => f.copyWith(levels: _TournamentsView._toggle(f.levels, l))),
                ),
            ]),
            group('Tournament type', [
              for (final p in PlayCategory.values)
                SxChip(
                  label: p.label,
                  selected: f.formats.contains(p),
                  onTap: () => ctl.update((f) => f.copyWith(formats: _TournamentsView._toggle(f.formats, p))),
                ),
            ]),
            group('Date', [
              for (final d in DateWindow.values)
                SxChip(label: d.label, selected: f.dates == d, onTap: () => ctl.update((f) => f.copyWith(dates: d))),
            ]),
            group('Entry fee', [
              for (final fee in const [null, 0, 500, 1000])
                SxChip(
                  label: fee == null ? 'Any' : fee == 0 ? 'Free' : 'Up to ${formatInr(fee)}',
                  selected: f.maxFee == fee,
                  onTap: () => ctl.update((f) => f.copyWith(maxFee: () => fee)),
                ),
            ]),
            group('Sort by', [
              for (final s in TournamentSort.values)
                SxChip(label: s.label, selected: f.sort == s, onTap: () => ctl.update((f) => f.copyWith(sort: s))),
            ]),
            Row(
              children: [
                SxButton.quiet(label: 'Clear all', onPressed: () => ctl.update((f) => f.cleared())),
                const Spacer(),
                SxButton(label: 'Show results', expand: false, onPressed: () => Navigator.of(context).pop()),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Courts: location and date here; time and court on the venue.
class _CourtsView extends ConsumerWidget {
  const _CourtsView({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final search = ref.watch(courtSearchProvider);
    final results = ref.watch(venueSearchProvider(search));
    final today = DateTime.now();
    final days = [for (var i = 0; i < 7; i++) DateTime(today.year, today.month, today.day + i)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1 · Location
        SxRow(
          key: const Key('cityPicker'),
          icon: Icons.place_outlined,
          label: search.city,
          subtitle: 'Location',
          onTap: () async {
            final city = await showSxSheet<String>(
              context,
              builder: (ctx) => Padding(
                padding: const EdgeInsets.fromLTRB(Sx.gutter, 0, Sx.gutter, Sx.s24),
                child: SxRows(
                  title: 'City',
                  children: [
                    for (final city in bookingCities)
                      SxRow(
                        label: city,
                        trailing: city == search.city ? Icon(Icons.check_rounded, color: c.ink) : null,
                        onTap: () => Navigator.of(ctx).pop(city),
                      ),
                  ],
                ),
              ),
            );
            if (city != null) ref.read(courtSearchProvider.notifier).setCity(city);
          },
        ),
        const SizedBox(height: Sx.s16),
        // 2 · Date
        DateStrip(
          days: days,
          selected: search.date,
          onSelect: (d) => ref.read(courtSearchProvider.notifier).setDate(d),
        ),
        const SizedBox(height: Sx.s24),
        switch (results) {
          AsyncData(:final value) => () {
              final list = value.where((v) => query.isEmpty || v.venue.name.toLowerCase().contains(query)).toList();
              if (list.isEmpty) {
                return EmptyBlock(
                  icon: Icons.stadium_outlined,
                  title: 'No courts here yet',
                  message: 'SkorX venues in ${search.city} will show up here. Try another city.',
                  compact: true,
                );
              }
              return Column(
                children: [
                  for (final v in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Sx.s12),
                      child: _VenueCard(availability: v, date: search.date),
                    ),
                ],
              );
            }(),
          AsyncError() => ErrorBlock(message: 'Courts did not load.', onRetry: () => ref.invalidate(venueSearchProvider(search))),
          _ => const SkeletonList(rows: 3, rowHeight: 110),
        },
      ],
    );
  }
}

/// A week of days to pick from.
class DateStrip extends StatelessWidget {
  const DateStrip({super.key, required this.days, required this.selected, required this.onSelect});

  final List<DateTime> days;
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final now = DateTime.now();
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: days.length,
        separatorBuilder: (_, _) => const SizedBox(width: Sx.s8),
        itemBuilder: (_, i) {
          final d = days[i];
          final on = daysBetween(d, selected) == 0;
          final top = i == 0 ? 'TODAY' : weekdaysShort[d.weekday - 1].toUpperCase();
          return Semantics(
            button: true,
            selected: on,
            label: relativeDay(d, now),
            excludeSemantics: true,
            child: Tappable(
              onTap: () => onSelect(d),
              radius: Sx.radius,
              child: AnimatedContainer(
                duration: Sx.fast,
                width: 58,
                decoration: BoxDecoration(
                  color: on ? c.ink : Colors.transparent,
                  borderRadius: BorderRadius.circular(Sx.radius),
                  border: Border.all(color: on ? c.ink : c.line),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(top, style: SxType.label(on ? c.canvas : c.inkMuted, size: 10.5)),
                    const SizedBox(height: 4),
                    Text('${d.day}', style: SxType.number(24, on ? c.canvas : c.ink, weight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _VenueCard extends StatelessWidget {
  const _VenueCard({required this.availability, required this.date});

  final VenueAvailability availability;
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final v = availability.venue;
    final free = availability.freeSlots;
    void open([int? hour]) =>
        context.push('/player/venue/${v.id}?date=${isoDay(date)}${hour == null ? '' : '&hour=$hour'}');
    return SxBlock(
      onTap: open,
      semanticLabel: '${v.name}, ${v.area}, ${free.length} times free',
      padding: const EdgeInsets.all(Sx.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(v.name, style: SxType.heading(c.ink, size: 17)),
                    const SizedBox(height: 2),
                    Text(
                      '${v.area} · ${v.distanceKm.toStringAsFixed(1)} km · ${v.courts} courts · ${v.indoor ? 'Indoor' : 'Outdoor'}',
                      style: SxType.caption(c.inkMuted),
                    ),
                  ],
                ),
              ),
              Text('${formatInr(v.pricePerHour)}/h', style: SxType.heading(c.ink, size: 14)),
            ],
          ),
          const SizedBox(height: Sx.s12),
          if (free.isEmpty)
            Text(
              daysBetween(DateTime.now(), date) == 0 ? 'No more slots today · try tomorrow' : 'Fully booked on this day',
              style: SxType.caption(c.inkFaint),
            )
          else
            Wrap(
              spacing: Sx.s8,
              runSpacing: Sx.s8,
              children: [
                for (final s in free.take(4))
                  Tappable(
                    onTap: () => open(s.start.hour),
                    radius: Sx.radiusSm,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: Sx.s12, vertical: Sx.s8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(Sx.radiusSm),
                        border: Border.all(color: c.line),
                      ),
                      child: Text(timeShort(s.start), style: SxType.number(15, c.ink)),
                    ),
                  ),
                if (free.length > 4)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: Sx.s8),
                    child: Text('+${free.length - 4} more', style: SxType.caption(c.inkMuted)),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Players: find a partner, size up an opponent.
class _PlayersView extends ConsumerWidget {
  const _PlayersView({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filters = ref.watch(playerFiltersProvider);
    final results = ref.watch(filteredPlayersProvider(query));
    final myCity = ref.watch(playerOverviewProvider).value?.city ?? ref.watch(courtSearchProvider).city;
    final ctl = ref.read(playerFiltersProvider.notifier);
    final code = XCode.parse(query);

    Widget chip(String label, bool on, PlayerFilters Function(PlayerFilters) change) => Padding(
          padding: const EdgeInsets.only(right: Sx.s8),
          child: SxChip(label: label, selected: on, onTap: () => ctl.update(change)),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: Sx.s8),
                child: SxChip(
                  key: const Key('playerFilterButton'),
                  label: filters.activeCount == 0 ? 'Filters' : 'Filters · ${filters.activeCount}',
                  icon: Icons.tune_rounded,
                  selected: filters.activeCount > 0,
                  onTap: () => showSxSheet<void>(context, builder: (_) => const _PlayerFilterSheet()),
                ),
              ),
              chip('Near me', filters.city == myCity,
                  (f) => f.copyWith(city: () => f.city == myCity ? null : myCity)),
              for (final l in const ['Beginner', 'Intermediate', 'Advanced'])
                chip(l, filters.levels.contains(l), (f) => f.copyWith(levels: _TournamentsView._toggle(f.levels, l))),
              for (final p in PlayCategory.values)
                chip(p.label, filters.formats.contains(p),
                    (f) => f.copyWith(formats: _TournamentsView._toggle(f.formats, p))),
            ],
          ),
        ),
        const SizedBox(height: Sx.s20),
        switch (results) {
          AsyncData(:final value) when value.isEmpty => EmptyBlock(
              icon: Icons.person_search_rounded,
              title: code != null ? 'No player with X code $code' : 'No players match',
              message: code != null
                  ? 'Check the code with them. It is 4 letters and digits, like 7K2Q.'
                  : filters.activeCount > 0
                      ? 'Try fewer filters or another city.'
                      : 'Check the spelling, or search by X code like 7K2Q.',
              action: code == null && filters.activeCount > 0
                  ? SxButton.secondary(label: 'Clear filters', expand: false, onPressed: () => ctl.update((f) => f.cleared()))
                  : null,
              compact: true,
            ),
          AsyncData(:final value) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SxSection('${value.length} player${value.length == 1 ? '' : 's'} · ${filters.sort.label.toLowerCase()}'),
                for (final p in value)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Sx.s8),
                    child: _PlayerCard(player: p),
                  ),
              ],
            ),
          AsyncError() => ErrorBlock(message: 'Players did not load.', onRetry: () => ref.invalidate(playerSearchProvider(query))),
          _ => const SkeletonList(rows: 5, rowHeight: 72),
        },
      ],
    );
  }
}

class _PlayerFilterSheet extends ConsumerWidget {
  const _PlayerFilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final f = ref.watch(playerFiltersProvider);
    final ctl = ref.read(playerFiltersProvider.notifier);
    Widget group(String title, List<Widget> chips) => Padding(
          padding: const EdgeInsets.only(bottom: Sx.s24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [SxSection(title), Wrap(spacing: Sx.s8, runSpacing: Sx.s8, children: chips)],
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sx.gutter, 0, Sx.gutter, Sx.s24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('FILTERS', style: SxType.title(c.ink, size: 28)),
            const SizedBox(height: Sx.s24),
            group('City', [
              for (final city in [null, ...bookingCities])
                SxChip(
                  label: city ?? 'Anywhere',
                  selected: f.city == city,
                  onTap: () => ctl.update((f) => f.copyWith(city: () => city)),
                ),
            ]),
            group('Level', [
              for (final l in playerLevels)
                SxChip(
                  label: l,
                  selected: f.levels.contains(l),
                  onTap: () => ctl.update((f) => f.copyWith(levels: _TournamentsView._toggle(f.levels, l))),
                ),
            ]),
            group('Best format', [
              for (final p in PlayCategory.values)
                SxChip(
                  label: p.label,
                  selected: f.formats.contains(p),
                  onTap: () => ctl.update((f) => f.copyWith(formats: _TournamentsView._toggle(f.formats, p))),
                ),
            ]),
            group('SkorX Points', [
              for (final r in const [null, 300, 500, 700, 900])
                SxChip(
                  label: r == null ? 'Any' : '$r+',
                  selected: f.minRating == r,
                  onTap: () => ctl.update((f) => f.copyWith(minRating: () => r)),
                ),
            ]),
            group('Sort by', [
              for (final s in PlayerSort.values)
                SxChip(label: s.label, selected: f.sort == s, onTap: () => ctl.update((f) => f.copyWith(sort: s))),
            ]),
            Row(
              children: [
                SxButton.quiet(label: 'Clear all', onPressed: () => ctl.update((f) => f.cleared())),
                const Spacer(),
                SxButton(label: 'Show players', expand: false, onPressed: () => Navigator.of(context).pop()),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerCard extends StatelessWidget {
  const _PlayerCard({required this.player});

  final PlayerSummary player;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final p = player;
    return SxBlock(
      key: Key('player-${p.playerId}'),
      padding: const EdgeInsets.symmetric(horizontal: Sx.s16, vertical: Sx.s12),
      semanticLabel: '${p.name}, ${p.city}, ${p.level}${p.rating == null ? '' : ', rating ${p.rating}'}',
      onTap: () => showPlayerQuickView(context, p.name),
      child: Row(
        children: [
          SxAvatar(name: p.name, size: 44),
          const SizedBox(width: Sx.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.heading(c.ink, size: 16)),
                const SizedBox(height: 2),
                Text([p.city, p.level, if (p.xCode != null) XCode.display(p.xCode!)].join(' · '), style: SxType.caption(c.inkMuted)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(p.rating?.toString() ?? '—', style: SxType.number(18, c.ink, weight: FontWeight.w800)),
              Text('RATING', style: SxType.label(c.inkFaint, size: 9.5)),
            ],
          ),
          const SizedBox(width: Sx.s4),
          Icon(Icons.chevron_right_rounded, color: c.inkFaint),
        ],
      ),
    );
  }
}
