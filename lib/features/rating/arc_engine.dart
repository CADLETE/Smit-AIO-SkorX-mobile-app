import 'dart:math' as math;

/// SkorX ARC (Athlete Rating & Career): the rating engine.
///
/// Players see two numbers, kept apart on purpose:
/// - **SkorX Rating** (SPI in code): 0–100, how well the player plays right
///   now. It moves up and down and is what rank, seeding and opponent strength
///   use. Shown with a [SkorxBand].
/// - **SkorX Points (SXP)**: the Career Score. Only the points a player
///   actually scores build it: points ÷ 20 in a casual match, ÷ 10 in a
///   tournament, and a doubles side's points shared equally by its two
///   players. No opponent strength, win bonus or other hidden factor. It never
///   goes down through play. Drives the 14 [ArcLevel]s.
///
/// **Heat** (recent form against expectation) is computed but not shown.
///
/// Pure Dart with no Flutter imports, so the server can run the same maths.
/// The full specification is `docs/RATING-SYSTEM.md`.

/// Engine version stored with every score change so old numbers stay explainable.
const arcEngineVersion = 'arc-2.0';

/// SkorX Points maths. SXP is kept in exact units of 1/40 point: points ÷ 20
/// ÷ 2 (casual doubles) is the smallest step, so every contribution and every
/// career total is a whole number of units and never drifts through rounding.
/// Only display rounds, to 2 decimals.
abstract final class Sxp {
  static const casualDivisor = 20;
  static const tournamentDivisor = 10;
  static const unitsPerPoint = 40;

  /// A player's SXP units from their side's actual points: points ÷ [divisor]
  /// ÷ [players] (1 for singles, 2 for doubles and mixed).
  static int units({required int points, required int divisor, required int players}) {
    assert(players == 1 || players == 2, 'a side has one or two players');
    assert(unitsPerPoint % (divisor * players) == 0);
    return points * (unitsPerPoint ~/ (divisor * players));
  }

  /// Exact SXP for [units].
  static double of(int units) => units / unitsPerPoint;

  /// [units] in hundredths of a point, rounded half up (half away from zero).
  static int hundredths(int units) => units >= 0 ? (units * 5 + 1) ~/ 2 : -((-units * 5 + 1) ~/ 2);

  /// [units] rounded to 2 decimals, for display.
  static double shown(int units) => hundredths(units) / 100;

  /// Whole units for an SXP value (sample data, or the server's decimal).
  static int unitsOf(double sxp) => (sxp * unitsPerPoint).round();
}

/// The kind of match. For SXP it sets the conversion: casual play divides the
/// points scored by 20, tournament play (league and championship included) by
/// 10. [weight] only weights recent matches in Heat; it never touches SXP.
enum ArcMatchType {
  casual('Casual', 0.6, Sxp.casualDivisor),
  club('Club', 0.8, Sxp.casualDivisor),
  league('League', 1.0, Sxp.tournamentDivisor),
  tournament('Tournament', 1.2, Sxp.tournamentDivisor),
  championship('Championship', 1.4, Sxp.tournamentDivisor);

  const ArcMatchType(this.label, this.weight, this.divisor);
  final String label;
  final double weight;

  /// Points scored ÷ this = the side's SXP.
  final int divisor;

  bool get isTournament => divisor == Sxp.tournamentDivisor;

  /// "Casual" or "Tournament": the two conversions players see.
  String get sxpLabel => isTournament ? 'Tournament' : 'Casual';
}

/// Where a match sits in an event; later rounds weigh a little more in Heat.
enum ArcStage {
  pool('Pool', 1.0),
  quarterFinal('Quarter-final', 1.05),
  semiFinal('Semi-final', 1.10),
  finalRound('Final', 1.15);

  const ArcStage(this.label, this.weight);
  final String label;
  final double weight;
}

/// How sure SkorX is that the score is real.
enum ArcTrust {
  tournament('T1', 'Tournament verified', true, 1.0),
  organiser('T2', 'Organiser verified', true, 0.95),
  players('T3', 'Player verified', true, 0.8),
  selfReported('T4', 'Self-reported', false, 0),
  unverified('T5', 'Unverified', false, 0);

  const ArcTrust(this.code, this.label, this.countsForCareer, this.spiFactor);
  final String code;
  final String label;

  /// Whether the match adds SkorX Points. SXP is all or nothing: a verified
  /// match credits every point scored, a self-reported or unverified one none.
  final bool countsForCareer;

  /// V: share of the SPI update applied. Self-reported matches never move SPI.
  final double spiFactor;

  /// Whether the match counts for SPI, Heat and rank.
  bool get movesSkill => spiFactor > 0;
}

/// Every constant of the skill engine in one place, so they can be versioned
/// and tuned. SXP has no tuning constants beyond [Sxp]'s two divisors.
class ArcWeights {
  const ArcWeights._();

  static const lambda = 0.5;
  static const maxMatchWeight = 1.6;
  static const kMin = 0.6;
  static const kExtra = 2.4;
  static const kScale = 10.0;
  static const casualSkillFactor = 0.7;
  static const retiredSkillFactor = 0.5;
  static const provisionalMatches = 10;
  static const maxStepProvisional = 0.45;
  static const maxStepConfirmed = 0.20;
  static const newPlayerSpi = 35.0;
  static const heatMatches = 10;
  static const heatDecay = 0.85;
}

double _sigmoid(double x) => 1 / (1 + math.exp(-x));

/// Internal strength θ for an SPI.
double arcTheta(double spi) {
  final p = (spi.clamp(1, 99)) / 100;
  return math.log(p / (1 - p));
}

/// SPI for a strength θ.
double arcSpi(double theta) => 100 * _sigmoid(theta);

/// A team's strength: the weaker partner counts slightly more, because
/// opponents play at them.
double arcTeamTheta(List<double> spis) {
  final t = [for (final s in spis) arcTheta(s)];
  if (t.length == 1) return t.first;
  final lo = t.reduce(math.min), hi = t.reduce(math.max);
  return 0.55 * lo + 0.45 * hi;
}

/// SPI of a side of the net.
double arcTeamSpi(List<double> spis) => arcSpi(arcTeamTheta(spis));

/// The share of points SkorX expects a side to win against the other.
double arcExpectedShare(List<double> mine, List<double> theirs) =>
    _sigmoid(ArcWeights.lambda * (arcTeamTheta(mine) - arcTeamTheta(theirs)));

/// How fast a player's SPI learns: fast when new, steady once known.
double arcLearningRate(int matches) => ArcWeights.kMin + ArcWeights.kExtra * math.exp(-matches / ArcWeights.kScale);

/// How much a player's SPI can be trusted, 0.4–1.0, from their match count.
double arcConfidence(int matches) => 0.4 + 0.6 * (1 - math.exp(-matches / ArcWeights.kScale));

/// Everything about one player going into a match.
class ArcPlayerState {
  const ArcPlayerState({required this.spi, required this.sxpUnits, required this.matches});

  static const newPlayer = ArcPlayerState(spi: ArcWeights.newPlayerSpi, sxpUnits: 0, matches: 0);

  /// Power Index in this format.
  final double spi;

  /// Career SXP (all formats), in [Sxp] units.
  final int sxpUnits;

  /// Trust-weighted rated matches in this format over the last 12 months.
  final int matches;

  bool get provisional => matches < ArcWeights.provisionalMatches;
}

/// One match from one player's side of the net.
class ArcMatchInput {
  const ArcMatchInput({
    required this.mySide,
    required this.theirSide,
    required this.pointsFor,
    required this.pointsAgainst,
    required this.won,
    this.type = ArcMatchType.casual,
    this.stage = ArcStage.pool,
    this.trust = ArcTrust.players,
    this.otherPlayersMatches = const [],
    this.retired = false,
  });

  /// SPI of each player on my side (me first) and theirs. How many players
  /// are on [mySide] is how many share the side's SXP.
  final List<double> mySide;
  final List<double> theirSide;

  /// Actual points scored, summed over every game played. Points awarded for
  /// a walkover or retirement are never included.
  final int pointsFor;
  final int pointsAgainst;
  final bool won;
  final ArcMatchType type;
  final ArcStage stage;
  final ArcTrust trust;

  /// Match counts of the other players on court (partner and opponents), for
  /// how much to trust their SPIs.
  final List<int> otherPlayersMatches;

  /// The match ended in a retirement. Only the points played up to then count.
  final bool retired;
}

/// What one match did to one player, with every number used to get there.
class ArcImpact {
  const ArcImpact({
    required this.expectedShare,
    required this.share,
    required this.won,
    required this.opponentSpi,
    required this.pointsScored,
    required this.playersOnSide,
    required this.matchWeight,
    required this.sxpBeforeUnits,
    required this.sxpUnits,
    required this.spiBefore,
    required this.spiAfter,
    required this.learningRate,
    required this.contextConfidence,
    required this.type,
    required this.trust,
  });

  /// E: the point share SkorX expected.
  final double expectedShare;

  /// PWR: the point share actually won.
  final double share;
  final bool won;

  /// SPI of the other side of the net.
  final double opponentSpi;

  /// Actual points the player's side scored, all games.
  final int pointsScored;

  /// 1 in singles, 2 in doubles and mixed: how many share the side's SXP.
  final int playersOnSide;

  /// Type × stage, for Heat only.
  final double matchWeight;

  /// Career SXP before the match and SXP earned by it, in [Sxp] units.
  final int sxpBeforeUnits;
  final int sxpUnits;
  final double spiBefore;
  final double spiAfter;
  final double learningRate;
  final double contextConfidence;
  final ArcMatchType type;
  final ArcTrust trust;

  /// Points ÷ this = the side's SXP (20 casual, 10 tournament).
  int get divisor => type.divisor;

  /// Whether the match added to the Career Score.
  bool get credited => trust.countsForCareer;

  int get sxpAfterUnits => sxpBeforeUnits + sxpUnits;

  /// Exact SXP.
  double get sxpBefore => Sxp.of(sxpBeforeUnits);
  double get sxpGain => Sxp.of(sxpUnits);
  double get sxpAfter => Sxp.of(sxpAfterUnits);

  /// The side's SXP before it is shared: points ÷ divisor.
  double get sideSxp => pointsScored / divisor;

  /// Career before and after, rounded to 2 decimals, and the change between
  /// them. The change is worked out from the rounded totals so the three
  /// numbers players see always add up; it can differ from the rounded
  /// exact gain by 0.01.
  double get shownBefore => Sxp.shown(sxpBeforeUnits);
  double get shownAfter => Sxp.shown(sxpAfterUnits);
  double get shownGain => (Sxp.hundredths(sxpAfterUnits) - Sxp.hundredths(sxpBeforeUnits)) / 100;

  double get spiChange => spiAfter - spiBefore;

  /// Share beaten (or missed) against expectation: the heart of SPI and Heat.
  double get residual => share - expectedShare;

  /// "Strong", "As expected" or "Below".
  String get performance => residual >= 0.05
      ? 'Strong'
      : residual <= -0.05
          ? 'Below'
          : 'As expected';

  /// How the other side compared, for the Match Card.
  String get opponentLabel => opponentSpi >= 75
      ? 'Elite'
      : opponentSpi >= 60
          ? 'High'
          : opponentSpi >= 45
              ? 'Even'
              : opponentSpi >= 25
                  ? 'Moderate'
                  : 'Low';

  /// The formula in one line: "11 points ÷ 20 ÷ 2 players".
  String get formula =>
      '$pointsScored ${pointsScored == 1 ? 'point' : 'points'} ÷ $divisor${playersOnSide > 1 ? ' ÷ $playersOnSide players' : ''}';

  /// One sentence on why the score moved.
  String get why {
    final pct = (share * 100).round(), exp = (expectedShare * 100).round();
    return 'You won $pct% of the points; SkorX expected $exp%.';
  }
}

/// Rates one match for one player.
ArcImpact arcRate(ArcPlayerState me, ArcMatchInput m) {
  final total = m.pointsFor + m.pointsAgainst;
  final share = total == 0 ? 0.5 : m.pointsFor / total;
  final expected = arcExpectedShare(m.mySide, m.theirSide);
  final opponentSpi = arcTeamSpi(m.theirSide);

  // Career Engine: actual points ÷ divisor ÷ players on the side. Nothing else.
  final players = m.mySide.length;
  final units = m.trust.countsForCareer
      ? Sxp.units(points: m.pointsFor, divisor: m.type.divisor, players: players)
      : 0;

  // Skill Engine.
  final k = arcLearningRate(me.matches);
  final v = m.trust.spiFactor *
      (m.type == ArcMatchType.casual ? ArcWeights.casualSkillFactor : 1.0) *
      (m.retired ? ArcWeights.retiredSkillFactor : 1.0);
  final others = m.otherPlayersMatches;
  final c = others.isEmpty ? 1.0 : others.fold<double>(0, (s, n) => s + arcConfidence(n)) / others.length;
  final step = me.provisional ? ArcWeights.maxStepProvisional : ArcWeights.maxStepConfirmed;
  final dTheta = (k * v * c * (share - expected)).clamp(-step, step);
  final spiAfter = arcSpi(arcTheta(me.spi) + dTheta);

  return ArcImpact(
    expectedShare: expected,
    share: share,
    won: m.won,
    opponentSpi: opponentSpi,
    pointsScored: m.pointsFor,
    playersOnSide: players,
    matchWeight: math.min(ArcWeights.maxMatchWeight, m.type.weight * m.stage.weight),
    sxpBeforeUnits: me.sxpUnits,
    sxpUnits: units,
    spiBefore: me.spi,
    spiAfter: spiAfter,
    learningRate: k,
    contextConfidence: c,
    type: m.type,
    trust: m.trust,
  );
}

/// Heat: how far the player's point share beat expectation over their last
/// [ArcWeights.heatMatches] skill-rated matches, as a signed %. Null with
/// fewer than 3 such matches. [newestFirst] may hold any impacts; only those
/// that move skill count.
double? arcHeat(Iterable<ArcImpact> newestFirst) {
  final rated = newestFirst.where((i) => i.trust.movesSkill).take(ArcWeights.heatMatches).toList();
  if (rated.length < 3) return null;
  var won = 0.0, expected = 0.0;
  for (final (i, x) in rated.indexed) {
    final w = math.pow(ArcWeights.heatDecay, i) * math.min(x.matchWeight, 1.2);
    won += w * x.share;
    expected += w * x.expectedShare;
  }
  return 100 * (won / expected - 1);
}

/// "On Fire", "Hot", "Warm", "Steady", "Cool", "Ice".
String arcHeatLabel(double heat) => heat > 20
    ? 'On Fire'
    : heat > 12
        ? 'Hot'
        : heat > 5
            ? 'Warm'
            : heat >= -5
                ? 'Steady'
                : heat >= -15
                    ? 'Cool'
                    : 'Ice';

/// The skill band a SkorX Rating sits in, in the words players already use.
enum SkorxBand {
  beginner('Beginner', 0, 'Learning the game'),
  intermediate('Intermediate', 40, 'Rallies well, knows the kitchen'),
  advanced('Advanced', 55, 'Wins club and league matches'),
  pro('Pro', 70, 'Top of the tournament draws');

  const SkorxBand(this.label, this.from, this.tagline);
  final String label;

  /// Lowest SkorX Rating in the band.
  final double from;
  final String tagline;

  static SkorxBand of(double rating) => values.lastWhere((b) => rating >= b.from);

  SkorxBand? get next => index < values.length - 1 ? values[index + 1] : null;
}

/// One of the fourteen career levels, from the Career Score alone. A level
/// shows how far a SkorX career has come, not how well the player plays; that
/// is the SkorX Rating.
///
/// The steps widen as the career grows: an active weekend player reaches
/// Centurion in about a year, while 10,000 takes the most active players
/// many years. The score keeps counting past 10,000.
class ArcLevel {
  const ArcLevel(this.number, this.name, this.minSxp, this.tagline);

  final int number;
  final String name;
  final int minSxp;
  final String tagline;

  static const all = [
    ArcLevel(1, 'First Serve', 0, 'Every point you score builds your career'),
    ArcLevel(2, 'Baseliner', 10, 'On the board and playing every week'),
    ArcLevel(3, 'Kitchen Walker', 25, 'Moving up to the net'),
    ArcLevel(4, 'Dinksmith', 50, 'Points adding up at the kitchen line'),
    ArcLevel(5, 'Centurion', 100, 'Your first hundred SkorX Points'),
    ArcLevel(6, 'Point Builder', 200, 'Building a career point by point'),
    ArcLevel(7, 'Rally Forger', 350, 'Seasons of rallies behind you'),
    ArcLevel(8, 'Net Raider', 600, 'A regular name on the courts and in the draws'),
    ArcLevel(9, 'Court Marshal', 1000, 'A thousand SkorX Points'),
    ArcLevel(10, 'Clutch Caller', 1750, 'Years of tournaments and big points'),
    ArcLevel(11, 'Paddle Ronin', 3000, 'A long road, travelled match by match'),
    ArcLevel(12, 'Rally Monarch', 5000, 'One of the great careers in SkorX'),
    ArcLevel(13, 'Evergreen', 7500, 'Still here, still scoring, year after year'),
    ArcLevel(14, 'SkorX Legend', 10000, 'Ten thousand points. A legend’s career'),
  ];

  /// The level a Career Score reaches.
  static ArcLevel of(double sxp) => all.lastWhere((l) => sxp >= l.minSxp);

  ArcLevel? get next => number < all.length ? all[number] : null;

  /// 0–1 of the way from this level to the next (1 at the top).
  double progress(double sxp) {
    final n = next;
    if (n == null) return 1;
    return ((sxp - minSxp) / (n.minSxp - minSxp)).clamp(0, 1).toDouble();
  }
}
