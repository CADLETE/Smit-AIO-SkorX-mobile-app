import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'pickleball.dart';
import 'tokens.dart';

// The SkorX motion and graphics layer: ambient light behind every screen,
// content that arrives in a stagger, a shine on primary actions, and the
// drawn pickleball and court that give cards their character. Looping pieces
// stop under reduced motion (and in widget tests); one-shot entrances are
// skipped under reduced motion.

// ─── Ambient backdrop ────────────────────────────────────────────────────

/// The canvas every screen sits on: slow drifting coloured light, faint
/// court lines and a few pickleballs floating up.
class SxBackdrop extends StatefulWidget {
  const SxBackdrop({super.key, required this.child});

  final Widget child;

  @override
  State<SxBackdrop> createState() => _SxBackdropState();
}

class _SxBackdropState extends State<SxBackdrop> with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(vsync: this, duration: const Duration(seconds: 36), value: 0.18);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (sxAmbientMotion(context)) {
      if (!_t.isAnimating) _t.repeat();
    } else {
      _t.stop();
    }
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: ExcludeSemantics(child: CustomPaint(painter: _AmbientPainter(_t, c))),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _AmbientPainter extends CustomPainter {
  _AmbientPainter(this.t, this.c) : super(repaint: t);

  final Animation<double> t;
  final SxColors c;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = c.canvas);
    final phase = t.value * 2 * math.pi;
    final a = c.isDark ? 1.0 : 0.6;

    // (colour, x, y, radius, drift x, drift y, speed, strength)
    final orbs = [
      (c.blue, 0.05, 0.02, 0.85, 0.18, 0.08, 1.0, 0.30),
      (c.cyan, 1.0, 0.30, 0.70, 0.14, 0.12, -1.0, 0.14),
      (c.deep, 0.15, 0.78, 0.75, 0.16, 0.10, 2.0, 0.55),
      (c.voltFill, 0.95, 0.95, 0.60, 0.10, 0.14, -2.0, 0.12),
    ];
    for (final (color, x, y, r, dx, dy, speed, strength) in orbs) {
      final center = Offset(
        w * (x + dx * math.sin(phase * speed)),
        h * (y + dy * math.cos(phase * speed)),
      );
      final radius = math.max(w, h) * r;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [color.withValues(alpha: strength * a), color.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }

    // A court seen from the baseline, fading into the bottom of the screen.
    CourtPainter.drawCourt(
      canvas,
      Rect.fromLTWH(-w * 0.1, h * 0.62, w * 1.2, h * 0.52),
      (c.isDark ? Colors.white : c.blue).withValues(alpha: c.isDark ? 0.045 : 0.06),
      topInset: 0.3,
    );

    // Balls drifting up, each on its own lane and pace.
    for (var i = 0; i < 3; i++) {
      final speed = [1.0, 2.0, 3.0][i];
      final lane = [0.18, 0.78, 0.46][i];
      final p = (t.value * speed + i / 3) % 1;
      final center = Offset(w * lane + math.sin(phase * speed + i) * 18, h * (1.1 - p * 1.25));
      PickleballPainter.drawBall(
        canvas,
        center,
        [9.0, 6.0, 12.0][i],
        c.voltFill.withValues(alpha: c.isDark ? 0.16 : 0.35),
        hole: c.canvas.withValues(alpha: 0.35),
        spin: phase * speed,
      );
    }
  }

  @override
  bool shouldRepaint(_AmbientPainter old) => old.c != c || old.t != t;
}

// ─── Page transitions ────────────────────────────────────────────────────

/// Every route arrives with a lift and fade over its own ambient backdrop.
/// iOS keeps its native swipe-back transition.
class SxPageTransitions extends PageTransitionsBuilder {
  const SxPageTransitions();

  static const _cupertino = CupertinoPageTransitionsBuilder();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 420);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final page = SxBackdrop(child: child);
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      return _cupertino.buildTransitions(route, context, animation, secondaryAnimation, page);
    }
    if (sxReduceMotion(context)) return FadeTransition(opacity: animation, child: page);
    final inCurve = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    final outCurve = CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeOutCubic);
    return AnimatedBuilder(
      animation: Listenable.merge([inCurve, outCurve]),
      child: page,
      builder: (context, child) {
        final i = inCurve.value;
        final o = outCurve.value;
        return Opacity(
          opacity: i.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1 - i) * 36),
            child: Transform.scale(scale: (0.96 + 0.04 * i) * (1 - 0.04 * o), child: child),
          ),
        );
      },
    );
  }
}

// ─── Entrances ───────────────────────────────────────────────────────────

/// Fades and lifts its child in once, [index] steps after its siblings.
class SxReveal extends StatefulWidget {
  const SxReveal({super.key, required this.child, this.index = 0, this.offset = 22});

  final Widget child;
  final int index;
  final double offset;

  @override
  State<SxReveal> createState() => _SxRevealState();
}

class _SxRevealState extends State<SxReveal> with SingleTickerProviderStateMixin {
  static const _step = 60;
  static const _run = 560;

  late final int _delay = math.min(widget.index, 8) * _step;
  late final AnimationController _c =
      AnimationController(vsync: this, duration: Duration(milliseconds: _delay + _run));
  late final Animation<double> _a = CurvedAnimation(
    parent: _c,
    curve: Interval(_delay / (_delay + _run), 1, curve: Curves.easeOutQuart),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (sxReduceMotion(context)) {
      _c.value = 1;
    } else if (_c.value == 0 && !_c.isAnimating) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _a,
        child: widget.child,
        builder: (context, child) {
          final v = _a.value;
          if (v == 1) return child!;
          return Opacity(
            opacity: v.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, (1 - v) * widget.offset),
              child: Transform.scale(scale: 0.97 + 0.03 * v, child: child),
            ),
          );
        },
      );
}

/// Pops its child in with a little overshoot, e.g. a badge or a big number.
class SxPop extends StatelessWidget {
  const SxPop({super.key, required this.child, this.delay = 0});

  final Widget child;
  final int delay;

  @override
  Widget build(BuildContext context) {
    if (sxReduceMotion(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 650 + delay),
      curve: Interval(delay / (650 + delay), 1, curve: Curves.elasticOut),
      child: child,
      builder: (_, v, child) => Transform.scale(scale: 0.6 + 0.4 * v, child: child),
    );
  }
}

/// Gives its child a springy bump each time [value] changes, e.g. a score.
class SxBump extends StatefulWidget {
  const SxBump({super.key, required this.value, required this.child});

  final Object value;
  final Widget child;

  @override
  State<SxBump> createState() => _SxBumpState();
}

class _SxBumpState extends State<SxBump> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 650), value: 1);

  @override
  void didUpdateWidget(SxBump old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && !sxReduceMotion(context)) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (context, child) {
          // Squash down, then overshoot back to size.
          final t = _c.value;
          final scale = t < 0.15 ? 1 - t * 2 : 0.7 + 0.3 * Curves.elasticOut.transform((t - 0.15) / 0.85);
          return Transform.scale(scale: scale, child: child);
        },
      );
}

// ─── Shine ───────────────────────────────────────────────────────────────

/// A band of light that sweeps across its child every few seconds.
class SxShine extends StatefulWidget {
  const SxShine({super.key, required this.child, this.radius = Sx.radius});

  final Widget child;
  final double radius;

  @override
  State<SxShine> createState() => _SxShineState();
}

class _SxShineState extends State<SxShine> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (sxAmbientMotion(context)) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!sxAmbientMotion(context)) return widget.child;
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(widget.radius),
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) {
                  // Sweep during the first third, then rest.
                  final p = (_c.value * 3).clamp(0.0, 1.0);
                  if (p == 0 || p == 1) return const SizedBox.shrink();
                  return FractionalTranslation(
                    translation: Offset(-1.2 + p * 2.4, 0),
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.skewX(-0.35),
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0x00FFFFFF), Color(0x66FFFFFF), Color(0x00FFFFFF)],
                            stops: [0.3, 0.5, 0.7],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Graphics ────────────────────────────────────────────────────────────

/// A pickleball: a shaded sphere with 40 holes, as on a real outdoor ball.
class PickleballPainter extends CustomPainter {
  PickleballPainter({required this.color, required this.hole, this.spin = 0, this.shade = true});

  final Color color;
  final Color hole;
  final double spin;
  final bool shade;

  /// Draws the SkorX pickleball ([Pickleball.paint]).
  static void drawBall(Canvas canvas, Offset center, double r, Color color,
          {required Color hole, double spin = 0, bool shade = false}) =>
      Pickleball.paint(canvas, center, r, color: color, hole: hole, spin: spin, shade: shade);

  @override
  void paint(Canvas canvas, Size size) =>
      drawBall(canvas, size.center(Offset.zero), size.shortestSide / 2, color, hole: hole, spin: spin, shade: shade);

  @override
  bool shouldRepaint(PickleballPainter old) =>
      old.color != color || old.hole != hole || old.spin != spin || old.shade != shade;
}

/// A drawn pickleball that bobs and turns slowly, with a soft glow.
class SxBall extends StatefulWidget {
  const SxBall({super.key, this.size = 64, this.color, this.float = true, this.glow = true});

  final double size;
  final Color? color;
  final bool float;
  final bool glow;

  @override
  State<SxBall> createState() => _SxBallState();
}

class _SxBallState extends State<SxBall> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 6));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.float && sxAmbientMotion(context)) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final color = widget.color ?? c.voltFill;
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final ph = _c.value * 2 * math.pi;
          return Transform.translate(
            offset: Offset(0, math.sin(ph) * widget.size * 0.06),
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: widget.glow
                  ? BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: color.withValues(alpha: 0.45 * c.glow), blurRadius: widget.size * 0.5)],
                    )
                  : null,
              child: CustomPaint(
                // Navy holes, as on the SkorX logo's ball.
                painter: PickleballPainter(color: color, hole: const Color(0xFF243A4E), spin: ph * 0.25),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Pickleball court lines, drawn in perspective from behind the baseline.
class CourtPainter extends CustomPainter {
  CourtPainter({required this.color, this.topInset = 0.22});

  final Color color;

  /// How much narrower the far baseline is than the near one (0–0.5).
  final double topInset;

  static void drawCourt(Canvas canvas, Rect r, Color color, {double topInset = 0.22}) {
    Offset at(double u, double v) {
      final inset = topInset * (1 - v) * r.width;
      return Offset(r.left + inset + u * (r.width - 2 * inset), r.top + v * v * 0.35 * r.height + v * 0.65 * r.height);
    }

    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    void line(double u1, double v1, double u2, double v2, [Paint? paint]) =>
        canvas.drawLine(at(u1, v1), at(u2, v2), paint ?? p);

    line(0, 0, 1, 0);
    line(0, 1, 1, 1);
    line(0, 0, 0, 1);
    line(1, 0, 1, 1);
    // The kitchen either side of the net, and the centre lines.
    line(0, 0.34, 1, 0.34);
    line(0, 0.66, 1, 0.66);
    line(0.5, 0, 0.5, 0.34);
    line(0.5, 0.66, 0.5, 1);
    line(-0.04, 0.5, 1.04, 0.5, Paint()
      ..color = color
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round);
  }

  @override
  void paint(Canvas canvas, Size size) => drawCourt(canvas, Offset.zero & size, color, topInset: topInset);

  @override
  bool shouldRepaint(CourtPainter old) => old.color != color || old.topInset != topInset;
}

// ─── Cards and marks ─────────────────────────────────────────────────────

/// The loudest block on a screen: a gradient card with court art and a
/// floating ball. Text on it is white.
class SxHeroCard extends StatelessWidget {
  const SxHeroCard({
    super.key,
    required this.child,
    this.gradient,
    this.padding = const EdgeInsets.all(Sx.s24),
    this.ball = true,
    this.ballColor,
    this.watermark = false,
  });

  final Widget child;
  final Gradient? gradient;
  final EdgeInsets padding;
  final bool ball;
  final Color? ballColor;

  /// The SkorX logo, large, faint and tilted into the bottom right corner.
  final bool watermark;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final g = gradient ?? c.hero;
    final glowColor = g.colors.first;
    return Container(
      decoration: BoxDecoration(
        gradient: g,
        borderRadius: BorderRadius.circular(Sx.radiusLg + 2),
        boxShadow: c.glowOf(glowColor, strength: 1.3),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Sx.radiusLg + 2),
        child: Stack(
          children: [
            Positioned.fill(
              child: ExcludeSemantics(
                child: CustomPaint(painter: _HeroArt(Colors.white.withValues(alpha: 0.13))),
              ),
            ),
            if (watermark)
              Positioned(
                right: -36,
                bottom: -14,
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: Transform.rotate(
                      angle: -0.14,
                      child: Opacity(
                        opacity: 0.14,
                        child: Image.asset('assets/brand/skorx_logo.png', height: 96, cacheHeight: 300),
                      ),
                    ),
                  ),
                ),
              ),
            if (ball)
              Positioned(right: -18, top: -18, child: SxBall(size: 92, color: ballColor ?? c.voltFill)),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }
}

class _HeroArt extends CustomPainter {
  _HeroArt(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // A sheen from the top left, and a court tilted into the bottom right.
    canvas.drawCircle(
      Offset(size.width * 0.1, 0),
      size.width * 0.8,
      Paint()
        ..shader = RadialGradient(colors: [Colors.white.withValues(alpha: 0.16), Colors.white.withValues(alpha: 0)])
            .createShader(Rect.fromCircle(center: Offset(size.width * 0.1, 0), radius: size.width * 0.8)),
    );
    canvas.save();
    canvas.translate(size.width * 0.55, size.height * 0.35);
    canvas.rotate(-0.28);
    CourtPainter.drawCourt(canvas, Rect.fromLTWH(0, 0, size.width * 0.75, size.height * 0.9), color, topInset: 0.18);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HeroArt old) => old.color != color;
}

/// Draws its subtree with [SxColors.onHero], for content on a hero card.
class SxOnHero extends StatelessWidget {
  const SxOnHero({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        extensions: [...theme.extensions.values.where((e) => e is! SxColors), context.sx.onHero()],
      ),
      child: child,
    );
  }
}

/// Fills text with a gradient.
class SxGradientText extends StatelessWidget {
  const SxGradientText(this.text, {super.key, required this.style, this.gradient, this.maxLines, this.textAlign});

  final String text;
  final TextStyle style;
  final Gradient? gradient;
  final int? maxLines;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final g = gradient ?? context.sx.brand;
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => g.createShader(Offset.zero & bounds.size),
      child: Text(
        text,
        style: style.copyWith(color: Colors.white),
        maxLines: maxLines,
        textAlign: textAlign,
        overflow: maxLines == null ? null : TextOverflow.ellipsis,
      ),
    );
  }
}

/// An icon in a soft gradient tile: the leading mark of actions and rows.
class SxIconTile extends StatelessWidget {
  const SxIconTile({super.key, required this.icon, this.colors, this.size = 42, this.solid = false});

  final IconData icon;

  /// Two brand colours for the tile; defaults to blue into cyan.
  final List<Color>? colors;
  final double size;

  /// A full-strength tile with white icon, for the one hero action.
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final cs = colors ?? [c.blue, c.cyan];
    final onVoltTile = cs.first == c.voltFill;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.32),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: solid ? cs : [for (final x in cs) x.withValues(alpha: c.isDark ? 0.26 : 0.16)],
          ),
          border: solid ? null : Border.all(color: cs.first.withValues(alpha: 0.35)),
          boxShadow: solid ? c.glowOf(cs.first, strength: 0.8) : null,
        ),
        child: Icon(
          icon,
          size: size * 0.5,
          color: solid
              ? (onVoltTile ? c.onVolt : Colors.white)
              : (c.isDark ? Color.lerp(cs.first, Colors.white, 0.45) : Color.lerp(cs.first, Colors.black, onVoltTile ? 0.45 : 0.15)),
        ),
      ),
    );
  }
}

/// Brand colour pairs for icon tiles, so neighbours don't match.
List<Color> sxTileColors(SxColors c, int i) => [
      [c.blue, c.cyan],
      [c.voltFill, c.olive],
      [c.cyan, c.blue],
      [c.deep, c.blue],
    ][i % 4];
