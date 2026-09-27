import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skorx/app/app.dart';
import 'package:skorx/features/auth/data/auth_repository.dart';
import 'package:skorx/features/shell/workspace_shell.dart';

import '../support/fakes.dart';

Future<void> pumpApp(WidgetTester tester, FakeAuthRepository repo) async {
  useReducedMotion(tester);
  await tester.pumpWidget(ProviderScope(overrides: appOverrides(repo), child: const SkorxApp()));
  await tester.pumpAndSettle();
}

/// A tab in the bottom bar. Player tabs are set in caps, so match either case.
Finder navLabel(String label) => find.descendant(
      of: find.byType(SkorxNavBar),
      matching: find.byWidgetPredicate((w) => w is Text && w.data?.toLowerCase() == label.toLowerCase()),
    );

/// Switches mode and waits out the short "… MODE" transition, which holds
/// no animation for settle to see. From Player it goes through Profile's
/// "Switch to Organiser" card; from Organiser through its Profile tab. With
/// one other workspace the card switches straight away; otherwise it opens
/// the picker and [title] is chosen.
/// The last tab: Account in Player, Profile in Organizer.
Finder get accountTab => navLabel('Account').evaluate().isNotEmpty ? navLabel('Account') : navLabel('Profile');

Future<void> switchWorkspaceTo(WidgetTester tester, String title) async {
  await tester.tap(accountTab);
  await tester.pumpAndSettle();
  final card = find.byKey(const Key('switchModeCard'));
  if (card.evaluate().isNotEmpty) {
    await tester.tap(card);
  } else {
    final row = find.byKey(Key(title == 'Player' ? 'switchToPlayer' : 'switchOrganisation'));
    await revealAboveNavBar(tester, row);
    await tester.tap(row);
  }
  await tester.pumpAndSettle();
  if (find.text('SWITCH MODE').evaluate().isNotEmpty) {
    await tester.tap(find.text(title).last);
    await tester.pumpAndSettle();
  }
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
}

/// Scrolls [row] into view and clear of the floating bottom bar.
Future<void> revealAboveNavBar(WidgetTester tester, Finder row) async {
  await tester.scrollUntilVisible(row, 200);
  await tester.drag(row, const Offset(0, -300));
  await tester.pumpAndSettle();
}

const playerTabs = ['Home', 'Matches', 'Explore', 'My Paddle', 'Account'];

void main() {
  setUp(useInMemoryPreferences);

  // Sign-in and first-launch journeys: test/features/onboarding_flow_test.dart.

  testWidgets('one account moves Player -> Organizer -> Player, keeping its place in each',
      (tester) async {
    final repo = FakeAuthRepository(
      stored: RestoredUser(
        user(memberships: [
          membership('org1', 'CADLETE Pickleball', 'owner', {'managePayments', 'editTournament', 'manageSettings'}),
        ]),
        fromCache: false,
      ),
    );
    await pumpApp(tester, repo);

    // Player workspace: player tabs only, no organizer tools.
    expect(navLabel('My Paddle'), findsOneWidget);
    expect(navLabel('Live'), findsNothing);

    Future<void> switchTo(String title) => switchWorkspaceTo(tester, title);

    await switchTo('CADLETE Pickleball');
    for (final tab in ['Home', 'Live', 'Check-in', 'Players', 'Profile']) {
      expect(navLabel(tab), findsOneWidget, reason: tab);
    }
    expect(navLabel('My Paddle'), findsNothing, reason: 'player tabs are gone in Organizer');
    expect(find.byKey(const Key('switchToPlayer')), findsNothing, reason: 'no mode switch in the top bar');
    await tester.tap(navLabel('Live'));
    await tester.pumpAndSettle();

    await switchTo('Player');
    expect(find.byKey(const Key('switchModeCard')), findsOneWidget, reason: 'back on Profile where the player left');

    await switchTo('CADLETE Pickleball');
    expect(find.text('Organiser stats'), findsOneWidget, reason: 'back on Profile in the organization');
  });

  testWidgets('organizer Profile shows only the tools the role allows', (tester) async {
    final repo = FakeAuthRepository(
      stored: RestoredUser(
        user(memberships: [membership('org1', 'CADLETE Pickleball', 'check_in_staff', {'manageCheckIn'})]),
        fromCache: false,
      ),
    );
    await pumpApp(tester, repo);
    await switchWorkspaceTo(tester, 'CADLETE Pickleball');
    await tester.tap(accountTab);
    await tester.pumpAndSettle();

    expect(find.text('All tournaments'), findsOneWidget);
    expect(find.text('Payments'), findsNothing);
    expect(find.text('Settings'), findsNothing);
  });

  testWidgets('a plain player has no mode switch', (tester) async {
    await pumpApp(tester, FakeAuthRepository(stored: RestoredUser(user(), fromCache: false)));
    // The Home avatar opens Profile.
    await tester.tap(find.byKey(const Key('homeAvatar')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('idCard')), findsOneWidget);
    expect(find.byKey(const Key('switchModeCard')), findsNothing);
    await tester.scrollUntilVisible(find.byKey(const Key('signOut')), 200);
    expect(find.text('Sign out'), findsOneWidget);
  });

  testWidgets('Switch to Organiser goes straight to the one organisation, and Player comes back', (tester) async {
    final repo = FakeAuthRepository(
      stored: RestoredUser(
        user(memberships: [membership('org1', 'CADLETE Pickleball', 'owner', {'editTournament'})]),
        fromCache: false,
      ),
    );
    // With motion on, so the mode transition shows (reduced motion skips it).
    // Player Home has a pulsing live match, so pump frames rather than
    // waiting for everything to settle.
    Future<void> frames() async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await tester.pumpWidget(ProviderScope(overrides: appOverrides(repo), child: const SkorxApp()));
    // Let the opening animation (just under 3 s) finish.
    for (var i = 0; i < 4; i++) {
      await frames();
    }
    await tester.tap(accountTab);
    await frames();
    expect(find.text('Switch to Organiser'), findsOneWidget);

    await tester.tap(find.byKey(const Key('switchModeCard')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('ORGANISER MODE'), findsOneWidget, reason: 'the transition says where the player is going');
    await tester.pump(const Duration(milliseconds: 600));
    // The live dot on the organiser home pulses, so pump frames rather
    // than waiting for everything to settle.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const Key('liveCommandCard')), findsOneWidget, reason: 'the live tournament leads the home');

    await tester.tap(accountTab);
    await frames();
    await tester.scrollUntilVisible(find.byKey(const Key('switchToPlayer')), 200);
    await tester.drag(find.byKey(const Key('switchToPlayer')), const Offset(0, -300));
    await frames();
    await tester.tap(find.byKey(const Key('switchToPlayer')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('PLAYER MODE'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600));
    await frames();
    expect(find.byKey(const Key('switchModeCard')), findsOneWidget, reason: 'back on Profile');
  });

  testWidgets('starting offline opens the app from the saved account with an offline notice', (tester) async {
    await pumpApp(tester, FakeAuthRepository(stored: RestoredUser(user(), fromCache: true)));
    expect(find.text('Offline. Showing what was saved on this phone.'), findsOneWidget);
    expect(navLabel('Home'), findsOneWidget);
  });

  testWidgets('signing out returns to sign-in', (tester) async {
    final repo = FakeAuthRepository(stored: RestoredUser(user(), fromCache: false));
    await pumpApp(tester, repo);
    await tester.tap(accountTab);
    await tester.pumpAndSettle();
    // Sign out is the last row: scroll to the end so it clears the tab bar.
    await tester.scrollUntilVisible(find.byKey(const Key('signOut')), 200);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('signOut')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await tester.pumpAndSettle();
    expect(repo.signedOut, isTrue);
    expect(find.byKey(const Key('mobileField')), findsOneWidget, reason: 'straight to sign-in, no introduction');
  });
}
