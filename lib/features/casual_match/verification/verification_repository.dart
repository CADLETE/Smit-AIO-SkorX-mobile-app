import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../local_match.dart';
import '../offline/sync_upload.dart';
import 'verification.dart';

/// One player of a casual match as sent to SkorX: yourself, a registered
/// player by account id, or a guest by name (a match with a guest never counts).
class LineupPlayer {
  const LineupPlayer.me() : userId = null, guestName = null, isMe = true;
  const LineupPlayer.registered(String this.userId) : guestName = null, isMe = false;
  const LineupPlayer.guest(String this.guestName) : userId = null, isMe = false;

  final bool isMe;
  final String? userId;
  final String? guestName;

  Map<String, dynamic> toJson() => isMe ? {'isMe': true} : userId != null ? {'userId': userId} : {'displayName': guestName};
}

class NewCasualMatch {
  const NewCasualMatch({
    required this.clientRef,
    required this.sportId,
    required this.categoryId,
    required this.sideA,
    required this.sideB,
    required this.sideANames,
    required this.sideBNames,
    required this.rules,
    required this.startedAt,
    this.firstServer,
    this.locationName,
  });

  /// The phone's own id for the match: a retried create returns the same one.
  final String clientRef;
  final String sportId;
  final String categoryId;
  final List<LineupPlayer> sideA;
  final List<LineupPlayer> sideB;

  /// Only for the sample stand-in; the server takes names from accounts.
  final List<String> sideANames;
  final List<String> sideBNames;
  final Map<String, dynamic> rules;
  final DateTime startedAt;
  final String? firstServer;
  final String? locationName;

  Map<String, dynamic> toJson() => {
        'clientRef': clientRef,
        'sportId': sportId,
        'category': categoryId,
        'sideA': [for (final p in sideA) p.toJson()],
        'sideB': [for (final p in sideB) p.toJson()],
        'rules': rules,
        'startedAt': startedAt.toUtc().toIso8601String(),
        'firstServer': ?firstServer,
        'locationName': ?locationName,
      };
}

class CasualResult {
  const CasualResult({required this.games, this.outcome = 'completed', this.winnerSide, required this.completedAt});

  /// (side A, side B) per game.
  final List<(int, int)> games;

  /// completed, retirement or walkover.
  final String outcome;
  final String? winnerSide;
  final DateTime completedAt;

  Map<String, dynamic> toJson() => {
        'sideAScores': [for (final g in games) g.$1],
        'sideBScores': [for (final g in games) g.$2],
        'outcome': outcome,
        'winnerSide': ?winnerSide,
        'completedAt': completedAt.toUtc().toIso8601String(),
      };
}

/// Counts for the profile and the badge.
class CasualSummary {
  const CasualSummary({this.verified = 0, this.pending = 0, this.disputed = 0, this.requests = 0});

  final int verified;
  final int pending;
  final int disputed;
  final int requests;
}

/// One match to send in a sync request (docs/OFFLINE-SCORING.md §5).
class SyncItem {
  const SyncItem(this.match, {this.baseVersion, this.force = false});

  final LocalMatch match;

  /// The server's syncVersion this phone last had acknowledged.
  final int? baseVersion;

  /// Conflict resolution: keep this phone's log over another device's.
  final bool force;
}

enum SyncStatus { synced, alreadyProcessed, conflict, rejected }

/// SkorX's side of a match in a conflict, to compare with this phone's.
class ServerLog {
  const ServerLog({required this.events, required this.games, required this.syncVersion, this.deviceId});

  final List<RecordedEvent> events;
  final List<(int, int)> games;
  final int syncVersion;
  final String? deviceId;

  Map<String, dynamic> toJson() => {
        'events': [for (final e in events) e.toJson()],
        'games': [for (final g in games) [g.$1, g.$2]],
        'syncVersion': syncVersion,
        'deviceId': deviceId,
      };

  factory ServerLog.fromJson(Map<String, dynamic> j) => ServerLog(
        events: [for (final e in (j['events'] as List<dynamic>)) RecordedEvent.fromJson(e as Map<String, dynamic>)],
        games: [for (final g in (j['games'] as List<dynamic>)) ((g as List<dynamic>)[0] as int, g[1] as int)],
        syncVersion: j['syncVersion'] as int? ?? 0,
        deviceId: j['deviceId'] as String?,
      );

  /// From the API's `server` block, whose events use the upload's shape.
  factory ServerLog.fromApi(Map<String, dynamic> j) => ServerLog(
        events: [
          for (final e in (j['events'] as List<dynamic>).cast<Map<String, dynamic>>())
            RecordedEvent.fromJson({
              'id': e['id'],
              'recordedAt': e['recordedAt'],
              'kind': e['kind'],
              'side': e['side'],
              'serverNumber': e['serverNumber'],
            }),
        ],
        games: [
          for (final g in (j['games'] as List<dynamic>).cast<Map<String, dynamic>>()) ((g['a'] as num).toInt(), (g['b'] as num).toInt()),
        ],
        syncVersion: (j['syncVersion'] as num?)?.toInt() ?? 0,
        deviceId: j['deviceId'] as String?,
      );
}

/// What SkorX did with one match of a sync request.
class SyncOutcome {
  const SyncOutcome({
    required this.clientRef,
    required this.status,
    this.matchId,
    this.syncVersion,
    this.accepted = 0,
    this.duplicates = 0,
    this.reverted = 0,
    this.errorCode,
    this.errorMessage,
    this.record,
    this.server,
  });

  final String clientRef;
  final SyncStatus status;
  final String? matchId;
  final int? syncVersion;
  final int accepted;
  final int duplicates;
  final int reverted;
  final String? errorCode;
  final String? errorMessage;
  final CasualMatchRecord? record;
  final ServerLog? server;

  factory SyncOutcome.fromJson(Map<String, dynamic> j) {
    final error = j['error'] as Map<String, dynamic>?;
    int n(String k) => (j[k] as num?)?.toInt() ?? 0;
    return SyncOutcome(
      clientRef: j['clientRef'] as String,
      status: switch (j['status']) {
        'SYNCED' => SyncStatus.synced,
        'ALREADY_PROCESSED' => SyncStatus.alreadyProcessed,
        'CONFLICT' => SyncStatus.conflict,
        _ => SyncStatus.rejected,
      },
      matchId: j['matchId'] as String?,
      syncVersion: (j['syncVersion'] as num?)?.toInt(),
      accepted: n('accepted'),
      duplicates: n('duplicates'),
      reverted: n('reverted'),
      errorCode: error?['code'] as String?,
      errorMessage: error?['message'] as String?,
      record: j['match'] == null ? null : CasualMatchRecord.fromJson(j['match'] as Map<String, dynamic>),
      server: j['server'] == null ? null : ServerLog.fromApi(j['server'] as Map<String, dynamic>),
    );
  }
}

/// Outcome of one item in Accept all.
class AcceptAllResult {
  const AcceptAllResult({required this.accepted, required this.failed});

  final int accepted;

  /// Match id → why it was not accepted.
  final Map<String, String> failed;
}

/// Casual match verification. Method names mirror the API
/// (backend `src/matches/casual-matches.controller.ts`).
abstract class CasualVerificationRepository {
  /// `POST /casual-matches`
  Future<CasualMatchRecord> create(NewCasualMatch match);

  /// `POST /casual-matches/:id/result`
  Future<CasualMatchRecord> submitResult(String id, CasualResult result);

  /// `GET /casual-matches/:id`
  Future<CasualMatchRecord> match(String id);

  /// `GET /casual-matches/requests`
  Future<List<CasualMatchRecord>> requests();

  /// `GET /casual-matches?scope=pending`
  Future<List<CasualMatchRecord>> pending();

  /// `GET /casual-matches/summary`
  Future<CasualSummary> summary();

  /// `POST /casual-matches/:id/accept {round}`
  Future<CasualMatchRecord> accept(String id, int round);

  /// `POST /casual-matches/:id/reject {round, reason, note}`
  Future<CasualMatchRecord> reject(String id, int round, RejectionReason reason, {String? note});

  /// `POST /casual-matches/requests/accept-all`
  Future<AcceptAllResult> acceptAll(List<(String, int)> items);

  /// `POST /casual-matches/:id/cancel`
  Future<CasualMatchRecord> cancel(String id);

  /// `POST /casual-matches/:id/remind`
  Future<int> remind(String id);

  /// `POST /casual-matches/sync`: up to 10 matches, each whole. Idempotent:
  /// sending the same items again changes nothing.
  Future<List<SyncOutcome>> sync(List<SyncItem> items, {required String deviceId, Map<String, dynamic>? client});
}

class ApiCasualVerificationRepository implements CasualVerificationRepository {
  const ApiCasualVerificationRepository(this._api);

  final ApiClient _api;

  CasualMatchRecord _one(Map<String, dynamic> j) => CasualMatchRecord.fromJson(j);

  @override
  Future<CasualMatchRecord> create(NewCasualMatch match) async =>
      _one(await _api.post<Map<String, dynamic>>('/casual-matches', body: match.toJson()));

  @override
  Future<CasualMatchRecord> submitResult(String id, CasualResult result) async =>
      _one(await _api.post<Map<String, dynamic>>('/casual-matches/$id/result', body: result.toJson()));

  @override
  Future<CasualMatchRecord> match(String id) async => _one(await _api.get<Map<String, dynamic>>('/casual-matches/$id'));

  @override
  Future<List<CasualMatchRecord>> requests() async {
    final data = await _api.get<List<dynamic>>('/casual-matches/requests');
    return [for (final m in data) _one(m as Map<String, dynamic>)];
  }

  @override
  Future<List<CasualMatchRecord>> pending() async {
    final (data, _) = await _api.getPage<List<dynamic>>('/casual-matches', query: {'scope': 'pending', 'pageSize': 50});
    return [for (final m in data) _one(m as Map<String, dynamic>)];
  }

  @override
  Future<CasualSummary> summary() async {
    final j = await _api.get<Map<String, dynamic>>('/casual-matches/summary');
    int n(String k) => (j[k] as num?)?.toInt() ?? 0;
    return CasualSummary(verified: n('verified'), pending: n('pending'), disputed: n('disputed'), requests: n('requests'));
  }

  @override
  Future<CasualMatchRecord> accept(String id, int round) async =>
      _one(await _api.post<Map<String, dynamic>>('/casual-matches/$id/accept', body: {'round': round}));

  @override
  Future<CasualMatchRecord> reject(String id, int round, RejectionReason reason, {String? note}) async => _one(
        await _api.post<Map<String, dynamic>>(
          '/casual-matches/$id/reject',
          body: {'round': round, 'reason': reason.id, if (note != null && note.trim().isNotEmpty) 'note': note.trim()},
        ),
      );

  @override
  Future<AcceptAllResult> acceptAll(List<(String, int)> items) async {
    final j = await _api.post<Map<String, dynamic>>(
      '/casual-matches/requests/accept-all',
      body: {
        'items': [for (final (id, round) in items) {'matchId': id, 'round': round}],
      },
    );
    final results = (j['results'] as List<dynamic>).cast<Map<String, dynamic>>();
    return AcceptAllResult(
      accepted: (j['accepted'] as num).toInt(),
      failed: {for (final r in results) if (r['ok'] != true) r['matchId'] as String: r['message'] as String? ?? 'Not accepted.'},
    );
  }

  @override
  Future<CasualMatchRecord> cancel(String id) async =>
      _one(await _api.post<Map<String, dynamic>>('/casual-matches/$id/cancel'));

  @override
  Future<int> remind(String id) async =>
      ((await _api.post<Map<String, dynamic>>('/casual-matches/$id/remind'))['reminded'] as num).toInt();

  @override
  Future<List<SyncOutcome>> sync(List<SyncItem> items, {required String deviceId, Map<String, dynamic>? client}) async {
    final j = await _api.post<Map<String, dynamic>>('/casual-matches/sync', body: {
      'deviceId': deviceId,
      'client': ?client,
      'matches': [for (final i in items) uploadOf(i.match, baseVersion: i.baseVersion, force: i.force)],
    });
    return [for (final r in (j['results'] as List<dynamic>)) SyncOutcome.fromJson(r as Map<String, dynamic>)];
  }
}

// ─── Debug stand-in ──────────────────────────────────────────────────────

/// Debug builds without a server: the same rules as the API, kept on the
/// phone so the whole flow can be tried. Sample players answer on their own
/// a little after the result is in (as real players would, later), and a few
/// requests from sample players are waiting for "You".
class SampleCasualVerificationRepository implements CasualVerificationRepository {
  SampleCasualVerificationRepository(
    this._prefs, {
    this.latency = const Duration(milliseconds: 350),
    DateTime Function()? clock,
    this.reachable,
  }) : _clock = clock ?? DateTime.now;

  static const _key = 'skorx.sampleCasualServer';
  static const _syncKey = 'skorx.sampleCasualSync';

  /// How long each sample player takes to confirm after the result is in.
  static const answerAfter = Duration(seconds: 20);

  final SharedPreferencesAsync _prefs;
  final Duration latency;
  final DateTime Function() _clock;

  /// Whether the phone is online. Sync fails like a real request without
  /// it, so offline scoring can be tried with airplane mode.
  final Future<bool> Function()? reachable;
  List<_SampleMatch>? _matches;

  /// Keeps, per clientRef, the version, signature and result the stand-in
  /// server has, so resends come back as already processed.
  @override
  Future<List<SyncOutcome>> sync(List<SyncItem> items, {required String deviceId, Map<String, dynamic>? client}) async {
    if (reachable != null && !await reachable!()) {
      throw const ApiException(ApiException.network, 'No internet connection. Check your network and try again.');
    }
    Map<String, dynamic> ledger;
    try {
      ledger = jsonDecode(await _prefs.getString(_syncKey) ?? '{}') as Map<String, dynamic>;
    } catch (_) {
      ledger = {};
    }
    final out = <SyncOutcome>[];
    for (final item in items) {
      final m = item.match;
      var record = await create(NewCasualMatch(
        clientRef: m.id,
        sportId: m.sportId,
        categoryId: m.categoryId,
        sideA: lineupOf(m.sideA, m.details.sideAIds),
        sideB: lineupOf(m.sideB, m.details.sideBIds),
        sideANames: m.sideA,
        sideBNames: m.sideB,
        rules: m.rules.toJson(),
        startedAt: m.startedAt,
        firstServer: m.firstServer.name,
        locationName: m.locationName,
      ));
      final seen = (ledger[m.id] as Map<String, dynamic>?) ?? {'version': 0, 'events': 0};
      final signature = syncSignature(m);
      final result = resultForUpload(m);
      final resultKey = result == null ? null : jsonEncode({...result}..remove('completedAt'));
      if (result != null && resultKey != seen['result']) {
        final a = (result['sideAScores'] as List<dynamic>).cast<int>();
        final b = (result['sideBScores'] as List<dynamic>).cast<int>();
        record = await submitResult(
          record.id,
          CasualResult(
            games: [for (final (i, x) in a.indexed) (x, b[i])],
            outcome: result['outcome'] as String,
            winnerSide: result['winnerSide'] as String?,
            completedAt: m.finishedAt ?? _clock(),
          ),
        );
      }
      final same = seen['signature'] == signature;
      final before = seen['events'] as int? ?? 0;
      final version = (seen['version'] as int? ?? 0) + (same ? 0 : 1);
      ledger[m.id] = {'version': version, 'events': m.events.length, 'signature': signature, 'result': resultKey};
      out.add(SyncOutcome(
        clientRef: m.id,
        status: same ? SyncStatus.alreadyProcessed : SyncStatus.synced,
        matchId: record.id,
        syncVersion: version,
        accepted: same ? 0 : (m.events.length - before).clamp(0, m.events.length),
        duplicates: same ? m.events.length : before.clamp(0, m.events.length),
        record: record,
      ));
    }
    await _prefs.setString(_syncKey, jsonEncode(ledger));
    return out;
  }

  Future<List<_SampleMatch>> _load() async {
    if (_matches != null) return _matches!;
    final raw = await _prefs.getString(_key);
    if (raw != null) {
      try {
        return _matches = [for (final j in (jsonDecode(raw) as List<dynamic>)) _SampleMatch.fromJson(j as Map<String, dynamic>)];
      } catch (_) {}
    }
    return _matches = _seed(_clock());
  }

  Future<void> _save() async => _prefs.setString(_key, jsonEncode([for (final m in _matches!) m.toJson()]));

  Future<T> _run<T>(T Function(List<_SampleMatch> all, DateTime now) body) async {
    await Future<void>.delayed(latency);
    final all = await _load();
    final now = _clock();
    for (final m in all) {
      m.autoAnswer(now);
    }
    final out = body(all, now);
    await _save();
    return out;
  }

  _SampleMatch _find(List<_SampleMatch> all, String id) =>
      all.where((m) => m.id == id).firstOrNull ?? (throw const ApiException('RESOURCE_NOT_FOUND', 'Match not found.', status: 404));

  @override
  Future<CasualMatchRecord> create(NewCasualMatch match) => _run((all, now) {
        final existing = all.where((m) => m.clientRef == match.clientRef).firstOrNull;
        if (existing != null) return existing.toRecord(now);
        List<_SamplePlayer> side(String s, List<LineupPlayer> players, List<String> names) => [
              for (final (i, p) in players.indexed)
                _SamplePlayer(
                  name: p.isMe ? 'You' : names[i],
                  side: s,
                  userId: p.isMe ? 'me' : p.userId,
                  isCreator: p.isMe,
                  state: p.isMe ? PlayerCheckState.confirmed : (p.userId == null ? PlayerCheckState.guest : PlayerCheckState.pending),
                ),
            ];
        final m = _SampleMatch(
          id: 'cm-${now.microsecondsSinceEpoch}',
          clientRef: match.clientRef,
          categoryId: match.categoryId,
          players: [...side('a', match.sideA, match.sideANames), ...side('b', match.sideB, match.sideBNames)],
          startedAt: match.startedAt,
          locationName: match.locationName,
          createdBy: 'You',
        );
        // Sample players say they are in shortly after being added.
        for (final (i, p) in m.players.where((p) => p.state == PlayerCheckState.pending).indexed) {
          p.answerAt = now.add(answerAfter * (i + 1));
        }
        all.insert(0, m);
        return m.toRecord(now);
      });

  @override
  Future<CasualMatchRecord> submitResult(String id, CasualResult result) => _run((all, now) {
        final m = _find(all, id);
        if (m.cancelled) throw const ApiException('MATCH_CANCELLED', 'This match was cancelled.', status: 409);
        m.games = result.games;
        m.completedAt = result.completedAt;
        m.winnerSide = result.winnerSide;
        m.round++;
        for (final (i, p) in m.players.indexed) {
          if (p.state == PlayerCheckState.guest || p.isCreator) continue;
          if (p.state == PlayerCheckState.confirmed) p.state = PlayerCheckState.joined;
          if (p.state == PlayerCheckState.rejected) p.state = PlayerCheckState.pending;
          p.answerAt = now.add(answerAfter * (i + 1));
        }
        return m.toRecord(now);
      });

  @override
  Future<CasualMatchRecord> match(String id) => _run((all, now) => _find(all, id).toRecord(now));

  @override
  Future<List<CasualMatchRecord>> requests() => _run((all, now) => [
        // As on the server: only answers still owed, not ones already given.
        for (final m in all)
          if (m.toRecord(now).verification.canRespond && m.players.any((p) => p.userId == 'me' && p.state != PlayerCheckState.rejected))
            m.toRecord(now),
      ]);

  @override
  Future<List<CasualMatchRecord>> pending() => _run((all, now) => [
        for (final m in all)
          if (!m.toRecord(now).verification.official && !m.cancelled) m.toRecord(now),
      ]);

  @override
  Future<CasualSummary> summary() => _run((all, now) {
        final records = [for (final m in all) m.toRecord(now)];
        return CasualSummary(
          verified: records.where((r) => r.verification.official).length,
          pending: records.where((r) => r.verification.lifecycle.waiting).length,
          disputed: records.where((r) => r.verification.lifecycle.troubled).length,
          requests: records.where((r) => r.verification.canRespond).length,
        );
      });

  _SamplePlayer _meIn(_SampleMatch m, int round) {
    final me = m.players.where((p) => p.userId == 'me').firstOrNull;
    if (me == null) throw const ApiException('RESOURCE_NOT_FOUND', 'You are not a player in this match.', status: 404);
    if (m.cancelled) throw const ApiException('MATCH_CANCELLED', 'This match was cancelled.', status: 409);
    if (round != m.round) {
      throw const ApiException('STALE_CONFIRMATION', 'This match changed since you opened it. Review the new details.', status: 409);
    }
    return me;
  }

  @override
  Future<CasualMatchRecord> accept(String id, int round) => _run((all, now) {
        final m = _find(all, id);
        final me = _meIn(m, round);
        me.state = m.completedAt == null ? PlayerCheckState.joined : PlayerCheckState.confirmed;
        return m.toRecord(now);
      });

  @override
  Future<CasualMatchRecord> reject(String id, int round, RejectionReason reason, {String? note}) => _run((all, now) {
        final m = _find(all, id);
        final me = _meIn(m, round);
        me
          ..state = PlayerCheckState.rejected
          ..rejection = reason
          ..note = note;
        return m.toRecord(now);
      });

  @override
  Future<AcceptAllResult> acceptAll(List<(String, int)> items) async {
    var accepted = 0;
    final failed = <String, String>{};
    for (final (id, round) in items) {
      try {
        await accept(id, round);
        accepted++;
      } on ApiException catch (e) {
        failed[id] = e.message;
      }
    }
    return AcceptAllResult(accepted: accepted, failed: failed);
  }

  @override
  Future<CasualMatchRecord> cancel(String id) => _run((all, now) {
        final m = _find(all, id)..cancelled = true;
        return m.toRecord(now);
      });

  @override
  Future<int> remind(String id) => _run((all, now) {
        final m = _find(all, id);
        final waiting = m.players.where((p) => p.state == PlayerCheckState.pending || p.state == PlayerCheckState.joined).toList();
        for (final p in waiting) {
          p.answerAt = now.add(answerAfter);
        }
        return waiting.length;
      });

  /// Three requests waiting for "You": two results to confirm, one match to join.
  static List<_SampleMatch> _seed(DateTime now) {
    _SamplePlayer p(String name, String side, PlayerCheckState state, {bool me = false, bool creator = false}) =>
        _SamplePlayer(name: name, side: side, userId: me ? 'me' : 'u-${name.toLowerCase().replaceAll(' ', '-')}', isCreator: creator, state: state);
    const c = PlayerCheckState.confirmed;
    const w = PlayerCheckState.pending;
    return [
      _SampleMatch(
        id: 'cm-seed-1',
        categoryId: 'mens_doubles',
        createdBy: 'Kamal Parmar',
        players: [p('You', 'a', w, me: true), p('Hardik Suthar', 'a', c), p('Kamal Parmar', 'b', c, creator: true), p('Anand Varsada', 'b', w)],
        startedAt: now.subtract(const Duration(hours: 3)),
        completedAt: now.subtract(const Duration(hours: 2, minutes: 20)),
        games: const [(7, 11), (11, 9), (8, 11)],
        winnerSide: 'b',
        round: 1,
        locationName: 'Pickle Blitz Arena',
      ),
      _SampleMatch(
        id: 'cm-seed-2',
        categoryId: 'singles',
        createdBy: 'Riya Shah',
        players: [p('Riya Shah', 'a', c, creator: true), p('You', 'b', w, me: true)],
        startedAt: now.subtract(const Duration(days: 1, hours: 2)),
        completedAt: now.subtract(const Duration(days: 1, hours: 1, minutes: 30)),
        games: const [(11, 6), (9, 11), (11, 8)],
        winnerSide: 'a',
        round: 1,
        locationName: 'CADLETE Club',
      ),
      _SampleMatch(
        id: 'cm-seed-3',
        categoryId: 'mens_doubles',
        createdBy: 'Dev Patel',
        players: [p('Dev Patel', 'a', c, creator: true), p('Parth Bhatt', 'a', w), p('You', 'b', w, me: true), p('Kabir Rao', 'b', w)],
        startedAt: now.subtract(const Duration(minutes: 25)),
        locationName: 'Rapid Frolic Courts',
      ),
    ];
  }
}

class _SamplePlayer {
  _SamplePlayer({required this.name, required this.side, required this.userId, required this.isCreator, required this.state, this.answerAt});

  final String name;
  final String side;
  final String? userId;
  final bool isCreator;
  PlayerCheckState state;
  RejectionReason? rejection;
  String? note;

  /// When this sample player answers on their own (null: never, e.g. "You").
  DateTime? answerAt;

  Map<String, dynamic> toJson() => {
        'name': name,
        'side': side,
        'userId': userId,
        'isCreator': isCreator,
        'state': state.name,
        'rejection': rejection?.id,
        'note': note,
        'answerAt': answerAt?.toIso8601String(),
      };

  factory _SamplePlayer.fromJson(Map<String, dynamic> j) => _SamplePlayer(
        name: j['name'] as String,
        side: j['side'] as String,
        userId: j['userId'] as String?,
        isCreator: j['isCreator'] as bool? ?? false,
        state: PlayerCheckState.parse(j['state'] as String?),
        answerAt: j['answerAt'] == null ? null : DateTime.parse(j['answerAt'] as String),
      )
        ..rejection = RejectionReason.parse(j['rejection'] as String?)
        ..note = j['note'] as String?;
}

class _SampleMatch {
  _SampleMatch({
    required this.id,
    required this.categoryId,
    required this.players,
    required this.startedAt,
    required this.createdBy,
    this.clientRef,
    this.completedAt,
    this.games = const [],
    this.winnerSide,
    this.round = 0,
    this.locationName,
  });

  final String id;
  final String? clientRef;
  final String categoryId;
  final List<_SamplePlayer> players;
  final DateTime startedAt;
  final String createdBy;
  final String? locationName;
  DateTime? completedAt;
  List<(int, int)> games;
  String? winnerSide;
  int round;
  bool cancelled = false;

  static const _window = Duration(days: 14);

  void autoAnswer(DateTime now) {
    for (final p in players) {
      final at = p.answerAt;
      if (at == null || at.isAfter(now) || cancelled) continue;
      p.answerAt = null;
      if (p.state == PlayerCheckState.pending || p.state == PlayerCheckState.joined) {
        p.state = completedAt == null ? PlayerCheckState.joined : PlayerCheckState.confirmed;
      }
    }
  }

  MatchLifecycle _lifecycle(DateTime now) {
    if (cancelled) return MatchLifecycle.cancelled;
    final rejected = players.where((p) => p.state == PlayerCheckState.rejected).toList();
    if (rejected.isNotEmpty) {
      const denial = {RejectionReason.didNotPlay, RejectionReason.notPresent, RejectionReason.matchCancelled};
      return rejected.any((p) => denial.contains(p.rejection)) ? MatchLifecycle.rejected : MatchLifecycle.disputed;
    }
    final done = completedAt != null;
    if (done && players.every((p) => p.state == PlayerCheckState.confirmed)) return MatchLifecycle.verified;
    if (players.any((p) => p.state == PlayerCheckState.guest)) return MatchLifecycle.unofficial;
    if (now.isAfter((completedAt ?? startedAt).add(_window))) return MatchLifecycle.expired;
    if (done) return MatchLifecycle.completed;
    return players.every((p) => p.state != PlayerCheckState.pending) ? MatchLifecycle.inProgress : MatchLifecycle.pendingConfirmation;
  }

  CasualMatchRecord toRecord(DateTime now) {
    final lifecycle = _lifecycle(now);
    final me = players.where((p) => p.userId == 'me').firstOrNull;
    final open = !cancelled && lifecycle != MatchLifecycle.verified && lifecycle != MatchLifecycle.expired;
    final canRespond = me != null && !me.isCreator && open && me.state != PlayerCheckState.confirmed &&
        !(completedAt == null && me.state == PlayerCheckState.joined);
    return CasualMatchRecord(
      id: id,
      clientRef: clientRef,
      categoryId: categoryId,
      sideA: [for (final p in players) if (p.side == 'a') p.name],
      sideB: [for (final p in players) if (p.side == 'b') p.name],
      games: games,
      startedAt: startedAt,
      completedAt: completedAt,
      locationName: locationName,
      winnerSide: winnerSide,
      verification: MatchVerification(
        lifecycle: lifecycle,
        round: round,
        official: lifecycle == MatchLifecycle.verified,
        players: [
          for (final p in players)
            PlayerCheck(
              name: p.name,
              side: p.side,
              state: completedAt == null && p.state == PlayerCheckState.joined ? PlayerCheckState.confirmed : p.state,
              userId: p.userId,
              isCreator: p.isCreator,
              isMe: p.userId == 'me',
              rejection: p.rejection,
              rejectionNote: p.note,
            ),
        ],
        confirmed: players.where((p) => p.state == PlayerCheckState.confirmed).length,
        required: players.length,
        createdBy: createdBy,
        confirmBy: (completedAt ?? startedAt).add(_window),
        isCreator: me?.isCreator ?? false,
        request: canRespond ? (completedAt == null ? RequestKind.join : RequestKind.result) : null,
        canRespond: canRespond,
        canRemind: (me?.isCreator ?? false) && open && players.any((p) => p.state == PlayerCheckState.pending || p.state == PlayerCheckState.joined),
        canCancel: (me?.isCreator ?? false) && open,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'clientRef': clientRef,
        'categoryId': categoryId,
        'players': [for (final p in players) p.toJson()],
        'startedAt': startedAt.toIso8601String(),
        'createdBy': createdBy,
        'locationName': locationName,
        'completedAt': completedAt?.toIso8601String(),
        'games': [for (final g in games) [g.$1, g.$2]],
        'winnerSide': winnerSide,
        'round': round,
        'cancelled': cancelled,
      };

  factory _SampleMatch.fromJson(Map<String, dynamic> j) => _SampleMatch(
        id: j['id'] as String,
        clientRef: j['clientRef'] as String?,
        categoryId: j['categoryId'] as String,
        players: [for (final p in (j['players'] as List<dynamic>)) _SamplePlayer.fromJson(p as Map<String, dynamic>)],
        startedAt: DateTime.parse(j['startedAt'] as String),
        createdBy: j['createdBy'] as String,
        locationName: j['locationName'] as String?,
        completedAt: j['completedAt'] == null ? null : DateTime.parse(j['completedAt'] as String),
        games: [for (final g in (j['games'] as List<dynamic>)) ((g as List<dynamic>)[0] as int, g[1] as int)],
        winnerSide: j['winnerSide'] as String?,
        round: j['round'] as int? ?? 0,
      )..cancelled = j['cancelled'] as bool? ?? false;
}
