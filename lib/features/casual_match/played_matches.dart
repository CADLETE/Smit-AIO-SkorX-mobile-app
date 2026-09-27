import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sports/core/score_state.dart';
import '../auth/data/current_user.dart';
import '../matches/data/match.dart';
import '../player/data/player_repository.dart' show PlayCategory;
import 'data/match_setup.dart';
import 'local_match.dart';
import 'offline/match_store.dart';
import 'offline/sync_engine.dart';
import 'verification/verification.dart';

final playedMatchesProvider = NotifierProvider<PlayedMatchesController, List<LocalMatch>>(PlayedMatchesController.new);

/// Casual matches finished on this phone, newest first. Kept after the
/// scoring screen closes so they show in the player's results, and each is
/// its own document in the [MatchStore], so one damaged file never costs
/// the others. A match SkorX does not have yet is never dropped.
class PlayedMatchesController extends Notifier<List<LocalMatch>> {
  /// Synced matches beyond this many are dropped from the phone; SkorX keeps them.
  static const _keep = 200;

  /// Resolves once the saved matches have been read.
  late final Future<void> ready;

  @override
  List<LocalMatch> build() {
    ready = _restore();
    return const [];
  }

  MatchStore get _store => ref.read(matchStoreProvider);

  Future<void> _restore() async {
    final matches = await _store.readPlayed();
    if (!ref.mounted) return;
    state = matches..sort((a, b) => _endOf(b).compareTo(_endOf(a)));
  }

  /// Adds [match], or updates it when it is already recorded.
  Future<void> record(LocalMatch match) async {
    await ready;
    await _store.writePlayed(match);
    if (!ref.mounted) return;
    final all = [match, ...state.where((m) => m.id != match.id)]..sort((a, b) => _endOf(b).compareTo(_endOf(a)));
    state = await _trim(all);
  }

  /// Forgets [id], for a match reopened by undoing its last point.
  Future<void> remove(String id) async {
    await ready;
    if (!state.any((m) => m.id == id)) return;
    await _store.removePlayed(id);
    if (ref.mounted) state = state.where((m) => m.id != id).toList();
  }

  /// Keeps the newest [_keep], plus every older match SkorX does not have yet.
  Future<List<LocalMatch>> _trim(List<LocalMatch> all) async {
    if (all.length <= _keep) return all;
    final ledger = ref.read(casualSyncProvider);
    final kept = <LocalMatch>[];
    for (final (i, m) in all.indexed) {
      final s = ledger[m.id];
      final onSkorx = s == null || s.phase == SyncPhase.synced;
      if (i < _keep || !onSkorx) {
        kept.add(m);
      } else {
        await _store.removePlayed(m.id);
      }
    }
    return kept;
  }

  static DateTime _endOf(LocalMatch m) => m.finishedAt ?? m.startedAt;
}

/// [match] as a result in the signed-in player's history, from their side of
/// the net. Null when they did not play in it. [verification] is where its
/// players' confirmation stands: only a verified match counts toward stats.
Match? historyMatchOf(LocalMatch match, CurrentUser? user, {MatchLifecycle verification = MatchLifecycle.draft}) {
  final names = {'You', if (user != null && user.name.trim().isNotEmpty) user.name.trim()};
  final Side me;
  if (match.sideA.any(names.contains)) {
    me = Side.a;
  } else if (match.sideB.any(names.contains)) {
    me = Side.b;
  } else {
    return null;
  }
  List<String> side(Side s) => [for (final n in match.names(s)) names.contains(n) ? 'You' : n];
  // The player first, as every match row expects.
  final mine = ['You', ...side(me).where((n) => n != 'You')];
  final score = match.score;
  final games = [
    for (final g in score.games)
      if (g.a + g.b > 0) (g.of(me), g.of(me.opponent)),
  ];
  final winner = match.winner;
  final format = switch (parseCategoryId(match.categoryId)?.$1) {
    MatchFormat.singles => PlayCategory.singles,
    MatchFormat.mixed => PlayCategory.mixed,
    MatchFormat.doubles => PlayCategory.doubles,
    null => match.sideA.length == 1 ? PlayCategory.singles : PlayCategory.doubles,
  };
  return Match(
    id: match.id,
    status: MatchStatus.completed,
    kind: MatchKind.friendly,
    format: format,
    mine: mine,
    theirs: side(me.opponent),
    scheduledAt: match.startedAt,
    startedAt: match.startedAt,
    completedAt: match.finishedAt ?? match.startedAt,
    games: games,
    venue: match.locationName,
    pointsToWin: match.rules.pointsToWin,
    bestOf: match.rules.bestOf,
    wonByDefault: match.outcome == null || winner == null ? null : winner == me,
    verification: verification,
  );
}
