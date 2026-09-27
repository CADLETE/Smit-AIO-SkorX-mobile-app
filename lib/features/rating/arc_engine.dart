import 'dart:math' as math;

/// SkorX ARC (Athlete Rating & Career): the rating engine.
///
/// Every player carries three numbers per format:
/// - **SkorX Points (SXP)**: the career total. Every counted match adds to it;
///   it never goes down through play.
/// - **Power Index (SPI)**: 0–100, how well the player plays right now. It
///   moves up and down and is what rank and opponent strength use.
/// - **Heat**: recent form, the % by which the player's point share beat what
///   SkorX expected over the last 10 matches.
///
/// Pure Dart with no Flutter imports, so the server can run the same maths.
/// The full specification is `docs/RATING-SYSTEM.md`.

/// Engine version stored with every score change so old numbers stay explainable.
const arcEngineVersion = 'arc-1.0';

/// How much a kind of match counts towards SXP. Never affects SPI.
enum ArcMatchType {
  casual('Casual', 0.6),
  club('Club', 0.8),
  league('League', 1.0),
  tournament('Tournament', 1.2),
  championship('Championship', 1.4);

  const ArcMatchType(this.label, this.weight);
  final String label;
  final double weight;
}

/// Where a match sits in an event; later rounds count a little more.
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
  tournament('T1', 'Tournament verified', 1.0, 1.0),
  organiser('T2', 'Organiser verified', 0.95, 0.95),
  players('T3', 'Player verified', 0.8, 0.8),
  selfReported('T4', 'Self-reported', 0.6, 0),
  unverified('T5', 'Unverified', 0, 0);

  const ArcTrust(this.code, this.label, this.sxpFactor, this.spiFactor);
  final String code;
  final String label;

  /// TF: share of SXP credited.
  final double sxpFactor;

  /// V: share of the SPI update applied. Self-reported matches never move SPI.
  final double spiFactor;

  /// Whether the match counts for SPI, Heat and rank.
  bool get movesSkill => spiFactor > 0;
}

/// Every constant of the engine in one place, so they can be versioned and tuned.
class ArcWeights {
  const ArcWeights._();

  static const lambda = 0.5;
  static const playCredit = 2.0;
  static const pointsCredit = 10.0;
  static const winBase = 4.0;
  static const winMargin = 4.0;
  static const challenge = 25.0;
  static const matchCap = 60.0;
  static const maxMatchWeight = 1.6;
  static const repeatDecay = 0.7;
  static const repeatFloor = 0.15;
  static const fullMatchesPerDay = 6;
  static const tiredFactor = 0.5;
  static const capBase = 200.0;
  static const capPerSpi = 10.0;
  static const gravityHalving = 100.0;
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

/// The career level a player's skill supports; gains slow down above it.
double arcCareerCap(double spi) => ArcWeights.capBase + ArcWeights.capPerSpi * spi;

/// Everything about one player going into a match.
class ArcPlayerState {
  const ArcPlayerState({required this.spi, required this.sxp, required this.matches, double? overallSpi})
      : overallSpi = overallSpi ?? spi;

  static const newPlayer = ArcPlayerState(spi: ArcWeights.newPlayerSpi, sxp: 0, matches: 0);

  /// Power Index in this format.
  final double spi;

  /// Career SXP (all formats), which Gravity compares with [overallSpi].
  final double sxp;

  /// Trust-weighted rated matches in this format over the last 12 months.
  final int matches;
  final double overallSpi;

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
    this.previousMeetings = 0,
    this.matchesEarlierToday = 0,
    this.retired = false,
  });

  /// SPI of each player on my side (me first) and theirs.
  final List<double> mySide;
  final List<double> theirSide;

  /// Summed over every game.
  final int pointsFor;
  final int pointsAgainst;
  final bool won;
  final ArcMatchType type;
  final ArcStage stage;
  final ArcTrust trust;

  /// Match counts of the other players on court (partner and opponents), for
  /// how much to trust their SPIs.
  final List<int> otherPlayersMatches;

  /// Counted matches against this same line-up in the last 30 days.
  final int previousMeetings;

  /// Counted matches the player already played today.
  final int matchesEarlierToday;

  /// The match ended in a retirement (scores completed for the other side).
  final bool retired;
}

/// A line of the "why did my score change" breakdown.
class ArcLine {
  const ArcLine(this.label, this.value);

  final String label;
  final double value;
}

/// What one match did to one player, with every number used to get there.
class ArcImpact {
  const ArcImpact({
    required this.expectedShare,
    required this.share,
    required this.won,
    required this.opponentSpi,
    required this.play,
    required this.points,
    required this.win,
    required this.challenge,
    required this.opponentFactor,
    required this.matchWeight,
    required this.trustFactor,
    required this.repeatFactor,
    required this.fatigueFactor,
    required this.gravity,
    required this.sxpBefore,
    required this.sxpGain,
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

  // The four credits, before multipliers.
  final double play;
  final double points;
  final double win;
  final double challenge;

  // The multipliers.
  final double opponentFactor;
  final double matchWeight;
  final double trustFactor;
  final double repeatFactor;
  final double fatigueFactor;
  final double gravity;

  final double sxpBefore;

  /// SXP earned: never negative.
  final double sxpGain;
  final double spiBefore;
  final double spiAfter;
  final double learningRate;
  final double contextConfidence;
  final ArcMatchType type;
  final ArcTrust trust;

  double get raw => play + points + win + challenge;
  double get sxpAfter => sxpBefore + sxpGain;
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

  /// The breakdown shown to players. Lines sum to [sxpGain] (before display
  /// rounding; see [displayLines]).
  List<ArcLine> get lines {
    final f = trustFactor * repeatFactor * fatigueFactor * gravity;
    final base = raw * f;
    final uncapped = base * opponentFactor * matchWeight;
    return [
      ArcLine('Played', play * f),
      ArcLine('Point performance', points * f),
      if (win > 0) ArcLine('Win bonus', win * f),
      if (challenge > 0) ArcLine('Beat expectation', challenge * f),
      ArcLine('Opponent strength', base * (opponentFactor - 1)),
      ArcLine(type.weight < 1 ? '${type.label} match' : 'Match importance', base * opponentFactor * (matchWeight - 1)),
      if (uncapped > sxpGain) ArcLine('Match cap', sxpGain - uncapped),
    ];
  }

  /// [lines] rounded to 0.1, tiny ones dropped, and the rounding remainder
  /// added to the largest line so the lines add up to the rounded headline.
  List<ArcLine> get displayLines {
    final shown = [for (final l in lines) if (l.value.abs() >= 0.05) ArcLine(l.label, (l.value * 10).round() / 10)];
    if (shown.isEmpty) return shown;
    final target = (sxpGain * 10).round() / 10;
    final sum = shown.fold<double>(0, (s, l) => s + l.value);
    final diff = ((target - sum) * 10).round() / 10;
    if (diff == 0) return shown;
    var big = 0;
    for (var i = 1; i < shown.length; i++) {
      if (shown[i].value > shown[big].value) big = i;
    }
    shown[big] = ArcLine(shown[big].label, ((shown[big].value + diff) * 10).round() / 10);
    return shown;
  }

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
  final dominance = total == 0 ? 0.0 : (m.pointsFor - m.pointsAgainst) / total;
  final expected = arcExpectedShare(m.mySide, m.theirSide);
  final opponentSpi = arcTeamSpi(m.theirSide);

  // Career Engine.
  const play = ArcWeights.playCredit;
  final points = ArcWeights.pointsCredit * share;
  final win = m.won ? ArcWeights.winBase + ArcWeights.winMargin * dominance : 0.0;
  final challenge = ArcWeights.challenge * math.max(0, share - expected);
  final od = 0.4 + 1.2 * opponentSpi / 100;
  final mw = math.min(ArcWeights.maxMatchWeight, m.type.weight * m.stage.weight);
  final tf = m.trust.sxpFactor;
  final rf = math.max(ArcWeights.repeatFloor, math.pow(ArcWeights.repeatDecay, m.previousMeetings).toDouble());
  final df = m.matchesEarlierToday >= ArcWeights.fullMatchesPerDay ? ArcWeights.tiredFactor : 1.0;
  final cap = arcCareerCap(me.overallSpi);
  final g = me.sxp <= cap ? 1.0 : math.pow(0.5, (me.sxp - cap) / ArcWeights.gravityHalving).toDouble();
  final gain = math.min(ArcWeights.matchCap, (play + points + win + challenge) * od * mw * tf * rf * df * g);

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
    play: play,
    points: points,
    win: win,
    challenge: challenge,
    opponentFactor: od,
    matchWeight: mw,
    trustFactor: tf,
    repeatFactor: rf,
    fatigueFactor: df,
    gravity: g,
    sxpBefore: me.sxp,
    sxpGain: gain,
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

/// One of the twelve career levels, from SXP.
class ArcLevel {
  const ArcLevel(this.number, this.name, this.minSxp, this.tagline,
      {this.verifiedMatches = 0, this.tournamentMatches = 0, this.needsConfirmed = false});

  final int number;
  final String name;
  final int minSxp;
  final String tagline;

  /// Gates besides SXP.
  final int verifiedMatches;
  final int tournamentMatches;
  final bool needsConfirmed;

  static const all = [
    ArcLevel(1, 'First Serve', 0, 'Learning the game and the score'),
    ArcLevel(2, 'Return Ready', 100, 'Plays every week and keeps the ball in'),
    ArcLevel(3, 'Dink Crafter', 200, 'Comfortable at the kitchen line', verifiedMatches: 10),
    ArcLevel(4, 'Kitchen Regular', 300, 'A regular in leagues and ladders', needsConfirmed: true),
    ArcLevel(5, 'Third-Shot Artist', 400, 'Builds points instead of just hitting', verifiedMatches: 20),
    ArcLevel(6, 'Transition Hunter', 500, 'Wins the battle through mid-court', verifiedMatches: 25),
    ArcLevel(7, 'Net Commander', 600, 'Controls the net against club peers', verifiedMatches: 30, tournamentMatches: 3),
    ArcLevel(8, 'Firefight Specialist', 700, 'Wins the fast hands battles', verifiedMatches: 40, tournamentMatches: 6),
    ArcLevel(9, 'Erne Striker', 800, 'Takes risks that pay off', verifiedMatches: 50, tournamentMatches: 10),
    ArcLevel(10, 'ATP Maestro', 900, 'A regular at regional tournaments', verifiedMatches: 60, tournamentMatches: 15),
    ArcLevel(11, 'Kitchen Sovereign', 1000, 'Top of the city and state tables',
        verifiedMatches: 80, tournamentMatches: 20),
    ArcLevel(12, 'SkorX Legend', 1200, 'A long elite career', verifiedMatches: 100, tournamentMatches: 30),
  ];

  /// The level SXP reaches, ignoring gates.
  static ArcLevel of(double sxp) => all.lastWhere((l) => sxp >= l.minSxp);

  /// The highest level SXP and the gates both allow.
  static ArcLevel reached(double sxp, {required int verified, required int tournament, required bool confirmed}) =>
      all.lastWhere((l) =>
          sxp >= l.minSxp &&
          verified >= l.verifiedMatches &&
          tournament >= l.tournamentMatches &&
          (!l.needsConfirmed || confirmed));

  ArcLevel? get next => number < all.length ? all[number] : null;

  /// 0–1 of the way from this level to the next (1 at the top).
  double progress(double sxp) {
    final n = next;
    if (n == null) return 1;
    return ((sxp - minSxp) / (n.minSxp - minSxp)).clamp(0, 1).toDouble();
  }
}
