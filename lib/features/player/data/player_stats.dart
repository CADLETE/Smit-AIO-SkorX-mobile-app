import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sample_latency.dart';
import '../../auth/auth_controller.dart';
import '../../matches/data/match.dart';
import '../../matches/data/match_repository.dart' show MatchPage;
import '../../matches/data/sample_universe.dart';
import 'player_repository.dart' show PlayCategory;

/// Who a player is: enough to recognise them in the Quick View.
class PlayerProfile {
  const PlayerProfile({
    required this.id,
    required this.name,
    this.city,
    this.region,
    this.country,
    this.level,
    this.points,
    this.isMe = false,
  });

  /// "SKX-10021"; `me` for the signed-in player. A player SkorX only knows
  /// by name (a guest on a casual match) keeps their name as the id.
  final String id;
  final String name;
  final String? city;
  final String? region;
  final String? country;

  /// "Intermediate".
  final String? level;

  /// SkorX Points (the rating); null until they have rated matches.
  final int? points;
  final bool isMe;

  /// Whether this is a registered SkorX player, with a public id.
  bool get hasPublicId => id.startsWith('SKX-');

  /// "Ahmedabad, Gujarat".
  String? get placeLabel {
    if (city == null) return country;
    return [city!, if (region != null && region != city) region!].join(', ');
  }

  /// How a match names this player: "You" for the signed-in player.
  String get matchName => isMe ? 'You' : name;
}

/// Wins and losses in one slice of a record: a format, casual, tournament.
class WinLoss {
  const WinLoss(this.label, {required this.played, required this.wins});

  final String label;
  final int played;
  final int wins;

  int get losses => played - wins;

  /// 0–100, or null before the first match.
  int? get winRate => played == 0 ? null : (wins * 100 / played).round();
}

/// A player's run in one tournament.
class TournamentRun {
  const TournamentRun({
    required this.id,
    required this.name,
    required this.played,
    required this.wins,
    required this.lastRound,
    required this.lastWon,
    required this.lastPlayed,
  });

  final String id;
  final String name;
  final int played;
  final int wins;
  final String lastRound;
  final bool lastWon;
  final DateTime lastPlayed;

  int get losses => played - wins;

  /// "Champion", "Runner-up", "Lost in the semi-final", "Won the quarter-final".
  String get result {
    final round = lastRound.toLowerCase();
    if (lastRound == 'Final') return lastWon ? 'Champion' : 'Runner-up';
    return lastWon ? 'Won the $round' : 'Lost in the $round';
  }
}

/// What a player's finished matches add up to. Worked out from matches and
/// nothing else, on the server for real players; [PlayerStats.from] is the
/// same sum, used by the sample data and the tests.
class PlayerStats {
  const PlayerStats({
    required this.career,
    required this.formats,
    required this.casual,
    required this.tournament,
    required this.form,
    required this.streak,
    required this.bestWinStreak,
    required this.tournaments,
  });

  factory PlayerStats.from(String name, Iterable<Match> matches) {
    final finished = [
      for (final m in matches)
        if (m.isCompleted) ?m.seenBy(name),
    ]..sort((a, b) => b.playedAt.compareTo(a.playedAt));

    WinLoss slice(String label, bool Function(Match) test) {
      final list = finished.where(test).toList();
      return WinLoss(label, played: list.length, wins: list.where((m) => m.won).length);
    }

    var streak = 0;
    for (final m in finished) {
      if (streak == 0) {
        streak = m.won ? 1 : -1;
      } else if (m.won == streak > 0) {
        streak += streak > 0 ? 1 : -1;
      } else {
        break;
      }
    }
    var best = 0, run = 0;
    for (final m in finished.reversed) {
      run = m.won ? run + 1 : 0;
      if (run > best) best = run;
    }

    final byTournament = <String, List<Match>>{};
    for (final m in finished) {
      if (m.tournament != null) byTournament.putIfAbsent(m.tournament!.id, () => []).add(m);
    }

    return PlayerStats(
      career: slice('Career', (_) => true),
      formats: [
        for (final f in PlayCategory.values)
          if (finished.any((m) => m.format == f)) slice(f.label, (m) => m.format == f),
      ],
      casual: slice(MatchCategory.casual.label, (m) => m.category == MatchCategory.casual),
      tournament: slice(MatchCategory.tournament.label, (m) => m.category == MatchCategory.tournament),
      form: [for (final m in finished.take(10)) m.won],
      streak: streak,
      bestWinStreak: best,
      tournaments: [
        for (final list in byTournament.values)
          TournamentRun(
            id: list.first.tournament!.id,
            name: list.first.tournament!.name,
            played: list.length,
            wins: list.where((m) => m.won).length,
            lastRound: list.first.tournament!.round,
            lastWon: list.first.won,
            lastPlayed: list.first.playedAt,
          ),
      ],
    );
  }

  static const empty = PlayerStats(
    career: WinLoss('Career', played: 0, wins: 0),
    formats: [],
    casual: WinLoss('Casual', played: 0, wins: 0),
    tournament: WinLoss('Tournament', played: 0, wins: 0),
    form: [],
    streak: 0,
    bestWinStreak: 0,
    tournaments: [],
  );

  final WinLoss career;

  /// Only the formats they have played, singles first.
  final List<WinLoss> formats;
  final WinLoss casual;
  final WinLoss tournament;

  /// Up to the last 10 results, newest first: true for a win.
  final List<bool> form;

  /// The current run: 3 for three wins in a row, −2 for two losses, 0 before
  /// the first match.
  final int streak;
  final int bestWinStreak;

  /// Tournaments played, most recent first.
  final List<TournamentRun> tournaments;

  /// Win % over the last [n] matches, or over all of them when there are
  /// fewer; null before the first match.
  int? winRateOfLast(int n) {
    final recent = form.take(n).toList();
    if (recent.isEmpty) return null;
    return (recent.where((w) => w).length * 100 / recent.length).round();
  }

  /// "W3" / "L2".
  String? get streakLabel => streak == 0 ? null : '${streak > 0 ? 'W' : 'L'}${streak.abs()}';
}

/// Someone a player keeps meeting across the net.
class Rival {
  const Rival({required this.player, required this.record, required this.last});

  final PlayerProfile player;

  /// From the player's side: their wins against this rival.
  final WinLoss record;

  /// The latest meeting, from the player's side.
  final Match last;
}

/// Everything two players have played against each other.
class HeadToHead {
  const HeadToHead({required this.a, required this.b, required this.meetings});

  final PlayerProfile a;
  final PlayerProfile b;

  /// Finished matches between them, newest first, from [a]'s side.
  final List<Match> meetings;

  int get played => meetings.length;
  int get aWins => meetings.where((m) => m.won).length;
  int get bWins => played - aWins;
  Match? get last => meetings.firstOrNull;

  /// [a]'s win %, null before they have met.
  int? get aWinRate => played == 0 ? null : (aWins * 100 / played).round();
}

/// Any player's profile and performance. Method names mirror the endpoints
/// they will call; none exist in the new API yet (docs/PLAYER-APP.md §6).
abstract class PlayerStatsRepository {
  /// `GET /players/:id`, or `GET /players/lookup?name=` for a name from a
  /// match. `me` (or "You") is the signed-in player.
  Future<PlayerProfile> profile(String idOrName);

  /// `GET /players/:id/stats`: career, formats, casual and tournament splits,
  /// form, streaks and tournament runs, summed on the server and cached there.
  Future<PlayerStats> stats(String id);

  /// `GET /players/:id/matches?before&limit`: finished matches, newest first,
  /// each from the player's side.
  Future<MatchPage> matches(String id, {DateTime? before, int limit = 20});

  /// `GET /players/:id/rivals?limit`: the opponents they have met most.
  Future<List<Rival>> rivals(String id, {int limit = 8});

  /// `GET /players/:id/head-to-head/:otherId`
  Future<HeadToHead> headToHead(String id, String otherId);
}

final playerStatsRepositoryProvider = Provider<PlayerStatsRepository>((ref) {
  if (!kDebugMode) return const EmptyPlayerStatsRepository();
  return SamplePlayerStatsRepository(
    ref.watch(sampleUniverseProvider),
    myName: ref.watch(currentUserProvider.select((u) => u?.name)) ?? '',
    latency: ref.watch(sampleLatencyProvider),
  );
});

// Profiles and stats are kept for the session once loaded (not auto
// disposed), so reopening a player is instant; pull to refresh reloads.

final playerProfileProvider = FutureProvider.family<PlayerProfile, String>(
  (ref, idOrName) => ref.watch(playerStatsRepositoryProvider).profile(idOrName),
);

final playerStatsProvider =
    FutureProvider.family<PlayerStats, String>((ref, id) => ref.watch(playerStatsRepositoryProvider).stats(id));

/// Profile then stats, for the Quick View, which starts from a name on a match.
final playerCardProvider = FutureProvider.family<(PlayerProfile, PlayerStats), String>((ref, idOrName) async {
  final profile = await ref.watch(playerProfileProvider(idOrName).future);
  final stats = await ref.watch(playerStatsProvider(profile.id).future);
  return (profile, stats);
});

final playerRivalsProvider =
    FutureProvider.family<List<Rival>, String>((ref, id) => ref.watch(playerStatsRepositoryProvider).rivals(id));

final headToHeadProvider = FutureProvider.family<HeadToHead, (String, String)>(
  (ref, ids) => ref.watch(playerStatsRepositoryProvider).headToHead(ids.$1, ids.$2),
);

/// A player's match history, a page at a time.
final playerMatchesProvider =
    AsyncNotifierProvider.family<PlayerMatches, MatchPage, String>(PlayerMatches.new);

class PlayerMatches extends AsyncNotifier<MatchPage> {
  PlayerMatches(this.playerId);

  final String playerId;
  bool _loading = false;

  @override
  Future<MatchPage> build() => ref.watch(playerStatsRepositoryProvider).matches(playerId, limit: 10);

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || _loading) return;
    _loading = true;
    try {
      final next = await ref
          .read(playerStatsRepositoryProvider)
          .matches(playerId, before: current.matches.last.playedAt, limit: 10);
      state = AsyncData(MatchPage([...current.matches, ...next.matches], hasMore: next.hasMore));
    } finally {
      _loading = false;
    }
  }
}

/// Release builds until the endpoints exist: honest empty states.
class EmptyPlayerStatsRepository implements PlayerStatsRepository {
  const EmptyPlayerStatsRepository();

  @override
  Future<PlayerProfile> profile(String idOrName) async => PlayerProfile(
        id: idOrName,
        name: idOrName == 'me' || idOrName == 'You' ? 'You' : idOrName,
        isMe: idOrName == 'me' || idOrName == 'You',
      );

  @override
  Future<PlayerStats> stats(String id) async => PlayerStats.empty;

  @override
  Future<MatchPage> matches(String id, {DateTime? before, int limit = 20}) async => const MatchPage([], hasMore: false);

  @override
  Future<List<Rival>> rivals(String id, {int limit = 8}) async => const [];

  @override
  Future<HeadToHead> headToHead(String id, String otherId) async =>
      HeadToHead(a: await profile(id), b: await profile(otherId), meetings: const []);
}

/// Debug builds: every player in the sample universe, their numbers summed
/// from the universe's matches exactly as the server will.
class SamplePlayerStatsRepository implements PlayerStatsRepository {
  SamplePlayerStatsRepository(this.universe, {this.myName = '', this.latency = const Duration(milliseconds: 350)});

  final SampleUniverse universe;

  /// The signed-in player's name, which older matches may use instead of "You".
  final String myName;
  final Duration latency;

  bool _isMe(String key) => key == 'me' || key == 'You' || (myName.isNotEmpty && key == myName);

  /// The name the player has on matches.
  String _matchName(String id) => _isMe(id) ? 'You' : universe.player(id)?.name ?? id;

  PlayerProfile _profile(String idOrName) {
    if (_isMe(idOrName)) {
      final played = universe.includeMe && universe.matches.any((m) => m.involvesMe && m.isCompleted);
      final place = SampleUniverse.placeOf('Ahmedabad');
      return PlayerProfile(
        id: 'me',
        name: myName.isEmpty ? 'You' : myName,
        city: place.city,
        region: place.region,
        country: place.country,
        level: played ? 'Intermediate' : 'New player',
        points: played ? universe.season.currentRating : null,
        isMe: true,
      );
    }
    final p = universe.player(idOrName);
    if (p == null) return PlayerProfile(id: idOrName, name: idOrName);
    final place = SampleUniverse.placeOf(p.city);
    return PlayerProfile(
      id: p.id,
      name: p.name,
      city: place.city,
      region: place.region,
      country: place.country,
      level: p.level,
      points: p.points,
    );
  }

  @override
  Future<PlayerProfile> profile(String idOrName) async {
    await simulateLatency(latency);
    return _profile(idOrName);
  }

  @override
  Future<PlayerStats> stats(String id) async {
    await simulateLatency(latency);
    return PlayerStats.from(_matchName(id), universe.matches);
  }

  @override
  Future<MatchPage> matches(String id, {DateTime? before, int limit = 20}) async {
    await simulateLatency(latency);
    final name = _matchName(id);
    final all = [
      for (final m in universe.matches)
        if (m.isCompleted && (before == null || m.playedAt.isBefore(before))) ?m.seenBy(name),
    ]..sort((a, b) => b.playedAt.compareTo(a.playedAt));
    return MatchPage(all.take(limit).toList(), hasMore: all.length > limit);
  }

  @override
  Future<List<Rival>> rivals(String id, {int limit = 8}) async {
    await simulateLatency(latency);
    final name = _matchName(id);
    final meetings = <String, List<Match>>{};
    for (final m in universe.matches) {
      if (!m.isCompleted) continue;
      final seen = m.seenBy(name);
      if (seen == null) continue;
      for (final opponent in seen.theirs) {
        meetings.putIfAbsent(opponent, () => []).add(seen);
      }
    }
    final ranked = meetings.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.length.compareTo(a.value.length);
        if (byCount != 0) return byCount;
        return _latest(b.value).playedAt.compareTo(_latest(a.value).playedAt);
      });
    return [
      for (final e in ranked.take(limit))
        Rival(
          player: _profile(e.key),
          record: WinLoss(e.key, played: e.value.length, wins: e.value.where((m) => m.won).length),
          last: _latest(e.value),
        ),
    ];
  }

  static Match _latest(List<Match> list) => list.reduce((a, b) => a.playedAt.isAfter(b.playedAt) ? a : b);

  @override
  Future<HeadToHead> headToHead(String id, String otherId) async {
    await simulateLatency(latency);
    final a = _matchName(id), b = _matchName(otherId);
    final meetings = [
      for (final m in universe.matches)
        if (m.isCompleted && m.hasPlayer(b)) ?m.seenBy(a),
    ].where((m) => m.theirs.contains(b)).toList()
      ..sort((x, y) => y.playedAt.compareTo(x.playedAt));
    return HeadToHead(a: _profile(id), b: _profile(otherId), meetings: meetings);
  }
}
