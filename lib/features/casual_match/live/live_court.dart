import 'package:flutter/foundation.dart';

import '../../../sports/core/match_rules.dart';
import '../../../sports/core/score_state.dart';
import '../../../sports/core/scoring_engine.dart';
import '../local_match.dart';

/// A service court, from the team's own view facing the net.
enum ServiceCourt {
  right('Right'),
  left('Left');

  const ServiceCourt(this.label);
  final String label;
}

/// What a rally (or a correction) changed, for banners, sound and commentary.
enum LiveEvent { point, sideOut, secondServer, endsSwitched, gameWon, matchWon, serveCorrected }

/// Who stands where. The scoring engine decides the score and which side
/// serves; this adds the people: which player is in which service court, who
/// serves from where, who receives, and which end each team is at.
///
/// Doubles: a team's two players only swap service courts when they win a
/// point on their own serve. After a side-out the first server is whoever
/// stands in the court matching their score (even: right, odd: left).
/// Singles: both players stand in the court matching the server's score.
@immutable
class CourtState {
  const CourtState({
    required this.aOnLeft,
    required this.rightIndexA,
    required this.rightIndexB,
    required this.serveSide,
    required this.serverIndex,
    required this.doubles,
    required this.serverScore,
  });

  /// Whether side A is at the left end (portrait: the top).
  final bool aOnLeft;

  /// The player index standing in each team's right-hand court (doubles).
  final int rightIndexA;
  final int rightIndexB;
  final Side serveSide;
  final int serverIndex;
  final bool doubles;

  /// The serving side's points in the current game (singles positions).
  final int serverScore;

  bool onLeft(Side side) => side == Side.a ? aOnLeft : !aOnLeft;

  int rightIndex(Side side) => side == Side.a ? rightIndexA : rightIndexB;

  ServiceCourt courtOf(Side side, int index) {
    if (!doubles) return serverScore.isEven ? ServiceCourt.right : ServiceCourt.left;
    return index == rightIndex(side) ? ServiceCourt.right : ServiceCourt.left;
  }

  ServiceCourt get serverCourt => courtOf(serveSide, serverIndex);

  /// The receiver stands diagonally opposite, in their own court of the same name.
  int get receiverIndex {
    if (!doubles) return 0;
    final receiving = serveSide.opponent;
    return courtOf(receiving, 0) == serverCourt ? 0 : 1;
  }

  /// The index of the player in [court] of [side].
  int playerIn(Side side, ServiceCourt court) =>
      !doubles ? 0 : (court == ServiceCourt.right ? rightIndex(side) : 1 - rightIndex(side));

  CourtState copyWith({bool? aOnLeft, int? rightIndexA, int? rightIndexB, Side? serveSide, int? serverIndex, int? serverScore}) =>
      CourtState(
        aOnLeft: aOnLeft ?? this.aOnLeft,
        rightIndexA: rightIndexA ?? this.rightIndexA,
        rightIndexB: rightIndexB ?? this.rightIndexB,
        serveSide: serveSide ?? this.serveSide,
        serverIndex: serverIndex ?? this.serverIndex,
        doubles: doubles,
        serverScore: serverScore ?? this.serverScore,
      );

  CourtState swapped(Side side) =>
      side == Side.a ? copyWith(rightIndexA: 1 - rightIndexA) : copyWith(rightIndexB: 1 - rightIndexB);
}

/// The match after one more recorded action.
@immutable
class LiveStep {
  const LiveStep({required this.score, required this.court, this.rallyWinner, this.events = const {}});

  final ScoreState score;
  final CourtState court;
  final Side? rallyWinner;
  final Set<LiveEvent> events;
}

/// Every state the match has been in, one per recorded action (the first is
/// before any rally). Undo is simply the previous entry.
List<LiveStep> replayLive(LocalMatch match) {
  final setup = match.setup;
  final engine = match.sport.engine;
  final rules = match.rules;
  var score = engine.start(setup);
  var court = CourtState(
    aOnLeft: match.details.aStartsLeft,
    rightIndexA: 0,
    rightIndexB: 0,
    serveSide: score.serve.side,
    serverIndex: 0,
    doubles: setup.isDoubles,
    serverScore: 0,
  );
  var switchedMidGame = false;
  CourtState fixed(CourtState c, int afterEvents) {
    for (final a in match.adjustments.where((a) => a.afterEvents == afterEvents)) {
      c = switch (a.fix) {
        CourtFix.swapEnds => c.copyWith(aOnLeft: !c.aOnLeft),
        // The other partner is in the serving court: the server changes, the court does not.
        CourtFix.swapServingPlayers => c.doubles ? c.swapped(c.serveSide).copyWith(serverIndex: 1 - c.serverIndex) : c,
        CourtFix.swapReceivingPlayers => c.doubles ? c.swapped(c.serveSide.opponent) : c,
      };
    }
    return c;
  }

  court = fixed(court, 0);
  final steps = [LiveStep(score: score, court: court)];

  for (final recorded in match.events) {
    final event = recorded.event;
    if (score.isOver) break;
    final next = engine.apply(setup, score, event);
    final events = <LiveEvent>{};
    Side? winner;

    switch (event) {
      case ServeCorrected(:final serve):
        final correct = _correctCourt(next.currentGame.of(serve.side));
        final first = court.playerIn(serve.side, correct);
        court = court.copyWith(serveSide: serve.side, serverIndex: serve.serverNumber == 2 ? 1 - first : first);
        events.add(LiveEvent.serveCorrected);
      case RallyWon(:final side):
        winner = side;
        final scored = next.gameNumber > score.gameNumber || next.currentGame.of(side) > score.currentGame.of(side);
        if (scored) events.add(LiveEvent.point);

        if (next.gameNumber > score.gameNumber) {
          // New game: back to the starting courts, and the ends the scorer
          // confirmed at the break (changing ends is the rule, so that is
          // what is shown until they answer).
          events.add(LiveEvent.gameWon);
          switchedMidGame = false;
          final switched = match.endChanges[score.gameNumber] ?? true;
          court = court.copyWith(
            aOnLeft: switched ? !court.aOnLeft : court.aOnLeft,
            rightIndexA: 0,
            rightIndexB: 0,
            serveSide: next.serve.side,
            serverIndex: 0,
          );
        } else {
          if (side == score.serve.side) {
            // The serving team scored: server and partner change courts.
            if (court.doubles) court = court.swapped(side);
          } else if (next.serve.side == score.serve.side) {
            events.add(LiveEvent.secondServer);
            court = court.copyWith(serverIndex: 1 - court.serverIndex);
          } else {
            events.add(LiveEvent.sideOut);
            final correct = _correctCourt(next.currentGame.of(side));
            court = court.copyWith(serveSide: side, serverIndex: court.playerIn(side, correct));
          }
          if (next.isOver) {
            events.add(LiveEvent.matchWon);
          } else if (!switchedMidGame && _switchesEndsMidGame(rules, next)) {
            final half = (rules.pointsToWin + 1) ~/ 2;
            if (next.currentGame.a >= half || next.currentGame.b >= half) {
              switchedMidGame = true;
              events.add(LiveEvent.endsSwitched);
              court = court.copyWith(aOnLeft: !court.aOnLeft);
            }
          }
        }
    }
    court = fixed(court.copyWith(serverScore: next.currentGame.of(court.serveSide)), steps.length);
    score = next;
    steps.add(LiveStep(score: score, court: court, rallyWinner: winner, events: events));
  }
  return steps;
}

ServiceCourt _correctCourt(int score) => score.isEven ? ServiceCourt.right : ServiceCourt.left;

/// Ends change halfway through the deciding game (6 in a game to 11, 8 to
/// 15, 11 to 21), including a one-game match to 15 or more.
bool _switchesEndsMidGame(MatchRules rules, ScoreState score) {
  final deciding = score.gamesWonA == rules.gamesToWin - 1 && score.gamesWonB == rules.gamesToWin - 1;
  if (!deciding) return false;
  return rules.bestOf > 1 || rules.pointsToWin >= 15;
}

/// Whether [side] wins the game by winning the next rally.
bool isGamePoint(LocalMatch match, ScoreState score, Side side) {
  if (score.isOver) return false;
  final rules = match.rules;
  final canScore = rules.scoring == ScoringSystem.rally || score.serve.side == side;
  if (!canScore) return false;
  final game = score.currentGame.plus(side);
  return gameWinnerOf(game, rules) == side;
}

bool isMatchPoint(LocalMatch match, ScoreState score, Side side) =>
    isGamePoint(match, score, side) && score.gamesWon(side) + 1 >= match.rules.gamesToWin;

/// What happened in one finished game, for the break between games.
@immutable
class GameSummary {
  const GameSummary({
    required this.number,
    required this.score,
    required this.winner,
    required this.rallies,
    required this.sideOuts,
    required this.longestRun,
    required this.longestRunSide,
    this.duration,
  });

  final int number;
  final GameScore score;
  final Side winner;
  final int rallies;
  final int sideOuts;

  /// Most points in a row by one side, and whose run it was.
  final int longestRun;
  final Side longestRunSide;

  /// First rally to last; null if the game had a single rally.
  final Duration? duration;
}

GameSummary summarizeGame(LocalMatch match, List<LiveStep> steps, int number) {
  var rallies = 0;
  var sideOuts = 0;
  var run = 0;
  Side? runSide;
  var best = 0;
  var bestSide = Side.a;
  DateTime? first;
  DateTime? last;
  for (var i = 1; i < steps.length; i++) {
    if (steps[i - 1].score.gameNumber != number) continue;
    final step = steps[i];
    final winner = step.rallyWinner;
    if (winner == null) continue;
    rallies++;
    first ??= match.events[i - 1].recordedAt;
    last = match.events[i - 1].recordedAt;
    if (step.events.contains(LiveEvent.sideOut)) sideOuts++;
    if (step.events.contains(LiveEvent.point)) {
      run = runSide == winner ? run + 1 : 1;
      runSide = winner;
      if (run > best) {
        best = run;
        bestSide = winner;
      }
    }
  }
  final game = steps.last.score.games[number - 1];
  return GameSummary(
    number: number,
    score: game,
    winner: game.a > game.b ? Side.a : Side.b,
    rallies: rallies,
    sideOuts: sideOuts,
    longestRun: best,
    longestRunSide: bestSide,
    duration: first == null || last == null || rallies < 2 ? null : last.difference(first),
  );
}
