import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How long sample repositories wait before answering, so debug builds show
/// the loading states a real network would. Tests set it to zero.
final sampleLatencyProvider = Provider<Duration>((ref) => const Duration(milliseconds: 350));

/// Waits [latency], or not at all when it is zero (no timer is left behind).
Future<void> simulateLatency(Duration latency) =>
    latency == Duration.zero ? Future<void>.value() : Future<void>.delayed(latency);
