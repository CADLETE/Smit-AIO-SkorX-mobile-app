import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/api/api_exception.dart';
import '../../../sports/core/score_state.dart';
import '../../../sports/core/scoring_engine.dart';
import '../../../sports/sport_registry.dart';
import '../../auth/auth_controller.dart';
import '../data/organizer_repository.dart';
import '../data/tms_models.dart';

/// Offline: taps are saved and waiting. Syncing: sending them. Synced: the
/// server has every tap. Conflict: another device scored first; the official
/// decides, nothing is overwritten.
enum SyncStatus { loading, synced, syncing, offline, conflict, failed }

class ConsoleState {
  const ConsoleState({
    this.match,
    this.category,
    this.confirmed = const [],
    this.version = 0,
    this.pending = const [],
    this.sync = SyncStatus.loading,
    this.message,
    this.theirs,
  });

  /// The last copy of the match from the server.
  final TmsMatch? match;
  final OrgCategory? category;

  /// Events the server has applied, up to [version].
  final List<ScoringEvent> confirmed;
  final int version;

  /// Taps made on this phone that the server has not confirmed, oldest first.
  final List<ScoreWrite> pending;
  final SyncStatus sync;

  /// Plain words for the official when something needs their attention.
  final String? message;

  /// In a conflict: the server's score, to compare with this phone's.
  final ScoreState? theirs;

  bool get ready => match != null && category != null;

  MatchSetup get setup =>
      MatchSetup(rules: category!.rules, playersPerSide: category!.playersPerSide, firstServer: Side.a);

  /// The score as this phone sees it: the server's events plus the taps
  /// still waiting to be sent.
  ScoreState get score {
    final events = [...confirmed];
    for (final w in pending) {
      _applyWrite(events, w);
    }
    return consoleEngine.replay(setup, events);
  }

  ConsoleState copyWith({
    TmsMatch? match,
    OrgCategory? category,
    List<ScoringEvent>? confirmed,
    int? version,
    List<ScoreWrite>? pending,
    SyncStatus? sync,
    String? Function()? message,
    ScoreState? Function()? theirs,
  }) =>
      ConsoleState(
        match: match ?? this.match,
        category: category ?? this.category,
        confirmed: confirmed ?? this.confirmed,
        version: version ?? this.version,
        pending: pending ?? this.pending,
        sync: sync ?? this.sync,
        message: message == null ? this.message : message(),
        theirs: theirs == null ? this.theirs : theirs(),
      );
}

/// Tournament play is pickleball today; the engine comes from the sport
/// registry like everywhere else.
final consoleEngine = SportRegistry.standard.of('pickleball')!.engine;

void _applyWrite(List<ScoringEvent> events, ScoreWrite w) {
  switch (w.kind) {
    case ScoreWriteKind.rally:
      events.add(RallyWon(w.side!));
    case ScoreWriteKind.serve:
      events.add(ServeCorrected(w.serve!));
    case ScoreWriteKind.undo:
      if (events.isNotEmpty) events.removeLast();
  }
}

final matchConsoleProvider =
    NotifierProvider.autoDispose.family<MatchConsoleController, ConsoleState, (String, String)>(MatchConsoleController.new);

/// Scoring one tournament match from this phone, local first:
///
/// tap → saved on the phone → score on screen → sent in order, one at a
/// time, each with its own id and the version it was based on.
///
/// A failed send stops the queue and keeps every tap. Resending is always
/// safe (the server ignores an id it has seen). If another device scored
/// first the server refuses the write and the official chooses which score
/// stands. Keyed by (tournament id, match id).
class MatchConsoleController extends Notifier<ConsoleState> {
  MatchConsoleController(this.key);

  final (String, String) key;
  String get _tournamentId => key.$1;
  String get _matchId => key.$2;

  static const _uuid = Uuid();
  static const retryAfter = Duration(seconds: 5);

  String get _storageKey => 'skorx.tmsScore.$_matchId';
  OrganizerRepository get _repo => ref.read(organizerRepositoryProvider);

  Timer? _retry;
  bool _flushing = false;

  @override
  ConsoleState build() {
    ref.onDispose(() => _retry?.cancel());
    Future.microtask(_load);
    return const ConsoleState();
  }

  Future<void> _load() async {
    // Taps saved before the app closed or lost signal come back first.
    List<ScoreWrite> saved = const [];
    try {
      final raw = await ref.read(preferencesProvider).getString(_storageKey);
      if (raw != null) {
        saved = [
          for (final w in (jsonDecode(raw) as List<dynamic>)) ScoreWrite.fromJson(w as Map<String, dynamic>),
        ];
      }
    } catch (_) {
      // Unreadable queue from an older version: start from the server.
    }
    if (!ref.mounted) return;
    state = state.copyWith(pending: saved);
    await refresh();
    if (ref.mounted && state.pending.isNotEmpty) unawaited(_flush());
  }

  /// Reloads the match and the server's score.
  Future<void> refresh() async {
    try {
      final t = await _repo.tournament(_tournamentId);
      final m = await _repo.match(_matchId);
      final log = await _repo.scoreLog(_matchId);
      if (!ref.mounted) return;
      state = state.copyWith(
        match: m,
        category: t.category(m.categoryId),
        confirmed: log.events,
        version: log.version,
        sync: state.pending.isEmpty ? SyncStatus.synced : SyncStatus.offline,
        message: () => null,
      );
    } on ApiException catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(sync: e.isNetwork ? SyncStatus.offline : SyncStatus.failed, message: () => e.message);
      if (e.isNetwork) _scheduleRetry();
    }
  }

  /// [side] won the rally. Ignored once the match is decided on this phone.
  Future<void> rally(Side side) async {
    if (!state.ready || state.score.isOver || state.match!.state != MatchState.live) return;
    await _enqueue(ScoreWriteKind.rally, side: side);
  }

  Future<void> correctServe(ServeState serve) async {
    if (!state.ready || state.score.isOver) return;
    await _enqueue(ScoreWriteKind.serve, serve: serve);
  }

  /// Takes back the last action. A tap still waiting on this phone is simply
  /// dropped; one the server has is undone there.
  Future<void> undo() async {
    if (!state.ready) return;
    final pending = state.pending;
    if (pending.isNotEmpty && pending.last.kind != ScoreWriteKind.undo && !_flushing) {
      _setPending(pending.sublist(0, pending.length - 1));
      await _persist();
      return;
    }
    if (state.score.rallies == 0 && state.confirmed.isEmpty && pending.isEmpty) return;
    await _enqueue(ScoreWriteKind.undo);
  }

  Future<void> _enqueue(ScoreWriteKind kind, {Side? side, ServeState? serve}) async {
    final write = ScoreWrite(clientEventId: _uuid.v4(), baseVersion: state.version, kind: kind, side: side, serve: serve);
    _setPending([...state.pending, write]);
    await _persist();
    unawaited(_flush());
  }

  /// Every change to the queue is one synchronous state update, so the
  /// screen never shows a tap twice or loses one to a concurrent send.
  void _setPending(List<ScoreWrite> pending) =>
      state = state.copyWith(pending: pending, sync: pending.isEmpty ? SyncStatus.synced : state.sync);

  Future<void> _persisting = Future.value();

  /// Writes the queue to the phone, in order. Sending waits for this, so
  /// nothing reaches the server that is not also saved here. (A tap is on
  /// disk within milliseconds; only a crash inside that window could lose it.)
  Future<void> _persist() {
    final prefs = ref.read(preferencesProvider);
    return _persisting = _persisting.then((_) {
      if (!ref.mounted) return null;
      final pending = state.pending;
      return pending.isEmpty
          ? prefs.remove(_storageKey)
          : prefs.setString(_storageKey, jsonEncode([for (final w in pending) w.toJson()]));
    });
  }

  /// Sends waiting taps in order. Stops at the first failure.
  Future<void> _flush() async {
    if (_flushing || state.sync == SyncStatus.conflict) return;
    _flushing = true;
    _retry?.cancel();
    try {
      await _persisting;
      while (ref.mounted && state.pending.isNotEmpty) {
        state = state.copyWith(sync: SyncStatus.syncing);
        final write = state.pending.first.rebased(state.version);
        try {
          final ack = await _repo.score(_matchId, write);
          if (!ref.mounted) return;
          var confirmed = [...state.confirmed];
          var version = ack.scoreVersion;
          if (ack.scoreVersion == write.baseVersion + 1) {
            _applyWrite(confirmed, write);
          } else {
            // A resend the server had already applied, with other writes
            // since: take the server's record rather than guess.
            final log = await _repo.scoreLog(_matchId);
            if (!ref.mounted) return;
            confirmed = log.events;
            version = log.version;
          }
          // Confirmed and removed from the queue in one step. Taps made while
          // this was in flight stay queued.
          state = state.copyWith(
            match: ack,
            confirmed: confirmed,
            version: version,
            pending: [for (final w in state.pending) if (w.clientEventId != write.clientEventId) w],
          );
          await _persist();
        } on ApiException catch (e) {
          if (!ref.mounted) return;
          if (e.code == scoreConflict) {
            await _enterConflict();
          } else if (e.isNetwork) {
            state = state.copyWith(sync: SyncStatus.offline, message: () => null);
            _scheduleRetry();
          } else {
            state = state.copyWith(sync: SyncStatus.failed, message: () => e.message);
          }
          return;
        }
      }
      if (ref.mounted) state = state.copyWith(sync: SyncStatus.synced, message: () => null);
    } finally {
      _flushing = false;
    }
  }

  /// Rebases every waiting tap on the server's current version. The server
  /// validates each against the rules, so a stale "point" cannot land on a
  /// finished game.
  Future<void> _enterConflict() async {
    try {
      final log = await _repo.scoreLog(_matchId);
      final m = await _repo.match(_matchId);
      if (!ref.mounted) return;
      state = state.copyWith(
        match: m,
        sync: SyncStatus.conflict,
        theirs: () => consoleEngine.replay(state.setup, log.events),
        message: () => 'The score changed on another device.',
      );
      _conflictLog = log;
    } on ApiException catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(sync: SyncStatus.offline, message: () => e.message);
    }
  }

  ScoreLog? _conflictLog;

  /// Conflict: the other device's score stands. This phone's waiting taps
  /// are dropped.
  Future<void> useServerScore() async {
    final log = _conflictLog;
    if (log == null) return;
    state = state.copyWith(
      confirmed: log.events,
      version: log.version,
      pending: const [],
      theirs: () => null,
      sync: SyncStatus.synced,
    );
    await _persist();
    _conflictLog = null;
  }

  /// Conflict: add this phone's waiting taps on top of the other device's.
  Future<void> addMyTaps() async {
    final log = _conflictLog;
    if (log == null) return;
    state = state.copyWith(confirmed: log.events, version: log.version, theirs: () => null, sync: SyncStatus.syncing);
    _conflictLog = null;
    await _flush();
  }

  /// Try the waiting taps again now.
  Future<void> retryNow() async {
    if (state.sync == SyncStatus.failed) {
      // A write the server refused outright (not a network problem) cannot
      // succeed on resend; drop it so the rest of the queue can go.
      _setPending(state.pending.isEmpty ? const [] : state.pending.sublist(1));
      await _persist();
    }
    if (!state.ready) {
      await refresh();
    }
    await _flush();
  }

  void _scheduleRetry() {
    _retry?.cancel();
    _retry = Timer(retryAfter, () {
      if (ref.mounted) unawaited(_flush());
    });
  }

  /// Call, start, pause or resume. Needs the network.
  Future<String?> command(MatchCommand command) async {
    try {
      final m = await _repo.command(_matchId, command);
      if (ref.mounted) state = state.copyWith(match: m, message: () => null);
      return null;
    } on ApiException catch (e) {
      return e.isNetwork ? 'No connection. Try again when the phone is back online.' : e.message;
    }
  }

  /// Closes the match with the score on screen. Every tap must be synced
  /// first, so the server confirms exactly what the official saw.
  Future<String?> confirmResult() async {
    if (state.pending.isNotEmpty) {
      return 'Some points are still on this phone. Wait for them to sync, then confirm.';
    }
    try {
      final m = await _repo.confirmResult(_matchId, state.version);
      if (!ref.mounted) return null;
      state = state.copyWith(match: m, version: m.scoreVersion);
      await ref.read(preferencesProvider).remove(_storageKey);
      return null;
    } on ApiException catch (e) {
      if (e.code == scoreConflict) {
        await _enterConflict();
        return 'The score changed on another device. Check it before confirming.';
      }
      return e.isNetwork ? 'No connection. The score is safe on this phone; confirm when back online.' : e.message;
    }
  }
}
