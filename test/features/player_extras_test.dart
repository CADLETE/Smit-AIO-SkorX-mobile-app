import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skorx/features/onboarding/app_tour.dart';
import 'package:skorx/features/player/data/player_repository.dart';
import 'package:skorx/features/settings/app_settings.dart';
import 'package:skorx/features/settings/match_defaults_sheet.dart';
import 'package:skorx/sports/core/match_rules.dart';

import '../support/fakes.dart';
import 'player_app_test.dart' show pumpSignedIn, goTo, tapNav, usePhone, tapVisible;

void main() {
  setUp(useInMemoryPreferences);

  group('default match settings', () {
    test('survive a restart and read back in one line', () {
      const rules = MatchRules(pointsToWin: 15, winByTwo: true, bestOf: 3, scoring: ScoringSystem.sideOut);
      const s = AppSettings(matchRules: rules, matchFormat: 'singles');
      final back = AppSettings.fromJson(s.toJson());
      expect(back.matchRules, rules);
      expect(back.matchFormat, 'singles');
      expect(describeMatchDefaults(back), 'Singles · Best of 3 · Side out · to 15');
      expect(describeMatchDefaults(const AppSettings()), startsWith('Not set'));
    });

    testWidgets('a new casual match starts with them', (tester) async {
      usePhone(tester);
      final container = await pumpSignedIn(tester);
      container.read(appSettingsProvider.notifier).update(
            (s) => s.copyWith(
              matchFormat: () => 'singles',
              matchRules: () => const MatchRules(pointsToWin: 11, winByTwo: true, bestOf: 3, scoring: ScoringSystem.sideOut),
            ),
          );
      await goTo(tester, '/player/match/new?type=mens_singles');
      // Straight to setup: the rules block and the summary line show them.
      bool picked(String key) => tester
          .widget<Semantics>(find.ancestor(of: find.byKey(Key(key)), matching: find.byType(Semantics)).first)
          .properties
          .selected!;
      await tester.scrollUntilVisible(find.byKey(const Key('bestOf-3')), 300,
          scrollable: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first);
      expect(picked('bestOf-3'), isTrue);
      expect(picked('scoring-${ScoringSystem.sideOut}'), isTrue);
      expect(picked('bestOf-1'), isFalse);
    });

    testWidgets('are set from Settings', (tester) async {
      usePhone(tester);
      final container = await pumpSignedIn(tester);
      await goTo(tester, '/player/settings');
      await tapVisible(tester, find.byKey(const Key('matchDefaults')));
      await tester.tap(find.byKey(const Key('bestOf-3')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('scoring-${ScoringSystem.sideOut}')));
      await tester.pumpAndSettle();
      final s = container.read(appSettingsProvider);
      expect(s.matchRules?.bestOf, 3);
      expect(s.matchRules?.scoring, ScoringSystem.sideOut);
    });
  });

  testWidgets('the app tour walks a new player through every tab, then gets out of the way', (tester) async {
    usePhone(tester);
    final container = await pumpSignedIn(tester);
    await container.read(appTourProvider.notifier).queue();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tourNext')), findsOneWidget);

    for (final kicker in ['HOME', 'MATCHES', 'EXPLORE', 'MY PADDLE', 'ACCOUNT', "YOU'RE SET"]) {
      await tester.tap(find.byKey(const Key('tourNext')));
      await tester.pumpAndSettle();
      expect(find.text(kicker), findsOneWidget);
    }
    await tester.tap(find.byKey(const Key('tourDone')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tourNext')), findsNothing);
    expect(container.read(appTourProvider).active, isFalse);

    // Replayable from Settings.
    await tapNav(tester, 'Account');
    await goTo(tester, '/player/settings');
    await tapVisible(tester, find.byKey(const Key('replayTour')));
    expect(find.byKey(const Key('tourSkip')), findsOneWidget);
  });

  test('there are plenty of badges to chase, on shelves', () async {
    final all = await const EmptyPlayerRepository().achievements();
    expect(all.length, greaterThanOrEqualTo(60));
    expect(all.map((a) => a.id).toSet().length, all.length, reason: 'ids are unique');
    expect(all.map((a) => a.category).toSet().length, greaterThanOrEqualTo(8));
    expect(all.every((a) => !a.unlocked && a.progress == 0), isTrue, reason: 'a newcomer starts from zero');
  });
}
