import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/onboarding/onboarding_controller.dart';
import '../../features/onboarding/ui/onboarding_kit.dart';
import '../../design/pickleball.dart';
import '../../shared/widgets.dart';
import '../theme/tokens.dart';

/// Plays the SkorX opening animation once per launch on top of [child], then
/// gets out of the way. The app keeps restoring the session underneath, so
/// the intro never adds to start-up time beyond its own length.
///
/// The first launch on a phone gets the full brand reveal (under 3 s); after
/// that, the same animation cut short and sped up (1.5 s) so returning
/// players are straight in.
/// Skipped entirely when the platform asks for reduced motion.
class SkorxIntroGate extends ConsumerStatefulWidget {
  const SkorxIntroGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SkorxIntroGate> createState() => _SkorxIntroGateState();
}

class _SkorxIntroGateState extends ConsumerState<SkorxIntroGate> {
  bool _done = false;

  /// Decided once, when the saved onboarding state is known, so finishing
  /// the introduction later does not swap the animation mid-play.
  bool? _quick;

  void _finish() {
    setState(() => _done = true);
    ref.read(launchIntroDoneProvider.notifier).finish();
  }

  @override
  Widget build(BuildContext context) {
    if (_done || MediaQuery.disableAnimationsOf(context)) return widget.child;
    final onboarding = ref.watch(onboardingControllerProvider);
    if (onboarding.ready) _quick ??= onboarding.hasCompletedOnboarding;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        // Swallows taps so nothing underneath is hit mid-intro.
        // Starts on the first frame from the opening scene (also the native
        // splash image). A returning player's shorter version takes over once
        // the saved state is read, while the ball is still off screen.
        AbsorbPointer(
          child: SkorxIntro(quick: _quick ?? false, onFinished: _finish),
        ),
      ],
    );
  }
}

/// A pickleball arcs in over a neon court, strikes centre court, and the
/// impact slashes the SkorX "X" and reveals the logo. [quick] joins the
/// ball already in flight and plays faster. It starts on the first Flutter
/// frame; the native splash before it is plain background, so launch reads
/// as one animation rather than a static icon followed by one.
class SkorxIntro extends StatefulWidget {
  const SkorxIntro({super.key, required this.onFinished, this.quick = false, this.started = true});

  static const duration = Duration(milliseconds: 3800);
  static const quickDuration = Duration(milliseconds: 2600);

  /// Where the full version starts on the timeline: the court is already
  /// lit (it is the splash image) and the ball is just about to come in.
  static const fullStart = 0.1;

  /// Where [quick] joins the timeline: the ball already in flight.
  static const quickStart = 0.14;

  final VoidCallback onFinished;
  final bool quick;

  /// False holds the opening scene (the court under its light, no ball):
  /// the same picture as the native splash, so launch has no visible seam.
  final bool started;

  @override
  State<SkorxIntro> createState() => _SkorxIntroState();
}

/// Timeline, as fractions of [SkorxIntro.duration].
abstract final class _T {
  static const ballFlight = (0.06, 0.36);
  static const impact = 0.36;
  static const slash = (0.33, 0.47);
  static const logoIn = (0.37, 0.56);
  static const sheen = (0.60, 0.78);
  static const tagline = (0.58, 0.76);
  static const exit = (0.92, 1.0);
}

/// Progress of [t] through [span], clamped to 0..1.
double _seg(double t, (double, double) span) => ((t - span.$1) / (span.$2 - span.$1)).clamp(0.0, 1.0);

// Where the logo's ball sits in the artwork, as fractions of its size, so the
// flying ball lands exactly on it.
const _logoBallCenter = Offset(0.4925, 0.52);
const _logoBallDiameter = 0.255;

class _SkorxIntroState extends State<SkorxIntro> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this)
    ..addListener(_onTick)
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onFinished();
    });

  @override
  void initState() {
    super.initState();
    if (widget.started) _start();
  }

  @override
  void didUpdateWidget(SkorxIntro old) {
    super.didUpdateWidget(old);
    if (!old.started && widget.started) {
      _start();
    } else if (!old.quick && widget.quick && widget.started) {
      // Carry on from the same point of the full timeline, faster. Before
      // SkorxIntro.quickStart the ball is still off screen, so the skip
      // ahead cannot be seen.
      final t = SkorxIntro.fullStart + (1 - SkorxIntro.fullStart) * _controller.value;
      final v = ((t - SkorxIntro.quickStart) / (1 - SkorxIntro.quickStart)).clamp(0.0, 1.0);
      _controller
        ..duration = SkorxIntro.quickDuration
        ..forward(from: v);
    }
  }

  void _start() {
    _controller
      ..duration = widget.quick ? SkorxIntro.quickDuration : SkorxIntro.duration
      ..forward();
  }

  bool _hit = false;

  /// Position on the full timeline.
  double get _t => !widget.started ? 0 : _startOf(widget.quick) + (1 - _startOf(widget.quick)) * _controller.value;

  static double _startOf(bool quick) => quick ? SkorxIntro.quickStart : SkorxIntro.fullStart;

  void _onTick() {
    if (!_hit && _t >= _T.impact) {
      _hit = true;
      HapticFeedback.lightImpact();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Decode the logo before it is needed so it pops in on the impact frame.
    precacheImage(const AssetImage(SkorxLogo.asset), context);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const colors = SkorxColors.dark;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final logoWidth = math.min(size.width * 0.78, 380.0);
        final logoHeight = logoWidth / SkorxLogo.aspectRatio;
        final center = Offset(size.width / 2, size.height * 0.44);
        final ballTarget =
            center + Offset((_logoBallCenter.dx - 0.5) * logoWidth, (_logoBallCenter.dy - 0.5) * logoHeight);
        final ballRadius = logoWidth * _logoBallDiameter / 2;

        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _t;
            final exit = Curves.easeInCubic.transform(_seg(t, _T.exit));
            final logoT = _seg(t, _T.logoIn);
            final logoScale = 1.35 - 0.35 * Curves.easeOutBack.transform(logoT) + 0.08 * exit;
            final taglineT = Curves.easeOutCubic.transform(_seg(t, _T.tagline));

            return Opacity(
              opacity: 1 - exit,
              child: ColoredBox(
                color: colors.background,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CustomPaint(
                      painter: _IntroPainter(
                        t: t,
                        center: center,
                        ballTarget: ballTarget,
                        ballRadius: ballRadius,
                        logoWidth: logoWidth,
                      ),
                    ),
                    Positioned(
                      left: center.dx - logoWidth / 2,
                      top: center.dy - logoHeight / 2,
                      width: logoWidth,
                      height: logoHeight,
                      child: Opacity(
                        opacity: Curves.easeOut.transform(math.min(1, logoT * 2.5)),
                        child: Transform.scale(
                          scale: logoScale,
                          child: _Sheen(
                            progress: _seg(t, _T.sheen),
                            child: SkorxLogo(height: logoHeight),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: center.dy + logoHeight / 2 + 28,
                      child: Opacity(
                        opacity: taglineT,
                        child: Column(
                          children: [
                            Container(
                              width: 64 * taglineT,
                              height: 2,
                              decoration: BoxDecoration(
                                color: colors.lime,
                                borderRadius: BorderRadius.circular(1),
                                boxShadow: [BoxShadow(color: colors.lime.withValues(alpha: 0.6), blurRadius: 8)],
                              ),
                            ),
                            const SizedBox(height: 14),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  'YOUR  PICKLEBALL  WORLD',
                                  maxLines: 1,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: 'BarlowCondensed',
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    letterSpacing: 2.2 + 4 * (1 - taglineT),
                                    color: colors.textMuted,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// A diagonal band of light that sweeps across [child] once.
class _Sheen extends StatelessWidget {
  const _Sheen({required this.progress, required this.child});

  final double progress;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (progress <= 0 || progress >= 1) return child;
    final p = Curves.easeInOut.transform(progress) * 2.4 - 1.2;
    return ShaderMask(
      blendMode: BlendMode.srcATop,
      shaderCallback: (bounds) => LinearGradient(
        begin: Alignment(p - 0.5, -1),
        end: Alignment(p + 0.5, 1),
        colors: [
          Colors.white.withValues(alpha: 0),
          Colors.white.withValues(alpha: 0.55),
          Colors.white.withValues(alpha: 0),
        ],
        stops: const [0.35, 0.5, 0.65],
      ).createShader(bounds),
      child: child,
    );
  }
}

class _IntroPainter extends CustomPainter {
  _IntroPainter({
    required this.t,
    required this.center,
    required this.ballTarget,
    required this.ballRadius,
    required this.logoWidth,
  });

  final double t;
  final Offset center;
  final Offset ballTarget;
  final double ballRadius;
  final double logoWidth;

  static const _colors = SkorxColors.dark;
  static const _ballLime = Color(0xFFCFE524);
  static const _ballInk = Color(0xFF243A4F);

  @override
  void paint(Canvas canvas, Size size) {
    _paintGlow(canvas, size);
    _paintCourt(canvas, size);
    _paintBall(canvas, size);
    _paintImpact(canvas);
    _paintSlash(canvas);
  }

  /// Soft spotlight behind the logo, blooming on impact.
  void _paintGlow(Canvas canvas, Size size) {
    // Lit from the first frame: the native splash is this same scene.
    const base = 1.0;
    final pulse = t < _T.impact ? 0.0 : math.exp(-(t - _T.impact) * 9);
    final radius = size.longestSide * (0.45 + 0.1 * pulse);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = ui.Gradient.radial(center, radius, [
          Color.lerp(_colors.navy, _colors.blue, 0.25 * pulse)!.withValues(alpha: 0.9 * base),
          _colors.background.withValues(alpha: 0),
        ]),
    );
  }

  /// A perspective court whose lines draw themselves in from the net outward.
  void _paintCourt(Canvas canvas, Size size) {
    // Already drawn at launch (it is in the native splash image).
    const draw = 1.0;

    final top = size.height * 0.64;
    final bottom = size.height * 1.04;
    final topHalf = size.width * 0.24;
    final bottomHalf = size.width * 0.78;
    final cx = size.width / 2;
    double yAt(double d) => top + (bottom - top) * (d * d * 0.55 + d * 0.45);
    double halfAt(double d) => topHalf + (bottomHalf - topHalf) * ((yAt(d) - top) / (bottom - top));
    Offset l(double d) => Offset(cx - halfAt(d), yAt(d));
    Offset r(double d) => Offset(cx + halfAt(d), yAt(d));

    const farKitchen = 0.5 - 7 / 44;
    const nearKitchen = 0.5 + 7 / 44;

    Path line(Offset a, Offset b) => Path()
      ..moveTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy);
    // Each line grows from its midpoint, so the court "opens" outward.
    Path grow(Offset a, Offset b) {
      final m = Offset.lerp(a, b, 0.5)!;
      return line(Offset.lerp(m, a, draw)!, Offset.lerp(m, b, draw)!);
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

    final pulse = t < _T.impact ? 0.0 : math.exp(-(t - _T.impact) * 7);
    final alpha = 0.28 + 0.5 * pulse;
    canvas.drawPath(
      lines,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = _colors.cyan.withValues(alpha: alpha * 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawPath(
      lines,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = _colors.cyan.withValues(alpha: alpha),
    );

    // The net, in lime.
    final netT = draw;
    final netL = l(0.5), netR = r(0.5);
    final m = Offset.lerp(netL, netR, 0.5)!;
    canvas.drawLine(
      Offset.lerp(m, netL, netT)!,
      Offset.lerp(m, netR, netT)!,
      Paint()
        ..strokeWidth = 2
        ..color = _colors.lime.withValues(alpha: 0.35 + 0.5 * pulse),
    );
  }

  Offset _ballAt(double f, Size size) {
    // Quadratic arc from off-screen bottom-right, lobbing up and dropping in.
    final start = Offset(size.width * 1.2, size.height * 0.92);
    final control = Offset(size.width * 0.9, size.height * 0.02);
    final u = 1 - f;
    return start * (u * u) + control * (2 * u * f) + ballTarget * (f * f);
  }

  void _paintBall(Canvas canvas, Size size) {
    final raw = _seg(t, _T.ballFlight);
    if (raw <= 0) return;
    // Fades into the logo's own ball once the logo is up.
    final fade = 1 - _seg(t, (_T.logoIn.$1 + 0.02, _T.logoIn.$1 + 0.08));
    if (fade <= 0) return;
    final f = Curves.easeInQuad.transform(raw);

    // Motion trail.
    if (raw < 1) {
      for (var i = 6; i >= 1; i--) {
        final g = Curves.easeInQuad.transform((raw - i * 0.022).clamp(0.0, 1.0));
        if (g <= 0) continue;
        canvas.drawCircle(
          _ballAt(g, size),
          _radiusAt(g) * (1 - i * 0.08),
          Paint()
            ..color = _colors.lime.withValues(alpha: 0.18 * (1 - i / 7) * fade)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
      }
    }

    final c = _ballAt(f, size);
    final radius = _radiusAt(f);
    // A quick squash on contact.
    final squash = t < _T.impact ? 0.0 : math.sin(_seg(t, (_T.impact, _T.impact + 0.04)) * math.pi) * 0.14;

    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(1 + squash, 1 - squash);
    canvas.saveLayer(null, Paint()..color = Colors.white.withValues(alpha: fade));
    _drawPickleball(canvas, radius, spin: f * math.pi * 3.2);
    canvas.restore();
    canvas.restore();
  }

  /// Bigger while close to the viewer, settling to the logo's ball size.
  double _radiusAt(double f) => ballRadius * (1.9 - 0.9 * f);

  void _drawPickleball(Canvas canvas, double r, {required double spin}) =>
      Pickleball.paint(canvas, Offset.zero, r, color: _ballLime, hole: _ballInk, spin: spin, glow: 1);

  /// Flash, shockwave rings and sparks when the ball lands.
  void _paintImpact(Canvas canvas) {
    if (t < _T.impact) return;
    final k = t - _T.impact;

    final flash = math.max(0.0, 1 - k / 0.08);
    if (flash > 0) {
      canvas.drawCircle(
        ballTarget,
        logoWidth * 0.55,
        Paint()
          ..shader = ui.Gradient.radial(ballTarget, logoWidth * 0.55, [
            Colors.white.withValues(alpha: 0.75 * flash),
            Colors.white.withValues(alpha: 0),
          ]),
      );
    }

    for (final (delay, color) in [(0.0, _colors.lime), (0.05, _colors.cyan), (0.1, _colors.blue)]) {
      final p = ((k - delay) / 0.28).clamp(0.0, 1.0);
      if (p <= 0 || p >= 1) continue;
      final e = Curves.easeOutCubic.transform(p);
      canvas.drawCircle(
        ballTarget,
        ballRadius + logoWidth * 0.75 * e,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 * (1 - e) + 0.5
          ..color = color.withValues(alpha: (1 - e) * 0.9),
      );
    }

    final sparkP = (k / 0.22).clamp(0.0, 1.0);
    if (sparkP < 1) {
      final e = Curves.easeOutQuart.transform(sparkP);
      const count = 16;
      for (var i = 0; i < count; i++) {
        final angle = i * 2 * math.pi / count + (i.isEven ? 0.12 : -0.08);
        final reach = logoWidth * (0.35 + 0.25 * ((i * 7) % 5) / 4);
        final dir = Offset(math.cos(angle), math.sin(angle));
        final head = ballTarget + dir * (ballRadius + reach * e);
        final tail = ballTarget + dir * (ballRadius + reach * e * 0.7);
        canvas.drawLine(
          tail,
          head,
          Paint()
            ..strokeCap = StrokeCap.round
            ..strokeWidth = 2.2 * (1 - sparkP) + 0.4
            ..color = (i % 3 == 0 ? _colors.cyan : _colors.lime).withValues(alpha: 1 - sparkP),
        );
      }
    }
  }

  /// Two blades cut through the ball, echoing the X in the logo.
  void _paintSlash(Canvas canvas) {
    final p = _seg(t, _T.slash);
    if (p <= 0 || p >= 1) return;
    final grow = Curves.easeOutExpo.transform(math.min(1, p * 1.6));
    final fade = 1 - Curves.easeIn.transform(_seg(p, (0.55, 1)));
    final len = logoWidth * 0.42;

    for (final (angle, delay) in [(-math.pi / 4.4, 0.0), (math.pi / 4.4, 0.12)]) {
      final g = ((grow - delay) / (1 - delay)).clamp(0.0, 1.0);
      if (g <= 0) continue;
      canvas.save();
      canvas.translate(ballTarget.dx, ballTarget.dy);
      canvas.rotate(angle);
      final half = len * g;
      final w = logoWidth * 0.022;
      final blade = Path()
        ..moveTo(-half, 0)
        ..lineTo(0, -w)
        ..lineTo(half, 0)
        ..lineTo(0, w)
        ..close();
      canvas.drawPath(
        blade,
        Paint()
          ..color = _colors.cyan.withValues(alpha: 0.6 * fade)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 1.5),
      );
      canvas.drawPath(blade, Paint()..color = Colors.white.withValues(alpha: fade));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_IntroPainter old) =>
      old.t != t || old.center != center || old.ballTarget != ballTarget || old.logoWidth != logoWidth;
}
