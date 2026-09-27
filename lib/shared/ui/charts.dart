import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/typography.dart';
import 'components.dart';

/// Rating over time: a line that draws itself in, a soft fill, the latest
/// point marked, and the range written at the edges.
class RatingChart extends StatelessWidget {
  const RatingChart({super.key, required this.values, this.height = 140, this.labels = const []});

  final List<double> values;
  final double height;

  /// Evenly spaced captions under the chart, e.g. month names.
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    if (values.length < 2) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text('Your chart starts after two rated matches', style: TextStyle(color: colors.textMuted)),
        ),
      );
    }
    final low = values.reduce(math.min).round();
    final high = values.reduce(math.max).round();
    return Semantics(
      label: 'Rating chart from ${values.first.round()} to ${values.last.round()}, low $low, high $high',
      excludeSemantics: true,
      child: Column(
        children: [
          SizedBox(
            height: height,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: reduceMotion(context) ? 1 : 0, end: 1),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (_, t, _) => CustomPaint(
                size: Size.infinite,
                painter: _LinePainter(
                  values: values,
                  progress: t,
                  line: colors.lime,
                  fill: colors.lime,
                  grid: colors.border,
                  dotRing: colors.background,
                  labelColor: colors.textMuted,
                  showRange: true,
                ),
              ),
            ),
          ),
          if (labels.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final l in labels) Text(l.toUpperCase(), style: SkorxType.label(color: colors.textMuted, size: 10)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A tiny trend line, e.g. beside the rating on Home.
class Sparkline extends StatelessWidget {
  const Sparkline({super.key, required this.values, this.width = 96, this.height = 36, this.color});

  final List<double> values;
  final double width;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    if (values.length < 2) return SizedBox(width: width, height: height);
    return ExcludeSemantics(
      child: SizedBox(
        width: width,
        height: height,
        child: CustomPaint(
          painter: _LinePainter(
            values: values,
            progress: 1,
            line: color ?? colors.lime,
            fill: color ?? colors.lime,
            grid: Colors.transparent,
            dotRing: colors.surface,
            labelColor: Colors.transparent,
            showRange: false,
            strokeWidth: 2,
          ),
        ),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.values,
    required this.progress,
    required this.line,
    required this.fill,
    required this.grid,
    required this.dotRing,
    required this.labelColor,
    required this.showRange,
    this.strokeWidth = 2.5,
  });

  final List<double> values;
  final double progress;
  final Color line;
  final Color fill;
  final Color grid;
  final Color dotRing;
  final Color labelColor;
  final bool showRange;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final low = values.reduce(math.min);
    final high = values.reduce(math.max);
    final span = (high - low).abs() < 1 ? 1.0 : high - low;
    const topPad = 10.0;
    final bottomPad = showRange ? 6.0 : 4.0;
    final rightPad = showRange ? 40.0 : 5.0;
    final w = size.width - rightPad;
    final h = size.height - topPad - bottomPad;

    Offset at(int i) => Offset(
          w * i / (values.length - 1),
          topPad + h - h * (values[i] - low) / span,
        );

    if (showRange) {
      final gridPaint = Paint()
        ..color = grid
        ..strokeWidth = 1;
      for (final y in [topPad, topPad + h / 2, topPad + h]) {
        _dashed(canvas, Offset(0, y), Offset(w, y), gridPaint);
      }
      _label(canvas, '${high.round()}', Offset(w + 6, topPad - 7));
      _label(canvas, '${low.round()}', Offset(w + 6, topPad + h - 7));
    }

    // Smooth curve through the points.
    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      final p0 = at(i - 1);
      final p1 = at(i);
      final mid = (p0.dx + p1.dx) / 2;
      path.cubicTo(mid, p0.dy, mid, p1.dy, p1.dx, p1.dy);
    }

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, w * progress + strokeWidth, size.height));
    final area = Path.from(path)
      ..lineTo(at(values.length - 1).dx, topPad + h)
      ..lineTo(0, topPad + h)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [fill.withValues(alpha: 0.28), fill.withValues(alpha: 0)],
        ).createShader(Rect.fromLTWH(0, topPad, w, h)),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();

    if (progress >= 0.98) {
      final last = at(values.length - 1);
      canvas.drawCircle(last, strokeWidth * 2.6, Paint()..color = line.withValues(alpha: 0.25));
      canvas.drawCircle(last, strokeWidth * 1.7, Paint()..color = dotRing);
      canvas.drawCircle(last, strokeWidth * 1.1, Paint()..color = line);
    }
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 4.0;
    var x = a.dx;
    while (x < b.dx) {
      canvas.drawLine(Offset(x, a.dy), Offset(math.min(x + dash, b.dx), a.dy), paint);
      x += dash * 2;
    }
  }

  void _label(Canvas canvas, String text, Offset at) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: SkorxType.score(12, color: labelColor)),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.progress != progress || old.values != values || old.line != line || old.grid != grid;
}

/// Win rate as a ring with the percentage inside.
class WinRing extends StatelessWidget {
  const WinRing({super.key, required this.percent, this.size = 88, this.label = 'WIN RATE'});

  /// 0–100, or null before the first match.
  final int? percent;
  final double size;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    final value = (percent ?? 0) / 100;
    return Semantics(
      label: '$label ${percent == null ? 'not yet' : '$percent percent'}',
      excludeSemantics: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: reduceMotion(context) ? value : 0, end: value),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (_, t, _) => SizedBox.square(
          dimension: size,
          child: CustomPaint(
            painter: _RingPainter(progress: t, track: colors.surfaceInteractive, fill: colors.success),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(percent == null ? '–' : '${(t * 100).round()}%', style: SkorxType.score(size * 0.26)),
                  Text(label, style: SkorxType.label(color: colors.textMuted, size: size * 0.1)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.progress, required this.track, required this.fill});

  final double progress;
  final Color track;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.09;
    final rect = Offset(stroke / 2, stroke / 2) & Size(size.width - stroke, size.height - stroke);
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      Paint()
        ..color = fill
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress || old.fill != fill || old.track != track;
}
