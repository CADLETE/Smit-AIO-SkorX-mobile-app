import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/typography.dart';
import '../../../design/ball_loader.dart';
import '../../../design/pickleball.dart';

export '../../../design/ball_loader.dart';

/// Becomes true when the launch animation has finished (or was skipped), so
/// screens underneath it hold their entrance until they can be seen.
final launchIntroDoneProvider = NotifierProvider<LaunchIntroDone, bool>(LaunchIntroDone.new);

class LaunchIntroDone extends Notifier<bool> {
  @override
  bool build() => false;

  void finish() => state = true;
}

/// The building blocks of the first-launch journey (splash, introduction,
/// sign-in, profile setup), so every screen shares one look and one motion
/// language: court lines that draw themselves, a ball on a natural arc,
/// content that rises into place, and a scoreboard feel for numbers.

// ─── Colour ──────────────────────────────────────────────────────────────

/// Onboarding colours. Dark is a deep court at night lit in SkorX blue;
/// light is bright daylight with navy type. Neon lime is the ball and one
/// accent word per screen, never a surface.
class OnboardPalette {
  const OnboardPalette._({
    required this.isDark,
    required this.canvas,
    required this.glow,
    required this.ink,
    required this.inkMuted,
    required this.inkFaint,
    required this.court,
    required this.accent,
    required this.accentText,
    required this.ball,
    required this.ballShade,
    required this.ballInk,
    required this.glass,
    required this.glassBorder,
    required this.primaryFill,
    required this.onPrimary,
    required this.error,
  });

  final bool isDark;
  final Color canvas;

  /// The soft light behind the court.
  final Color glow;
  final Color ink;
  final Color inkMuted;
  final Color inkFaint;

  /// Court lines.
  final Color court;

  /// SkorX blue: focus rings, active steps, links.
  final Color accent;

  /// Lime that reads as text on [canvas].
  final Color accentText;
  final Color ball;
  final Color ballShade;
  final Color ballInk;

  /// Translucent panels over the backdrop.
  final Color glass;
  final Color glassBorder;
  final Color primaryFill;
  final Color onPrimary;
  final Color error;

  static const dark = OnboardPalette._(
    isDark: true,
    canvas: Color(0xFF060A10),
    glow: Color(0xFF0F2A4A),
    ink: Color(0xFFF2F5F9),
    inkMuted: Color(0xFF8B96A5),
    inkFaint: Color(0xFF4A5566),
    court: Color(0xFF4DD8F0),
    accent: Color(0xFF3BA0F0),
    accentText: Color(0xFFD7F062),
    ball: Color(0xFFCFE524),
    ballShade: Color(0xFF9DB524),
    ballInk: Color(0xFF243A4F),
    glass: Color(0x0FFFFFFF),
    glassBorder: Color(0x1FFFFFFF),
    primaryFill: Color(0xFFD4F53C),
    onPrimary: Color(0xFF0E1013),
    error: Color(0xFFFB7185),
  );

  static const light = OnboardPalette._(
    isDark: false,
    canvas: Color(0xFFF4F7FB),
    glow: Color(0xFFD9E8FA),
    ink: Color(0xFF0B1C33),
    inkMuted: Color(0xFF5B6778),
    inkFaint: Color(0xFFA3AEBC),
    court: Color(0xFF1E7FE0),
    accent: Color(0xFF1E7FE0),
    accentText: Color(0xFF5B7A00),
    ball: Color(0xFFC7EA3A),
    ballShade: Color(0xFF9DB524),
    ballInk: Color(0xFF0B1C33),
    glass: Color(0xB3FFFFFF),
    glassBorder: Color(0xFFDDE4EC),
    primaryFill: Color(0xFF0B1C33),
    onPrimary: Color(0xFFFFFFFF),
    error: Color(0xFFE11D48),
  );

  static OnboardPalette of(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? dark : light;
}

bool reduceMotion(BuildContext context) => MediaQuery.disableAnimationsOf(context);

// ─── Type ────────────────────────────────────────────────────────────────

abstract final class OnboardType {
  /// The one big statement on a screen. Scales with the phone so a line
  /// like "WHAT SHOULD WE CALL YOU?" fits a 360-wide screen in two lines.
  static TextStyle statement(BuildContext context, Color color, {double max = 52}) {
    final width = MediaQuery.sizeOf(context).width;
    return SkorxType.headline(math.min(max, math.max(34, width * 0.118)), color: color).copyWith(height: 0.95);
  }

  /// Small tracked caps above a statement: "STEP 2 OF 5", "SKORX TMS".
  static TextStyle eyebrow(Color color) => SkorxType.label(color: color, size: 13).copyWith(letterSpacing: 2.4);

  static TextStyle body(Color color) => TextStyle(fontSize: 16, height: 1.45, color: color);

  static TextStyle button(Color color) =>
      TextStyle(fontFamily: SkorxType.family, fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: 1.6, color: color);
}

// ─── Page transition ─────────────────────────────────────────────────────

/// Fade through with a slight rise and scale: calm enough to repeat on every
/// step, quick enough (320 ms) never to feel like waiting.
CustomTransitionPage<void> onboardPage(GoRouterState state, Widget child) => CustomTransitionPage<void>(
      key: state.pageKey,
      child: StartDark(child: child),
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      transitionsBuilder: (context, animation, secondary, child) {
        final t = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
        return FadeTransition(
          opacity: t,
          child: ScaleTransition(
            scale: Tween(begin: 0.97, end: 1.0).animate(t),
            child: SlideTransition(
              position: Tween(begin: const Offset(0, 0.025), end: Offset.zero).animate(t),
              child: child,
            ),
          ),
        );
      },
    );

/// The starting screens (welcome, sign-in, verify, profile setup) are
/// always in the dark SkorX look, whatever the app theme, so launch reads
/// as one piece with the dark native splash and intro.
class StartDark extends StatelessWidget {
  const StartDark({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).extension<SkorxThemeExtension>()?.accent ?? WorkspaceAccent.player;
    return Theme(data: buildSkorxTheme(brightness: Brightness.dark, accent: accent), child: child);
  }
}

// ─── Backdrop: court + ball ──────────────────────────────────────────────

/// The shared background: a perspective pickleball court whose lines draw
/// themselves in, a soft light behind it, and (optionally) a ball that lobs
/// across now and then. Kept faint so text over it always reads.
class CourtBackdrop extends StatefulWidget {
  const CourtBackdrop({
    super.key,
    this.courtTop = 0.58,
    this.strength = 1,
    this.ball = true,
    this.child,
  });

  /// Where the far baseline sits, as a fraction of the height.
  final double courtTop;

  /// 0..1: how visible the court and light are.
  final double strength;
  final bool ball;
  final Widget? child;

  @override
  State<CourtBackdrop> createState() => _CourtBackdropState();
}

class _CourtBackdropState extends State<CourtBackdrop> with TickerProviderStateMixin {
  late final AnimationController _draw = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(milliseconds: 4400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _draw.value = 1;
      _loop.stop();
    } else {
      if (!_draw.isAnimating && _draw.value == 0) _draw.forward();
      if (widget.ball && !_loop.isAnimating) _loop.repeat();
    }
  }

  @override
  void dispose() {
    _draw.dispose();
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = OnboardPalette.of(context);
    return ColoredBox(
      color: palette.canvas,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: CustomPaint(
              painter: _CourtPainter(
                palette: palette,
                draw: _draw,
                loop: _loop,
                courtTop: widget.courtTop,
                strength: widget.strength,
                ball: widget.ball && !reduceMotion(context),
              ),
            ),
          ),
          ?widget.child,
        ],
      ),
    );
  }
}

class _CourtPainter extends CustomPainter {
  _CourtPainter({
    required this.palette,
    required this.draw,
    required this.loop,
    required this.courtTop,
    required this.strength,
    required this.ball,
  }) : super(repaint: Listenable.merge([draw, loop]));

  final OnboardPalette palette;
  final Animation<double> draw;
  final Animation<double> loop;
  final double courtTop;
  final double strength;
  final bool ball;

  @override
  void paint(Canvas canvas, Size size) {
    final glowCenter = Offset(size.width * 0.5, size.height * (courtTop + 0.12));
    final glowRadius = size.longestSide * 0.62;
    canvas.drawCircle(
      glowCenter,
      glowRadius,
      Paint()
        ..shader = ui.Gradient.radial(glowCenter, glowRadius, [
          palette.glow.withValues(alpha: (palette.isDark ? 0.95 : 0.9) * strength),
          palette.canvas.withValues(alpha: 0),
        ]),
    );

    final d = Curves.easeInOutCubic.transform(draw.value);
    if (d > 0) paintCourt(canvas, size, top: size.height * courtTop, draw: d, color: palette.court, alpha: strength);
    if (ball) _paintBall(canvas, size);
  }

  /// The ball lobs from one side to the other once per loop, then rests.
  /// A rally straight up and down the court, the way you see it standing
  /// behind the baseline: your paddle hits the ball away up the phone, it
  /// taps down in the far court, the far paddle sends it back, it taps down
  /// in front of you, and you hit it again. The loop has no gaps; the ball
  /// shrinks with distance and throws a shadow on the court.
  void _paintBall(Canvas canvas, Size size) {
    final court = CourtGeometry(size, top: size.height * courtTop);
    final v = loop.value;
    final flight = _Rally.at(v);
    final ground = court.point(flight.depth, flight.side);
    final scale = court.scale(flight.depth);
    final lift = flight.height * size.height * 0.5 * scale;
    final ball = ground - Offset(0, lift + 9 * scale);

    // Taps on the court: a ring spreading from where the ball lands.
    for (final bounce in _Rally.bounces) {
      final k = (v - bounce.at) / 0.12;
      if (k < 0 || k > 1) continue;
      final spot = court.point(bounce.depth, bounce.side);
      final sc = court.scale(bounce.depth);
      canvas.drawOval(
        Rect.fromCenter(center: spot, width: (10 + 40 * k) * sc, height: (3 + 12 * k) * sc),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = palette.ball.withValues(alpha: 0.55 * (1 - k) * strength),
      );
    }

    // Shadow: smaller and fainter the higher the ball.
    final shadowK = (1 - lift / (size.height * 0.2)).clamp(0.25, 1.0);
    canvas.drawOval(
      Rect.fromCenter(center: ground, width: 16 * scale * shadowK, height: 5 * scale * shadowK),
      Paint()
        ..color = Colors.black.withValues(alpha: (palette.isDark ? 0.55 : 0.2) * shadowK * strength)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );

    // The paddles, each seen only around its own hit.
    for (final hit in _Rally.hits) {
      // Nearest way round the loop, so the near hit at 0 also shows at 0.95.
      var delta = v - hit.at;
      if (delta > 0.5) delta -= 1;
      if (delta < -0.5) delta += 1;
      final k = delta / 0.16;
      if (k < -1 || k > 1) continue;
      final spot = court.point(hit.depth, hit.side);
      final sc = court.scale(hit.depth);
      final contact = spot - Offset(0, hit.height * size.height * 0.5 * sc + 9 * sc);
      final show = (1 - k.abs()).clamp(0.0, 1.0);
      paintPaddle(
        canvas,
        contact + Offset(14 * sc * hit.hand, 10 * sc),
        length: 64 * sc,
        // Wind up, strike, follow through.
        angle: hit.hand * (0.35 - 0.9 * Curves.easeInOutCubic.transform((k + 1) / 2)),
        alpha: Curves.easeOut.transform(show) * strength,
        palette: palette,
      );
    }

    // Trail.
    for (var i = 5; i >= 1; i--) {
      final g = _Rally.at((v - i * 0.012) % 1);
      final p = court.point(g.depth, g.side);
      final sc = court.scale(g.depth);
      final tail = p - Offset(0, g.height * size.height * 0.5 * sc + 9 * sc);
      canvas.drawCircle(tail, 8 * sc * (1 - i * 0.1), Paint()..color = palette.ball.withValues(alpha: 0.12 * (1 - i / 6) * strength));
    }

    canvas.save();
    canvas.translate(ball.dx, ball.dy);
    // A quick squash as it taps the court.
    final squash = flight.height < 0.015 ? 0.18 : 0.0;
    canvas.scale(1 + squash, 1 - squash);
    canvas.saveLayer(null, Paint()..color = Colors.white.withValues(alpha: strength));
    paintPickleball(canvas, 9 * scale, palette: palette, spin: v * 40, glow: palette.isDark);
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CourtPainter old) =>
      old.palette != palette || old.courtTop != courtTop || old.strength != strength || old.ball != ball;
}

/// The rally [CourtBackdrop] plays, as a loop from 0 to 1. Depth 0 is the
/// far baseline, 0.5 the net, 1 the near baseline; side -1..1 is sideline
/// to sideline, kept close to the middle so the ball travels up and down the
/// phone. Height is above the court, in court units.
abstract final class _Rally {
  /// Each leg: (start, end, depth, side and height at both ends, peak).
  static const _legs = [
    // Near hit, over the net, down in the far court.
    (t0: 0.00, t1: 0.36, d0: 0.9, d1: 0.2, s0: 0.06, s1: -0.04, h0: 0.06, h1: 0.0, peak: 0.36),
    // Bounce up to the far player.
    (t0: 0.36, t1: 0.46, d0: 0.2, d1: 0.08, s0: -0.04, s1: -0.06, h0: 0.0, h1: 0.07, peak: 0.08),
    // Far hit, back over the net, down in front of you.
    (t0: 0.46, t1: 0.82, d0: 0.08, d1: 0.72, s0: -0.06, s1: 0.03, h0: 0.07, h1: 0.0, peak: 0.34),
    // Bounce up to your paddle.
    (t0: 0.82, t1: 1.00, d0: 0.72, d1: 0.9, s0: 0.03, s1: 0.06, h0: 0.0, h1: 0.06, peak: 0.1),
  ];

  static const bounces = [(at: 0.36, depth: 0.2, side: -0.04), (at: 0.82, depth: 0.72, side: 0.03)];

  /// hand: 1 swings from the right (forehand), -1 from the left.
  static const hits = [
    (at: 0.0, depth: 0.9, side: 0.06, height: 0.06, hand: 1.0),
    (at: 0.46, depth: 0.08, side: -0.06, height: 0.07, hand: -1.0),
  ];

  static ({double depth, double side, double height}) at(double v) {
    final leg = _legs.lastWhere((l) => v >= l.t0, orElse: () => _legs.first);
    final f = ((v - leg.t0) / (leg.t1 - leg.t0)).clamp(0.0, 1.0);
    return (
      depth: leg.d0 + (leg.d1 - leg.d0) * f,
      side: leg.s0 + (leg.s1 - leg.s0) * f,
      height: leg.h0 + (leg.h1 - leg.h0) * f + math.sin(f * math.pi) * leg.peak,
    );
  }
}

/// A pickleball paddle: a rounded face with an edge guard and a wrapped
/// grip. [at] is the middle of the face; [angle] turns it about the grip.
void paintPaddle(
  Canvas canvas,
  Offset at, {
  required double length,
  required double angle,
  required OnboardPalette palette,
  double alpha = 1,
}) {
  if (alpha <= 0 || length <= 0) return;
  final faceH = length * 0.66;
  final faceW = length * 0.48;
  final gripH = length * 0.34;
  final gripW = length * 0.12;
  canvas.save();
  canvas.translate(at.dx, at.dy);
  canvas.rotate(angle);
  canvas.saveLayer(null, Paint()..color = Colors.white.withValues(alpha: alpha));

  // Grip, below the face.
  final grip = RRect.fromRectAndRadius(
    Rect.fromLTWH(-gripW / 2, faceH * 0.46, gripW, gripH),
    Radius.circular(gripW * 0.4),
  );
  canvas.drawRRect(grip, Paint()..color = const Color(0xFF151A22));
  final wrap = Paint()
    ..color = Colors.white.withValues(alpha: 0.12)
    ..strokeWidth = math.max(0.8, length * 0.012);
  for (var i = 1; i < 6; i++) {
    final y = grip.top + gripH * i / 6;
    canvas.drawLine(Offset(-gripW / 2, y), Offset(gripW / 2, y - gripW * 0.5), wrap);
  }

  // Face: carbon grey, lit from the upper left.
  final face = RRect.fromRectAndCorners(
    Rect.fromCenter(center: Offset.zero, width: faceW, height: faceH),
    topLeft: Radius.circular(faceW * 0.42),
    topRight: Radius.circular(faceW * 0.42),
    bottomLeft: Radius.circular(faceW * 0.26),
    bottomRight: Radius.circular(faceW * 0.26),
  );
  canvas.drawRRect(
    face,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: palette.isDark
            ? const [Color(0xFF3A4556), Color(0xFF1A212C)]
            : const [Color(0xFF2E3A4C), Color(0xFF121821)],
      ).createShader(face.outerRect),
  );
  // Surface texture: a fine carbon weave.
  canvas.save();
  canvas.clipRRect(face);
  final weave = Paint()
    ..color = Colors.white.withValues(alpha: 0.05)
    ..strokeWidth = 1;
  for (var x = -faceW; x < faceW; x += math.max(3, length * 0.05)) {
    canvas.drawLine(Offset(x, -faceH / 2), Offset(x + faceH * 0.6, faceH / 2), weave);
  }
  canvas.restore();
  // Edge guard, in the ball's lime.
  canvas.drawRRect(
    face.deflate(length * 0.012),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, length * 0.03)
      ..color = palette.ball,
  );
  canvas.restore();
  canvas.restore();
}

/// Where things sit on the perspective court drawn by [paintCourt].
class CourtGeometry {
  CourtGeometry(this.size, {required this.top});

  final Size size;

  /// The far baseline's y.
  final double top;

  double get _bottom => size.height * 1.04;
  double get _topHalf => size.width * 0.24;
  double get _bottomHalf => size.width * 0.8;

  /// Screen y of [depth] (0 far baseline, 0.5 net, 1 near baseline).
  double y(double depth) => top + (_bottom - top) * (depth * depth * 0.55 + depth * 0.45);

  /// Half the court's width on screen at [depth].
  double halfWidth(double depth) => _topHalf + (_bottomHalf - _topHalf) * ((y(depth) - top) / (_bottom - top));

  /// A point on the court: [side] -1 is the left sideline, 1 the right.
  Offset point(double depth, double side) => Offset(size.width / 2 + side * halfWidth(depth), y(depth));

  /// How big something at [depth] looks, relative to the near baseline.
  double scale(double depth) => halfWidth(depth) / _bottomHalf * 1.6;
}

/// A pickleball court seen from behind the near baseline, drawn from the
/// net outward. [draw] 0..1 grows each line from its midpoint.
void paintCourt(
  Canvas canvas,
  Size size, {
  required double top,
  required double draw,
  required Color color,
  double alpha = 1,
  double glowAlpha = 0.3,
}) {
  final bottom = size.height * 1.04;
  final topHalf = size.width * 0.24;
  final bottomHalf = size.width * 0.8;
  final cx = size.width / 2;
  double yAt(double d) => top + (bottom - top) * (d * d * 0.55 + d * 0.45);
  double halfAt(double d) => topHalf + (bottomHalf - topHalf) * ((yAt(d) - top) / (bottom - top));
  Offset l(double d) => Offset(cx - halfAt(d), yAt(d));
  Offset r(double d) => Offset(cx + halfAt(d), yAt(d));

  // Kitchen lines are 7 ft either side of the net on a 44 ft court.
  const farKitchen = 0.5 - 7 / 44;
  const nearKitchen = 0.5 + 7 / 44;

  Path grow(Offset a, Offset b) {
    final m = Offset.lerp(a, b, 0.5)!;
    final from = Offset.lerp(m, a, draw)!, to = Offset.lerp(m, b, draw)!;
    return Path()
      ..moveTo(from.dx, from.dy)
      ..lineTo(to.dx, to.dy);
  }

  final lines = Path()
    ..addPath(grow(l(0), r(0)), Offset.zero)
    ..addPath(grow(l(1), r(1)), Offset.zero)
    ..addPath(grow(l(0), l(1)), Offset.zero)
    ..addPath(grow(r(0), r(1)), Offset.zero)
    ..addPath(grow(l(farKitchen), r(farKitchen)), Offset.zero)
    ..addPath(grow(l(nearKitchen), r(nearKitchen)), Offset.zero)
    ..addPath(grow(Offset(cx, yAt(0)), Offset(cx, yAt(farKitchen))), Offset.zero)
    ..addPath(grow(Offset(cx, yAt(nearKitchen)), Offset(cx, yAt(1))), Offset.zero);

  canvas.drawPath(
    lines,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..color = color.withValues(alpha: glowAlpha * 0.35 * alpha)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
  );
  canvas.drawPath(
    lines,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..color = color.withValues(alpha: 0.32 * alpha),
  );
  // The net.
  final m = Offset.lerp(l(0.5), r(0.5), 0.5)!;
  canvas.drawLine(
    Offset.lerp(m, l(0.5), draw)!,
    Offset.lerp(m, r(0.5), draw)!,
    Paint()
      ..strokeWidth = 2
      ..color = color.withValues(alpha: 0.5 * alpha),
  );
}

/// A pickleball of radius [r] centred on the canvas origin.
void paintPickleball(Canvas canvas, double r, {required OnboardPalette palette, double spin = 0, bool glow = true}) =>
    Pickleball.paint(canvas, Offset.zero, r, color: palette.ball, hole: palette.ballInk, spin: spin, glow: glow ? 1 : 0);

/// A static pickleball, for icons and cards.
class PickleballMark extends StatelessWidget {
  const PickleballMark({super.key, this.size = 20, this.glow = false});

  final double size;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final palette = OnboardPalette.of(context);
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _BallPainter(palette, glow)),
    );
  }
}

class _BallPainter extends CustomPainter {
  _BallPainter(this.palette, this.glow);

  final OnboardPalette palette;
  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(size.width / 2, size.height / 2);
    paintPickleball(canvas, size.shortestSide / 2 / 1.07, palette: palette, spin: 0.3, glow: glow);
  }

  @override
  bool shouldRepaint(_BallPainter old) => old.palette != palette || old.glow != glow;
}

// ─── Entrance ────────────────────────────────────────────────────────────

/// Rises and fades [child] into place once, after [delay]. Stagger a few of
/// these down a screen so it reads top to bottom. Waits for the launch
/// animation, so nothing plays unseen underneath it.
class Reveal extends ConsumerStatefulWidget {
  const Reveal({super.key, required this.child, this.delay = Duration.zero, this.offset = 18});

  final Widget child;
  final Duration delay;

  /// How far below its place the child starts, in logical pixels.
  final double offset;

  @override
  ConsumerState<Reveal> createState() => _RevealState();
}

class _RevealState extends ConsumerState<Reveal> with SingleTickerProviderStateMixin {
  static const _length = Duration(milliseconds: 520);
  late final AnimationController _controller = AnimationController(vsync: this, duration: widget.delay + _length);
  late final Animation<double> _t = CurvedAnimation(
    parent: _controller,
    curve: Interval(widget.delay.inMilliseconds / (widget.delay + _length).inMilliseconds, 1, curve: Curves.easeOutCubic),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) {
      _controller.value = 1;
    } else if (ref.watch(launchIntroDoneProvider) && _controller.value == 0 && !_controller.isAnimating) {
      _controller.forward();
    }
    return AnimatedBuilder(
        animation: _t,
        child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _t.value,
        child: Transform.translate(offset: Offset(0, widget.offset * (1 - _t.value)), child: child),
      ),
    );
  }
}

// ─── Progress ────────────────────────────────────────────────────────────

/// A row of segments, one per step: done ones filled, the current one
/// filling by [progress], later ones faint.
class SegmentedProgress extends StatelessWidget {
  const SegmentedProgress({super.key, required this.count, required this.index, this.progress = 1, this.label});

  final int count;
  final int index;

  /// 0..1 through the current segment.
  final double progress;

  /// Read out instead of the bars, e.g. "Step 2 of 5".
  final String? label;

  @override
  Widget build(BuildContext context) {
    final palette = OnboardPalette.of(context);
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Row(
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: SizedBox(
                  height: 3,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(color: palette.ink.withValues(alpha: 0.14)),
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: i < index ? 1 : (i == index ? progress.clamp(0.0, 1.0) : 0),
                        child: ColoredBox(color: palette.isDark ? palette.ball : palette.ink),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Actions ─────────────────────────────────────────────────────────────

/// The one primary action on an onboarding screen: big, caps, and it dips
/// under the thumb. Shows [BallLoader] while [busy].
class OnboardButton extends StatefulWidget {
  const OnboardButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.secondary = false,
    this.icon,
  });

  const OnboardButton.secondary({super.key, required this.label, required this.onPressed, this.icon})
      : busy = false,
        secondary = true;

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final bool secondary;
  final IconData? icon;

  @override
  State<OnboardButton> createState() => _OnboardButtonState();
}

class _OnboardButtonState extends State<OnboardButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final palette = OnboardPalette.of(context);
    final enabled = widget.onPressed != null && !widget.busy;
    final bg = widget.secondary ? palette.glass : palette.primaryFill;
    final fg = widget.secondary ? palette.ink : palette.onPrimary;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: enabled
            ? () {
                HapticFeedback.lightImpact();
                widget.onPressed!();
              }
            : null,
        child: AnimatedScale(
          scale: _down && !reduceMotion(context) ? 0.97 : 1,
          duration: const Duration(milliseconds: 120),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 160),
            opacity: enabled || widget.busy ? 1 : 0.38,
            child: Container(
              height: 58,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(18),
                border: widget.secondary ? Border.all(color: palette.glassBorder) : null,
                boxShadow: widget.secondary || !enabled || !palette.isDark
                    ? null
                    : [BoxShadow(color: palette.primaryFill.withValues(alpha: 0.22), blurRadius: 24, offset: const Offset(0, 8))],
              ),
              child: widget.busy
                  ? BallLoader(color: fg, width: 40, label: '${widget.label}, working')
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            widget.label.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: OnboardType.button(fg),
                          ),
                        ),
                        if (widget.icon != null) ...[const SizedBox(width: 10), Icon(widget.icon, size: 20, color: fg)],
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A 48×48 round glass button for back and close.
class OnboardIconButton extends StatelessWidget {
  const OnboardIconButton({super.key, required this.icon, required this.label, required this.onPressed});

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = OnboardPalette.of(context);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onPressed,
        radius: 28,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: palette.glass,
            border: Border.all(color: palette.glassBorder),
          ),
          child: Icon(icon, size: 22, color: palette.ink),
        ),
      ),
    );
  }
}

/// A translucent, blurred panel that keeps a form readable over the moving
/// backdrop.
class GlassPanel extends StatelessWidget {
  const GlassPanel({super.key, required this.child, this.padding = const EdgeInsets.all(20)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final palette = OnboardPalette.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: palette.glass,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: palette.glassBorder),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// A message under a field or form: what went wrong and, when there is
/// one, the thing to do about it.
class OnboardError extends StatelessWidget {
  const OnboardError({super.key, required this.message, this.action, this.onAction});

  final String message;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final palette = OnboardPalette.of(context);
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.error_outline_rounded, size: 18, color: palette.error),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, key: const Key('onboardError'), style: TextStyle(color: palette.error, fontSize: 14, height: 1.35)),
          ),
          if (action != null)
            GestureDetector(
              onTap: onAction,
              child: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text(
                  action!,
                  style: TextStyle(color: palette.ink, fontSize: 14, fontWeight: FontWeight.w700, decoration: TextDecoration.underline),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The standard onboarding screen: backdrop, an optional top bar, content
/// that scrolls when the keyboard is up, and the primary action pinned to
/// the bottom (above the keyboard).
class OnboardScaffold extends StatelessWidget {
  const OnboardScaffold({
    super.key,
    required this.body,
    this.leading,
    this.trailing,
    this.top,
    this.bottom,
    this.courtTop = 0.62,
    this.backdropStrength = 1,
    this.ball = true,
    this.fillBody = false,
  });

  final Widget body;

  /// Gives [body] at least the whole height between the top bar and the
  /// bottom action (it still scrolls on small phones), so it can use
  /// [Spacer]s to sit centred instead of leaving a gap at the bottom.
  final bool fillBody;
  final Widget? leading;
  final Widget? trailing;

  /// Under the top bar, e.g. step progress.
  final Widget? top;
  final Widget? bottom;
  final double courtTop;
  final double backdropStrength;
  final bool ball;

  @override
  Widget build(BuildContext context) {
    final palette = OnboardPalette.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: palette.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: palette.canvas,
        body: CourtBackdrop(
          courtTop: courtTop,
          strength: backdropStrength,
          ball: ball,
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (leading != null || trailing != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Row(
                          children: [
                            leading ?? const SizedBox(height: 48),
                            const Spacer(),
                            ?trailing,
                          ],
                        ),
                      ),
                    if (top != null) Padding(padding: const EdgeInsets.fromLTRB(24, 12, 24, 0), child: top),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, box) => SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                          child: fillBody
                              ? ConstrainedBox(
                                  constraints: BoxConstraints(minHeight: math.max(0, box.maxHeight - 40)),
                                  child: IntrinsicHeight(child: body),
                                )
                              : body,
                        ),
                      ),
                    ),
                    if (bottom != null) Padding(padding: const EdgeInsets.fromLTRB(24, 8, 24, 16), child: bottom),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
