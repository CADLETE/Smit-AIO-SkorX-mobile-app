import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sample_latency.dart';
import '../../matches/data/match.dart';
import '../../matches/data/match_repository.dart' show MatchPage;
import '../../matches/data/sample_universe.dart';
import '../../player/data/player_stats.dart' show WinLoss;
import '../../tournaments/data/tournaments.dart';

/// A tournament the signed-in player entered or played in, and how it went.
class MyTournamentPlay {
  const MyTournamentPlay({required this.tournament, required this.played, required this.wins, this.registration, this.lastMatch});

  final Tournament tournament;
  final Registration? registration;
  final int played;
  final int wins;

  /// Their latest finished match in it.
  final Match? lastMatch;

  int get losses => played - wins;
}

/// The signed-in player's own play, for My Paddle.
///
/// "Mine" means the player was on court: never matches they watched,
/// searched for, or that happened in their city or tournament without them.
/// The server decides that from the signed-in account on every call; the
/// app never filters someone else's matches out on the phone.
abstract class MyPlayRepository {
  /// `GET /me/matches?category=casual|tournament&status=completed&before&limit`:
  /// newest first.
  Future<MatchPage> myMatches(MatchCategory category, {DateTime? before, int limit = 20});

  /// `GET /me/matches/summary?category=`: wins and losses over every
  /// finished match in [category].
  Future<WinLoss> summary(MatchCategory category);

  /// `GET /me/tournaments?include=played`: tournaments entered or played,
  /// the latest first, with the player's record in each.
  Future<List<MyTournamentPlay>> tournaments();

  /// `GET /me/tournaments/:id/matches`: only the player's own matches in
  /// the tournament, in playing order.
  Future<List<Match>> tournamentMatches(String tournamentId);
}

final myPlayRepositoryProvider = Provider<MyPlayRepository>((ref) {
  if (!kDebugMode) return const EmptyMyPlayRepository();
  return SampleMyPlayRepository(
    ref.watch(sampleUniverseProvider),
    tournaments: ref.watch(tournamentRepositoryProvider),
    latency: ref.watch(sampleLatencyProvider),
  );
});

final myPlaySummaryProvider = FutureProvider.family<WinLoss, MatchCategory>(
  (ref, category) => ref.watch(myPlayRepositoryProvider).summary(category),
);

final myPlayedTournamentsProvider =
    FutureProvider<List<MyTournamentPlay>>((ref) => ref.watch(myPlayRepositoryProvider).tournaments());

final myTournamentMatchesProvider = FutureProvider.family<List<Match>, String>(
  (ref, id) => ref.watch(myPlayRepositoryProvider).tournamentMatches(id),
);

/// The player's casual or tournament matches, a page at a time.
final myMatchesProvider = AsyncNotifierProvider.family<MyMatches, MatchPage, MatchCategory>(MyMatches.new);

class MyMatches extends AsyncNotifier<MatchPage> {
  MyMatches(this.category);

  final MatchCategory category;
  bool _loading = false;

  @override
  Future<MatchPage> build() => ref.watch(myPlayRepositoryProvider).myMatches(category);

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || _loading) return;
    _loading = true;
    try {
      final next =
          await ref.read(myPlayRepositoryProvider).myMatches(category, before: current.matches.last.playedAt);
      state = AsyncData(MatchPage([...current.matches, ...next.matches], hasMore: next.hasMore));
    } finally {
      _loading = false;
    }
  }
}

/// Release builds until the endpoints exist: honest empty states.
class EmptyMyPlayRepository implements MyPlayRepository {
  const EmptyMyPlayRepository();

  @override
  Future<MatchPage> myMatches(MatchCategory category, {DateTime? before, int limit = 20}) async =>
      const MatchPage([], hasMore: false);

  @override
  Future<WinLoss> summary(MatchCategory category) async => WinLoss(category.label, played: 0, wins: 0);

  @override
  Future<List<MyTournamentPlay>> tournaments() async => const [];

  @override
  Future<List<Match>> tournamentMatches(String tournamentId) async => const [];
}

/// Debug builds: the sample universe, where [Match.involvesMe] stands for the
/// server's participant check.
class SampleMyPlayRepository implements MyPlayRepository {
  SampleMyPlayRepository(this.universe, {required TournamentRepository tournaments, this.latency = const Duration(milliseconds: 350)})
      : _tournaments = tournaments;

  final SampleUniverse universe;
  final TournamentRepository _tournaments;
  final Duration latency;

  Iterable<Match> get _mine => universe.matches.where((m) => m.involvesMe && !m.isCancelled);

  List<Match> _finished(MatchCategory category) =>
      _mine.where((m) => m.isCompleted && m.category == category).toList()..sort((a, b) => b.playedAt.compareTo(a.playedAt));

  @override
  Future<MatchPage> myMatches(MatchCategory category, {DateTime? before, int limit = 20}) async {
    await simulateLatency(latency);
    final all = _finished(category).where((m) => before == null || m.playedAt.isBefore(before)).toList();
    return MatchPage(all.take(limit).toList(), hasMore: all.length > limit);
  }

  @override
  Future<WinLoss> summary(MatchCategory category) async {
    await simulateLatency(latency);
    final all = _finished(category);
    return WinLoss(category.label, played: all.length, wins: all.where((m) => m.won).length);
  }

  @override
  Future<List<MyTournamentPlay>> tournaments() async {
    final (registrations, known) = await (_tournaments.mine(), _tournaments.discover()).wait;
    final byId = {for (final t in known) t.id: t};
    final ids = <String>{
      for (final r in registrations) r.tournament.id,
      for (final m in _mine) ?m.tournament?.id,
    };
    final out = <MyTournamentPlay>[];
    for (final id in ids) {
      final t = byId[id];
      if (t == null) continue;
      final finished = _mine.where((m) => m.tournament?.id == id && m.isCompleted).toList()
        ..sort((a, b) => b.playedAt.compareTo(a.playedAt));
      out.add(MyTournamentPlay(
        tournament: t,
        registration: registrations.where((r) => r.tournament.id == id).firstOrNull?.registration,
        played: finished.length,
        wins: finished.where((m) => m.won).length,
        lastMatch: finished.firstOrNull,
      ));
    }
    final now = DateTime.now();
    // On now first, then coming up, then the most recent.
    int rank(MyTournamentPlay p) => switch (p.tournament.phase(now)) {
          TournamentPhase.live => 0,
          TournamentPhase.upcoming => 1,
          TournamentPhase.completed => 2,
        };
    return out
      ..sort((a, b) {
        final r = rank(a).compareTo(rank(b));
        if (r != 0) return r;
        return rank(a) == 1 ? a.tournament.start.compareTo(b.tournament.start) : b.tournament.start.compareTo(a.tournament.start);
      });
  }

  @override
  Future<List<Match>> tournamentMatches(String tournamentId) async {
    await simulateLatency(latency);
    return _mine.where((m) => m.tournament?.id == tournamentId).toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  }
}
