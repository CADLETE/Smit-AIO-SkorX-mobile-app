import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:skorx/app/app.dart';
import 'package:skorx/app/routing/router.dart';
import 'package:skorx/features/auth/data/auth_repository.dart';
import 'package:skorx/features/casual_match/ui/scoring_screen.dart' show scoringClockProvider;
import 'package:skorx/features/organizer/data/organizer_repository.dart';
import 'package:skorx/features/organizer/data/sample_organizer_repository.dart';
import 'package:skorx/features/organizer/data/tms_models.dart';
import 'package:skorx/features/shell/workspace_shell.dart';

import '../../support/fakes.dart';

var _tick = DateTime(2026);

const everything = {
  'editTournament',
  'managePlayers',
  'manageCheckIn',
  'manageSchedule',
  'managePayments',
  'viewAnalytics',
  'manageSettings',
  'scoreMatch',
};

void usePhone(WidgetTester tester, [Size size = const Size(360, 690)]) {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> pumpOrganizer(WidgetTester tester, {String role = 'owner', Set<String> capabilities = everything}) async {
  useReducedMotion(tester);
  // The app opens in the Player workspace. Boot on a roomy screen so these
  // tests measure only organiser screens, then return to the phone size.
  final phone = tester.view.physicalSize;
  tester.view.physicalSize = const Size(1200, 2400) * 3;
  await tester.pumpWidget(ProviderScope(
    overrides: [
      ...appOverrides(FakeAuthRepository(
        stored: RestoredUser(user(memberships: [membership('org1', 'CADLETE Pickleball', role, capabilities)]), fromCache: false),
      )),
      // Each tap is a second apart, clear of the double-tap guard.
      scoringClockProvider.overrideWithValue(() => _tick = _tick.add(const Duration(seconds: 1))),
    ],
    child: const SkorxApp(),
  ));
  await tester.pumpAndSettle();
  await goTo(tester, '/org/org1/home');
  tester.view.physicalSize = phone;
  await tester.pumpAndSettle();
}

ProviderContainer containerOf(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(SkorxApp)));

GoRouter routerOf(WidgetTester tester) => containerOf(tester).read(routerProvider);

Future<void> goTo(WidgetTester tester, String location) async {
  routerOf(tester).go(location);
  await tester.pumpAndSettle();
}

SampleOrganizerRepository serverOf(WidgetTester tester) => containerOf(tester).read(sampleOrganizerRepositoryProvider);

Finder navLabel(String label) => find.descendant(of: find.byType(SkorxNavBar), matching: find.text(label));

Future<void> scrollThrough(WidgetTester tester) async {
  final scrollables = find.byType(Scrollable);
  if (scrollables.evaluate().isEmpty) return;
  for (var i = 0; i < 8; i++) {
    await tester.drag(scrollables.first, const Offset(0, -500), warnIfMissed: false);
    await tester.pumpAndSettle();
  }
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  final vertical = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down);
  await tester.scrollUntilVisible(finder, 200, scrollable: vertical.first);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUp(useInMemoryPreferences);

  group('every organiser screen lays out on a small phone', () {
    const screens = [
      '/org/org1/home',
      '/org/org1/tournaments',
      '/org/org1/live',
      '/org/org1/check-in',
      '/org/org1/players',
      '/org/org1/profile',
      '/org/org1/more',
      '/org/org1/new-tournament',
      '/org/org1/t/t-summer',
      '/org/org1/t/t-night',
      '/org/org1/t/t-league',
      '/org/org1/t/t-diwali',
      '/org/org1/t/t-spring',
      '/org/org1/t/t-night/registrations',
      '/org/org1/t/t-summer/check-in',
      '/org/org1/t/t-summer/draw',
      '/org/org1/t/t-league/draw',
      '/org/org1/t/t-summer/schedule',
      '/org/org1/t/t-summer/courts',
      '/org/org1/t/t-summer/results',
      '/org/org1/t/t-spring/results',
      '/org/org1/t/t-summer/announce',
      '/org/org1/finance',
      '/org/org1/analytics',
      '/org/org1/staff',
      '/org/org1/audit',
      '/org/org1/profile/public',
      '/org/org1/dashboard',
    ];
    for (final screen in screens) {
      testWidgets(screen, (tester) async {
        usePhone(tester);
        await pumpOrganizer(tester);
        await goTo(tester, screen);
        await scrollThrough(tester);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the match console', (tester) async {
      usePhone(tester);
      await pumpOrganizer(tester);
      final live = (await serverOf(tester).matches('t-summer')).firstWhere((m) => m.state == MatchState.live);
      await goTo(tester, '/org/org1/t/t-summer/match/${live.id}');
      expect(find.byKey(const Key('syncBar')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('home leads with the live tournament and what needs attention', (tester) async {
    usePhone(tester, const Size(390, 844));
    await pumpOrganizer(tester);
    expect(find.byKey(const Key('liveCommandCard')), findsOneWidget);
    expect(find.text('SKORX SUMMER OPEN 2026'), findsWidgets);
    expect(find.text('Needs attention'), findsOneWidget);
    for (final tab in ['Home', 'Live', 'Check-in', 'Players', 'Profile']) {
      expect(navLabel(tab), findsOneWidget, reason: tab);
    }
  });

  testWidgets('the top-right Actions button opens every tool for the running tournament', (tester) async {
    usePhone(tester, const Size(390, 844));
    await pumpOrganizer(tester);
    await tester.tap(find.byKey(const Key('orgActions')));
    await tester.pumpAndSettle();
    expect(find.text('TOURNAMENT ACTIONS'), findsOneWidget);
    for (final key in ['live', 'checkIn', 'approve', 'announce', 'draw', 'schedule', 'courts', 'results']) {
      expect(find.byKey(Key('action-$key')), findsOneWidget, reason: key);
    }
    await tester.tap(find.byKey(const Key('action-draw')));
    await tester.pumpAndSettle();
    expect(find.text('Draws'), findsOneWidget, reason: 'opens the tool for the tournament in focus');
  });

  testWidgets('create a tournament in the wizard, publish it, and players can find it', (tester) async {
    usePhone(tester, const Size(390, 844));
    await pumpOrganizer(tester);
    await goTo(tester, '/org/org1/new-tournament');

    await tester.tap(find.byKey(const Key('wizardNext')));
    await tester.pumpAndSettle();
    expect(find.text('Give the tournament a name.'), findsOneWidget, reason: 'says what is missing, in words');

    await tester.enterText(find.byKey(const Key('tournamentName')), 'Navratri Smash 2026');
    await tester.tap(find.byKey(const Key('wizardNext')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key("preset-Men's Doubles")));
    await tester.tap(find.byKey(const Key('preset-Mixed Doubles')));
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const Key('wizardNext')));
      await tester.pumpAndSettle();
    }
    expect(find.text('NAVRATRI SMASH 2026'), findsOneWidget, reason: 'review step');

    await tester.tap(find.byKey(const Key('publishTournament')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmAction')));
    await tester.pumpAndSettle();
    expect(find.text('REGISTRATION OPEN'), findsWidgets, reason: 'the hub opens on the published tournament');

    final published = serverOf(tester).playerTournaments().where((t) => t.name == 'Navratri Smash 2026');
    expect(published, hasLength(1), reason: 'the same record the Player app reads');
    expect(published.single.categories, hasLength(2));
  });

  testWidgets('approve a registration from the queue', (tester) async {
    usePhone(tester, const Size(390, 844));
    await pumpOrganizer(tester);
    await goTo(tester, '/org/org1/t/t-night/registrations?filter=pending');
    final pending = (await serverOf(tester).entries('t-night')).where((e) => e.approval == Approval.pending).toList();
    expect(pending, isNotEmpty);
    final target = pending.first;

    await tapVisible(tester, find.byKey(Key('approve-${target.id}')));
    final after = (await serverOf(tester).entries('t-night')).firstWhere((e) => e.id == target.id);
    expect(after.approval, Approval.approved);
    expect(find.byKey(Key('approve-${target.id}')), findsNothing, reason: 'it leaves the pending list');
    expect((await serverOf(tester).audit('org1')).first.action, 'Changed registration');
  });

  testWidgets('generate and publish a draw', (tester) async {
    usePhone(tester, const Size(390, 844));
    await pumpOrganizer(tester);
    await goTo(tester, '/org/org1/t/t-league/draw');
    await tester.tap(find.byKey(const Key('generateDraw')));
    await tester.pumpAndSettle();
    expect(find.text('NOT PUBLISHED'), findsOneWidget);
    // Let the "Draw ready" toast clear; it sits over the bottom of the page.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('publishDraw')));
    expect(find.text('Publish draw?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirmAction')));
    await tester.pumpAndSettle();
    expect(find.text('PUBLISHED'), findsOneWidget);
    expect((await serverOf(tester).tournament('t-league')).status, TournamentStatus.drawGenerated);
  });

  testWidgets('score a live match to a confirmed result', (tester) async {
    usePhone(tester, const Size(390, 844));
    await pumpOrganizer(tester);
    final server = serverOf(tester);
    final live = (await server.matches('t-summer')).firstWhere((m) => m.state == MatchState.live);
    await goTo(tester, '/org/org1/t/t-summer/match/${live.id}');

    // Tap the serving side until the match is decided; each tap syncs.
    for (var i = 0; i < 80 && find.byKey(const Key('confirmResult')).evaluate().isEmpty; i++) {
      final m = await server.match(live.id);
      await tester.tap(find.byKey(Key('console-${(m.serve ?? live.serve!).side.name}')));
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
    }
    expect(find.text('CONFIRM MATCH RESULT?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirmResult')));
    await tester.pumpAndSettle();
    final done = await server.match(live.id);
    expect(done.state, MatchState.completed);
    expect(find.text('FINAL'), findsOneWidget);
  });

  testWidgets('a scorer sees scoring, not money or staff', (tester) async {
    usePhone(tester, const Size(390, 844));
    await pumpOrganizer(tester, role: 'scorer', capabilities: {'scoreMatch'});
    await tester.tap(navLabel('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Finance'), findsNothing);
    expect(find.text('Staff & roles'), findsNothing);
    expect(find.text('Public profile'), findsOneWidget);

    await goTo(tester, '/org/org1/finance');
    expect(find.text('Your role cannot see payments'), findsOneWidget, reason: 'a direct link does not bypass it');
  });

  testWidgets('a player registering in the Player app shows up in the organiser queue', (tester) async {
    usePhone(tester, const Size(390, 844));
    await pumpOrganizer(tester);
    final server = serverOf(tester);
    final before = (await server.entries('t-night')).length;
    // What `POST /tournaments/:id/registrations` does from the Player app.
    server.registerPlayer('t-night', 't-night-od', playerName: 'Smit Ramani', partner: 'Kamal Parmar');
    await goTo(tester, '/org/org1/t/t-night/registrations');
    expect(find.text('Smit Ramani / Kamal Parmar'), findsOneWidget);
    expect((await server.entries('t-night')).length, before + 1);
  });

  testWidgets('announcements reach the chosen players', (tester) async {
    usePhone(tester, const Size(390, 844));
    await pumpOrganizer(tester);
    await goTo(tester, '/org/org1/t/t-summer/announce?kind=delay');
    await tapVisible(tester, find.byKey(const Key('sendAnnouncement')));
    await tester.tap(find.byKey(const Key('confirmAction')));
    await tester.pumpAndSettle();
    final sent = await serverOf(tester).announcements('t-summer');
    expect(sent.first.kind, AnnouncementKind.delay);
    expect(sent.first.recipients, greaterThan(0));
  });

  test('the repository contract has a release fallback for every read', () async {
    const empty = EmptyOrganizerRepository();
    expect(await empty.tournaments('org1'), isEmpty);
    expect(await empty.entries('t'), isEmpty);
  });
}
