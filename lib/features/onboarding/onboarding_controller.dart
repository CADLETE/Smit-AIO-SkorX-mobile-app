import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';

/// First-launch state kept on this phone. The rest of the launch state lives
/// elsewhere: the session (is the user signed in, and as whom) in secure
/// storage via [tokenStoreProvider], and whether the profile is complete on
/// the server's user, cached for offline launches.
class OnboardingState {
  const OnboardingState({required this.ready, required this.hasCompletedOnboarding});

  static const initial = OnboardingState(ready: false, hasCompletedOnboarding: false);

  /// False until the saved flag has been read, so the app never flashes the
  /// introduction at a returning user.
  final bool ready;

  /// The introduction has been watched or skipped once on this phone. After
  /// that, launches go straight to sign-in or the app.
  final bool hasCompletedOnboarding;
}

final onboardingControllerProvider = NotifierProvider<OnboardingController, OnboardingState>(OnboardingController.new);

class OnboardingController extends Notifier<OnboardingState> {
  static const _key = 'skorx.onboarding.completed';

  @override
  OnboardingState build() {
    // Anyone who has signed in on this phone has been onboarded, including
    // players who updated from a version without the introduction.
    ref.listen(authControllerProvider, (_, next) {
      if (next is SignedIn) complete();
    });
    Future.microtask(_load);
    return OnboardingState.initial;
  }

  Future<void> _load() async {
    var completed = false;
    try {
      completed = await ref.read(preferencesProvider).getBool(_key) ?? false;
    } catch (_) {
      // Unreadable preferences: show the introduction again, which is harmless.
    }
    // Completing is one-way: a sign-in while this was loading still counts.
    state = OnboardingState(ready: true, hasCompletedOnboarding: completed || state.hasCompletedOnboarding);
  }

  /// Debug builds: show the introduction again on the next sign-out.
  Future<void> reset() async {
    state = const OnboardingState(ready: true, hasCompletedOnboarding: false);
    await ref.read(preferencesProvider).remove(_key);
  }

  Future<void> complete() async {
    if (state.hasCompletedOnboarding) return;
    state = const OnboardingState(ready: true, hasCompletedOnboarding: true);
    await ref.read(preferencesProvider).setBool(_key, true);
  }
}

/// A new player's answers while they build their profile, one question per
/// screen. Saved after every step so a player who leaves mid-way picks up
/// where they stopped. Nothing reaches the server until the last step.
class ProfileDraft {
  const ProfileDraft({
    this.step = 0,
    this.firstName = '',
    this.lastName = '',
    this.photoPath,
    this.level,
    this.hand,
    this.formats = const {},
    this.city,
  });

  /// Index of the question the player is on.
  final int step;
  final String firstName;
  final String lastName;

  /// A copy of the chosen photo in the app's documents folder.
  final String? photoPath;

  /// A [PlayerLevel] name.
  final String? level;

  /// "Right" or "Left": the hand that holds the paddle.
  final String? hand;

  /// "singles" and/or "doubles".
  final Set<String> formats;
  final String? city;

  String get fullName => [firstName.trim(), lastName.trim()].where((s) => s.isNotEmpty).join(' ');

  ProfileDraft copyWith({
    int? step,
    String? firstName,
    String? lastName,
    String? Function()? photoPath,
    String? level,
    String? hand,
    Set<String>? formats,
    String? Function()? city,
  }) =>
      ProfileDraft(
        step: step ?? this.step,
        firstName: firstName ?? this.firstName,
        lastName: lastName ?? this.lastName,
        photoPath: photoPath == null ? this.photoPath : photoPath(),
        level: level ?? this.level,
        hand: hand ?? this.hand,
        formats: formats ?? this.formats,
        city: city == null ? this.city : city(),
      );

  Map<String, dynamic> toJson() => {
        'step': step,
        'firstName': firstName,
        'lastName': lastName,
        'photoPath': photoPath,
        'level': level,
        'hand': hand,
        'formats': formats.toList(),
        'city': city,
      };

  factory ProfileDraft.fromJson(Map<String, dynamic> json) => ProfileDraft(
        step: json['step'] as int? ?? 0,
        firstName: json['firstName'] as String? ?? '',
        lastName: json['lastName'] as String? ?? '',
        photoPath: json['photoPath'] as String?,
        level: json['level'] as String?,
        hand: json['hand'] as String?,
        formats: {...((json['formats'] as List<dynamic>?) ?? const []).cast<String>()},
        city: json['city'] as String?,
      );
}

/// Where each account's unfinished [ProfileDraft] is kept.
class ProfileDraftStore {
  ProfileDraftStore(this._ref);

  final Ref _ref;

  String _key(String userId) => 'skorx.onboarding.draft.$userId';

  Future<ProfileDraft?> read(String userId) async {
    try {
      final raw = await _ref.read(preferencesProvider).getString(_key(userId));
      return raw == null ? null : ProfileDraft.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String userId, ProfileDraft draft) =>
      _ref.read(preferencesProvider).setString(_key(userId), jsonEncode(draft.toJson()));

  Future<void> clear(String userId) => _ref.read(preferencesProvider).remove(_key(userId));
}

final profileDraftStoreProvider = Provider<ProfileDraftStore>(ProfileDraftStore.new);

/// How a new player describes their game. Plain words at sign-up; ratings
/// (SkorX, DUPR) come later from real matches.
enum PlayerLevel {
  beginner('Beginner', 'New to pickleball or still learning the rules'),
  intermediate('Intermediate', 'Comfortable rallies, working on the kitchen game'),
  advanced('Advanced', 'Consistent drops, dinks and resets'),
  competitive('Competitive', 'Tournaments and rated matches');

  const PlayerLevel(this.label, this.description);

  final String label;
  final String description;
}
