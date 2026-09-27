import '../../sports/core/match_rules.dart';
import '../../sports/core/score_state.dart';
import '../../sports/core/scoring_engine.dart';
import '../../sports/core/sport_definition.dart';
import '../../sports/sport_registry.dart';
import 'data/match_setup.dart';
import 'handover/scoring_handover.dart';

/// One thing the official did, with the ids the API needs to accept it
/// exactly once when it syncs.
class RecordedEvent {
  const RecordedEvent({required this.id, required this.event, required this.recordedAt});

  final String id;
  final ScoringEvent event;
  final DateTime recordedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'recordedAt': recordedAt.toIso8601String(),
        ...switch (event) {
          RallyWon(:final side) => {'kind': 'rally', 'side': side.name},
          ServeCorrected(:final serve) => {'kind': 'serve', 'side': serve.side.name, 'serverNumber': serve.serverNumber},
        },
      };

  factory RecordedEvent.fromJson(Map<String, dynamic> json) {
    final side = Side.values.byName(json['side'] as String);
    return RecordedEvent(
      id: json['id'] as String,
      recordedAt: DateTime.parse(json['recordedAt'] as String),
      event: json['kind'] == 'serve' ? ServeCorrected(ServeState(side, json['serverNumber'] as int?)) : RallyWon(side),
    );
  }
}

/// How a match ended without being played out.
enum EarlyEnd {
  /// The other side never turned up.
  walkover('Walkover'),

  /// The other side stopped mid-match (injury, withdrawal).
  retired('Retired');

  const EarlyEnd(this.label);
  final String label;
}

/// The result of a match decided off the scoreboard.
class MatchOutcome {
  const MatchOutcome(this.kind, this.winner);

  final EarlyEnd kind;
  final Side winner;

  Map<String, dynamic> toJson() => {'kind': kind.name, 'winner': winner.name};

  factory MatchOutcome.fromJson(Map<String, dynamic> json) =>
      MatchOutcome(EarlyEnd.values.byName(json['kind'] as String), Side.values.byName(json['winner'] as String));
}

/// A correction the scorer made to who stands where, without a rally.
enum CourtFix {
  /// The teams are at the other ends.
  swapEnds('Ends swapped'),

  /// The serving team's players are the other way round: the partner is
  /// actually serving from this court.
  swapServingPlayers('Serving players switched'),

  /// The receiving team's players are the other way round.
  swapReceivingPlayers('Receiving players switched');

  const CourtFix(this.label);
  final String label;
}

/// A [CourtFix] made after [afterEvents] recorded actions. Undo takes it back
/// like a rally.
class CourtAdjustment {
  const CourtAdjustment(this.fix, this.afterEvents);

  final CourtFix fix;
  final int afterEvents;

  Map<String, dynamic> toJson() => {'fix': fix.name, 'after': afterEvents};

  factory CourtAdjustment.fromJson(Map<String, dynamic> json) =>
      CourtAdjustment(CourtFix.values.byName(json['fix'] as String), json['after'] as int);
}

/// Who held the phone: [name] scored from [fromEvent] recorded actions on.
class ScorerShift {
  const ScorerShift({required this.name, required this.fromEvent, required this.at, this.playerId});

  final String name;
  final String? playerId;
  final int fromEvent;
  final DateTime at;

  Map<String, dynamic> toJson() =>
      {'name': name, if (playerId != null) 'playerId': playerId, 'fromEvent': fromEvent, 'at': at.toIso8601String()};

  factory ScorerShift.fromJson(Map<String, dynamic> json) => ScorerShift(
        name: json['name'] as String,
        playerId: json['playerId'] as String?,
        fromEvent: json['fromEvent'] as int,
        at: DateTime.parse(json['at'] as String),
      );
}

/// A casual match being scored on this phone. The score is never stored: it
/// is always replayed from [events] through the sport's engine.
class LocalMatch {
  const LocalMatch({
    required this.id,
    required this.sportId,
    required this.categoryId,
    required this.sideA,
    required this.sideB,
    required this.rules,
    required this.firstServer,
    required this.startedAt,
    this.events = const [],
    this.finishedAt,
    this.locationName,
    this.details = const MatchDetails(),
    this.outcome,
    this.pausedAt,
    this.pauseReason,
    this.endChanges = const {},
    this.code,
    this.scorers = const [],
    this.adjustments = const [],
    this.handover,
  });

  final String id;
  final String sportId;
  final String categoryId;

  /// Player names per side, in court order at the first serve: the player
  /// in the right-hand service court first.
  final List<String> sideA;
  final List<String> sideB;
  final MatchRules rules;
  final Side firstServer;
  final DateTime startedAt;
  final List<RecordedEvent> events;
  final DateTime? finishedAt;
  final String? locationName;
  final MatchDetails details;

  /// Set when the match was decided by walkover or retirement.
  final MatchOutcome? outcome;

  /// Set while play is stopped (injury, water break...). Scoring is locked.
  final DateTime? pausedAt;
  final String? pauseReason;

  bool get isPaused => pausedAt != null;

  /// For each finished game (by number), whether the players changed ends
  /// before the next one, as the scorer confirmed at the game break.
  final Map<int, bool> endChanges;

  /// The public match ID (see `MatchCode`), e.g. "SKX-PCMD-260927-7K3QX".
  /// Null only for matches started before IDs existed.
  final String? code;

  /// Everyone who scored this match, in order. The first is who started it.
  final List<ScorerShift> scorers;

  /// Court corrections, in the order they were made.
  final List<CourtAdjustment> adjustments;

  /// An unanswered request for someone to score on their phone. Scoring is
  /// paused here until it is answered.
  final ScoringHandover? handover;

  bool get awaitingHandover => handover != null;

  /// The ID to show: [code], or a stand-in from the internal id.
  String get displayCode => code ?? 'SKX-${id.substring(0, 8).toUpperCase()}';

  /// A game has just finished and the scorer has not yet said whether the
  /// players changed ends. Scoring waits for the answer.
  bool get awaitingEndChange {
    if (isOver) return false;
    final game = score.gameNumber;
    return game > 1 && !endChanges.containsKey(game - 1);
  }

  SportDefinition get sport => SportRegistry.standard.of(sportId)!;

  MatchSetup get setup => MatchSetup(rules: rules, playersPerSide: sideA.length, firstServer: firstServer);

  ScoreState get score => sport.engine.replay(setup, events.map((e) => e.event));

  /// The winner, on the scoreboard or by walkover or retirement.
  Side? get winner => outcome?.winner ?? score.winner;

  bool get isOver => outcome != null || score.isOver;

  List<String> names(Side side) => side == Side.a ? sideA : sideB;

  String label(Side side) => names(side).join(' / ');

  /// The team name if one was given, otherwise the players' names.
  String teamLabel(Side side) => (side == Side.a ? details.teamA : details.teamB) ?? label(side);

  /// [reopen] clears [finishedAt], for undoing the match-winning point.
  /// [resume] clears the pause.
  LocalMatch copyWith({
    List<RecordedEvent>? events,
    DateTime? finishedAt,
    bool reopen = false,
    MatchRules? rules,
    MatchOutcome? outcome,
    DateTime? pausedAt,
    String? pauseReason,
    bool resume = false,
    Map<int, bool>? endChanges,
    List<ScorerShift>? scorers,
    List<CourtAdjustment>? adjustments,
    ScoringHandover? handover,
    bool clearHandover = false,
  }) =>
      LocalMatch(
        id: id,
        sportId: sportId,
        categoryId: categoryId,
        sideA: sideA,
        sideB: sideB,
        rules: rules ?? this.rules,
        firstServer: firstServer,
        startedAt: startedAt,
        events: events ?? this.events,
        finishedAt: reopen ? null : finishedAt ?? this.finishedAt,
        locationName: locationName,
        details: details,
        outcome: reopen ? null : outcome ?? this.outcome,
        pausedAt: resume ? null : pausedAt ?? this.pausedAt,
        pauseReason: resume ? null : pauseReason ?? this.pauseReason,
        endChanges: endChanges ?? this.endChanges,
        code: code,
        scorers: scorers ?? this.scorers,
        adjustments: adjustments ?? this.adjustments,
        handover: clearHandover ? null : handover ?? this.handover,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'sportId': sportId,
        'categoryId': categoryId,
        'sideA': sideA,
        'sideB': sideB,
        'rules': rules.toJson(),
        'firstServer': firstServer.name,
        'startedAt': startedAt.toIso8601String(),
        'finishedAt': finishedAt?.toIso8601String(),
        'locationName': locationName,
        'details': details.toJson(),
        if (outcome != null) 'outcome': outcome!.toJson(),
        if (pausedAt != null) 'pausedAt': pausedAt!.toIso8601String(),
        if (pauseReason != null) 'pauseReason': pauseReason,
        if (code != null) 'code': code,
        if (handover != null) 'handover': handover!.toJson(),
        if (scorers.isNotEmpty) 'scorers': scorers.map((s) => s.toJson()).toList(),
        if (adjustments.isNotEmpty) 'adjustments': adjustments.map((a) => a.toJson()).toList(),
        if (endChanges.isNotEmpty) 'endChanges': {for (final e in endChanges.entries) '${e.key}': e.value},
        'events': events.map((e) => e.toJson()).toList(),
      };

  factory LocalMatch.fromJson(Map<String, dynamic> json) => LocalMatch(
        id: json['id'] as String,
        sportId: json['sportId'] as String,
        categoryId: json['categoryId'] as String,
        sideA: (json['sideA'] as List<dynamic>).cast<String>(),
        sideB: (json['sideB'] as List<dynamic>).cast<String>(),
        rules: MatchRules.parse(json['rules']).rules!,
        firstServer: Side.values.byName(json['firstServer'] as String),
        startedAt: DateTime.parse(json['startedAt'] as String),
        finishedAt: json['finishedAt'] == null ? null : DateTime.parse(json['finishedAt'] as String),
        locationName: json['locationName'] as String?,
        details: json['details'] == null
            ? const MatchDetails()
            : MatchDetails.fromJson(json['details'] as Map<String, dynamic>),
        outcome: json['outcome'] == null ? null : MatchOutcome.fromJson(json['outcome'] as Map<String, dynamic>),
        pausedAt: json['pausedAt'] == null ? null : DateTime.parse(json['pausedAt'] as String),
        pauseReason: json['pauseReason'] as String?,
        code: json['code'] as String?,
        handover: json['handover'] == null ? null : ScoringHandover.fromJson(json['handover'] as Map<String, dynamic>),
        scorers: ((json['scorers'] as List<dynamic>?) ?? const []).cast<Map<String, dynamic>>().map(ScorerShift.fromJson).toList(),
        adjustments:
            ((json['adjustments'] as List<dynamic>?) ?? const []).cast<Map<String, dynamic>>().map(CourtAdjustment.fromJson).toList(),
        endChanges: {
          for (final e in ((json['endChanges'] as Map<String, dynamic>?) ?? const {}).entries) int.parse(e.key): e.value as bool,
        },
        events: (json['events'] as List<dynamic>).cast<Map<String, dynamic>>().map(RecordedEvent.fromJson).toList(),
      );
}
