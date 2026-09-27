import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../design/design.dart';
import '../auth/auth_controller.dart';

/// The first-run walk through the Player app: one card per tab, with the tab
/// lit up in the bottom bar, the way first-time scoring gets its cards.
///
/// A new player gets it once, right after their profile is built; anyone can
/// replay it from Settings › Support. The pending flag is saved, so a player
/// who closes the app mid-welcome still gets the tour next time.
@immutable
class AppTourState {
  const AppTourState({this.active = false, this.step = 0});

  final bool active;
  final int step;
}

final appTourProvider = NotifierProvider<AppTourController, AppTourState>(AppTourController.new);

class AppTourController extends Notifier<AppTourState> {
  static const _key = 'skorx.appTour.pending';

  @override
  AppTourState build() {
    _restore();
    return const AppTourState();
  }

  Future<void> _restore() async {
    try {
      if (await ref.read(preferencesProvider).getBool(_key) == true) state = const AppTourState(active: true);
    } catch (_) {
      // No saved flag: no tour.
    }
  }

  /// A new player: show the tour when the app opens on Home.
  Future<void> queue() async {
    state = const AppTourState(active: true);
    await ref.read(preferencesProvider).setBool(_key, true);
  }

  /// Replay from Settings.
  void start() => state = const AppTourState(active: true);

  void next() => state = AppTourState(active: true, step: state.step + 1);

  void back() => state = AppTourState(active: true, step: math.max(0, state.step - 1));

  Future<void> finish() async {
    state = const AppTourState();
    await ref.read(preferencesProvider).setBool(_key, false);
  }
}

/// The Player bottom bar's tabs, so the tour can light one up. Only the
/// Player shell attaches them (there is one Player shell at a time).
final appTourTabKeys = List.generate(5, (i) => GlobalKey(debugLabel: 'tourTab$i'));

class _Stop {
  const _Stop(this.tab, this.icon, this.kicker, this.title, this.body, this.points);

  /// The bottom-bar tab this stop is about, or null for a card on its own.
  final int? tab;
  final IconData icon;
  final String kicker;
  final String title;
  final String body;
  final List<String> points;
}

const _stops = [
  _Stop(null, Icons.waving_hand_rounded, 'WELCOME', 'Your pickleball world',
      'A 30-second tour of where everything lives. You can skip any time.', []),
  _Stop(0, Icons.home_rounded, 'HOME', 'Your day at a glance',
      'Everything happening for you right now, and one tap to get playing.', [
    'Start a casual match and score it on this phone',
    'Your live and next matches up top',
    'Your SkorX Rating: how good you are right now',
  ]),
  _Stop(1, Icons.scoreboard_rounded, 'MATCHES', 'Every score, live',
      'Follow matches across SkorX as they happen, point by point.', [
    'Live scores and streams',
    'Results from your city and tournaments',
    'Tap any player to size them up',
  ]),
  _Stop(2, Icons.explore_rounded, 'EXPLORE', 'Find your next game',
      'Tournaments, courts, scores, and the whole pickleball community.', [
    'Book a court in three taps',
    'Enter tournaments near you',
    'Community: find referees, coaches, clubs and partners',
  ]),
  _Stop(3, Icons.sports_tennis_rounded, 'MY PADDLE', 'Your journey',
      'Only your matches, and how far you have come.', [
    'Casual and tournament records',
    'SkorX Rating, rankings and SkorX Points',
    'Achievements to unlock as you play',
  ]),
  _Stop(4, Icons.person_rounded, 'ACCOUNT', 'Your player card',
      'Your X code, your photo and how SkorX works for you.', [
    'Share your X code to be added to matches',
    'Change your profile photo',
    'Set default match rules in Settings',
  ]),
  _Stop(null, Icons.sports_score_rounded, "YOU'RE SET", 'Time to play',
      'Score your first match: pick players, tap the side that wins each rally, SkorX does the rest.', []),
];

/// Draws the tour over the Player shell when it is running.
class AppTourLayer extends ConsumerWidget {
  const AppTourLayer({super.key, required this.onSelectTab});

  /// Switches the page behind the card to the tab being described.
  final ValueChanged<int> onSelectTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tour = ref.watch(appTourProvider);
    if (!tour.active) return const SizedBox.shrink();
    return _TourOverlay(step: tour.step.clamp(0, _stops.length - 1), onSelectTab: onSelectTab);
  }
}

class _TourOverlay extends ConsumerStatefulWidget {
  const _TourOverlay({required this.step, required this.onSelectTab});

  final int step;
  final ValueChanged<int> onSelectTab;

  @override
  ConsumerState<_TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends ConsumerState<_TourOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  Rect? _spot;

  @override
  void initState() {
    super.initState();
    _enter();
  }

  @override
  void didUpdateWidget(_TourOverlay old) {
    super.didUpdateWidget(old);
    if (old.step != widget.step) _enter();
  }

  void _enter() {
    // After this frame: switching tabs rebuilds the router, which cannot
    // happen mid-build. The tab's place is known once the bar has laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final tab = _stops[widget.step].tab;
      if (tab != null) widget.onSelectTab(tab);
      WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    });
  }

  void _measure() {
    if (!mounted) return;
    final tab = _stops[widget.step].tab;
    Rect? spot;
    final box = tab == null ? null : appTourTabKeys[tab].currentContext?.findRenderObject() as RenderBox?;
    final me = context.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize && me != null && me.hasSize) {
      final topLeft = box.localToGlobal(Offset.zero, ancestor: me);
      spot = (topLeft & box.size).inflate(4);
    }
    setState(() => _spot = spot);
    if (sxAmbientMotion(context)) {
      _pulse.repeat();
    } else {
      _pulse.value = 0.5;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _next() {
    HapticFeedback.selectionClick();
    if (widget.step >= _stops.length - 1) {
      _finish();
    } else {
      ref.read(appTourProvider.notifier).next();
    }
  }

  void _finish({String? then}) {
    ref.read(appTourProvider.notifier).finish();
    widget.onSelectTab(0);
    if (then != null) GoRouter.of(context).push(then);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final i = widget.step;
    final stop = _stops[i];
    final first = i == 0;
    final last = i == _stops.length - 1;
    final spot = stop.tab == null ? null : _spot;
    final name = ref.watch(currentUserProvider)?.firstName ?? '';
    final size = MediaQuery.sizeOf(context);
    // Above the lit tab, or centred when there is no tab to point at.
    final cardBottom = spot == null ? null : size.height - spot.top + 18;

    final card = SxReveal(
      key: ValueKey(i),
      child: Container(
        padding: const EdgeInsets.all(Sx.s20),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(Sx.radiusLg),
          border: Border.all(color: c.voltFill.withValues(alpha: 0.5)),
          boxShadow: c.glowOf(c.voltFill, strength: 0.6),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (first || last)
                  const SxBall(size: 40, float: false)
                else
                  SxIconTile(icon: stop.icon, size: 44, colors: [c.voltFill, c.olive], solid: true),
                const SizedBox(width: Sx.s12),
                Expanded(child: Text(stop.kicker, style: SxType.label(c.volt, size: 13))),
                _Dots(count: _stops.length, at: i),
              ],
            ),
            const SizedBox(height: Sx.s16),
            Text(
              first && name.isNotEmpty ? 'Welcome, $name' : stop.title,
              style: SxType.title(c.ink, size: 30),
            ),
            if (first) Text(stop.title, style: SxType.heading(c.inkMuted, size: 16)),
            const SizedBox(height: Sx.s8),
            Text(stop.body, style: SxType.body(c.inkMuted)),
            if (stop.points.isNotEmpty) ...[
              const SizedBox(height: Sx.s12),
              for (final p in stop.points)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Icon(Icons.check_circle_rounded, size: 16, color: c.volt),
                      ),
                      const SizedBox(width: Sx.s8),
                      Expanded(child: Text(p, style: SxType.body(c.ink, size: 14))),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: Sx.s16),
            Row(
              children: [
                if (last)
                  SxButton.quiet(key: const Key('tourDone'), label: 'Look around', onPressed: _finish)
                else if (first)
                  SxButton.quiet(key: const Key('tourSkip'), label: 'Skip', onPressed: _finish)
                else
                  SxButton.quiet(
                    key: const Key('tourBack'),
                    label: 'Back',
                    onPressed: () => ref.read(appTourProvider.notifier).back(),
                  ),
                const SizedBox(width: Sx.s12),
                Expanded(
                  child: SxButton(
                    key: const Key('tourNext'),
                    label: last ? 'Start a match' : (first ? 'Show me' : 'Next'),
                    icon: last ? Icons.play_arrow_rounded : null,
                    height: 48,
                    onPressed: last ? () => _finish(then: '/player/match/new') : _next,
                  ),
                ),
              ],
            ),
            if (!first && !last)
              Center(
                child: Tappable(
                  key: const Key('tourSkipAll'),
                  onTap: _finish,
                  child: Padding(
                    padding: const EdgeInsets.only(top: Sx.s8),
                    child: Text('Skip tour', style: SxType.caption(c.inkFaint, size: 12)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // The dim, with a hole over the tab being described. Tapping the
          // lit tab moves on, like tapping Next.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) {
                if (spot != null && spot.contains(d.localPosition)) _next();
              },
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (_, _) => CustomPaint(
                  painter: _SpotlightPainter(spot: spot, pulse: _pulse.value, ring: c.voltFill),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: cardBottom,
            top: cardBottom == null ? 0 : null,
            child: SafeArea(
              bottom: cardBottom == null,
              child: Align(
                alignment: cardBottom == null ? Alignment.center : Alignment.bottomCenter,
                child: SxWidth(
                  child: Padding(padding: const EdgeInsets.symmetric(horizontal: Sx.s16), child: card),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.at});

  final int count;
  final int at;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: Sx.medium,
            margin: const EdgeInsets.only(left: 4),
            width: i == at ? 16 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i <= at ? c.voltFill : c.line,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  _SpotlightPainter({required this.spot, required this.pulse, required this.ring});

  final Rect? spot;
  final double pulse;
  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Paint()..color = Colors.black.withValues(alpha: 0.72);
    final s = spot;
    if (s == null) {
      canvas.drawRect(Offset.zero & size, dim);
      return;
    }
    final hole = RRect.fromRectAndRadius(s, const Radius.circular(22));
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), Path()..addRRect(hole)),
      dim,
    );
    // A ring that breathes outward from the lit tab.
    final grow = Curves.easeOut.transform(pulse);
    canvas.drawRRect(
      hole.inflate(2 + grow * 10),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = ring.withValues(alpha: 0.9 * (1 - grow)),
    );
    canvas.drawRRect(
      hole,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = ring,
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) => old.spot != spot || old.pulse != pulse || old.ring != ring;
}
