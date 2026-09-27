import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/sample_latency.dart';
import '../../../core/sample_persona.dart';
import '../../auth/auth_controller.dart' show currentUserProvider;
import '../../casual_match/played_matches.dart';
import '../../casual_match/verification/verification.dart' show MatchLifecycle;
import '../../casual_match/verification/verification_controller.dart';
import '../../player/data/player_repository.dart' show PlayCategory;
import '../../rating/arc_career.dart';
import '../../rating/arc_engine.dart' show ArcImpact, Sxp;
import '../../tournaments/data/tournaments.dart';
import 'journey.dart';
import 'match.dart';
import 'sample_universe.dart';

/// One page of match history, newest first.
class MatchPage {
  const MatchPage(this.matches, {required this.hasMore});

  final List<Match> matches;
  final bool hasMore;
}

/// The player's matches. Method names mirror the endpoints they will call
/// (docs/PLAYER-APP.md §2); none exist in the new API yet.
abstract class MatchRepository {
  /// `GET /me/matches?status=live,upcoming`: soonest first.
  Future<List<Match>> active();

  /// `GET /matches/live?around=me`: every match on court now, the player's
  /// own first, then their tournaments' and clubs'.
  Future<List<Match>> liveNow();

  /// `GET /me/matches?status=completed,cancelled&before&limit`: newest first.
  Future<MatchPage> results({DateTime? before, int limit = 20});

  /// `GET /matches/:id`
  Future<Match> match(String id);

  /// `GET /me/player/record`: totals over every finished match.
  Future<PlayerRecord> record();

  /// `GET /me/player/rating-history`
  Future<List<ArcPoint>> ratingHistory();

  /// `GET /tournaments/:id/matches?category=mine`: every match in the
  /// player's category, theirs and everyone else's.
  Future<List<Match>> tournamentMatches(String tournamentId);

  /// `GET /tournaments/:id/rounds?category=mine`: the category's rounds in order.
  Future<List<TournamentRound>> rounds(String tournamentId);
}

final matchRepositoryProvider = Provider<MatchRepository>((ref) {
  if (!kDebugMode) return const EmptyMatchRepository();
  if (ref.watch(samplePersonaProvider) == SamplePersona.newcomer) return const EmptyMatchRepository();
  return SampleMatchRepository(latency: ref.watch(sampleLatencyProvider), universe: ref.watch(sampleUniverseProvider));
});

/// Live and upcoming, soonest first.
final activeMatchesProvider = FutureProvider<List<Match>>((ref) => ref.watch(matchRepositoryProvider).active());

/// Matches on court right now, the player's own first.
final liveMatchesProvider = FutureProvider<List<Match>>((ref) => ref.watch(matchRepositoryProvider).liveNow());

final matchProvider = FutureProvider.family<Match, String>((ref, id) async {
  // A casual match finished on this phone, before the API has it.
  await ref.read(playedMatchesProvider.notifier).ready;
  final local = ref.read(playedMatchesProvider).where((m) => m.id == id).firstOrNull;
  final here = local == null
      ? null
      : historyMatchOf(local, ref.read(currentUserProvider), verification: ref.watch(localLifecycleProvider(local.id)));
  return here ?? ref.watch(matchRepositoryProvider).match(id);
});

/// The player's casual matches from this phone that do not count yet:
/// waiting for confirmation, disputed, rejected or never sent. Shown under
/// Pending matches, never in stats, rating or history.
final pendingCasualMatchesProvider = Provider<List<Match>>((ref) {
  final played = ref.watch(playedMatchesProvider);
  final sync = ref.watch(casualSyncProvider);
  final user = ref.read(currentUserProvider);
  return [
    for (final local in played)
      // Matches finished before verification existed were never sent: they
      // stay off the record without being listed as waiting.
      if (sync[local.id] != null)
        if (historyMatchOf(local, user, verification: sync[local.id]!.lifecycle) case final m?
            when !m.isOfficial && m.verification != MatchLifecycle.cancelled)
          m,
  ];
});

final playerRecordProvider = FutureProvider<PlayerRecord>((ref) async {
  final played = ref.watch(playedMatchesProvider);
  final sync = ref.watch(casualSyncProvider);
  final record = await ref.watch(matchRepositoryProvider).record();
  final user = ref.read(currentUserProvider);
  final ids = {for (final m in record.finished) m.id};
  // Only casual matches every player confirmed reach the record; PlayerRecord
  // drops the rest (Match.isOfficial).
  final here = [
    for (final local in played)
      if (historyMatchOf(local, user, verification: sync[local.id]?.lifecycle ?? MatchLifecycle.draft) case final m?
          when !ids.contains(m.id) && m.isOfficial)
        m,
  ];
  return here.isEmpty ? record : PlayerRecord([...record.finished, ...here]);
});

final ratingHistoryProvider =
    FutureProvider<List<ArcPoint>>((ref) => ref.watch(matchRepositoryProvider).ratingHistory());

final tournamentMatchesProvider = FutureProvider.family<List<Match>, String>(
  (ref, id) => ref.watch(matchRepositoryProvider).tournamentMatches(id),
);

/// The player's path through one tournament, or null when they are not in it.
final journeyProvider = FutureProvider.family<TournamentJourney?, String>((ref, id) async {
  final detail = await ref.watch(tournamentDetailProvider(id).future);
  final registration = detail.myRegistration;
  if (registration == null) return null;
  final repo = ref.watch(matchRepositoryProvider);
  final (rounds, matches) = await (repo.rounds(id), repo.tournamentMatches(id)).wait;
  return buildJourney(
    category: registration.categoryName,
    partner: registration.partner,
    registeredAt: registration.registeredAt,
    rounds: rounds,
    myMatches: matches.where((m) => m.involvesMe).toList(),
  );
});

/// Match history, loaded a page at a time as the list scrolls.
final matchHistoryProvider = AsyncNotifierProvider<MatchHistory, MatchPage>(MatchHistory.new);

class MatchHistory extends AsyncNotifier<MatchPage> {
  bool _loading = false;

  @override
  Future<MatchPage> build() async {
    // Rebuilt whenever a match finishes on this phone or is verified, so it shows at once.
    ref.watch(playedMatchesProvider);
    ref.watch(casualSyncProvider);
    await ref.read(playedMatchesProvider.notifier).ready;
    final page = await ref.watch(matchRepositoryProvider).results();
    return MatchPage(_withPlayedHere(page, before: null), hasMore: page.hasMore);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || _loading) return;
    _loading = true;
    try {
      final before = current.matches.last.playedAt;
      final next = await ref.read(matchRepositoryProvider).results(before: before);
      state = AsyncData(MatchPage([...current.matches, ..._withPlayedHere(next, before: before)], hasMore: next.hasMore));
    } finally {
      _loading = false;
    }
  }

  /// [page] with the verified casual matches finished on this phone that
  /// fall in the same stretch of time, newest first. Unverified ones are
  /// under Pending matches instead.
  List<Match> _withPlayedHere(MatchPage page, {required DateTime? before}) {
    final user = ref.read(currentUserProvider);
    final sync = ref.read(casualSyncProvider);
    final oldest = page.hasMore && page.matches.isNotEmpty ? page.matches.last.playedAt : null;
    final ids = {for (final m in page.matches) m.id};
    final here = [
      for (final local in ref.read(playedMatchesProvider))
        if (historyMatchOf(local, user, verification: sync[local.id]?.lifecycle ?? MatchLifecycle.draft) case final m?)
          if (m.isOfficial &&
              !ids.contains(m.id) &&
              (before == null || m.playedAt.isBefore(before)) &&
              (oldest == null || !m.playedAt.isBefore(oldest)))
            m,
    ];
    if (here.isEmpty) return page.matches;
    return [...page.matches, ...here]..sort((a, b) => b.playedAt.compareTo(a.playedAt));
  }
}

/// Release builds until the endpoints exist, and the "new player" sample.
class EmptyMatchRepository implements MatchRepository {
  const EmptyMatchRepository();

  @override
  Future<List<Match>> active() async => const [];

  @override
  Future<List<Match>> liveNow() async => const [];

  @override
  Future<MatchPage> results({DateTime? before, int limit = 20}) async => const MatchPage([], hasMore: false);

  @override
  Future<Match> match(String id) async => throw const ApiException('NOT_FOUND', 'This match is not on SkorX.');

  @override
  Future<PlayerRecord> record() async => PlayerRecord(const []);

  @override
  Future<List<ArcPoint>> ratingHistory() async => const [];

  @override
  Future<List<Match>> tournamentMatches(String tournamentId) async => const [];

  @override
  Future<List<TournamentRound>> rounds(String tournamentId) async => const [];
}

/// Debug builds: one consistent season. Every rating change adds up to the
/// rating shown in the header, and tournament matches line up with the
/// sample tournaments' ids and dates.
class SampleMatchRepository implements MatchRepository {
  SampleMatchRepository({this.latency = const Duration(milliseconds: 350), SampleUniverse? universe}) : _universe = universe;

  final Duration latency;

  /// Every match on SkorX, so any match can be opened and any tournament's
  /// matches listed. Without it, just the player's season.
  final SampleUniverse? _universe;
  late final SampleSeason _season = _universe?.season ?? SampleSeason(DateTime.now());
  List<Match> get _all => _universe?.matches ?? _season.matches;

  List<Match> get _mine => _all.where((m) => m.involvesMe).toList();

  @override
  Future<List<Match>> active() async {
    await simulateLatency(latency);
    return _mine.where((m) => m.isLive || m.isUpcoming).toList()
      ..sort((a, b) {
        if (a.isLive != b.isLive) return a.isLive ? -1 : 1;
        return a.scheduledAt.compareTo(b.scheduledAt);
      });
  }

  @override
  Future<List<Match>> liveNow() async {
    await simulateLatency(latency);
    return _season.matches.where((m) => m.isLive).toList()
      ..sort((a, b) {
        if (a.involvesMe != b.involvesMe) return a.involvesMe ? -1 : 1;
        return (a.startedAt ?? a.scheduledAt).compareTo(b.startedAt ?? b.scheduledAt);
      });
  }

  @override
  Future<MatchPage> results({DateTime? before, int limit = 20}) async {
    await simulateLatency(latency);
    final all = _mine.where((m) => m.isCompleted || m.isCancelled).toList()
      ..sort((a, b) => b.playedAt.compareTo(a.playedAt));
    final from = before == null ? all : all.where((m) => m.playedAt.isBefore(before)).toList();
    return MatchPage(from.take(limit).toList(), hasMore: from.length > limit);
  }

  @override
  Future<Match> match(String id) async {
    await simulateLatency(latency);
    return _all.firstWhere(
      (m) => m.id == id,
      orElse: () => throw const ApiException('NOT_FOUND', 'This match is not on SkorX.'),
    );
  }

  @override
  Future<PlayerRecord> record() async {
    await simulateLatency(latency);
    return PlayerRecord(_mine);
  }

  @override
  Future<List<ArcPoint>> ratingHistory() async {
    await simulateLatency(latency);
    return ArcSummary.fromMatches(_mine)?.timeline ?? const [];
  }

  @override
  Future<List<Match>> tournamentMatches(String tournamentId) async {
    await simulateLatency(latency);
    return _all.where((m) => m.tournament?.id == tournamentId).toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  }

  @override
  Future<List<TournamentRound>> rounds(String tournamentId) async {
    await simulateLatency(latency);
    return (_universe?.rounds ?? _season.rounds)[tournamentId] ?? const [];
  }
}

/// The sample player's season, relative to [now]. Every finished match is
/// rated by the SkorX ARC engine in the order it was played, so each match's
/// SXP change, the career total and the graph always agree.
class SampleSeason {
  SampleSeason(this.now) {
    _build();
  }

  /// Career SkorX Points after the last rated match, as shown (2 decimals).
  double get currentPoints => Sxp.shown(career.sxpUnits);

  /// The replayed career: SXP, Power Index per format, every impact.
  late final ArcCareer career;

  /// Power Index of the players the sample season meets, from their sample
  /// ratings. The signed-in player starts the season at [startSpi].
  static const startSpi = 38.0;

  /// Career SkorX Points the sample player had earned before this season.
  static const startSxp = 612.40;
  static const spi = <String, double>{
    'Kamal Parmar': 44, 'Dev Patel': 36.4, 'Arjun Trivedi': 45.5, 'Anand Varsada': 46, 'Hardik Suthar': 33,
    'Om Trivedi': 34, 'Jay Desai': 38, 'Rahul Mehta': 50, 'Vivek Rana': 42, 'Kabir Rao': 43, 'Ishaan Patel': 50.7,
    'Rohan Desai': 48, 'Aarav Shah': 52, 'Karan Shah': 40, 'Nikhil Jain': 36, 'Riya Shah': 37.7, 'Nisha Joshi': 40,
    'Kavya Mehta': 49.4, 'Anaya Nair': 41.6, 'Sara Khan': 39, 'Diya Joshi': 46.8, 'Meera Iyer': 44,
  };

  final DateTime now;
  final List<Match> matches = [];
  final Map<String, List<TournamentRound>> rounds = {};

  DateTime _day(int d, int hour, [int minute = 0]) => DateTime(now.year, now.month, now.day + d, hour, minute);

  void _build() {
    final raw = <Match>[];

    Match m(
      String id,
      List<String> mine,
      List<String> theirs,
      DateTime at,
      List<(int, int)> games, {
      PlayCategory format = PlayCategory.doubles,
      MatchKind kind = MatchKind.friendly,
      TournamentRef? t,
      String? venue,
      String? court,
      bool me = true,
      int minutes = 35,
    }) =>
        Match(
          id: id,
          status: MatchStatus.completed,
          kind: kind,
          format: format,
          mine: mine,
          theirs: theirs,
          scheduledAt: at,
          startedAt: at,
          completedAt: at.add(Duration(minutes: minutes)),
          games: games,
          involvesMe: me,
          tournament: t,
          venue: venue,
          court: court,
        );

    // ── Ahmedabad Pickle League: Men's Doubles · Intermediate, on now ──
    const us = ['You', 'Kamal Parmar'];
    const devArjun = ['Dev Patel', 'Arjun Trivedi'];
    const anandHardik = ['Anand Varsada', 'Hardik Suthar'];
    const omJay = ['Om Trivedi', 'Jay Desai'];
    const rahulVivek = ['Rahul Mehta', 'Vivek Rana'];
    const kabirIshaan = ['Kabir Rao', 'Ishaan Patel'];
    const rohanAarav = ['Rohan Desai', 'Aarav Shah'];
    const karanNikhil = ['Karan Shah', 'Nikhil Jain'];
    const league = 'Ahmedabad Pickle League';
    const leagueCat = "Men's Doubles · Intermediate";
    TournamentRef lg(String round, [String? pool]) =>
        TournamentRef(id: 't-league', name: league, category: leagueCat, round: round, pool: pool);
    const club = 'CADLETE Club';

    rounds['t-league'] = [
      TournamentRound('Pool A · Match 1', startsAt: _day(-1, 9), short: 'P1'),
      TournamentRound('Pool A · Match 2', startsAt: _day(-1, 11), short: 'P2'),
      TournamentRound('Pool A · Match 3', startsAt: _day(-1, 15), short: 'P3'),
      TournamentRound('Quarter-final', knockout: true, startsAt: _day(0, 8), short: 'QF'),
      TournamentRound('Semi-final', knockout: true, startsAt: _day(0, 19, 30), short: 'SF'),
      TournamentRound('Final', knockout: true, startsAt: _day(1, 17), short: 'F'),
    ];

    raw.addAll([
      m('lg-a1', us, omJay, _day(-1, 9), const [(11, 3), (11, 5)],
          kind: MatchKind.league, t: lg('Pool A · Match 1', 'Pool A'), venue: club, court: 'Court 02', minutes: 24),
      m('lg-a2', us, anandHardik, _day(-1, 11, 30), const [(11, 9), (8, 11), (11, 7)],
          kind: MatchKind.league, t: lg('Pool A · Match 2', 'Pool A'), venue: club, court: 'Court 01', minutes: 46),
      m('lg-a3', us, devArjun, _day(-1, 15), const [(10, 12), (11, 13)],
          kind: MatchKind.league, t: lg('Pool A · Match 3', 'Pool A'), venue: club, court: 'Court 03', minutes: 38),
      m('lg-a4', devArjun, omJay, _day(-1, 9), const [(11, 5), (11, 7)],
          kind: MatchKind.league, t: lg('Pool A', 'Pool A'), venue: club, court: 'Court 01', me: false),
      m('lg-a5', anandHardik, devArjun, _day(-1, 11, 30), const [(11, 8), (6, 11), (11, 9)],
          kind: MatchKind.league, t: lg('Pool A', 'Pool A'), venue: club, court: 'Court 02', me: false),
      m('lg-a6', anandHardik, omJay, _day(-1, 15), const [(11, 4), (11, 6)],
          kind: MatchKind.league, t: lg('Pool A', 'Pool A'), venue: club, court: 'Court 04', me: false),
      m('lg-b1', rahulVivek, kabirIshaan, _day(-1, 9), const [(11, 8), (11, 9)],
          kind: MatchKind.league, t: lg('Pool B', 'Pool B'), venue: club, court: 'Court 04', me: false),
      m('lg-b2', rohanAarav, karanNikhil, _day(-1, 9), const [(11, 6), (9, 11), (11, 8)],
          kind: MatchKind.league, t: lg('Pool B', 'Pool B'), venue: club, court: 'Court 05', me: false),
      m('lg-b3', rahulVivek, rohanAarav, _day(-1, 11, 30), const [(11, 4), (11, 7)],
          kind: MatchKind.league, t: lg('Pool B', 'Pool B'), venue: club, court: 'Court 04', me: false),
      m('lg-b4', kabirIshaan, karanNikhil, _day(-1, 11, 30), const [(11, 5), (11, 9)],
          kind: MatchKind.league, t: lg('Pool B', 'Pool B'), venue: club, court: 'Court 05', me: false),
      m('lg-b5', rahulVivek, karanNikhil, _day(-1, 15), const [(11, 2), (11, 6)],
          kind: MatchKind.league, t: lg('Pool B', 'Pool B'), venue: club, court: 'Court 05', me: false),
      m('lg-b6', kabirIshaan, rohanAarav, _day(-1, 15), const [(12, 10), (11, 8)],
          kind: MatchKind.league, t: lg('Pool B', 'Pool B'), venue: club, court: 'Court 01', me: false),
    ]);

    final qfStart = now.subtract(const Duration(minutes: 24));
    raw.add(Match(
      id: 'lg-qf1',
      status: MatchStatus.live,
      kind: MatchKind.league,
      format: PlayCategory.doubles,
      mine: us,
      theirs: rahulVivek,
      scheduledAt: qfStart,
      startedAt: qfStart,
      games: const [(11, 7)],
      live: const LiveGame(number: 2, mine: 8, theirs: 6, myServe: true),
      tournament: lg('Quarter-final'),
      venue: club,
      court: 'Court 03',
      // Any public YouTube video stands in for the club's live stream.
      broadcast: const LiveBroadcast(videoId: sampleBroadcastVideoId, title: 'Quarter-final · Court 03', channel: 'SkorX Live'),
    ));
    // The other quarter-finals on court at the same time.
    Match liveQf(String id, List<String> a, List<String> b, int startedMinsAgo, List<(int, int)> games, LiveGame live, String court) {
      final at = now.subtract(Duration(minutes: startedMinsAgo));
      return Match(
        id: id,
        status: MatchStatus.live,
        kind: MatchKind.league,
        format: PlayCategory.doubles,
        mine: a,
        theirs: b,
        involvesMe: false,
        scheduledAt: at,
        startedAt: at,
        games: games,
        live: live,
        tournament: lg('Quarter-final'),
        venue: club,
        court: court,
      );
    }

    raw.addAll([
      liveQf('lg-qf3', anandHardik, rohanAarav, 31, const [(9, 11), (11, 6)],
          const LiveGame(number: 3, mine: 5, theirs: 5, myServe: false), 'Court 02'),
      liveQf('lg-qf4', omJay, karanNikhil, 12, const [], const LiveGame(number: 1, mine: 9, theirs: 4, myServe: true), 'Court 04'),
    ]);
    final friendlyStart = now.subtract(const Duration(minutes: 18));
    raw.add(Match(
      id: 'fr-live',
      status: MatchStatus.live,
      kind: MatchKind.friendly,
      format: PlayCategory.singles,
      mine: const ['Meera Iyer'],
      theirs: const ['Nisha Joshi'],
      involvesMe: false,
      scheduledAt: friendlyStart,
      startedAt: friendlyStart,
      games: const [(11, 8)],
      live: const LiveGame(number: 2, mine: 3, theirs: 7, myServe: false),
      venue: 'Riverside Courts',
      court: 'Court 01',
    ));

    // Tonight if there is time, otherwise tomorrow morning.
    final laterToday = now.hour < 18 ? _day(0, 19, 30) : _day(1, 10);
    raw.addAll([
      Match(
        id: 'lg-qf2',
        status: MatchStatus.upcoming,
        kind: MatchKind.league,
        format: PlayCategory.doubles,
        mine: devArjun,
        theirs: kabirIshaan,
        involvesMe: false,
        scheduledAt: now.add(const Duration(minutes: 40)),
        tournament: lg('Quarter-final'),
        venue: club,
        court: 'Court 01',
      ),
      Match(
        id: 'lg-sf1',
        status: MatchStatus.upcoming,
        kind: MatchKind.league,
        format: PlayCategory.doubles,
        mine: us,
        theirs: const [],
        theirsPlaceholder: 'Winner of QF 2',
        scheduledAt: laterToday,
        tournament: lg('Semi-final'),
        venue: club,
        court: 'Court 01',
      ),
    ]);

    // ── Friendly singles, booked court ──
    raw.add(Match(
      id: 'fr-up',
      status: MatchStatus.upcoming,
      kind: MatchKind.friendly,
      format: PlayCategory.singles,
      mine: const ['You'],
      theirs: const ['Vivek Rana'],
      scheduledAt: _day(4, 7),
      venue: 'Pickle Blitz Arena',
      court: 'Court 02',
    ));

    // ── CADLETE Monsoon Cup: Mixed Doubles · Open, runner-up ──
    const usMixed = ['You', 'Riya Shah'];
    const devNisha = ['Dev Patel', 'Nisha Joshi'];
    const arjunKavya = ['Arjun Trivedi', 'Kavya Mehta'];
    const monsoon = 'CADLETE Monsoon Cup';
    const monsoonCat = 'Mixed Doubles · Open';
    TournamentRef mo(String round, [String? pool]) =>
        TournamentRef(id: 't-monsoon', name: monsoon, category: monsoonCat, round: round, pool: pool);
    rounds['t-monsoon'] = [
      TournamentRound('Group B · Match 1', startsAt: _day(-27, 9), short: 'G1'),
      TournamentRound('Group B · Match 2', startsAt: _day(-27, 12), short: 'G2'),
      TournamentRound('Quarter-final', knockout: true, startsAt: _day(-26, 10), short: 'QF'),
      TournamentRound('Semi-final', knockout: true, startsAt: _day(-26, 16), short: 'SF'),
      TournamentRound('Final', knockout: true, startsAt: _day(-25, 17), short: 'F'),
    ];
    const mixed = PlayCategory.mixed;
    const tour = MatchKind.tournament;
    raw.addAll([
      m('mo-g1', usMixed, devNisha, _day(-27, 9), const [(5, 11), (10, 12)],
          format: mixed, kind: tour, t: mo('Group B · Match 1', 'Group B'), venue: club, court: 'Court 02', minutes: 30),
      m('mo-g2', usMixed, arjunKavya, _day(-27, 12), const [(11, 4), (11, 6)],
          format: mixed, kind: tour, t: mo('Group B · Match 2', 'Group B'), venue: club, court: 'Court 01', minutes: 22),
      m('mo-g3', devNisha, arjunKavya, _day(-27, 15), const [(11, 7), (11, 9)],
          format: mixed, kind: tour, t: mo('Group B', 'Group B'), venue: club, court: 'Court 03', me: false),
      m('mo-qf', usMixed, const ['Rohan Desai', 'Anaya Nair'], _day(-26, 10), const [(11, 6), (11, 8)],
          format: mixed, kind: tour, t: mo('Quarter-final'), venue: club, court: 'Court 01', minutes: 33),
      m('mo-sf', usMixed, const ['Anand Varsada', 'Sara Khan'], _day(-26, 16), const [(13, 11), (11, 6)],
          format: mixed, kind: tour, t: mo('Semi-final'), venue: club, court: 'Court 01', minutes: 41),
      m('mo-f', usMixed, const ['Kabir Rao', 'Diya Joshi'], _day(-25, 17), const [(9, 11), (11, 8), (7, 11)],
          format: mixed, kind: tour, t: mo('Final'), venue: club, court: 'Centre Court', minutes: 58),
    ]);

    // ── SkorX Open 2026: registered, draw not out yet ──
    rounds['t-open'] = [
      TournamentRound('Group stage', startsAt: _day(9, 8), short: 'GS'),
      TournamentRound('Round of 16', knockout: true, startsAt: _day(10, 8), short: 'R16'),
      TournamentRound('Quarter-final', knockout: true, startsAt: _day(10, 14), short: 'QF'),
      TournamentRound('Semi-final', knockout: true, startsAt: _day(11, 16), short: 'SF'),
      TournamentRound('Final', knockout: true, startsAt: _day(11, 19), short: 'F'),
    ];

    // ── Friendlies ──
    const singles = PlayCategory.singles;
    raw.addAll([
      m('fr-1', const ['You'], const ['Dev Patel'], _day(-3, 7), const [(11, 5), (11, 8)],
          format: singles, venue: 'Riverside Courts', court: 'Court 01', minutes: 29),
      m('fr-2', us, const ['Rahul Mehta', 'Jay Desai'], _day(-8, 19), const [(8, 11), (11, 9), (7, 11)],
          venue: 'Pickle Blitz Arena', court: 'Court 04', minutes: 55),
      m('fr-3', us, anandHardik, _day(-12, 18), const [(7, 11), (11, 9), (8, 11)],
          venue: 'Smash Arena', court: 'Court 02', minutes: 49),
      m('fr-4', const ['You'], const ['Hardik Suthar'], _day(-16, 7), const [(11, 4), (11, 9)],
          format: singles, venue: 'Riverside Courts', court: 'Court 03', minutes: 26),
      m('fr-5', const ['You'], const ['Vivek Rana'], _day(-22, 6), const [(11, 9), (11, 7)],
          format: singles, venue: 'Pickle Blitz Arena', court: 'Court 02', minutes: 31),
      m('fr-6', us, omJay, _day(-33, 19), const [(11, 3), (11, 6)],
          venue: 'Smash Arena', court: 'Court 05', minutes: 24),
      m('fr-7', const ['You'], const ['Dev Patel'], _day(-40, 7), const [(9, 11), (11, 13)],
          format: singles, venue: 'Riverside Courts', court: 'Court 01', minutes: 35),
    ]);
    raw.add(Match(
      id: 'fr-x',
      status: MatchStatus.cancelled,
      kind: MatchKind.friendly,
      format: PlayCategory.doubles,
      mine: us,
      theirs: const ['Rahul Mehta', 'Jay Desai'],
      scheduledAt: _day(-2, 18),
      venue: 'Riverside Courts',
      court: 'Court 02',
      cancelReason: 'Rain: outdoor courts closed',
    ));

    // An older history long enough to page through.
    const rivals = [
      ['Jay Desai', 'Om Trivedi'],
      ['Nisha Joshi'],
      ['Hardik Suthar', 'Anand Varsada'],
      ['Rohan Desai', 'Karan Shah'],
      ['Meera Iyer'],
      ['Ishaan Patel', 'Kabir Rao'],
    ];
    const venues = ['Riverside Courts', 'Smash Arena', 'Pickle Blitz Arena', 'CADLETE Club'];
    for (var i = 0; i < 26; i++) {
      final opp = rivals[i % rivals.length];
      final won = (i * 7) % 5 != 0;
      final a = 11;
      final b = 3 + (i * 5) % 8;
      final isSingles = opp.length == 1;
      raw.add(m(
        'old-$i',
        isSingles ? const ['You'] : us,
        opp,
        _day(-46 - i * 6, 7 + (i % 3) * 5),
        won ? [(a, b), (a, b + 1)] : [(b, a), (a, b), (b + 1, a)],
        format: isSingles ? singles : PlayCategory.doubles,
        venue: venues[i % venues.length],
        court: 'Court 0${1 + i % 4}',
        minutes: 25 + i % 20,
      ));
    }

    // Rating: replay the season through the ARC engine, oldest first.
    // pointsBefore/pointsEarned are the SXP rounded to 2 decimals, so the
    // changes add up exactly to the header number.
    final rated = raw.where((x) => x.involvesMe && x.isCompleted).toList()
      ..sort((a, b) => a.playedAt.compareTo(b.playedAt));
    career = ArcCareer(spiOf: (name) => spi[name] ?? 40, startSpi: startSpi, startSxpUnits: Sxp.unitsOf(startSxp));
    final before = <String, double>{};
    final impact = <String, ArcImpact>{};
    for (final x in rated) {
      before[x.id] = Sxp.shown(career.sxpUnits);
      impact[x.id] = career.add(x);
    }
    matches.addAll([
      for (final x in raw)
        before.containsKey(x.id)
            ? Match(
                id: x.id,
                status: x.status,
                kind: x.kind,
                format: x.format,
                mine: x.mine,
                theirs: x.theirs,
                scheduledAt: x.scheduledAt,
                games: x.games,
                involvesMe: x.involvesMe,
                tournament: x.tournament,
                venue: x.venue,
                court: x.court,
                startedAt: x.startedAt,
                completedAt: x.completedAt,
                pointsBefore: before[x.id],
                pointsEarned: impact[x.id]!.shownGain,
                arc: impact[x.id],
              )
            : x,
    ]);
  }
}

/// The video sample matches stream: YouTube's first upload, which will not
/// go away. Swap in a real broadcast's id to try a live stream.
const sampleBroadcastVideoId = 'jNQXAC9IVRw';
