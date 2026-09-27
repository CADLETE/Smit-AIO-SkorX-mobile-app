import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import '../../../core/sample_latency.dart';
import '../../../core/sync/connectivity.dart';
import '../../auth/auth_controller.dart';
import 'verification.dart';
import 'verification_repository.dart';

// Sending phone-scored matches to SkorX lives in the offline sync engine.
export '../offline/sync_engine.dart';

final casualVerificationRepositoryProvider = Provider<CasualVerificationRepository>((ref) {
  if (useRealApi || !kDebugMode) return ApiCasualVerificationRepository(ref.watch(apiClientProvider));
  return SampleCasualVerificationRepository(
    ref.watch(preferencesProvider),
    latency: ref.watch(sampleLatencyProvider),
    reachable: ref.watch(reachabilityProbeProvider),
  );
});

/// Matches waiting for the signed-in player's confirmation (Match requests).
final matchRequestsProvider = FutureProvider<List<CasualMatchRecord>>((ref) async {
  if (ref.watch(currentUserProvider) == null) return const [];
  return ref.watch(casualVerificationRepositoryProvider).requests();
});

/// The badge: how many requests are waiting.
final matchRequestCountProvider = Provider<int>((ref) => ref.watch(matchRequestsProvider).value?.length ?? 0);

/// One casual match with its verification, by SkorX id.
final casualMatchProvider = FutureProvider.autoDispose.family<CasualMatchRecord, String>(
  (ref, id) => ref.watch(casualVerificationRepositoryProvider).match(id),
);

/// Verified / pending counts for My Paddle.
final casualSummaryProvider = FutureProvider<CasualSummary>((ref) async {
  if (ref.watch(currentUserProvider) == null) return const CasualSummary();
  return ref.watch(casualVerificationRepositoryProvider).summary();
});

/// After any answer, everything that shows verification is read again.
/// Takes `ref.invalidate` from a provider or a widget.
void refreshVerification(void Function(ProviderOrFamily) invalidate) {
  invalidate(matchRequestsProvider);
  invalidate(casualSummaryProvider);
  invalidate(casualMatchProvider);
}
