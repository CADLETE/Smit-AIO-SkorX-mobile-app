import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/sync/connectivity.dart';
import '../../auth/auth_controller.dart';
import '../local_match.dart';
import '../played_matches.dart';
import '../scoring_controller.dart';
import '../verification/verification.dart';
import '../verification/verification_controller.dart';
import '../verification/verification_repository.dart';
import 'match_store.dart';
import 'sync_upload.dart';

/// Where one match stands with SkorX (docs/OFFLINE-SCORING.md §2.3).
enum SyncPhase {
  /// Changed on the phone since SkorX last acknowledged it.
  pending,
  syncing,

  /// SkorX has exactly what the phone has.
  synced,

  /// SkorX refused it; retried with backoff and by "Retry failed sync".
  failed,

  /// Another device changed the match. Waits for the scorer to choose.
  conflict,
}

/// A match's line in the sync ledger. Nothing here is ever the match
/// itself: the match stays in the local store whatever SkorX answers.
@immutable
class CasualSync {
  const CasualSync({
    required this.localId,
    this.ownerUserId,
    this.serverId,
    this.record,
    this.error,
    this.phase = SyncPhase.pending,
    this.syncedSignature,
    this.serverVersion,
    this.attempts = 0,
    this.lastAttemptAt,
    this.nextAttemptAt,
    this.lastSyncedAt,
    this.conflict,
    this.forceNext = false,
    this.finishSeen = false,
  });

  final String localId;

  /// Who scored it; it syncs only while they are signed in.
  final String? ownerUserId;
  final String? serverId;

  /// The last copy SkorX sent back.
  final CasualMatchRecord? record;

  /// Why the last attempt failed, in plain words.
  final String? error;
  final SyncPhase phase;

  /// [syncSignature] of what SkorX last acknowledged.
  final String? syncedSignature;

  /// SkorX's syncVersion at that acknowledgement, sent back as baseVersion.
  final int? serverVersion;
  final int attempts;
  final DateTime? lastAttemptAt;
  final DateTime? nextAttemptAt;
  final DateTime? lastSyncedAt;

  /// In a conflict: what SkorX has.
  final ServerLog? conflict;

  /// The scorer chose "Keep this phone's score": the next send overrides.
  final bool forceNext;

  /// Whether the finish was already counted for analytics.
  final bool finishSeen;

  /// Draft until SkorX has it; after that whatever SkorX says.
  MatchLifecycle get lifecycle => record?.verification.lifecycle ?? MatchLifecycle.draft;

  bool isDirty(LocalMatch m) => serverId == null || syncedSignature != syncSignature(m) || forceNext;

  /// Waiting to reach SkorX, in any way.
  bool get outstanding => phase != SyncPhase.synced;

  CasualSync copyWith({
    String? ownerUserId,
    String? serverId,
    CasualMatchRecord? record,
    String? error,
    bool clearError = false,
    SyncPhase? phase,
    String? syncedSignature,
    int? serverVersion,
    int? attempts,
    DateTime? lastAttemptAt,
    DateTime? nextAttemptAt,
    bool clearNextAttempt = false,
    DateTime? lastSyncedAt,
    ServerLog? conflict,
    bool clearConflict = false,
    bool? forceNext,
    bool? finishSeen,
  }) =>
      CasualSync(
        localId: localId,
        ownerUserId: ownerUserId ?? this.ownerUserId,
        serverId: serverId ?? this.serverId,
        record: record ?? this.record,
        error: clearError ? null : error ?? this.error,
        phase: phase ?? this.phase,
        syncedSignature: syncedSignature ?? this.syncedSignature,
        serverVersion: serverVersion ?? this.serverVersion,
        attempts: attempts ?? this.attempts,
        lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
        nextAttemptAt: clearNextAttempt ? null : nextAttemptAt ?? this.nextAttemptAt,
        lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
        conflict: clearConflict ? null : conflict ?? this.conflict,
        forceNext: forceNext ?? this.forceNext,
        finishSeen: finishSeen ?? this.finishSeen,
      );

  Map<String, dynamic> toJson() => {
        'localId': localId,
        'ownerUserId': ?ownerUserId,
        'serverId': ?serverId,
        if (record != null) 'record': record!.toJson(),
        'error': ?error,
        // "syncing" never survives a restart: it goes back to waiting.
        'phase': (phase == SyncPhase.syncing ? SyncPhase.pending : phase).name,
        'syncedSignature': ?syncedSignature,
        'serverVersion': ?serverVersion,
        'attempts': attempts,
        'lastAttemptAt': ?lastAttemptAt?.toIso8601String(),
        'nextAttemptAt': ?nextAttemptAt?.toIso8601String(),
        'lastSyncedAt': ?lastSyncedAt?.toIso8601String(),
        if (conflict != null) 'conflict': conflict!.toJson(),
        if (forceNext) 'forceNext': true,
        if (finishSeen) 'finishSeen': true,
      };

  factory CasualSync.fromJson(Map<String, dynamic> j) {
    DateTime? at(String k) => j[k] == null ? null : DateTime.parse(j[k] as String);
    return CasualSync(
      localId: j['localId'] as String,
      ownerUserId: j['ownerUserId'] as String?,
      serverId: j['serverId'] as String?,
      record: j['record'] == null ? null : CasualMatchRecord.fromJson(j['record'] as Map<String, dynamic>),
      error: j['error'] as String?,
      // Records from before offline sync have no phase: send them once more
      // through the sync endpoint, which is a no-op for anything SkorX has.
      phase: SyncPhase.values.asNameMap()[j['phase']] ?? SyncPhase.pending,
      syncedSignature: j['syncedSignature'] as String?,
      serverVersion: j['serverVersion'] as int?,
      attempts: j['attempts'] as int? ?? 0,
      lastAttemptAt: at('lastAttemptAt'),
      nextAttemptAt: at('nextAttemptAt'),
      lastSyncedAt: at('lastSyncedAt'),
      conflict: j['conflict'] == null ? null : ServerLog.fromJson(j['conflict'] as Map<String, dynamic>),
      forceNext: j['forceNext'] as bool? ?? false,
      finishSeen: j['finishSeen'] as bool? ?? false,
    );
  }
}

final casualSyncProvider = NotifierProvider<CasualSyncController, Map<String, CasualSync>>(CasualSyncController.new);

/// The lifecycle of a match scored on this phone, by its local id.
final localLifecycleProvider = Provider.family<MatchLifecycle, String>(
  (ref, localId) => ref.watch(casualSyncProvider)[localId]?.lifecycle ?? MatchLifecycle.draft,
);

/// Sends matches scored on this phone to SkorX (docs/OFFLINE-SCORING.md §4).
///
/// Runs by itself: at app start, when the app comes back to the foreground,
/// when SkorX becomes reachable, 4 s after any change (at once when a match
/// starts or ends), and every 60 s while something is waiting. Every send is
/// the whole match and SkorX treats a resend as a no-op, so retries, lost
/// answers and two triggers at once can never add a point twice. One run at
/// a time; a trigger during a run makes it go round once more.
class CasualSyncController extends Notifier<Map<String, CasualSync>> {
  static const _key = 'skorx.casualSync';
  static const debounce = Duration(seconds: 4);
  static const tick = Duration(seconds: 60);
  static const backoff = [Duration(minutes: 1), Duration(minutes: 5), Duration(minutes: 15), Duration(hours: 1)];
  static const maxPerRequest = 10;
  static const maxWeight = 600 * 1024;

  late final Future<void> ready;
  Timer? _debounce;
  Timer? _tick;
  Future<void>? _running;
  bool _again = false;
  bool _againFailed = false;

  @override
  Map<String, CasualSync> build() {
    ready = _restore();
    ref.listen(connectivityProvider, (previous, next) {
      if (next == NetStatus.online && previous != NetStatus.online) _kick();
    });
    ref.listen(currentUserProvider, (previous, next) {
      if (next != null && previous?.id != next.id) _kick();
    });
    final life = AppLifecycleListener(onResume: _kick);
    ref.onDispose(() {
      _debounce?.cancel();
      _tick?.cancel();
      life.dispose();
    });
    Future.microtask(_kick);
    return const {};
  }

  CasualVerificationRepository get _repo => ref.read(casualVerificationRepositoryProvider);
  ConnectivityMonitor get _net => ref.read(connectivityProvider.notifier);
  SyncStatsController get _stats => ref.read(syncStatsProvider.notifier);

  Future<void> _restore() async {
    final raw = await ref.read(preferencesProvider).getString(_key);
    if (raw == null) return;
    try {
      state = {
        for (final e in (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>()) e['localId'] as String: CasualSync.fromJson(e),
      };
    } catch (_) {
      // An unreadable ledger is rebuilt: every match is sent again, which
      // SkorX treats as already processed.
    }
  }

  Future<void> _putAll(Iterable<CasualSync> records) async {
    if (!ref.mounted) return;
    state = {...state, for (final s in records) s.localId: s};
    await ref.read(preferencesProvider).setString(_key, jsonEncode([for (final e in state.values) e.toJson()]));
  }

  Future<void> _put(CasualSync s) => _putAll([s]);

  // ─── Triggers ──────────────────────────────────────────────────────────

  void _kick() {
    if (ref.mounted) unawaited(run());
  }

  /// A match started on this phone: it joins the ledger (it will reach
  /// SkorX, now or later) and is sent at once, so the other players are
  /// asked straight away when there is signal.
  Future<void> track(LocalMatch m) async {
    await ready;
    if (state.containsKey(m.id)) return;
    await _put(CasualSync(localId: m.id, ownerUserId: ref.read(currentUserProvider)?.id));
    if (_net.isOffline) unawaited(_stats.bump(offlineCreated: 1));
    _kick();
  }

  /// The match changed on this phone (a point, an undo, the end...).
  Future<void> changed(LocalMatch m) async {
    await ready;
    var s = state[m.id];
    if (s == null) return;
    if (m.isOver && !s.finishSeen) {
      s = s.copyWith(finishSeen: true);
      if (_net.isOffline) unawaited(_stats.bump(offlineCompleted: 1));
    }
    final waiting = s.phase == SyncPhase.synced && s.isDirty(m) ? s.copyWith(phase: SyncPhase.pending) : s;
    if (!identical(waiting, state[m.id])) await _put(waiting);
    _debounce?.cancel();
    // The end of a match goes at once: the other players are waiting for it.
    if (m.isOver) {
      _kick();
    } else {
      _debounce = Timer(debounce, _kick);
    }
  }

  /// "Sync now": checks the connection and sends whatever is waiting.
  Future<void> syncNow() async {
    await _net.check();
    await run(ignoreOffline: true);
  }

  /// "Retry failed sync": failed matches go again without waiting out their backoff.
  Future<void> retryFailed() async {
    await _net.check();
    await run(includeFailed: true, ignoreOffline: true);
  }

  /// Re-reads SkorX's copy, e.g. when the result screen opens.
  Future<void> refresh(String localId) async {
    await ready;
    final s = state[localId];
    if (s?.serverId == null) return;
    try {
      await _put(s!.copyWith(record: await _repo.match(s.serverId!), clearError: true));
    } catch (e) {
      // Best effort: the screen keeps the copy it already has, and the next
      // sync run fetches SkorX's version anyway. Nothing on the phone is lost.
      debugPrint('Sync: could not refresh server copy of $localId: $e');
    }
  }

  // ─── Conflicts ─────────────────────────────────────────────────────────

  /// Keep this phone's score: SkorX replaces the other device's events,
  /// which it keeps on record as overwritten.
  Future<void> keepMine(String localId) async {
    final s = state[localId];
    if (s == null || s.phase != SyncPhase.conflict) return;
    await _put(s.copyWith(phase: SyncPhase.pending, forceNext: true, clearError: true));
    await syncNow();
  }

  /// Use SkorX's score: this phone's events are replaced by SkorX's. The
  /// phone's version is archived first.
  Future<void> useServer(String localId) async {
    final s = state[localId];
    final server = s?.conflict;
    if (s == null || server == null) return;
    final local = (await _localMatches())[localId];
    if (local == null) return;
    await ref.read(matchStoreProvider).archive(local, 'superseded');
    final scoring = ref.read(scoringControllerProvider.notifier);
    if (ref.read(scoringControllerProvider)?.id == localId) {
      await scoring.replaceEvents(server.events);
    } else {
      await ref.read(playedMatchesProvider.notifier).record(local.copyWith(events: server.events));
    }
    await _put(s.copyWith(phase: SyncPhase.pending, serverVersion: server.syncVersion, clearConflict: true, clearError: true));
    await syncNow();
  }

  // ─── The run ───────────────────────────────────────────────────────────

  /// Sends every match that is waiting. Concurrent calls share one run.
  Future<void> run({bool includeFailed = false, bool ignoreOffline = false}) {
    if (_running != null) {
      _again = true;
      _againFailed |= includeFailed;
      return _running!;
    }
    return _running = _loop(includeFailed, ignoreOffline).whenComplete(() {
      _running = null;
      _scheduleTick();
    });
  }

  Future<void> _loop(bool includeFailed, bool ignoreOffline) async {
    var failed = includeFailed;
    var offlineOk = ignoreOffline;
    do {
      _again = false;
      await _pass(includeFailed: failed, ignoreOffline: offlineOk);
      failed = _againFailed;
      _againFailed = false;
      offlineOk = false;
    } while (_again && ref.mounted);
  }

  Future<Map<String, LocalMatch>> _localMatches() async {
    await ref.read(playedMatchesProvider.notifier).ready;
    await ref.read(scoringControllerProvider.notifier).ready;
    final out = {for (final m in ref.read(playedMatchesProvider)) m.id: m};
    final active = ref.read(scoringControllerProvider);
    if (active != null) out[active.id] = active;
    return out;
  }

  Future<void> _pass({required bool includeFailed, required bool ignoreOffline}) async {
    await ready;
    if (!ref.mounted) return;
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    if (_net.isOffline && !ignoreOffline) return;

    final local = await _localMatches();
    if (!ref.mounted) return;
    final now = DateTime.now();
    final due = <SyncItem>[];
    final settled = <CasualSync>[];
    for (final s in state.values) {
      final m = local[s.localId];
      if (m == null) continue;
      if (s.ownerUserId != null && s.ownerUserId != user.id) continue;
      if (s.phase == SyncPhase.conflict && !s.forceNext) continue;
      if (!s.isDirty(m)) {
        if (s.phase != SyncPhase.synced) settled.add(s.copyWith(phase: SyncPhase.synced));
        continue;
      }
      final waitingOut = s.phase == SyncPhase.failed && !includeFailed && s.nextAttemptAt != null && now.isBefore(s.nextAttemptAt!);
      if (waitingOut) continue;
      due.add(SyncItem(m, baseVersion: s.serverVersion, force: s.forceNext));
    }
    if (settled.isNotEmpty) await _putAll(settled);
    if (due.isEmpty) return;

    final deviceId = await ref.read(deviceIdProvider.future);
    var anyChanged = false;
    for (final chunk in _chunks(due)) {
      if (!ref.mounted) return;
      final sent = {for (final i in chunk) i.match.id: syncSignature(i.match)};
      await _putAll([
        for (final i in chunk) state[i.match.id]!.copyWith(phase: SyncPhase.syncing, ownerUserId: user.id, lastAttemptAt: now),
      ]);
      final clock = Stopwatch()..start();
      try {
        final outcomes = await _repo.sync(
          chunk,
          deviceId: deviceId,
          client: {
            'pending': due.length,
            'attempts': chunk.map((i) => state[i.match.id]!.attempts).fold(0, math.max),
            'platform': defaultTargetPlatform.name,
          },
        );
        if (!ref.mounted) return;
        _net.reportOnline();
        anyChanged = true;
        await _apply(outcomes, sent, clock.elapsedMilliseconds);
      } on ApiException catch (e) {
        if (!ref.mounted) return;
        if (e.isNetwork) {
          // Not a failure: the matches wait for the connection.
          _net.reportOffline();
          await _putAll([for (final i in chunk) state[i.match.id]!.copyWith(phase: SyncPhase.pending)]);
          await _stats.bump(networkFailures: 1);
          return;
        }
        await _fail(chunk, e.message);
      } catch (e) {
        if (!ref.mounted) return;
        debugPrint('Sync failed: $e');
        await _fail(chunk, 'Something went wrong. SkorX will try again.');
      }
    }
    if (anyChanged) refreshVerification(ref.invalidate);
  }

  Future<void> _apply(List<SyncOutcome> outcomes, Map<String, String> sent, int ms) async {
    final now = DateTime.now();
    final current = await _localMatches();
    final updates = <CasualSync>[];
    var ok = 0, failed = 0, conflicts = 0, duplicates = 0;
    for (final o in outcomes) {
      final s = state[o.clientRef];
      if (s == null) continue;
      switch (o.status) {
        case SyncStatus.synced || SyncStatus.alreadyProcessed:
          ok++;
          duplicates += o.status == SyncStatus.alreadyProcessed ? o.duplicates : 0;
          final m = current[o.clientRef];
          // Taps made while the request was out are still waiting.
          final still = m != null && syncSignature(m) != sent[o.clientRef];
          if (still) _again = true;
          updates.add(s.copyWith(
            serverId: o.matchId,
            record: o.record,
            serverVersion: o.syncVersion,
            syncedSignature: sent[o.clientRef],
            phase: still ? SyncPhase.pending : SyncPhase.synced,
            attempts: 0,
            clearError: true,
            clearNextAttempt: true,
            clearConflict: true,
            forceNext: false,
            lastSyncedAt: now,
          ));
        case SyncStatus.conflict:
          conflicts++;
          updates.add(s.copyWith(
            serverId: o.matchId,
            phase: SyncPhase.conflict,
            conflict: o.server,
            forceNext: false,
            error: 'This match was also changed on another device.',
          ));
        case SyncStatus.rejected:
          failed++;
          final attempts = s.attempts + 1;
          updates.add(s.copyWith(
            serverId: o.matchId,
            phase: SyncPhase.failed,
            attempts: attempts,
            error: o.errorMessage ?? 'SkorX could not accept this match.',
            nextAttemptAt: now.add(backoff[math.min(attempts - 1, backoff.length - 1)]),
            forceNext: false,
          ));
      }
    }
    await _putAll(updates);
    await _stats.bump(
      requests: 1,
      synced: ok,
      failed: failed,
      conflicts: conflicts,
      duplicates: duplicates,
      durationMs: ms,
      lastError: updates.where((u) => u.phase == SyncPhase.failed).map((u) => u.error).firstOrNull,
    );
  }

  Future<void> _fail(List<SyncItem> chunk, String message) async {
    final now = DateTime.now();
    await _putAll([
      for (final i in chunk)
        if (state[i.match.id] case final s?)
          s.copyWith(
            phase: SyncPhase.failed,
            attempts: s.attempts + 1,
            error: message,
            nextAttemptAt: now.add(backoff[math.min(s.attempts, backoff.length - 1)]),
          ),
    ]);
    await _stats.bump(requests: 1, failed: chunk.length, lastError: message);
  }

  /// At most 10 matches and ~600 kB per request.
  static List<List<SyncItem>> _chunks(List<SyncItem> items) {
    final out = <List<SyncItem>>[];
    var current = <SyncItem>[];
    var weight = 0;
    for (final i in items) {
      final w = uploadWeight(i.match);
      if (current.isNotEmpty && (current.length >= maxPerRequest || weight + w > maxWeight)) {
        out.add(current);
        current = [];
        weight = 0;
      }
      current.add(i);
      weight += w;
    }
    if (current.isNotEmpty) out.add(current);
    return out;
  }

  /// The safety net: while anything of this player's is waiting, try again
  /// every minute.
  void _scheduleTick() {
    if (!ref.mounted) return;
    final me = ref.read(currentUserProvider)?.id;
    final waiting = state.values.any((s) =>
        (s.ownerUserId == null || s.ownerUserId == me) && (s.phase == SyncPhase.pending || s.phase == SyncPhase.failed));
    if (!waiting) {
      _tick?.cancel();
      _tick = null;
      return;
    }
    _tick ??= Timer(tick, () {
      _tick = null;
      _kick();
    });
  }
}

// ─── What the screens show ─────────────────────────────────────────────

/// The small status on the scoring screen and match cards (§8).
enum SyncBadge {
  /// Not in the ledger (matches from before sync existed): saved here only.
  saved('SAVED', 'Saved on this phone'),
  online('ONLINE', 'Online · sending shortly'),
  offline('OFFLINE · SAVED', 'Offline · saved on this phone'),
  syncing('SYNCING', 'Syncing…'),
  synced('SYNCED', 'Synced with SkorX'),
  failed('SYNC FAILED', 'Sync failed · will retry'),
  attention('NEEDS ATTENTION', 'Match sync needs attention');

  const SyncBadge(this.short, this.label);
  final String short;
  final String label;
}

final syncBadgeProvider = Provider.family<SyncBadge, String>((ref, localId) {
  final s = ref.watch(casualSyncProvider.select((all) => all[localId]));
  final net = ref.watch(connectivityProvider);
  if (s == null) return SyncBadge.saved;
  return switch (s.phase) {
    SyncPhase.conflict => SyncBadge.attention,
    SyncPhase.failed => SyncBadge.failed,
    SyncPhase.syncing => SyncBadge.syncing,
    SyncPhase.synced => SyncBadge.synced,
    SyncPhase.pending => net == NetStatus.offline ? SyncBadge.offline : SyncBadge.online,
  };
});

/// Counts for the Offline matches row and page.
@immutable
class OfflineSummary {
  const OfflineSummary({this.waiting = 0, this.failed = 0, this.conflicts = 0, this.synced = 0, this.otherAccounts = 0});

  /// Not yet on SkorX (pending or syncing).
  final int waiting;
  final int failed;
  final int conflicts;
  final int synced;

  /// Matches on this phone scored by someone else's account.
  final int otherAccounts;

  int get outstanding => waiting + failed + conflicts;
}

final offlineSummaryProvider = Provider<OfflineSummary>((ref) {
  final me = ref.watch(currentUserProvider)?.id;
  final all = ref.watch(casualSyncProvider).values;
  var waiting = 0, failed = 0, conflicts = 0, synced = 0, others = 0;
  for (final s in all) {
    if (s.ownerUserId != null && s.ownerUserId != me) {
      if (s.outstanding) others++;
      continue;
    }
    switch (s.phase) {
      case SyncPhase.pending || SyncPhase.syncing:
        waiting++;
      case SyncPhase.failed:
        failed++;
      case SyncPhase.conflict:
        conflicts++;
      case SyncPhase.synced:
        synced++;
    }
  }
  return OfflineSummary(waiting: waiting, failed: failed, conflicts: conflicts, synced: synced, otherAccounts: others);
});

// ─── Client analytics ──────────────────────────────────────────────────

/// Sync analytics kept on the phone (§10 / brief §22), shown under Sync
/// diagnostics. The server keeps its own per-attempt rows.
@immutable
class SyncStats {
  const SyncStats({
    this.offlineCreated = 0,
    this.offlineCompleted = 0,
    this.requests = 0,
    this.synced = 0,
    this.failed = 0,
    this.networkFailures = 0,
    this.conflicts = 0,
    this.duplicates = 0,
    this.totalMs = 0,
    this.lastError,
    this.lastSyncAt,
  });

  final int offlineCreated;
  final int offlineCompleted;
  final int requests;
  final int synced;
  final int failed;
  final int networkFailures;
  final int conflicts;

  /// Resends SkorX recognised and did not count again.
  final int duplicates;
  final int totalMs;
  final String? lastError;
  final DateTime? lastSyncAt;

  double? get successRate => synced + failed == 0 ? null : synced / (synced + failed);
  int? get averageMs => requests == 0 ? null : totalMs ~/ requests;

  Map<String, dynamic> toJson() => {
        'offlineCreated': offlineCreated,
        'offlineCompleted': offlineCompleted,
        'requests': requests,
        'synced': synced,
        'failed': failed,
        'networkFailures': networkFailures,
        'conflicts': conflicts,
        'duplicates': duplicates,
        'totalMs': totalMs,
        'lastError': ?lastError,
        'lastSyncAt': ?lastSyncAt?.toIso8601String(),
      };

  factory SyncStats.fromJson(Map<String, dynamic> j) {
    int n(String k) => (j[k] as num?)?.toInt() ?? 0;
    return SyncStats(
      offlineCreated: n('offlineCreated'),
      offlineCompleted: n('offlineCompleted'),
      requests: n('requests'),
      synced: n('synced'),
      failed: n('failed'),
      networkFailures: n('networkFailures'),
      conflicts: n('conflicts'),
      duplicates: n('duplicates'),
      totalMs: n('totalMs'),
      lastError: j['lastError'] as String?,
      lastSyncAt: j['lastSyncAt'] == null ? null : DateTime.parse(j['lastSyncAt'] as String),
    );
  }
}

final syncStatsProvider = NotifierProvider<SyncStatsController, SyncStats>(SyncStatsController.new);

class SyncStatsController extends Notifier<SyncStats> {
  static const _key = 'skorx.syncStats';
  late final Future<void> _ready;

  @override
  SyncStats build() {
    _ready = _restore();
    return const SyncStats();
  }

  Future<void> _restore() async {
    try {
      final raw = await ref.read(preferencesProvider).getString(_key);
      if (raw != null && ref.mounted) state = SyncStats.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      // Counters for the sync diagnostics screen only; starting from zero is harmless.
      debugPrint('Sync: stored sync stats were unreadable, starting fresh: $e');
    }
  }

  Future<void> bump({
    int offlineCreated = 0,
    int offlineCompleted = 0,
    int requests = 0,
    int synced = 0,
    int failed = 0,
    int networkFailures = 0,
    int conflicts = 0,
    int duplicates = 0,
    int durationMs = 0,
    String? lastError,
  }) async {
    await _ready;
    if (!ref.mounted) return;
    final s = state;
    state = SyncStats(
      offlineCreated: s.offlineCreated + offlineCreated,
      offlineCompleted: s.offlineCompleted + offlineCompleted,
      requests: s.requests + requests,
      synced: s.synced + synced,
      failed: s.failed + failed,
      networkFailures: s.networkFailures + networkFailures,
      conflicts: s.conflicts + conflicts,
      duplicates: s.duplicates + duplicates,
      totalMs: s.totalMs + durationMs,
      lastError: lastError ?? s.lastError,
      lastSyncAt: synced > 0 ? DateTime.now() : s.lastSyncAt,
    );
    await ref.read(preferencesProvider).setString(_key, jsonEncode(state.toJson()));
  }
}
