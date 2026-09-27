import '../matches/data/match.dart';
import '../player/data/player_repository.dart' show PlayCategory;
import 'arc_engine.dart';

/// The ARC match type a SkorX match counts as.
ArcMatchType arcTypeOf(Match m) => switch (m.kind) {
      MatchKind.tournament => ArcMatchType.tournament,
      MatchKind.league => ArcMatchType.league,
      MatchKind.friendly => ArcMatchType.casual,
    };

/// The ARC stage from a tournament round name (weighs Heat only) ("Quarter-final", "Pool A · Match 2").
ArcStage arcStageOf(Match m) {
  final round = m.tournament?.round.toLowerCase() ?? '';
  if (round.startsWith('quarter')) return ArcStage.quarterFinal;
  if (round.startsWith('semi')) return ArcStage.semiFinal;
  if (round.startsWith('final') || round.startsWith('bronze')) return ArcStage.finalRound;
  return ArcStage.pool;
}

/// How SkorX trusts a match's score by where it was scored. Until verification
/// is stored with the match: tournaments are scored live by the organiser's
/// scorer (T1), leagues are entered by the organiser (T2), and friendlies are
/// live-scored in the app by a player (T3).
ArcTrust arcTrustOf(Match m) => switch (m.kind) {
      MatchKind.tournament => ArcTrust.tournament,
      MatchKind.league => ArcTrust.organiser,
      MatchKind.friendly => ArcTrust.players,
    };

/// A player's ARC numbers in one format.
class ArcFormatState {
  const ArcFormatState({required this.spi, required this.sxpUnits, required this.matches});

  final double spi;

  /// SXP earned in this format, in [Sxp] units.
  final int sxpUnits;
  final int matches;

  double get sxp => Sxp.of(sxpUnits);

  bool get provisional => matches < ArcWeights.provisionalMatches;
}

/// Replays one player's finished matches, oldest first, through the engine,
/// keeping SPI per format and one career SXP. Opponents' SPIs come from
/// [spiOf]; their match counts from [matchesOf]. [startSxpUnits] is a career
/// already earned before the first replayed match.
class ArcCareer {
  ArcCareer({
    required this.spiOf,
    this.matchesOf,
    double startSpi = ArcWeights.newPlayerSpi,
    int startSxpUnits = 0,
    this.me = 'You',
  })  : _startSpi = startSpi,
        _units = startSxpUnits;

  final double Function(String name) spiOf;
  final int Function(String name)? matchesOf;
  final String me;
  final double _startSpi;

  final Map<PlayCategory, ArcFormatState> _formats = {};
  final List<(Match, ArcImpact)> _history = [];
  int _units;

  /// Career SXP in [Sxp] units, and exact.
  int get sxpUnits => _units;
  double get sxp => Sxp.of(_units);

  ArcFormatState format(PlayCategory c) => _formats[c] ?? ArcFormatState(spi: _startSpi, sxpUnits: 0, matches: 0);

  /// Every rated match so far, oldest first.
  List<(Match, ArcImpact)> get history => List.unmodifiable(_history);

  /// Rates [m] (seen from [me]'s side, [me] first in `mine`) and records it.
  ArcImpact add(Match m) {
    final f = format(m.format);
    final partners = m.mine.where((n) => n != me).toList();
    final impact = arcRate(
      ArcPlayerState(spi: f.spi, sxpUnits: _units, matches: f.matches),
      ArcMatchInput(
        mySide: [f.spi, for (final p in partners) spiOf(p)],
        theirSide: [for (final p in m.theirs) spiOf(p)],
        pointsFor: m.pointsWon,
        pointsAgainst: m.pointsLost,
        won: m.won,
        type: arcTypeOf(m),
        stage: arcStageOf(m),
        trust: arcTrustOf(m),
        otherPlayersMatches: [for (final p in [...partners, ...m.theirs]) matchesOf?.call(p) ?? 40],
      ),
    );
    _units = impact.sxpAfterUnits;
    _formats[m.format] = ArcFormatState(
      spi: impact.spiAfter,
      sxpUnits: f.sxpUnits + impact.sxpUnits,
      matches: f.matches + (impact.trust.movesSkill ? 1 : 0),
    );
    _history.add((m, impact));
    return impact;
  }

  /// SPI across formats, weighted by matches played in each.
  double get overallSpi {
    final played = _formats.values.where((f) => f.matches > 0).toList();
    if (played.isEmpty) return _startSpi;
    final n = played.fold<int>(0, (s, f) => s + f.matches);
    return played.fold<double>(0, (s, f) => s + f.spi * f.matches) / n;
  }
}

/// A player's SkorX Rating and SkorX Points after one rated match.
class ArcPoint {
  const ArcPoint(this.date, this.rating, this.pointsUnits);

  final DateTime date;

  /// SkorX Rating (overall SPI) after the match.
  final double rating;

  /// Career SkorX Points after the match, in [Sxp] units.
  final int pointsUnits;

  double get points => Sxp.of(pointsUnits);
}

/// A player's ARC profile, worked out from their rated matches alone, so the
/// header, graph and every match's change always agree.
class ArcSummary {
  const ArcSummary({
    required this.sxpUnits,
    required this.spi,
    required this.formats,
    required this.heat,
    required this.level,
    required this.verifiedMatches,
    required this.tournamentMatches,
    required this.confirmed,
    required this.timeline,
  });

  /// Career SXP, all formats, in [Sxp] units.
  final int sxpUnits;

  /// SkorX Rating across formats: SPI weighted by matches in each.
  final double spi;
  final Map<PlayCategory, ArcFormatState> formats;

  /// Signed %, or null before 3 rated matches. Not shown to players.
  final double? heat;

  /// The career level the Career Score has reached.
  final ArcLevel level;
  final int verifiedMatches;
  final int tournamentMatches;

  /// Whether the rating has settled ([ArcWeights.provisionalMatches] verified
  /// matches). Before that it moves faster while SkorX learns the player.
  final bool confirmed;

  /// Rating and points after every rated match, oldest first, starting with
  /// where the player stood the day before the first one.
  final List<ArcPoint> timeline;

  /// Career SXP, exact.
  double get sxp => Sxp.of(sxpUnits);

  /// Career SXP as shown: 2 decimals.
  double get points => Sxp.shown(sxpUnits);

  /// SkorX Rating, the headline skill number.
  double get rating => spi;
  SkorxBand get band => SkorxBand.of(spi);

  ArcPoint _before(DateTime now, int days) =>
      timeline.lastWhere((p) => p.date.isBefore(now.subtract(Duration(days: days))), orElse: () => timeline.first);

  /// How far the rating moved over the last [days].
  double ratingChange(DateTime now, {int days = 30}) => spi - _before(now, days).rating;

  /// SkorX Points earned over the last [days], as shown (2 decimals, and the
  /// difference of the two shown totals).
  double pointsEarned(DateTime now, {int days = 30}) =>
      (Sxp.hundredths(sxpUnits) - Sxp.hundredths(_before(now, days).pointsUnits)) / 100;

  /// Builds the summary from [mine]: the player's matches, each carrying its
  /// [Match.arc] impact. Formats' SPI come from each format's latest match.
  static ArcSummary? fromMatches(Iterable<Match> mine) {
    final rated = [
      for (final m in mine)
        if (m.isCompleted && m.involvesMe && m.arc != null) m,
    ]..sort((a, b) => a.playedAt.compareTo(b.playedAt));
    if (rated.isEmpty) return null;
    final formats = <PlayCategory, ArcFormatState>{};
    double overall() {
      final played = formats.values.where((f) => f.matches > 0).toList();
      final n = played.fold<int>(0, (s, f) => s + f.matches);
      return n == 0 ? ArcWeights.newPlayerSpi : played.fold<double>(0, (s, f) => s + f.spi * f.matches) / n;
    }

    final first = rated.first.arc!;
    final timeline = [ArcPoint(rated.first.playedAt.subtract(const Duration(days: 1)), first.spiBefore, first.sxpBeforeUnits)];
    var units = first.sxpBeforeUnits;
    for (final m in rated) {
      final a = m.arc!;
      final f = formats[m.format];
      formats[m.format] = ArcFormatState(
        spi: a.spiAfter,
        sxpUnits: (f?.sxpUnits ?? 0) + a.sxpUnits,
        matches: (f?.matches ?? 0) + (a.trust.movesSkill ? 1 : 0),
      );
      units = a.sxpAfterUnits;
      timeline.add(ArcPoint(m.playedAt, overall(), units));
    }
    final spi = overall();
    final verified = rated.where((m) => m.arc!.trust.movesSkill).length;
    final tournament = rated.where((m) => m.arc!.type.isTournament).length;
    return ArcSummary(
      sxpUnits: units,
      spi: spi,
      formats: formats,
      heat: arcHeat([for (final m in rated.reversed) m.arc!]),
      level: ArcLevel.of(Sxp.of(units)),
      verifiedMatches: verified,
      tournamentMatches: tournament,
      confirmed: verified >= ArcWeights.provisionalMatches,
      timeline: timeline,
    );
  }
}
