import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skorx/features/casual_match/live/commentary.dart';
import 'package:skorx/features/casual_match/live/live_court.dart';
import 'package:skorx/features/casual_match/local_match.dart';
import 'package:skorx/features/matches/data/live_feed.dart';
import 'package:skorx/features/matches/data/match.dart';
import 'package:skorx/features/matches/data/sample_universe.dart';
import 'package:skorx/app/app.dart';
import 'package:skorx/features/auth/data/auth_repository.dart';
import 'package:skorx/sports/core/score_state.dart';
import 'package:skorx/sports/core/scoring_engine.dart';

import '../support/fakes.dart';
import 'player_app_test.dart' show goTo, tapVisible, usePhone;

/// A feed the test plays rallies into.
class _TestFeed implements LiveFeedSource {
  final controller = StreamController<LocalMatch>.broadcast();
  LocalMatch? current;

  @override
  Stream<LocalMatch>? watch(Match match) {
    current = sampleRallyHistory(match, DateTime.now());
    return Stream.multi((out) {
      out.add(current!);
      final sub = controller.stream.listen(out.add);
      out.onCancel = sub.cancel;
    });
  }

  void rally(Side side) {
    final m = current!;
    current = m.copyWith(events: [
      ...m.events,
      RecordedEvent(id: 'test-${m.events.length}', event: RallyWon(side), recordedAt: DateTime.now()),
    ]);
    controller.add(current!);
  }
}

class _Recorder implements Commentator {
  final lines = <String>[];

  @override
  Future<void> say(String text) async => lines.add(text);

  @override
  Future<void> stop() async {}
}

void main() {
  setUp(useInMemoryPreferences);

  group('sample rally history', () {
    final now = DateTime.now();
    final live = SampleUniverse(now).matches.where((m) => m.isLive).toList();

    test('there are live matches to watch', () => expect(live, isNotEmpty));

    test('replays to the live score, game by game, with the right side serving', () {
      for (final m in live) {
        final local = sampleRallyHistory(m, now);
        final score = local.score;
        final reason = '${m.id}: ${score.games}';
        expect(score.isOver, isFalse, reason: reason);
        expect([for (final g in score.games.take(score.games.length - 1)) (g.a, g.b)], m.games, reason: reason);
        if (m.live case final g?) {
          expect(score.gameNumber, g.number, reason: reason);
          expect((score.currentGame.a, score.currentGame.b), (g.mine, g.theirs), reason: reason);
          if (g.myServe case final mine?) expect(score.serve.side, mine ? Side.a : Side.b, reason: reason);
        }
        // Positions work out for every rally, and time only moves forward.
        expect(replayLive(local), hasLength(local.events.length + 1));
        for (var i = 1; i < local.events.length; i++) {
          expect(local.events[i].recordedAt.isBefore(local.events[i - 1].recordedAt), isFalse);
        }
      }
    });

    test('is the same every time a match is opened', () {
      final m = live.first;
      final a = sampleRallyHistory(m, now), b = sampleRallyHistory(m, now);
      expect([for (final e in a.events) (e.event as RallyWon).side], [for (final e in b.events) (e.event as RallyWon).side]);
    });
  });

  group('watching a live match', () {
    Future<(_TestFeed, _Recorder)> open(WidgetTester tester, String id) async {
      usePhone(tester);
      useReducedMotion(tester);
      final feed = _TestFeed();
      final voice = _Recorder();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          ...appOverrides(FakeAuthRepository(stored: RestoredUser(user(), fromCache: false))),
          liveFeedSourceProvider.overrideWithValue(feed),
          commentatorProvider.overrideWithValue(voice),
        ],
        child: const SkorxApp(),
      ));
      await tester.pumpAndSettle();
      await goTo(tester, '/player/matches/$id');
      return (feed, voice);
    }

    Finder points(Side side) => find.descendant(of: find.byKey(Key('points-${side.name}')), matching: find.byType(Text));

    testWidgets('shows the scoreboard, the court and the story so far', (tester) async {
      await open(tester, 'lg-qf1'); // Game 2, 8–6, our serve.
      expect(find.byKey(const Key('liveScoreboard')), findsOneWidget);
      expect(find.text('LIVE · GAME 2'), findsOneWidget);
      expect(tester.widget<Text>(points(Side.a)).data, '8');
      expect(tester.widget<Text>(points(Side.b)).data, '6');
      expect(find.byKey(const Key('liveCourt')), findsOneWidget);
      expect(find.textContaining('receives'), findsOneWidget);
      expect(find.text('Play by play'), findsOneWidget);

      await tapVisible(tester, find.byKey(const Key('playByPlayAll')));
      expect(find.textContaining('Show fewer'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('Head to head'), 300,
          scrollable: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first);
      expect(find.text('Points won'), findsOneWidget);
    });

    testWidgets('moves with every rally, and can call it out loud', (tester) async {
      final (feed, voice) = await open(tester, 'lg-qf1');
      await tester.tap(find.byKey(const Key('liveCommentary')));
      await tester.pumpAndSettle();
      expect(voice.lines.single, contains('Game 2'));

      final serving = feed.current!.score.serve.side;
      feed.rally(serving);
      await tester.pumpAndSettle();
      final after = feed.current!.score.currentGame;
      expect(tester.widget<Text>(points(Side.a)).data, '${after.a}');
      expect(tester.widget<Text>(points(Side.b)).data, '${after.b}');
      expect(voice.lines, hasLength(2), reason: 'the rally was called');

      // Game point for whoever leads now: the scoreboard says so.
      while (!isGamePoint(feed.current!, feed.current!.score, Side.a) && !feed.current!.isOver) {
        feed.rally(Side.a);
      }
      await tester.pumpAndSettle();
      expect(find.text('GAME POINT').evaluate().isNotEmpty || find.text('MATCH POINT').evaluate().isNotEmpty, isTrue);
    });

    testWidgets('a streamed match has a video window, ready to play', (tester) async {
      await open(tester, 'lg-qf1');
      expect(find.byKey(const Key('streamWindow')), findsOneWidget);
      expect(find.byKey(const Key('streamPlay')), findsOneWidget, reason: 'a poster until play is tapped');
      expect(find.byKey(const Key('streamClose')), findsNothing);

      await goTo(tester, '/player/matches/fr-live');
      expect(find.byKey(const Key('liveScoreboard')), findsOneWidget);
      expect(find.byKey(const Key('streamWindow')), findsNothing, reason: 'not streamed');
    });

    testWidgets('a match with no rally feed keeps the summary', (tester) async {
      usePhone(tester);
      useReducedMotion(tester);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          ...appOverrides(FakeAuthRepository(stored: RestoredUser(user(), fromCache: false))),
          liveFeedSourceProvider.overrideWithValue(const NoLiveFeed()),
        ],
        child: const SkorxApp(),
      ));
      await tester.pumpAndSettle();
      await goTo(tester, '/player/matches/lg-qf1');
      expect(find.byKey(const Key('liveScoreboard')), findsNothing);
      expect(find.text('Score'), findsOneWidget);
    });
  });
}
