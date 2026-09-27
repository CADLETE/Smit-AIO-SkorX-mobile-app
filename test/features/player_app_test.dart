import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:skorx/app/app.dart';
import 'package:skorx/app/routing/router.dart';
import 'package:skorx/core/sample_persona.dart';
import 'package:skorx/design/design.dart';
import 'package:skorx/features/auth/data/auth_repository.dart';
import 'package:skorx/features/matches/data/journey.dart';
import 'package:skorx/features/matches/data/match.dart';
import 'package:skorx/features/matches/data/match_feed.dart';
import 'package:skorx/features/matches/data/match_repository.dart';
import 'package:skorx/features/matches/data/sample_universe.dart' show sampleUniverseProvider;
import 'package:skorx/features/paddle/data/my_play.dart';
import 'package:skorx/features/player/data/player_repository.dart';
import 'package:skorx/features/shell/workspace_shell.dart';
import 'package:skorx/features/tournaments/data/tournaments.dart' show PlaceFilter;
import 'package:skorx/shared/format.dart';

import '../support/fakes.dart';

/// Renders at a real phone size, so anything that does not fit fails the test.
void usePhone(WidgetTester tester, [Size size = const Size(390, 844)]) {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<ProviderContainer> pumpSignedIn(WidgetTester tester, {SamplePersona persona = SamplePersona.regular}) async {
  useReducedMotion(tester);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      ...appOverrides(FakeAuthRepository(stored: RestoredUser(user(), fromCache: false))),
      samplePersonaProvider.overrideWith(() => _FixedPersona(persona)),
    ],
    child: const SkorxApp(),
  ));
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(SkorxApp)));
}

class _FixedPersona extends SamplePersonaController {
  _FixedPersona(this.persona);

  final SamplePersona persona;

  @override
  SamplePersona build() => persona;
}

GoRouter routerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(SkorxApp))).read(routerProvider);

Future<void> goTo(WidgetTester tester, String location) async {
  routerOf(tester).go(location);
  await tester.pumpAndSettle();
}

Finder navLabel(String label) => find.descendant(
      of: find.byType(SkorxNavBar),
      matching: find.byWidgetPredicate((w) => w is Text && w.data?.toLowerCase() == label.toLowerCase()),
    );

Future<void> tapNav(WidgetTester tester, String label) async {
  await tester.tap(navLabel(label));
  await tester.pumpAndSettle();
}

/// Every Community screen, for the screen-size checks.
final communityScreens = [
  '/player/community',
  '/player/community/search',
  '/player/community/search?q=referee%20near%20Ahmedabad',
  for (final s in ['players', 'officials', 'organizers', 'training', 'places', 'media', 'business'])
    '/player/community/browse/$s',
  '/player/community/people/cm-rohan',
  '/player/community/people/cm-kavya',
  '/player/community/places/pl-cadlete',
  '/player/community/places/pl-smashacad',
  '/player/community/places/pl-kitchenline',
  '/player/community/groups',
  '/player/community/groups/g-guj-refs',
  '/player/community/messages',
  '/player/community/messages/cv-kavya',
  '/player/community/me',
  '/player/community/connections?tab=requests',
  '/player/community/saved',
  '/player/community/events',
  '/player/community/events/ev-clinic',
  '/player/community/events/ev-women',
  '/player/community/events/new',
  '/player/community/posts',
  '/player/community/posts/ps-win',
  '/player/community/groups/g-bodakdev',
];

Future<void> openExplore(WidgetTester tester) => tapNav(tester, 'Explore');

/// Community is a module inside the Explore tab.
Future<void> openCommunity(WidgetTester tester) async {
  await tapNav(tester, 'Explore');
  await tapVisible(tester, find.byKey(const Key('explore-community')));
}

/// The page's main, vertical scroll view.
Finder get pageScroll => find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first;

/// Scrolls until [finder] is on screen and taps it.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 250, scrollable: pageScroll);
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Scrolls the page's main list to the end, so every lazily built item is
/// laid out once.
Future<void> scrollThrough(WidgetTester tester) async {
  if (find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).evaluate().isEmpty) return;
  for (var i = 0; i < 6; i++) {
    await tester.drag(pageScroll, const Offset(0, -600), warnIfMissed: false);
    await tester.pumpAndSettle();
  }
}

void main() {
  setUp(useInMemoryPreferences);

  final tomorrow = isoDay(DateTime.now().add(const Duration(days: 1)));
  final screens = [
    '/player/home',
    '/player/matches',
    '/player/matches?view=live',
    '/player/matches?view=upcoming',
    '/player/matches?view=completed',
    '/player/matches?view=tournaments',
    '/player/players/me',
    '/player/players/SKX-10611',
    '/player/players/Rahul%20Mehta',
    '/player/players/me/vs/SKX-10611',
    '/player/paddle/matches',
    '/player/paddle/matches?category=tournament',
    '/player/paddle/tournament/t-league',
    '/player/paddle/tournament/t-open',
    '/player/tournament/t-spt-amd?view=matches',
    '/player/explore',
    ...communityScreens,
    '/player/explore?view=courts',
    '/player/explore/tournaments',
    '/player/explore/players',
    '/player/explore/leaderboards',
    '/player/paddle',
    '/player/profile',
    '/player/matches/lg-qf1',
    '/player/matches/lg-qf3',
    '/player/matches/fr-live',
    '/player/matches/lg-sf1',
    '/player/matches/mo-f',
    '/player/matches/fr-x',
    '/player/matches/lg-b1',
    '/player/matches/not-a-match',
    '/player/tournament/t-league',
    '/player/tournament/t-league?view=matches',
    '/player/tournament/t-league?view=standings',
    '/player/tournament/t-league?view=about',
    '/player/tournament/t-monsoon',
    '/player/tournament/t-open',
    '/player/tournament/t-blitz',
    '/player/tournament/t-juniors?view=standings',
    '/player/tournaments/mine',
    '/player/venue/v-blitz?date=$tomorrow',
    '/player/venue/v-blitz/confirm?date=$tomorrow&hour=19&court=2',
    '/player/bookings',
    '/player/rankings',
    '/player/achievements',
    '/player/notifications',
    '/player/settings',
    '/player/edit-profile',
  ];

  group('every Player screen lays out', () {
    for (final (size, dark) in const [
      (Size(390, 844), false),
      (Size(360, 690), true),
      (Size(1180, 820), false),
    ]) {
      testWidgets('at ${size.width.toInt()}×${size.height.toInt()} ${dark ? 'dark' : 'light'}', (tester) async {
        usePhone(tester, size);
        if (dark) {
          tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
          addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        }
        await pumpSignedIn(tester);
        for (final screen in screens) {
          debugPrint('SCREEN $screen');
          await goTo(tester, screen);
          await scrollThrough(tester);
        }
      });
    }

    testWidgets('for a brand-new player, with every empty state', (tester) async {
      usePhone(tester, const Size(360, 690));
      await pumpSignedIn(tester, persona: SamplePersona.newcomer);
      for (final screen in [
        '/player/home',
        '/player/matches',
        '/player/matches?view=results',
        '/player/matches?view=tournaments',
        '/player/explore',
        ...communityScreens,
        '/player/explore/tournaments',
        '/player/explore/players',
        '/player/paddle',
        '/player/paddle/matches',
        '/player/players/me',
        '/player/profile',
        '/player/tournaments/mine',
        '/player/bookings',
        '/player/rankings',
        '/player/achievements',
        '/player/notifications',
        '/player/tournament/t-open',
      ]) {
        debugPrint('SCREEN (new) $screen');
        await goTo(tester, screen);
        await scrollThrough(tester);
      }
    });
  });

  group('Home answers "what matters now"', () {
    testWidgets('a live match leads, then the last result, three actions and three numbers', (tester) async {
      usePhone(tester);
      final container = await pumpSignedIn(tester);

      expect(find.byKey(const Key('nowCard')), findsOneWidget);
      expect(find.text('LIVE · GAME 2'), findsOneWidget);
      expect(find.text('QUARTER-FINAL'), findsOneWidget);
      expect(find.textContaining(RegExp(r'^Semi-final · ')), findsOneWidget, reason: 'what comes after the live match');
      await tester.scrollUntilVisible(find.byKey(const Key('snapshot')), 300, scrollable: pageScroll);
      expect(find.byKey(const Key('lastResult')), findsOneWidget);
      for (final key in ['quickStartMatch', 'quickTournaments', 'quickMatches']) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      }
      final season = container.read(sampleUniverseProvider).season;
      expect(find.text(ratingText(season.career.overallSpi)), findsWidgets, reason: 'SkorX Rating in the header and the snapshot');
      expect(find.text(sxpText(season.currentPoints)), findsOneWidget, reason: 'SkorX Points in the snapshot');
    });

    testWidgets('a new player gets a welcome with three ways in, not empty cards', (tester) async {
      usePhone(tester);
      await pumpSignedIn(tester, persona: SamplePersona.newcomer);
      expect(find.byKey(const Key('welcome')), findsOneWidget);
      expect(find.byKey(const Key('nowCard')), findsNothing);
      expect(find.byKey(const Key('lastResult')), findsNothing);

      await tester.tap(find.byKey(const Key('welcomeTournament')));
      await tester.pumpAndSettle();
      expect(find.text('SKORX OPEN 2026'), findsOneWidget, reason: 'lands on tournament discovery');
    });
  });

  // The brief's final design test: a player who has never used SkorX, no
  // instructions. Every task starts on Home and must be reachable in a few
  // obvious taps.
  group('a first-time player can', () {
    testWidgets('1–5: find the next match, the last result and its score, the tournament and their journey',
        (tester) async {
      usePhone(tester);
      await pumpSignedIn(tester);

      // 1. Next match: My Paddle › Up next.
      await tapNav(tester, 'My Paddle');
      expect(find.byKey(const Key('upNext')), findsOneWidget);
      expect(find.text('Winner of QF 2'), findsOneWidget, reason: 'the semi-final is next');

      // 2–3. Previous match and its score: Home › Last result.
      await tapNav(tester, 'Home');
      await tapVisible(tester, find.byKey(const Key('lastResult')));
      expect(find.text('LOST 0–2'), findsOneWidget);
      expect(find.text('12'), findsWidgets, reason: 'the scoreboard shows the games');
      expect(find.byKey(const Key('matchImpact')), findsOneWidget);

      // 4. Its tournament.
      await tapVisible(tester, find.byKey(const Key('viewTournament')));
      expect(find.text('AHMEDABAD PICKLE LEAGUE'), findsOneWidget);

      // 5. Where am I in it?
      expect(find.byKey(const Key('journeyRail')), findsOneWidget);
      expect(find.text('PLAYING THE QUARTER-FINAL'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('journeyRail')), matching: find.text('WON')), findsNWidgets(2),
          reason: 'two pool wins');
    });

    testWidgets('6–8: find their rating, ranking and achievements', (tester) async {
      usePhone(tester);
      await pumpSignedIn(tester);
      expect(find.byKey(const Key('headerRating')), findsOneWidget);

      await tapNav(tester, 'My Paddle');
      // Achievements have their own highlighted card, above the rating.
      await tapVisible(tester, find.byKey(const Key('allAchievements')));
      expect(find.text('Achievements'), findsOneWidget);
      expect(find.textContaining('Getting started ·'), findsOneWidget, reason: 'badges sit on shelves by kind');
      await tester.tap(find.byKey(const Key('badgeFilter-unlocked')));
      await tester.pumpAndSettle();
      expect(find.text('Bagel'), findsNothing, reason: 'not unlocked yet');
      await tester.tap(find.byKey(const Key('back')));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.byKey(const Key('ratingSection')), 300, scrollable: pageScroll);
      await tester.scrollUntilVisible(find.byKey(const Key('rankingSection')), 300, scrollable: pageScroll);
      expect(find.text('#14'), findsOneWidget);
      await tester.scrollUntilVisible(find.byKey(const Key('pointsSection')), 300, scrollable: pageScroll);
      expect(find.byKey(const Key('skorxBands')), findsOneWidget, reason: 'the rating shows its band');
      expect(find.byKey(const Key('arcLevel')), findsOneWidget, reason: 'the level sits with the points');
    });

    testWidgets('9: find a tournament and register', (tester) async {
      usePhone(tester);
      await pumpSignedIn(tester);
      await tapVisible(tester, find.byKey(const Key('quickTournaments')));

      await tapVisible(tester, find.text('PICKLE BLITZ NIGHT SERIES'));
      await tester.tap(find.byKey(const Key('registerNow')));
      await tester.pumpAndSettle();
      final confirm = find.byKey(const Key('confirmRegistration'));
      expect(tester.widget<SxButton>(confirm).onPressed, isNull, reason: 'doubles needs a partner');
      await tester.enterText(find.byKey(const Key('partnerField')), 'Kamal Parmar');
      await tester.pump();
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(find.text("YOU'RE IN"), findsOneWidget);

      await tester.tap(find.byKey(const Key('viewMyRegistration')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('journeyRail')), findsOneWidget, reason: 'registered: the hub opens on My journey');
    });

    testWidgets('10: book a court: location, date, time, court, confirm', (tester) async {
      usePhone(tester);
      final semantics = tester.ensureSemantics();
      await pumpSignedIn(tester);
      await openExplore(tester);
      await tapVisible(tester, find.text('Courts'));
      expect(find.byKey(const Key('cityPicker')), findsOneWidget);

      // Tomorrow, so every slot is in the future.
      await tester.tap(find.bySemanticsLabel('Tomorrow'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Pickle Blitz Arena'));

      // Booking is on the venue page itself: a time, then a court.
      final continueButton = find.byKey(const Key('continueBooking'));
      expect(tester.widget<SxButton>(continueButton).onPressed, isNull, reason: 'nothing picked yet');
      final time = find.bySemanticsLabel(RegExp(r'courts? free$')).first;
      await tester.ensureVisible(time);
      await tester.pumpAndSettle();
      await tester.tap(time);
      await tester.pumpAndSettle();
      expect(tester.widget<SxButton>(continueButton).onPressed, isNotNull, reason: 'a free court is picked for you');
      expect(find.bySemanticsLabel(RegExp(r'^Court \d+, free$')), findsWidgets, reason: 'the court map shows what is free');
      await tester.tap(continueButton);
      await tester.pumpAndSettle();

      expect(find.text('CONFIRM'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirmAndPay')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('bookingCode')), findsOneWidget, reason: 'a code to show at the desk');

      await tester.tap(find.byKey(const Key('toMyBookings')));
      await tester.pumpAndSettle();
      expect(find.text('Pickle Blitz Arena'), findsWidgets);
      semantics.dispose();
    });

    testWidgets('11: find settings and switch to light or dark', (tester) async {
      usePhone(tester);
      await pumpSignedIn(tester);
      await tapNav(tester, 'Account');
      await tester.tap(find.byKey(const Key('openSettings')));
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);

      Brightness brightness() => Theme.of(tester.element(find.text('Settings'))).brightness;
      await tester.tap(find.byKey(const Key('theme-Dark')));
      await tester.pumpAndSettle();
      expect(brightness(), Brightness.dark);
      await tester.tap(find.byKey(const Key('theme-Light')));
      await tester.pumpAndSettle();
      expect(brightness(), Brightness.light);
    });
  });

  testWidgets('my match history loads a page at a time and groups by month', (tester) async {
    usePhone(tester);
    final container = await pumpSignedIn(tester);
    await goTo(tester, '/player/paddle/matches');
    expect(find.text('This month'), findsOneWidget);
    expect(container.read(myMatchesProvider(MatchCategory.casual)).value!.matches, hasLength(20));

    await scrollThrough(tester);
    await scrollThrough(tester);
    final page = container.read(myMatchesProvider(MatchCategory.casual)).value!;
    expect(page.matches.length, greaterThan(20));
    expect(page.matches.every((m) => m.involvesMe && m.tournament == null), isTrue, reason: 'only my casual matches');
  });

  testWidgets('reading notifications and answering match requests clears the bell', (tester) async {
    usePhone(tester);
    await pumpSignedIn(tester);
    final bell = find.byKey(const Key('notificationsBell'));
    expect(tester.widget<SxIconAction>(bell).dot, isTrue);

    await tester.tap(bell);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('markAllRead')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('back')));
    await tester.pumpAndSettle();
    // Match requests keep the dot until they are answered.
    expect(tester.widget<SxIconAction>(bell).dot, isTrue);

    await tester.tap(bell);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('acceptAll')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmAcceptAll')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('back')));
    await tester.pumpAndSettle();
    expect(tester.widget<SxIconAction>(bell).dot, isFalse);
  });

  testWidgets('a new player still sees SkorX in Matches, and how to start in My Paddle', (tester) async {
    usePhone(tester);
    await pumpSignedIn(tester, persona: SamplePersona.newcomer);
    await tapNav(tester, 'Matches');
    expect(find.byKey(const Key('liveNow')), findsOneWidget, reason: 'other players are on court');

    await tapNav(tester, 'My Paddle');
    expect(find.text('No casual matches yet'), findsOneWidget);
    expect(find.byKey(const Key('playFirstMatch')), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('noTournamentsYet')), 300, scrollable: pageScroll);
    await tester.scrollUntilVisible(find.byKey(const Key('unrated')), 300, scrollable: pageScroll);
  });

  group('one connected season', () {
    final season = SampleSeason(DateTime(2026, 9, 25, 14));
    final mine = season.matches.where((m) => m.involvesMe).toList();

    test('rating changes add up to the rating in the header', () {
      final rated = mine.where((m) => m.isCompleted).toList()..sort((a, b) => a.playedAt.compareTo(b.playedAt));
      expect(rated.last.pointsAfter, season.currentPoints);
      for (var i = 1; i < rated.length; i++) {
        expect(rated[i].pointsBefore, rated[i - 1].pointsAfter, reason: rated[i].id);
      }
    });

    test('every tournament match points at a real round', () {
      for (final m in mine.where((m) => m.tournament != null)) {
        final rounds = season.rounds[m.tournament!.id]!;
        expect(rounds.map((r) => r.name), contains(m.tournament!.round), reason: m.id);
      }
    });

    List<Match> inTournament(String id) => mine.where((m) => m.tournament?.id == id).toList();

    test('the league journey: registered, 2–1 in the pool, quarter-final live, semi next', () {
      final j = buildJourney(
        category: "Men's Doubles · Intermediate",
        registeredAt: DateTime(2026, 9, 1),
        rounds: season.rounds['t-league']!,
        myMatches: inTournament('t-league'),
      );
      expect(j.steps.map((s) => s.state), [
        JourneyState.done,
        JourneyState.won,
        JourneyState.won,
        JourneyState.lost,
        JourneyState.live,
        JourneyState.ahead,
        JourneyState.ahead,
      ]);
      expect(j.headline, 'Playing the quarter-final');
      expect(j.current?.match?.id, 'lg-qf1');
    });

    test('the monsoon journey ends as runner-up', () {
      final j = buildJourney(
        category: 'Mixed Doubles · Open',
        registeredAt: DateTime(2026, 8, 1),
        rounds: season.rounds['t-monsoon']!,
        myMatches: inTournament('t-monsoon'),
      );
      expect(j.headline, 'Runner-up');
      expect(j.won, 3);
      expect(j.lost, 2);
    });

    test('a knockout loss strikes out the rounds after it', () {
      final rounds = season.rounds['t-monsoon']!;
      final lostQf = inTournament('t-monsoon').map((m) {
        if (m.tournament!.round != 'Quarter-final') return m;
        return Match(
          id: m.id,
          status: MatchStatus.completed,
          kind: m.kind,
          format: m.format,
          mine: m.mine,
          theirs: m.theirs,
          scheduledAt: m.scheduledAt,
          games: const [(5, 11), (6, 11)],
          tournament: m.tournament,
        );
      }).where((m) => ['Group B · Match 1', 'Group B · Match 2', 'Quarter-final'].contains(m.tournament!.round));
      final j = buildJourney(category: 'x', registeredAt: DateTime(2026), rounds: rounds, myMatches: lostQf.toList());
      expect(j.headline, 'Out in the quarter-final');
      expect(j.steps.skip(4).map((s) => s.state), everyElement(JourneyState.out));
    });

    test('registered with no draw yet: the first round is next', () {
      final j = buildJourney(category: 'x', registeredAt: DateTime(2026), rounds: season.rounds['t-open']!, myMatches: const []);
      expect(j.steps[1].state, JourneyState.next);
      expect(j.steps.skip(2).map((s) => s.state), everyElement(JourneyState.ahead));
    });

    test('pool tables rank by wins, then point difference, and mark the player', () {
      final tables = computeStandings(season.matches.where((m) => m.tournament?.id == 't-league').toList());
      expect(tables.map((t) => t.pool), ['Pool A', 'Pool B']);
      final a = tables.first.rows;
      expect(a.map((r) => r.won), [2, 2, 2, 0]);
      expect(a[1].isMe, isTrue, reason: 'second in the pool on point difference');
      expect(a.first.team, 'Dev & Arjun');
    });

    test('the record is worked out from matches only', () {
      final r = PlayerRecord(season.matches);
      expect(r.played, mine.where((m) => m.isCompleted).length);
      expect(r.wins + r.losses, r.played);
      expect(r.tournamentsPlayed, 2);
    });
  });

  group('the connected SkorX ecosystem', () {
    testWidgets('player tap → Quick View → full stats → rival → head-to-head → match → tournament', (tester) async {
      usePhone(tester);
      await pumpSignedIn(tester);
      await goTo(tester, '/player/matches/fr-1'); // You beat Dev Patel.

      // Tap the opponent on the scoreboard: the Quick View, not a new page.
      await tester.tap(find.text('Dev Patel').first);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('playerQuickView')), findsOneWidget);
      expect(find.textContaining('SKX-10611'), findsOneWidget);
      expect(find.text('SKORX RATING'), findsOneWidget);
      expect(find.text('FORM'), findsOneWidget);
      expect(find.byKey(const Key('quickViewHeadToHead')), findsOneWidget, reason: 'they have played the signed-in player');

      await tester.ensureVisible(find.byKey(const Key('viewFullStats')));
      await tester.tap(find.byKey(const Key('viewFullStats')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('playerOverview')), findsOneWidget);
      expect(find.text('Dev Patel'), findsWidgets);

      await tester.scrollUntilVisible(find.byKey(const Key('currentForm')), 300, scrollable: pageScroll);
      await tester.scrollUntilVisible(find.byKey(const Key('rivals')), 300, scrollable: pageScroll);
      await tapVisible(tester, find.byKey(const Key('rival-me')));
      expect(find.byKey(const Key('headToHead')), findsOneWidget);
      expect(find.byKey(const Key('h2hScore')), findsOneWidget);

      final history = find.descendant(of: find.byKey(const Key('headToHead')), matching: find.byType(MatchRow));
      await tester.scrollUntilVisible(history.first, 300, scrollable: pageScroll);
      await tester.tap(history.first);
      await tester.pumpAndSettle();
      expect(find.byType(Scoreboard), findsOneWidget, reason: 'the match detail');
    });

    testWidgets('a tournament match leads to its tournament and its matches', (tester) async {
      usePhone(tester);
      await pumpSignedIn(tester);
      await goTo(tester, '/player/matches?view=tournaments');
      await tapVisible(tester, find.byKey(const Key('activity-t-spt-amd')));
      expect(find.text('SPT 2026 AHMEDABAD'), findsOneWidget);
      expect(find.byType(MatchRow), findsWidgets, reason: 'the tournament opens on its matches');
    });

    testWidgets('Matches is the whole SkorX universe: live first, filtered by place, found by search', (tester) async {
      usePhone(tester);
      final container = await pumpSignedIn(tester);
      await tapNav(tester, 'Matches');
      expect(find.byKey(const Key('liveNow')), findsOneWidget);
      expect(find.byKey(const Key('fromTournaments')), findsOneWidget);
      await tester.scrollUntilVisible(find.byKey(const Key('latestResults')), 300, scrollable: pageScroll);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('latestResults')), findsOneWidget, reason: 'results sit side by side like Live now');
      await tester.ensureVisible(find.byKey(const Key('matchFilters')));
      await tester.pumpAndSettle();

      // Location from the filter sheet: India › Maharashtra.
      await tester.tap(find.byKey(const Key('matchFilters')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('place-India')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('place-Maharashtra')));
      await tester.pumpAndSettle();
      expect(container.read(matchQueryProvider).place, const PlaceFilter(country: 'India', region: 'Maharashtra'),
          reason: 'filters apply as they are picked');
      await tester.ensureVisible(find.byKey(const Key('showMatches')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('showMatches')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('matchFilterSheet')), findsNothing);
      expect(find.byKey(const Key('remove-Maharashtra')), findsOneWidget, reason: 'the active filter shows as a chip');
      final q = container.read(matchQueryProvider);
      final page = container.read(matchFeedProvider(q.copyWith(status: () => MatchStatus.completed))).value!;
      expect(page.matches, isNotEmpty);
      expect(page.matches.every((m) => m.place!.region == 'Maharashtra'), isTrue);

      // Remove it with its ×.
      await tester.tap(find.byKey(const Key('remove-Maharashtra')));
      await tester.pumpAndSettle();
      expect(container.read(matchQueryProvider).place.isAny, isTrue);

      // Search: "SPT" suggests the tour's tournaments.
      await tester.tap(find.byKey(const Key('matchSearch')));
      await tester.enterText(find.byKey(const Key('matchSearch')), 'SPT');
      await tester.pumpAndSettle();
      expect(find.text('SPT 2026 Surat'), findsOneWidget);
      await tester.tap(find.text('SPT 2026 Surat'));
      await tester.pumpAndSettle();
      expect(container.read(matchQueryProvider).tournamentId, 't-spt-surat');
      expect(find.byKey(const Key('remove-SPT 2026 Surat')), findsOneWidget);

      // Nothing matches: a helpful empty state.
      container.read(matchQueryProvider.notifier).update((q) => q.copyWith(status: () => MatchStatus.live));
      await tester.pumpAndSettle();
      expect(find.text('No matches found'), findsOneWidget);
      await tester.tap(find.byKey(const Key('clearMatchFilters')));
      await tester.pumpAndSettle();
      expect(container.read(matchQueryProvider).tournamentId, isNull);
    });

    testWidgets('My Paddle: my tournament shows only my matches in it', (tester) async {
      usePhone(tester);
      await pumpSignedIn(tester);
      await tapNav(tester, 'My Paddle');
      await tester.scrollUntilVisible(find.byKey(const Key('my-casual')), 300, scrollable: pageScroll);
      await tester.scrollUntilVisible(find.byKey(const Key('myTournaments')), 300, scrollable: pageScroll);
      await tapVisible(tester, find.byKey(const Key('myTournament-t-league')));
      expect(find.byKey(const Key('myTournamentMatches')), findsOneWidget);
      await scrollThrough(tester);
      final rows = tester.widgetList<MatchRow>(find.byType(MatchRow)).map((r) => r.match).toList();
      expect(rows, isNotEmpty);
      expect(rows.every((m) => m.involvesMe), isTrue, reason: 'never the rest of the draw');
      expect(find.text('Nikhil'), findsNothing, reason: 'Karan & Nikhil never played the player');
    });

    testWidgets('Account has no X code', (tester) async {
      usePhone(tester);
      await pumpSignedIn(tester);
      await tapNav(tester, 'Account');
      await scrollThrough(tester);
      expect(find.textContaining(RegExp('x code', caseSensitive: false)), findsNothing);
      expect(find.byKey(const Key('myXCode')), findsNothing);
      expect(find.byKey(const Key('idCardXCode')), findsNothing);
    });

    testWidgets('a leaderboard name opens the Quick View', (tester) async {
      usePhone(tester);
      await pumpSignedIn(tester);
      await goTo(tester, '/player/rankings');
      await tapVisible(tester, find.text('Kavya Mehta'));
      expect(find.byKey(const Key('playerQuickView')), findsOneWidget);
      expect(find.textContaining('SKX-10388'), findsOneWidget);
    });
  });

  group('format', () {
    test('rupees use Indian grouping', () {
      expect(formatInr(500), '₹500');
      expect(formatInr(200000), '₹2,00,000');
      expect(formatInr(0), 'Free');
    });

    test('signed numbers use a real minus', () {
      expect(signed(18), '+18');
      expect(signed(-12), '−12');
    });

    test('side labels are short and put You first', () {
      expect(sideLabel(const ['You', 'Kamal Parmar']), 'You & Kamal');
      expect(sideLabel(const ['Vivek Rana']), 'Vivek Rana');
      expect(sideLabel(const []), 'TBD');
    });

    test('initials', () {
      expect(initials('Smit Ramani'), 'SR');
      expect(initials('  '), '?');
    });
  });

  test('PlayCategory labels', () => expect(PlayCategory.mixed.label, 'Mixed'));
}
