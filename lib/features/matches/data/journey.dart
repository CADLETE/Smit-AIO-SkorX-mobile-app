import 'match.dart';

/// One round of the player's category, in playing order.
class TournamentRound {
  const TournamentRound(this.name, {this.knockout = false, this.startsAt, this.short});

  /// Matches the round in [TournamentRef.round] ("Quarter-final", "Pool A · Match 2").
  final String name;

  /// A loss here ends the player's tournament.
  final bool knockout;
  final DateTime? startsAt;

  /// "QF", for tight spaces.
  final String? short;
}

enum JourneyState {
  /// Registration, draw published: things that simply happened.
  done,
  won,
  lost,
  live,

  /// The next thing to play.
  next,

  /// Still to come.
  ahead,

  /// Will not happen for this player: knocked out before it.
  out,
}

class JourneyStep {
  const JourneyStep({required this.title, required this.state, this.detail, this.match, this.when});

  final String title;
  final JourneyState state;

  /// "11–7 · 11–9 vs Rahul & Jay", "Court 03 · 7:30 PM".
  final String? detail;
  final Match? match;
  final DateTime? when;
}

/// Where the player is in one tournament, built from their registration,
/// their matches and the rounds of their category. Never stored, so it can
/// never disagree with the match list.
class TournamentJourney {
  const TournamentJourney({required this.steps, required this.headline, required this.category, this.partner});

  final List<JourneyStep> steps;

  /// "Playing the quarter-final", "Runner-up", "Out in the semi-final".
  final String headline;
  final String category;
  final String? partner;

  JourneyStep? get current =>
      steps.where((s) => s.state == JourneyState.live || s.state == JourneyState.next).firstOrNull;

  int get won => steps.where((s) => s.state == JourneyState.won).length;
  int get lost => steps.where((s) => s.state == JourneyState.lost).length;
}

String _gamesLine(Match m) => m.games.map((g) => '${g.$1}–${g.$2}').join(' · ');

TournamentJourney buildJourney({
  required String category,
  required DateTime registeredAt,
  String? partner,
  required List<TournamentRound> rounds,
  required List<Match> myMatches,
}) {
  final steps = <JourneyStep>[
    JourneyStep(
      title: 'Registered',
      state: JourneyState.done,
      detail: partner == null ? category : '$category · with ${partner.split(' ').first}',
      when: registeredAt,
    ),
  ];

  var eliminatedIn = '';
  var nextTaken = false;
  String? headline;

  for (final round in rounds) {
    final match = myMatches.where((m) => m.tournament?.round == round.name).firstOrNull;
    if (eliminatedIn.isNotEmpty) {
      steps.add(JourneyStep(title: round.name, state: JourneyState.out, when: round.startsAt));
      continue;
    }
    if (match == null) {
      steps.add(JourneyStep(
        title: round.name,
        state: nextTaken ? JourneyState.ahead : JourneyState.next,
        when: round.startsAt,
        detail: nextTaken ? null : 'Draw to be confirmed',
      ));
      nextTaken = true;
      continue;
    }
    final opp = match.opponentKnown ? 'vs ${sideLabel(match.theirs)}' : 'vs ${match.theirsPlaceholder ?? 'TBD'}';
    switch (match.status) {
      case MatchStatus.completed:
        steps.add(JourneyStep(
          title: round.name,
          state: match.won ? JourneyState.won : JourneyState.lost,
          detail: '${_gamesLine(match)} $opp',
          match: match,
          when: match.playedAt,
        ));
        if (!match.won && round.knockout) eliminatedIn = round.name;
      case MatchStatus.live:
        steps.add(JourneyStep(title: round.name, state: JourneyState.live, detail: opp, match: match));
        headline ??= 'Playing the ${round.name.toLowerCase()}';
        nextTaken = true;
      case MatchStatus.upcoming:
        steps.add(JourneyStep(
          title: round.name,
          state: nextTaken ? JourneyState.ahead : JourneyState.next,
          detail: [opp, ?match.court].join(' · '),
          match: match,
          when: match.scheduledAt,
        ));
        headline ??= 'Next: ${round.name.toLowerCase()}';
        nextTaken = true;
      case MatchStatus.cancelled:
        steps.add(JourneyStep(title: round.name, state: JourneyState.out, detail: 'Cancelled', match: match));
    }
  }

  final lastRound = rounds.isEmpty ? null : rounds.last;
  final finalMatch = lastRound == null ? null : myMatches.where((m) => m.tournament?.round == lastRound.name).firstOrNull;
  if (finalMatch != null && finalMatch.isCompleted) {
    headline = finalMatch.won ? 'Champion' : 'Runner-up';
  } else if (eliminatedIn.isNotEmpty) {
    headline = 'Out in the ${eliminatedIn.toLowerCase()}';
  }

  return TournamentJourney(
    steps: steps,
    headline: headline ?? 'Registered',
    category: category,
    partner: partner,
  );
}

/// One team's line in a pool table.
class StandingRow {
  const StandingRow({
    required this.team,
    required this.played,
    required this.won,
    required this.pointDiff,
    required this.isMe,
  });

  final String team;
  final int played;
  final int won;
  final int pointDiff;
  final bool isMe;

  int get lost => played - won;
}

class PoolTable {
  const PoolTable(this.pool, this.rows);

  final String pool;

  /// Best first: wins, then point difference.
  final List<StandingRow> rows;
}

/// Pool tables from the finished pool matches.
List<PoolTable> computeStandings(List<Match> matches) {
  final byPool = <String, Map<String, ({int played, int won, int diff, bool me})>>{};
  for (final m in matches) {
    final pool = m.tournament?.pool;
    if (pool == null) continue;
    final table = byPool.putIfAbsent(pool, () => {});
    final a = sideLabel(m.mine);
    final b = sideLabel(m.theirs);
    void ensure(String team, bool me) =>
        table.putIfAbsent(team, () => (played: 0, won: 0, diff: 0, me: me));
    ensure(a, m.involvesMe);
    ensure(b, false);
    if (!m.isCompleted) continue;
    final diff = m.pointsWon - m.pointsLost;
    void add(String team, bool won, int d) {
      final r = table[team]!;
      table[team] = (played: r.played + 1, won: r.won + (won ? 1 : 0), diff: r.diff + d, me: r.me);
    }

    add(a, m.won, diff);
    add(b, !m.won, -diff);
  }
  final pools = byPool.keys.toList()..sort();
  return [
    for (final p in pools)
      PoolTable(
        p,
        [
          for (final e in byPool[p]!.entries)
            StandingRow(team: e.key, played: e.value.played, won: e.value.won, pointDiff: e.value.diff, isMe: e.value.me),
        ]..sort((x, y) => y.won != x.won ? y.won.compareTo(x.won) : y.pointDiff.compareTo(x.pointDiff)),
      ),
  ];
}
