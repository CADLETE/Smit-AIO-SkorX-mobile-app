import 'package:flutter/material.dart';

import '../../../design/design.dart';
import '../../../sports/core/score_state.dart';
import '../data/match_setup.dart';

/// The court seen from above, net down the middle, as the scorer sees it
/// from the side. Each team's players stand in their service courts with
/// their picture and name, and a dashed arrow shows the first serve going
/// cross-court.
///
/// A team's list is in court order: index 0 stands in the team's
/// right-hand service court (where the first serve is hit from), index 1 in
/// the left. Facing the net, the left-end team's right hand is the bottom of
/// the drawing and the right-end team's is the top.
class CourtTopView extends StatelessWidget {
  const CourtTopView({
    super.key,
    required this.teamA,
    required this.teamB,
    required this.aOnLeft,
    required this.server,
    required this.onSlotTap,
    this.teamNameA,
    this.teamNameB,
    this.onTeamNameTap,
    this.emptyLabel,
  });

  final List<MatchPlayer?> teamA;
  final List<MatchPlayer?> teamB;
  final bool aOnLeft;

  /// The side that serves first; its right-hand player is the server.
  final Side server;
  final void Function(Side side, int index) onSlotTap;
  final String? teamNameA;
  final String? teamNameB;

  /// Renaming a team; null hides the pencil.
  final ValueChanged<Side>? onTeamNameTap;

  /// What an empty slot says, e.g. "Add man" in mixed doubles.
  final String Function(Side side, int index)? emptyLabel;

  static Color teamColor(SxColors c, Side side) => side == Side.a ? c.cyan : c.voltFill;

  List<MatchPlayer?> _team(Side side) => side == Side.a ? teamA : teamB;

  bool _onLeft(Side side) => side == Side.a ? aOnLeft : !aOnLeft;

  /// Where slot [index] of [side] stands, as fractions of the court.
  Offset _spot(Side side, int index) {
    final left = _onLeft(side);
    final x = left ? 0.18 : 0.82;
    final rightHand = index == 0;
    // Left end faces right: its right hand is the bottom half.
    final bottom = left ? rightHand : !rightHand;
    return Offset(x, bottom ? 0.75 : 0.25);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Column(
      children: [
        Row(
          children: [
            for (final side in aOnLeft ? const [Side.a, Side.b] : const [Side.b, Side.a])
              Expanded(
                child: Align(
                  alignment: _onLeft(side) ? Alignment.centerLeft : Alignment.centerRight,
                  child: _TeamTag(
                    side: side,
                    name: (side == Side.a ? teamNameA : teamNameB) ?? (side == Side.a ? 'TEAM A' : 'TEAM B'),
                    serving: side == server,
                    onTap: onTeamNameTap == null ? null : () => onTeamNameTap!(side),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: Sx.s8),
        LayoutBuilder(builder: (context, box) {
          final w = box.maxWidth;
          final h = (w / 1.72).clamp(170.0, 280.0);
          const pad = 10.0;
          final court = Rect.fromLTWH(pad, pad, w - pad * 2, h - pad * 2);
          Offset at(Offset f) => Offset(court.left + f.dx * court.width, court.top + f.dy * court.height);
          final serverTeam = _team(server);
          final receiver = server.opponent;
          final from = at(_spot(server, 0));
          final to = at(_spot(receiver, 0));
          const slotW = 78.0;
          const slotH = 70.0;

          return SizedBox(
            height: h,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: TweenAnimationBuilder<Offset>(
                    tween: Tween(end: from),
                    duration: Sx.slow,
                    curve: Curves.easeInOutCubic,
                    builder: (context, animFrom, _) => TweenAnimationBuilder<Offset>(
                      tween: Tween(end: to),
                      duration: Sx.slow,
                      curve: Curves.easeInOutCubic,
                      builder: (context, animTo, _) => CustomPaint(
                        painter: CourtSurfacePainter(
                          c: c,
                          court: court,
                          serveFrom: serverTeam.isEmpty || serverTeam.first == null ? null : animFrom,
                          serveTo: animTo,
                          serveColor: teamColor(c, server),
                        ),
                      ),
                    ),
                  ),
                ),
                for (final side in Side.values)
                  for (final (i, player) in _team(side).indexed)
                    AnimatedPositioned(
                      key: ValueKey('slot-${side.name}-${player?.id ?? 'empty$i'}'),
                      duration: Sx.slow,
                      curve: Curves.easeInOutCubic,
                      left: at(_spot(side, i)).dx - slotW / 2,
                      top: at(_spot(side, i)).dy - slotH / 2,
                      width: slotW,
                      height: slotH,
                      child: _Slot(
                        key: Key('court-${side.name}$i'),
                        player: player,
                        side: side,
                        serving: side == server && i == 0,
                        emptyLabel: emptyLabel?.call(side, i) ?? 'Add player',
                        onTap: () => onSlotTap(side, i),
                      ),
                    ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

class _TeamTag extends StatelessWidget {
  const _TeamTag({required this.side, required this.name, required this.serving, this.onTap});

  final Side side;
  final String name;
  final bool serving;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final color = CourtTopView.teamColor(c, side);
    return Semantics(
      button: onTap != null,
      label: 'Team name $name${onTap == null ? '' : ', rename'}',
      excludeSemantics: true,
      child: Tappable(
        onTap: onTap,
        radius: 14,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 160),
          padding: const EdgeInsets.fromLTRB(10, 5, 8, 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: c.isDark ? 0.12 : 0.18),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(name.toUpperCase(),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.label(c.ink, size: 12)),
              ),
              if (onTap != null) ...[const SizedBox(width: 4), Icon(Icons.edit_rounded, size: 12, color: c.inkMuted)],
            ],
          ),
        ),
      ),
    );
  }
}

class _Slot extends StatelessWidget {
  const _Slot({
    super.key,
    required this.player,
    required this.side,
    required this.serving,
    required this.emptyLabel,
    required this.onTap,
  });

  final MatchPlayer? player;
  final Side side;
  final bool serving;
  final String emptyLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final color = CourtTopView.teamColor(c, side);
    final p = player;
    const dp = 40.0;
    final name = p == null ? emptyLabel : (p.isMe ? 'You' : p.name.split(' ').first);

    return Semantics(
      button: true,
      label: p == null ? emptyLabel : '${p.name}${serving ? ', serves first' : ''}',
      excludeSemantics: true,
      child: Tappable(
        onTap: onTap,
        radius: 16,
        // Scales down rather than overflowing under large system text.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: dp + 12,
              height: dp + 6,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  if (p == null)
                    Container(
                      width: dp,
                      height: dp,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.08),
                        border: Border.all(color: color.withValues(alpha: 0.85), width: 1.6),
                      ),
                      child: Icon(Icons.add_rounded, color: color, size: 22),
                    )
                  else
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: serving ? c.glowOf(c.voltFill, strength: 1.2) : null,
                      ),
                      child: SxPop(child: PlayerDp(name: p.isMe ? 'You' : p.name, size: dp, edge: color)),
                    ),
                  if (serving && p != null)
                    const Positioned(right: -1, top: -3, child: SxBall(size: 18, float: false, glow: false)),
                ],
              ),
            ),
            const SizedBox(height: 3),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: p == null ? Colors.transparent : const Color(0xCC060A10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: SxType.sans,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: p == null ? color : Colors.white,
                ),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

/// Court surface, lines, the net and the serve arrow. Always drawn on navy
/// so it reads the same in light and dark themes.
class CourtSurfacePainter extends CustomPainter {
  CourtSurfacePainter({
    required this.c,
    required this.court,
    required this.serveFrom,
    required this.serveTo,
    required this.serveColor,
    this.arrowInset = 30,
  });

  /// How far the serve arrow stays clear of the players' pictures.
  final double arrowInset;

  final SxColors c;
  final Rect court;
  final Offset? serveFrom;
  final Offset serveTo;
  final Color serveColor;

  // Pickleball court: 44 ft long, the kitchen 7 ft either side of the net.
  static const _kitchen = 7 / 44;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = (Offset.zero & size);
    canvas.drawRRect(
      RRect.fromRectAndRadius(outer, const Radius.circular(Sx.radius)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF09121E), Color(0xFF0F2A4A)],
        ).createShader(outer),
    );
    canvas.drawRect(
      court,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color.lerp(const Color(0xFF0F2A4A), c.blue, 0.45)!,
            Color.lerp(const Color(0xFF0F2A4A), c.blue, 0.25)!,
            Color.lerp(const Color(0xFF0F2A4A), c.blue, 0.45)!,
          ],
        ).createShader(court),
    );
    double x(double f) => court.left + f * court.width;
    final kL = x(0.5 - _kitchen);
    final kR = x(0.5 + _kitchen);
    // The kitchen (non-volley zone), tinted cyan.
    canvas.drawRect(Rect.fromLTRB(kL, court.top, kR, court.bottom), Paint()..color = c.cyan.withValues(alpha: 0.16));

    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    canvas.drawRect(court, line);
    canvas.drawLine(Offset(kL, court.top), Offset(kL, court.bottom), line);
    canvas.drawLine(Offset(kR, court.top), Offset(kR, court.bottom), line);
    canvas.drawLine(Offset(court.left, court.center.dy), Offset(kL, court.center.dy), line);
    canvas.drawLine(Offset(kR, court.center.dy), Offset(court.right, court.center.dy), line);

    // The net, a little past the sidelines, with posts.
    final netX = court.center.dx;
    canvas.drawLine(
      Offset(netX, court.top - 6),
      Offset(netX, court.bottom + 6),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    for (final y in [court.top - 6, court.bottom + 6]) {
      canvas.drawCircle(Offset(netX, y), 3.2, Paint()..color = c.voltFill);
    }

    final from = serveFrom;
    if (from != null) _serveArrow(canvas, from, serveTo);
  }

  void _serveArrow(Canvas canvas, Offset from, Offset to) {
    final d = to - from;
    final len = d.distance;
    if (len < 1) return;
    final dir = d / len;
    // Start and stop clear of the pictures.
    final a = from + dir * arrowInset;
    final b = to - dir * arrowInset;
    final paint = Paint()
      ..color = serveColor.withValues(alpha: 0.9)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final total = (b - a).distance;
    for (var t = 0.0; t < total; t += 9) {
      canvas.drawLine(a + dir * t, a + dir * (t + 5).clamp(0, total), paint);
    }
    final normal = Offset(-dir.dy, dir.dx);
    final head = Path()
      ..moveTo(b.dx, b.dy)
      ..lineTo((b - dir * 9 + normal * 5).dx, (b - dir * 9 + normal * 5).dy)
      ..lineTo((b - dir * 9 - normal * 5).dx, (b - dir * 9 - normal * 5).dy)
      ..close();
    canvas.drawPath(head, Paint()..color = serveColor);
  }

  @override
  bool shouldRepaint(CourtSurfacePainter old) =>
      old.c != c || old.court != court || old.serveFrom != serveFrom || old.serveTo != serveTo || old.serveColor != serveColor ||
      old.arrowInset != arrowInset;
}
