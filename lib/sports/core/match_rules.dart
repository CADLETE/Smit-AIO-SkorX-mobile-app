/// How points are won in a game.
enum ScoringSystem {
  /// Every rally scores a point.
  rally('rally'),

  /// Only the serving side scores; losing a rally on serve passes the serve.
  sideOut('side_out');

  const ScoringSystem(this.wire);

  /// The value used by the API (`MatchRules.scoring`).
  final String wire;

  static ScoringSystem? fromWire(Object? value) {
    for (final system in values) {
      if (system.wire == value) return system;
    }
    return null;
  }
}

/// Match lengths players can pick: one game or best of 3. Older matches
/// stored as best of 5 or 7 still parse so history keeps loading.
const playableBestOf = [1, 3];

/// Rules for point-based racket sports: best of [bestOf] games, each game
/// first to [pointsToWin], optionally win by two, optionally capped.
///
/// Mirrors `MatchRules` in backend/src/matches/rules/match-rules.ts, including
/// the JSON keys, so the same rules object travels between app, API and TMS.
class MatchRules {
  const MatchRules({
    required this.pointsToWin,
    required this.winByTwo,
    required this.bestOf,
    this.pointCap,
    this.scoring = ScoringSystem.rally,
  });

  final int pointsToWin;
  final bool winByTwo;
  final int bestOf;

  /// A game ends when a side reaches this score even without a 2-point lead.
  final int? pointCap;
  final ScoringSystem scoring;

  int get gamesToWin => (bestOf / 2).ceil();

  Map<String, Object?> toJson() => {
        'pointsToWin': pointsToWin,
        'winByTwo': winByTwo,
        'bestOf': bestOf,
        if (pointCap != null) 'pointCap': pointCap,
        'scoring': scoring.wire,
      };

  MatchRules copyWith({int? pointsToWin, bool? winByTwo, int? bestOf, ScoringSystem? scoring}) => MatchRules(
        pointsToWin: pointsToWin ?? this.pointsToWin,
        winByTwo: winByTwo ?? this.winByTwo,
        bestOf: bestOf ?? this.bestOf,
        pointCap: pointCap,
        scoring: scoring ?? this.scoring,
      );

  @override
  bool operator ==(Object other) =>
      other is MatchRules &&
      other.pointsToWin == pointsToWin &&
      other.winByTwo == winByTwo &&
      other.bestOf == bestOf &&
      other.pointCap == pointCap &&
      other.scoring == scoring;

  @override
  int get hashCode => Object.hash(pointsToWin, winByTwo, bestOf, pointCap, scoring);

  /// Plain-language summary, e.g. "Best of 3 · first to 11, win by 2".
  String describe() {
    final games = bestOf == 1 ? '1 game' : 'Best of $bestOf';
    final winBy = winByTwo ? 'win by 2' : 'win by 1';
    final cap = pointCap != null ? ', max $pointCap' : '';
    return '$games · first to $pointsToWin, $winBy$cap';
  }

  /// Parses rules from the API. Rejects anything malformed rather than
  /// coercing it, with the same messages as the server's `parseMatchRules`.
  static RulesParseResult parse(Object? input) {
    if (input is! Map) return const RulesParseResult.invalid('Match rules are missing.');
    final pointsToWin = input['pointsToWin'];
    final winByTwo = input['winByTwo'];
    final bestOf = input['bestOf'];
    final pointCap = input['pointCap'];
    final scoring = input['scoring'];

    if (pointsToWin is! int || pointsToWin < 1 || pointsToWin > 99) {
      return const RulesParseResult.invalid('Points to win must be a whole number from 1 to 99.');
    }
    if (winByTwo is! bool) return const RulesParseResult.invalid('Win by two must be true or false.');
    if (bestOf is! int || bestOf < 1 || bestOf > 7 || bestOf.isEven) {
      return const RulesParseResult.invalid('Best of must be 1, 3, 5 or 7 games.');
    }
    if (pointCap != null && (pointCap is! int || pointCap <= pointsToWin)) {
      return const RulesParseResult.invalid('The point cap must be higher than points to win.');
    }
    final system = scoring == null ? ScoringSystem.rally : ScoringSystem.fromWire(scoring);
    if (system == null) return const RulesParseResult.invalid('Scoring must be rally or side out.');

    return RulesParseResult.valid(MatchRules(
      pointsToWin: pointsToWin,
      winByTwo: winByTwo,
      bestOf: bestOf,
      pointCap: pointCap as int?,
      scoring: system,
    ));
  }
}

class RulesParseResult {
  const RulesParseResult.valid(MatchRules this.rules) : reason = null;
  const RulesParseResult.invalid(String this.reason) : rules = null;

  final MatchRules? rules;
  final String? reason;
}
