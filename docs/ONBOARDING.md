# SkorX first launch, sign-in and profile setup

How a player gets from tapping the icon to Player home, and where each piece lives.

## 1. Journeys

| Who | Path |
|---|---|
| First launch on this phone | Full brand reveal (3.8 s) → 3 stories (Welcome, Your pickleball world, SkorX TMS) → Get started → WhatsApp number → code → *new number:* profile setup (first and last name, photo, level, game, city; no skipping, photo optional) → location and notification permissions → player card → Home |
| Existing player on a new phone | Brand reveal → stories → Get started → number → code → **Welcome back, Smit** (1.4 s) → where they left off |
| Signed in, reopening | Short brand reveal (2.6 s) → where they left off. Nothing in between. |
| Signed out, after the stories | Quick logo → sign-in |
| Left during profile setup | Quick logo → the same setup question, answers kept |
| Explore SkorX (no account) | Stories → Explore SkorX → tournaments and courts as a guest; anything that needs an account opens sign-in |

The app is dark by default (Settings › Appearance offers light and system). Stories advance every 4.2 s and can be tapped (right: next, left: back), swiped or skipped. Touching the screen pauses them. With the system's "reduce motion" setting on, nothing auto-advances, the launch animation is skipped, and entrances appear at once.

**Launch.** The native splash is the animation's opening scene (`branding/splash_scene.png`: the court under its light), and it stays up until Flutter's first frame, which draws the same picture and starts the ball at once. Tap to first frame is about 0.65 s in a profile/release build on a OnePlus 6, of which about 0.1 s is app code; a debug build takes 2.7–3.4 s because Dart is compiled on the phone. To judge start-up, use `flutter run --profile --dart-define=DEV_AUTH=true` (fast, dev sign-in, no hot reload).

## 2. State

| Value | Where | Notes |
|---|---|---|
| `hasCompletedOnboarding` | `SharedPreferences` `skorx.onboarding.completed` (`OnboardingController`) | Set on reaching Get started, and whenever anyone signs in (players updating from older builds never see the stories). |
| `isLoggedIn` | Secure storage (`SecureTokenStore`: Keychain / Android keystore) | Session tokens only; never in preferences. |
| `userId`, `isProfileComplete` | Server (`GET /auth/me`), cached in preferences for offline launch | The server decides new vs existing by the verified number, so one number is one account. |
| Profile draft | `SharedPreferences` `skorx.onboarding.draft.<userId>` | Current step and answers; cleared once the profile is saved. |
| Level, formats, photo | `AppSettings` on the phone | Move to the API when it has fields for them; name and city go to `PATCH /me/profile`. |

`redirectFor` in `lib/app/routing/redirect.dart` is the one place that decides which screen a state belongs on. It is pure and unit-tested (`test/app/redirect_test.dart`).

## 3. Screens

| Route | Screen | File |
|---|---|---|
| (overlay) | `SkorxIntroGate`: full reveal or quick logo | `lib/app/intro/skorx_intro.dart` |
| `/splash` | `SplashScreen`: while the session restores | `lib/app/routing/router.dart` |
| `/welcome` | `WelcomeFlow`: 3 stories + Get started | `lib/features/onboarding/ui/welcome_flow.dart` |
| `/explore-skorx` | `GuestExplorePage` | `lib/features/onboarding/ui/guest_explore_page.dart` |
| `/login` | `SignInScreen`: WhatsApp number | `lib/features/auth/ui/sign_in_screen.dart` |
| `/login/verify` | `VerifyScreen`: 6 code boxes, resend timer | `lib/features/auth/ui/verify_screen.dart` |
| `/profile-setup` | `ProfileSetupScreen`: name, photo, level, game, city, then permissions ("Allow & finish" shows the system prompts for whatever is not yet answered; a declined permission never blocks sign-up) | `lib/features/auth/ui/profile_setup_screen.dart` |
| `/profile-complete` | `ProfileCompleteScreen`: player card, welcome, Enter SkorX | `lib/features/onboarding/ui/arrival_screens.dart` |
| `/welcome-back` | `WelcomeBackScreen` | `lib/features/onboarding/ui/arrival_screens.dart` |

Shared pieces (`lib/features/onboarding/ui/onboarding_kit.dart`): `OnboardPalette` (dark and light), `CourtBackdrop` (court lines that draw themselves, and a rally up and down the court: paddles, taps on the court, shadows), `Reveal` (staggered entrance, held until the launch animation ends), `SegmentedProgress`, `OnboardButton`, `GlassPanel`, `OnboardError`, `onboardPage` (the route transition). Every pickleball in the app is drawn by `Pickleball.paint` (`lib/design/pickleball.dart`): 40 evenly spaced holes on a real sphere, turning in 3D. `BallLoader` (`lib/design/ball_loader.dart`) replaces spinners, including in `SxButton`.

## 4. Errors

| Case | Message | Way out |
|---|---|---|
| Invalid number | Please enter a valid WhatsApp number. | Fix and continue |
| Wrong code | That code doesn't look right. Try again. | Boxes shake and clear |
| Expired / too many tries | Your code has expired. Request a new one. | *Send new code*, even before the timer ends |
| No connection | Something went wrong. Check your connection and try again. | *Retry* (the code is kept) |
| WhatsApp send failed | We couldn't send the code on WhatsApp. Try again in a moment. | *Send new code* |
| Profile save fails | The network message | *Retry*; every answer is kept |

Server error codes are mapped in `lib/features/auth/auth_errors.dart`; unknown codes show the server's own message.

## 5. Adding sign-in methods later

Google, Apple or email sign-in add an `AuthRepository` call that returns a `CurrentUser` and stores the session, and a button under the WhatsApp form. Everything after sign-in (welcome back, profile setup, home) only looks at `SignedIn(user)` and `user.profileComplete`, never at how the player signed in. DUPR / PWR ratings, tournament history import, clubs and court preferences are later profile steps: add an entry to `_Step` and a field to `ProfileDraft`.

## 6. Trying it in a debug build

Debug builds sign in without the server (`DevAuthRepository`). Like a release build, a fresh install starts signed out and plays the whole first launch; a sign-in is then remembered. **Settings › Developer › Replay first launch** signs out and shows the stories again. Then:

- your own number (95865 45430) is an existing player → Welcome back;
- any other number is a new player → profile setup;
- code `000000` is wrong, `999999` has expired.

Tests: `test/features/onboarding_flow_test.dart` walks user types A–F plus guest browsing and small-screen layout in both themes.
