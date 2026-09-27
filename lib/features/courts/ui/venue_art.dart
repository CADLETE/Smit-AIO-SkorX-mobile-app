import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../design/design.dart';
import '../data/courts.dart';

/// A venue's court colours: the playing surface, the run-off around it, and
/// the light it is played under.
@immutable
class CourtScheme {
  const CourtScheme(this.surface, this.runoff, this.sky, this.accent);

  final Color surface;
  final Color runoff;

  /// Top to bottom of the backdrop: a hall ceiling, or the sky outdoors.
  final List<Color> sky;
  final Color accent;

  static const _indoor = [
    CourtScheme(Color(0xFF1E6FD9), Color(0xFF2E9E5B), [Color(0xFF071427), Color(0xFF0F2A4A)], Color(0xFF4DD8F0)),
    CourtScheme(Color(0xFF2D8C57), Color(0xFF1B4F8F), [Color(0xFF09121E), Color(0xFF123456)], Color(0xFFD4F53C)),
    CourtScheme(Color(0xFF3651C9), Color(0xFFE0663A), [Color(0xFF100E24), Color(0xFF2A1F4F)], Color(0xFFFFB547)),
    CourtScheme(Color(0xFF12839B), Color(0xFF26386B), [Color(0xFF051A22), Color(0xFF0B3A4A)], Color(0xFF7CF2E0)),
  ];

  static const _outdoor = [
    CourtScheme(Color(0xFF2F7FE0), Color(0xFF3FA35F), [Color(0xFF79C4F2), Color(0xFFFBD38D)], Color(0xFFFFE08A)),
    CourtScheme(Color(0xFF2E9E5B), Color(0xFF3563C9), [Color(0xFF1C2D5A), Color(0xFFF08A5D)], Color(0xFFFFC97A)),
  ];

  /// Stable per venue, so a venue always looks the same.
  static CourtScheme of(Venue v) {
    final seed = v.id.codeUnits.fold<int>(7, (a, b) => a * 31 + b);
    final list = v.indoor ? _indoor : _outdoor;
    return list[seed.abs() % list.length];
  }
}

/// The venue's banner: its photo when the API has one, until then an
/// illustrated scene of its courts — a lit hall for indoor venues, open sky
/// and floodlights outdoors.
class VenueBanner extends StatelessWidget {
  const VenueBanner({super.key, required this.venue, this.height = 150, this.radius = Sx.radiusLg, this.child});

  final Venue venue;
  final double height;
  final double radius;

  /// Drawn over the scene (chips, a title).
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final scene = CustomPaint(painter: VenueScenePainter(scheme: CourtScheme.of(venue), indoor: venue.indoor, courts: venue.courts));
    final url = venue.imageUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ExcludeSemantics(
              child: url == null
                  ? scene
                  : Image.network(
                      url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => scene,
                      loadingBuilder: (_, img, progress) => progress == null ? img : scene,
                    ),
            ),
            // Keeps text on the banner readable.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x33000000), Color(0x00000000), Color(0x99000000)],
                  stops: [0, 0.45, 1],
                ),
              ),
            ),
            ?child,
          ],
        ),
      ),
    );
  }
}

class VenueScenePainter extends CustomPainter {
  VenueScenePainter({required this.scheme, required this.indoor, required this.courts});

  final CourtScheme scheme;
  final bool indoor;
  final int courts;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width, h = size.height;
    final horizon = h * 0.42;

    // Backdrop.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, Offset(0, horizon), scheme.sky),
    );
    if (indoor) {
      _hall(canvas, size, horizon);
    } else {
      _outside(canvas, size, horizon);
    }

    // The floor: run-off in perspective, then the courts on it.
    final floor = Path()
      ..moveTo(-w * 0.2, h)
      ..lineTo(w * 0.12, horizon)
      ..lineTo(w * 0.88, horizon)
      ..lineTo(w * 1.2, h)
      ..close();
    canvas.drawPath(
      floor,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, horizon),
          Offset(0, h),
          [Color.lerp(scheme.runoff, Colors.black, 0.35)!, scheme.runoff],
        ),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, horizon - 1, w, 2),
      Paint()..color = Colors.white.withValues(alpha: 0.12),
    );

    // Up to three courts side by side, the middle one nearest.
    final shown = courts.clamp(1, 3);
    for (var i = 0; i < shown; i++) {
      final offset = shown == 1 ? 0.0 : (i - (shown - 1) / 2) * 0.62;
      _court(canvas, size, horizon, offset);
    }

    // A ball mid-flight over the net.
    final ball = Offset(w * 0.64, horizon + (h - horizon) * 0.2);
    canvas.drawCircle(ball + const Offset(3, 26), 5, Paint()..color = Colors.black.withValues(alpha: 0.25));
    Pickleball.paint(canvas, ball, math.max(6, h * 0.045), color: const Color(0xFFD4F53C), hole: const Color(0xFF243A4E), spin: 0.6, glow: 0.6);
  }

  /// A court in perspective, [dx] court-widths off centre.
  void _court(Canvas canvas, Size size, double horizon, double dx) {
    final w = size.width, h = size.height;
    final nearHalf = w * 0.3, farHalf = w * 0.1;
    final cx = w / 2 + dx * w;
    final farCx = w / 2 + dx * w * 0.36;
    final top = horizon + (h - horizon) * 0.06;
    final bottom = h * 1.02;
    Offset at(double u, double v) {
      // u across 0..1, v from far (0) to near (1).
      final half = farHalf + (nearHalf - farHalf) * v;
      final centre = farCx + (cx - farCx) * v;
      return Offset(centre - half + u * 2 * half, top + (bottom - top) * (v * v * 0.45 + v * 0.55));
    }

    final surface = Path()
      ..moveTo(at(0, 0).dx, at(0, 0).dy)
      ..lineTo(at(1, 0).dx, at(1, 0).dy)
      ..lineTo(at(1, 1).dx, at(1, 1).dy)
      ..lineTo(at(0, 1).dx, at(0, 1).dy)
      ..close();
    canvas.drawPath(
      surface,
      Paint()
        ..shader = ui.Gradient.linear(
          at(0.5, 0),
          at(0.5, 1),
          [Color.lerp(scheme.surface, Colors.black, 0.25)!, scheme.surface],
        ),
    );
    // The kitchen, a shade lighter.
    final kitchen = Path()
      ..moveTo(at(0, 0.36).dx, at(0, 0.36).dy)
      ..lineTo(at(1, 0.36).dx, at(1, 0.36).dy)
      ..lineTo(at(1, 0.64).dx, at(1, 0.64).dy)
      ..lineTo(at(0, 0.64).dx, at(0, 0.64).dy)
      ..close();
    canvas.drawPath(kitchen, Paint()..color = Colors.white.withValues(alpha: 0.08));

    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = 1.3
      ..style = PaintingStyle.stroke;
    canvas.drawPath(surface, line);
    void seg(double u1, double v1, double u2, double v2) => canvas.drawLine(at(u1, v1), at(u2, v2), line);
    seg(0, 0.36, 1, 0.36);
    seg(0, 0.64, 1, 0.64);
    seg(0.5, 0, 0.5, 0.36);
    seg(0.5, 0.64, 0.5, 1);

    // The net, with its posts and a little height.
    final l = at(-0.04, 0.5), r = at(1.04, 0.5);
    final netH = 10.0 + 6 * (1 - dx.abs());
    final net = Path()
      ..moveTo(l.dx, l.dy)
      ..lineTo(r.dx, r.dy)
      ..lineTo(r.dx, r.dy - netH)
      ..lineTo(l.dx, l.dy - netH)
      ..close();
    canvas.drawPath(net, Paint()..color = Colors.black.withValues(alpha: 0.35));
    canvas.drawLine(
      Offset(l.dx, l.dy - netH),
      Offset(r.dx, r.dy - netH),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 1.6,
    );
    final post = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..strokeWidth = 2;
    canvas.drawLine(l, Offset(l.dx, l.dy - netH), post);
    canvas.drawLine(r, Offset(r.dx, r.dy - netH), post);
  }

  /// A lit hall: back wall, ceiling lights and their beams.
  void _hall(Canvas canvas, Size size, double horizon) {
    final w = size.width;
    // Back wall panels.
    final panel = Paint()..color = Colors.white.withValues(alpha: 0.04);
    for (var i = 0; i < 9; i++) {
      final x = w * (0.05 + i * 0.11);
      canvas.drawRect(Rect.fromLTWH(x, horizon * 0.52, w * 0.08, horizon * 0.46), panel);
    }
    // A glowing sign band in the venue's accent.
    canvas.drawRect(
      Rect.fromLTWH(w * 0.28, horizon * 0.62, w * 0.44, 3),
      Paint()
        ..color = scheme.accent.withValues(alpha: 0.8)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    // Ceiling lights and soft beams.
    for (var i = 0; i < 5; i++) {
      final x = w * (0.1 + i * 0.2);
      final lamp = Offset(x, horizon * 0.16);
      final beam = Path()
        ..moveTo(lamp.dx - 4, lamp.dy)
        ..lineTo(lamp.dx + 4, lamp.dy)
        ..lineTo(lamp.dx + w * 0.09, size.height * 0.95)
        ..lineTo(lamp.dx - w * 0.09, size.height * 0.95)
        ..close();
      canvas.drawPath(
        beam,
        Paint()
          ..shader = ui.Gradient.linear(
            lamp,
            Offset(lamp.dx, size.height),
            [Colors.white.withValues(alpha: 0.13), Colors.white.withValues(alpha: 0)],
          ),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: lamp, width: w * 0.08, height: 4), const Radius.circular(2)),
        Paint()..color = Colors.white.withValues(alpha: 0.95),
      );
      canvas.drawCircle(
        lamp,
        14,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.25)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
    }
  }

  /// Open air: a low sun, trees on the skyline and floodlight towers.
  void _outside(Canvas canvas, Size size, double horizon) {
    final w = size.width;
    final sun = Offset(w * 0.78, horizon * 0.55);
    canvas.drawCircle(
      sun,
      horizon * 0.5,
      Paint()
        ..shader = ui.Gradient.radial(sun, horizon * 0.5, [scheme.accent.withValues(alpha: 0.55), scheme.accent.withValues(alpha: 0)]),
    );
    canvas.drawCircle(sun, horizon * 0.14, Paint()..color = scheme.accent);

    // Treeline.
    final trees = Path()..moveTo(0, horizon);
    final rnd = math.Random(courts * 17 + 3);
    var x = 0.0;
    while (x < w) {
      final r = 8 + rnd.nextDouble() * 14;
      trees.arcToPoint(Offset(x + r * 2, horizon), radius: Radius.circular(r));
      x += r * 2;
    }
    trees
      ..lineTo(w, horizon + 2)
      ..lineTo(0, horizon + 2)
      ..close();
    canvas.drawPath(trees, Paint()..color = const Color(0xFF0E2A1F).withValues(alpha: 0.85));

    // Floodlight towers either side.
    for (final fx in [0.06, 0.94]) {
      final base = Offset(w * fx, horizon + 6);
      final head = Offset(w * fx, horizon * 0.18);
      canvas.drawLine(
        base,
        head,
        Paint()
          ..color = const Color(0xFF1A2230)
          ..strokeWidth = 3,
      );
      canvas.drawRect(Rect.fromCenter(center: head, width: 18, height: 8), Paint()..color = const Color(0xFF1A2230));
      canvas.drawCircle(
        head,
        12,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
  }

  @override
  bool shouldRepaint(VenueScenePainter old) => old.scheme != scheme || old.indoor != indoor || old.courts != courts;
}

/// The venue's courts from above, to pick one: free courts lit in the
/// venue's colours, booked ones greyed and struck through.
class CourtMap extends StatelessWidget {
  const CourtMap({
    super.key,
    required this.venue,
    required this.free,
    required this.selected,
    required this.onSelect,
  });

  final Venue venue;

  /// Free court numbers at the chosen time.
  final List<int> free;
  final int? selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = CourtScheme.of(venue);
    final n = venue.courts;
    final perRow = n <= 4 ? 2 : 3;
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final cell = (constraints.maxWidth - gap * (perRow - 1)) / perRow;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 1; i <= n; i++)
              SizedBox(
                width: cell,
                child: _MiniCourt(
                  number: i,
                  scheme: scheme,
                  free: free.contains(i),
                  selected: selected == i,
                  onTap: () => onSelect(i),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MiniCourt extends StatelessWidget {
  const _MiniCourt({required this.number, required this.scheme, required this.free, required this.selected, required this.onTap});

  final int number;
  final CourtScheme scheme;
  final bool free;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Semantics(
      button: true,
      selected: selected,
      enabled: free,
      label: 'Court $number, ${free ? 'free' : 'booked'}',
      excludeSemantics: true,
      child: Tappable(
        onTap: free ? onTap : null,
        radius: Sx.radiusSm,
        child: AnimatedContainer(
          duration: Sx.medium,
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Sx.radiusSm + 2),
            gradient: selected ? c.brand : null,
            boxShadow: selected ? c.glowOf(c.voltFill, strength: 0.9) : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Sx.radiusSm),
            child: AspectRatio(
              aspectRatio: 0.78,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(painter: _TopCourtPainter(scheme: scheme, free: free)),
                  if (!free)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(6)),
                        child: Text('BOOKED', style: SxType.label(Colors.white70, size: 10)),
                      ),
                    ),
                  if (selected)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: c.voltFill),
                        child: Icon(Icons.check_rounded, size: 16, color: c.onVolt),
                      ),
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 6,
                    child: Text(
                      'COURT $number',
                      textAlign: TextAlign.center,
                      style: SxType.label(Colors.white.withValues(alpha: free ? 1 : 0.6), size: 11.5, weight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A court from above: run-off, surface, kitchen, lines and net.
class _TopCourtPainter extends CustomPainter {
  _TopCourtPainter({required this.scheme, required this.free});

  final CourtScheme scheme;
  final bool free;

  @override
  void paint(Canvas canvas, Size size) {
    Color tone(Color col) => free ? col : Color.lerp(col, const Color(0xFF3A414C), 0.8)!;
    canvas.drawRect(Offset.zero & size, Paint()..color = tone(scheme.runoff));
    final court = Rect.fromLTWH(size.width * 0.16, size.height * 0.1, size.width * 0.68, size.height * 0.72);
    canvas.drawRect(court, Paint()..color = tone(scheme.surface));
    final k = court.height * 0.16;
    final mid = court.center.dy;
    canvas.drawRect(
      Rect.fromLTRB(court.left, mid - k, court.right, mid + k),
      Paint()..color = Colors.white.withValues(alpha: free ? 0.12 : 0.05),
    );
    final line = Paint()
      ..color = Colors.white.withValues(alpha: free ? 0.9 : 0.35)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    canvas.drawRect(court, line);
    canvas.drawLine(Offset(court.left, mid - k), Offset(court.right, mid - k), line);
    canvas.drawLine(Offset(court.left, mid + k), Offset(court.right, mid + k), line);
    canvas.drawLine(Offset(court.center.dx, court.top), Offset(court.center.dx, mid - k), line);
    canvas.drawLine(Offset(court.center.dx, mid + k), Offset(court.center.dx, court.bottom), line);
    canvas.drawLine(
      Offset(court.left - 4, mid),
      Offset(court.right + 4, mid),
      Paint()
        ..color = Colors.white.withValues(alpha: free ? 1 : 0.4)
        ..strokeWidth = 2.4,
    );
    if (!free) {
      // Struck through, so booked reads without colour.
      final strike = Paint()
        ..color = Colors.white.withValues(alpha: 0.18)
        ..strokeWidth = 1;
      for (var d = -size.height; d < size.width; d += 9) {
        canvas.drawLine(Offset(d, size.height), Offset(d + size.height, 0), strike);
      }
    }
  }

  @override
  bool shouldRepaint(_TopCourtPainter old) => old.free != free || old.scheme != scheme;
}
