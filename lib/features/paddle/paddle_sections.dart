import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../design/design.dart';
import '../../shared/format.dart';
import '../matches/data/match.dart';
import '../player/data/player_repository.dart';
import '../player/data/player_stats.dart' show WinLoss;

// ─── Playing now / up next ───────────────────────────────────────────────

/// My live and next matches as cards you can read from arm's length: who,
/// where, and the score or the start time. Two or more swipe sideways.
class PlayingNowCards extends StatelessWidget {
  const PlayingNowCards({super.key, required this.matches});

  final List<Match> matches;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final shown = matches.take(4).toList();
    if (shown.length == 1) return _NowCard(match: shown.first, now: now);
    return SizedBox(
      height: 196,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: shown.length,
        separatorBuilder: (_, _) => const SizedBox(width: Sx.s12),
        itemBuilder: (context, i) => SizedBox(
          width: MediaQuery.sizeOf(context).width * 0.8,
          child: _NowCard(match: shown[i], now: now),
        ),
      ),
    );
  }
}

class _NowCard extends StatelessWidget {
  const _NowCard({required this.match, required this.now});

  final Match match;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final m = match;
    final live = m.isLive;
    final soon = startsIn(m, now);
    final where = [
      if (m.tournament != null) m.tournament!.round else m.kind.label,
      m.tournament?.name ?? m.venue,
      ?m.court,
    ].whereType<String>().toSet().join(' · ');
    final theirs = m.opponentKnown ? m.theirs : const <String>[];
    final theirsLabel = m.opponentKnown ? sideLabel(m.theirs) : (m.theirsPlaceholder ?? 'To be decided');

    Widget side(List<String> names, String label, int? score, {required bool me}) => Row(
          children: [
            SideDps(names: names, size: 30, edge: c.surface),
            const SizedBox(width: Sx.s12),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SxType.heading(me ? c.ink : c.inkMuted, size: 16).copyWith(fontWeight: me ? FontWeight.w800 : FontWeight.w600),
              ),
            ),
            if (score != null)
              SxBump(
                value: score,
                child: Text('$score', style: SxType.number(34, me ? c.ink : c.inkMuted, weight: FontWeight.w800)),
              ),
          ],
        );

    return Tappable(
      onTap: () => context.push('/player/matches/${m.id}'),
      radius: Sx.radiusLg,
      child: Container(
        decoration: BoxDecoration(
          gradient: c.card,
          borderRadius: BorderRadius.circular(Sx.radiusLg),
          border: Border.all(color: live ? c.live.withValues(alpha: 0.55) : c.cardEdge, width: live ? 1.4 : 1),
          boxShadow: live ? c.glowOf(c.live, strength: 0.6) : c.cardShadow,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Sx.radiusLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Status strip: red for live, the brand blue for what is next.
              Container(
                padding: const EdgeInsets.symmetric(horizontal: Sx.s16, vertical: 10),
                decoration: BoxDecoration(gradient: live ? c.heat : c.hero),
                child: Row(
                  children: [
                    if (live) ...[
                      const LivePulse(size: 8, color: Colors.white),
                      const SizedBox(width: Sx.s8),
                      Flexible(
                        child: Text(
                          m.live == null ? 'LIVE' : 'LIVE · GAME ${m.live!.number}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SxType.label(Colors.white, size: 12.5),
                        ),
                      ),
                    ] else ...[
                      const Icon(Icons.schedule_rounded, size: 15, color: Colors.white),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          soon ?? '${relativeDay(m.scheduledAt, now).toUpperCase()} · ${time12(m.scheduledAt)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SxType.label(Colors.white, size: 12.5),
                        ),
                      ),
                    ],
                    const Spacer(),
                    Icon(Icons.chevron_right_rounded, size: 18, color: Colors.white.withValues(alpha: 0.85)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Sx.s16, Sx.s12, Sx.s16, Sx.s12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    side(m.mine, sideLabel(m.mine), live ? m.live?.mine : null, me: true),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(child: Divider(height: 1, color: c.line)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: Sx.s8),
                            child: Text('VS', style: SxType.label(c.inkFaint, size: 10.5)),
                          ),
                          Expanded(child: Divider(height: 1, color: c.line)),
                        ],
                      ),
                    ),
                    side(theirs, theirsLabel, live ? m.live?.theirs : null, me: false),
                    if (where.isNotEmpty) ...[
                      const SizedBox(height: Sx.s12),
                      Row(
                        children: [
                          Icon(m.tournament != null ? Icons.emoji_events_outlined : Icons.place_outlined, size: 14, color: c.inkMuted),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(where, maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.caption(c.inkMuted, size: 12.5)),
                          ),
                        ],
                      ),
                    ],
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

// ─── My casual / tournament matches ──────────────────────────────────────

/// One kind of my matches as a single card: the record around a win-rate
/// ring, recent form, then the last three results as compact rows.
class MyMatchesCard extends StatelessWidget {
  const MyMatchesCard({
    super.key,
    required this.category,
    required this.record,
    required this.matches,
    required this.onAll,
  });

  final MatchCategory category;
  final WinLoss record;
  final List<Match> matches;
  final VoidCallback onAll;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final casual = category == MatchCategory.casual;
    final r = record;
    final form = matches.where((m) => m.isCompleted).take(5).toList();
    return Container(
      decoration: BoxDecoration(
        gradient: c.card,
        borderRadius: BorderRadius.circular(Sx.radiusLg),
        border: Border.all(color: c.cardEdge),
        boxShadow: c.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Sx.s16, Sx.s16, Sx.s16, Sx.s12),
            child: Row(
              children: [
                _WinRing(rate: r.winRate, size: 64),
                const SizedBox(width: Sx.s16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: _MiniStat(value: '${r.played}', label: 'Played')),
                          Expanded(child: _MiniStat(value: '${r.wins}', label: 'Won', color: r.wins > 0 ? c.volt : null)),
                          Expanded(child: _MiniStat(value: '${r.losses}', label: 'Lost')),
                        ],
                      ),
                      if (form.isNotEmpty) ...[
                        const SizedBox(height: Sx.s12),
                        Row(
                          children: [
                            Text('FORM', style: SxType.label(c.inkFaint, size: 10)),
                            const SizedBox(width: Sx.s8),
                            // Oldest to newest, like reading a scoreline.
                            for (final m in form.reversed) _FormPip(won: m.won),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: c.line),
          for (final (i, m) in matches.take(3).indexed) ...[
            if (i > 0) Padding(padding: const EdgeInsets.only(left: 64), child: Divider(height: 1, color: c.line)),
            _ResultTile(match: m),
          ],
          Tappable(
            onTap: onAll,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    casual ? 'All casual matches' : 'All tournament matches',
                    style: SxType.caption(c.isDark ? c.cyan : c.blue, size: 13.5).copyWith(fontWeight: FontWeight.w700),
                  ),
                  Icon(Icons.chevron_right_rounded, size: 18, color: c.isDark ? c.cyan : c.blue),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.value, required this.label, this.color});

  final String value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Semantics(
      label: '$label $value',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: SxType.number(24, color ?? c.ink, weight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label.toUpperCase(), style: SxType.label(c.inkMuted, size: 10)),
        ],
      ),
    );
  }
}

class _FormPip extends StatelessWidget {
  const _FormPip({required this.won});

  final bool won;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Container(
      width: 20,
      height: 20,
      margin: const EdgeInsets.only(right: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: won ? c.brand : null,
        color: won ? null : c.surfaceAlt,
        border: won ? null : Border.all(color: c.line),
      ),
      child: Text(won ? 'W' : 'L', style: SxType.label(won ? c.onVolt : c.inkMuted, size: 10.5, weight: FontWeight.w800)),
    );
  }
}

/// Win rate as a ring: volt for the wins, the track for the rest.
class _WinRing extends StatelessWidget {
  const _WinRing({required this.rate, this.size = 64});

  final int? rate;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Semantics(
      label: rate == null ? 'No results yet' : 'Won $rate percent',
      excludeSemantics: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: (rate ?? 0) / 100),
        duration: sxReduceMotion(context) ? Duration.zero : const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (_, v, _) => SizedBox.square(
          dimension: size,
          child: CustomPaint(
            painter: _RingPainter(value: v, track: c.surfaceAlt, fill: c.voltFill, glow: c.glow),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(rate == null ? '—' : '${(v * 100).round()}%', style: SxType.number(19, c.ink, weight: FontWeight.w800)),
                  Text('WON', style: SxType.label(c.inkMuted, size: 8.5)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.value, required this.track, required this.fill, required this.glow});

  final double value;
  final Color track;
  final Color fill;
  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2 - 4;
    final center = size.center(Offset.zero);
    final rect = Rect.fromCircle(center: center, radius: r);
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = track,
    );
    if (value <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * value,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..color = fill
        ..maskFilter = glow > 0.8 ? const MaskFilter.blur(BlurStyle.solid, 2) : null,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value || old.fill != fill || old.track != track;
}

/// One result: a W/L badge, the other side, where and when, the games.
class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.match});

  final Match match;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final m = match;
    final now = DateTime.now();
    final done = m.isCompleted;
    final won = done && m.won;
    final badge = switch (m.status) {
      MatchStatus.completed => won ? 'W' : 'L',
      MatchStatus.live => 'LIVE',
      MatchStatus.upcoming => timeShort(m.scheduledAt),
      MatchStatus.cancelled => '—',
    };
    final day = switch (daysBetween(m.playedAt, now)) {
      0 => 'Today',
      1 => 'Yesterday',
      _ => '${m.playedAt.day} ${monthsShort[m.playedAt.month - 1]}',
    };
    final context_ = [day, if (m.tournament != null) m.tournament!.round else m.venue].whereType<String>().join(' · ');
    final opponents = m.opponentKnown ? sideLabel(m.theirs) : (m.theirsPlaceholder ?? 'To be decided');

    return Semantics(
      button: true,
      label: '${done ? (won ? 'Won' : 'Lost') : m.status.name} against $opponents, $context_',
      excludeSemantics: true,
      child: Tappable(
        onTap: () => context.push('/player/matches/${m.id}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Sx.s16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  gradient: won ? c.brand : (m.isLive ? c.heat : null),
                  color: won || m.isLive ? null : c.surfaceAlt,
                  boxShadow: won ? c.glowOf(c.voltFill, strength: 0.45) : null,
                ),
                child: FittedBox(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      badge,
                      style: SxType.number(badge.length > 2 ? 12 : 18, won ? c.onVolt : (m.isLive ? Colors.white : c.inkMuted),
                          weight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: Sx.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: 'vs ', style: SxType.caption(c.inkMuted, size: 13)),
                          TextSpan(text: opponents),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SxType.heading(c.ink, size: 15.5),
                    ),
                    const SizedBox(height: 2),
                    Text(context_, maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.caption(c.inkMuted, size: 12)),
                  ],
                ),
              ),
              const SizedBox(width: Sx.s8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (m.games.isNotEmpty)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final (a, b) in m.games.take(3))
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(text: '$a', style: TextStyle(color: a > b ? c.ink : c.inkFaint)),
                                  TextSpan(text: '-', style: TextStyle(color: c.inkFaint)),
                                  TextSpan(text: '$b', style: TextStyle(color: b > a ? c.ink : c.inkFaint)),
                                ],
                              ),
                              style: SxType.number(15, c.ink, weight: FontWeight.w700),
                            ),
                          ),
                      ],
                    ),
                  if (m.pointsEarned != null && m.involvesMe) ...[
                    const SizedBox(height: 4),
                    RatingDelta(m.pointsEarned!, size: 12.5, digits: 2, unit: ' SXP', what: 'SkorX Points'),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Trophy room ─────────────────────────────────────────────────────────

/// Achievements, highlighted on their own: the collection so far, the
/// latest badges, and the two closest to unlocking, so there is always
/// something within reach.
class TrophyRoomCard extends StatelessWidget {
  const TrophyRoomCard({super.key, required this.all, required this.onOpen, required this.onBadge});

  final List<Achievement> all;
  final VoidCallback onOpen;
  final ValueChanged<Achievement> onBadge;

  @override
  Widget build(BuildContext context) {
    final unlocked = all.where((a) => a.unlocked).toList()..sort((a, b) => b.unlockedAt!.compareTo(a.unlockedAt!));
    final close = all.where((a) => !a.unlocked).toList()..sort((a, b) => b.progress.compareTo(a.progress));
    final nearest = close.take(2).toList();
    final score = unlocked.fold<int>(0, (s, a) => s + a.score);
    final share = all.isEmpty ? 0.0 : unlocked.length / all.length;
    final ink = Colors.white;
    final muted = Colors.white.withValues(alpha: 0.75);

    return SxHeroCard(
      padding: const EdgeInsets.all(Sx.s20),
      ballColor: const Color(0xFFF2C94C),
      child: SxOnHero(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.emoji_events_rounded, size: 18, color: Color(0xFFF2C94C)),
                const SizedBox(width: 6),
                Text('TROPHY ROOM', style: SxType.label(muted, size: 12.5)),
              ],
            ),
            const SizedBox(height: Sx.s12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                CountUp(value: unlocked.length, style: SxType.hero(60, ink)),
                const SizedBox(width: Sx.s8),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('of ${all.length}\nbadges', style: SxType.caption(muted, size: 12.5).copyWith(height: 1.15)),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('$score', style: SxType.number(26, const Color(0xFFF2C94C), weight: FontWeight.w800)),
                    Text('BADGE SCORE', style: SxType.label(muted, size: 9.5)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: Sx.s12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: share),
                duration: sxReduceMotion(context) ? Duration.zero : const Duration(milliseconds: 1000),
                curve: Curves.easeOutCubic,
                builder: (_, v, _) => LinearProgressIndicator(
                  value: v,
                  minHeight: 7,
                  backgroundColor: Colors.white.withValues(alpha: 0.16),
                  valueColor: const AlwaysStoppedAnimation(Color(0xFFD4F53C)),
                ),
              ),
            ),
            if (unlocked.isNotEmpty) ...[
              const SizedBox(height: Sx.s16),
              Text('LATEST', style: SxType.label(muted, size: 10.5)),
              const SizedBox(height: Sx.s8),
              SizedBox(
                height: 58,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: math.min(unlocked.length, 8),
                  separatorBuilder: (_, _) => const SizedBox(width: Sx.s8),
                  itemBuilder: (_, i) => Tappable(
                    onTap: () => onBadge(unlocked[i]),
                    child: SxPop(delay: i * 60, child: AchievementCoin(achievement: unlocked[i], size: 56)),
                  ),
                ),
              ),
            ] else ...[
              const SizedBox(height: Sx.s12),
              Text('Your first badge comes with your first match.', style: SxType.body(muted, size: 14)),
            ],
            if (nearest.isNotEmpty) ...[
              const SizedBox(height: Sx.s16),
              Text('ALMOST THERE', style: SxType.label(muted, size: 10.5)),
              const SizedBox(height: Sx.s8),
              for (final a in nearest)
                Padding(
                  padding: const EdgeInsets.only(bottom: Sx.s8),
                  child: Tappable(
                    onTap: () => onBadge(a),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(Sx.radiusSm),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(colors: [for (final m in tierMetal(a.tier)) m.withValues(alpha: 0.35)]),
                            ),
                            child: Icon(achievementIcon(a.icon), size: 20, color: Colors.white),
                          ),
                          const SizedBox(width: Sx.s12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(a.title,
                                          maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.heading(ink, size: 14.5)),
                                    ),
                                    Text(a.progressLabel ?? '${(a.progress * 100).round()}%',
                                        style: SxType.number(14, ink, weight: FontWeight.w700)),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(3),
                                  child: LinearProgressIndicator(
                                    value: a.progress,
                                    minHeight: 5,
                                    backgroundColor: Colors.white.withValues(alpha: 0.14),
                                    valueColor: AlwaysStoppedAnimation(tierMetal(a.tier)[1]),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
            const SizedBox(height: Sx.s8),
            SxButton(
              key: const Key('allAchievements'),
              label: 'See all ${all.length} badges',
              icon: Icons.military_tech_rounded,
              height: 48,
              onPressed: onOpen,
            ),
          ],
        ),
      ),
    );
  }
}
