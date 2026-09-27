import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design/design.dart';
import '../../../sports/core/match_rules.dart';
import '../../../sports/core/sport_definition.dart';

/// Games, scoring, play to, win by: always on show, each one tap.
class RulesBlock extends StatelessWidget {
  const RulesBlock({super.key, required this.sport, required this.rules, required this.onChanged});

  final SportDefinition sport;
  final MatchRules rules;
  final ValueChanged<MatchRules> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    Widget row(String label, Widget control, [String? caption]) => Padding(
          padding: const EdgeInsets.only(bottom: Sx.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label.toUpperCase(), style: SxType.label(c.inkMuted)),
              const SizedBox(height: Sx.s8),
              control,
              if (caption != null) ...[const SizedBox(height: 6), Text(caption, style: SxType.caption(c.inkMuted, size: 12))],
            ],
          ),
        );
    return SxBlock(
      padding: const EdgeInsets.fromLTRB(Sx.s16, Sx.s16, Sx.s16, 0),
      child: Column(
        children: [
          row(
            'Games',
            SegmentedPills<int>(
              keyPrefix: 'bestOf',
              options: [for (final n in sport.bestOfOptions) (n, n == 1 ? '1 game' : 'Best of $n')],
              selected: rules.bestOf,
              onChanged: (n) => onChanged(rules.copyWith(bestOf: n)),
            ),
          ),
          if (sport.scoringSystems.length > 1)
            row(
              'Scoring',
              SegmentedPills<ScoringSystem>(
                keyPrefix: 'scoring',
                options: const [(ScoringSystem.rally, 'Rally'), (ScoringSystem.sideOut, 'Side out')],
                selected: rules.scoring,
                onChanged: (s) => onChanged(rules.copyWith(scoring: s)),
              ),
              rules.scoring == ScoringSystem.rally
                  ? 'Every rally wins a point, whoever served.'
                  : 'Only the serving side scores; a lost rally passes the serve.',
            ),
          row(
            'Points',
            SegmentedPills<int>(
              keyPrefix: 'playTo',
              options: [for (final n in sport.pointTargets) (n, 'Play to $n')],
              selected: rules.pointsToWin,
              onChanged: (n) => onChanged(rules.copyWith(pointsToWin: n)),
            ),
          ),
          row(
            'Win by',
            SegmentedPills<bool>(
              keyPrefix: 'winBy',
              options: const [(false, '1 point'), (true, '2 points')],
              selected: rules.winByTwo,
              onChanged: (v) => onChanged(rules.copyWith(winByTwo: v)),
            ),
          ),
        ],
      ),
    );
  }
}

class SegmentedPills<T> extends StatelessWidget {
  const SegmentedPills({super.key, required this.keyPrefix, required this.options, required this.selected, required this.onChanged});

  final String keyPrefix;
  final List<(T, String)> options;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Container(
      height: 44,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(Sx.radiusSm)),
      child: Row(
        children: [
          for (final (value, label) in options)
            Expanded(
              child: Semantics(
                button: true,
                selected: value == selected,
                label: label,
                excludeSemantics: true,
                child: Tappable(
                  key: Key('$keyPrefix-$value'),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onChanged(value);
                  },
                  radius: Sx.radiusSm - 3,
                  child: AnimatedContainer(
                    duration: Sx.medium,
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: value == selected ? c.brand : null,
                      borderRadius: BorderRadius.circular(Sx.radiusSm - 3),
                      boxShadow: value == selected ? c.glowOf(c.voltFill, strength: 0.4) : null,
                    ),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: SxType.sans,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: value == selected ? c.onVolt : c.inkMuted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
