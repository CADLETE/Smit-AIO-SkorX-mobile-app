import 'package:flutter/material.dart';

import '../../../design/design.dart';
import '../../player/data/player_repository.dart' show PlayCategory;
import '../arc_career.dart';
import '../arc_engine.dart';

/// "56.4", the Power Index as players see it.
String arcSpiText(double spi) => spi.toStringAsFixed(1);

/// "+4.2" / "−1.5" for a signed decimal.
String arcSigned(double v, {int digits = 1}) {
  final s = v.abs().toStringAsFixed(digits);
  return v < 0 ? '−$s' : '+$s';
}

/// The player's level: its name, the bar to the next level and what is left.
class ArcLevelBar extends StatelessWidget {
  const ArcLevelBar({super.key, required this.summary});

  final ArcSummary summary;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final level = summary.level;
    final next = level.next;
    final progress = summary.lockedLevel != null ? 1.0 : level.progress(summary.sxp);
    final left = next == null ? 0 : (next.minSxp - summary.sxp).ceil();
    final locked = summary.lockedLevel;
    final caption = locked != null
        ? '${locked.name} unlocks after ${_gate(locked)}'
        : next == null
            ? 'The top level. Every 200 SXP adds a Legend star.'
            : '$left SXP to ${next.name}';
    return Semantics(
      label: 'Level ${level.number}, ${level.name}. $caption',
      excludeSemantics: true,
      child: Column(
        key: const Key('arcLevel'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Crest(level: level.number),
              const SizedBox(width: Sx.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(level.name.toUpperCase(),
                        style: SxType.heading(c.ink, size: 16).copyWith(fontWeight: FontWeight.w900, letterSpacing: 0.6)),
                    Text('Level ${level.number} · ${level.tagline}', style: SxType.caption(c.inkMuted, size: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Sx.s12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 8,
              width: double.infinity,
              child: ColoredBox(
                color: c.line,
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: progress,
                  heightFactor: 1,
                  child: DecoratedBox(decoration: BoxDecoration(gradient: c.brand)),
                ),
              ),
            ),
          ),
          const SizedBox(height: Sx.s8),
          Text(caption, style: SxType.caption(c.inkMuted, size: 12)),
        ],
      ),
    );
  }

  String _gate(ArcLevel l) {
    final parts = [
      if (summary.verifiedMatches < l.verifiedMatches) '${l.verifiedMatches - summary.verifiedMatches} more verified matches',
      if (summary.tournamentMatches < l.tournamentMatches)
        '${l.tournamentMatches - summary.tournamentMatches} more tournament matches',
      if (l.needsConfirmed && !summary.confirmed) 'your Power Index is confirmed',
    ];
    return parts.join(' and ');
  }
}

/// The level crest: a shape that grows with the level, brand colours only.
class _Crest extends StatelessWidget {
  const _Crest({required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final shape = level <= 2
        ? const CircleBorder()
        : level <= 4
            ? const StarBorder.polygon(sides: 6, pointRounding: 0.3)
            : RoundedRectangleBorder(borderRadius: BorderRadius.circular(level >= 10 ? 14 : 8));
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        shape: shape,
        gradient: level >= 7 ? c.brand : null,
        color: level >= 7 ? null : (level >= 3 ? c.blue : c.surfaceAlt),
        shadows: level >= 7 ? c.glowOf(c.voltFill, strength: 0.5) : null,
      ),
      child: Text('$level',
          style: SxType.number(18, level >= 7 ? c.onVolt : Colors.white, weight: FontWeight.w900)),
    );
  }
}

/// Power Index and Heat side by side.
class ArcSkillStrip extends StatelessWidget {
  const ArcSkillStrip({super.key, required this.summary});

  final ArcSummary summary;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final heat = summary.heat;
    return Row(
      key: const Key('arcSkill'),
      children: [
        Expanded(
          child: _Tile(
            label: summary.confirmed ? 'Power Index' : 'Power Index · provisional',
            value: arcSpiText(summary.spi),
            caption: 'Skill now, out of 100',
          ),
        ),
        const SizedBox(width: Sx.s12),
        Expanded(
          child: _Tile(
            label: 'Heat',
            value: heat == null ? '—' : '${heat >= 0 ? '+' : '−'}${heat.abs().round()}%',
            caption: heat == null ? 'After 3 rated matches' : arcHeatLabel(heat),
            valueColor: heat != null && heat > 5 ? c.volt : null,
          ),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value, required this.caption, this.valueColor});

  final String label;
  final String value;
  final String caption;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Semantics(
      label: '$label $value, $caption',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(Sx.s12),
        decoration: BoxDecoration(
          color: c.surfaceAlt,
          borderRadius: BorderRadius.circular(Sx.radiusLg),
          border: Border.all(color: c.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: SxType.caption(c.inkMuted, size: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(value, style: SxType.number(26, valueColor ?? c.ink, weight: FontWeight.w900)),
            Text(caption, style: SxType.caption(c.inkMuted, size: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

/// SXP and Power Index per format: the three add up to the career total.
class ArcFormats extends StatelessWidget {
  const ArcFormats({super.key, required this.summary});

  final ArcSummary summary;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Row(
      key: const Key('arcFormats'),
      children: [
        for (final (i, f) in PlayCategory.values.indexed) ...[
          if (i > 0) const SizedBox(width: Sx.s8),
          Expanded(
            child: Builder(builder: (context) {
              final s = summary.formats[f];
              return Semantics(
                label: s == null ? '${f.label}: not played' : '${f.label}: ${s.sxp.round()} SXP, Power ${arcSpiText(s.spi)}',
                excludeSemantics: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(f.label, style: SxType.caption(c.inkMuted, size: 12)),
                    Text(s == null ? '—' : '${s.sxp.round()}', style: SxType.number(20, c.ink, weight: FontWeight.w800)),
                    Text(s == null ? 'Not played' : 'Power ${arcSpiText(s.spi)}',
                        style: SxType.caption(c.inkMuted, size: 11.5)),
                  ],
                ),
              );
            }),
          ),
        ],
      ],
    );
  }
}

/// "Why did my score change": every credit and multiplier as a line, the
/// Power Index move, and one sentence.
class ArcBreakdown extends StatelessWidget {
  const ArcBreakdown({super.key, required this.impact});

  final ArcImpact impact;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final lines = impact.displayLines;
    Widget row(String label, String value, {Color? color, bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(child: Text(label, style: SxType.body(bold ? c.ink : c.inkMuted, size: 14))),
              Text(value,
                  style: SxType.number(15, color ?? c.ink, weight: bold ? FontWeight.w900 : FontWeight.w700)),
            ],
          ),
        );
    return Column(
      key: const Key('arcBreakdown'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final l in lines) row(l.label, arcSigned(l.value), color: l.value < 0 ? c.inkMuted : null),
        Divider(height: Sx.s16, color: c.line),
        row('SkorX Points', '+${impact.sxpGain.round()}', color: c.volt, bold: true),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(child: Text('Power Index', style: SxType.body(c.inkMuted, size: 14))),
              Text(arcSpiText(impact.spiBefore), style: SxType.number(15, c.inkMuted)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.arrow_forward_rounded, size: 14, color: c.inkFaint),
              ),
              Text(arcSpiText(impact.spiAfter),
                  style: SxType.number(15, impact.trust.movesSkill ? c.ink : c.inkMuted, weight: FontWeight.w700)),
            ],
          ),
        ),
        const SizedBox(height: Sx.s8),
        Text(
          [
            impact.why,
            'Opponent: ${impact.opponentLabel} (Power ${arcSpiText(impact.opponentSpi)})',
            '${impact.type.label} match · ${impact.trust.label}',
            if (!impact.trust.movesSkill) 'Self-reported: Power Index unchanged',
            if (impact.repeatFactor < 1) 'Repeat opponent: ${(impact.repeatFactor * 100).round()}% credit',
          ].join(' · '),
          style: SxType.caption(c.inkMuted, size: 12),
        ),
      ],
    );
  }
}

/// A plain-language explanation of SkorX Points, Power Index and Heat.
Future<void> showArcExplainer(BuildContext context) => showSxSheet(
      context,
      builder: (context) {
        final c = context.sx;
        Widget para(String title, String body) => Padding(
              padding: const EdgeInsets.only(bottom: Sx.s16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: SxType.heading(c.ink, size: 16)),
                  const SizedBox(height: 4),
                  Text(body, style: SxType.body(c.inkMuted, size: 14)),
                ],
              ),
            );
        return SingleChildScrollView(
          key: const Key('arcExplainer'),
          padding: const EdgeInsets.fromLTRB(Sx.s20, 0, Sx.s20, Sx.s24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('How SkorX Points work', style: SxType.heading(c.ink, size: 20)),
              const SizedBox(height: Sx.s16),
              para('SkorX Points (SXP): your career',
                  'Every match adds points. You earn for playing, for every point you win, for winning, and extra '
                      'when you beat what SkorX expected. Your total never goes down.'),
              para('Power Index: how good you are now',
                  'A 0–100 number that goes up when you win more points than expected and down when you win fewer. '
                      'Rankings and opponent strength use it.'),
              para('Heat: your form',
                  'How far above or below expectation you played over your last 10 rated matches.'),
              para('What makes a match worth more',
                  'Stronger opponents, tournaments and finals, and scores verified by an organiser. Friendly '
                      'matches count a little less, and playing the same opponent again and again counts less each time.'),
              para('Levels',
                  'Your SXP moves you through 12 levels, from First Serve to SkorX Legend. Higher levels also need '
                      'verified and tournament matches.'),
            ],
          ),
        );
      },
    );
