import 'package:flutter_test/flutter_test.dart';
import 'package:skorx/app/routing/redirect.dart';
import 'package:skorx/features/auth/auth_controller.dart';
import 'package:skorx/features/onboarding/onboarding_controller.dart';
import 'package:skorx/features/workspace/workspace.dart';
import 'package:skorx/features/workspace/workspace_controller.dart';

import '../support/fakes.dart';

void main() {
  final organizer = user(memberships: [membership('org1', 'CADLETE Pickleball', 'owner')]);
  final available = workspacesFor(organizer);

  WorkspaceState ready({String current = 'player', Map<String, String> locations = const {}}) => WorkspaceState(
        available: available,
        current: available.firstWhere((w) => w.key == current),
        lastLocations: locations,
        ready: true,
      );

  const introSeen = OnboardingState(ready: true, hasCompletedOnboarding: true);
  const firstLaunch = OnboardingState(ready: true, hasCompletedOnboarding: false);

  String? go(AuthState auth, String location, [WorkspaceState? workspaces, OnboardingState onboarding = introSeen]) =>
      redirectFor(auth: auth, onboarding: onboarding, workspaces: workspaces ?? ready(), location: location);

  test('waits on the splash screen while the session is restored', () {
    expect(go(const AuthRestoring(), '/player/home'), Routes.splash);
    expect(go(const AuthRestoring(), Routes.splash), isNull);
  });

  test('shows the introduction on the first launch, and never after it', () {
    expect(go(const SignedOut(), Routes.splash, null, firstLaunch), Routes.welcome);
    expect(go(const SignedOut(), Routes.welcome, null, firstLaunch), isNull);
    expect(go(const SignedOut(), Routes.login, null, firstLaunch), isNull, reason: 'Get started opens sign-in');
    expect(go(const SignedOut(), Routes.guest, null, firstLaunch), isNull, reason: 'Explore SkorX as a guest');
    expect(go(const SignedOut(), Routes.splash), Routes.login);
    expect(go(const SignedOut(), Routes.splash, null, OnboardingState.initial), isNull, reason: 'wait for the saved flag');
  });

  test('sends a signed-out user to sign-in from anywhere', () {
    expect(go(const SignedOut(), '/org/org1/dashboard'), Routes.login);
    expect(go(const SignedOut(), '/player/tournament/t1'), Routes.login, reason: 'a guest opening a tournament');
    expect(go(const SignedOut(), Routes.login), isNull);
    expect(go(const SignedOut(), Routes.verify), isNull);
    expect(go(const SignedOut(), Routes.profileSetup), Routes.login, reason: 'signed out mid-setup');
  });

  test('asks a new player for their profile before anything else', () {
    final fresh = SignedIn(user(name: '', profileComplete: false));
    expect(go(fresh, Routes.verify), Routes.profileSetup);
    expect(go(fresh, '/player/home'), Routes.profileSetup);
    expect(go(fresh, Routes.splash), Routes.profileSetup, reason: 'left mid-setup and came back');
    expect(go(fresh, Routes.profileSetup), isNull);
  });

  test('a finished profile gets its welcome, then the app', () {
    expect(go(SignedIn(user()), Routes.profileSetup), Routes.profileComplete);
    expect(go(SignedIn(user()), Routes.profileComplete, WorkspaceState.initial), isNull);
  });

  test('an existing player signing in is welcomed back, not asked for a profile', () {
    expect(go(SignedIn(organizer), Routes.verify), Routes.welcomeBack);
    expect(go(SignedIn(organizer), Routes.welcomeBack, WorkspaceState.initial), isNull);
  });

  test('holds on the splash screen until the saved workspace is known', () {
    expect(go(SignedIn(organizer), Routes.splash, WorkspaceState.initial), isNull);
    expect(go(SignedIn(organizer), '/player/home', WorkspaceState.initial), Routes.splash);
  });

  test('opens the current workspace where the user left it', () {
    expect(go(SignedIn(organizer), Routes.splash), '/player/home');
    expect(
      go(SignedIn(organizer), Routes.splash, ready(current: 'org:org1', locations: {'org:org1': '/org/org1/schedule'})),
      '/org/org1/schedule',
    );
  });

  test('lets the user move within workspaces they have', () {
    expect(go(SignedIn(organizer), '/org/org1/matches'), isNull);
    expect(go(SignedIn(organizer), '/player/paddle'), isNull);
  });

  test('sends links into workspaces the user does not have to Player home', () {
    expect(go(SignedIn(organizer), '/org/someone-else/dashboard'), '/player/home');
    expect(go(SignedIn(organizer), '/referee/current'), '/player/home');
  });
}
