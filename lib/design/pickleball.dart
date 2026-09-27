import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// The one way SkorX draws a pickleball, everywhere in the app.
///
/// Modelled on an outdoor ball: 40 round holes spread evenly over the
/// sphere (as on 40-hole tournament balls), not a flat pattern. Each hole is
/// placed in 3D, so as the ball turns the holes move across it and narrow
/// into ellipses towards the rim, and the ones round the back are hidden.
/// Light comes from the upper left.
abstract final class Pickleball {
  static const holeCount = 40;

  /// Angular radius of a hole, in radians (about 0.11 of the ball radius).
  static const _holeAngle = 0.115;

  /// Hole centres on the unit sphere: a Fibonacci lattice, which spaces 40
  /// points almost exactly evenly, like a moulded ball.
  static final List<(double, double, double)> _holes = () {
    final golden = math.pi * (3 - math.sqrt(5));
    return [
      for (var i = 0; i < holeCount; i++)
        () {
          final y = 1 - (i + 0.5) / holeCount * 2;
          final ring = math.sqrt(1 - y * y);
          final theta = golden * i;
          return (math.cos(theta) * ring, y, math.sin(theta) * ring);
        }(),
    ];
  }();

  /// Draws a ball of radius [r] at [center].
  ///
  /// [spin] turns the ball about its vertical axis and [tilt] tips it
  /// towards the viewer, both in radians; animate [spin] for a rolling ball.
  static void paint(
    Canvas canvas,
    Offset center,
    double r, {
    required Color color,
    Color hole = const Color(0xFF243A4F),
    double spin = 0,
    double tilt = 0.35,
    bool shade = true,
    double glow = 0,
  }) {
    if (r <= 0) return;
    final rect = Rect.fromCircle(center: center, radius: r);

    if (glow > 0) {
      canvas.drawCircle(
        center,
        r * 1.25,
        Paint()
          ..color = color.withValues(alpha: 0.35 * glow)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.45),
      );
    }

    canvas.save();
    canvas.clipPath(Path()..addOval(rect));

    // Body.
    canvas.drawCircle(center, r, Paint()..color = color);

    // Holes, back to front so rim holes sit under nearer ones.
    final sinS = math.sin(spin), cosS = math.cos(spin);
    final sinT = math.sin(tilt), cosT = math.cos(tilt);
    final visible = <(double, double, double)>[];
    for (final (x0, y0, z0) in _holes) {
      // Spin about the vertical axis, then tilt about the horizontal one.
      final x1 = x0 * cosS + z0 * sinS;
      final z1 = -x0 * sinS + z0 * cosS;
      final y2 = y0 * cosT - z1 * sinT;
      final z2 = y0 * sinT + z1 * cosT;
      if (z2 > -0.05) visible.add((x1, y2, z2));
    }
    visible.sort((a, b) => a.$3.compareTo(b.$3));

    final holeR = r * math.sin(_holeAngle);
    final inner = Color.lerp(hole, Colors.black, 0.15)!;
    for (final (x, y, z) in visible) {
      // Seen at an angle, a round hole is an ellipse: full width along the
      // rim, narrowed by how far it faces away from us.
      final facing = z.clamp(0.0, 1.0);
      final p = center + Offset(x * r, -y * r);
      final radial = math.atan2(-y, x);
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(radial);
      final oval = Rect.fromCenter(center: Offset.zero, width: holeR * 2 * math.max(facing, 0.08), height: holeR * 2);
      canvas.drawOval(oval, Paint()..color = inner.withValues(alpha: inner.a * (0.55 + 0.45 * facing)));
      // The far wall inside the hole catches a little light.
      if (facing > 0.35) {
        canvas.drawOval(
          oval.deflate(holeR * 0.28).shift(Offset(holeR * 0.18 * facing, 0)),
          Paint()..color = Color.lerp(inner, color, 0.28)!.withValues(alpha: inner.a * 0.6),
        );
      }
      canvas.restore();
    }

    if (shade) {
      // Round the sphere off: light upper left, shadow lower right.
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..shader = ui.Gradient.radial(
            center + Offset(-r * 0.35, -r * 0.4),
            r * 1.55,
            [
              Colors.white.withValues(alpha: 0.28),
              Colors.white.withValues(alpha: 0.0),
              Colors.black.withValues(alpha: 0.0),
              Colors.black.withValues(alpha: 0.38),
            ],
            const [0.0, 0.35, 0.6, 1.0],
          ),
      );
      // A soft highlight.
      canvas.drawOval(
        Rect.fromCenter(center: center + Offset(-r * 0.38, -r * 0.45), width: r * 0.5, height: r * 0.32),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.35)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.12),
      );
    }
    canvas.restore();

    // A thin dark edge so a solid ball reads on light backgrounds too.
    if (!shade) return;
    canvas.drawCircle(
      center,
      r - 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, r * 0.03)
        ..color = Colors.black.withValues(alpha: 0.18),
    );
  }
}
