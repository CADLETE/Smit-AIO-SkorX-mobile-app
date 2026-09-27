import 'package:flutter/material.dart';

import '../../../../design/design.dart';
import '../../../../sports/core/score_state.dart';
import '../../live/live_court.dart';
import '../../local_match.dart';
import '../../../../shared/widgets.dart' show SkorxLogo;
import '../court_top_view.dart';
import '../scoring_labels.dart';

/// A tap on a half: flash it, and float "+1" when it scored.
@immutable
class CourtFlash {
  const CourtFlash(this.side, {required this.point, required this.token});

  final Side side;
  final bool point;
  final int token;
}

/// A short call over the net: SIDE OUT, 2ND SERVER, CHANGE ENDS...
@immutable
class CourtBanner {
  const CourtBanner(this.text, {this.detail, required this.token, this.strong = false});

  final String text;
  final String? detail;
  final int token;

  /// Volt, for game and match moments; otherwise navy glass.
  final bool strong;
}

/// The call a recorded rally makes over the net, if any: game won, change
/// ends, side out, second server, game or match point. Shared by the scorer
/// and everyone watching, so both see the same moments.
CourtBanner? rallyBanner(LocalMatch match, LiveStep step, int token) {
  final events = step.events;
  final winner = step.rallyWinner;
  if (events.contains(LiveEvent.matchWon)) return null;
  if (events.contains(LiveEvent.gameWon) && winner != null) {
    final g = step.score.games[step.score.games.length - 2];
    return CourtBanner('GAME ${step.score.gameNumber - 1}',
        detail: '${match.teamLabel(winner)} ${g.of(winner)}–${g.of(winner.opponent)}', token: token, strong: true);
  }
  if (events.contains(LiveEvent.endsSwitched)) {
    return CourtBanner('CHANGE ENDS', detail: 'Halfway in the deciding game', token: token, strong: true);
  }
  if (events.contains(LiveEvent.sideOut)) {
    return CourtBanner('SIDE OUT', detail: '${match.teamLabel(step.court.serveSide)} to serve', token: token);
  }
  if (events.contains(LiveEvent.secondServer)) {
    final name = match.names(step.court.serveSide)[step.court.serverIndex];
    return CourtBanner('2ND SERVER', detail: '${name.split(' ').first} serves', token: token);
  }
  if (events.contains(LiveEvent.serveCorrected)) return CourtBanner('SERVE CORRECTED', token: token);
  CourtBanner? banner;
  for (final side in Side.values) {
    if (isMatchPoint(match, step.score, side)) {
      banner = CourtBanner('MATCH POINT', detail: match.teamLabel(side), token: token, strong: true);
    } else if (isGamePoint(match, step.score, side)) {
      banner ??= CourtBanner('GAME POINT', detail: match.teamLabel(side), token: token);
    }
  }
  return banner;
}

/// The live court from above: the interaction surface. Each team's half is
/// one big button ("this side won the rally"); players stand in their real
/// service courts and slide when they change courts; the ball and SERVE tag
/// sit on the server and a dashed arrow runs to the receiver.
///
/// It is laid out as a landscape court (ends left and right). In portrait,
/// [vertical] turns the court a quarter clockwise so the ends are top and
/// bottom, and turns every label back so text stays upright.
///
/// [spectator] draws the same court for someone watching: nothing to tap,
/// no tap hints, and smaller player markers for a court that shares the
/// screen with the rest of the match.
class LiveCourtView extends StatelessWidget {
  const LiveCourtView({
    super.key,
    required this.match,
    required this.step,
    required this.vertical,
    required this.onRally,
    required this.enabled,
    this.flash,
    this.banner,
    this.spectator = false,
  });

  final LocalMatch match;
  final LiveStep step;
  final bool vertical;
  final ValueChanged<Side> onRally;
  final bool enabled;
  final CourtFlash? flash;
  final CourtBanner? banner;
  final bool spectator;

  static const move = Duration(milliseconds: 380);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final screen = box.biggest;
      final model = vertical ? Size(screen.height, screen.width) : screen;
      Widget court = SizedBox.fromSize(size: model, child: _ModelCourt(view: this, size: model));
      if (vertical) court = RotatedBox(quarterTurns: 1, child: court);
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: court),
          if (banner != null)
            Positioned.fill(
              child: IgnorePointer(child: Center(child: _BannerView(key: ValueKey(banner!.token), banner: banner!))),
            ),
        ],
      );
    });
  }
}

class _ModelCourt extends StatelessWidget {
  const _ModelCourt({required this.view, required this.size});

  final LiveCourtView view;
  final Size size;

  /// Turns a screen-upright child back after the court was rotated.
  Widget _upright(Widget child) => view.vertical ? RotatedBox(quarterTurns: 3, child: child) : child;

  /// A screen size as it measures in model space.
  Size _model(Size s) => view.vertical ? Size(s.height, s.width) : s;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final court = view.step.court;
    final score = view.step.score;
    final match = view.match;
    const pad = 14.0;
    final rect = Rect.fromLTWH(pad, pad, size.width - pad * 2, size.height - pad * 2);
    Offset at(double fx, double fy) => Offset(rect.left + fx * rect.width, rect.top + fy * rect.height);

    Offset spot(Side side, int index) {
      final left = court.onLeft(side);
      final rightHand = court.courtOf(side, index) == ServiceCourt.right;
      // Facing the net from the left end, a player's right hand is the bottom.
      final bottom = left ? rightHand : !rightHand;
      return at(left ? 0.19 : 0.81, bottom ? 0.75 : 0.25);
    }

    final receiving = court.serveSide.opponent;
    final from = spot(court.serveSide, court.serverIndex);
    final to = spot(receiving, court.receiverIndex);
    final over = match.isOver;
    final marker = view.spectator && !view.vertical ? const Size(84, 84) : const Size(104, 104);
    final m = _model(marker);
    const hint = Size(150, 64);
    final h = _model(hint);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: TweenAnimationBuilder<Offset>(
            tween: Tween(end: from),
            duration: LiveCourtView.move,
            curve: Curves.easeInOutCubic,
            builder: (context, f, _) => TweenAnimationBuilder<Offset>(
              tween: Tween(end: to),
              duration: LiveCourtView.move,
              curve: Curves.easeInOutCubic,
              builder: (context, t, _) => CustomPaint(
                painter: CourtSurfacePainter(
                  c: c,
                  court: rect,
                  serveFrom: over ? null : f,
                  serveTo: t,
                  serveColor: c.voltFill,
                  arrowInset: 40,
                ),
              ),
            ),
          ),
        ),

        // The SkorX mark, faint, in each kitchen: branding the court the way
        // real venues paint theirs, without competing with the players.
        for (final end in const [-1.0, 1.0])
          () {
            final kitchen = rect.width * 7 / 44;
            final logoH = view.vertical ? (kitchen * 0.5).clamp(10.0, 34.0) : (kitchen * 0.8 / SkorxLogo.aspectRatio).clamp(10.0, 28.0);
            final s = _model(Size(logoH * SkorxLogo.aspectRatio, logoH));
            final p = at(0.5 + end * 3.5 / 44, 0.5);
            return Positioned(
              left: p.dx - s.width / 2,
              top: p.dy - s.height / 2,
              width: s.width,
              height: s.height,
              child: IgnorePointer(
                child: _upright(Opacity(opacity: 0.3, child: SkorxLogo(height: logoH))),
              ),
            );
          }(),

        // Service court names, so left and right never need working out.
        for (final side in Side.values)
          for (final sc in ServiceCourt.values)
            () {
              final left = court.onLeft(side);
              final bottom = left ? sc == ServiceCourt.right : sc == ServiceCourt.left;
              final p = at(left ? 0.31 : 0.69, bottom ? 0.93 : 0.07);
              final s = _model(const Size(44, 14));
              return Positioned(
                left: p.dx - s.width / 2,
                top: p.dy - s.height / 2,
                width: s.width,
                height: s.height,
                child: IgnorePointer(
                  child: _upright(Center(
                    child: Text(sc.label.toUpperCase(),
                        style: SxType.label(Colors.white.withValues(alpha: 0.45), size: 10.5)),
                  )),
                ),
              );
            }(),

        // The two halves: the whole of each is the button.
        for (final side in Side.values)
          Positioned(
            left: court.onLeft(side) ? 0 : size.width / 2,
            top: 0,
            width: size.width / 2,
            height: size.height,
            child: _TapHalf(
              side: side,
              enabled: view.enabled && !over && !view.spectator,
              label: '${match.teamLabel(side)} won the rally. ${rallyActionLabel(match, score, side)}',
              onTap: () => view.onRally(side),
              flash: view.flash?.side == side ? view.flash : null,
              atLeft: court.onLeft(side),
              upright: _upright,
            ),
          ),

        // Team name and what a tap does, at each baseline.
        for (final side in Side.values)
          () {
            final p = at(court.onLeft(side) ? 0.075 : 0.925, 0.5);
            return Positioned(
              left: p.dx - h.width / 2,
              top: p.dy - h.height / 2,
              width: h.width,
              height: h.height,
              child: IgnorePointer(child: _upright(_BaselineHint(match: match, score: score, side: side, tapHint: !view.spectator))),
            );
          }(),

        // Players.
        for (final side in Side.values)
          for (var i = 0; i < match.names(side).length; i++)
            () {
              final p = spot(side, i);
              final serving = !over && side == court.serveSide && i == court.serverIndex;
              final receiving = !over && side == court.serveSide.opponent && i == court.receiverIndex;
              return AnimatedPositioned(
                key: ValueKey('player-${side.name}$i'),
                duration: LiveCourtView.move,
                curve: Curves.easeInOutCubic,
                left: p.dx - m.width / 2,
                top: p.dy - m.height / 2,
                width: m.width,
                height: m.height,
                child: IgnorePointer(
                  child: _upright(_PlayerMarker(
                    key: Key('marker-${side.name}$i'),
                    name: match.names(side)[i],
                    color: CourtTopView.teamColor(c, side),
                    serving: serving,
                    receiving: receiving,
                    serverNumber: serving ? score.serve.serverNumber : null,
                  )),
                ),
              );
            }(),
      ],
    );
  }
}

class _TapHalf extends StatelessWidget {
  const _TapHalf({
    required this.side,
    required this.enabled,
    required this.label,
    required this.onTap,
    required this.flash,
    required this.atLeft,
    required this.upright,
  });

  final Side side;
  final bool enabled;
  final String label;
  final VoidCallback onTap;
  final CourtFlash? flash;
  final bool atLeft;
  final Widget Function(Widget) upright;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final color = CourtTopView.teamColor(c, side);
    final f = flash;
    return Semantics(
      button: enabled,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        key: Key('side-${side.name}'),
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: Stack(
          children: [
            if (f != null)
              Positioned.fill(
                child: TweenAnimationBuilder<double>(
                  key: ValueKey('flash${f.token}'),
                  tween: Tween(begin: 1, end: 0),
                  duration: const Duration(milliseconds: 520),
                  curve: Curves.easeOut,
                  builder: (context, v, _) => DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(atLeft ? -0.3 : 0.3, 0),
                        radius: 0.9,
                        colors: [color.withValues(alpha: 0.42 * v), color.withValues(alpha: 0.12 * v)],
                      ),
                    ),
                  ),
                ),
              ),
            if (f != null && f.point)
              Positioned.fill(
                child: Align(
                  alignment: Alignment(atLeft ? 0.35 : -0.35, 0),
                  child: upright(
                    TweenAnimationBuilder<double>(
                      key: ValueKey('plus${f.token}'),
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 700),
                      curve: Curves.easeOutCubic,
                      builder: (context, v, child) => Opacity(
                        opacity: (1 - v).clamp(0, 1),
                        child: Transform.translate(offset: Offset(0, -34 * v), child: Transform.scale(scale: 0.8 + 0.4 * v, child: child)),
                      ),
                      child: Text('+1', style: SxType.number(44, color, weight: FontWeight.w800).copyWith(
                        shadows: [Shadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 12)],
                      )),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BaselineHint extends StatelessWidget {
  const _BaselineHint({required this.match, required this.score, required this.side, this.tapHint = true});

  final LocalMatch match;
  final ScoreState score;
  final Side side;

  /// What a tap does, for the scorer; people watching only see the calls.
  final bool tapHint;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final color = CourtTopView.teamColor(c, side);
    final matchPoint = isMatchPoint(match, score, side);
    final gamePoint = !matchPoint && isGamePoint(match, score, side);
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (matchPoint || gamePoint)
            Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(gradient: c.brand, borderRadius: BorderRadius.circular(10)),
              child: Text(matchPoint ? 'MATCH POINT' : 'GAME POINT', style: SxType.label(c.onVolt, size: 11)),
            ),
          if (tapHint && !match.isOver) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.fromLTRB(7, 4, 10, 4),
              decoration: BoxDecoration(
                color: const Color(0xB3060A10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.touch_app_rounded, size: 14, color: color),
                  const SizedBox(width: 4),
                  Text(rallyActionLabel(match, score, side), style: SxType.label(Colors.white, size: 12)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlayerMarker extends StatelessWidget {
  const _PlayerMarker({
    super.key,
    required this.name,
    required this.color,
    required this.serving,
    required this.receiving,
    this.serverNumber,
  });

  final String name;
  final Color color;
  final bool serving;
  final bool receiving;
  final int? serverNumber;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    const dp = 50.0;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: dp + 16,
            height: dp + 6,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                if (serving) const _ServeHalo(size: dp + 14),
                PlayerDp(name: name, size: dp, edge: serving ? c.voltFill : color),
                AnimatedSwitcher(
                  duration: Sx.medium,
                  transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
                  child: serving
                      ? const Align(
                          key: ValueKey('ball'),
                          alignment: Alignment(1.05, -1.1),
                          child: SxBall(size: 20, float: false, glow: false),
                        )
                      : const SizedBox(key: ValueKey('none')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 3),
          Container(
            constraints: const BoxConstraints(maxWidth: 100),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: const Color(0xD9060A10), borderRadius: BorderRadius.circular(8)),
            child: Text(
              name.trim().split(' ').first,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: SxType.sans, fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white),
            ),
          ),
          const SizedBox(height: 3),
          SizedBox(
            height: 17,
            child: AnimatedSwitcher(
              duration: Sx.medium,
              child: serving
                  ? _RoleTag(
                      key: const ValueKey('serve'),
                      text: serverNumber == null ? 'SERVE' : 'SERVE · $serverNumber',
                      fill: c.voltFill,
                      ink: c.onVolt,
                    )
                  : receiving
                      ? _RoleTag(key: const ValueKey('receive'), text: 'RECEIVE', fill: Colors.white.withValues(alpha: 0.9), ink: c.onVolt)
                      : const SizedBox(key: ValueKey('none')),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleTag extends StatelessWidget {
  const _RoleTag({super.key, required this.text, required this.fill, required this.ink});

  final String text;
  final Color fill;
  final Color ink;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(7)),
        child: Text(text, style: SxType.label(ink, size: 11).copyWith(fontWeight: FontWeight.w800)),
      );
}

/// A soft volt pulse behind the server. Still when motion is reduced.
class _ServeHalo extends StatefulWidget {
  const _ServeHalo({required this.size});

  final double size;

  @override
  State<_ServeHalo> createState() => _ServeHaloState();
}

class _ServeHaloState extends State<_ServeHalo> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (sxAmbientMotion(context)) {
      _c.repeat();
    } else {
      _c.value = 0.3;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final volt = context.sx.voltFill;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = Curves.easeOut.transform(_c.value);
        return Container(
          width: widget.size * (0.9 + 0.35 * t),
          height: widget.size * (0.9 + 0.35 * t),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: volt.withValues(alpha: 0.28 * (1 - t)),
            border: Border.all(color: volt.withValues(alpha: 0.6 * (1 - t)), width: 2),
          ),
        );
      },
    );
  }
}

class _BannerView extends StatefulWidget {
  const _BannerView({super.key, required this.banner});

  final CourtBanner banner;

  @override
  State<_BannerView> createState() => _BannerViewState();
}

class _BannerViewState extends State<_BannerView> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: Duration(milliseconds: widget.banner.strong ? 1900 : 1300))
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed && mounted) setState(() => _done = true);
        })
        ..forward();

  /// Gone once shown, so screen readers and finders don't meet a ghost.
  bool _done = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return const SizedBox.shrink();
    final c = context.sx;
    final b = widget.banner;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = _c.value;
        final opacity = t < 0.12 ? t / 0.12 : (t > 0.8 ? (1 - t) / 0.2 : 1.0);
        final scale = t < 0.12 ? 0.85 + 0.15 * Curves.easeOutBack.transform(t / 0.12) : 1.0;
        return Opacity(opacity: opacity.clamp(0, 1), child: Transform.scale(scale: scale, child: child));
      },
      child: Semantics(
        liveRegion: true,
        label: [b.text, if (b.detail != null) b.detail].join('. '),
        excludeSemantics: true,
        child: Container(
          key: const Key('courtBanner'),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
          decoration: BoxDecoration(
            gradient: b.strong ? c.brand : null,
            color: b.strong ? null : const Color(0xE6060A10),
            borderRadius: BorderRadius.circular(18),
            border: b.strong ? null : Border.all(color: c.voltFill.withValues(alpha: 0.7), width: 1.5),
            boxShadow: c.glowOf(c.voltFill, strength: b.strong ? 1 : 0.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(b.text, style: SxType.verdict(30, b.strong ? c.onVolt : c.voltFill)),
              if (b.detail != null)
                Text(b.detail!, style: SxType.caption(b.strong ? c.onVolt : Colors.white, size: 13).copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}
