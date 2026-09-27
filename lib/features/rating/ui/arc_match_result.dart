import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design/design.dart';
import '../../../sports/core/score_state.dart';
import '../../auth/auth_controller.dart';
import '../../casual_match/local_match.dart';
import '../../player/data/player_repository.dart' show playerOverviewProvider;
import '../arc_engine.dart';
import 'arc_widgets.dart';

/// What a finished friendly adds to each side's SkorX Points, and what it
/// does to their SkorX Rating, shown on the result screen. The signed-in
/// player's own side gets the count-up and their Career Score before and
/// after.
///
/// SkorX Points are exact: the points the side scored ÷ 20, shared by the
/// players on the side. They are credited once both sides confirm the
/// score. The rating move is an estimate: until SkorX has the players'
/// history every rating is taken as equal, so the expectation is 50%.
class ArcMatchResult extends ConsumerWidget {
  const ArcMatchResult({super.key, required this.match});

  final LocalMatch match;

  /// Each side's impact, or null when the match adds nothing (a walkover, or
  /// no points played). [careerUnits] is each side's Career Score going in,
  /// where known.
  static Map<Side, ArcImpact>? impacts(LocalMatch match, {Map<Side, int> careerUnits = const {}}) {
    final winner = match.winner;
    if (winner == null || match.outcome?.kind == EarlyEnd.walkover) return null;
    // Only points actually played count: a retirement ends the match
    // without awarding the rest.
    var a = 0, b = 0;
    for (final g in match.score.games) {
      a += g.a;
      b += g.b;
    }
    if (a + b == 0) return null;
    ArcImpact side(Side s) {
      final mine = s == Side.a ? a : b, theirs = s == Side.a ? b : a;
      return arcRate(
        ArcPlayerState(spi: ArcWeights.newPlayerSpi, sxpUnits: careerUnits[s] ?? 0, matches: 0),
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
    final me = ref.watch(currentUserProvider)?.name;
    final mySide = me == null
        ? null
        : Side.values.where((s) => match.names(s).contains(me)).firstOrNull;
    final overview = ref.watch(playerOverviewProvider);
    final knowCareer = mySide != null && overview.hasValue;
    final all = impacts(match, careerUnits: {if (knowCareer) mySide: overview.value?.arc?.sxpUnits ?? 0});
    if (all == null) return const SizedBox.shrink();
    final focus = mySide ?? match.winner!;
    final impact = all[focus]!;
    final other = all[focus == Side.a ? Side.b : Side.a]!;
    final shareNote = impact.playersOnSide > 1 ? ' each' : '';

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
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.bottomLeft,
                  child: SxpCountUp(value: impact.shownGain, from: 0, signed: true, style: SxType.hero(56, c.volt)),
                ),
              ),
              const SizedBox(width: Sx.s8),
              Padding(
                padding: const EdgeInsets.only(bottom: Sx.s12),
                child: Text('SXP$shareNote', style: SxType.heading(c.ink, size: 18)),
              ),
            ],
          ),
          const SizedBox(height: Sx.s12),
          SxpUpdate(impact: impact, showCareer: knowCareer, pending: true),
          Divider(height: Sx.s24, color: c.line),
          Row(
            key: const Key('arcRatingMove'),
            children: [
              Expanded(child: Text('SkorX Rating', style: SxType.heading(c.ink, size: 15))),
              RatingDelta(impact.spiChange, size: 16, digits: 1),
            ],
          ),
          const SizedBox(height: Sx.s4),
          Text(arcRatingWhy(impact), style: SxType.caption(c.inkMuted, size: 12)),
          const SizedBox(height: Sx.s12),
          Text(
            '${match.teamLabel(focus == Side.a ? Side.b : Side.a)}: ${sxpDeltaText(other.shownGain)} SXP'
            '${other.playersOnSide > 1 ? ' each' : ''} (${other.formula}).',
            style: SxType.caption(c.inkMuted, size: 12),
          ),
          const SizedBox(height: Sx.s8),
          Tappable(
            onTap: () => showArcExplainer(context),
            child: Text('How Rating and Points work',
                style: SxType.caption(c.isDark ? c.cyan : c.blue, size: 13).copyWith(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
