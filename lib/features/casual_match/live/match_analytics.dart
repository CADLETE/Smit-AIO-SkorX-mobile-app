import 'package:flutter/foundation.dart';

import '../../../sports/core/score_state.dart';
import '../local_match.dart';
import 'live_court.dart';

/// One rally as the analytics see it.
@immutable
class RallyRecord {
  const RallyRecord({
    required this.number,
    required this.game,
    required this.rallyInGame,
    required this.winner,
    required this.scored,
    required this.servingSide,
    required this.serverIndex,
    required this.after,
    required this.at,
  });

  /// 1-based across the match.
  final int number;
  final int game;

  /// 1-based within the game.
  final int rallyInGame;
  final Side winner;

  /// Whether the rally won a point (in side-out scoring, only the server scores).
  final bool scored;
  final Side servingSide;
  final int serverIndex;

  /// The game score after this rally.
  final GameScore after;
  final DateTime at;
}

@immutable
class SideStats {
  const SideStats({
    required this.points,
    required this.ralliesWon,
    required this.servicePoints,
    required this.serveRallies,
    required this.returnRalliesWon,
    required this.returnRallies,
    required this.bestRun,
    required this.biggestLead,
  });

  final int points;
  final int ralliesWon;

  /// Points won on own serve, out of rallies served.
  final int servicePoints;
  final int serveRallies;

  /// Rallies won while receiving (breaks of serve), out of rallies received.
  final int returnRalliesWon;
  final int returnRallies;
  final int bestRun;
  final int biggestLead;
}

/// Points won by each player on their own serve.
@immutable
class ServerStats {
  const ServerStats({required this.side, required this.index, required this.name, required this.served, required this.won});

  final Side side;
  final int index;
  final String name;
  final int served;
  final int won;
}

/// Everything the result screen charts and counts, computed from the
/// recorded rallies alone.
@immutable
class MatchAnalytics {
  const MatchAnalytics({
    required this.rallies,
    required this.stats,
    required this.servers,
    required this.leadChanges,
    required this.ties,
    required this.duration,
    required this.averageRally,
    required this.games,
  });

  final List<RallyRecord> rallies;
  final Map<Side, SideStats> stats;
  final List<ServerStats> servers;
  final int leadChanges;

  /// Times the game score was level after 0-0.
  final int ties;
  final Duration duration;

  /// Average time from one rally being recorded to the next.
  final Duration? averageRally;
  final List<GameSummary> games;

  bool get hasRallies => rallies.isNotEmpty;

  List<RallyRecord> game(int number) => rallies.where((r) => r.game == number).toList();
}

MatchAnalytics analyzeMatch(LocalMatch match) {
  final steps = replayLive(match);
  final rallies = <RallyRecord>[];
  for (var i = 1; i < steps.length; i++) {
    final step = steps[i];
    final winner = step.rallyWinner;
    if (winner == null) continue;
    final before = steps[i - 1];
    final game = before.score.gameNumber;
    final after = step.events.contains(LiveEvent.gameWon) ? step.score.games[game - 1] : step.score.currentGame;
    final inGame = rallies.where((r) => r.game == game).length + 1;
    rallies.add(RallyRecord(
      number: rallies.length + 1,
      game: game,
      rallyInGame: inGame,
      winner: winner,
      scored: step.events.contains(LiveEvent.point),
      servingSide: before.court.serveSide,
      serverIndex: before.court.serverIndex,
      after: after,
      at: match.events[i - 1].recordedAt,
    ));
  }

  final stats = <Side, SideStats>{};
  for (final side in Side.values) {
    var points = 0, won = 0, servicePoints = 0, served = 0, returnWon = 0, returned = 0, run = 0, bestRun = 0, lead = 0;
    for (final r in rallies) {
      // Runs don't carry over from one game to the next.
      if (r.rallyInGame == 1) run = 0;
      final serving = r.servingSide == side;
      if (serving) {
        served++;
      } else {
        returned++;
      }
      if (r.winner == side) {
        won++;
        if (r.scored) {
          points++;
          if (serving) servicePoints++;
        }
        if (!serving) returnWon++;
      }
      if (r.scored) {
        run = r.winner == side ? run + 1 : 0;
        if (run > bestRun) bestRun = run;
      }
      final diff = r.after.of(side) - r.after.of(side.opponent);
      if (diff > lead) lead = diff;
    }
    stats[side] = SideStats(
      points: points,
      ralliesWon: won,
      servicePoints: servicePoints,
      serveRallies: served,
      returnRalliesWon: returnWon,
      returnRallies: returned,
      bestRun: bestRun,
      biggestLead: lead,
    );
  }

  final servers = <ServerStats>[
    for (final side in Side.values)
      for (var i = 0; i < match.names(side).length; i++)
        ServerStats(
          side: side,
          index: i,
          name: match.names(side)[i],
          served: rallies.where((r) => r.servingSide == side && r.serverIndex == i).length,
          won: rallies.where((r) => r.servingSide == side && r.serverIndex == i && r.winner == side && r.scored).length,
        ),
  ];

  var leadChanges = 0, ties = 0;
  Side? leader;
  var lastGame = 0;
  for (final r in rallies) {
    if (r.game != lastGame) {
      leader = null;
      lastGame = r.game;
    }
    if (!r.scored) continue;
    final a = r.after.a, b = r.after.b;
    if (a == b) {
      ties++;
    } else {
      final now = a > b ? Side.a : Side.b;
      if (leader != null && now != leader) leadChanges++;
      leader = now;
    }
  }

  final end = match.finishedAt ?? (rallies.isEmpty ? match.startedAt : rallies.last.at);
  Duration? average;
  if (rallies.length > 1) {
    average = Duration(milliseconds: rallies.last.at.difference(rallies.first.at).inMilliseconds ~/ (rallies.length - 1));
  }
  final finishedGames = steps.last.score.isOver ? steps.last.score.gameNumber : steps.last.score.gameNumber - 1;

  return MatchAnalytics(
    rallies: rallies,
    stats: stats,
    servers: servers,
    leadChanges: leadChanges,
    ties: ties,
    duration: end.difference(match.startedAt),
    averageRally: average,
    games: [for (var g = 1; g <= finishedGames; g++) summarizeGame(match, steps, g)],
  );
}
