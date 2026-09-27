import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../design/design.dart';
import '../../../../sports/core/score_state.dart';
import '../../live/match_analytics.dart';
import '../../local_match.dart';

/// Series colours for the two sides: SkorX blue and the ball's olive-volt,
/// stepped per theme so both pass the colour-vision and contrast checks
/// (validated with the dataviz palette script). Charts always carry a legend
/// and direct labels, so identity never rests on colour alone.
Color chartColor(SxColors c, Side side) => c.isDark
    ? (side == Side.a ? const Color(0xFF2F95DE) : const Color(0xFF8AA11F))
    : (side == Side.a ? const Color(0xFF0EA5E0) : const Color(0xFF9DB52A));

/// Short side name for legends: team name or first names.
String shortSide(LocalMatch match, Side side) =>
    (side == Side.a ? match.details.teamA : match.details.teamB) ??
    match.names(side).map((n) => n.trim().split(' ').first).join(' / ');

class ChartLegend extends StatelessWidget {
  const ChartLegend({super.key, required this.match});

  final LocalMatch match;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Wrap(
      spacing: Sx.s16,
      runSpacing: 4,
      children: [
        for (final side in Side.values)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 14, height: 3, decoration: BoxDecoration(color: chartColor(c, side), borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 6),
              Text(shortSide(match, side), style: SxType.caption(c.inkMuted, size: 12)),
            ],
          ),
      ],
    );
  }
}

// ─── Points per game ─────────────────────────────────────────────────────

/// How each side's score climbed through a game, rally by rally. One game at
/// a time, chosen with the tabs; touch to read any rally. While the match is
/// still on, the game in play is a tab too, and [initialGame] (the one
/// being played, for someone watching) is shown until another is picked.
class PointsProgressChart extends StatefulWidget {
  const PointsProgressChart({super.key, required this.match, required this.analytics, this.initialGame});

  final LocalMatch match;
  final MatchAnalytics analytics;
  final int? initialGame;

  @override
  State<PointsProgressChart> createState() => _PointsProgressChartState();
}

class _PointsProgressChartState extends State<PointsProgressChart> {
  int? _picked;
  int? _selected;

  int get _game => _picked ?? widget.initialGame ?? 1;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final match = widget.match;
    final score = match.isOver ? null : match.score;
    final tabs = [
      for (final g in widget.analytics.games) (g.number, 'G${g.number}  ${g.score.a}–${g.score.b}'),
      if (score != null && widget.analytics.games.isNotEmpty)
        (score.gameNumber, 'G${score.gameNumber}  LIVE ${score.currentGame.a}–${score.currentGame.b}'),
    ];
    final rallies = widget.analytics.game(_game);
    final target = match.rules.pointsToWin;
    final selected = _selected == null || rallies.isEmpty ? null : rallies[_selected!.clamp(0, rallies.length - 1)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (tabs.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: Sx.s12),
            child: Wrap(
              spacing: Sx.s8,
              runSpacing: Sx.s8,
              children: [
                for (final (number, label) in tabs)
                  SxChip(
                    key: Key('chartGame-$number'),
                    label: label,
                    selected: _game == number,
                    onTap: () => setState(() {
                      _picked = number;
                      _selected = null;
                    }),
                  ),
              ],
            ),
          ),
        ChartLegend(match: match),
        const SizedBox(height: Sx.s8),
        SizedBox(
          height: 26,
          child: selected == null
              ? Text('Touch the chart to read any rally', style: SxType.caption(c.inkFaint, size: 12))
              : Text(
                  'Rally ${selected.rallyInGame} · ${shortSide(match, Side.a)} ${selected.after.a} – ${selected.after.b} ${shortSide(match, Side.b)}'
                  '${selected.scored ? '' : ' · side out'}',
                  style: SxType.caption(c.ink, size: 12.5).copyWith(fontWeight: FontWeight.w700),
                ),
        ),
        Semantics(
          label: 'Game $_game points chart. Final ${rallies.isEmpty ? '0 to 0' : '${rallies.last.after.a} to ${rallies.last.after.b}'}',
          excludeSemantics: true,
          child: LayoutBuilder(builder: (context, box) {
            void pick(Offset p) {
              if (rallies.isEmpty) return;
              final x = ((p.dx - _ProgressPainter.left) / (box.maxWidth - _ProgressPainter.left - _ProgressPainter.right))
                  .clamp(0.0, 1.0);
              setState(() => _selected = (x * rallies.length).ceil().clamp(1, rallies.length) - 1);
            }

            return GestureDetector(
              onPanDown: (d) => pick(d.localPosition),
              onPanUpdate: (d) => pick(d.localPosition),
              child: CustomPaint(
                size: Size(box.maxWidth, 190),
                painter: _ProgressPainter(
                  rallies: rallies,
                  target: target,
                  colorA: chartColor(c, Side.a),
                  colorB: chartColor(c, Side.b),
                  grid: c.line,
                  ink: c.inkMuted,
                  strong: c.ink,
                  surface: c.surface,
                  selected: _selected,
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _ProgressPainter extends CustomPainter {
  _ProgressPainter({
    required this.rallies,
    required this.target,
    required this.colorA,
    required this.colorB,
    required this.grid,
    required this.ink,
    required this.strong,
    required this.surface,
    required this.selected,
  });

  static const left = 26.0;
  static const right = 30.0;
  static const top = 8.0;
  static const bottom = 22.0;

  final List<RallyRecord> rallies;
  final int target;
  final Color colorA;
  final Color colorB;
  final Color grid;
  final Color ink;
  final Color strong;
  final Color surface;
  final int? selected;

  void _text(Canvas canvas, String s, Offset at, Color color, {double size = 10.5, bool right = false, bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(fontFamily: SxType.sans, fontSize: size, color: color, fontWeight: bold ? FontWeight.w800 : FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(right ? at.dx - tp.width : at.dx, at.dy - tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(left, top, size.width - right, size.height - bottom);
    final n = math.max(rallies.length, 1);
    final maxY = math.max(target, rallies.fold<int>(0, (m, r) => math.max(m, math.max(r.after.a, r.after.b))));
    double x(int i) => plot.left + plot.width * i / n;
    double y(int v) => plot.bottom - plot.height * v / maxY;

    // Recessive grid: zero, halfway and the target.
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final v in {0, (target / 2).round(), target}) {
      canvas.drawLine(Offset(plot.left, y(v)), Offset(plot.right, y(v)), gridPaint);
      _text(canvas, '$v', Offset(plot.left - 6, y(v)), ink, right: true);
    }
    _text(canvas, 'Rallies →', Offset(plot.right, size.height - 8), ink, right: true, size: 10);

    if (rallies.isEmpty) return;

    Path series(int Function(RallyRecord) of) {
      final p = Path()..moveTo(x(0), y(0));
      var last = 0;
      for (var i = 0; i < rallies.length; i++) {
        final v = of(rallies[i]);
        p.lineTo(x(i + 1), y(last));
        p.lineTo(x(i + 1), y(v));
        last = v;
      }
      return p;
    }

    Paint line(Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(series((r) => r.after.b), line(colorB));
    canvas.drawPath(series((r) => r.after.a), line(colorA));

    // Direct labels: each side's final score at the line end, in ink.
    final last = rallies.last.after;
    final ya = y(last.a), yb = y(last.b);
    final apart = (ya - yb).abs() < 13;
    for (final (side, v, yy, color) in [(Side.a, last.a, ya, colorA), (Side.b, last.b, yb, colorB)]) {
      final nudge = apart ? (side == Side.a ? (last.a >= last.b ? -7.0 : 7.0) : (last.b > last.a ? -7.0 : 7.0)) : 0.0;
      canvas.drawCircle(Offset(plot.right, yy), 4, Paint()..color = surface);
      canvas.drawCircle(Offset(plot.right, yy), 3, Paint()..color = color);
      _text(canvas, '$v', Offset(plot.right + 7, yy + nudge), strong, bold: true, size: 12);
    }

    final s = selected;
    if (s != null && s < rallies.length) {
      final cx = x(s + 1);
      canvas.drawLine(Offset(cx, plot.top), Offset(cx, plot.bottom), Paint()
        ..color = ink
        ..strokeWidth = 1);
      for (final (v, color) in [(rallies[s].after.a, colorA), (rallies[s].after.b, colorB)]) {
        canvas.drawCircle(Offset(cx, y(v)), 5.5, Paint()..color = surface);
        canvas.drawCircle(Offset(cx, y(v)), 4, Paint()..color = color);
      }
    }
  }

  @override
  bool shouldRepaint(_ProgressPainter old) =>
      old.rallies != rallies || old.selected != selected || old.colorA != colorA || old.grid != grid || old.target != target;
}

// ─── Momentum ────────────────────────────────────────────────────────────

/// Who was ahead, and by how much, after every rally of the match. Bars
/// above the line: side A leads; below: side B. Games are separated.
class MomentumChart extends StatefulWidget {
  const MomentumChart({super.key, required this.match, required this.analytics});

  final LocalMatch match;
  final MatchAnalytics analytics;

  @override
  State<MomentumChart> createState() => _MomentumChartState();
}

class _MomentumChartState extends State<MomentumChart> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final rallies = widget.analytics.rallies;
    final match = widget.match;
    final s = _selected == null || rallies.isEmpty ? null : rallies[_selected!.clamp(0, rallies.length - 1)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChartLegend(match: match),
        const SizedBox(height: Sx.s8),
        SizedBox(
          height: 26,
          child: s == null
              ? Text('Above the line ${shortSide(match, Side.a)} lead, below ${shortSide(match, Side.b)}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.caption(c.inkFaint, size: 12))
              : Text(
                  'Game ${s.game}, rally ${s.rallyInGame} · ${s.after.a}–${s.after.b}'
                  '${s.after.a == s.after.b ? ' · level' : ' · ${shortSide(match, s.after.a > s.after.b ? Side.a : Side.b)} +${(s.after.a - s.after.b).abs()}'}',
                  style: SxType.caption(c.ink, size: 12.5).copyWith(fontWeight: FontWeight.w700),
                ),
        ),
        Semantics(
          label: 'Momentum chart: lead after each rally, ${widget.analytics.leadChanges} lead changes',
          excludeSemantics: true,
          child: LayoutBuilder(builder: (context, box) {
            void pick(Offset p) {
              if (rallies.isEmpty) return;
              final x = (p.dx / box.maxWidth).clamp(0.0, 0.9999);
              setState(() => _selected = (x * rallies.length).floor());
            }

            return GestureDetector(
              onPanDown: (d) => pick(d.localPosition),
              onPanUpdate: (d) => pick(d.localPosition),
              child: CustomPaint(
                size: Size(box.maxWidth, 150),
                painter: _MomentumPainter(
                  rallies: rallies,
                  colorA: chartColor(c, Side.a),
                  colorB: chartColor(c, Side.b),
                  zero: c.inkFaint,
                  ink: c.inkMuted,
                  selected: _selected,
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _MomentumPainter extends CustomPainter {
  _MomentumPainter({
    required this.rallies,
    required this.colorA,
    required this.colorB,
    required this.zero,
    required this.ink,
    required this.selected,
  });

  final List<RallyRecord> rallies;
  final Color colorA;
  final Color colorB;
  final Color zero;
  final Color ink;
  final int? selected;

  @override
  void paint(Canvas canvas, Size size) {
    const labelH = 16.0;
    final plot = Rect.fromLTRB(0, labelH, size.width, size.height);
    final mid = plot.center.dy;
    if (rallies.isEmpty) return;
    final maxLead = math.max(3, rallies.fold<int>(0, (m, r) => math.max(m, (r.after.a - r.after.b).abs())));
    final slot = plot.width / rallies.length;
    final gap = slot > 5 ? 2.0 : (slot > 3 ? 1.0 : 0.0);
    final half = plot.height / 2 - 2;

    for (var i = 0; i < rallies.length; i++) {
      final r = rallies[i];
      final lead = r.after.a - r.after.b;
      if (r.rallyInGame == 1 && r.game > 1) {
        final gx = plot.left + slot * i;
        final dash = Paint()
          ..color = ink.withValues(alpha: 0.6)
          ..strokeWidth = 1;
        for (var yy = plot.top; yy < plot.bottom; yy += 6) {
          canvas.drawLine(Offset(gx, yy), Offset(gx, math.min(yy + 3, plot.bottom)), dash);
        }
        final tp = TextPainter(
          text: TextSpan(text: 'G${r.game}', style: TextStyle(fontFamily: SxType.sans, fontSize: 10, color: ink, fontWeight: FontWeight.w700)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(gx + 3, 0));
      }
      if (lead == 0) continue;
      final h = half * lead.abs() / maxLead;
      final left = plot.left + slot * i + gap / 2;
      final w = math.max(slot - gap, 1.0);
      final rect = lead > 0 ? Rect.fromLTWH(left, mid - h, w, h) : Rect.fromLTWH(left, mid, w, h);
      final radius = Radius.circular(math.min(4, w / 2));
      final rr = lead > 0
          ? RRect.fromRectAndCorners(rect, topLeft: radius, topRight: radius)
          : RRect.fromRectAndCorners(rect, bottomLeft: radius, bottomRight: radius);
      final dim = selected != null && selected != i;
      canvas.drawRRect(rr, Paint()..color = (lead > 0 ? colorA : colorB).withValues(alpha: dim ? 0.45 : 1));
    }
    canvas.drawLine(Offset(plot.left, mid), Offset(plot.right, mid), Paint()
      ..color = zero
      ..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(_MomentumPainter old) => old.rallies != rallies || old.selected != selected || old.colorA != colorA;
}

// ─── Head to head ────────────────────────────────────────────────────────

/// One stat for both sides: numbers in ink, a split bar in the sides' colours.
class VersusRow extends StatelessWidget {
  const VersusRow({super.key, required this.label, required this.a, required this.b, this.valueA, this.valueB});

  final String label;
  final num a;
  final num b;

  /// Shown instead of the raw numbers, e.g. "9/14".
  final String? valueA;
  final String? valueB;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final total = a + b;
    final share = total == 0 ? 0.5 : a / total;
    final aWins = a > b, bWins = b > a;
    TextStyle num0(bool win) => SxType.number(20, win ? c.ink : c.inkMuted, weight: win ? FontWeight.w800 : FontWeight.w600);
    return Semantics(
      label: '$label: ${valueA ?? a} to ${valueB ?? b}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Column(
          children: [
            Row(
              children: [
                SizedBox(width: 56, child: Text(valueA ?? '$a', style: num0(aWins))),
                Expanded(child: Text(label, textAlign: TextAlign.center, style: SxType.caption(c.inkMuted, size: 12.5))),
                SizedBox(width: 56, child: Text(valueB ?? '$b', textAlign: TextAlign.right, style: num0(bWins))),
              ],
            ),
            const SizedBox(height: 5),
            LayoutBuilder(builder: (context, box) {
              final w = box.maxWidth - 2;
              return Row(
                children: [
                  Container(
                    width: w * share,
                    height: 6,
                    decoration: BoxDecoration(
                      color: chartColor(c, Side.a),
                      borderRadius: const BorderRadius.horizontal(left: Radius.circular(3)),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Container(
                    width: w * (1 - share),
                    height: 6,
                    decoration: BoxDecoration(
                      color: chartColor(c, Side.b),
                      borderRadius: const BorderRadius.horizontal(right: Radius.circular(3)),
                    ),
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }
}
