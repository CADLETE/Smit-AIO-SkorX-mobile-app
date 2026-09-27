import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design/design.dart';
import '../../../sports/core/score_state.dart';
import '../../auth/auth_controller.dart';
import '../../casual_match/local_match.dart';
import '../arc_engine.dart';
import 'arc_widgets.dart';

/// What a finished friendly will add to each side's SkorX Points, shown on
/// the result screen. The signed-in player's own side gets the count-up.
///
/// It is an estimate until the match reaches SkorX: a friendly counts as
/// player verified once both sides confirm, and until SkorX has the players'
/// history every Power Index is taken as equal, so the expectation is 50%.
class ArcMatchResult extends ConsumerWidget {
  const ArcMatchResult({super.key, required this.match});

  final LocalMatch match;

  /// Each side's impact, or null when the match does not count (walkover).
  static Map<Side, ArcImpact>? impacts(LocalMatch match) {
    final winner = match.winner;
    if (winner == null || match.outcome?.kind == EarlyEnd.walkover) return null;
    var a = 0, b = 0;
    for (final g in match.score.games) {
      a += g.a;
      b += g.b;
    }
    if (a + b == 0) return null;
    ArcImpact side(Side s) {
      final mine = s == Side.a ? a : b, theirs = s == Side.a ? b : a;
      return arcRate(
        ArcPlayerState.newPlayer,
        ArcMatchInput(
          mySide: [for (final _ in match.names(s)) ArcWeights.newPlayerSpi],
          theirSide: [for (final _ in match.names(s == Side.a ? Side.b : Side.a)) ArcWeights.newPlayerSpi],
          pointsFor: mine,
          pointsAgainst: theirs,
          won: winner == s,
          type: ArcMatchType.casual,
          trust: ArcTrust.players,
          retired: match.outcome?.kind == EarlyEnd.retired,
        ),
      );
    }

    return {Side.a: side(Side.a), Side.b: side(Side.b)};
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final all = impacts(match);
    if (all == null) return const SizedBox.shrink();
    final me = ref.watch(currentUserProvider)?.name;
    final mySide = me == null
        ? null
        : Side.values.where((s) => match.names(s).contains(me)).firstOrNull;
    final focus = mySide ?? match.winner!;
    final impact = all[focus]!;
    final other = all[focus == Side.a ? Side.b : Side.a]!;
    final gain = impact.sxpGain;

    return SxBlock(
      key: const Key('arcMatchResult'),
      padding: const EdgeInsets.all(Sx.s20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(mySide != null ? 'YOUR SKORX POINTS' : 'SKORX POINTS · ${match.teamLabel(focus).toUpperCase()}',
              style: SxType.label(c.inkMuted, size: 11)),
          const SizedBox(height: Sx.s4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _CountTo(value: gain, style: SxType.hero(64, c.volt)),
              const SizedBox(width: Sx.s8),
              Padding(
                padding: const EdgeInsets.only(bottom: Sx.s12),
                child: Text('SXP', style: SxType.heading(c.ink, size: 18)),
              ),
            ],
          ),
          const SizedBox(height: Sx.s8),
          for (final l in impact.displayLines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(child: Text(l.label, style: SxType.body(c.inkMuted, size: 14))),
                  Text(arcSigned(l.value), style: SxType.number(15, l.value < 0 ? c.inkMuted : c.ink)),
                ],
              ),
            ),
          Divider(height: Sx.s20, color: c.line),
          Text(
            '${match.teamLabel(focus == Side.a ? Side.b : Side.a)}: +${other.sxpGain.round()} SXP. '
            'Estimate: it counts when both sides confirm, and moves once SkorX knows everyone\'s Power Index.',
            style: SxType.caption(c.inkMuted, size: 12),
          ),
          const SizedBox(height: Sx.s8),
          Tappable(
            onTap: () => showArcExplainer(context),
            child: Text('How SkorX Points work',
                style: SxType.caption(c.isDark ? c.cyan : c.blue, size: 13).copyWith(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

/// Counts from 0 up to [value] once, ending on "+12".
class _CountTo extends StatelessWidget {
  const _CountTo({required this.value, required this.style});

  final double value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final end = value.round();
    if (sxReduceMotion(context)) return Text('+$end', style: style);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: end.toDouble()),
      duration: const Duration(milliseconds: 1200),
      curve: Curves.easeOutCubic,
      builder: (_, v, _) => Text('+${v.round()}', style: style),
    );
  }
}
