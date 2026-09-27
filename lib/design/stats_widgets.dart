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

/// A SkorX Rating (or Points) line over time: one line, an end dot, no
/// grid. Draws in once. [minSpan] keeps small moves from looking huge.
class RatingGraph extends StatelessWidget {
  const RatingGraph({super.key, required this.values, this.height = 120, this.minSpan = 20, this.label = 'Rating'});

  final List<num> values;
  final double height;
  final double minSpan;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    if (values.length < 2) return SizedBox(height: height);
    final lo = values.fold<num>(values.first, math.min);
    final hi = values.fold<num>(values.first, math.max);
    return Semantics(
      label: '$label graph from ${_t(values.first)} to ${_t(values.last)}, low ${_t(lo)}, high ${_t(hi)}',
      excludeSemantics: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: sxReduceMotion(context) ? 1 : 0, end: 1),
        duration: const Duration(milliseconds: 1400),
        curve: Curves.easeOutCubic,
        builder: (_, t, _) => CustomPaint(
          size: Size(double.infinity, height),
          painter: _GraphPainter(values, minSpan, t, c.cyan, c.voltFill, c.line, c.canvas),
        ),
      ),
    );
  }

  static String _t(num v) => v is int ? '$v' : v.toStringAsFixed(1);
}

class _GraphPainter extends CustomPainter {
  _GraphPainter(this.values, this.minSpan, this.t, this.ink, this.accent, this.line, this.canvasColor);

  final List<num> values;
  final double minSpan;
  final double t;
  final Color ink;
  final Color accent;
  final Color line;
  final Color canvasColor;

  @override
  void paint(Canvas canvas, Size size) {
    final lo = values.fold<num>(values.first, math.min).toDouble();
    final hi = values.fold<num>(values.first, math.max).toDouble();
    final span = math.max(hi - lo, minSpan);
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
      'scoreboard' => Icons.scoreboard_rounded,
      'camera' => Icons.photo_camera_rounded,
      'court' => Icons.stadium_rounded,
      'share' => Icons.ios_share_rounded,
      'handshake' => Icons.handshake_rounded,
      'heart' => Icons.favorite_rounded,
      'calendar' => Icons.event_available_rounded,
      'rocket' => Icons.rocket_launch_rounded,
      'diamond' => Icons.diamond_rounded,
      'flag' => Icons.flag_rounded,
      'comeback' => Icons.trending_up_rounded,
      'shield' => Icons.shield_rounded,
      'clock' => Icons.timer_rounded,
      'sun' => Icons.wb_sunny_rounded,
      'moon' => Icons.nights_stay_rounded,
      'users' => Icons.groups_rounded,
      'whistle' => Icons.sports_rounded,
      'map' => Icons.map_rounded,
      _ => Icons.emoji_events_outlined,
    };

/// The metal of a tier, light to dark, for coins and tier labels. The one
/// place SkorX steps outside its brand colours: players read bronze,
/// silver and gold at a glance. Elite is the SkorX X itself.
List<Color> tierMetal(AchievementTier t) => switch (t) {
      AchievementTier.bronze => const [Color(0xFFF2C39A), Color(0xFFC8844E), Color(0xFF8A5530)],
      AchievementTier.silver => const [Color(0xFFF4F7FB), Color(0xFFB9C4D2), Color(0xFF7D8A9C)],
      AchievementTier.gold => const [Color(0xFFFFF1A8), Color(0xFFF2C94C), Color(0xFFB8860B)],
      AchievementTier.elite => const [Color(0xFFD4F53C), Color(0xFF4DD8F0), Color(0xFF3B6FF0)],
    };

/// An achievement coin. Tier is told by the metal and by the number of rings
/// (1 bronze to 4 elite), so it reads without colour too; locked coins are
/// an outline with a progress arc.
class AchievementCoin extends StatelessWidget {
  const AchievementCoin({super.key, required this.achievement, this.size = 72});

  final Achievement achievement;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final a = achievement;
    final rings = a.tier.index + 1;
    final metal = tierMetal(a.tier);
    return Semantics(
      label: '${a.title}, ${a.tier.name}, ${a.unlocked ? 'unlocked' : 'locked, ${(a.progress * 100).round()} percent'}',
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        decoration: a.unlocked
            ? BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: metal[1].withValues(alpha: 0.4 * c.glow), blurRadius: size * 0.3)],
              )
            : null,
        child: CustomPaint(
          painter: _CoinPainter(
            rings: rings,
            unlocked: a.unlocked,
            progress: a.progress,
            ink: c.ink,
            line: c.line,
            metal: metal,
            surface: c.surface,
          ),
          child: Center(
            child: Icon(
              achievementIcon(a.icon),
              size: size * 0.36,
              color: a.unlocked ? const Color(0xFF14202E) : c.inkFaint,
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
    required this.metal,
    required this.surface,
  });

  final int rings;
  final bool unlocked;
  final double progress;
  final Color ink;
  final Color line;
  final List<Color> metal;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = unlocked ? metal[1] : line;
    for (var i = 0; i < rings; i++) {
      canvas.drawCircle(c, r - 1 - i * 4, ringPaint);
    }
    final inner = r - 1 - rings * 4 - 2;
    final face = Rect.fromCircle(center: c, radius: inner);
    if (unlocked) {
      // A struck coin: light from the top left, a bright rim.
      canvas.drawCircle(
        c,
        inner,
        Paint()..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: metal).createShader(face),
      );
      canvas.drawCircle(
        c,
        inner - 1,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = Colors.white.withValues(alpha: 0.55),
      );
      return;
    }
    canvas.drawCircle(c, inner, Paint()..color = surface);
    canvas.drawCircle(
        c,
        inner,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = line);
    if (progress > 0) {
      canvas.drawArc(
        face,
        -math.pi / 2,
        math.pi * 2 * progress,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = metal[1],
      );
    }
  }

  @override
  bool shouldRepaint(_CoinPainter old) =>
      old.unlocked != unlocked || old.progress != progress || old.ink != ink || old.rings != rings || old.surface != surface;
}

String tierLabel(AchievementTier t) => switch (t) {
      AchievementTier.bronze => 'Bronze',
      AchievementTier.silver => 'Silver',
      AchievementTier.gold => 'Gold',
      AchievementTier.elite => 'Elite',
    };
