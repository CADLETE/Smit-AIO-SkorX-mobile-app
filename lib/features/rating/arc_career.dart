import '../matches/data/match.dart';
import '../player/data/player_repository.dart' show PlayCategory;
import 'arc_engine.dart';

/// The ARC match type a SkorX match counts as.
ArcMatchType arcTypeOf(Match m) => switch (m.kind) {
      MatchKind.tournament => ArcMatchType.tournament,
      MatchKind.league => ArcMatchType.league,
      MatchKind.friendly => ArcMatchType.casual,
    };

/// The ARC stage from a tournament round name ("Quarter-final", "Pool A · Match 2").
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
  const ArcFormatState({required this.spi, required this.sxp, required this.matches});

  final double spi;
  final double sxp;
  final int matches;

  bool get provisional => matches < ArcWeights.provisionalMatches;
}

/// Replays one player's finished matches, oldest first, through the engine,
/// keeping SPI per format and one career SXP. Opponents' SPIs come from
/// [spiOf]; their match counts from [matchesOf].
class ArcCareer {
  ArcCareer({
    required this.spiOf,
    this.matchesOf,
    double startSpi = ArcWeights.newPlayerSpi,
    this.me = 'You',
  }) : _startSpi = startSpi;

  final double Function(String name) spiOf;
  final int Function(String name)? matchesOf;
  final String me;
  final double _startSpi;

  final Map<PlayCategory, ArcFormatState> _formats = {};
  final List<(Match, ArcImpact)> _history = [];
  double _sxp = 0;

  double get sxp => _sxp;

  ArcFormatState format(PlayCategory c) => _formats[c] ?? ArcFormatState(spi: _startSpi, sxp: 0, matches: 0);

  /// Every rated match so far, oldest first.
  List<(Match, ArcImpact)> get history => List.unmodifiable(_history);

  /// Rates [m] (seen from [me]'s side, [me] first in `mine`) and records it.
  ArcImpact add(Match m) {
    final f = format(m.format);
    final partners = m.mine.where((n) => n != me).toList();
    final day = DateTime(m.playedAt.year, m.playedAt.month, m.playedAt.day);
    final lineup = {...m.mine, ...m.theirs};
    final earlierToday = _history.where((h) {
      final p = h.$1.playedAt;
      return DateTime(p.year, p.month, p.day) == day;
    }).length;
    final meetings = _history.where((h) {
      final gap = m.playedAt.difference(h.$1.playedAt);
      return gap.inDays < 30 && {...h.$1.mine, ...h.$1.theirs}.containsAll(lineup);
    }).length;

    final impact = arcRate(
      ArcPlayerState(spi: f.spi, sxp: _sxp, matches: f.matches, overallSpi: overallSpi),
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
        previousMeetings: meetings,
        matchesEarlierToday: earlierToday,
      ),
    );
    _sxp = impact.sxpAfter;
    _formats[m.format] = ArcFormatState(
      spi: impact.spiAfter,
      sxp: f.sxp + impact.sxpGain,
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

/// A player's ARC profile, worked out from their rated matches alone, so the
/// header, graph and every match's change always agree.
class ArcSummary {
  const ArcSummary({
    required this.sxp,
    required this.spi,
    required this.formats,
    required this.heat,
    required this.level,
    required this.lockedLevel,
    required this.verifiedMatches,
    required this.tournamentMatches,
    required this.confirmed,
  });

  /// Career SXP, all formats.
  final double sxp;

  /// Power Index across formats.
  final double spi;
  final Map<PlayCategory, ArcFormatState> formats;

  /// Signed %, or null before 3 rated matches.
  final double? heat;

  /// The level reached (SXP and gates).
  final ArcLevel level;

  /// The level SXP alone would give, when a gate still holds it back.
  final ArcLevel? lockedLevel;
  final int verifiedMatches;
  final int tournamentMatches;
  final bool confirmed;

  int get points => sxp.round();

  /// Builds the summary from [mine]: the player's matches, each carrying its
  /// [Match.arc] impact. Formats' SPI come from each format's latest match.
  static ArcSummary? fromMatches(Iterable<Match> mine) {
    final rated = [
      for (final m in mine)
        if (m.isCompleted && m.involvesMe && m.arc != null) m,
    ]..sort((a, b) => a.playedAt.compareTo(b.playedAt));
    if (rated.isEmpty) return null;
    final formats = <PlayCategory, ArcFormatState>{};
    var sxp = 0.0;
    for (final m in rated) {
      final a = m.arc!;
      final f = formats[m.format];
      formats[m.format] = ArcFormatState(
        spi: a.spiAfter,
        sxp: (f?.sxp ?? 0) + a.sxpGain,
        matches: (f?.matches ?? 0) + (a.trust.movesSkill ? 1 : 0),
      );
      sxp = a.sxpAfter;
    }
    final played = formats.values.where((f) => f.matches > 0).toList();
    final n = played.fold<int>(0, (s, f) => s + f.matches);
    final spi = n == 0 ? ArcWeights.newPlayerSpi : played.fold<double>(0, (s, f) => s + f.spi * f.matches) / n;
    final verified = rated.where((m) => m.arc!.trust.movesSkill).length;
    final tournament = rated.where((m) => m.arc!.type.weight >= ArcMatchType.tournament.weight).length;
    final confirmed = verified >= ArcWeights.provisionalMatches;
    final level = ArcLevel.reached(sxp, verified: verified, tournament: tournament, confirmed: confirmed);
    final bySxp = ArcLevel.of(sxp);
    return ArcSummary(
      sxp: sxp,
      spi: spi,
      formats: formats,
      heat: arcHeat([for (final m in rated.reversed) m.arc!]),
      level: level,
      lockedLevel: bySxp.number > level.number ? bySxp : null,
      verifiedMatches: verified,
      tournamentMatches: tournament,
      confirmed: confirmed,
    );
  }
}
