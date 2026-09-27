import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How long sample repositories wait before answering, so debug builds show
/// the loading states a real network would. Tests set it to zero.
final sampleLatencyProvider = Provider<Duration>((ref) => const Duration(milliseconds: 350));

/// How often a sample live match plays its next rally, so debug builds show
/// a match moving. Null holds every match still; tests set it to null so no
/// timer is left running.
final sampleLiveTickProvider = Provider<Duration?>((ref) => const Duration(seconds: 6));

/// Waits [latency], or not at all when it is zero (no timer is left behind).
Future<void> simulateLatency(Duration latency) =>
    latency == Duration.zero ? Future<void>.value() : Future<void>.delayed(latency);
