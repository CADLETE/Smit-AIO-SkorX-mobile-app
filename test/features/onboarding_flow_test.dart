import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skorx/app/app.dart';
import 'package:skorx/core/api/api_exception.dart';
import 'package:skorx/core/app_permissions.dart';
import 'package:skorx/features/auth/data/auth_repository.dart';
import 'package:skorx/features/onboarding/ui/onboarding_kit.dart';
import 'package:skorx/features/settings/app_settings.dart';
import 'package:skorx/features/shell/workspace_shell.dart';

import '../support/fakes.dart';

/// The first-launch journey, tested as the six kinds of user it has to
/// serve. Every test ends somewhere with an obvious next step.
Future<void> pumpApp(WidgetTester tester, FakeAuthRepository repo) async {
  useReducedMotion(tester);
  await tester.pumpWidget(ProviderScope(overrides: appOverrides(repo), child: const SkorxApp()));
  await tester.pumpAndSettle();
}

Finder navLabel(String label) => find.descendant(
      of: find.byType(SkorxNavBar),
      matching: find.byWidgetPredicate((w) => w is Text && w.data?.toLowerCase() == label.toLowerCase()),
    );

Future<void> tapKey(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

Future<void> enterNumber(WidgetTester tester, String number) async {
  await tester.enterText(find.byKey(const Key('mobileField')), number);
  await tester.pump();
}

Future<void> enterCode(WidgetTester tester, String code) async {
  await tester.enterText(find.byKey(const Key('codeField')), code);
  await tester.pumpAndSettle();
}

bool enabled(WidgetTester tester, String key) => tester.widget<OnboardButton>(find.byKey(Key(key))).onPressed != null;

void main() {
  setUp(useInMemoryPreferences);

  testWidgets('A: a brand-new player goes from the introduction to Player home', (tester) async {
    final repo = FakeAuthRepository();
    final permissions = FakeAppPermissions();
    useReducedMotion(tester);
    await tester.pumpWidget(
      ProviderScope(overrides: appOverrides(repo, permissions: permissions), child: const SkorxApp()),
    );
    await tester.pumpAndSettle();

    // What is SkorX? The introduction opens on the first launch.
    expect(find.text('WELCOME TO SKORX'), findsOneWidget);
    await tester.fling(find.byKey(const Key('welcomePages')), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('FOR PLAYERS'), findsOneWidget, reason: 'swipe moves to the next story');
    await tapKey(tester, 'welcomeSkip');
    expect(find.byKey(const Key('getStarted')), findsOneWidget);
    expect(find.text('ONTO THE COURT?'), findsOneWidget);
    await tapKey(tester, 'getStarted');

    // WhatsApp sign-in.
    expect(find.text('WITH WHATSAPP'), findsOneWidget);
    await enterNumber(tester, '12345');
    expect(enabled(tester, 'signInPrimary'), isFalse, reason: 'a short number cannot continue');
    await enterNumber(tester, '1234567890');
    await tapKey(tester, 'signInPrimary');
    expect(find.text('Please enter a valid WhatsApp number.'), findsOneWidget);
    expect(repo.sentTo, isEmpty);

    await enterNumber(tester, '9586545430');
    await tapKey(tester, 'signInPrimary');
    expect(repo.sentTo, ['9586545430']);
    expect(find.text('VERIFY YOUR NUMBER'), findsOneWidget);
    expect(find.text('Resend in 30s'), findsOneWidget);

    await enterCode(tester, '123456');

    // New number: build the player profile, one question at a time.
    expect(find.text('WHAT SHOULD WE CALL YOU?'), findsOneWidget);
    expect(enabled(tester, 'setupNext'), isFalse, reason: 'a name is needed');
    await tester.enterText(find.byKey(const Key('firstNameField')), 'Smit');
    await tester.pump();
    expect(enabled(tester, 'setupNext'), isFalse, reason: 'the last name is needed too');
    await tester.enterText(find.byKey(const Key('lastNameField')), 'Ramani');
    await tester.pump();
    await tapKey(tester, 'setupNext');

    expect(find.text('ADD YOUR PLAYER PHOTO'), findsOneWidget);
    expect(find.text('SR'), findsOneWidget, reason: 'initials until there is a photo');
    expect(find.text('SKIP FOR NOW'), findsNothing, reason: 'no skipping during setup');
    expect(enabled(tester, 'setupNext'), isTrue, reason: 'the photo is still optional');
    await tapKey(tester, 'setupNext');

    expect(find.text("WHAT'S YOUR LEVEL?"), findsOneWidget);
    expect(enabled(tester, 'setupNext'), isFalse);
    await tapKey(tester, 'level-intermediate');
    await tapKey(tester, 'setupNext');

    expect(find.text('WHICH HAND DO YOU PLAY WITH?'), findsOneWidget);
    expect(enabled(tester, 'setupNext'), isFalse, reason: 'a playing hand is needed');
    await tapKey(tester, 'hand-left');
    await tapKey(tester, 'setupNext');

    expect(find.text('TELL US ABOUT YOUR GAME'), findsOneWidget);
    await tapKey(tester, 'format-both');
    await tapKey(tester, 'setupNext');

    expect(find.text('WHERE DO YOU PLAY?'), findsOneWidget);
    expect(find.text('SKIP'), findsNothing);
    expect(enabled(tester, 'setupNext'), isFalse, reason: 'a city is needed');
    await tester.enterText(find.byKey(const Key('cityField')), 'ahmed');
    await tester.pump();
    await tester.tap(find.text('Ahmedabad'));
    await tester.pumpAndSettle();
    await tapKey(tester, 'setupNext');

    // After the six questions: location and notifications, with why.
    expect(find.text('STAY IN THE GAME'), findsOneWidget);
    expect(find.text('ALLOW & FINISH'), findsOneWidget);
    expect(repo.savedProfile, isNull, reason: 'nothing is saved until the end');
    await tapKey(tester, 'setupNext');
    expect(permissions.requested, [AppPermission.location, AppPermission.notifications]);

    expect(repo.savedProfile?.name, 'Smit Ramani');
    expect(repo.savedProfile?.city, 'Ahmedabad');

    // The player card and the welcome.
    expect(find.byKey(const Key('playerCard')), findsOneWidget);
    expect(find.text('LEFT-HANDED PLAYER'), findsOneWidget, reason: 'the playing hand is on the card');
    expect(find.text('WELCOME TO SKORX,'), findsOneWidget);
    expect(find.text('SMIT.'), findsOneWidget);
    expect(find.text('Intermediate'), findsOneWidget);
    expect(find.text('Singles & doubles'), findsOneWidget);

    await tapKey(tester, 'enterSkorx');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.text('SMIT'), findsOneWidget, reason: 'Home greets the player by first name');
    expect(navLabel('Home'), findsOneWidget);

    final settings = ProviderScope.containerOf(tester.element(find.byType(WorkspaceShell))).read(appSettingsProvider);
    expect(settings.level, 'intermediate');
    expect(settings.formats, ['doubles', 'singles']);
    expect(settings.homeCity, 'Ahmedabad');
  });

  testWidgets('B: an existing player on a new phone is welcomed back, with no profile questions', (tester) async {
    await markIntroSeen();
    final repo = FakeAuthRepository(signInAs: user());
    await pumpApp(tester, repo);

    expect(find.text('WELCOME TO SKORX'), findsNothing, reason: 'the introduction is shown once per phone');
    expect(tester.testTextInput.isVisible, isFalse, reason: 'no keyboard until the player taps the number field');
    await tester.tap(find.text('+91'));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue, reason: 'tapping anywhere on the field opens it');
    await enterNumber(tester, '9586545430');
    await tapKey(tester, 'signInPrimary');
    await enterCode(tester, '123456');

    expect(find.text('WELCOME BACK,'), findsOneWidget);
    expect(find.text('SMIT.'), findsOneWidget);
    expect(find.text('WHAT SHOULD WE CALL YOU?'), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(navLabel('Home'), findsOneWidget);
    expect(repo.savedProfile, isNull);
  });

  testWidgets('C: a signed-in player reopening the app goes straight home', (tester) async {
    await pumpApp(tester, FakeAuthRepository(stored: RestoredUser(user(), fromCache: false)));
    expect(navLabel('Home'), findsOneWidget);
    expect(find.text('WELCOME TO SKORX'), findsNothing);
    expect(find.text('WELCOME BACK,'), findsNothing, reason: 'nothing between launch and home');
  });

  testWidgets('D: leaving during profile setup resumes on the same question', (tester) async {
    final repo = FakeAuthRepository(stored: RestoredUser(user(name: '', profileComplete: false), fromCache: false));
    await pumpApp(tester, repo);

    expect(find.text('WHAT SHOULD WE CALL YOU?'), findsOneWidget, reason: 'setup comes before anything else');
    await tester.enterText(find.byKey(const Key('firstNameField')), 'Asha');
    await tester.enterText(find.byKey(const Key('lastNameField')), 'Patel');
    await tester.pump();
    await tapKey(tester, 'setupNext');
    await tapKey(tester, 'setupNext');
    await tapKey(tester, 'level-beginner');
    expect(find.text("WHAT'S YOUR LEVEL?"), findsOneWidget);

    // The app is closed and opened again.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(ProviderScope(overrides: appOverrides(repo), child: const SkorxApp()));
    await tester.pumpAndSettle();

    expect(find.text("WHAT'S YOUR LEVEL?"), findsOneWidget);
    expect(enabled(tester, 'setupNext'), isTrue, reason: 'the level chosen before is kept');
    await tapKey(tester, 'setupNext');
    await tapKey(tester, 'hand-right');
    await tapKey(tester, 'setupNext');
    await tapKey(tester, 'format-singles');
    await tapKey(tester, 'setupNext');
    await tester.tap(find.text('Pune'));
    await tester.pumpAndSettle();
    await tapKey(tester, 'setupNext');
    // A permission allowed on its own card is not asked again.
    await tapKey(tester, 'permission-location');
    await tapKey(tester, 'setupNext');
    expect(repo.savedProfile?.name, 'Asha Patel');
    expect(repo.savedProfile?.city, 'Pune');
    expect(find.text('ASHA.'), findsOneWidget);

    // Back on step one, a player can still leave with another number.
    expect(await SharedPreferencesAsync().getString('skorx.onboarding.draft.u1'), isNull, reason: 'draft cleared');
  });

  testWidgets('E: a poor connection shows what went wrong and lets the player retry', (tester) async {
    await markIntroSeen();
    final repo = FakeAuthRepository()..sendError = const ApiException(ApiException.network, 'offline');
    await pumpApp(tester, repo);

    await enterNumber(tester, '9586545430');
    await tapKey(tester, 'signInPrimary');
    expect(find.text('Something went wrong. Check your connection and try again.'), findsOneWidget);
    expect(find.text('VERIFY YOUR NUMBER'), findsNothing);

    // Connection back: the same button carries on.
    await tapKey(tester, 'signInPrimary');
    expect(find.text('VERIFY YOUR NUMBER'), findsOneWidget);
    await enterCode(tester, '123456');

    await tester.enterText(find.byKey(const Key('firstNameField')), 'Ravi');
    await tester.enterText(find.byKey(const Key('lastNameField')), 'Shah');
    await tester.pump();
    await tapKey(tester, 'setupNext');
    await tapKey(tester, 'setupNext');
    await tapKey(tester, 'level-advanced');
    await tapKey(tester, 'setupNext');
    await tapKey(tester, 'hand-right');
    await tapKey(tester, 'setupNext');
    await tapKey(tester, 'format-doubles');
    await tapKey(tester, 'setupNext');
    await tester.tap(find.text('Surat'));
    await tester.pumpAndSettle();
    await tapKey(tester, 'setupNext');

    repo.profileError = const ApiException(ApiException.network, 'offline');
    await tapKey(tester, 'setupNext');
    expect(find.text('Something went wrong. Check your connection and try again.'), findsOneWidget);
    expect(find.text('STAY IN THE GAME'), findsOneWidget, reason: 'answers are kept');
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(repo.savedProfile?.name, 'Ravi Shah');
    expect(find.text('RAVI.'), findsOneWidget);
  });

  testWidgets('F: a wrong or expired code says so and offers the way out', (tester) async {
    await markIntroSeen();
    final repo = FakeAuthRepository(signInAs: user());
    await pumpApp(tester, repo);
    await enterNumber(tester, '9586545430');
    await tapKey(tester, 'signInPrimary');

    await enterCode(tester, '000000');
    expect(find.text("That code doesn't look right. Try again."), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('codeField'))).controller!.text, isEmpty);

    await enterCode(tester, '999999');
    expect(find.text('Your code has expired. Request a new one.'), findsOneWidget);
    await tester.tap(find.text('Send new code'));
    await tester.pumpAndSettle();
    expect(repo.sentTo, hasLength(2), reason: 'an expired code can be replaced at once');

    // Wrong number? Back to change it.
    await tester.tap(find.byKey(const Key('changeNumber')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mobileField')), findsOneWidget);
    await tapKey(tester, 'signInPrimary');
    await enterCode(tester, '123456');
    expect(find.text('WELCOME BACK,'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });

  testWidgets('Explore SkorX lets a visitor browse before signing in', (tester) async {
    await pumpApp(tester, FakeAuthRepository());
    await tapKey(tester, 'welcomeSkip');
    await tapKey(tester, 'exploreSkorx');
    expect(find.text('GUEST'), findsOneWidget);
    expect(find.byKey(const Key('exploreSearch')), findsOneWidget);
    await tapKey(tester, 'guestGetStarted');
    expect(find.byKey(const Key('mobileField')), findsOneWidget);
  });

  testWidgets('a new player can go back and use another number', (tester) async {
    final repo = FakeAuthRepository(stored: RestoredUser(user(name: '', profileComplete: false), fromCache: false));
    await pumpApp(tester, repo);
    await tapKey(tester, 'setupClose');
    expect(repo.signedOut, isTrue);
    expect(find.byKey(const Key('mobileField')), findsOneWidget);
  });

  for (final (size, dark) in [(const Size(360, 690), true), (const Size(390, 844), false)]) {
    testWidgets('every onboarding screen lays out at ${size.width.toInt()}×${size.height.toInt()}', (tester) async {
      tester.view.physicalSize = size * tester.view.devicePixelRatio;
      addTearDown(tester.view.reset);
      if (!dark) await SharedPreferencesAsync().setString('skorx.settings', '{"themeMode":"light"}');
      final repo = FakeAuthRepository();
      await pumpApp(tester, repo);
      for (var i = 0; i < 3; i++) {
        await tester.fling(find.byKey(const Key('welcomePages')), const Offset(-400, 0), 1000);
        await tester.pumpAndSettle();
      }
      expect(find.byKey(const Key('getStarted')), findsOneWidget);
      await tapKey(tester, 'getStarted');
      await enterNumber(tester, '9586545430');
      await tapKey(tester, 'signInPrimary');
      await enterCode(tester, '123456');
      await tester.enterText(find.byKey(const Key('firstNameField')), 'Smit');
      await tester.enterText(find.byKey(const Key('lastNameField')), 'Ramani');
      await tester.pump();
      for (final step in ['setupNext', 'setupNext', 'level-competitive', 'setupNext', 'hand-right', 'setupNext', 'format-singles', 'setupNext', 'Goa', 'setupNext', 'setupNext']) {
        if (step == 'Goa') {
          await tester.ensureVisible(find.text('Goa'));
          await tester.tap(find.text('Goa'));
          await tester.pumpAndSettle();
        } else {
          await tapKey(tester, step);
        }
      }
      expect(find.byKey(const Key('enterSkorx')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
