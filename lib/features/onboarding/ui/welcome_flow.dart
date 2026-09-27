import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routing/redirect.dart';
import '../../../app/theme/typography.dart';
import '../../../shared/widgets.dart';
import '../onboarding_controller.dart';
import 'onboarding_kit.dart';

/// The first-launch introduction: three short stories (what SkorX is, what it
/// does for a player, SkorX TMS), then Get Started. Stories advance on their
/// own every few seconds; tap, swipe or Skip to move faster.
class WelcomeFlow extends ConsumerStatefulWidget {
  const WelcomeFlow({super.key});

  static const storyLength = Duration(milliseconds: 4200);

  @override
  ConsumerState<WelcomeFlow> createState() => _WelcomeFlowState();
}

class _WelcomeFlowState extends ConsumerState<WelcomeFlow> with SingleTickerProviderStateMixin {
  static const _stories = 3;
  final _pages = PageController();
  late final AnimationController _timer = AnimationController(vsync: this, duration: WelcomeFlow.storyLength)
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed) _goTo(_index + 1);
    });
  int _index = 0;
  bool _started = false;

  bool get _onStory => _index < _stories;

  @override
  void dispose() {
    _timer.dispose();
    _pages.dispose();
    super.dispose();
  }

  bool get _autoplay => !reduceMotion(context);

  void _goTo(int index) {
    final target = index.clamp(0, _stories);
    if (target == _index) return;
    if (reduceMotion(context)) {
      _pages.jumpToPage(target);
    } else {
      _pages.animateToPage(target, duration: const Duration(milliseconds: 520), curve: Curves.easeInOutCubic);
    }
  }

  void _onPageChanged(int index) {
    setState(() => _index = index);
    HapticFeedback.selectionClick();
    _timer.reset();
    if (_onStory && _autoplay) _timer.forward();
    // Seeing Get Started once is enough: later launches open on sign-in.
    if (!_onStory) ref.read(onboardingControllerProvider.notifier).complete();
  }

  void _pause() {
    if (_timer.isAnimating) _timer.stop();
  }

  void _resume() {
    if (_onStory && _autoplay && !_timer.isAnimating && _timer.value < 1) _timer.forward();
  }

  void _onTapUp(TapUpDetails details) {
    if (!_onStory) return;
    final width = MediaQuery.sizeOf(context).width;
    _goTo(details.globalPosition.dx < width * 0.3 ? _index - 1 : _index + 1);
  }

  Future<void> _getStarted() async {
    await ref.read(onboardingControllerProvider.notifier).complete();
    if (mounted) context.go(Routes.login);
  }

  Future<void> _explore() async {
    await ref.read(onboardingControllerProvider.notifier).complete();
    if (mounted) context.go(Routes.guest);
  }

  @override
  Widget build(BuildContext context) {
    final palette = OnboardPalette.of(context);
    final launched = ref.watch(launchIntroDoneProvider) || reduceMotion(context);
    if (launched && !_started) {
      _started = true;
      if (_autoplay) _timer.forward();
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: palette.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: palette.canvas,
        body: CourtBackdrop(
          courtTop: _onStory ? 0.66 : 0.5,
          // Fainter wherever text sits over the court.
          strength: 0.6,
          ball: false,
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  children: [
                    _TopBar(
                      showSkip: _onStory,
                      onSkip: () => _goTo(_stories),
                      progress: _onStory
                          ? AnimatedBuilder(
                              animation: _timer,
                              builder: (_, _) => SegmentedProgress(
                                count: _stories,
                                index: _index,
                                progress: _autoplay ? _timer.value : 1,
                                label: 'Story ${_index + 1} of $_stories',
                              ),
                            )
                          : null,
                    ),
                    Expanded(
                      child: Listener(
                        onPointerDown: (_) => _pause(),
                        onPointerUp: (_) => _resume(),
                        onPointerCancel: (_) => _resume(),
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTapUp: _onStory ? _onTapUp : null,
                          child: PageView(
                            key: const Key('welcomePages'),
                            controller: _pages,
                            onPageChanged: _onPageChanged,
                            children: [
                              _Story(
                                active: launched && _index == 0,
                                hero: (active) => _ScoreHero(active: active),
                                eyebrow: 'WELCOME TO SKORX',
                                lines: const ['YOUR GAME.', 'YOUR MATCHES.'],
                                accentLine: 'YOUR PADDLE.',
                                body: 'Scoring, matches, tournaments, rankings and players, together in one place.',
                              ),
                              _Story(
                                active: launched && _index == 1,
                                hero: (active) => _WorldHero(active: active),
                                eyebrow: 'FOR PLAYERS',
                                lines: const ['YOUR PICKLEBALL', 'WORLD.'],
                                accentLine: 'CONNECTED.',
                                body: 'Track your matches and performance, follow tournaments and rankings, and watch live.',
                              ),
                              _Story(
                                active: launched && _index == 2,
                                hero: (active) => _TmsHero(active: active),
                                eyebrow: 'SKORX TMS',
                                lines: const ['POWERING THE GAME'],
                                accentLine: 'BEYOND THE COURT.',
                                body: 'A complete tournament platform for organisers, players, referees and spectators.',
                              ),
                              _GetStarted(active: launched && _index == 3, onStart: _getStarted, onExplore: _explore),
                            ],
                          ),
                        ),
                      ),
                    ),
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

class _TopBar extends StatelessWidget {
  const _TopBar({required this.showSkip, required this.onSkip, this.progress});

  final bool showSkip;
  final VoidCallback onSkip;
  final Widget? progress;

  @override
  Widget build(BuildContext context) {
    final palette = OnboardPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 12, 0),
      child: Column(
        children: [
          SizedBox(
            height: 56,
            child: Row(
              children: [
                const SkorxLogo(height: 44, glow: true),
                const Spacer(),
                AnimatedOpacity(
                  opacity: showSkip ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: TextButton(
                    key: const Key('welcomeSkip'),
                    onPressed: showSkip ? onSkip : null,
                    style: TextButton.styleFrom(
                      foregroundColor: palette.inkMuted,
                      minimumSize: const Size(64, 48),
                      textStyle: SkorxType.label(size: 14).copyWith(letterSpacing: 2),
                    ),
                    child: const Text('SKIP'),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 20,
            child: Padding(
              padding: const EdgeInsets.only(right: 12, top: 8),
              child: AnimatedSwitcher(duration: const Duration(milliseconds: 200), child: progress ?? const SizedBox()),
            ),
          ),
        ],
      ),
    );
  }
}

/// One story: a moving picture on top, one message under it.
class _Story extends StatelessWidget {
  const _Story({
    required this.active,
    required this.hero,
    required this.eyebrow,
    required this.lines,
    required this.accentLine,
    required this.body,
  });

  final bool active;
  final Widget Function(bool active) hero;
  final String eyebrow;
  final List<String> lines;
  final String accentLine;
  final String body;

  @override
  Widget build(BuildContext context) {
    final palette = OnboardPalette.of(context);
    final statement = OnboardType.statement(context, palette.ink);
    return Semantics(
      container: true,
      label: '$eyebrow. ${[...lines, accentLine].join(' ')} $body',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Center(child: hero(active))),
            _Entrance(
              active: active,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(eyebrow, style: OnboardType.eyebrow(palette.accent)),
                  const SizedBox(height: 14),
                  for (final line in lines) _FitLine(line, style: statement),
                  _FitLine(accentLine, style: statement.copyWith(color: palette.accentText)),
                  const SizedBox(height: 16),
                  Text(body, style: OnboardType.body(palette.inkMuted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A statement line that shrinks rather than wraps on narrow phones.
class _FitLine extends StatelessWidget {
  const _FitLine(this.text, {required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(text, maxLines: 1, style: style),
      );
}

/// Rises into place each time its page becomes the current one.
class _Entrance extends StatefulWidget {
  const _Entrance({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<_Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<_Entrance> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 620));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_Entrance old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) _sync();
  }

  void _sync() {
    if (reduceMotion(context)) {
      _c.value = 1;
    } else if (widget.active) {
      _c.forward(from: 0);
    }
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
        builder: (_, child) {
          final t = Curves.easeOutCubic.transform(_c.value);
          return Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 24 * (1 - t)), child: child));
        },
      );
}

/// A hero picture that plays its build-in whenever its page is current.
abstract class _Hero extends StatefulWidget {
  const _Hero({required this.active});

  final bool active;

  Duration get length;
}

abstract class _HeroState<T extends _Hero> extends State<T> with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(vsync: this, duration: widget.length);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(T old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) _sync();
  }

  void _sync() {
    if (reduceMotion(context)) {
      controller.value = 1;
    } else if (widget.active) {
      controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}

/// Progress of [t] through [from]..[to], eased.
double _span(double t, double from, double to, [Curve curve = Curves.easeOutCubic]) =>
    curve.transform(((t - from) / (to - from)).clamp(0.0, 1.0));

// ─── Story 1: the scoreboard ─────────────────────────────────────────────

/// A broadcast-style scoreboard: a ball lobs in and the score ticks to
/// game point, then 11.
class _ScoreHero extends _Hero {
  const _ScoreHero({required super.active});

  @override
  Duration get length => const Duration(milliseconds: 3000);

  @override
  State<_ScoreHero> createState() => _ScoreHeroState();
}

class _ScoreHeroState extends _HeroState<_ScoreHero> {
  @override
  Widget build(BuildContext context) {
    final palette = OnboardPalette.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = controller.value;
        final card = _span(t, 0.0, 0.25);
        final you = t < 0.45 ? 9 : (t < 0.72 ? 10 : 11);
        final won = t >= 0.72;
        return LayoutBuilder(
          builder: (context, box) {
            final width = math.min(box.maxWidth, 340.0);
            return SizedBox(
              width: width,
              height: math.min(box.maxHeight, 260),
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: CustomPaint(painter: _ArcPainter(t: _span(t, 0.18, 0.7, Curves.easeInOutSine), palette: palette)),
                  ),
                  Opacity(
                    opacity: card,
                    child: Transform.scale(
                      scale: 0.92 + 0.08 * card,
                      child: _Scoreboard(you: you, them: 9, won: won, width: width),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _Scoreboard extends StatelessWidget {
  const _Scoreboard({required this.you, required this.them, required this.won, required this.width});

  final int you;
  final int them;
  final bool won;
  final double width;

  @override
  Widget build(BuildContext context) {
    final palette = OnboardPalette.of(context);
    Widget side(String name, int score, {required bool lead}) => Expanded(
          child: Column(
            children: [
              Text(name, style: SkorxType.label(color: palette.inkMuted, size: 12)),
              const SizedBox(height: 6),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                transitionBuilder: (child, a) => ClipRect(
                  child: SlideTransition(
                    position: Tween(begin: const Offset(0, 0.6), end: Offset.zero).animate(a),
                    child: FadeTransition(opacity: a, child: child),
                  ),
                ),
                child: Text(
                  '$score',
                  key: ValueKey(score),
                  style: SkorxType.score(72, color: lead ? palette.ink : palette.inkMuted),
                ),
              ),
            ],
          ),
        );

    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
      child: SizedBox(
        width: width * 0.86,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: won ? palette.accentText : palette.error),
                ),
                const SizedBox(width: 6),
                Text(won ? 'MATCH WON' : 'LIVE · GAME 3', style: SkorxType.label(color: palette.ink, size: 12)),
                const Spacer(),
                Text('BEST OF 3', style: SkorxType.label(color: palette.inkMuted, size: 11)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                side('YOU', you, lead: true),
                Container(width: 1, height: 64, color: palette.glassBorder),
                side('RIVAL', them, lead: false),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A ball lobbing over the scoreboard, with a fading trail.
class _ArcPainter extends CustomPainter {
  _ArcPainter({required this.t, required this.palette});

  final double t;
  final OnboardPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    // A shot hit from in front of the viewer, rising over the scoreboard and
    // dropping away into the far court: big and close first, small and far
    // at the end.
    final start = Offset(size.width * 0.12, size.height * 1.15);
    final control = Offset(size.width * 0.45, -size.height * 0.6);
    final end = Offset(size.width * 0.78, size.height * 0.02);
    Offset at(double f) {
      final u = 1 - f;
      return start * (u * u) + control * (2 * u * f) + end * (f * f);
    }

    double radiusAt(double f) => 16 - 11 * f;

    for (var i = 8; i >= 1; i--) {
      final g = t - i * 0.022;
      if (g <= 0) continue;
      canvas.drawCircle(
        at(g),
        radiusAt(g) * (1 - i * 0.07),
        Paint()..color = palette.ball.withValues(alpha: 0.16 * (1 - i / 9)),
      );
    }
    canvas.save();
    canvas.translate(at(t).dx, at(t).dy);
    paintPickleball(canvas, radiusAt(t), palette: palette, spin: t * 10);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.t != t || old.palette != palette;
}

// ─── Story 2: the player's world ─────────────────────────────────────────

/// A court seen from above, with the four things a player follows lighting
/// up around it.
class _WorldHero extends _Hero {
  const _WorldHero({required super.active});

  @override
  Duration get length => const Duration(milliseconds: 2600);

  @override
  State<_WorldHero> createState() => _WorldHeroState();
}

class _WorldHeroState extends _HeroState<_WorldHero> {
  static const _items = [
    ('MATCHES', Icons.sports_tennis_rounded, Alignment(-1, -0.92)),
    ('TOURNAMENTS', Icons.emoji_events_outlined, Alignment(1, -0.62)),
    ('RANKINGS', Icons.leaderboard_outlined, Alignment(-1, 0.62)),
    ('ANALYTICS', Icons.insights_rounded, Alignment(1, 0.92)),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = OnboardPalette.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = controller.value;
        return LayoutBuilder(
          builder: (context, box) {
            final size = Size(math.min(box.maxWidth, 360), math.min(box.maxHeight, 300));
            return SizedBox.fromSize(
              size: size,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _TopCourtPainter(
                        draw: _span(t, 0, 0.35, Curves.easeInOutCubic),
                        links: [for (var i = 0; i < _items.length; i++) _span(t, 0.3 + i * 0.12, 0.5 + i * 0.12)],
                        anchors: [for (final item in _items) item.$3],
                        palette: palette,
                        pulse: _span(t, 0.2, 1, Curves.linear),
                      ),
                    ),
                  ),
                  for (var i = 0; i < _items.length; i++)
                    Align(
                      alignment: _items[i].$3,
                      child: _FloatingChip(
                        label: _items[i].$1,
                        icon: _items[i].$2,
                        t: _span(t, 0.36 + i * 0.12, 0.6 + i * 0.12, Curves.easeOutBack),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _FloatingChip extends StatelessWidget {
  const _FloatingChip({required this.label, required this.icon, required this.t});

  final String label;
  final IconData icon;
  final double t;

  @override
  Widget build(BuildContext context) {
    final palette = OnboardPalette.of(context);
    return Opacity(
      opacity: t.clamp(0.0, 1.0),
      child: Transform.scale(
        scale: 0.8 + 0.2 * t,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: palette.isDark ? const Color(0xE60D131C) : const Color(0xF2FFFFFF),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.glassBorder),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: palette.isDark ? 0.3 : 0.06), blurRadius: 16, offset: const Offset(0, 6))],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: palette.accent),
              const SizedBox(width: 7),
              Text(label, style: SkorxType.label(color: palette.ink, size: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopCourtPainter extends CustomPainter {
  _TopCourtPainter({required this.draw, required this.links, required this.anchors, required this.palette, required this.pulse});

  final double draw;
  final List<double> links;
  final List<Alignment> anchors;
  final OnboardPalette palette;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    // A 20 × 44 ft court, turned sideways and tilted a little.
    final h = size.height * 0.46, w = h * 44 / 20 * 0.62;
    final rect = Rect.fromCenter(center: center, width: w, height: h);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = palette.court.withValues(alpha: 0.55);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.transform((Matrix4.identity()
          ..setEntry(3, 2, 0.0015)
          ..rotateX(0.55))
        .storage);
    canvas.translate(-center.dx, -center.dy);

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.inflate(10), const Radius.circular(8)),
      Paint()..color = palette.court.withValues(alpha: 0.06 * draw),
    );
    Path grow(Offset a, Offset b) {
      final m = Offset.lerp(a, b, 0.5)!;
      return Path()
        ..moveTo(Offset.lerp(m, a, draw)!.dx, Offset.lerp(m, a, draw)!.dy)
        ..lineTo(Offset.lerp(m, b, draw)!.dx, Offset.lerp(m, b, draw)!.dy);
    }

    final kitchen = w * 7 / 44;
    final path = Path()
      ..addPath(grow(rect.topLeft, rect.topRight), Offset.zero)
      ..addPath(grow(rect.bottomLeft, rect.bottomRight), Offset.zero)
      ..addPath(grow(rect.topLeft, rect.bottomLeft), Offset.zero)
      ..addPath(grow(rect.topRight, rect.bottomRight), Offset.zero)
      ..addPath(grow(Offset(center.dx - kitchen, rect.top), Offset(center.dx - kitchen, rect.bottom)), Offset.zero)
      ..addPath(grow(Offset(center.dx + kitchen, rect.top), Offset(center.dx + kitchen, rect.bottom)), Offset.zero)
      ..addPath(grow(Offset(rect.left, center.dy), Offset(center.dx - kitchen, center.dy)), Offset.zero)
      ..addPath(grow(Offset(center.dx + kitchen, center.dy), Offset(rect.right, center.dy)), Offset.zero);
    canvas.drawPath(path, line);
    canvas.drawLine(
      Offset(center.dx, rect.top - 6),
      Offset(center.dx, rect.top - 6 + (rect.height + 12) * draw),
      Paint()
        ..strokeWidth = 2.5
        ..color = palette.ink.withValues(alpha: 0.7),
    );
    canvas.restore();

    // Links from the ball at centre court to each floating label.
    for (var i = 0; i < anchors.length; i++) {
      final p = links[i];
      if (p <= 0) continue;
      final a = anchors[i];
      final target = Offset(size.width * (0.5 + a.x * 0.36), size.height * (0.5 + a.y * 0.42));
      canvas.drawLine(
        center,
        Offset.lerp(center, target, p)!,
        Paint()
          ..strokeWidth = 1
          ..color = palette.accent.withValues(alpha: 0.45),
      );
      canvas.drawCircle(Offset.lerp(center, target, p)!, 2.5, Paint()..color = palette.accent);
    }

    // The ball at centre court, with a slow ring pulse.
    if (draw > 0.5) {
      final ring = (pulse * 2) % 1;
      canvas.drawCircle(
        center,
        12 + 26 * ring,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = palette.ball.withValues(alpha: 0.5 * (1 - ring)),
      );
      canvas.save();
      canvas.translate(center.dx, center.dy);
      paintPickleball(canvas, 11, palette: palette, spin: 0.4);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_TopCourtPainter old) => true;
}

// ─── Story 3: SkorX TMS ──────────────────────────────────────────────────

/// How a tournament runs on SkorX TMS, one stage lighting after another
/// along a rail.
class _TmsHero extends _Hero {
  const _TmsHero({required super.active});

  @override
  Duration get length => const Duration(milliseconds: 3000);

  @override
  State<_TmsHero> createState() => _TmsHeroState();
}

class _TmsHeroState extends _HeroState<_TmsHero> {
  static const _stages = [
    ('Tournament', Icons.emoji_events_outlined),
    ('Schedule', Icons.calendar_month_outlined),
    ('Live score', Icons.scoreboard_outlined),
    ('Streaming', Icons.videocam_outlined),
    ('Results', Icons.military_tech_outlined),
    ('Player data', Icons.query_stats_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = controller.value;
        return LayoutBuilder(
          builder: (context, box) {
            final rowHeight = (math.min(box.maxHeight, 320) / _stages.length).clamp(30.0, 50.0);
            return SizedBox(
              width: math.min(box.maxWidth, 340),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < _stages.length; i++)
                    _StageRow(
                      label: _stages[i].$1,
                      icon: _stages[i].$2,
                      height: rowHeight,
                      t: _span(t, i * 0.12, i * 0.12 + 0.22),
                      line: i == _stages.length - 1 ? 0 : _span(t, i * 0.12 + 0.12, i * 0.12 + 0.26),
                      live: i == 2,
                      step: i + 1,
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _StageRow extends StatelessWidget {
  const _StageRow({
    required this.label,
    required this.icon,
    required this.height,
    required this.t,
    required this.line,
    required this.live,
    required this.step,
  });

  final String label;
  final IconData icon;
  final double height;
  final double t;
  final double line;
  final bool live;
  final int step;

  @override
  Widget build(BuildContext context) {
    final palette = OnboardPalette.of(context);
    final node = height * 0.62;
    final lit = t >= 1;
    return SizedBox(
      height: height,
      child: Row(
        children: [
          SizedBox(
            width: node,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                // The rail down to the next stage.
                Positioned(
                  top: node / 2,
                  child: Container(
                    width: 2,
                    height: (height) * line,
                    color: palette.accent.withValues(alpha: 0.6),
                  ),
                ),
                Transform.scale(
                  scale: 0.6 + 0.4 * t,
                  child: Opacity(
                    opacity: t.clamp(0.0, 1.0),
                    child: Container(
                      width: node,
                      height: node,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: lit ? palette.accent : palette.canvas,
                        border: Border.all(color: palette.accent, width: 1.5),
                        boxShadow: lit && palette.isDark
                            ? [BoxShadow(color: palette.accent.withValues(alpha: 0.45), blurRadius: 12)]
                            : null,
                      ),
                      child: Icon(icon, size: node * 0.52, color: lit ? Colors.white : palette.accent),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Opacity(
              opacity: t.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(12 * (1 - t), -height * 0.19),
                child: Row(
                  children: [
                    Text(
                      step.toString().padLeft(2, '0'),
                      style: SkorxType.score(14, color: palette.inkFaint),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        label.toUpperCase(),
                        overflow: TextOverflow.ellipsis,
                        style: SkorxType.label(color: palette.ink, size: 16).copyWith(letterSpacing: 1.8),
                      ),
                    ),
                    if (live && lit) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: palette.error, borderRadius: BorderRadius.circular(4)),
                        child: Text('LIVE', style: SkorxType.label(color: Colors.white, size: 10)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Get started ─────────────────────────────────────────────────────────

class _GetStarted extends StatelessWidget {
  const _GetStarted({required this.active, required this.onStart, required this.onExplore});

  final bool active;
  final VoidCallback onStart;
  final VoidCallback onExplore;

  @override
  Widget build(BuildContext context) {
    final palette = OnboardPalette.of(context);
    final statement = OnboardType.statement(context, palette.ink, max: 50);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _DinkHero(active: active)),
          _Entrance(
            active: active,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("YOU'RE ONE STEP AWAY", style: OnboardType.eyebrow(palette.accent)),
                const SizedBox(height: 12),
                Semantics(
                  header: true,
                  label: 'Ready to step onto the court?',
                  excludeSemantics: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FitLine('READY TO STEP', style: statement),
                      _FitLine('ONTO THE COURT?', style: statement.copyWith(color: palette.accentText)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Create your SkorX profile and start tracking your pickleball journey.',
                  style: OnboardType.body(palette.inkMuted),
                ),
                const SizedBox(height: 24),
                OnboardButton(
                  key: const Key('getStarted'),
                  label: 'Get started',
                  icon: Icons.arrow_forward_rounded,
                  onPressed: onStart,
                ),
                const SizedBox(height: 4),
                Center(
                  child: TextButton(
                    key: const Key('exploreSkorx'),
                    onPressed: onExplore,
                    style: TextButton.styleFrom(foregroundColor: palette.inkMuted, minimumSize: const Size(48, 48)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            'Explore SkorX first',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: palette.ink, fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(Icons.arrow_forward_rounded, size: 18, color: palette.ink),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The hero of Get Started: a paddle keeping a ball up, tap after tap, in a
/// pool of light over the court. It loops quietly; still under reduced
/// motion.
class _DinkHero extends StatefulWidget {
  const _DinkHero({required this.active});

  final bool active;

  @override
  State<_DinkHero> createState() => _DinkHeroState();
}

class _DinkHeroState extends State<_DinkHero> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_DinkHero old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) _sync();
  }

  void _sync() {
    if (reduceMotion(context) || !widget.active) {
      _c.stop();
      if (reduceMotion(context)) _c.value = 0.5;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = OnboardPalette.of(context);
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(painter: _DinkPainter(_c, palette), size: Size.infinite),
      ),
    );
  }
}

class _DinkPainter extends CustomPainter {
  _DinkPainter(this.t, this.palette) : super(repaint: t);

  final Animation<double> t;
  final OnboardPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    // Sized so the grip ends above the text below the hero.
    final length = math.min(size.height * 0.5, size.width * 0.55).clamp(70.0, 240.0);
    final face = Offset(size.width * 0.5, size.height * 0.5);
    final ballR = length * 0.1;
    final top = size.height * 0.08 + ballR;

    // Light pooling under the paddle.
    canvas.drawOval(
      Rect.fromCenter(center: face + Offset(0, length * 0.55), width: length * 1.9, height: length * 0.42),
      Paint()
        ..shader = ui.Gradient.radial(face + Offset(0, length * 0.55), length * 0.95, [
          palette.accent.withValues(alpha: palette.isDark ? 0.28 : 0.16),
          palette.accent.withValues(alpha: 0),
        ]),
    );

    // One tap per loop, the paddle doing the work: it sinks under the
    // falling ball, rises and tilts up through the contact (brushing it, so
    // the ball leaves spinning), follows through, and settles again.
    final p = t.value;
    final wave = 2 * math.pi * p;
    Offset paddleAt(double w) => face + Offset(length * 0.05 * math.sin(w), -length * 0.07 * math.cos(w - 0.12));
    final paddle = paddleAt(wave);
    final angle = -0.16 + 0.24 * math.sin(wave - 0.1);

    // The ball meets the face where the paddle is at the moment of contact.
    final contact = paddleAt(0) - Offset(0, ballR + length * 0.02);
    final rise = 4 * p * (1 - p);
    final ball = Offset(contact.dx, contact.dy - (contact.dy - top) * rise);
    final near = 1 - rise;

    paintPaddle(canvas, paddle, length: length, angle: angle, palette: palette);

    // Ball shadow on the face, sharper as it comes down.
    canvas.drawOval(
      Rect.fromCenter(
        center: paddle + Offset(ballR * 0.2, 0),
        width: ballR * (1.2 + 0.8 * near),
        height: ballR * (0.5 + 0.3 * near),
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35 * near)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, ballR * 0.3),
    );

    // Contact ring.
    final fromContact = math.min(p, 1 - p);
    final ring = fromContact < 0.12 ? 1 - fromContact / 0.12 : 0.0;
    if (ring > 0) {
      canvas.drawOval(
        Rect.fromCenter(
          center: paddle,
          width: ballR * (2 + 3 * (1 - ring)),
          height: ballR * (0.9 + 1.2 * (1 - ring)),
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = palette.ball.withValues(alpha: 0.7 * ring),
      );
    }

    canvas.save();
    canvas.translate(ball.dx, ball.dy);
    final squash = fromContact < 0.03 ? 0.12 : 0.0;
    canvas.scale(1 + squash, 1 - squash);
    // Spun hard by the brush, slowing as it rises and falls.
    final spin = 2 * math.pi * 1.8 * (1 - (1 - p) * (1 - p));
    paintPickleball(canvas, ballR, palette: palette, spin: spin);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DinkPainter old) => old.palette != palette;
}

