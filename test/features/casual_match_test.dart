import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skorx/app/app.dart';
import 'package:skorx/features/auth/data/auth_repository.dart';
import 'package:skorx/design/design.dart';
import 'package:skorx/features/casual_match/data/match_setup.dart';
import 'package:skorx/features/casual_match/live/commentary.dart';
import 'package:skorx/features/casual_match/played_matches.dart';
import 'package:skorx/features/casual_match/scoring_controller.dart';
import 'package:skorx/features/matches/data/match_repository.dart';
import 'package:skorx/features/casual_match/ui/scoring_screen.dart';
import 'package:skorx/features/shell/workspace_shell.dart';
import 'package:skorx/sports/core/match_rules.dart';
import 'package:skorx/sports/core/score_state.dart';

import '../support/fakes.dart';

const pickleballDefault = MatchRules(pointsToWin: 11, winByTwo: true, bestOf: 3, scoring: ScoringSystem.sideOut);
const shortRules = MatchRules(pointsToWin: 2, winByTwo: false, bestOf: 3, scoring: ScoringSystem.sideOut);

NewMatch doubles({MatchRules rules = shortRules}) => NewMatch(
      sportId: 'pickleball',
      categoryId: 'doubles',
      sideA: const ['Smit Ramani', 'Kamal Parmar'],
      sideB: const ['Anand Varsada', 'Hardik Suthar'],
      rules: rules,
      firstServer: Side.a,
    );

void main() {
  setUp(() {
    useInMemoryPreferences();
    // wakelock_plus talks to the platform; there is none in tests.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle', (_) async {
      return const StandardMessageCodec().encodeMessage(<Object?>[]);
    });
  });

  group('ScoringController', () {
    Future<ProviderContainer> container() async {
      final c = ProviderContainer(overrides: appOverrides(FakeAuthRepository()));
      addTearDown(c.dispose);
      c.listen(scoringControllerProvider, (_, _) {});
      await c.read(scoringControllerProvider.notifier).ready;
      return c;
    }

    test('scores through the engine and ends the match on a majority of games', () async {
      final c = await container();
      final scoring = c.read(scoringControllerProvider.notifier);
      await scoring.start(doubles());
      // Game 1: A serves and wins 2-0. Game 2: B serves first, so A's first
      // rally only wins the serve back, then A wins 2-0.
      for (var i = 0; i < 5; i++) {
        await scoring.rallyWonBy(Side.a);
        // Between games the scorer confirms the ends before play goes on.
        if (i == 1) await scoring.setEndChange(1, switched: true);
      }
      final match = c.read(scoringControllerProvider)!;
      expect(match.score.games, const [GameScore(2, 0), GameScore(2, 0)]);
      expect(match.score.winner, Side.a);
      expect(match.finishedAt, isNotNull);
    });

    test('ignores taps after the match is over', () async {
      final c = await container();
      final scoring = c.read(scoringControllerProvider.notifier);
      await scoring.start(doubles(rules: const MatchRules(pointsToWin: 1, winByTwo: false, bestOf: 1)));
      await scoring.rallyWonBy(Side.b);
      final events = c.read(scoringControllerProvider)!.events.length;
      await scoring.rallyWonBy(Side.a);
      expect(c.read(scoringControllerProvider)!.events, hasLength(events));
    });

    test('undo takes back the winning point and reopens the match', () async {
      final c = await container();
      final scoring = c.read(scoringControllerProvider.notifier);
      await scoring.start(doubles(rules: const MatchRules(pointsToWin: 1, winByTwo: false, bestOf: 1)));
      await scoring.rallyWonBy(Side.b);
      await scoring.undo();
      final match = c.read(scoringControllerProvider)!;
      expect(match.finishedAt, isNull);
      expect(match.score.isOver, isFalse);
    });

    test('survives the app being killed mid-match', () async {
      final first = await container();
      await first.read(scoringControllerProvider.notifier).start(doubles());
      await first.read(scoringControllerProvider.notifier).rallyWonBy(Side.a);
      await first.read(scoringControllerProvider.notifier).rallyWonBy(Side.b);
      final before = first.read(scoringControllerProvider)!;

      final relaunched = await container();
      final after = relaunched.read(scoringControllerProvider)!;
      expect(after.id, before.id);
      expect(after.events.map((e) => e.id), before.events.map((e) => e.id));
      expect(after.score.currentGame, before.score.currentGame);
      expect(after.score.serve, before.score.serve);
    });

    test('closing a finished match clears it from the phone', () async {
      final c = await container();
      await c.read(scoringControllerProvider.notifier).start(doubles());
      await c.read(scoringControllerProvider.notifier).close();
      final relaunched = await container();
      expect(relaunched.read(scoringControllerProvider), isNull);
    });

    test('a finished match stays in the player\'s results only once its players confirm it', () async {
      final c = await container();
      final scoring = c.read(scoringControllerProvider.notifier);
      await scoring.start(const NewMatch(
        sportId: 'pickleball',
        categoryId: 'doubles',
        sideA: ['Anand Varsada', 'Hardik Suthar'],
        sideB: ['Kamal Parmar', 'You'],
        rules: MatchRules(pointsToWin: 1, winByTwo: false, bestOf: 1),
        firstServer: Side.b,
      ));
      await scoring.rallyWonBy(Side.b);
      final id = c.read(scoringControllerProvider)!.id;
      await scoring.close();

      final relaunched = await container();
      // Home watches the history, as here.
      relaunched.listen(matchHistoryProvider, (_, _) {});
      final page = await relaunched.read(matchHistoryProvider.future);
      // Casual matches count only once verified (docs/CASUAL-VERIFICATION.md).
      expect(page.matches.map((m) => m.id), isNot(contains(id)));
      final match = await relaunched.read(matchProvider(id).future);
      expect(match.id, id);
      expect(match.mine, ['You', 'Kamal Parmar']);
      expect(match.games, [(1, 0)]);
      expect(match.won, isTrue);
      expect(match.isOfficial, isFalse);
      expect((await relaunched.read(playerRecordProvider.future)).finished.map((m) => m.id), isNot(contains(id)));
    });

    test('undoing the winning point takes the match out of the results', () async {
      final c = await container();
      final scoring = c.read(scoringControllerProvider.notifier);
      await scoring.start(const NewMatch(
        sportId: 'pickleball',
        categoryId: 'singles',
        sideA: ['You'],
        sideB: ['Vivek Rana'],
        rules: MatchRules(pointsToWin: 1, winByTwo: false, bestOf: 1),
        firstServer: Side.a,
      ));
      await scoring.rallyWonBy(Side.a);
      expect(c.read(playedMatchesProvider), hasLength(1));
      await scoring.undo();
      expect(c.read(playedMatchesProvider), isEmpty);
    });
  });

  group('screens', () {
    late DateTime clock;

    /// Time between taps as the tap guard sees it. One second unless a test
    /// sets it shorter.
    late Duration tapGap;

    Future<void> pumpSignedIn(WidgetTester tester) async {
      useReducedMotion(tester);
      clock = DateTime(2026, 9, 25, 18);
      tapGap = const Duration(seconds: 1);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          ...appOverrides(FakeAuthRepository(stored: RestoredUser(user(), fromCache: false))),
          scoringClockProvider.overrideWithValue(() => clock = clock.add(tapGap)),
          commentatorProvider.overrideWithValue(SilentCommentator()),
        ],
        child: const SkorxApp(),
      ));
      await tester.pumpAndSettle();
    }

    String points(WidgetTester tester, Side side) =>
        (tester.widget<Text>(find.byKey(Key('points-${side.name}')))).data!;
    /// Scrolls [key] into view and taps it.
    Future<void> tapKey(WidgetTester tester, String key) async {
      await tester.ensureVisible(find.byKey(Key(key)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
    }

    /// Taps a court spot, then a player in the picker.
    Future<void> pick(WidgetTester tester, String spot, String player, [String? search]) async {
      await tester.ensureVisible(find.byKey(Key(spot)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key(spot)));
      await tester.pumpAndSettle();
      if (search != null) {
        await tester.enterText(find.byKey(const Key('playerSearch')), search);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(Key(player)));
      await tester.pumpAndSettle();
    }

    String call(WidgetTester tester) => [
          for (var i = 0; i < 3; i++)
            if (find.byKey(Key('call-$i')).evaluate().isNotEmpty) tester.widget<Text>(find.byKey(Key('call-$i'))).data!,
        ].join('-');

    /// The first-time guide covers the court; these tests skip it.
    Future<void> skipTutorial(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('tutorialSkip')));
      await tester.pumpAndSettle();
    }

    testWidgets('Matches -> new doubles match -> scoring with the old app\'s POINT / SIDE OUT buttons', (tester) async {
      await pumpSignedIn(tester);
      // "Score a match" is the + on My Matches.
      await tester.tap(find.descendant(of: find.byType(SkorxNavBar), matching: find.text('Matches')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scoreMatch')));
      await tester.pumpAndSettle();

      // Step 1: format, then division (which moves on by itself).
      expect(find.text('New match'), findsOneWidget);
      await tester.tap(find.byKey(const Key('format-doubles')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('division-men')));
      await tester.pumpAndSettle();
      expect(find.text("Men's Doubles"), findsOneWidget);

      // Step 2: nobody on court yet.
      final start = find.byKey(const Key('startMatch'));
      expect(tester.widget<SxButton>(start).onPressed, isNull, reason: 'players are missing');
      expect(tester.widget<Text>(find.byKey(const Key('startHint'))).data, 'Add 4 more players');

      await pick(tester, 'court-a0', 'pickMe');
      await pick(tester, 'court-a1', 'pick-SKX-10412', 'Kamal');
      // Added by X code, typed the loose way people read it out.
      await pick(tester, 'court-b0', 'pick-SKX-10427', 'x-8avn');
      await pick(tester, 'court-b1', 'pick-SKX-10544', 'Hardik');
      // "Scoring" and "Games" default to side out and a single game.
      expect(tester.widget<Text>(find.byKey(const Key('startHint'))).data, contains('1 game'));
      await tester.ensureVisible(start);
      await tester.tap(start);
      await tester.pumpAndSettle();

      final match = ProviderScope.containerOf(tester.element(find.byType(SkorxApp))).read(scoringControllerProvider)!;
      expect(match.sideA, ['Smit Ramani', 'Kamal Parmar']);
      expect(match.sideB, ['Anand Varsada', 'Hardik Suthar']);
      expect(match.categoryId, 'mens_doubles');
      expect(match.details.court, 'Court 1');
      expect(match.details.sideAIds, ['me', 'SKX-10412']);
      await skipTutorial(tester);

      // Pickleball doubles, side-out: the first server starts as server 2.
      expect(call(tester), '0-0-2');
      expect(find.text('POINT'), findsOneWidget);
      expect(find.text('SIDE OUT'), findsOneWidget);

      await tester.tap(find.byKey(const Key('side-a')));
      await tester.pumpAndSettle();
      expect(points(tester, Side.a), '1');
      expect(call(tester), '1-0-2');

      await tester.tap(find.byKey(const Key('side-b')));
      await tester.pumpAndSettle();
      expect(points(tester, Side.a), '1', reason: 'a side out is not a point');
      expect(call(tester), '0-1-1');
      expect(find.text('2ND SERVER'), findsOneWidget, reason: 'side A would only pass serve to the 2nd server');

      await tester.tap(find.byKey(const Key('undo')));
      await tester.pumpAndSettle();
      expect(call(tester), '1-0-2');
    });

    testWidgets('mixed doubles: the pool follows the partner, guests and stars, the server moves to the right court',
        (tester) async {
      await pumpSignedIn(tester);
      await tester.tap(find.descendant(of: find.byType(SkorxNavBar), matching: find.text('Matches')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scoreMatch')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('format-mixed')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('division-men')), findsNothing, reason: "mixed has no men's division");
      await tester.tap(find.byKey(const Key('division-open')));
      await tester.pumpAndSettle();

      await pick(tester, 'court-a0', 'pick-SKX-10412');
      // Kamal's partner must be a woman: the men are gone from the list.
      await tapKey(tester, 'court-a1');
      expect(find.text('Showing Women only'), findsOneWidget);
      expect(find.byKey(const Key('pick-SKX-10427')), findsNothing);
      await tester.tap(find.byKey(const Key('star-SKX-10519')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pick-SKX-10519')));
      await tester.pumpAndSettle();

      // Guests: with no partner yet, the picker asks man or woman.
      await tapKey(tester, 'court-b0');
      await tester.enterText(find.byKey(const Key('playerSearch')), 'Raj');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('guestMale')));
      await tester.pumpAndSettle();
      await tapKey(tester, 'court-b1');
      await tester.enterText(find.byKey(const Key('playerSearch')), 'Pooja');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('addGuest')));
      await tester.pumpAndSettle();

      // Riya serves first, so she moves into the right-hand court.
      await tapKey(tester, 'serve-SKX-10519');
      final start = find.byKey(const Key('startMatch'));
      await tester.ensureVisible(start);
      await tester.tap(start);
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(tester.element(find.byType(SkorxApp)));
      final match = container.read(scoringControllerProvider)!;
      expect(match.categoryId, 'mixed_doubles');
      expect(match.sideA, ['Riya Shah', 'Kamal Parmar']);
      expect(match.sideB, ['Raj', 'Pooja']);
      expect(match.firstServer, Side.a);
      expect(container.read(starredPlayersProvider).map((p) => p.name), ['Riya Shah']);
      expect(container.read(matchSetupMemoryProvider).format, MatchFormat.mixed);
    });

    testWidgets('a double tap within the guard counts once', (tester) async {
      await pumpSignedIn(tester);
      final container = ProviderScope.containerOf(tester.element(find.byType(SkorxApp)));
      await container.read(scoringControllerProvider.notifier).start(doubles(rules: pickleballDefault));
      await tester.pump();
      // A match on the go floats over every tab, one tap from scoring.
      expect(find.byKey(const Key('resumeMatchBar')), findsOneWidget);
      await tester.tap(find.byKey(const Key('resumeMatchBar')));
      await tester.pumpAndSettle();
      await skipTutorial(tester);

      tapGap = const Duration(milliseconds: 100);
      await tester.tap(find.byKey(const Key('side-a')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('side-a')));
      await tester.pumpAndSettle();
      expect(points(tester, Side.a), '1', reason: 'the second tap came 100 ms after the first');

      tapGap = const Duration(milliseconds: 500);
      await tester.tap(find.byKey(const Key('side-a')));
      await tester.pumpAndSettle();
      expect(points(tester, Side.a), '2', reason: 'a deliberate tap half a second later counts');
    });
  });

  group('match setup', () {
    test('category ids round-trip for every format and division', () {
      for (final f in MatchFormat.values) {
        for (final d in Division.forFormat(f)) {
          expect(parseCategoryId(categoryIdFor(f, d)), (f, d));
        }
      }
      expect(categoryIdFor(MatchFormat.doubles, Division.men), 'mens_doubles');
      expect(categoryIdFor(MatchFormat.mixed, Division.kids), 'kids_mixed_doubles');
    });

    test('the division decides the player pool', () {
      const man = MatchPlayer(id: '1', name: 'A', gender: Gender.male);
      const woman = MatchPlayer(id: '2', name: 'B', gender: Gender.female);
      const girl = MatchPlayer(id: '3', name: 'C', gender: Gender.female, kid: true);
      expect([man, woman, girl].where((p) => p.fits(Division.men)), [man]);
      expect([man, woman, girl].where((p) => p.fits(Division.women)), [woman]);
      expect([man, woman, girl].where((p) => p.fits(Division.kids)), [girl]);
      expect([man, woman, girl].where((p) => p.fits(Division.open, requiredGender: Gender.female)), [woman]);
    });
  });
}

/// Commentary that stays quiet in tests and remembers what it would say.
class SilentCommentator implements Commentator {
  final lines = <String>[];

  @override
  Future<void> say(String text) async => lines.add(text);

  @override
  Future<void> stop() async {}
}
