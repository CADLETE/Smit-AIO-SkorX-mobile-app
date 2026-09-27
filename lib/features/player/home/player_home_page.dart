import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design/design.dart';
import '../../../shared/format.dart';
import '../../auth/auth_controller.dart';
import '../../casual_match/verification/verification_controller.dart';
import '../../looking_for/ui/home_card.dart';
import '../../matches/data/match.dart';
import '../../matches/data/match_repository.dart';
import '../../notifications/notifications.dart';
import '../../rating/arc_career.dart' show ArcPoint;
import '../../rating/ui/arc_widgets.dart';
import '../data/player_repository.dart';
import '../player_pages.dart';

String greetingFor(DateTime now) {
  final hour = now.hour;
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
}

/// Home answers one question: what matters to me right now? One Now card,
/// three actions, recent results and three numbers. Nothing else.
class PlayerHomePage extends ConsumerWidget {
  const PlayerHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeMatchesProvider);
    final live = ref.watch(liveMatchesProvider).value ?? const <Match>[];
    final history = ref.watch(matchHistoryProvider);
    final results = history.value?.matches.where((m) => m.isCompleted).take(10).toList() ?? const <Match>[];
    final brandNew = active.value?.isEmpty == true && history.value?.matches.isEmpty == true;

    return PlayerTabList(
      onRefresh: () async {
        ref.invalidate(activeMatchesProvider);
        ref.invalidate(liveMatchesProvider);
        ref.invalidate(matchHistoryProvider);
        ref.invalidate(playerOverviewProvider);
        ref.invalidate(playerRecordProvider);
        await ref.read(activeMatchesProvider.future);
      },
      header: const _Header(),
      children: [
        const SizedBox(height: Sx.s8),
        switch (active) {
          AsyncData() when brandNew => const _Welcome(),
          AsyncData(:final value) => _NowCard(matches: value, live: live),
          AsyncError() => ErrorBlock(
              message: 'Your matches did not load.',
              onRetry: () => ref.invalidate(activeMatchesProvider),
            ),
          _ => const Skeleton(height: 300, radius: Sx.radiusLg),
        },
        if (!brandNew) ...[
          const SizedBox(height: Sx.section),
          const _QuickActions(),
        ],
        const SizedBox(height: Sx.s16),
        const LookingForHomeCard(),
        if (results.isNotEmpty) ...[
          const SizedBox(height: Sx.section),
          SxSection(results.length == 1 ? 'Last result' : 'Last results',
              action: 'All results', onAction: () => context.push('/player/paddle/matches')),
          _LastResults(matches: results),
        ],
        if (!brandNew) ...[
          const SizedBox(height: Sx.section),
          const _Snapshot(),
        ],
      ],
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final user = ref.watch(currentUserProvider);
    final rating = ref.watch(playerOverviewProvider).value?.rating;
    final unread = ref.watch(unreadNotificationsProvider);
    // Match requests wait for an answer, so they keep the dot on until answered.
    final requests = ref.watch(matchRequestCountProvider);
    final name = user?.firstName ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s12, Sx.s12, Sx.s8),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'Profile',
            excludeSemantics: true,
            child: Tappable(
              key: const Key('homeAvatar'),
              onTap: () => context.go('/player/profile'),
              radius: 24,
              child: SxAvatar(name: user?.name ?? '', size: 46, ring: true),
            ),
          ),
          const SizedBox(width: Sx.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(greetingFor(DateTime.now()), style: SxType.caption(c.inkMuted, size: 13)),
                const SizedBox(height: 1),
                Text(name.toUpperCase(),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.title(c.ink, size: 30)),
              ],
            ),
          ),
          Semantics(
            button: true,
            label: rating == null ? 'Not rated yet. My Paddle' : 'SkorX Rating ${ratingText(rating)}. My Paddle',
            excludeSemantics: true,
            child: Tappable(
              key: const Key('headerRating'),
              onTap: () => context.go('/player/paddle'),
              child: Container(
                height: 40,
                padding: const EdgeInsets.fromLTRB(6, 4, 12, 4),
                decoration: BoxDecoration(
                  color: c.surface.withValues(alpha: c.isDark ? 0.6 : 0.9),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: c.cardEdge),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SxBall(size: 24, float: false, glow: false),
                    const SizedBox(width: 6),
                    Text(rating == null ? '—' : ratingText(rating), style: SxType.number(22, c.ink, weight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: Sx.s4),
          SxIconAction(
            key: const Key('notificationsBell'),
            icon: Icons.notifications_none_rounded,
            label: 'Notifications',
            dot: unread > 0 || requests > 0,
            onTap: () => context.push(requests > 0 && unread == 0 ? '/player/notifications?tab=requests' : '/player/notifications'),
          ),
        ],
      ),
    );
  }
}

/// The one thing that matters now: what is live (the player's match first,
/// then everyone else's, rotating), a match about to start, the next match,
/// or a nudge to find one.
class _NowCard extends StatelessWidget {
  const _NowCard({required this.matches, this.live = const []});

  final List<Match> matches;

  /// Every match on court now, the player's own first.
  final List<Match> live;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final onCourt = live.isNotEmpty ? live : matches.where((m) => m.isLive).toList();
    if (matches.isEmpty && onCourt.isEmpty) {
      return _HeroTap(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SxHeroTag(text: 'NOTHING SCHEDULED', icon: Icons.event_available_rounded),
            const SizedBox(height: Sx.s16),
            Text('Your next\nmatch awaits', style: SxType.title(Colors.white, size: 38)),
            const SizedBox(height: Sx.s8),
            Text('Enter a tournament or start a match with friends.',
                style: SxType.body(Colors.white.withValues(alpha: 0.8))),
            const SizedBox(height: Sx.s24),
            SxButton(label: 'Find a tournament', icon: Icons.emoji_events_rounded, onPressed: () => context.go('/player/explore')),
          ],
        ),
      );
    }

    final next = matches.where((m) => !m.isLive).firstOrNull;
    if (onCourt.isNotEmpty) {
      return Column(
        children: [
          _LiveCarousel(matches: onCourt),
          if (next != null) _ThenLine(match: next, now: now, playing: matches.any((m) => m.isLive)),
        ],
      );
    }
    return _NextCard(match: next!, now: now);
  }
}

/// Live matches, one at a time: a new one slides in every few seconds, and a
/// swipe moves on straight away.
class _LiveCarousel extends StatefulWidget {
  const _LiveCarousel({required this.matches});

  final List<Match> matches;

  @override
  State<_LiveCarousel> createState() => _LiveCarouselState();
}

class _LiveCarouselState extends State<_LiveCarousel> {
  static const _dwell = Duration(seconds: 5);

  Timer? _timer;
  int _index = 0;
  int _dir = 1;

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void didUpdateWidget(_LiveCarousel old) {
    super.didUpdateWidget(old);
    if (_index >= widget.matches.length) _index = 0;
    if (old.matches.length != widget.matches.length) _restart();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _restart() {
    _timer?.cancel();
    if (widget.matches.length < 2) return;
    _timer = Timer.periodic(_dwell, (_) => _step(1));
  }

  void _step(int dir) {
    if (!mounted) return;
    final n = widget.matches.length;
    setState(() {
      _dir = dir;
      _index = (_index + dir + n) % n;
    });
  }

  void _swipe(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (v.abs() < 150) return;
    _step(v < 0 ? 1 : -1);
    _restart();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.matches.length;
    final m = widget.matches[_index];
    final still = MediaQuery.disableAnimationsOf(context);
    final current = ValueKey(m.id);
    return GestureDetector(
      onHorizontalDragEnd: n < 2 ? null : _swipe,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: Duration(milliseconds: still ? 200 : 520),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          layoutBuilder: (child, previous) => Stack(
            alignment: Alignment.topCenter,
            children: [...previous, ?child],
          ),
          transitionBuilder: (child, anim) {
            if (still) return FadeTransition(opacity: anim, child: child);
            // In from the side it is heading, out the other way.
            final incoming = child.key == current;
            final from = Offset(incoming ? _dir.toDouble() : -_dir.toDouble(), 0);
            return SlideTransition(
              position: Tween(begin: from, end: Offset.zero).animate(anim),
              child: FadeTransition(opacity: anim, child: child),
            );
          },
          child: KeyedSubtree(
            key: current,
            child: _LiveCard(match: m, index: _index, count: n),
          ),
        ),
      ),
    );
  }
}

/// Which live match is showing: a volt bar for this one, dots for the rest.
class _Dots extends StatelessWidget {
  const _Dots({required this.index, required this.count});

  final int index;
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Semantics(
      label: 'Live match ${index + 1} of $count',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == index ? 20 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: i == index ? c.voltFill : Colors.white.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
        ],
      ),
    );
  }
}

/// The hero gradient card, tappable when [onTap] is set.
class _HeroTap extends StatelessWidget {
  const _HeroTap({super.key, required this.child, this.onTap, this.semanticLabel});

  final Widget child;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final card = SxHeroCard(
      watermark: true,
      padding: const EdgeInsets.fromLTRB(Sx.s20, Sx.s20, Sx.s20, Sx.s20),
      child: SxOnHero(child: child),
    );
    if (onTap == null) return card;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Tappable(onTap: onTap, radius: Sx.radiusLg, child: card),
    );
  }
}

class _LiveCard extends StatelessWidget {
  const _LiveCard({required this.match, this.index = 0, this.count = 1});

  final Match match;
  final int index;
  final int count;

  @override
  Widget build(BuildContext context) {
    final m = match;
    return _HeroTap(
      key: const Key('nowCard'),
      onTap: () => context.push('/player/matches/${m.id}'),
      semanticLabel: 'Live match',
      child: Builder(builder: (context) {
        final c = context.sx;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(flex: 2, child: SxHeroTag(text: 'LIVE · GAME ${m.live!.number}', live: true)),
                const SizedBox(width: Sx.s8),
                if (m.court != null)
                  Flexible(child: SxHeroTag(text: m.court!.toUpperCase(), icon: Icons.grid_view_rounded)),
              ],
            ),
            const SizedBox(height: Sx.s16),
            Text(m.stageLabel.toUpperCase(), style: SxType.title(c.ink, size: 32)),
            const SizedBox(height: 2),
            Text(m.contextLabel, style: SxType.caption(c.inkMuted)),
            const SizedBox(height: Sx.s16),
            Container(
              padding: const EdgeInsets.fromLTRB(Sx.s16, Sx.s12, Sx.s16, Sx.s12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(Sx.radius),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: LiveScore(match: m),
            ),
            const SizedBox(height: Sx.s12),
            Text('First to ${m.pointsToWin}, win by 2 · best of ${m.bestOf}', style: SxType.caption(c.inkMuted)),
            const SizedBox(height: Sx.s16),
            SxButton(
              key: const Key('followLive'),
              label: m.involvesMe ? 'View live match' : 'Watch live',
              icon: Icons.play_arrow_rounded,
              onPressed: () => context.push('/player/matches/${m.id}'),
            ),
            if (count > 1) ...[
              const SizedBox(height: Sx.s16),
              Center(child: _Dots(index: index, count: count)),
            ],
          ],
        );
      }),
    );
  }
}

class _ThenLine extends StatelessWidget {
  const _ThenLine({required this.match, required this.now, this.playing = true});

  final Match match;
  final DateTime now;

  /// The player is on court now, so this comes after.
  final bool playing;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final m = match;
    return Semantics(
      button: true,
      label: '${playing ? 'Then' : 'Your next match'} ${m.stageLabel}, ${relativeDay(m.scheduledAt, now)} ${time12(m.scheduledAt)}',
      excludeSemantics: true,
      child: Tappable(
        onTap: () => context.push('/player/matches/${m.id}'),
        child: Container(
          margin: const EdgeInsets.fromLTRB(Sx.s16, 0, Sx.s16, 0),
          padding: const EdgeInsets.fromLTRB(Sx.s16, Sx.s12, Sx.s12, Sx.s12),
          decoration: BoxDecoration(
            color: c.surface.withValues(alpha: c.isDark ? 0.75 : 0.95),
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(Sx.radius)),
            border: Border(
              left: BorderSide(color: c.cardEdge),
              right: BorderSide(color: c.cardEdge),
              bottom: BorderSide(color: c.cardEdge),
            ),
          ),
          child: Row(
            children: [
              Text(playing ? 'THEN' : 'YOUR NEXT', style: SxType.label(c.cyan, size: 12)),
              const SizedBox(width: Sx.s12),
              Expanded(
                child: Text(
                  '${m.stageLabel} · ${relativeDay(m.scheduledAt, now)} ${time12(m.scheduledAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SxType.body(c.ink, size: 14).copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: c.inkFaint, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// The next match. Within the hour a volt countdown tag takes over the top.
class _NextCard extends StatelessWidget {
  const _NextCard({required this.match, required this.now});

  final Match match;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final m = match;
    final soon = startsIn(m, now);
    final when = '${relativeDay(m.scheduledAt, now)} · ${time12(m.scheduledAt)}';

    return _HeroTap(
      key: const Key('nowCard'),
      onTap: () => context.push('/player/matches/${m.id}'),
      semanticLabel: 'Next match',
      child: Builder(builder: (context) {
        final c = context.sx;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: soon != null
                      ? SxHeroTag(text: soon, icon: Icons.bolt_rounded, highlight: true)
                      : SxHeroTag(
                          text: 'NEXT MATCH · ${relativeDay(m.scheduledAt, now).toUpperCase()}',
                          icon: Icons.schedule_rounded,
                        ),
                ),
              ],
            ),
            const SizedBox(height: Sx.s16),
            Text(m.stageLabel.toUpperCase(), style: SxType.title(c.ink, size: 32)),
            const SizedBox(height: 2),
            Text(m.contextLabel, style: SxType.caption(c.inkMuted)),
            const SizedBox(height: Sx.s16),
            Container(
              padding: const EdgeInsets.all(Sx.s16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(Sx.radius),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            SideDps(names: m.mine, size: 32, edge: Colors.white.withValues(alpha: 0.9)),
                            const SizedBox(width: Sx.s12),
                            Expanded(child: Text(sideLabel(m.mine), style: SxType.heading(c.ink, size: 18))),
                          ],
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: Sx.s8),
                          child: SizedBox(height: 8, child: NetLine()),
                        ),
                        Row(
                          children: [
                            SideDps(names: m.theirs, size: 32, edge: Colors.white.withValues(alpha: 0.9)),
                            const SizedBox(width: Sx.s12),
                            Expanded(
                              child: Text(
                                m.opponentKnown ? sideLabel(m.theirs) : (m.theirsPlaceholder ?? 'Opponent to be decided'),
                                style: SxType.heading(m.opponentKnown ? c.ink : c.inkMuted, size: 18)
                                    .copyWith(fontStyle: m.opponentKnown ? null : FontStyle.italic),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Sx.s16),
                  Column(
                    children: [
                      Text(time12(m.scheduledAt), style: SxType.number(26, c.ink, weight: FontWeight.w800)),
                      Text('START', style: SxType.label(c.inkMuted, size: 11)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: Sx.s12),
            Wrap(
              spacing: Sx.s16,
              runSpacing: Sx.s8,
              children: [
                if (m.court != null) _Fact(icon: Icons.grid_view_rounded, text: m.court!, color: c.inkMuted),
                if (m.venue != null) _Fact(icon: Icons.place_outlined, text: m.venue!, color: c.inkMuted),
                _Fact(icon: Icons.schedule_rounded, text: when, color: c.inkMuted),
              ],
            ),
            const SizedBox(height: Sx.s20),
            SxButton(
              key: const Key('viewMatch'),
              label: 'View match',
              icon: Icons.arrow_forward_rounded,
              onPressed: () => context.push('/player/matches/${m.id}'),
            ),
          ],
        );
      }),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Text(text, style: SxType.caption(color, size: 13.5)),
        ],
      );
}

/// Recent results in one card: the form line, the latest match as a
/// scoreboard, then the few before it as rows. Everything older is one tap
/// away in All results.
class _LastResults extends StatelessWidget {
  const _LastResults({required this.matches});

  /// Newest first.
  final List<Match> matches;

  static const _rows = 3;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final latest = matches.first;
    final earlier = matches.skip(1).take(_rows).toList();
    return Container(
      key: const Key('lastResults'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: c.card,
        borderRadius: BorderRadius.circular(Sx.radiusLg),
        border: Border.all(color: c.cardEdge),
        boxShadow: c.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (matches.length > 1) _FormStrip(matches: matches.take(5).toList()),
          _LatestResult(key: const Key('lastResult'), match: latest),
          for (final (i, m) in earlier.indexed) ...[
            Divider(height: 1, thickness: 1, color: c.line, indent: Sx.s16, endIndent: Sx.s16),
            _ResultRow(key: Key('lastResult-${i + 1}'), match: m),
          ],
        ],
      ),
    );
  }
}

/// FORM with a square per match, newest on the left, and the tally.
class _FormStrip extends StatelessWidget {
  const _FormStrip({required this.matches});

  final List<Match> matches;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final wins = matches.where((m) => m.won).length;
    return Semantics(
      label: 'Form: $wins won, ${matches.length - wins} lost in the last ${matches.length}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(Sx.s16, Sx.s12, Sx.s16, Sx.s12),
        decoration: BoxDecoration(
          color: c.surfaceAlt.withValues(alpha: 0.5),
          border: Border(bottom: BorderSide(color: c.line)),
        ),
        child: Row(
          children: [
            Text('FORM', style: SxType.label(c.inkMuted, size: 11)),
            const SizedBox(width: Sx.s12),
            for (final m in matches) ...[
              _ResultBadge(won: m.won, size: 22),
              const SizedBox(width: 6),
            ],
            const Spacer(),
            Text.rich(
              TextSpan(children: [
                TextSpan(text: '$wins', style: SxType.number(15, c.ink, weight: FontWeight.w800)),
                TextSpan(text: 'W  ', style: SxType.caption(c.inkMuted, size: 12)),
                TextSpan(text: '${matches.length - wins}', style: SxType.number(15, c.ink, weight: FontWeight.w800)),
                TextSpan(text: 'L', style: SxType.caption(c.inkMuted, size: 12)),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

/// A W or L in a rounded square: volt for a win, quiet for a loss.
class _ResultBadge extends StatelessWidget {
  const _ResultBadge({required this.won, this.size = 28});

  final bool won;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: won ? c.brand : null,
        color: won ? null : c.surfaceAlt,
        borderRadius: BorderRadius.circular(size * 0.3),
        border: won ? null : Border.all(color: c.line),
      ),
      child: Text(won ? 'W' : 'L', style: SxType.label(won ? c.onVolt : c.inkMuted, size: size * 0.5, weight: FontWeight.w800)),
    );
  }
}

/// The latest match as a scoreboard: both sides with their games, the
/// winner bright, the rating change up top.
class _LatestResult extends StatelessWidget {
  const _LatestResult({super.key, required this.match});

  final Match match;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final m = match;
    final opp = sideLabel(m.theirs);
    final context_ = [m.contextLabel, if (m.tournament != null) m.stageLabel].join(' · ');
    return Semantics(
      button: true,
      label: '${m.won ? 'Won' : 'Lost'} against $opp, ${m.games.map((g) => '${g.$1} ${g.$2}').join(', ')}',
      excludeSemantics: true,
      child: Tappable(
        onTap: () => context.push('/player/matches/${m.id}'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Sx.s16, Sx.s16, Sx.s16, Sx.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _VerdictChip(won: m.won),
                  const SizedBox(width: Sx.s12),
                  Expanded(
                    child: Text(context_, maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.caption(c.inkMuted)),
                  ),
                  if (m.pointsEarned != null) ...[
                    const SizedBox(width: Sx.s8),
                    RatingDelta(m.pointsEarned!, size: 15, digits: 2, unit: ' SXP', what: 'SkorX Points'),
                  ],
                ],
              ),
              const SizedBox(height: Sx.s16),
              Container(
                padding: const EdgeInsets.fromLTRB(Sx.s12, Sx.s12, Sx.s12, Sx.s12),
                decoration: BoxDecoration(
                  color: c.surfaceAlt.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(Sx.radius),
                  border: Border.all(color: c.line),
                ),
                child: Column(
                  children: [
                    _ScoreLine(names: m.mine, games: [for (final g in m.games) (g.$1, g.$2)], winner: m.won),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: Sx.s8),
                      child: SizedBox(height: 8, child: NetLine()),
                    ),
                    _ScoreLine(names: m.theirs, games: [for (final g in m.games) (g.$2, g.$1)], winner: !m.won),
                  ],
                ),
              ),
              const SizedBox(height: Sx.s12),
              Row(
                children: [
                  _Fact(icon: Icons.schedule_rounded, text: relativeDay(m.playedAt, DateTime.now()), color: c.inkMuted),
                  if (m.venue != null) ...[
                    const SizedBox(width: Sx.s16),
                    Icon(Icons.place_outlined, size: 15, color: c.inkMuted),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(m.venue!,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.caption(c.inkMuted, size: 13.5)),
                    ),
                  ] else
                    const Spacer(),
                  Icon(Icons.chevron_right_rounded, color: c.inkFaint, size: 20),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One side of the scoreboard: faces, name, then a column per game. Each
/// game's winning score is bright, the other faint.
class _ScoreLine extends StatelessWidget {
  const _ScoreLine({required this.names, required this.games, required this.winner});

  final List<String> names;

  /// (this side, the other side) per game.
  final List<(int, int)> games;
  final bool winner;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Row(
      children: [
        SideDps(names: names, size: 28, edge: c.surface),
        const SizedBox(width: Sx.s12),
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(sideLabel(names),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SxType.heading(winner ? c.ink : c.inkMuted, size: 16)),
              ),
              if (winner) ...[
                const SizedBox(width: 6),
                Icon(Icons.emoji_events_rounded, size: 15, color: c.volt),
              ],
            ],
          ),
        ),
        for (final g in games)
          SizedBox(
            width: 34,
            child: Text(
              '${g.$1}',
              textAlign: TextAlign.center,
              style: SxType.number(20, g.$1 > g.$2 ? c.ink : c.inkFaint, weight: FontWeight.w800),
            ),
          ),
      ],
    );
  }
}

/// An earlier result on one line: W/L, opponent, games, day.
class _ResultRow extends StatelessWidget {
  const _ResultRow({super.key, required this.match});

  final Match match;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final m = match;
    final opp = sideLabel(m.theirs);
    final score = m.games.map((g) => '${g.$1}–${g.$2}').join('  ');
    return Semantics(
      button: true,
      label: '${m.won ? 'Won' : 'Lost'} against $opp, ${m.games.map((g) => '${g.$1} ${g.$2}').join(', ')}',
      excludeSemantics: true,
      child: Tappable(
        onTap: () => context.push('/player/matches/${m.id}'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Sx.s16, Sx.s12, Sx.s12, Sx.s12),
          child: Row(
            children: [
              _ResultBadge(won: m.won),
              const SizedBox(width: Sx.s12),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('vs $opp', maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.heading(c.ink, size: 15)),
                    const SizedBox(height: 2),
                    Text(
                      '${m.tournament == null ? m.kind.label : m.stageLabel} · ${relativeDay(m.playedAt, DateTime.now())}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SxType.caption(c.inkMuted, size: 12.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Sx.s8),
              // Three long games shrink to fit a narrow phone rather than push the name out.
              Flexible(
                flex: 2,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(score, style: SxType.number(15, m.won ? c.ink : c.inkMuted, weight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.chevron_right_rounded, color: c.inkFaint, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// WON in volt with a trophy, LOST quiet.
class _VerdictChip extends StatelessWidget {
  const _VerdictChip({required this.won});

  final bool won;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final ink = won ? c.onVolt : c.inkMuted;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
      decoration: BoxDecoration(
        gradient: won ? c.brand : null,
        color: won ? null : c.surfaceAlt,
        borderRadius: BorderRadius.circular(Sx.radiusSm),
        boxShadow: won ? c.glowOf(c.voltFill, strength: 0.5) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(won ? Icons.emoji_events_rounded : Icons.sports_tennis_rounded, size: 15, color: ink),
          const SizedBox(width: 5),
          Text(won ? 'WON' : 'LOST', style: SxType.verdict(15, ink)),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    Widget tile(String key, IconData icon, String label, String route, List<Color> colors) => Expanded(
          child: _ActionTile(key: Key(key), icon: icon, label: label, colors: colors, // Tabs are switched to; other screens open on top, with a way back.
              onTap: () => route.startsWith('/player/paddle/') ? context.push(route) : context.go(route)),
        );
    return Row(
      children: [
        Expanded(
          child: _ActionTile(
            key: const Key('quickStartMatch'),
            icon: Icons.sports_tennis_rounded,
            label: 'Start match',
            colors: [c.blue, c.cyan],
            onTap: () => context.push('/player/match/new'),
          ),
        ),
        const SizedBox(width: Sx.s12),
        tile('quickTournaments', Icons.emoji_events_rounded, 'Find tournament', '/player/explore/tournaments',
            [c.voltFill, c.olive]),
        const SizedBox(width: Sx.s12),
        tile('quickMatches', Icons.scoreboard_rounded, 'My matches', '/player/paddle/matches', [c.cyan, c.blue]),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({super.key, required this.icon, required this.label, required this.colors, required this.onTap});

  final IconData icon;
  final String label;
  final List<Color> colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Tappable(
        onTap: onTap,
        haptic: true,
        child: Container(
          height: 108,
          padding: const EdgeInsets.all(Sx.s12),
          decoration: BoxDecoration(
            gradient: c.card,
            borderRadius: BorderRadius.circular(Sx.radiusLg),
            border: Border.all(color: c.cardEdge),
            boxShadow: c.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SxIconTile(icon: icon, size: 40, solid: true, colors: colors),
              Text(label, maxLines: 2, style: SxType.heading(c.ink, size: 15).copyWith(height: 1.15)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The SkorX Rating up top, then SkorX Points, win rate and rank; everything
/// else is in My Paddle.
class _Snapshot extends ConsumerWidget {
  const _Snapshot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final overview = ref.watch(playerOverviewProvider).value;
    final record = ref.watch(playerRecordProvider).value;
    final city = overview?.rankings
        .where((r) => r.scope == RankScope.city && r.category == (record?.preferredFormat ?? PlayCategory.doubles))
        .firstOrNull;
    Widget cell(String value, String label, IconData icon, Gradient g) => Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(Sx.s12, Sx.s12, Sx.s12, Sx.s16),
            decoration: BoxDecoration(
              gradient: c.card,
              borderRadius: BorderRadius.circular(Sx.radius),
              border: Border.all(color: c.cardEdge),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: (b) => g.createShader(Offset.zero & b.size),
                  child: Icon(icon, size: 18, color: Colors.white),
                ),
                const SizedBox(height: Sx.s8),
                Semantics(
                  label: '$label $value',
                  excludeSemantics: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: SxGradientText(value, gradient: g, style: SxType.number(32, c.ink, weight: FontWeight.w800)),
                      ),
                      const SizedBox(height: 2),
                      Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.caption(c.inkMuted, size: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
    return Column(
      children: [
        SxSection('Your game', action: 'My Paddle', onAction: () => context.go('/player/paddle')),
        Semantics(
          button: true,
          label: 'Open My Paddle',
          child: Tappable(
            key: const Key('snapshot'),
            onTap: () => context.go('/player/paddle'),
            child: Column(
              children: [
                _RatingCard(overview: overview),
                const SizedBox(height: Sx.s8),
                Row(
                  children: [
                    cell(overview?.points == null ? '—' : sxpText(overview!.points!), 'SkorX Points', Icons.stars_rounded, c.brand),
                    const SizedBox(width: Sx.s8),
                    cell(record?.winRate == null ? '—' : '${record!.winRate}%', 'Win rate', Icons.local_fire_department_rounded,
                        c.cool),
                    const SizedBox(width: Sx.s8),
                    cell(city == null ? '—' : '#${city.rank}', city == null ? 'Rank' : '${city.place} rank',
                        Icons.leaderboard_rounded, c.cool),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The SkorX Rating as the centrepiece of "Your game": the number, its band,
/// the last 30 days and a trend line drawing in beside it.
class _RatingCard extends ConsumerWidget {
  const _RatingCard({required this.overview});

  final PlayerOverview? overview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final arc = overview?.arc;
    final change = overview?.ratingChange30d ?? 0;
    final history = ref.watch(ratingHistoryProvider).value ?? const <ArcPoint>[];
    final values = [for (final p in history) p.rating];
    return Semantics(
      key: const Key('homeRating'),
      label: arc == null
          ? 'SkorX Rating: not rated yet'
          : 'SkorX Rating ${ratingText(arc.rating)}, ${arc.band.label}, '
              '${change >= 0 ? 'up' : 'down'} ${change.abs().toStringAsFixed(1)} in 30 days',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(Sx.s16, Sx.s16, Sx.s16, Sx.s16),
        decoration: BoxDecoration(
          gradient: c.card,
          borderRadius: BorderRadius.circular(Sx.radiusLg),
          border: Border.all(color: c.cardEdge),
          boxShadow: c.cardShadow,
        ),
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const SxBall(size: 18, float: false, glow: false),
                      const SizedBox(width: 6),
                      Text('SKORX RATING', style: SxType.label(c.inkMuted, size: 11)),
                    ],
                  ),
                  const SizedBox(height: Sx.s8),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: arc == null
                        ? Text('NOT RATED', style: SxType.number(36, c.inkFaint, weight: FontWeight.w800))
                        : SxGradientText(ratingText(arc.rating),
                            gradient: c.brand, style: SxType.number(52, c.ink, weight: FontWeight.w800)),
                  ),
                  const SizedBox(height: Sx.s4),
                  if (arc == null)
                    Text('Finish a scored match to get your rating', style: SxType.caption(c.inkMuted, size: 12))
                  else
                    Row(
                      children: [
                        Flexible(child: SkorxBandChip(band: arc.band, size: 11)),
                        if (change.abs() >= 0.05) ...[
                          const SizedBox(width: Sx.s8),
                          RatingDelta(change, size: 13, digits: 1),
                          const SizedBox(width: 3),
                          Text('30d', style: SxType.caption(c.inkMuted, size: 11)),
                        ],
                      ],
                    ),
                ],
              ),
            ),
            if (values.length >= 2) ...[
              const SizedBox(width: Sx.s12),
              Expanded(flex: 4, child: RatingGraph(values: values, height: 72, minSpan: 4, label: 'SkorX Rating')),
            ],
          ],
        ),
      ),
    );
  }
}

/// First launch: no matches, no tournaments, no rating. Three ways in.
class _Welcome extends StatelessWidget {
  const _Welcome();

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const Key('welcome'),
      padding: const EdgeInsets.only(top: Sx.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SxHeroCard(
            padding: const EdgeInsets.fromLTRB(Sx.s24, Sx.s32, Sx.s24, Sx.s24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('WELCOME TO', style: SxType.label(Colors.white.withValues(alpha: 0.8), size: 13)),
                const SizedBox(height: Sx.s4),
                Text('SkorX', style: SxType.title(Colors.white, size: 60).copyWith(letterSpacing: -1.5)),
                const SizedBox(height: Sx.s12),
                Text('Your pickleball journey starts here. Every match you play builds your rating, your ranking and your story.',
                    style: SxType.body(Colors.white.withValues(alpha: 0.85), size: 15)),
              ],
            ),
          ),
          const SizedBox(height: Sx.s24),
          SxButton(key: const Key('welcomeTournament'), label: 'Find a tournament', icon: Icons.emoji_events_rounded,
              onPressed: () => context.go('/player/explore/tournaments')),
          const SizedBox(height: Sx.s12),
          SxButton.secondary(key: const Key('welcomeScore'), label: 'Start a match', icon: Icons.sports_tennis_rounded,
              onPressed: () => context.push('/player/match/new')),
          const SizedBox(height: Sx.s32),
          const _HowItWorks(),
        ],
      ),
    );
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    Widget step(int i, IconData icon, String title, String body) => Padding(
          padding: const EdgeInsets.only(bottom: Sx.s12),
          child: SxReveal(
            index: i + 2,
            child: SxBlock(
              padding: const EdgeInsets.all(Sx.s16),
              child: Row(
                children: [
                  SxIconTile(icon: icon, size: 44, solid: true, colors: sxTileColors(c, i)),
                  const SizedBox(width: Sx.s16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: SxType.heading(c.ink, size: 17)),
                        const SizedBox(height: 2),
                        Text(body, style: SxType.caption(c.inkMuted)),
                      ],
                    ),
                  ),
                  Text('0${i + 1}', style: SxType.number(26, c.line, weight: FontWeight.w800)),
                ],
              ),
            ),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SxSection('How SkorX works'),
        step(0, Icons.sports_tennis_rounded, 'Play', 'Enter tournaments or score friendly matches.'),
        step(1, Icons.trending_up_rounded, 'Get rated', 'Every scored match moves your SkorX Rating and adds SkorX Points.'),
        step(2, Icons.leaderboard_rounded, 'Climb', 'Rank in your city, state and country. Unlock achievements.'),
      ],
    );
  }
}
