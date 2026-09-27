import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../design/design.dart';
import '../../../shared/format.dart';
import '../data/tournaments.dart';
import 'tournament_widgets.dart';

/// A tournament's banner: the organiser's uploaded image when there is one,
/// otherwise SkorX art drawn from the tournament's id, so no two tournaments
/// share a picture. Brand colours only; the logo (or a monogram) sits in the
/// bottom-left corner.
class TournamentBanner extends StatelessWidget {
  const TournamentBanner({
    super.key,
    required this.id,
    required this.name,
    this.bannerUrl,
    this.logoUrl,
    this.height = 132,
    this.radius = Sx.radiusLg,
    this.logo = true,
    this.child,
  });

  TournamentBanner.of(Tournament t, {Key? key, double height = 132, double radius = Sx.radiusLg, bool logo = true, Widget? child})
      : this(
          key: key,
          id: t.id,
          name: t.name,
          bannerUrl: t.bannerUrl,
          logoUrl: t.logoUrl,
          height: height,
          radius: radius,
          logo: logo,
          child: child,
        );

  final String id;
  final String name;
  final String? bannerUrl;
  final String? logoUrl;
  final double height;
  final double radius;
  final bool logo;

  /// Drawn over the banner (status, date).
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final art = _BannerArt(seed: id.codeUnits.fold(7, (a, b) => (a * 31 + b) & 0x7fffffff), c: c, monogram: monogram(name));
    final fallback = CustomPaint(painter: art, child: const SizedBox.expand());
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (bannerUrl == null)
                fallback
              else
                Image.network(
                  bannerUrl!,
                  fit: BoxFit.cover,
                  cacheHeight: (height * MediaQuery.devicePixelRatioOf(context)).round(),
                  errorBuilder: (_, _, _) => fallback,
                  loadingBuilder: (_, image, progress) => progress == null ? image : fallback,
                ),
              // A shade at the bottom, so the logo and any text read on a photo.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.35)],
                    stops: const [0.45, 1],
                  ),
                ),
              ),
              if (logo)
                Positioned(
                  left: Sx.s12,
                  bottom: Sx.s12,
                  child: _Logo(name: name, url: logoUrl, size: math.min(44, height * 0.34)),
                ),
              ?child,
            ],
          ),
        ),
      ),
    );
  }

  /// "SPT", "AP", "MPM": the name's initials, numbers left out.
  static String monogram(String name) {
    final words = name.split(RegExp(r'\s+')).where((w) => w.isNotEmpty && !RegExp(r'^\d').hasMatch(w)).toList();
    if (words.isEmpty) return 'X';
    if (words.first.length <= 4 && words.first == words.first.toUpperCase()) return words.first;
    return words.take(3).map((w) => w[0].toUpperCase()).join();
  }
}

class _Logo extends StatelessWidget {
  const _Logo({required this.name, required this.url, required this.size});

  final String name;
  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final mark = Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(gradient: c.brand, shape: BoxShape.circle),
      child: Text(
        TournamentBanner.monogram(name),
        maxLines: 1,
        style: SxType.label(c.onVolt, size: size * 0.36, weight: FontWeight.w900).copyWith(letterSpacing: 0.2),
      ),
    );
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: ClipOval(
        child: url == null ? mark : Image.network(url!, fit: BoxFit.cover, errorBuilder: (_, _, _) => mark),
      ),
    );
  }
}

/// The drawn banner. The seed picks one of the brand gradients, where the
/// court sits and at what angle, and where the ball is.
class _BannerArt extends CustomPainter {
  _BannerArt({required this.seed, required this.c, required this.monogram});

  final int seed;
  final SxColors c;
  final String monogram;

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.Random(seed);
    final rect = Offset.zero & size;
    final palettes = [
      [c.deep, c.blue, c.cyan],
      [const Color(0xFF09121E), c.deep, c.blue],
      [c.deep, const Color(0xFF243A4E), c.olive],
      [c.blue, c.deep, const Color(0xFF09121E)],
      [c.deep, c.cyan, c.blue],
    ];
    final colors = palettes[seed % palettes.length];
    final angle = r.nextDouble() * math.pi;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment(math.cos(angle), math.sin(angle)),
          end: Alignment(-math.cos(angle), -math.sin(angle)),
          colors: colors,
        ).createShader(rect),
    );

    // Light from one corner.
    final light = Offset(r.nextBool() ? 0 : size.width, 0);
    canvas.drawCircle(
      light,
      size.width * 0.7,
      Paint()
        ..shader = RadialGradient(colors: [Colors.white.withValues(alpha: 0.16), Colors.white.withValues(alpha: 0)])
            .createShader(Rect.fromCircle(center: light, radius: size.width * 0.7)),
    );

    // The monogram, huge and faint, bleeding off the right edge.
    final tp = TextPainter(
      text: TextSpan(
        text: monogram,
        style: TextStyle(
          fontFamily: SxType.display,
          fontSize: size.height * 1.05,
          fontWeight: FontWeight.w800,
          fontStyle: FontStyle.italic,
          color: Colors.white.withValues(alpha: 0.08),
          letterSpacing: -2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(size.width - tp.width * 0.82, size.height - tp.height * 0.86));

    // A court, tilted into the frame.
    canvas.save();
    canvas.translate(size.width * (0.35 + r.nextDouble() * 0.3), size.height * (0.1 + r.nextDouble() * 0.2));
    canvas.rotate(-0.5 + r.nextDouble() * 0.6);
    CourtPainter.drawCourt(
      canvas,
      Rect.fromLTWH(0, 0, size.width * 0.62, size.height * 1.1),
      Colors.white.withValues(alpha: 0.22),
      topInset: 0.2,
    );
    canvas.restore();

    // The volt ball.
    final ball = Offset(size.width * (0.6 + r.nextDouble() * 0.3), size.height * (0.2 + r.nextDouble() * 0.3));
    final radius = size.height * (0.12 + r.nextDouble() * 0.06);
    canvas.drawCircle(ball, radius * 1.8, Paint()..color = c.voltFill.withValues(alpha: 0.16 * c.glow));
    PickleballPainter.drawBall(canvas, ball, radius, SxColors.dark.voltFill, hole: const Color(0xFF243A4E), shade: true);
  }

  @override
  bool shouldRepaint(_BannerArt old) => old.seed != seed || old.c != c || old.monogram != monogram;
}

/// A status word on a banner: white on a dark glass pill, red dot when live.
class BannerTag extends StatelessWidget {
  const BannerTag({super.key, required this.text, this.live = false});

  final String text;
  final bool live;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: live ? context.sx.live : Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (live) ...[const LivePulse(size: 6, color: Colors.white), const SizedBox(width: 5)],
            Text(text, style: SxType.label(Colors.white, size: 11.5)),
          ],
        ),
      );
}

/// Explore's tournament card: banner first, then only what decides whether
/// to open it.
class TournamentBannerCard extends StatelessWidget {
  const TournamentBannerCard({super.key, required this.tournament, required this.onTap, this.registered = false, this.matchCount});

  final Tournament tournament;
  final VoidCallback onTap;
  final bool registered;

  /// Matches on SkorX so far, when known.
  final int? matchCount;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final t = tournament;
    final now = DateTime.now();
    final (state, word) = tournamentState(t, now, registered: registered);
    final phase = t.phase(now);
    final facts = [
      '${t.playersRegistered} players',
      if (matchCount != null && matchCount! > 0) '$matchCount matches',
      formatsLabel(t),
    ];
    return Semantics(
      button: true,
      label: '${t.name}, ${dateRange(t.start, t.end)}, ${t.venue}, ${t.city}, ${word.toLowerCase()}',
      excludeSemantics: true,
      child: Tappable(
        onTap: onTap,
        radius: Sx.radiusLg,
        child: Container(
          decoration: BoxDecoration(
            gradient: c.card,
            borderRadius: BorderRadius.circular(Sx.radiusLg),
            border: Border.all(color: c.cardEdge),
            boxShadow: c.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TournamentBanner.of(
                t,
                height: 128,
                radius: Sx.radiusLg - 1,
                child: Stack(
                  children: [
                    Positioned(
                      left: Sx.s12,
                      top: Sx.s12,
                      child: BannerTag(
                        text: switch (phase) {
                          TournamentPhase.live => 'LIVE',
                          TournamentPhase.upcoming => 'UPCOMING',
                          TournamentPhase.completed => 'COMPLETED',
                        },
                        live: phase == TournamentPhase.live,
                      ),
                    ),
                    Positioned(right: Sx.s12, top: Sx.s12, child: _DateChip(t.start)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Sx.s16, Sx.s12, Sx.s16, Sx.s16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.name.toUpperCase(), maxLines: 2, overflow: TextOverflow.ellipsis, style: SxType.title(c.ink, size: 22)),
                    const SizedBox(height: Sx.s4),
                    _IconLine(Icons.place_outlined, '${t.venue} · ${t.placeLabel}'),
                    _IconLine(Icons.event_outlined, dateRange(t.start, t.end)),
                    _IconLine(
                      t.organizerVerified ? Icons.verified_rounded : Icons.groups_2_outlined,
                      t.organizer,
                      accent: t.organizerVerified,
                    ),
                    const SizedBox(height: Sx.s12),
                    Row(
                      children: [
                        Expanded(child: Align(alignment: Alignment.centerLeft, child: StateMark(state, word: word, size: 12))),
                        const SizedBox(width: Sx.s8),
                        if (phase != TournamentPhase.completed)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: c.voltFill.withValues(alpha: c.isDark ? 0.14 : 0.3),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              t.minFee == 0 ? 'Free' : 'from ${formatInr(t.minFee)}',
                              style: SxType.heading(c.isDark ? c.volt : c.ink, size: 14),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: Sx.s8),
                    Text(facts.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.caption(c.inkMuted, size: 12.5)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  const _DateChip(this.day);

  final DateTime day;

  @override
  Widget build(BuildContext context) => Container(
        width: 46,
        padding: const EdgeInsets.symmetric(vertical: 5),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(Sx.radiusSm)),
        child: Column(
          children: [
            Text('${day.day}', style: SxType.number(20, const Color(0xFF09121E), weight: FontWeight.w800)),
            Text(monthsShort[day.month - 1].toUpperCase(), style: SxType.label(const Color(0xFF09121E), size: 10)),
          ],
        ),
      );
}

class _IconLine extends StatelessWidget {
  const _IconLine(this.icon, this.text, {this.accent = false});

  final IconData icon;
  final String text;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          Icon(icon, size: 14, color: accent ? (c.isDark ? c.cyan : c.blue) : c.inkFaint),
          const SizedBox(width: 6),
          Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.caption(c.inkMuted))),
        ],
      ),
    );
  }
}
