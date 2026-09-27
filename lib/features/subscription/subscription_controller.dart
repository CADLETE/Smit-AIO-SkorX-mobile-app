import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sample_latency.dart';
import '../auth/auth_controller.dart';
import 'data/billing_repository.dart';
import 'data/dev_billing_repository.dart';
import 'data/plans.dart';
import 'data/subscription.dart';

/// Where SkorX Pro is billed: the API in release builds (and with
/// `--dart-define=REAL_AUTH=true`), the on-phone Razorpay Test Mode stand-in
/// in debug builds, for the signed-in account.
final billingRepositoryProvider = Provider<BillingRepository>((ref) {
  if (useRealApi) return ApiBillingRepository(ref.watch(apiClientProvider));
  final user = ref.watch(currentUserProvider);
  return DevBillingRepository(
    ref.watch(preferencesProvider),
    userId: user?.id ?? 'signed-out',
    customerName: user?.name ?? '',
    customerPhone: user?.phone,
    customerEmail: user?.email,
    latency: ref.watch(sampleLatencyProvider),
  );
});

/// The one answer, for the whole app, to "is this player Free or Pro, and
/// what may they use?". Screens never work it out themselves: they watch
/// this, [isProProvider] or [canAccessProvider].
///
/// Reloaded when the account changes, when the app comes back to the
/// foreground and when the running period ends, so an expired plan falls
/// back to Free without a restart. The server decides; this only asks.
final subscriptionProvider = AsyncNotifierProvider<SubscriptionController, SubscriptionSummary>(SubscriptionController.new);

class SubscriptionController extends AsyncNotifier<SubscriptionSummary> {
  Timer? _expiry;

  @override
  Future<SubscriptionSummary> build() async {
    final userId = ref.watch(currentUserProvider.select((u) => u?.id));
    final repo = ref.watch(billingRepositoryProvider);
    final lifecycle = AppLifecycleListener(onResume: refresh);
    ref.onDispose(() {
      lifecycle.dispose();
      _expiry?.cancel();
    });
    if (userId == null) return SubscriptionSummary.free;
    return _watchExpiry(await repo.summary());
  }

  BillingRepository get _repo => ref.read(billingRepositoryProvider);

  /// Re-reads the plan in place, keeping the current one on screen meanwhile.
  Future<void> refresh() async {
    if (ref.read(currentUserProvider) == null) return;
    try {
      apply(await _repo.summary());
    } catch (_) {
      // Offline: keep what we have; access is checked again on the server.
    }
  }

  /// The plan the server just returned (after a payment, a renewal change).
  void apply(SubscriptionSummary summary) {
    if (ref.mounted) state = AsyncData(_watchExpiry(summary));
  }

  Future<void> setAutoRenew(bool on) async => apply(await _repo.setAutoRenew(on));

  /// Test Mode tools.
  Future<void> simulateRenewal() async => apply(await _repo.simulateRenewal());
  Future<void> expireNow() async => apply(await _repo.expireNow());

  SubscriptionSummary _watchExpiry(SubscriptionSummary s) {
    _expiry?.cancel();
    final end = s.endsAt;
    if (end != null) {
      final wait = end.difference(DateTime.now()) + const Duration(seconds: 1);
      // Timers only for periods ending soon; longer ones are caught on resume.
      if (wait < const Duration(days: 1)) _expiry = Timer(wait.isNegative ? Duration.zero : wait, refresh);
    }
    return s;
  }
}

/// Free or Pro. Free until the server says otherwise.
final isProProvider = Provider<bool>((ref) => ref.watch(subscriptionProvider).value?.isPro ?? false);

/// Whether the player may use [ProFeature] now: `canAccessFeature` for the UI.
final canAccessProvider = Provider.family<bool, ProFeature>(
  (ref, feature) => ref.watch(subscriptionProvider).value?.can(feature) ?? false,
);
