import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../features/player/data/player_repository.dart' show Achievement, AchievementTier;
import 'tokens.dart';
import 'type.dart';

/// A number with a tracked label under it.
class Stat extends StatelessWidget {
  const Stat({super.key, required this.value, required this.label, this.size = 32, this.color, this.align = CrossAxisAlignment.start});

  final String value;
  final String label;
  final double size;
  final Color? color;
  final CrossAxisAlignment align;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Semantics(
      label: '$label $value',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: align,
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: SxType.number(size, color ?? c.ink, weight: FontWeight.w800)),
          ),
          const SizedBox(height: 4),
          Text(label.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.label(c.inkMuted, size: 11)),
        ],
      ),
    );
  }
}

/// The rating over time: one line, an end dot, no grid. Draws in once.
class RatingGraph extends StatelessWidget {
  const RatingGraph({super.key, required this.values, this.height = 120});

  final List<int> values;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    if (values.length < 2) return SizedBox(height: height);
    final lo = values.reduce(math.min);
    final hi = values.reduce(math.max);
    return Semantics(
      label: 'Rating graph from ${values.first} to ${values.last}, low $lo, high $hi',
      excludeSemantics: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: sxReduceMotion(context) ? 1 : 0, end: 1),
        duration: const Duration(milliseconds: 1400),
        curve: Curves.easeOutCubic,
        builder: (_, t, _) => CustomPaint(
          size: Size(double.infinity, height),
          painter: _GraphPainter(values, t, c.cyan, c.voltFill, c.line, c.canvas),
        ),
      ),
    );
  }
}

class _GraphPainter extends CustomPainter {
  _GraphPainter(this.values, this.t, this.ink, this.accent, this.line, this.canvasColor);

  final List<int> values;
  final double t;
  final Color ink;
  final Color accent;
  final Color line;
  final Color canvasColor;

  @override
  void paint(Canvas canvas, Size size) {
    final lo = values.reduce(math.min).toDouble();
    final hi = values.reduce(math.max).toDouble();
    final span = math.max(hi - lo, 20);
    const pad = 8.0;
    Offset at(int i) => Offset(
          pad + (size.width - pad * 2) * i / (values.length - 1),
          pad + (size.height - pad * 2) * (1 - (values[i] - lo) / span),
        );

    // Baseline: the starting rating, dashed.
    final y0 = at(0).dy;
    final dash = Paint()
      ..color = line
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, y0), Offset(x + 4, y0), dash);
    }

    final path = Path()..moveTo(at(0).dx, at(0).dy);
    final shown = ((values.length - 1) * t).clamp(0, values.length - 1).toDouble();
    for (var i = 1; i <= shown.floor(); i++) {
      path.lineTo(at(i).dx, at(i).dy);
    }
    Offset end = at(shown.floor());
    if (shown.floor() < values.length - 1) {
      final f = shown - shown.floor();
      final a = at(shown.floor());
      final b = at(shown.floor() + 1);
      end = Offset.lerp(a, b, f)!;
      path.lineTo(end.dx, end.dy);
    }
    // Area under the line: brand cyan fading into the canvas.
    final area = Path.from(path)
      ..lineTo(end.dx, size.height)
      ..lineTo(at(0).dx, size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [ink.withValues(alpha: 0.28), ink.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    // The line: cyan into volt, with a soft glow under it.
    final lineShader = LinearGradient(colors: [ink, accent]).createShader(Offset.zero & size);
    canvas.drawPath(
      path,
      Paint()
        ..shader = lineShader
        ..strokeWidth = 7
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawPath(
      path,
      Paint()
        ..shader = lineShader
        ..strokeWidth = 2.6
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(end, 14, Paint()..color = accent.withValues(alpha: 0.25));
    canvas.drawCircle(end, 6.5, Paint()..color = accent);
    canvas.drawCircle(
        end,
        6.5,
        Paint()
          ..color = canvasColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5);
  }

  @override
  bool shouldRepaint(_GraphPainter old) => old.t != t || old.values != values || old.ink != ink;
}

/// One bar split into wins (volt) and losses (line).
class RecordBar extends StatelessWidget {
  const RecordBar({super.key, required this.wins, required this.losses, this.height = 10});

  final int wins;
  final int losses;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final total = wins + losses;
    return Semantics(
      label: '$wins wins, $losses losses',
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: SizedBox(
          height: height,
          child: total == 0
              ? Container(color: c.surfaceAlt)
              : Row(
                  children: [
                    if (wins > 0) Expanded(flex: wins, child: Container(color: c.voltFill)),
                    if (wins > 0 && losses > 0) SizedBox(width: 2, child: Container(color: c.canvas)),
                    if (losses > 0) Expanded(flex: losses, child: Container(color: c.line)),
                  ],
                ),
        ),
      ),
    );
  }
}

IconData achievementIcon(String key) => switch (key) {
      'ball' => Icons.sports_baseball_rounded,
      'trophy' => Icons.emoji_events_rounded,
      'medal' => Icons.military_tech_rounded,
      'fire' => Icons.local_fire_department_rounded,
      'target' => Icons.track_changes_rounded,
      'bolt' => Icons.bolt_rounded,
      'crown' => Icons.workspace_premium_rounded,
      'rank' => Icons.leaderboard_rounded,
      'star' => Icons.star_rounded,
      _ => Icons.emoji_events_outlined,
    };

/// An achievement coin. Tier is told by the number of rings (1 bronze to
/// 4 elite), so it reads without colour; unlocked coins are ink with a volt
/// centre, locked ones are an outline with a progress arc.
class AchievementCoin extends StatelessWidget {
  const AchievementCoin({super.key, required this.achievement, this.size = 72});

  final Achievement achievement;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final a = achievement;
    final rings = a.tier.index + 1;
    return Semantics(
      label: '${a.title}, ${a.tier.name}, ${a.unlocked ? 'unlocked' : 'locked, ${(a.progress * 100).round()} percent'}',
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _CoinPainter(
            rings: rings,
            unlocked: a.unlocked,
            progress: a.progress,
            ink: c.ink,
            line: c.line,
            fill: c.voltFill,
            surface: c.surface,
          ),
          child: Center(
            child: Icon(
              achievementIcon(a.icon),
              size: size * 0.36,
              color: a.unlocked ? c.onVolt : c.inkFaint,
            ),
          ),
        ),
      ),
    );
  }
}

class _CoinPainter extends CustomPainter {
  _CoinPainter({
    required this.rings,
    required this.unlocked,
    required this.progress,
    required this.ink,
    required this.line,
    required this.fill,
    required this.surface,
  });

  final int rings;
  final bool unlocked;
  final double progress;
  final Color ink;
  final Color line;
  final Color fill;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = unlocked ? ink : line;
    for (var i = 0; i < rings; i++) {
      canvas.drawCircle(c, r - 1 - i * 4, ringPaint);
    }
    final inner = r - 1 - rings * 4 - 2;
    canvas.drawCircle(c, inner, Paint()..color = unlocked ? fill : surface);
    if (!unlocked) {
      canvas.drawCircle(
          c,
          inner,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = line);
      if (progress > 0) {
        canvas.drawArc(
          Rect.fromCircle(center: c, radius: inner),
          -math.pi / 2,
          math.pi * 2 * progress,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round
            ..color = ink,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CoinPainter old) =>
      old.unlocked != unlocked || old.progress != progress || old.ink != ink || old.rings != rings;
}

String tierLabel(AchievementTier t) => switch (t) {
      AchievementTier.bronze => 'Bronze',
      AchievementTier.silver => 'Silver',
      AchievementTier.gold => 'Gold',
      AchievementTier.elite => 'Elite',
    };
