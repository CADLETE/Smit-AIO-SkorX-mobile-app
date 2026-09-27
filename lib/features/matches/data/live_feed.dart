import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sample_latency.dart';
import '../../../core/sample_persona.dart';
import '../../../sports/core/match_rules.dart';
import '../../../sports/core/score_state.dart';
import '../../../sports/core/scoring_engine.dart';
import '../../../sports/sport_registry.dart';
import '../../casual_match/data/match_setup.dart' show MatchDetails;
import '../../casual_match/local_match.dart';
import '../../player/data/player_repository.dart' show PlayCategory;
import 'match.dart';
import 'match_repository.dart';

/// Every rally of a match on court, for people watching it.
///
/// Spectators get exactly what the scorer's phone records: the rally log.
/// Replaying it through the sport's engine (as the scorer's own screen does)
/// gives the score, who serves from which court, the momentum and every
/// stat, so what a spectator sees can never disagree with the scoreboard.
abstract class LiveFeedSource {
  /// `GET /matches/:id/events`, then the `match.<id>` socket for each new
  /// rally. Null when this match has no rally feed (only its summary).
  Stream<LocalMatch>? watch(Match match);
}

final liveFeedSourceProvider = Provider<LiveFeedSource>((ref) {
  if (!kDebugMode) return const NoLiveFeed();
  if (ref.watch(samplePersonaProvider) == SamplePersona.newcomer) return const NoLiveFeed();
  return SampleLiveFeed(tick: ref.watch(sampleLiveTickProvider));
});

/// The rally-by-rally match behind [Match] `id`, while it is live. Null for
/// matches that are not live or have no feed; screens then fall back to the
/// summary score.
final liveFeedProvider = StreamProvider.autoDispose.family<LocalMatch?, String>((ref, id) async* {
  final match = await ref.watch(matchProvider(id).future);
  final feed = match.isLive ? ref.watch(liveFeedSourceProvider).watch(match) : null;
  if (feed == null) {
    yield null;
  } else {
    yield* feed;
  }
});

/// Release builds until the endpoint exists.
class NoLiveFeed implements LiveFeedSource {
  const NoLiveFeed();

  @override
  Stream<LocalMatch>? watch(Match match) => null;
}

/// Debug builds: a rally history that ends on the match's live score, then
/// a new rally every [tick] until the match is won. Null [tick] holds the
/// match still.
class SampleLiveFeed implements LiveFeedSource {
  const SampleLiveFeed({this.tick});

  final Duration? tick;

  @override
  Stream<LocalMatch>? watch(Match match) {
    var local = sampleRallyHistory(match, DateTime.now());
    final every = tick;
    if (every == null) return Stream.value(local);
    return Stream.multi((controller) {
      controller.add(local);
      final random = Random();
      var rest = 0;
      final timer = Timer.periodic(every, (_) {
        if (local.isOver) return;
        // A short breather between games.
        if (rest > 0) {
          rest--;
          return;
        }
        final before = local.score.gameNumber;
        local = _withRally(local, _nextWinner(local, random), DateTime.now());
        if (local.score.gameNumber > before) rest = 2;
        controller.add(local);
      });
      controller.onCancel = timer.cancel;
    });
  }

  /// Close to a coin toss, with a little momentum for whoever won the last rally.
  static Side _nextWinner(LocalMatch match, Random random) {
    final last = match.events.lastOrNull?.event;
    final lead = last is RallyWon ? last.side : Side.a;
    return random.nextDouble() < 0.56 ? lead : lead.opponent;
  }
}

LocalMatch _withRally(LocalMatch match, Side winner, DateTime at) => match.copyWith(
      events: [
        ...match.events,
        RecordedEvent(id: '${match.id}-${match.events.length + 1}', event: RallyWon(winner), recordedAt: at),
      ],
    );

/// The match as its scorer would have recorded it: finished games and the
/// game in play land on [match]'s scores, with side-outs and server changes
/// played out by the real engine. The same match always gets the same
/// history.
@visibleForTesting
LocalMatch sampleRallyHistory(Match match, DateTime now) {
  final random = Random(match.id.hashCode);
  final doubles = match.format != PlayCategory.singles;
  final rules = MatchRules(
    pointsToWin: match.pointsToWin,
    winByTwo: true,
    bestOf: match.bestOf,
    scoring: ScoringSystem.sideOut,
  );
  final start = match.startedAt ?? match.scheduledAt;
  var local = LocalMatch(
    id: match.id,
    sportId: pickleball.id,
    categoryId: switch (match.format) {
      PlayCategory.singles => 'singles',
      PlayCategory.doubles => 'doubles',
      PlayCategory.mixed => 'mixed_doubles',
    },
    sideA: match.mine,
    sideB: match.theirs,
    rules: rules,
    firstServer: random.nextBool() ? Side.a : Side.b,
    startedAt: start,
    locationName: match.venue,
    details: MatchDetails(court: match.court, venue: match.venue),
  );
  if (local.sideA.length != (doubles ? 2 : 1) || local.sideB.length != local.sideA.length) return local;

  final engine = local.sport.engine;
  final setup = local.setup;
  final winners = <Side>[];
  var score = engine.start(setup);

  void play(Side side) {
    winners.add(side);
    score = engine.rally(setup, score, side);
  }

  // One game at a time: pick who wins each point, never letting the game end
  // early, and win serve back (side-outs) whenever the point goes the other way.
  final targets = [
    for (final g in match.games) GameScore(g.$1, g.$2),
    if (match.live case final live?) GameScore(live.mine, live.theirs),
  ];
  for (final (i, target) in targets.indexed) {
    final finished = i < match.games.length;
    while (score.gameNumber == i + 1 && !score.isOver && score.currentGame != target) {
      final game = score.currentGame;
      Side? point;
      final needA = target.a - game.a, needB = target.b - game.b;
      if (needA <= 0 && needB <= 0) break;
      bool fits(Side s) {
        if ((s == Side.a ? needA : needB) <= 0) return false;
        final next = game.plus(s);
        final over = gameWinnerOf(next, rules) != null;
        return !over || (finished && next == target);
      }

      final preferA = random.nextInt(needA + needB) < needA;
      final first = preferA ? Side.a : Side.b;
      if (fits(first)) {
        point = first;
      } else if (fits(first.opponent)) {
        point = first.opponent;
      }
      if (point == null) break;
      // Now and then the server loses a rally before the point is played.
      if (score.serve.side == point && random.nextInt(7) == 0) play(point.opponent);
      var guard = 0;
      while (score.serve.side != point && guard++ < 3) {
        play(point);
      }
      play(point);
    }
  }
  // The server the summary reports.
  if (match.live?.myServe case final mine? when !score.isOver) {
    final serving = mine ? Side.a : Side.b;
    var guard = 0;
    while (score.serve.side != serving && guard++ < 3) {
      play(serving);
    }
  }

  // Spread the rallies over the time played, a little unevenly, with a pause
  // between games.
  final span = now.difference(start).inMilliseconds;
  final gaps = [for (var i = 0; i < winners.length; i++) 0.6 + random.nextDouble()];
  final total = gaps.fold<double>(0, (s, g) => s + g) + 2;
  var elapsed = 0.0;
  final events = <RecordedEvent>[];
  for (final (i, side) in winners.indexed) {
    elapsed += gaps[i];
    events.add(RecordedEvent(
      id: '${match.id}-${i + 1}',
      event: RallyWon(side),
      recordedAt: start.add(Duration(milliseconds: (span * elapsed / total).round())),
    ));
  }
  return local.copyWith(events: events);
}
