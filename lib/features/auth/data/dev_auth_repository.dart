import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api/api_exception.dart';
import '../../player/data/x_code.dart';
import 'current_user.dart';
import 'auth_repository.dart';

/// Debug-build sign-in that never calls the server, so the app can be used
/// on a phone without a working OTP. Like the real app, a fresh install
/// starts signed out (so the whole first launch can be seen) and a sign-in
/// is remembered on the phone. Any 6-digit code signs in:
///
/// - the dev user's own number (95865 45430) is an existing player, who is
///   welcomed back straight into the app;
/// - any other number is a brand-new player, who builds a profile first;
/// - code 000000 is a wrong code and 999999 an expired one, to try the
///   error states.
///
/// The dev user is a player who also owns an organization, so both
/// workspaces can be tried.
class DevAuthRepository implements AuthRepository {
  DevAuthRepository(this._prefs);

  final SharedPreferencesAsync _prefs;
  static const _key = 'skorx.dev.session';

  /// Who is signed in now: [user], or a new player made at sign-in.
  CurrentUser? _current;

  Future<CurrentUser> _remember(CurrentUser user) async {
    _current = user;
    await _prefs.setString(_key, jsonEncode(user.toJson()));
    return user;
  }

  static const user = CurrentUser(
    id: 'dev-user',
    name: 'Smit Ramani',
    phone: '+919586545430',
    xCode: 'S7MR',
    profileComplete: true,
    memberships: [
      Membership(
        organizationId: 'dev-org-1',
        organizationName: 'CADLETE Pickleball',
        role: 'owner',
        capabilities: {
          'editTournament',
          'manageCheckIn',
          'managePayments',
          'managePlayers',
          'manageSchedule',
          'manageSettings',
          'manageStreaming',
        },
      ),
    ],
  );

  @override
  Future<OtpSent> sendOtp(String mobile) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    return const OtpSent(resendAfter: Duration(seconds: 30));
  }

  @override
  Future<CurrentUser> verifyOtp(String mobile, String code) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (code == '000000') throw const ApiException('OTP_INVALID', 'That code is not right.', status: 400);
    if (code == '999999') throw const ApiException('OTP_EXPIRED', 'That code has expired.', status: 400);
    return _remember(
      '+91$mobile' == user.phone
          ? user
          : CurrentUser(
              id: 'dev-new-$mobile',
              name: '',
              phone: '+91$mobile',
              xCode: XCode.generate(),
              profileComplete: false,
              memberships: const [],
            ),
    );
  }

  @override
  Future<RestoredUser?> restore() async {
    final saved = await _prefs.getString(_key);
    if (saved == null) return null;
    final restored = CurrentUser.fromJson(jsonDecode(saved) as Map<String, dynamic>);
    // The dev account always has its latest memberships.
    if (restored.id == user.id) {
      _current = user;
    } else if (restored.xCode == null) {
      // Signed in before X codes existed: give them a dummy one.
      await _remember(CurrentUser(
        id: restored.id,
        name: restored.name,
        phone: restored.phone,
        email: restored.email,
        xCode: XCode.generate(),
        profileComplete: restored.profileComplete,
        memberships: restored.memberships,
      ));
    } else {
      _current = restored;
    }
    return RestoredUser(_current!, fromCache: false);
  }

  @override
  Future<CurrentUser> updateProfile(ProfileUpdate update) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final current = _current ?? user;
    return _remember(
      CurrentUser(
        id: current.id,
        name: update.name,
        phone: current.phone,
        email: current.email,
        xCode: current.xCode,
        profileComplete: true,
        memberships: current.memberships,
      ),
    );
  }

  @override
  Future<void> signOut() async {
    _current = null;
    await _prefs.remove(_key);
  }
}
