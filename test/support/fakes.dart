import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:skorx/core/api/api_exception.dart';
import 'package:skorx/core/app_permissions.dart';
import 'package:skorx/core/sample_latency.dart';
import 'package:skorx/features/auth/auth_controller.dart';
import 'package:skorx/features/auth/data/auth_repository.dart';
import 'package:skorx/features/auth/data/current_user.dart';
import 'package:skorx/features/subscription/data/billing_repository.dart';
import 'package:skorx/features/subscription/data/plans.dart';
import 'package:skorx/features/subscription/data/subscription.dart';
import 'package:skorx/features/subscription/subscription_controller.dart';

/// A player on SkorX Pro (annual, renewing), for tests of Pro screens.
class ProBillingRepository implements BillingRepository {
  const ProBillingRepository();

  static final summaryValue = SubscriptionSummary(
    tier: PlanTier.pro,
    status: SubscriptionStatus.active,
    plan: ProPlan.annual,
    startedAt: DateTime(2026, 9, 1),
    endsAt: DateTime(2027, 8, 31, 23, 59, 59),
    nextBillingDate: DateTime(2027, 9, 1),
    autoRenew: true,
    payment: PaymentState.paid,
    entitlements: {for (final f in ProFeature.values) f.key},
  );

  @override
  Future<SubscriptionSummary> summary() async => summaryValue;

  @override
  Future<List<BillingRecord>> history() async => const [];

  @override
  Future<PriceQuote> quote(ProPlan plan, {String? coupon}) async => PriceQuote(
        plan: plan,
        subtotalPaise: plan.price * 100,
        discountPaise: 0,
        gstRate: 0.18,
        gstPaise: (plan.price * 18).round(),
        totalPaise: plan.price * 118,
        startsAt: DateTime(2027, 9, 1),
        endsAt: DateTime(2027, 9, 1).add(Duration(days: plan.months * 30)),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

/// Turns on the system "reduce motion" setting. Home has looping animations
/// (floating ball, live pulse) that never settle otherwise; with reduced
/// motion they stay still, which is also what those users get.
void useReducedMotion(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

/// Fresh in-memory preferences for each test.
void useInMemoryPreferences() {
  SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
}

Membership membership(String orgId, String name, String role, [Set<String> capabilities = const {}]) =>
    Membership(organizationId: orgId, organizationName: name, role: role, capabilities: capabilities);

CurrentUser user({
  String id = 'u1',
  String name = 'Smit Ramani',
  bool profileComplete = true,
  List<Membership> memberships = const [],
}) =>
    CurrentUser(id: id, name: name, phone: '+919586545430', profileComplete: profileComplete, memberships: memberships);

/// A phone that has already been through the first-launch introduction.
Future<void> markIntroSeen() => SharedPreferencesAsync().setBool('skorx.onboarding.completed', true);

/// Sign-in without a server. Accepts [validCode] only; [expiredCode] fails
/// as expired. A number's first sign-in comes back with an incomplete
/// profile, like the real API.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.stored, this.validCode = '123456', this.expiredCode = '999999', this.signInAs});

  /// The session found at launch, if any.
  RestoredUser? stored;
  final String validCode;
  final String expiredCode;

  /// Thrown by the next send / profile save, then cleared (a flaky network).
  ApiException? sendError;
  ApiException? profileError;

  /// Who a successful sign-in returns. Defaults to a brand-new player.
  final CurrentUser? signInAs;
  final List<String> sentTo = [];
  ProfileUpdate? savedProfile;
  bool signedOut = false;

  @override
  Future<RestoredUser?> restore() async => stored;

  @override
  Future<OtpSent> sendOtp(String mobile) async {
    final error = sendError;
    sendError = null;
    if (error != null) throw error;
    sentTo.add(mobile);
    return const OtpSent(resendAfter: Duration(seconds: 30));
  }

  @override
  Future<CurrentUser> verifyOtp(String mobile, String code) async {
    if (code == expiredCode) throw const ApiException('OTP_EXPIRED', 'This code has expired.', status: 400);
    if (code != validCode) throw const ApiException('OTP_INVALID', 'That code is not right. 4 tries left.', status: 400);
    return signInAs ?? user(name: '', profileComplete: false);
  }

  @override
  Future<CurrentUser> updateProfile(ProfileUpdate update) async {
    final error = profileError;
    profileError = null;
    if (error != null) throw error;
    savedProfile = update;
    return user(name: update.name);
  }

  @override
  Future<void> signOut() async => signedOut = true;
}

/// Permissions without a phone: every request is allowed and recorded.
class FakeAppPermissions implements AppPermissions {
  final List<AppPermission> requested = [];

  @override
  Future<PermissionAnswer> status(AppPermission permission) async => PermissionAnswer.notAsked;

  @override
  Future<PermissionAnswer> request(AppPermission permission) async {
    requested.add(permission);
    return PermissionAnswer.granted;
  }

  @override
  Future<void> openSettings() async {}
}

/// [realBilling] bills through the app's own Test Mode stand-in, starting on
/// Free like a new account. Otherwise the player is on Pro, so screens built
/// before SkorX Pro keep showing everything they test.
List<Override> appOverrides(FakeAuthRepository repo, {AppPermissions? permissions, bool realBilling = false}) => [
      authRepositoryProvider.overrideWithValue(repo),
      if (!realBilling) billingRepositoryProvider.overrideWithValue(const ProBillingRepository()),
      appPermissionsProvider.overrideWithValue(permissions ?? FakeAppPermissions()),
      preferencesProvider.overrideWithValue(SharedPreferencesAsync()),
      // Sample data answers at once, so settled tests see it and leave no timers.
      sampleLatencyProvider.overrideWithValue(Duration.zero),
      // Live matches hold still, so no rally timer outlives a test.
      sampleLiveTickProvider.overrideWithValue(null),
    ];
