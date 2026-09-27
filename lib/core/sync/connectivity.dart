import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../features/auth/auth_controller.dart';
import '../api/api_client.dart' show apiBaseUrl;

/// Whether SkorX can be reached right now (docs/OFFLINE-SCORING.md §2.2).
enum NetStatus { unknown, online, offline }

/// True when SkorX answered. Any HTTP answer counts: the question is
/// whether the phone can get through, not whether one route exists.
typedef ReachabilityProbe = Future<bool> Function();

Future<bool> _apiAnswers() async {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 5),
    validateStatus: (_) => true,
  ));
  try {
    await dio.get<Object?>('$apiBaseUrl/health/live');
    return true;
  } on DioException {
    return false;
  } finally {
    dio.close(force: true);
  }
}

/// Builds with sample data have no server: they check the internet itself,
/// so airplane mode on a test phone behaves like the real thing.
Future<bool> _internetAnswers() async {
  try {
    final found = await InternetAddress.lookup('skorx.in').timeout(const Duration(seconds: 5));
    return found.isNotEmpty && found.first.rawAddress.isNotEmpty;
  } catch (_) {
    return false;
  }
}

final reachabilityProbeProvider = Provider<ReachabilityProbe>((ref) {
  // Widget tests have no network and must not leave timers behind.
  if (Platform.environment.containsKey('FLUTTER_TEST')) return () async => true;
  return useRealApi ? _apiAnswers : _internetAnswers;
});

final connectivityProvider = NotifierProvider<ConnectivityMonitor, NetStatus>(ConnectivityMonitor.new);

/// Reachability, not the Wi-Fi icon: Wi-Fi without internet, a captive
/// portal or a server outage all count as offline. Offline, it checks again
/// after 5, 10, 20 and then every 30 seconds, and at once when the app comes
/// back to the foreground. Sync results report in too, so a failed send
/// flips the status without waiting for a probe.
class ConnectivityMonitor extends Notifier<NetStatus> {
  static const _retry = [Duration(seconds: 5), Duration(seconds: 10), Duration(seconds: 20), Duration(seconds: 30)];

  Timer? _timer;
  int _misses = 0;
  Future<bool>? _probing;

  @override
  NetStatus build() {
    final life = AppLifecycleListener(onResume: () => unawaited(check()));
    ref.onDispose(() {
      _timer?.cancel();
      life.dispose();
    });
    Future.microtask(check);
    return NetStatus.unknown;
  }

  bool get isOffline => state == NetStatus.offline;

  /// Probes now. Concurrent callers share one probe.
  Future<bool> check() => _probing ??= _probe().whenComplete(() => _probing = null);

  Future<bool> _probe() async {
    final ok = await ref.read(reachabilityProbeProvider)();
    if (!ref.mounted) return ok;
    ok ? reportOnline() : reportOffline();
    return ok;
  }

  void reportOnline() {
    _misses = 0;
    _timer?.cancel();
    if (state != NetStatus.online) state = NetStatus.online;
  }

  void reportOffline() {
    if (state != NetStatus.offline) state = NetStatus.offline;
    _timer?.cancel();
    _timer = Timer(_retry[_misses.clamp(0, _retry.length - 1)], () {
      if (ref.mounted) unawaited(check());
    });
    _misses++;
  }
}

/// This phone's id for sync, made once and kept. Tells the server which
/// device scored which events (docs/OFFLINE-SCORING.md §6).
final deviceIdProvider = FutureProvider<String>((ref) async {
  const key = 'skorx.deviceId';
  final prefs = ref.read(preferencesProvider);
  final saved = await prefs.getString(key);
  if (saved != null && saved.isNotEmpty) return saved;
  final id = const Uuid().v4();
  await prefs.setString(key, id);
  return id;
});
