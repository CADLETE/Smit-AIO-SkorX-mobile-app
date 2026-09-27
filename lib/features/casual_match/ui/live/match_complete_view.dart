import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../design/design.dart';
import '../../../../sports/core/score_state.dart';
import '../../../auth/auth_controller.dart';
import '../../../rating/ui/arc_match_result.dart';
import '../../live/match_analytics.dart';
import '../../local_match.dart';
import '../../scoring_controller.dart';
import '../court_top_view.dart';
import '../scoring_labels.dart';
import 'match_charts.dart';
import 'share_result.dart';

/// The result, held on screen until the scorer is done with it: the winner,
/// every game, how the points went (charts), head-to-head numbers, who
/// served best, and who scored it. Shareable as an image.
class MatchCompleteView extends StatelessWidget {
  const MatchCompleteView({super.key, required this.match, required this.onDone, required this.onUndo});

  final LocalMatch match;
  final VoidCallback onDone;

  /// Takes back the last point (or the walkover) and reopens the match.
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final score = match.score;
    final winner = match.winner!;
    final early = match.outcome?.kind;
    final a = analyzeMatch(match);
    final showGames = early != EarlyEnd.walkover;
    var section = 0;
    Widget reveal(Widget child) => SxReveal(index: section++, child: child);

    return SxWidth(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s12, Sx.gutter, Sx.s32),
        children: [
          reveal(_Hero(match: match, winner: winner, showGames: showGames)),
          if (ArcMatchResult.impacts(match) != null) ...[
            const SizedBox(height: Sx.s24),
            reveal(ArcMatchResult(match: match)),
          ],
          if (showGames) ...[
            const SizedBox(height: Sx.s24),
            const SxSection('Game scores'),
            reveal(_GamesTable(match: match, score: score, winner: winner)),
          ],
          if (a.hasRallies) ...[
            const SizedBox(height: Sx.s24),
            const SxSection('Points by game'),
            reveal(SxBlock(child: PointsProgressChart(match: match, analytics: a))),
            const SizedBox(height: Sx.s24),
            const SxSection('Momentum'),
            reveal(SxBlock(child: MomentumChart(match: match, analytics: a))),
            const SizedBox(height: Sx.s24),
            const SxSection('Head to head'),
            reveal(SxBlock(child: _HeadToHead(match: match, analytics: a))),
            const SizedBox(height: Sx.s24),
            SxSection(match.names(Side.a).length > 1 ? 'On serve, by player' : 'On serve'),
            reveal(SxBlock(child: _Servers(match: match, analytics: a))),
          ],
          const SizedBox(height: Sx.s24),
          const SxSection('Match'),
          reveal(SxBlock(
            child: Column(
              children: [
                _Fact(icon: Icons.tag_rounded, label: 'Match ID', value: match.displayCode, valueKey: const Key('matchCode')),
                _Fact(icon: Icons.category_rounded, label: 'Match', value: matchTypeLabel(match)),
                if (match.details.courtLabel != null)
                  _Fact(icon: Icons.grid_on_rounded, label: 'Court', value: match.details.courtLabel!),
                _Fact(icon: Icons.timer_outlined, label: 'Duration', value: clockText(a.duration)),
                _Fact(icon: Icons.rule_rounded, label: 'Format', value: match.rules.describe()),
                if (a.hasRallies) ...[
                  _Fact(icon: Icons.sports_tennis_rounded, label: 'Rallies', value: '${a.rallies.length}'),
                  if (a.averageRally != null)
                    _Fact(icon: Icons.av_timer_rounded, label: 'Time per rally', value: '${a.averageRally!.inSeconds}s average'),
                  _Fact(icon: Icons.swap_vert_rounded, label: 'Lead changes', value: '${a.leadChanges}'),
                  _Fact(icon: Icons.drag_handle_rounded, label: 'Times level', value: '${a.ties}'),
                ],
              ],
            ),
          )),
          const SizedBox(height: Sx.s24),
          reveal(_ScoredBy(match: match)),
          if (a.hasRallies) ...[
            const SizedBox(height: Sx.s16),
            _RallyLog(match: match, analytics: a),
          ],
          const SizedBox(height: Sx.s24),
          SxButton(key: const Key('done'), label: 'Done', icon: Icons.check_rounded, onPressed: onDone),
          const SizedBox(height: Sx.s12),
          Row(
            children: [
              Expanded(
                child: SxButton.secondary(
                  key: const Key('shareButton'),
                  label: 'Share',
                  icon: Icons.ios_share_rounded,
                  onPressed: () => shareMatchResult(context, match, a),
                ),
              ),
              const SizedBox(width: Sx.s12),
              Expanded(
                child: SxButton.secondary(
                  key: const Key('undoResult'),
                  label: early == null ? 'Undo point' : 'Undo ${early.label.toLowerCase()}',
                  icon: Icons.undo_rounded,
                  onPressed: onUndo,
                ),
              ),
            ],
          ),
          const SizedBox(height: Sx.s8),
          Center(child: Text('Saved on this phone', style: SxType.caption(c.inkFaint, size: 12))),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.match, required this.winner, required this.showGames});

  final LocalMatch match;
  final Side winner;
  final bool showGames;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final score = match.score;
    final early = match.outcome?.kind;
    final single = match.rules.bestOf == 1;
    final (w, l, unit) = single
        ? (score.games.last.of(winner), score.games.last.of(winner.opponent), 'POINTS')
        : (score.gamesWon(winner), score.gamesWon(winner.opponent), 'GAMES');
    return SxHeroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SxHeroTag(text: early == null ? 'MATCH COMPLETE' : early.label.toUpperCase(), icon: Icons.emoji_events_rounded, highlight: true),
          const SizedBox(height: Sx.s16),
          Text('WINNER', style: SxType.label(Colors.white.withValues(alpha: 0.8), size: 13)),
          const SizedBox(height: Sx.s8),
          Row(
            children: [
              SideDps(names: match.names(winner), size: 44, edge: c.voltFill),
              const SizedBox(width: Sx.s12),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  excludeSemantics: true,
                  label: '${match.teamLabel(winner)} won',
                  child: Text(match.teamLabel(winner), key: const Key('result'), style: SxType.title(Colors.white, size: 32)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('def. ${match.teamLabel(winner.opponent)}', style: SxType.body(Colors.white.withValues(alpha: 0.75), size: 14)),
          if (showGames) ...[
            const SizedBox(height: Sx.s12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('$w', style: SxType.hero(84, c.voltFill)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Sx.s12, vertical: 10),
                  child: Text('–', style: SxType.hero(48, Colors.white.withValues(alpha: 0.6))),
                ),
                Text('$l', style: SxType.hero(84, Colors.white)),
                const SizedBox(width: Sx.s12),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(unit, style: SxType.label(Colors.white.withValues(alpha: 0.75))),
                ),
              ],
            ),
          ],
          const SizedBox(height: Sx.s8),
          Text(match.displayCode, style: SxType.label(Colors.white.withValues(alpha: 0.7), size: 11.5)),
        ],
      ),
    );
  }
}

class _HeadToHead extends StatelessWidget {
  const _HeadToHead({required this.match, required this.analytics});

  final LocalMatch match;
  final MatchAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    final a = analytics.stats[Side.a]!;
    final b = analytics.stats[Side.b]!;
    String pct(int won, int of) => of == 0 ? '–' : '${(won * 100 / of).round()}%';
    return Column(
      children: [
        ChartLegend(match: match),
        const SizedBox(height: Sx.s8),
        VersusRow(label: 'Points won', a: a.points, b: b.points),
        VersusRow(label: 'Rallies won', a: a.ralliesWon, b: b.ralliesWon),
        VersusRow(
          label: 'Points on serve',
          a: a.servicePoints,
          b: b.servicePoints,
          valueA: '${a.servicePoints}/${a.serveRallies}',
          valueB: '${b.servicePoints}/${b.serveRallies}',
        ),
        VersusRow(
          label: 'Serve broken',
          a: a.returnRalliesWon,
          b: b.returnRalliesWon,
          valueA: pct(a.returnRalliesWon, a.returnRallies),
          valueB: pct(b.returnRalliesWon, b.returnRallies),
        ),
        VersusRow(label: 'Best run', a: a.bestRun, b: b.bestRun),
        VersusRow(label: 'Biggest lead', a: a.biggestLead, b: b.biggestLead),
      ],
    );
  }
}

class _Servers extends StatelessWidget {
  const _Servers({required this.match, required this.analytics});

  final LocalMatch match;
  final MatchAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final list = [...analytics.servers]..sort((x, y) => y.won.compareTo(x.won));
    final best = list.isEmpty ? 0 : list.first.won;
    return Column(
      children: [
        for (final s in list)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                PlayerDp(name: s.name, size: 30, edge: chartColor(c, s.side)),
                const SizedBox(width: Sx.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(child: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.heading(c.ink, size: 14.5))),
                          if (s.won == best && best > 0) ...[
                            const SizedBox(width: 6),
                            Icon(Icons.star_rounded, size: 15, color: c.volt),
                          ],
                        ],
                      ),
                      Text('${s.won} points from ${s.served} rallies served', style: SxType.caption(c.inkMuted, size: 12)),
                    ],
                  ),
                ),
                Text(s.served == 0 ? '–' : '${(s.won * 100 / s.served).round()}%',
                    style: SxType.number(20, c.ink, weight: FontWeight.w800)),
              ],
            ),
          ),
      ],
    );
  }
}

class _ScoredBy extends ConsumerWidget {
  const _ScoredBy({required this.match});

  final LocalMatch match;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final shifts = scorersOf(match, ref.watch(currentUserProvider));
    final handedOver = shifts.length > 1;
    String from(ScorerShift s) {
      if (s.fromEvent == 0) return 'from the start';
      final sub = match.sport.engine.replay(match.setup, match.events.take(s.fromEvent).map((e) => e.event));
      return 'from ${sub.currentGame.a}–${sub.currentGame.b}, game ${sub.gameNumber}';
    }

    return SxBlock(
      key: const Key('scoredBy'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SxIconTile(icon: Icons.edit_note_rounded, size: 40, colors: [c.blue, c.cyan]),
          const SizedBox(width: Sx.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('MATCH SCORED BY', style: SxType.label(c.inkMuted, size: 11)),
                const SizedBox(height: Sx.s8),
                for (final s in shifts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        PlayerDp(name: s.name, size: 28),
                        const SizedBox(width: Sx.s8),
                        Expanded(
                          child: Text.rich(
                            key: Key('scoredBy-${s.name}'),
                            TextSpan(
                              text: s.name,
                              style: SxType.heading(c.ink, size: 16),
                              children: [
                                if (handedOver) TextSpan(text: '  ${from(s)}', style: SxType.caption(c.inkMuted, size: 12)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Every rally as a table: the chart data, readable without the charts.
class _RallyLog extends StatelessWidget {
  const _RallyLog({required this.match, required this.analytics});

  final LocalMatch match;
  final MatchAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const Key('rallyLog'),
        tilePadding: EdgeInsets.zero,
        title: Text('Rally by rally', style: SxType.heading(c.ink, size: 16)),
        subtitle: Text('${analytics.rallies.length} rallies · who served, who won, the score', style: SxType.caption(c.inkMuted, size: 12)),
        children: [
          for (final r in analytics.rallies)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(width: 44, child: Text('G${r.game}·${r.rallyInGame}', style: SxType.caption(c.inkFaint, size: 12))),
                  Expanded(
                    child: Text(
                      '${match.names(r.servingSide)[r.serverIndex].split(' ').first} served · ${shortSide(match, r.winner)} ${r.scored ? 'point' : 'side out'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SxType.caption(c.ink, size: 12.5),
                    ),
                  ),
                  Text('${r.after.a}–${r.after.b}', style: SxType.number(15, c.ink, weight: FontWeight.w700)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _GamesTable extends StatelessWidget {
  const _GamesTable({required this.match, required this.score, required this.winner});

  final LocalMatch match;
  final ScoreState score;
  final Side winner;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    Widget cell(String text, {bool bold = false, bool faint = false}) => SizedBox(
          width: 40,
          child: Text(text,
              textAlign: TextAlign.center,
              style: SxType.number(22, faint ? c.inkFaint : c.ink, weight: bold ? FontWeight.w800 : FontWeight.w600)),
        );
    return SxBlock(
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(child: SizedBox()),
              for (var i = 0; i < score.games.length; i++)
                SizedBox(width: 40, child: Text('G${i + 1}', textAlign: TextAlign.center, style: SxType.label(c.inkMuted, size: 11))),
            ],
          ),
          const SizedBox(height: Sx.s8),
          for (final side in [winner, winner.opponent])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 28,
                    margin: const EdgeInsets.only(right: Sx.s8),
                    decoration: BoxDecoration(color: CourtTopView.teamColor(c, side), borderRadius: BorderRadius.circular(2)),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        if (side == winner) ...[Icon(Icons.emoji_events_rounded, size: 16, color: c.volt), const SizedBox(width: 4)],
                        Flexible(
                          child: Text(match.teamLabel(side),
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.heading(c.ink, size: 15)),
                        ),
                      ],
                    ),
                  ),
                  for (final g in score.games)
                    cell('${g.of(side)}', bold: g.of(side) > g.of(side.opponent), faint: g.of(side) < g.of(side.opponent)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.label, required this.value, this.valueKey});

  final IconData icon;
  final String label;
  final String value;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: c.inkMuted),
          const SizedBox(width: Sx.s12),
          Text(label, style: SxType.body(c.inkMuted, size: 14)),
          const SizedBox(width: Sx.s16),
          Expanded(child: Text(value, key: valueKey, textAlign: TextAlign.right, style: SxType.heading(c.ink, size: 14.5))),
        ],
      ),
    );
  }
}
