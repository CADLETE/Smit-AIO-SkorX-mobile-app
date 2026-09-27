import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'tokens.dart';

/// SkorX's loading mark instead of a spinner: a ball bouncing across a short
/// stretch of court, leaving a trail. Still dots under reduced motion.
class BallLoader extends StatefulWidget {
  const BallLoader({super.key, this.color, this.width = 44, this.label = 'Loading'});

  final Color? color;
  final double width;
  final String label;

  @override
  State<BallLoader> createState() => _BallLoaderState();
}

class _BallLoaderState extends State<BallLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (sxReduceMotion(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? context.sx.ink;
    return Semantics(
      label: widget.label,
      liveRegion: true,
      child: SizedBox(
        width: widget.width,
        height: widget.width * 0.42,
        child: CustomPaint(
          painter: _LoaderPainter(_controller, color, still: sxReduceMotion(context)),
        ),
      ),
    );
  }
}

class _LoaderPainter extends CustomPainter {
  _LoaderPainter(this.t, this.color, {required this.still}) : super(repaint: t);

  final Animation<double> t;
  final Color color;
  final bool still;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.height * 0.16;
    final floor = size.height - r;
    if (still) {
      for (var i = 0; i < 3; i++) {
        canvas.drawCircle(Offset(size.width * (0.25 + i * 0.25), floor), r * 0.8, Paint()..color = color.withValues(alpha: 0.35 + i * 0.25));
      }
      return;
    }
    // Two bounces left to right, then back, like a rally.
    Offset at(double v) {
      final forward = v < 0.5;
      final p = forward ? v * 2 : (1 - v) * 2;
      final x = r + (size.width - 2 * r) * Curves.easeInOutSine.transform(p);
      final hop = (p * 2) % 1;
      final y = floor - (size.height - 2 * r) * math.sin(hop * math.pi);
      return Offset(x, y);
    }

    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      Paint()
        ..strokeWidth = 1
        ..color = color.withValues(alpha: 0.18),
    );
    for (var i = 5; i >= 1; i--) {
      final v = (t.value - i * 0.02) % 1;
      canvas.drawCircle(at(v), r * (1 - i * 0.12), Paint()..color = color.withValues(alpha: 0.14 * (1 - i / 6)));
    }
    canvas.drawCircle(at(t.value), r, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_LoaderPainter old) => old.color != color || old.still != still;
}
