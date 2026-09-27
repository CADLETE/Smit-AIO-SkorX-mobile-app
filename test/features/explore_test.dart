import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skorx/features/explore/explore_modules.dart';

import '../support/fakes.dart' show useInMemoryPreferences;
import 'player_app_test.dart' show goTo, openExplore, pumpSignedIn, routerOf, tapNav, tapVisible, usePhone;

String locationOf(WidgetTester tester) => routerOf(tester).routerDelegate.currentConfiguration.uri.toString();

void main() {
  setUp(useInMemoryPreferences);

  test('every open module has somewhere to go; every coming-soon one waits', () {
    for (final m in exploreModules) {
      expect(m.available, isTrue, reason: m.id);
      expect(m.location, isNotNull, reason: m.id);
    }
    for (final m in upcomingExploreModules) {
      expect(m.available, isFalse, reason: m.id);
      expect(m.location, isNull, reason: m.id);
    }
    final ids = [...exploreModules, ...upcomingExploreModules].map((m) => m.id);
    expect(ids.toSet().length, ids.length, reason: 'ids are unique');
  });

  group('Explore hub', () {
    testWidgets('lists every module, open ones first', (tester) async {
      usePhone(tester);
      await pumpSignedIn(tester);
      await openExplore(tester);
      expect(find.text('Discover everything happening on SkorX.'), findsOneWidget);
      for (final m in [...exploreModules, ...upcomingExploreModules]) {
        await tester.scrollUntilVisible(find.byKey(Key('explore-${m.id}')), 200,
            scrollable: find.byType(Scrollable).first);
        expect(find.text(m.title), findsOneWidget, reason: m.id);
      }
      expect(find.text('SOON'), findsNWidgets(upcomingExploreModules.length));
    });

    testWidgets('Tournaments, Players and Courts open inside Explore, with a way back', (tester) async {
      usePhone(tester);
      await pumpSignedIn(tester);
      for (final (id, marker) in const [
        ('tournaments', Key('filterButton')),
        ('players', Key('playerFilterButton')),
        ('courts', Key('cityPicker')),
      ]) {
        await openExplore(tester);
        await tapVisible(tester, find.byKey(Key('explore-$id')));
        expect(locationOf(tester), '/player/explore/$id');
        expect(find.byKey(marker), findsOneWidget, reason: id);
        expect(find.byKey(const Key('exploreSearch')), findsOneWidget);
        await tester.tap(find.byKey(const Key('exploreBack')));
        await tester.pumpAndSettle();
        expect(locationOf(tester), '/player/explore');
      }
    });

    testWidgets('Scores opens the Matches tab', (tester) async {
      usePhone(tester);
      await pumpSignedIn(tester);
      await openExplore(tester);
      await tapVisible(tester, find.byKey(const Key('explore-scores')));
      expect(locationOf(tester), '/player/matches');
    });

    testWidgets('Leaderboards shows the top players and opens the full rankings where it was', (tester) async {
      usePhone(tester);
      await pumpSignedIn(tester);
      await openExplore(tester);
      expect(find.text('Coming to SkorX'), findsNothing);
      expect(find.text('Your Performance'), findsNothing);
      expect(find.text('Associations'), findsNothing);
      await tapVisible(tester, find.byKey(const Key('leaderScope-state')));
      await tapVisible(tester, find.byKey(const Key('leaderFormat-mixed')));
      expect(find.byKey(const Key('leaderRow-1')), findsOneWidget, reason: 'the top of the board');
      expect(find.byKey(const Key('leaderRow-6')), findsNothing, reason: 'the hub shows the top five');
      expect(find.textContaining('(you)'), findsOneWidget, reason: 'and where you sit');
      await tapVisible(tester, find.byKey(const Key('leaderFull')));
      expect(find.text('Rankings'), findsOneWidget);
      expect(find.text('State leaderboard · Mixed'), findsOneWidget, reason: 'opens on the board Explore showed');
    });

    testWidgets('old links and deep links land in the right place', (tester) async {
      usePhone(tester);
      await pumpSignedIn(tester);
      for (final (from, to) in const [
        ('/player/explore?view=courts', '/player/explore/courts'),
        ('/player/explore?view=tournaments', '/player/explore/tournaments'),
        ('/player/tournaments', '/player/explore/tournaments'),
        ('/player/courts', '/player/explore/courts'),
        ('/player/explore/scores', '/player/matches'),
        ('/player/explore/nope', '/player/explore'),
        ('/player/explore/leaderboards', '/player/rankings'),
      ]) {
        await goTo(tester, from);
        expect(locationOf(tester), to, reason: from);
      }
    });

    testWidgets('re-tapping the Explore tab returns to the hub', (tester) async {
      usePhone(tester);
      await pumpSignedIn(tester);
      await goTo(tester, '/player/explore/players');
      await tapNav(tester, 'Explore');
      expect(locationOf(tester), '/player/explore');
    });

    testWidgets('Community opens inside Explore, with a way back and its news on the card', (tester) async {
      usePhone(tester);
      await pumpSignedIn(tester);
      expect(find.byKey(const Key('navBadge-Explore')), findsOneWidget, reason: 'Community requests and messages');
      await tapNav(tester, 'Explore');
      await tapVisible(tester, find.byKey(const Key('explore-community')));
      expect(locationOf(tester), '/player/community');
      expect(find.byKey(const Key('navBadge-Explore')), findsOneWidget, reason: 'still the Explore tab');
      await tester.tap(find.byKey(const Key('communityHubBack')));
      await tester.pumpAndSettle();
      expect(locationOf(tester), '/player/explore');
      expect(find.textContaining(RegExp(r'^\d+ NEW$')), findsOneWidget, reason: 'the Community card says what is waiting');
    });
  });
}
