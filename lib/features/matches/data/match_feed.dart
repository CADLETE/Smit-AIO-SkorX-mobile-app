import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sample_latency.dart';
import '../../auth/auth_controller.dart';
import '../../player/data/player_repository.dart' show PlayCategory;
import '../../tournaments/data/tournaments.dart' show PlaceFilter, PlaceOption, placeOptions;
import 'match.dart';
import 'sample_universe.dart';

/// When a match is played, for the Matches date filter.
enum MatchWhen {
  any('Any date'),
  today('Today'),
  tomorrow('Tomorrow'),
  thisWeek('This week'),
  day('Pick a date');

  const MatchWhen(this.label);
  final String label;
}

/// Everything the Matches tab can narrow the SkorX match universe by. Sent
/// to the server as query parameters ([toQuery]); nothing is filtered on
/// the phone.
@immutable
class MatchQuery {
  const MatchQuery({
    this.status,
    this.place = const PlaceFilter(),
    this.venue,
    this.formats = const {},
    this.category,
    this.tournamentId,
    this.tournamentName,
    this.when = MatchWhen.any,
    this.day,
    this.text = '',
  });

  /// Null: live, upcoming and completed.
  final MatchStatus? status;
  final PlaceFilter place;
  final String? venue;
  final Set<PlayCategory> formats;

  /// Null: casual and tournament.
  final MatchCategory? category;
  final String? tournamentId;

  /// For the filter chip only; the server filters by [tournamentId].
  final String? tournamentName;
  final MatchWhen when;

  /// The date picked, for [MatchWhen.day].
  final DateTime? day;

  /// Player, tournament, venue, city or match id.
  final String text;

  /// Filters in the sheet that are on (status and search have their own
  /// controls), for the filter button's badge.
  int get activeCount =>
      (place.isAny ? 0 : 1) +
      (venue == null ? 0 : 1) +
      formats.length +
      (category == null ? 0 : 1) +
      (tournamentId == null ? 0 : 1) +
      (when == MatchWhen.any ? 0 : 1);

  bool get isFiltered => activeCount > 0 || text.trim().isNotEmpty;

  MatchQuery copyWith({
    MatchStatus? Function()? status,
    PlaceFilter? place,
    String? Function()? venue,
    Set<PlayCategory>? formats,
    MatchCategory? Function()? category,
    (String, String)? Function()? tournament,
    MatchWhen? when,
    DateTime? Function()? day,
    String? text,
  }) {
    final t = tournament == null ? (tournamentId == null ? null : (tournamentId!, tournamentName ?? '')) : tournament();
    return MatchQuery(
      status: status == null ? this.status : status(),
      place: place ?? this.place,
      venue: venue == null ? this.venue : venue(),
      formats: formats ?? this.formats,
      category: category == null ? this.category : category(),
      tournamentId: t?.$1,
      tournamentName: t?.$2,
      when: when ?? this.when,
      day: day == null ? this.day : day(),
      text: text ?? this.text,
    );
  }

  /// Everything but the status tab and the search text.
  MatchQuery cleared() => MatchQuery(status: status, text: text);

  /// The date range this query covers, [from, to).
  (DateTime, DateTime)? range(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return switch (when) {
      MatchWhen.any => null,
      MatchWhen.today => (today, today.add(const Duration(days: 1))),
      MatchWhen.tomorrow => (today.add(const Duration(days: 1)), today.add(const Duration(days: 2))),
      MatchWhen.thisWeek => (today, today.add(const Duration(days: 7))),
      MatchWhen.day => day == null
          ? null
          : (DateTime(day!.year, day!.month, day!.day), DateTime(day!.year, day!.month, day!.day + 1)),
    };
  }

  /// `GET /matches` query parameters.
  Map<String, String> toQuery(DateTime now) {
    final r = range(now);
    return {
      if (status != null) 'status': status!.name,
      if (place.country != null) 'country': place.country!,
      if (place.region != null) 'state': place.region!,
      if (place.city != null) 'city': place.city!,
      'venue': ?venue,
      if (formats.isNotEmpty) 'format': formats.map((f) => f.name).join(','),
      'category': ?category?.name,
      'tournament': ?tournamentId,
      if (r != null) 'from': r.$1.toIso8601String(),
      if (r != null) 'to': r.$2.toIso8601String(),
      if (text.trim().isNotEmpty) 'q': text.trim(),
    };
  }

  /// The same filter the server applies. Used by the sample repository.
  bool matches(Match m, DateTime now, {bool ignoreStatus = false}) {
    if (m.isCancelled) return false;
    if (!ignoreStatus && status != null && m.status != status) return false;
    final p = m.place;
    if (!place.isAny && (p == null || !place.includes(country: p.country, region: p.region, city: p.city))) return false;
    if (venue != null && m.venue != venue) return false;
    if (formats.isNotEmpty && !formats.contains(m.format)) return false;
    if (category != null && m.category != category) return false;
    if (tournamentId != null && m.tournament?.id != tournamentId) return false;
    final r = range(now);
    if (r != null) {
      final at = m.isCompleted ? m.playedAt : m.scheduledAt;
      if (m.isLive ? !(r.$1.isBefore(now) && r.$2.isAfter(now)) : (at.isBefore(r.$1) || !at.isBefore(r.$2))) return false;
    }
    final q = text.trim().toLowerCase();
    if (q.isNotEmpty) {
      final haystack = [
        m.id,
        ...m.players,
        ?m.tournament?.name,
        ?m.venue,
        ?p?.city,
        ?p?.region,
        ?p?.country,
      ].join(' · ').toLowerCase();
      if (!haystack.contains(q)) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is MatchQuery &&
      other.status == status &&
      other.place == place &&
      other.venue == venue &&
      setEquals(other.formats, formats) &&
      other.category == category &&
      other.tournamentId == tournamentId &&
      other.when == when &&
      other.day == day &&
      other.text == text;

  @override
  int get hashCode =>
      Object.hash(status, place, venue, Object.hashAllUnordered(formats), category, tournamentId, when, day, text);
}

/// One page of the feed, and where the next one starts.
class MatchFeedPage {
  const MatchFeedPage(this.matches, {this.nextCursor});

  final List<Match> matches;

  /// Opaque; null on the last page.
  final String? nextCursor;
  bool get hasMore => nextCursor != null;
}

/// A tournament with matches on SkorX, and how many are live, coming up and done.
class TournamentActivity {
  const TournamentActivity({
    required this.id,
    required this.name,
    required this.place,
    required this.venue,
    required this.start,
    required this.end,
    required this.live,
    required this.upcoming,
    required this.completed,
  });

  final String id;
  final String name;
  final MatchPlace place;
  final String venue;
  final DateTime start;
  final DateTime end;
  final int live;
  final int upcoming;
  final int completed;

  int get total => live + upcoming + completed;
}

/// A venue with matches, and where it is: the location filter's leaves.
typedef VenueOption = ({String venue, MatchPlace place});

enum SuggestionKind { player, tournament, venue, city, match }

/// A search suggestion: tapping it narrows the feed.
class SearchSuggestion {
  const SearchSuggestion(this.kind, this.label, {required this.value, this.detail});

  final SuggestionKind kind;
  final String label;
  final String? detail;

  /// Player name, tournament id, venue, city or match id.
  final String value;
}

/// Every match on SkorX: the Matches tab. Method names mirror the endpoints
/// they will call; none exist in the new API yet (docs/PLAYER-APP.md §6).
abstract class MatchFeedRepository {
  /// `GET /matches?status&country&state&city&venue&format&category&tournament&from&to&q&cursor&limit`
  /// ([MatchQuery.toQuery]). Live first (latest start), then upcoming
  /// (soonest), then completed (newest).
  Future<MatchFeedPage> feed(MatchQuery query, {String? cursor, int limit = 20});

  /// `GET /tournaments/activity?country&state&city&format&from&to&q`: tournaments
  /// with matches, live ones first, with their match counts.
  Future<List<TournamentActivity>> tournaments(MatchQuery query);

  /// `GET /matches/places`: countries, states, cities and venues that have
  /// matches, for the location filter.
  Future<List<VenueOption>> places();

  /// `GET /search/suggest?q`: players, tournaments, venues, cities, match ids.
  Future<List<SearchSuggestion>> suggest(String text);
}

final matchFeedRepositoryProvider = Provider<MatchFeedRepository>((ref) {
  if (!kDebugMode) return const EmptyMatchFeedRepository();
  return SampleMatchFeedRepository(ref.watch(sampleUniverseProvider), latency: ref.watch(sampleLatencyProvider));
});

/// The Matches tab's current filters.
final matchQueryProvider = NotifierProvider<MatchQueryController, MatchQuery>(MatchQueryController.new);

class MatchQueryController extends Notifier<MatchQuery> {
  @override
  MatchQuery build() => const MatchQuery();

  void update(MatchQuery Function(MatchQuery) change) => state = change(state);
}

/// A feed for one query, loaded a page at a time as the list scrolls.
final matchFeedProvider =
    AsyncNotifierProvider.autoDispose.family<MatchFeed, MatchFeedPage, MatchQuery>(MatchFeed.new);

class MatchFeed extends AsyncNotifier<MatchFeedPage> {
  MatchFeed(this.query);

  final MatchQuery query;
  bool _loading = false;

  @override
  Future<MatchFeedPage> build() => ref.watch(matchFeedRepositoryProvider).feed(query);

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || _loading) return;
    _loading = true;
    try {
      final next = await ref.read(matchFeedRepositoryProvider).feed(query, cursor: current.nextCursor);
      state = AsyncData(MatchFeedPage([...current.matches, ...next.matches], nextCursor: next.nextCursor));
    } finally {
      _loading = false;
    }
  }
}

final tournamentActivityProvider = FutureProvider.autoDispose.family<List<TournamentActivity>, MatchQuery>(
  (ref, query) => ref.watch(matchFeedRepositoryProvider).tournaments(query),
);

/// Venues and places with matches; kept for the session.
final matchPlacesProvider = FutureProvider<List<VenueOption>>((ref) => ref.watch(matchFeedRepositoryProvider).places());

/// The location filter's tree, from [matchPlacesProvider].
final matchPlaceOptionsProvider = Provider<List<PlaceOption>>((ref) {
  final venues = ref.watch(matchPlacesProvider).value ?? const [];
  return placeOptions([for (final v in venues) (country: v.place.country, region: v.place.region, city: v.place.city)]);
});

final searchSuggestionsProvider = FutureProvider.autoDispose.family<List<SearchSuggestion>, String>((ref, text) {
  if (text.trim().length < 2) return const [];
  return ref.watch(matchFeedRepositoryProvider).suggest(text.trim());
});

/// The last few searches on this phone, newest first.
final recentMatchSearchesProvider =
    NotifierProvider<RecentMatchSearches, List<String>>(RecentMatchSearches.new);

class RecentMatchSearches extends Notifier<List<String>> {
  static const _key = 'skorx.recentMatchSearches';
  static const _max = 6;

  @override
  List<String> build() {
    Future.microtask(_load);
    return const [];
  }

  Future<void> _load() async {
    try {
      final saved = await ref.read(preferencesProvider).getStringList(_key);
      if (saved != null && state.isEmpty) state = saved;
    } catch (_) {
      // Nothing saved yet, or unreadable: start empty.
    }
  }

  void add(String text) {
    final t = text.trim();
    if (t.length < 2) return;
    state = [t, ...state.where((s) => s.toLowerCase() != t.toLowerCase())].take(_max).toList();
    ref.read(preferencesProvider).setStringList(_key, state);
  }

  void clear() {
    state = const [];
    ref.read(preferencesProvider).remove(_key);
  }
}

/// Release builds until the endpoints exist: honest empty states.
class EmptyMatchFeedRepository implements MatchFeedRepository {
  const EmptyMatchFeedRepository();

  @override
  Future<MatchFeedPage> feed(MatchQuery query, {String? cursor, int limit = 20}) async => const MatchFeedPage([]);

  @override
  Future<List<TournamentActivity>> tournaments(MatchQuery query) async => const [];

  @override
  Future<List<VenueOption>> places() async => const [];

  @override
  Future<List<SearchSuggestion>> suggest(String text) async => const [];
}

/// Debug builds: the sample universe, filtered and paged the way the server
/// will do it.
class SampleMatchFeedRepository implements MatchFeedRepository {
  SampleMatchFeedRepository(this.universe, {this.latency = const Duration(milliseconds: 350)});

  final SampleUniverse universe;
  final Duration latency;

  static int _order(Match a, Match b) {
    int rank(Match m) => m.isLive ? 0 : m.isUpcoming ? 1 : 2;
    final r = rank(a).compareTo(rank(b));
    if (r != 0) return r;
    if (a.isLive) return (b.startedAt ?? b.scheduledAt).compareTo(a.startedAt ?? a.scheduledAt);
    if (a.isUpcoming) return a.scheduledAt.compareTo(b.scheduledAt);
    return b.playedAt.compareTo(a.playedAt);
  }

  @override
  Future<MatchFeedPage> feed(MatchQuery query, {String? cursor, int limit = 20}) async {
    await simulateLatency(latency);
    final now = DateTime.now();
    final all = universe.matches.where((m) => query.matches(m, now)).toList()..sort(_order);
    final from = int.tryParse(cursor ?? '') ?? 0;
    final end = (from + limit).clamp(0, all.length);
    return MatchFeedPage(all.sublist(from.clamp(0, all.length), end), nextCursor: end < all.length ? '$end' : null);
  }

  @override
  Future<List<TournamentActivity>> tournaments(MatchQuery query) async {
    await simulateLatency(latency);
    final now = DateTime.now();
    // Everything but status and tournament: the counts are per status.
    final scope = query.copyWith(status: () => null, tournament: () => null, text: '');
    final q = query.text.trim().toLowerCase();
    final byId = <String, List<Match>>{};
    for (final m in universe.matches) {
      if (m.tournament == null || !scope.matches(m, now)) continue;
      byId.putIfAbsent(m.tournament!.id, () => []).add(m);
    }
    final out = <TournamentActivity>[
      for (final list in byId.values)
        if (q.isEmpty || '${list.first.tournament!.name} ${list.first.venue} ${list.first.place?.city}'.toLowerCase().contains(q))
          TournamentActivity(
            id: list.first.tournament!.id,
            name: list.first.tournament!.name,
            place: list.first.place ?? SampleUniverse.placeOf('Ahmedabad'),
            venue: list.first.venue ?? '',
            start: list.map((m) => m.scheduledAt).reduce((a, b) => a.isBefore(b) ? a : b),
            end: list.map((m) => m.playedAt).reduce((a, b) => a.isAfter(b) ? a : b),
            live: list.where((m) => m.isLive).length,
            upcoming: list.where((m) => m.isUpcoming).length,
            completed: list.where((m) => m.isCompleted).length,
          ),
    ];
    // Live first, then coming up, then the most recent.
    out.sort((a, b) {
      int rank(TournamentActivity t) => t.live > 0 ? 0 : t.upcoming > 0 ? 1 : 2;
      final r = rank(a).compareTo(rank(b));
      if (r != 0) return r;
      return rank(a) == 1 ? a.start.compareTo(b.start) : b.end.compareTo(a.end);
    });
    return out;
  }

  @override
  Future<List<VenueOption>> places() async {
    await simulateLatency(latency);
    final seen = <String, VenueOption>{};
    for (final m in universe.matches) {
      if (m.venue != null && m.place != null) seen.putIfAbsent(m.venue!, () => (venue: m.venue!, place: m.place!));
    }
    return seen.values.toList()..sort((a, b) => a.venue.compareTo(b.venue));
  }

  @override
  Future<List<SearchSuggestion>> suggest(String text) async {
    await simulateLatency(latency ~/ 3);
    final q = text.toLowerCase();
    bool hit(String s) => s.toLowerCase().contains(q);
    final players = <String>{};
    final tournaments = <String, TournamentRef>{};
    final venues = <String, MatchPlace>{};
    final cities = <String, MatchPlace>{};
    final ids = <Match>[];
    for (final m in universe.matches) {
      for (final p in m.players) {
        if (p != 'You' && hit(p)) players.add(p);
      }
      if (m.tournament != null && hit(m.tournament!.name)) tournaments[m.tournament!.id] = m.tournament!;
      if (m.venue != null && m.place != null && hit(m.venue!)) venues[m.venue!] = m.place!;
      if (m.place != null && hit(m.place!.city)) cities[m.place!.city] = m.place!;
      if (hit(m.id) && q.length >= 3) ids.add(m);
    }
    return [
      for (final t in tournaments.values.take(4))
        SearchSuggestion(SuggestionKind.tournament, t.name, value: t.id, detail: 'Tournament'),
      for (final p in (players.toList()..sort()).take(4))
        SearchSuggestion(SuggestionKind.player, p, value: p, detail: universe.player(p)?.city ?? 'Player'),
      for (final e in cities.entries.take(3))
        SearchSuggestion(SuggestionKind.city, e.key, value: e.key, detail: e.value.country),
      for (final e in venues.entries.take(3))
        SearchSuggestion(SuggestionKind.venue, e.key, value: e.key, detail: e.value.city),
      for (final m in ids.take(2))
        SearchSuggestion(SuggestionKind.match, 'Match ${m.id}', value: m.id, detail: m.contextLabel),
    ];
  }
}
