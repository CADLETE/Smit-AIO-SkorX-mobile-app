import '../../features/auth/auth_controller.dart';
import '../../features/onboarding/onboarding_controller.dart';
import '../../features/workspace/workspace.dart';
import '../../features/workspace/workspace_controller.dart';

abstract final class Routes {
  static const splash = '/splash';

  /// First launch: the introduction, ending on Get Started.
  static const welcome = '/welcome';

  /// Browsing before signing in.
  static const guest = '/explore-skorx';
  static const login = '/login';
  static const verify = '/login/verify';

  /// New player: name, photo, level, game, city.
  static const profileSetup = '/profile-setup';

  /// New player: their card and "Welcome to SkorX".
  static const profileComplete = '/profile-complete';

  /// Existing player on a new sign-in.
  static const welcomeBack = '/welcome-back';

  static String verifyFor(String mobile, {Duration resendAfter = const Duration(seconds: 30)}) =>
      Uri(path: verify, queryParameters: {'mobile': mobile, 'resend': '${resendAfter.inSeconds}'}).toString();

  /// Screens for someone who is not signed in.
  static const signedOut = {welcome, guest, login, verify};
}

/// Where the router should send the user instead of [location], or null to
/// stay. Pure, so every rule is unit-tested without widgets.
///
/// First launch: splash → welcome → login → verify → profile setup →
/// profile complete → home. A returning player: splash → where they left
/// off. Signed out after the introduction: splash → login.
String? redirectFor({
  required AuthState auth,
  required OnboardingState onboarding,
  required WorkspaceState workspaces,
  required String location,
}) {
  String? goTo(String target) => target == location ? null : target;

  switch (auth) {
    case AuthRestoring():
      return goTo(Routes.splash);
    case SignedOut():
      if (!onboarding.ready) return goTo(Routes.splash);
      if (Routes.signedOut.contains(location)) return null;
      return onboarding.hasCompletedOnboarding ? Routes.login : Routes.welcome;
    case SignedIn(:final user):
      if (!user.profileComplete) return goTo(Routes.profileSetup);
      // Just signed in on this phone with an existing account.
      if (location == Routes.verify || location == Routes.login) return Routes.welcomeBack;
      // Just finished building a new profile.
      if (location == Routes.profileSetup) return Routes.profileComplete;
      // Both hand over to the app themselves once the workspaces are known.
      if (location == Routes.welcomeBack || location == Routes.profileComplete) return null;
      if (!workspaces.ready) return goTo(Routes.splash);

      final entry = workspaces.entryLocation(workspaces.current);
      if (location == Routes.splash || Routes.signedOut.contains(location) || location == '/') return entry;
      // A link into a workspace the user does not have (an organization
      // they left, a referee screen without the role) lands on Player home.
      // The server refuses the data regardless.
      if (workspaces.ownerOf(location) == null) return const PlayerWorkspace().homeLocation;
      return null;
  }
}
