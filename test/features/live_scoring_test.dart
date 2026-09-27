import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skorx/app/app.dart';
import 'package:skorx/features/auth/auth_controller.dart';
import 'package:skorx/features/auth/data/auth_repository.dart';
import 'package:skorx/features/casual_match/data/match_code.dart';
import 'package:skorx/features/casual_match/data/match_setup.dart';
import 'package:skorx/features/casual_match/live/commentary.dart';
import 'package:skorx/features/casual_match/live/match_analytics.dart';
import 'package:skorx/features/casual_match/live/live_court.dart';
import 'package:skorx/features/casual_match/local_match.dart';
import 'package:skorx/features/casual_match/scoring_controller.dart';
import 'package:skorx/features/casual_match/ui/live/share_result.dart';
import 'package:skorx/features/casual_match/ui/scoring_screen.dart';
import 'package:skorx/sports/core/match_rules.dart';
import 'package:skorx/sports/core/score_state.dart';
import 'package:skorx/sports/core/scoring_engine.dart';

import '../support/fakes.dart';
import 'casual_match_test.dart' show SilentCommentator;

const sideOut11 = MatchRules(pointsToWin: 11, winByTwo: true, bestOf: 1, scoring: ScoringSystem.sideOut);

LocalMatch match({
  List<String> a = const ['Smit Ramani', 'Kamal Parmar'],
  List<String> b = const ['Anand Varsada', 'Hardik Suthar'],
  MatchRules rules = sideOut11,
  List<Side> rallies = const [],
}) =>
    LocalMatch(
      id: 'm1-local-match',
      sportId: 'pickleball',
      categoryId: a.length == 1 ? 'mens_singles' : 'mens_doubles',
      sideA: a,
      sideB: b,
      rules: rules,
      firstServer: Side.a,
      startedAt: DateTime(2026, 9, 27, 18),
      events: [
        for (final (i, s) in rallies.indexed) RecordedEvent(id: 'e$i', event: RallyWon(s), recordedAt: DateTime(2026, 9, 27, 18, i)),
      ],
    );

void main() {
  group('court positions', () {
    test('doubles side-out: swaps on serve points, second server, and the side-out server by score', () {
      final steps = replayLive(match(rallies: const [Side.a, Side.b, Side.b, Side.a, Side.a]));

      // 0-0-2: Smit serves from the right to the player diagonally opposite.
      var c = steps[0].court;
      expect((c.serveSide, c.serverIndex, c.serverCourt), (Side.a, 0, ServiceCourt.right));
      expect(c.courtOf(Side.b, c.receiverIndex), ServiceCourt.right);

      // A scores on serve: Smit and Kamal change courts, Smit now serves from the left.
      c = steps[1].court;
      expect(steps[1].events, contains(LiveEvent.point));
      expect((c.serverIndex, c.serverCourt), (0, ServiceCourt.left));
      expect(c.courtOf(Side.a, 1), ServiceCourt.right);
      expect(c.receiverIndex, 1, reason: 'Hardik stands in B\'s left court, diagonally opposite');

      // B wins on the 0-0-2 start: straight side-out. B has 0, so their right-court player serves.
      c = steps[2].court;
      expect(steps[2].events, contains(LiveEvent.sideOut));
      expect((c.serveSide, c.serverIndex, c.serverCourt), (Side.b, 0, ServiceCourt.right));

      // B scores on serve: Anand moves to the left.
      c = steps[3].court;
      expect((c.serverIndex, c.serverCourt), (0, ServiceCourt.left));

      // A wins the rally: B's second server, Hardik, now in the right court.
      c = steps[4].court;
      expect(steps[4].events, contains(LiveEvent.secondServer));
      expect((c.serveSide, c.serverIndex, c.serverCourt), (Side.b, 1, ServiceCourt.right));

      // A wins again: side-out to A at 1 point (odd), so the player in A's left court serves: Smit.
      c = steps[5].court;
      expect(steps[5].events, contains(LiveEvent.sideOut));
      expect((c.serveSide, c.serverIndex, c.serverCourt), (Side.a, 0, ServiceCourt.left));
    });

    test('singles: both players stand in the court that matches the server\'s score', () {
      final steps = replayLive(match(a: const ['Smit'], b: const ['Anand'], rallies: const [Side.a, Side.b]));
      expect(steps[0].court.serverCourt, ServiceCourt.right);
      expect(steps[1].court.serverCourt, ServiceCourt.left, reason: 'Smit has 1');
      expect(steps[1].court.courtOf(Side.b, 0), ServiceCourt.left);
      expect(steps[2].court.serveSide, Side.b);
      expect(steps[2].court.serverCourt, ServiceCourt.right, reason: 'Anand has 0');
    });

    test('ends change after each game and halfway through the deciding game', () {
      const rules = MatchRules(pointsToWin: 2, winByTwo: false, bestOf: 3, scoring: ScoringSystem.rally);
      // Rally scoring to 2: A takes game 1, B takes game 2, then the decider reaches 1 (half of 2).
      final steps = replayLive(match(rules: rules, rallies: const [Side.a, Side.a, Side.b, Side.b, Side.a]));
      expect(steps[0].court.aOnLeft, isTrue);
      expect(steps[2].events, contains(LiveEvent.gameWon));
      expect(steps[2].court.aOnLeft, isFalse);
      expect(steps[4].court.aOnLeft, isTrue);
      expect(steps[5].events, contains(LiveEvent.endsSwitched));
      expect(steps[5].court.aOnLeft, isFalse);
    });

    test('between games the court follows the scorer: changed ends or the same ends', () {
      const rules = MatchRules(pointsToWin: 2, winByTwo: false, bestOf: 3, scoring: ScoringSystem.rally);
      final m = match(rules: rules, rallies: const [Side.a, Side.a]);
      expect(m.awaitingEndChange, isTrue);
      expect(replayLive(m.copyWith(endChanges: {1: true})).last.court.aOnLeft, isFalse);
      expect(replayLive(m.copyWith(endChanges: {1: false})).last.court.aOnLeft, isTrue);
      expect(m.copyWith(endChanges: {1: false}).awaitingEndChange, isFalse);

      final g = summarizeGame(m, replayLive(m), 1);
      expect((g.score, g.winner, g.rallies, g.longestRun, g.longestRunSide), (const GameScore(2, 0), Side.a, 2, 2, Side.a));
    });

    test('game point and match point only for a side that can score', () {
      final m = match(rules: const MatchRules(pointsToWin: 2, winByTwo: false, bestOf: 1, scoring: ScoringSystem.sideOut),
          rallies: const [Side.a]);
      final score = m.score;
      expect(isMatchPoint(m, score, Side.a), isTrue);
      expect(isGamePoint(m, score, Side.b), isFalse, reason: 'B is receiving and cannot score in side-out');
    });
  });

  group('match IDs', () {
    test('every type of match is told apart by its ID, and IDs read back', () {
      final at = DateTime(2026, 9, 27, 18);
      final codes = <String>{};
      for (final f in MatchFormat.values) {
        for (final d in Division.forFormat(f)) {
          for (final ctx in MatchContext.values) {
            final code = MatchCode.generate(sport: 'pickleball', context: ctx, format: f, division: d, at: at);
            final text = code.toString();
            expect(text, matches(RegExp(r'^SKX-P[CTL][A-Z]{2}-260927-[0-9A-HJKMNP-TV-Z]{5}$')));
            final back = MatchCode.tryParse(text)!;
            expect((back.context, back.format, back.division, back.date), (ctx, f, d, DateTime(2026, 9, 27)));
            codes.add(text.substring(4, 8));
          }
        }
      }
      expect(codes, hasLength(MatchContext.values.length * 8), reason: 'each context and category has its own prefix');
      expect(MatchCode.tryParse('SKX-PCMD-260927-7K3QX')!.division, Division.men);
      expect(MatchCode.tryParse('SKX-PTKX-260927-7K3QX')!.format, MatchFormat.mixed);
      expect(MatchCode.tryParse('not-a-match'), isNull);
    });
  });

  group('analytics', () {
    test('points, serve, runs, leads and lead changes from the rallies', () {
      const rules = MatchRules(pointsToWin: 5, winByTwo: false, bestOf: 1, scoring: ScoringSystem.rally);
      // A A B B B A A A: 2-0, 2-3, then 5-3.
      final m = match(rules: rules, rallies: const [Side.a, Side.a, Side.b, Side.b, Side.b, Side.a, Side.a, Side.a]);
      final a = analyzeMatch(m);
      expect(a.rallies, hasLength(8));
      expect((a.stats[Side.a]!.points, a.stats[Side.b]!.points), (5, 3));
      expect((a.stats[Side.a]!.bestRun, a.stats[Side.b]!.bestRun), (3, 3));
      expect((a.stats[Side.a]!.biggestLead, a.stats[Side.b]!.biggestLead), (2, 1));
      expect(a.leadChanges, 2, reason: 'A led, B went ahead at 2-3, A back ahead at 4-3');
      expect(a.ties, 2, reason: '2-2 and 3-3');
      expect(a.stats[Side.a]!.servicePoints + a.stats[Side.a]!.returnRalliesWon, 5);
      expect(a.servers.fold<int>(0, (n, s) => n + s.served), 8);
    });
  });

  group('court corrections', () {
    test('swap ends and swap the server, both undone in order', () async {
      useInMemoryPreferences();
      final c = ProviderContainer(overrides: appOverrides(FakeAuthRepository(stored: RestoredUser(user(), fromCache: false))));
      addTearDown(c.dispose);
      c.listen(scoringControllerProvider, (_, _) {});
      c.listen(authControllerProvider, (_, _) {});
      await c.read(scoringControllerProvider.notifier).ready;
      // Let the stored sign-in restore, so the match knows who is scoring.
      while (c.read(currentUserProvider) == null) {
        await Future<void>.delayed(Duration.zero);
      }
      final scoring = c.read(scoringControllerProvider.notifier);
      await scoring.start(const NewMatch(
        sportId: 'pickleball',
        categoryId: 'mens_doubles',
        sideA: ['Smit Ramani', 'Kamal Parmar'],
        sideB: ['Anand Varsada', 'Hardik Suthar'],
        rules: sideOut11,
        firstServer: Side.a,
      ));
      final started = c.read(scoringControllerProvider)!;
      expect(started.code, startsWith('SKX-PCMD-'));
      expect(started.scorers.single.name, 'Smit Ramani');

      CourtState court() => replayLive(c.read(scoringControllerProvider)!).last.court;
      await scoring.adjustCourt(CourtFix.swapEnds);
      expect(court().aOnLeft, isFalse);
      await scoring.adjustCourt(CourtFix.swapServingPlayers);
      expect((court().serverIndex, court().serverCourt), (1, ServiceCourt.right), reason: 'Kamal now serves from the right');

      await scoring.rallyWonBy(Side.a);
      expect(court().serverIndex, 1, reason: 'the correction holds through later rallies');

      await scoring.undo();
      await scoring.undo();
      expect(court().serverIndex, 0);
      await scoring.undo();
      expect(court().aOnLeft, isTrue);

      await scoring.changeScorer('Kamal Parmar');
      expect(c.read(scoringControllerProvider)!.scorers.map((s) => s.name), ['Smit Ramani', 'Kamal Parmar']);
    });
  });

  group('scored by', () {
    test('a match saved without a scorer is credited to the signed-in profile', () async {
      useInMemoryPreferences();
      final c = ProviderContainer(overrides: appOverrides(FakeAuthRepository(stored: RestoredUser(user(), fromCache: false))));
      addTearDown(c.dispose);
      await c.read(preferencesProvider).setString('skorx.activeMatch', jsonEncode(match(rallies: const [Side.a]).toJson()));
      c.listen(authControllerProvider, (_, _) {});
      c.listen(scoringControllerProvider, (_, _) {});
      await c.read(scoringControllerProvider.notifier).ready;
      while (c.read(scoringControllerProvider)?.scorers.isEmpty ?? true) {
        await Future<void>.delayed(Duration.zero);
      }
      final scorer = c.read(scoringControllerProvider)!.scorers.single;
      expect((scorer.name, scorer.fromEvent), ('Smit Ramani', 0));
    });

    test('with no one signed in there is simply no name, never a placeholder', () {
      expect(scorersOf(match(), null), isEmpty);
      expect(scorersOf(match(), user(name: 'Riya Shah')).single.name, 'Riya Shah');
    });
  });

  group('commentary', () {
    test('basic calls the score, advanced names the players', () {
      final m = match(rallies: const [Side.a]);
      final steps = replayLive(m);
      expect(commentaryFor(m, steps.last, CommentaryLevel.basic, before: steps.first), '1, 0, 2.');
      expect(commentaryFor(m, steps.last, CommentaryLevel.advanced, before: steps.first),
          'Smit and Kamal take the lead. 1, 0, 2.');
      expect(commentaryFor(m, steps.last, CommentaryLevel.off), isNull);
    });

    test('side-out and match point', () {
      final m = match(
        rules: const MatchRules(pointsToWin: 2, winByTwo: false, bestOf: 1, scoring: ScoringSystem.sideOut),
        rallies: const [Side.b, Side.b],
      );
      final steps = replayLive(m);
      expect(commentaryFor(m, steps[1], CommentaryLevel.advanced), 'Side out. Anand and Hardik to serve. 0, 0, 1.');
      expect(commentaryFor(m, steps[2], CommentaryLevel.basic), '1, 0, 1. Match point.');
    });
  });

  group('live screen', () {
    late SilentCommentator voice;
    var clock = DateTime(2026, 9, 27, 18);

    Future<ProviderContainer> pumpMatch(WidgetTester tester, LocalMatch m, {bool tutorialSeen = true}) async {
      useReducedMotion(tester);
      voice = SilentCommentator();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          ...appOverrides(FakeAuthRepository(stored: RestoredUser(user(), fromCache: false))),
          commentatorProvider.overrideWithValue(voice),
          // Every tap a second after the last, clear of the double-tap guard.
          scoringClockProvider.overrideWithValue(() => clock = clock.add(const Duration(seconds: 1))),
        ],
        child: const SkorxApp(),
      ));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(tester.element(find.byType(SkorxApp)));
      if (tutorialSeen) await container.read(liveSettingsProvider.notifier).update((s) => s.copyWith(tutorialSeen: true));
      await container.read(scoringControllerProvider.notifier).start(NewMatch(
            sportId: m.sportId,
            categoryId: m.categoryId,
            sideA: m.sideA,
            sideB: m.sideB,
            rules: m.rules,
            firstServer: m.firstServer,
          ));
      await tester.pump();
      await tester.tap(find.byKey(const Key('resumeMatchBar')));
      await tester.pumpAndSettle();
      return container;
    }

    setUp(() {
      useInMemoryPreferences();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler('dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle', (_) async {
        return const StandardMessageCodec().encodeMessage(<Object?>[]);
      });
    });

    testWidgets('first use shows a three-step guide, then never again', (tester) async {
      final container = await pumpMatch(tester, match(), tutorialSeen: false);
      expect(find.text('Tap the winning side'), findsOneWidget);
      await tester.tap(find.byKey(const Key('tutorialNext')));
      await tester.pumpAndSettle();
      expect(find.text('The ball shows the server'), findsOneWidget);
      await tester.tap(find.byKey(const Key('tutorialNext')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tutorialNext')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tutorialNext')), findsNothing);
      expect(container.read(liveSettingsProvider).tutorialSeen, isTrue);
    });

    testWidgets('one tap scores, the announcer calls it, undo takes it back', (tester) async {
      final container = await pumpMatch(tester, match());
      expect(find.byKey(const Key('serverTag')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('serverTag'))).data, 'Smit · RIGHT');

      await tester.tap(find.byKey(const Key('side-a')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('points-a'))).data, '1');
      expect(tester.widget<Text>(find.byKey(const Key('serverTag'))).data, 'Smit · LEFT');
      expect(voice.lines.last, '1, 0, 2.');

      await tester.tap(find.byKey(const Key('undo')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('points-a'))).data, '0');
      expect(tester.widget<Text>(find.byKey(const Key('serverTag'))).data, 'Smit · RIGHT');
      expect(container.read(scoringControllerProvider)!.events, isEmpty);
    });

    testWidgets('pause locks the court until resumed', (tester) async {
      final container = await pumpMatch(tester, match());
      await tester.tap(find.byKey(const Key('pause')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pause-Water break')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pausedTitle')), findsOneWidget);
      await container.read(scoringControllerProvider.notifier).rallyWonBy(Side.a);
      expect(container.read(scoringControllerProvider)!.events, isEmpty, reason: 'no scoring while paused');

      await tester.tap(find.byKey(const Key('resume')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('side-a')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('points-a'))).data, '1');
    });

    testWidgets('changing the format mid-match asks first, then resets to 0-0', (tester) async {
      final container = await pumpMatch(tester, match());
      await tester.tap(find.byKey(const Key('side-a')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('menu-rules')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('playTo-15')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('applyRules')));
      await tester.pumpAndSettle();
      expect(find.text('Change the match format?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('cancelAction')));
      await tester.pumpAndSettle();
      expect(container.read(scoringControllerProvider)!.rules.pointsToWin, 11, reason: 'cancel changes nothing');

      await tester.tap(find.byKey(const Key('menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('menu-rules')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('playTo-15')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('applyRules')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmReset')));
      await tester.pumpAndSettle();
      final m = container.read(scoringControllerProvider)!;
      expect(m.rules.pointsToWin, 15);
      expect(m.events, isEmpty);
      expect(tester.widget<Text>(find.byKey(const Key('points-a'))).data, '0');
    });

    testWidgets('after game 1 a break card asks about ends; scoring waits for the answer; undo takes it back', (tester) async {
      const rules = MatchRules(pointsToWin: 2, winByTwo: false, bestOf: 3, scoring: ScoringSystem.rally);
      final container = await pumpMatch(tester, match(rules: rules));
      final aTopBefore = replayLive(container.read(scoringControllerProvider)!).last.court.aOnLeft;
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byKey(const Key('side-a')));
        await tester.pumpAndSettle();
      }
      expect(find.byKey(const Key('gameBreak')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('breakGameScore'))).data, '2–0');
      expect(find.text('Did the players change ends?'), findsOneWidget);

      // The court is locked while the card is up.
      await container.read(scoringControllerProvider.notifier).rallyWonBy(Side.b);
      expect(container.read(scoringControllerProvider)!.events, hasLength(2));

      await tester.tap(find.byKey(const Key('endsSame')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('gameBreak')), findsNothing);
      final m = container.read(scoringControllerProvider)!;
      expect(m.endChanges, {1: false});
      expect(replayLive(m).last.court.aOnLeft, aTopBefore, reason: 'they stayed at the same ends');
      expect(voice.lines.last, 'Game 2. Anand and Hardik to serve.');

      // Undoing the game-winning point forgets the answer; winning it again asks again.
      await tester.tap(find.byKey(const Key('undo')));
      await tester.pumpAndSettle();
      expect(container.read(scoringControllerProvider)!.endChanges, isEmpty);
      await tester.tap(find.byKey(const Key('side-a')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('gameBreak')), findsOneWidget);
      await tester.tap(find.byKey(const Key('endsSwitched')));
      await tester.pumpAndSettle();
      expect(replayLive(container.read(scoringControllerProvider)!).last.court.aOnLeft, !aTopBefore);
    });

    testWidgets('back asks before leaving live scoring', (tester) async {
      await pumpMatch(tester, match());
      await tester.tap(find.byKey(const Key('side-a')));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Back to home. The match stays saved.'));
      await tester.pumpAndSettle();
      expect(find.text('Leave live scoring?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('stayScoring')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('side-a')), findsOneWidget, reason: 'still scoring');

      await tester.tap(find.bySemanticsLabel('Back to home. The match stays saved.'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('leaveScoring')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('side-a')), findsNothing);
      expect(find.byKey(const Key('resumeMatchBar')), findsOneWidget, reason: 'the match waits on Home');
    });

    testWidgets('scorer handover, then the result shows charts, who scored, the ID, and a share preview', (tester) async {
      const rules = MatchRules(pointsToWin: 2, winByTwo: false, bestOf: 1, scoring: ScoringSystem.rally);
      final container = await pumpMatch(tester, match(rules: rules));
      await tester.tap(find.byKey(const Key('side-a')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('menu-scorer')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scorer-Kamal Parmar')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmScorer')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('side-a')));
      await tester.pumpAndSettle();
      final m = container.read(scoringControllerProvider)!;
      expect(m.isOver, isTrue);

      expect(find.byKey(const Key('arcMatchResult')), findsOneWidget, reason: 'SkorX Points for the match');
      final list = find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first;
      await tester.scrollUntilVisible(find.text('Points by game'), 300, scrollable: list);
      expect(find.text('Points by game'), findsOneWidget);
      await tester.scrollUntilVisible(find.byKey(const Key('matchCode')), 300, scrollable: list);
      expect(tester.widget<Text>(find.byKey(const Key('matchCode'))).data, m.code);
      await tester.scrollUntilVisible(find.byKey(const Key('scoredBy')), 300, scrollable: list);
      expect(find.textContaining('Smit Ramani'), findsWidgets);
      expect(find.textContaining('from 1–0, game 1'), findsOneWidget);

      await tester.tap(find.byKey(const Key('shareResult')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('shareNow')), findsOneWidget);
      expect(shareText(m), contains('Match ID: ${m.code}'));
      expect(shareText(m), contains('https://skorx.in'));
    });

    testWidgets('the keyboard never covers the Change scorer name box', (tester) async {
      await pumpMatch(tester, match());
      await tester.tap(find.byKey(const Key('menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('menu-scorer')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scorerSearch')));
      await tester.pump();

      // A 300-point keyboard slides up.
      final dpr = tester.view.devicePixelRatio;
      tester.view.viewInsets = FakeViewPadding(bottom: 300 * dpr);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();

      final screen = tester.view.physicalSize.height / dpr;
      final field = tester.getRect(find.byKey(const Key('scorerSearch')));
      expect(field.bottom, lessThanOrEqualTo(screen - 300), reason: 'the search box sits above the keyboard');
      await tester.enterText(find.byKey(const Key('scorerSearch')), 'Coach Ravi');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('scorerGuest')));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(const Key('scorerGuest'))).bottom, lessThanOrEqualTo(screen - 300));
      await tester.tap(find.byKey(const Key('scorerGuest')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('confirmScorer')));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(const Key('confirmScorer'))).bottom, lessThanOrEqualTo(screen - 300));
    });

    testWidgets('the new scorer is found by mobile number, X code or name', (tester) async {
      final container = await pumpMatch(tester, match());
      Future<void> search(String text) async {
        await tester.enterText(find.byKey(const Key('scorerSearch')), text);
        await tester.pumpAndSettle();
      }

      await tester.tap(find.byKey(const Key('menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('menu-scorer')));
      await tester.pumpAndSettle();

      // Mobile: the whole number, typed any way; part of a number finds nobody by number.
      await search('+91 98250-10519');
      expect(find.byKey(const Key('scorerResult-SKX-10519')), findsOneWidget);
      expect(find.textContaining('Mobile ····0519'), findsOneWidget);
      await search('98250');
      expect(find.byKey(const Key('scorerResult-SKX-10519')), findsNothing);
      await search('99999 99999');
      expect(find.byKey(const Key('scorerNotFound')), findsOneWidget);

      // X code, however it is typed.
      await search('x-d4jx');
      expect(find.byKey(const Key('scorerResult-SKX-10412')), findsOneWidget);

      // Name.
      await search('meera');
      await tester.tap(find.byKey(const Key('scorerResult-SKX-10648')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('confirmScorer')));
      await tester.tap(find.byKey(const Key('confirmScorer')));
      await tester.pumpAndSettle();
      final last = container.read(scoringControllerProvider)!.scorers.last;
      expect((last.name, last.playerId), ('Meera Joshi', 'SKX-10648'));
    });

    testWidgets('handover to another phone: scoring pauses here until they accept, then carries on', (tester) async {
      final container = await pumpMatch(tester, match());
      await tester.tap(find.byKey(const Key('side-a')));
      await tester.pumpAndSettle();

      Future<void> request() async {
        await tester.tap(find.byKey(const Key('menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('menu-scorer')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('scorerSearch')), 'meera');
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('scorerResult-SKX-10648')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('sendHandover')));
        await tester.tap(find.byKey(const Key('sendHandover')));
        await tester.pumpAndSettle();
      }

      // Declined: scoring carries on here with the same scorer.
      await request();
      expect(find.byKey(const Key('handoverWaiting')), findsOneWidget);
      await container.read(scoringControllerProvider.notifier).rallyWonBy(Side.a);
      expect(container.read(scoringControllerProvider)!.events, hasLength(1), reason: 'scoring is paused on this phone');
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('handoverPrompt')), findsOneWidget);
      await tester.tap(find.byKey(const Key('declineHandover')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('handoverWaiting')), findsNothing);
      expect(container.read(scoringControllerProvider)!.scorers.last.name, 'Smit Ramani');

      // Cancelled before it arrives: nothing pops up later.
      await request();
      await tester.tap(find.byKey(const Key('cancelHandover')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('handoverPrompt')), findsNothing);

      // Accepted: the new scorer takes over from exactly this point.
      await request();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('acceptHandover')));
      await tester.pumpAndSettle();
      final m = container.read(scoringControllerProvider)!;
      expect(m.awaitingHandover, isFalse);
      expect((m.scorers.last.name, m.scorers.last.playerId, m.scorers.last.fromEvent), ('Meera Joshi', 'SKX-10648', 1));
      await tester.tap(find.byKey(const Key('side-a')));
      await tester.pumpAndSettle();
      expect(container.read(scoringControllerProvider)!.events, hasLength(2), reason: 'scoring continues');
    });

    testWidgets('walkover: pick the winner, confirm, result stays until Done; undo reopens', (tester) async {
      final container = await pumpMatch(tester, match());
      await tester.tap(find.byKey(const Key('menu')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('menu-walkover')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('menu-walkover')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('early-b')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Walkover will mark Anand Varsada / Hardik Suthar'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirmEarlyEnd')));
      await tester.pumpAndSettle();

      final m = container.read(scoringControllerProvider)!;
      expect(m.winner, Side.b);
      expect(m.outcome!.kind, EarlyEnd.walkover);
      expect(find.text('WALKOVER'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('result'))).data, 'Anand Varsada / Hardik Suthar');

      await tester.scrollUntilVisible(find.byKey(const Key('undoResult')), 300,
          scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first);
      await tester.tap(find.byKey(const Key('undoResult')));
      await tester.pumpAndSettle();
      expect(container.read(scoringControllerProvider)!.outcome, isNull);
      expect(find.byKey(const Key('side-a')), findsOneWidget);
    });
  });
}
