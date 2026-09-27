import 'package:flutter/material.dart';

import '../../../design/design.dart';
import '../../../shared/format.dart';
import '../../player/data/player_repository.dart' show PlayCategory;
import '../arc_career.dart';
import '../arc_engine.dart';

export '../../../shared/format.dart' show ratingText, sxpText, sxpDeltaText;

// Players see two numbers, never mixed up:
// - SkorX Rating: skill now, 0–100, up and down, with a band.
// - SkorX Points: the Career Score, built only from points scored, with a level.

/// "+4.2" / "−1.5" for a signed decimal.
String arcSigned(double v, {int digits = 1}) {
  final s = v.abs().toStringAsFixed(digits);
  return v < 0 ? '−$s' : '+$s';
}

/// The band name on a pill: "Intermediate".
class SkorxBandChip extends StatelessWidget {
  const SkorxBandChip({super.key, required this.band, this.size = 12});

  final SkorxBand band;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final top = band == SkorxBand.pro;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: size * 0.8, vertical: size * 0.3),
      decoration: BoxDecoration(
        gradient: top ? c.brand : null,
        color: top ? null : c.surfaceAlt,
        borderRadius: BorderRadius.circular(99),
        border: top ? null : Border.all(color: c.line),
      ),
      child: Text(band.label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: SxType.label(top ? c.onVolt : c.ink, size: size * 0.9).copyWith(fontWeight: FontWeight.w800)),
    );
  }
}

/// The four bands as one ladder, filled up to the player's rating, with how
/// far it is to the next band.
class SkorxBandBar extends StatelessWidget {
  const SkorxBandBar({super.key, required this.rating});

  final double rating;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final band = SkorxBand.of(rating);
    final next = band.next;
    final caption =
        next == null ? 'The top band' : '${ratingText(next.from - rating)} to ${next.label} (${next.from.round()})';
    double fill(SkorxBand b) {
      if (b.index < band.index) return 1;
      if (b.index > band.index) return 0;
      final end = b.next?.from ?? 100;
      return ((rating - b.from) / (end - b.from)).clamp(0.04, 1).toDouble();
    }

    return Semantics(
      label: 'SkorX Rating band ${band.label}. $caption',
      excludeSemantics: true,
      child: Column(
        key: const Key('skorxBands'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (final (i, b) in SkorxBand.values.indexed) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: SizedBox(
                          height: 6,
                          child: ColoredBox(
                            color: c.line,
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: fill(b),
                              heightFactor: 1,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: b == band ? c.brand : null,
                                  color: b == band ? null : c.volt.withValues(alpha: 0.4),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(b.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SxType.caption(b == band ? c.ink : c.inkFaint, size: 11)
                              .copyWith(fontWeight: b == band ? FontWeight.w800 : FontWeight.w500)),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: Sx.s4),
          Text(caption, style: SxType.caption(c.inkMuted, size: 12)),
        ],
      ),
    );
  }
}

/// SkorX Rating: skill now. The number and band, the month's move, the band
/// ladder, the graph and each format.
class SkorxRatingPanel extends StatelessWidget {
  const SkorxRatingPanel({super.key, required this.summary, this.now});

  final ArcSummary summary;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final change = summary.ratingChange(now ?? DateTime.now());
    final values = [for (final p in summary.timeline) p.rating];
    final shown = values.length > 30 ? values.sublist(values.length - 30) : values;
    return Column(
      key: const Key('skorxRating'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.bottomLeft,
                child: Semantics(
                  label: 'SkorX Rating ${ratingText(summary.rating)}, ${summary.band.label}',
                  child: Text(ratingText(summary.rating), style: SxType.hero(80, c.ink)),
                ),
              ),
            ),
            const SizedBox(width: Sx.s16),
            Padding(
              padding: const EdgeInsets.only(bottom: Sx.s8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkorxBandChip(band: summary.band),
                  const SizedBox(height: Sx.s8),
                  RatingDelta(change, size: 18, digits: 1),
                  Text('last 30 days', style: SxType.caption(c.inkMuted, size: 12)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: Sx.s16),
        SkorxBandBar(rating: summary.rating),
        if (!summary.confirmed) ...[
          const SizedBox(height: Sx.s12),
          _Note(
            icon: Icons.hourglass_top_rounded,
            text: 'Still settling: ${summary.verifiedMatches} of ${ArcWeights.provisionalMatches} matches. '
                'Your rating moves faster until SkorX knows your game.',
          ),
        ],
        if (shown.length > 1) ...[
          const SizedBox(height: Sx.s20),
          RatingGraph(values: shown, height: 96, minSpan: 4, label: 'SkorX Rating'),
          const SizedBox(height: Sx.s4),
          Text('Your rating over the last ${shown.length - 1} rated matches',
              style: SxType.caption(c.inkMuted, size: 12)),
        ],
        const SizedBox(height: Sx.s16),
        _FormatRow(summary: summary, points: false),
      ],
    );
  }
}

/// SkorX Points: the Career Score. The total, this month, the level and
/// each format.
class SkorxPointsPanel extends StatelessWidget {
  const SkorxPointsPanel({super.key, required this.summary, this.now});

  final ArcSummary summary;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final earned = summary.pointsEarned(now ?? DateTime.now());
    return Column(
      key: const Key('skorxPoints'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.bottomLeft,
                child: Semantics(
                  label: '${sxpText(summary.points)} SkorX Points',
                  excludeSemantics: true,
                  child: SxpCountUp(value: summary.points, style: SxType.hero(64, c.ink)),
                ),
              ),
            ),
            const SizedBox(width: Sx.s16),
            Padding(
              padding: const EdgeInsets.only(bottom: Sx.s8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RatingDelta(earned, size: 18, digits: 2, unit: ' SXP', what: 'SkorX Points'),
                  Text('earned in 30 days', style: SxType.caption(c.inkMuted, size: 12)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: Sx.s16),
        ArcLevelBar(summary: summary),
        const SizedBox(height: Sx.s16),
        _FormatRow(summary: summary, points: true),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: c.inkMuted),
        const SizedBox(width: Sx.s8),
        Expanded(child: Text(text, style: SxType.caption(c.inkMuted, size: 12.5))),
      ],
    );
  }
}

/// Singles, doubles and mixed side by side: the rating in each, or the
/// points earned in each (which add up to what was earned in these matches).
class _FormatRow extends StatelessWidget {
  const _FormatRow({required this.summary, required this.points});

  final ArcSummary summary;
  final bool points;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Row(
      key: Key(points ? 'pointsFormats' : 'ratingFormats'),
      children: [
        for (final (i, f) in PlayCategory.values.indexed) ...[
          if (i > 0) const SizedBox(width: Sx.s8),
          Expanded(
            child: Builder(builder: (context) {
              final s = summary.formats[f];
              final value = s == null ? '—' : (points ? sxpText(Sxp.shown(s.sxpUnits)) : ratingText(s.spi));
              return Semantics(
                label: s == null ? '${f.label}: not played' : '${f.label}: $value ${points ? 'SkorX Points' : 'rating'}',
                excludeSemantics: true,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: Sx.s12, vertical: Sx.s8),
                  decoration: BoxDecoration(
                    color: c.surfaceAlt,
                    borderRadius: BorderRadius.circular(Sx.radiusLg),
                    border: Border.all(color: c.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(f.label, style: SxType.caption(c.inkMuted, size: 12)),
                      Text(value, style: SxType.number(20, s == null ? c.inkFaint : c.ink, weight: FontWeight.w800)),
                    ],
                  ),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }
}

/// The player's SkorX Points level: its name, the bar to the next level and
/// what is left.
class ArcLevelBar extends StatelessWidget {
  const ArcLevelBar({super.key, required this.summary});

  final ArcSummary summary;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final level = summary.level;
    final next = level.next;
    final progress = level.progress(summary.sxp);
    final caption = next == null
        ? 'The top level. Your career keeps counting.'
        : '${sxpText(next.minSxp - summary.points)} more points to ${next.name} (${sxpText(next.minSxp).replaceAll('.00', '')})';
    return Semantics(
      label: 'Level ${level.number} of ${ArcLevel.all.length}, ${level.name}. $caption',
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
                    Text('Level ${level.number} of ${ArcLevel.all.length} · ${level.tagline}',
                        style: SxType.caption(c.inkMuted, size: 12)),
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

/// Why a match moved the rating, in one plain sentence.
String arcRatingWhy(ArcImpact i) {
  if (!i.trust.movesSkill) return 'Self-reported scores do not change your SkorX Rating.';
  final pct = (i.share * 100).round(), exp = (i.expectedShare * 100).round();
  final moved = i.spiChange >= 0.05
      ? 'went up'
      : i.spiChange <= -0.05
          ? 'went down'
          : 'held steady';
  return 'You won $pct% of the points. Against this opponent SkorX expected $exp%, so your rating $moved.';
}

/// A Career Score counting up to [value] once, ending on "684.75".
class SxpCountUp extends StatelessWidget {
  const SxpCountUp({super.key, required this.value, required this.style, this.from, this.signed = false});

  final double value;

  /// Where the count starts; a little below [value] when null.
  final double? from;
  final TextStyle style;

  /// Show a sign: "+0.55".
  final bool signed;

  @override
  Widget build(BuildContext context) {
    String text(double v) => signed ? sxpDeltaText(v) : sxpText(v);
    if (sxReduceMotion(context)) return Text(text(value), style: style);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: from ?? (value - 5).clamp(0, value).toDouble(), end: value),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (_, v, _) => Text(text(v), style: style),
    );
  }
}

/// What one match added to the Career Score, with the whole sum in view:
/// previous → new, then the actual points, the match type, the conversion,
/// the doubles split and the points earned. Nothing else goes into it.
class SxpUpdate extends StatelessWidget {
  const SxpUpdate({super.key, required this.impact, this.showCareer = true, this.pending = false});

  final ArcImpact impact;

  /// Show previous and new Career Score; off when the player's career is not
  /// known (the other side of a friendly).
  final bool showCareer;

  /// Counts once every player confirms the score.
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final i = impact;
    Widget row(String label, String value, {bool strong = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(child: Text(label, style: SxType.body(strong ? c.ink : c.inkMuted, size: 14))),
              Text(value,
                  style: SxType.number(strong ? 16 : 15, strong ? c.volt : c.ink,
                      weight: strong ? FontWeight.w900 : FontWeight.w700)),
            ],
          ),
        );
    Widget career(String label, String value, {bool strong = false}) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(), style: SxType.label(c.inkMuted, size: 10.5)),
            const SizedBox(height: 2),
            Text(value, style: SxType.number(20, strong ? c.ink : c.inkMuted, weight: FontWeight.w800)),
          ],
        );
    final earned = sxpDeltaText(i.shownGain);
    return Semantics(
      label: [
        'SkorX Score update.',
        if (showCareer) 'Previous ${sxpText(i.shownBefore)}, new ${sxpText(i.shownAfter)}.',
        '${i.pointsScored} points scored, ${i.type.sxpLabel.toLowerCase()} match, divided by ${i.divisor}'
            '${i.playersOnSide > 1 ? ' and shared by ${i.playersOnSide} players' : ''}: $earned SkorX Points.',
      ].join(' '),
      excludeSemantics: true,
      child: Column(
        key: const Key('sxpUpdate'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('SKORX SCORE UPDATE', style: SxType.label(c.volt, size: 11.5)),
          const SizedBox(height: Sx.s8),
          if (showCareer) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: career('Previous', sxpText(i.shownBefore))),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4, right: Sx.s8),
                  child: Text(earned, style: SxType.number(15, c.volt, weight: FontWeight.w800)),
                ),
                Icon(Icons.arrow_forward_rounded, size: 16, color: c.inkFaint),
                const SizedBox(width: Sx.s8),
                Expanded(child: career('New', sxpText(i.shownAfter), strong: true)),
              ],
            ),
            Divider(height: Sx.s20, color: c.line),
          ],
          row('Actual points scored', '${i.pointsScored}'),
          row('Match type', i.type.sxpLabel),
          row('Conversion', '÷${i.divisor}'),
          if (i.playersOnSide > 1) row('Shared by ${i.playersOnSide} players', '÷${i.playersOnSide}'),
          row('SkorX Points earned', earned, strong: true),
          const SizedBox(height: Sx.s4),
          Text(
            !i.credited
                ? '${i.trust.label} scores do not add SkorX Points.'
                : pending
                    ? '${i.formula}. Counts once every player confirms the score.'
                    : '${i.formula}. Only the points you score count.',
            style: SxType.caption(c.inkMuted, size: 12),
          ),
        ],
      ),
    );
  }
}

/// What one match did: the SkorX Rating move and why, then the SkorX Score
/// update.
class ArcBreakdown extends StatelessWidget {
  const ArcBreakdown({super.key, required this.impact});

  final ArcImpact impact;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    Widget heading(String label, Widget trailing) => Row(
          children: [
            Expanded(child: Text(label, style: SxType.heading(c.ink, size: 16))),
            trailing,
          ],
        );
    return Column(
      key: const Key('arcBreakdown'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heading(
          'SkorX Rating',
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(ratingText(impact.spiBefore), style: SxType.number(15, c.inkMuted)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.arrow_forward_rounded, size: 14, color: c.inkFaint),
              ),
              Text(ratingText(impact.spiAfter), style: SxType.number(15, c.ink, weight: FontWeight.w800)),
              const SizedBox(width: Sx.s8),
              RatingDelta(impact.spiChange, size: 14, digits: 1),
            ],
          ),
        ),
        const SizedBox(height: Sx.s4),
        Text(arcRatingWhy(impact), style: SxType.caption(c.inkMuted, size: 12.5)),
        Divider(height: Sx.s24, color: c.line),
        SxpUpdate(impact: impact),
      ],
    );
  }
}

/// A plain-language explanation of SkorX Rating and SkorX Points.
Future<void> showArcExplainer(BuildContext context) => showSxSheet(
      context,
      builder: (context) {
        final c = context.sx;
        Widget para(String title, String body) => Padding(
              padding: const EdgeInsets.only(bottom: Sx.s12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: SxType.heading(c.ink, size: 15)),
                  const SizedBox(height: 2),
                  Text(body, style: SxType.body(c.inkMuted, size: 14)),
                ],
              ),
            );
        Widget compare(String label, String rating, String points) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 72, child: Text(label, style: SxType.caption(c.inkFaint, size: 12))),
                  Expanded(child: Text(rating, style: SxType.body(c.ink, size: 14))),
                  const SizedBox(width: Sx.s8),
                  Expanded(child: Text(points, style: SxType.body(c.ink, size: 14))),
                ],
              ),
            );
        Widget head(String text) => Padding(
              padding: const EdgeInsets.only(top: Sx.s24, bottom: Sx.s8),
              child: Text(text.toUpperCase(), style: SxType.label(c.volt, size: 12)),
            );
        return SingleChildScrollView(
          key: const Key('arcExplainer'),
          padding: const EdgeInsets.fromLTRB(Sx.s20, 0, Sx.s20, Sx.s24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Rating and Points', style: SxType.heading(c.ink, size: 20)),
              const SizedBox(height: Sx.s4),
              Text('SkorX keeps two numbers. They measure different things.', style: SxType.body(c.inkMuted, size: 14)),
              const SizedBox(height: Sx.s16),
              Container(
                padding: const EdgeInsets.all(Sx.s12),
                decoration: BoxDecoration(
                  color: c.surfaceAlt,
                  borderRadius: BorderRadius.circular(Sx.radiusLg),
                  border: Border.all(color: c.line),
                ),
                child: Column(
                  children: [
                    compare('', 'SkorX Rating', 'SkorX Points'),
                    Divider(height: 1, color: c.line),
                    compare('Shows', 'How good you are now', 'Your career: every point you have scored'),
                    compare('Scale', '0 to 100', 'From 0 toward 10,000 and beyond'),
                    compare('Moves', 'Up and down', 'Only up'),
                    compare('Used for', 'Rankings, seeding, fair matches', 'Your level and badges'),
                  ],
                ),
              ),
              head('SkorX Rating'),
              para('Beat what SkorX expected',
                  'Before each match SkorX works out what share of the points you should win against that opponent. '
                      'Win more than that and your rating goes up. Win fewer and it goes down. A close loss to a much '
                      'stronger player can still raise it.'),
              para('Bands',
                  'Beginner under 40 · Intermediate 40–55 · Advanced 55–70 · Pro 70 and above. Everyone starts at '
                      '${ArcWeights.newPlayerSpi.round()}.'),
              para('Your first ${ArcWeights.provisionalMatches} matches',
                  'Your rating moves faster while SkorX learns your game, then settles.'),
              head('SkorX Points'),
              para('The points you score build your career',
                  'Casual match: points scored ÷ ${Sxp.casualDivisor}. Tournament match: points scored ÷ '
                      '${Sxp.tournamentDivisor}. Score 11 in a casual match and you earn 0.55; in a tournament, 1.10.'),
              para('Doubles and mixed',
                  'Your team’s points are converted the same way, then shared equally by the two partners. '
                      '11 points in a casual doubles match is 0.55, or 0.28 each.'),
              para('Nothing hidden',
                  'No bonus for winning, nothing for who you played. Every game of the match counts. '
                      'Walkovers add nothing, and casual matches count once every player confirms the score.'),
              para('Levels',
                  'Your Career Score moves you through ${ArcLevel.all.length} levels, from '
                      '${ArcLevel.all.first.name} to ${ArcLevel.all.last.name} at 10,000. A level shows how far your '
                      'career has come; your SkorX Rating shows how well you play.'),
            ],
          ),
        );
      },
    );
