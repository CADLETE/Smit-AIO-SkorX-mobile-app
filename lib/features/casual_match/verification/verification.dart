import 'package:flutter/foundation.dart';

/// Casual match verification (docs/CASUAL-VERIFICATION.md). The server
/// decides every state here; the app only shows it and sends answers.
///
/// The rule: a casual match counts toward stats, rating, rankings and
/// achievements only once every registered player in it confirms the result.

/// Where a casual match is in its life, as the player sees it.
enum MatchLifecycle {
  /// Scored on this phone, not yet sent to SkorX (offline).
  draft('Not sent yet'),
  pendingConfirmation('Pending confirmation'),
  inProgress('In progress'),

  /// Result in, waiting for players to confirm it.
  completed('Awaiting confirmation'),
  verified('Verified'),
  disputed('Disputed'),
  rejected('Rejected'),
  cancelled('Cancelled'),
  expired('Expired'),

  /// Has a guest (no SkorX account), so it can never be verified.
  unofficial('Unofficial');

  const MatchLifecycle(this.label);
  final String label;

  static MatchLifecycle parse(String? s) => switch (s) {
        'pending_confirmation' => pendingConfirmation,
        'in_progress' => inProgress,
        'completed' => completed,
        'verified' => verified,
        'disputed' => disputed,
        'rejected' => rejected,
        'cancelled' => cancelled,
        'expired' => expired,
        'unofficial' => unofficial,
        _ => pendingConfirmation,
      };

  /// Only verified matches reach stats, rating and rankings.
  bool get official => this == verified;

  /// Still waiting on someone (shown under Pending matches).
  bool get waiting => this == draft || this == pendingConfirmation || this == inProgress || this == completed;

  /// Went wrong: a player said no, or it lapsed.
  bool get troubled => this == disputed || this == rejected || this == expired;
}

/// Where one player is in confirming.
enum PlayerCheckState {
  confirmed('Confirmed'),

  /// Said they are in the match; the latest result still needs them.
  joined('Joined'),
  pending('Pending'),
  rejected('Rejected'),
  guest('Guest'),
  unavailable('Account closed');

  const PlayerCheckState(this.label);
  final String label;

  static PlayerCheckState parse(String? s) => values.asNameMap()[s] ?? pending;
}

/// Why a player says no. The API ids match `MatchRejectionReason`.
enum RejectionReason {
  didNotPlay('did_not_play', 'I did not play this match'),
  wrongPlayer('wrong_player', 'Wrong player added'),
  wrongScore('wrong_score', 'Wrong score'),
  wrongTeam('wrong_team', 'Wrong opponent/team'),
  notPresent('not_present', 'I was not present'),
  matchCancelled('match_cancelled', 'Match was cancelled'),
  other('other', 'Other');

  const RejectionReason(this.id, this.label);
  final String id;
  final String label;

  static RejectionReason? parse(String? id) => values.where((r) => r.id == id).firstOrNull;
}

/// What the viewer is being asked to confirm.
enum RequestKind {
  /// Added to a match that has no result yet: confirm you are playing.
  join,

  /// The result is in (or changed): confirm it.
  result,

  /// A verified match's score is being corrected.
  correction;

  static RequestKind? parse(String? s) => values.asNameMap()[s];
}

@immutable
class PlayerCheck {
  const PlayerCheck({
    required this.name,
    required this.side,
    required this.state,
    this.userId,
    this.isCreator = false,
    this.isMe = false,
    this.rejection,
    this.rejectionNote,
  });

  final String name;

  /// 'a' or 'b'.
  final String side;
  final PlayerCheckState state;
  final String? userId;
  final bool isCreator;
  final bool isMe;
  final RejectionReason? rejection;
  final String? rejectionNote;

  factory PlayerCheck.fromJson(Map<String, dynamic> j) => PlayerCheck(
        name: j['name'] as String,
        side: j['side'] as String,
        state: PlayerCheckState.parse(j['state'] as String?),
        userId: j['userId'] as String?,
        isCreator: j['isCreator'] as bool? ?? false,
        isMe: j['isMe'] as bool? ?? false,
        rejection: RejectionReason.parse(j['rejectionReason'] as String?),
        rejectionNote: j['rejectionNote'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'side': side,
        'state': state.name,
        'userId': ?userId,
        'isCreator': isCreator,
        'isMe': isMe,
        'rejectionReason': ?rejection?.id,
        'rejectionNote': ?rejectionNote,
      };
}

/// A score change proposed for a verified match.
@immutable
class ScoreCorrection {
  const ScoreCorrection({required this.games, required this.proposedBy, this.reason});

  final List<(int, int)> games;
  final String proposedBy;
  final String? reason;
}

/// The verification block of a casual match, as the signed-in player sees it.
@immutable
class MatchVerification {
  const MatchVerification({
    required this.lifecycle,
    required this.round,
    required this.players,
    required this.confirmed,
    required this.required,
    this.official = false,
    this.createdBy,
    this.confirmBy,
    this.flagged = false,
    this.correction,
    this.isCreator = false,
    this.request,
    this.canRespond = false,
    this.canRemind = false,
    this.canCancel = false,
  });

  final MatchLifecycle lifecycle;

  /// What the player confirms is pinned to this round, so a score changed
  /// while their screen was open is never confirmed by mistake.
  final int round;
  final List<PlayerCheck> players;
  final int confirmed;
  final int required;
  final bool official;
  final String? createdBy;
  final DateTime? confirmBy;

  /// A player disputed it after it was verified; SkorX reviews it.
  final bool flagged;
  final ScoreCorrection? correction;
  final bool isCreator;
  final RequestKind? request;
  final bool canRespond;
  final bool canRemind;
  final bool canCancel;

  /// Registered players who have not confirmed yet ("Waiting for Dia").
  List<PlayerCheck> get waitingFor => [
        for (final p in players)
          if (p.state == PlayerCheckState.pending || p.state == PlayerCheckState.joined) p,
      ];

  bool get hasGuests => players.any((p) => p.state == PlayerCheckState.guest);

  factory MatchVerification.fromJson(Map<String, dynamic> j) {
    final viewer = (j['viewer'] as Map<String, dynamic>?) ?? const {};
    final progress = (j['progress'] as Map<String, dynamic>?) ?? const {};
    final correction = j['correction'] as Map<String, dynamic>?;
    List<int> ints(Object? o) => [for (final x in (o as List<dynamic>? ?? const [])) (x as num).toInt()];
    return MatchVerification(
      lifecycle: MatchLifecycle.parse(j['lifecycle'] as String?),
      round: (j['round'] as num?)?.toInt() ?? 0,
      official: j['official'] as bool? ?? false,
      players: [for (final p in (j['players'] as List<dynamic>? ?? const [])) PlayerCheck.fromJson(p as Map<String, dynamic>)],
      confirmed: (progress['confirmed'] as num?)?.toInt() ?? 0,
      required: (progress['required'] as num?)?.toInt() ?? 0,
      createdBy: (j['createdBy'] as Map<String, dynamic>?)?['name'] as String?,
      confirmBy: j['confirmBy'] == null ? null : DateTime.parse(j['confirmBy'] as String).toLocal(),
      flagged: j['flagged'] as bool? ?? false,
      correction: correction == null
          ? null
          : ScoreCorrection(
              games: [
                for (final (i, a) in ints(correction['sideAScores']).indexed) (a, ints(correction['sideBScores'])[i]),
              ],
              proposedBy: correction['proposedBy'] as String? ?? '',
              reason: correction['reason'] as String?,
            ),
      isCreator: viewer['role'] == 'creator',
      request: RequestKind.parse(viewer['request'] as String?),
      canRespond: viewer['canRespond'] as bool? ?? false,
      canRemind: viewer['canRemind'] as bool? ?? false,
      canCancel: viewer['canCancel'] as bool? ?? false,
    );
  }

  /// The sample server's copy of the same shape.
  Map<String, dynamic> toJson() => {
        'lifecycle': switch (lifecycle) {
          MatchLifecycle.pendingConfirmation => 'pending_confirmation',
          MatchLifecycle.inProgress => 'in_progress',
          final l => l.name,
        },
        'round': round,
        'official': official,
        'players': [for (final p in players) p.toJson()],
        'progress': {'confirmed': confirmed, 'required': required},
        if (createdBy != null) 'createdBy': {'name': createdBy},
        if (confirmBy != null) 'confirmBy': confirmBy!.toUtc().toIso8601String(),
        'flagged': flagged,
        'viewer': {
          'role': isCreator ? 'creator' : 'player',
          if (request != null) 'request': request!.name,
          'canRespond': canRespond,
          'canRemind': canRemind,
          'canCancel': canCancel,
        },
      };
}

/// A casual match as SkorX stores it: who, the score, and its verification.
@immutable
class CasualMatchRecord {
  const CasualMatchRecord({
    required this.id,
    required this.categoryId,
    required this.sideA,
    required this.sideB,
    required this.games,
    required this.verification,
    required this.startedAt,
    this.clientRef,
    this.completedAt,
    this.locationName,
    this.winnerSide,
  });

  final String id;

  /// The id of the match on the phone that created it.
  final String? clientRef;
  final String categoryId;
  final List<String> sideA;
  final List<String> sideB;

  /// Game scores as (side A, side B).
  final List<(int, int)> games;
  final MatchVerification verification;
  final DateTime startedAt;
  final DateTime? completedAt;
  final String? locationName;

  /// 'a' or 'b' once the result is in.
  final String? winnerSide;

  bool get hasResult => games.isNotEmpty && completedAt != null;

  /// "11–7, 11–9"
  String get scoreLabel => games.map((g) => '${g.$1}–${g.$2}').join(', ');

  /// "Ronak + Kamal vs Riya + Dev"
  String get lineup => '${sideA.map(_first).join(' + ')} vs ${sideB.map(_first).join(' + ')}';

  static String _first(String name) => name.split(' ').first;

  factory CasualMatchRecord.fromJson(Map<String, dynamic> j) {
    List<int> scores(Object? side) => [for (final x in ((side as Map<String, dynamic>)['score'] as List<dynamic>)) (x as num).toInt()];
    final a = scores(j['sideA']);
    final b = scores(j['sideB']);
    final participants = (j['participants'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
    List<String> names(String side) => [for (final p in participants) if (p['side'] == side) p['displayName'] as String];
    return CasualMatchRecord(
      id: j['id'] as String,
      clientRef: j['clientRef'] as String?,
      categoryId: j['category'] as String? ?? 'doubles',
      sideA: names('a'),
      sideB: names('b'),
      games: [for (final (i, x) in a.indexed) (x, b[i])],
      verification: MatchVerification.fromJson(j['verification'] as Map<String, dynamic>),
      startedAt: DateTime.parse((j['startedAt'] ?? DateTime.now().toIso8601String()) as String).toLocal(),
      completedAt: j['completedAt'] == null ? null : DateTime.parse(j['completedAt'] as String).toLocal(),
      locationName: j['locationName'] as String?,
      winnerSide: j['winnerSide'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'clientRef': ?clientRef,
        'category': categoryId,
        'participants': [
          for (final n in sideA) {'side': 'a', 'displayName': n},
          for (final n in sideB) {'side': 'b', 'displayName': n},
        ],
        'sideA': {'score': [for (final g in games) g.$1]},
        'sideB': {'score': [for (final g in games) g.$2]},
        'verification': verification.toJson(),
        'startedAt': startedAt.toUtc().toIso8601String(),
        'completedAt': ?completedAt?.toUtc().toIso8601String(),
        'locationName': ?locationName,
        'winnerSide': ?winnerSide,
      };
}
