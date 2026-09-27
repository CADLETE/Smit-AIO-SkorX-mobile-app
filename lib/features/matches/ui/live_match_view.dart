import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design/design.dart';
import '../../../shared/format.dart';
import '../../../sports/core/score_state.dart';
import '../../casual_match/live/commentary.dart';
import '../../casual_match/live/live_court.dart';
import '../../casual_match/live/match_analytics.dart';
import '../../casual_match/local_match.dart';
import '../../casual_match/ui/court_top_view.dart';
import '../../casual_match/ui/live/live_court_view.dart';
import '../../casual_match/ui/live/match_charts.dart';
import '../../subscription/data/plans.dart';
import '../../subscription/subscription_controller.dart';
import '../../subscription/ui/pro_widgets.dart';
import '../data/match.dart';
import 'stream_window.dart';

/// Watching a match that is on court now.
///
/// Built from the scorer's rally log ([match]), so it shows what the scorer
/// sees: a broadcast scoreboard, the court from above with every player in
/// their service court and the serve going across, and the calls (side out,
/// game point) as they happen, with the video on top when it is streamed. Below: the story so far, rally by rally, the
/// momentum, and the numbers side by side. [summary] adds the tournament,
/// round and venue.
class LiveMatchView extends ConsumerStatefulWidget {
  const LiveMatchView({super.key, required this.summary, required this.match});

  final Match summary;
  final LocalMatch match;

  @override
  ConsumerState<LiveMatchView> createState() => _LiveMatchViewState();
}

class _LiveMatchViewState extends ConsumerState<LiveMatchView> {
  late final Commentator _voice = ref.read(commentatorProvider);
  int _token = 0;
  CourtFlash? _flash;
  CourtBanner? _banner;

  /// The side that just scored, for the scoreboard's flash.
  Side? _scored;

  /// Spoken commentary, for watching from the stands with the phone down.
  bool _listening = false;

  @override
  void didUpdateWidget(LiveMatchView old) {
    super.didUpdateWidget(old);
    final before = old.match, after = widget.match;
    if (before.id != after.id || after.events.length <= before.events.length) return;
    final steps = replayLive(after);
    final step = steps.last;
    final winner = step.rallyWinner;
    final point = step.events.contains(LiveEvent.point);
    _flash = winner == null ? null : CourtFlash(winner, point: point, token: ++_token);
    _banner = rallyBanner(after, step, ++_token) ?? _banner;
    _scored = point ? winner : null;
    if (_listening) {
      final line = commentaryFor(after, step, CommentaryLevel.advanced, before: steps[steps.length - 2]);
      if (line != null) _voice.say(line);
    }
  }

  @override
  void dispose() {
    if (_listening) _voice.stop();
    super.dispose();
  }

  void _toggleVoice() {
    setState(() => _listening = !_listening);
    if (!_listening) {
      _voice.stop();
    } else {
      final m = widget.match;
      final score = m.score;
      _voice.say('${spokenSide(m, Side.a)} against ${spokenSide(m, Side.b)}. Game ${score.gameNumber}. ${spokenCall(m, score)}.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.match;
    final steps = replayLive(m);
    final step = steps.last;
    final analytics = analyzeMatch(m);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.summary.broadcast case final broadcast?) ...[
          // Tournament streams are free; a casual match's stream is SkorX Pro.
          SxReveal(
            child: widget.summary.category == MatchCategory.casual
                ? ProGate(
                    feature: ProFeature.casualLiveStream,
                    locked: const ProLockedPanel(
                      feature: ProFeature.casualLiveStream,
                      message: 'This casual match is live on video. Watch it with SkorX Pro.',
                    ),
                    child: StreamWindow(broadcast: broadcast),
                  )
                : StreamWindow(broadcast: broadcast),
          ),
          const SizedBox(height: Sx.s16),
        ],
        SxReveal(
          child: _Scoreboard(
            summary: widget.summary,
            match: m,
            step: step,
            scored: _scored,
            token: _token,
            listening: _listening,
            onListen: _toggleVoice,
          ),
        ),
        const SizedBox(height: Sx.s16),
        SxReveal(
          index: 1,
          child: _Court(match: m, step: step, flash: _flash, banner: _banner),
        ),
        const SizedBox(height: Sx.s12),
        SxReveal(index: 2, child: _Pulse(match: m, steps: steps, analytics: analytics)),
        const SizedBox(height: Sx.section),
        SxSection('Play by play', padding: const EdgeInsets.only(bottom: Sx.s8)),
        _PlayByPlay(match: m, steps: steps),
        if (analytics.hasRallies && !ref.watch(canAccessProvider(ProFeature.matchAnalytics))) ...[
          // Momentum, game flow and the numbers are Match Analytics (SkorX Pro).
          const SizedBox(height: Sx.section),
          const SxSection('Momentum'),
          const ProLockedPanel(
            feature: ProFeature.matchAnalytics,
            message: 'Momentum, game flow and both sides’ numbers, rally by rally, as the match is played.',
          ),
        ] else ...[
          if (analytics.rallies.length > 1) ...[
            const SizedBox(height: Sx.section),
            const SxSection('Momentum'),
            SxBlock(child: MomentumChart(match: m, analytics: analytics)),
            const SizedBox(height: Sx.section),
            const SxSection('Game flow'),
            SxBlock(child: PointsProgressChart(match: m, analytics: analytics, initialGame: step.score.gameNumber)),
          ],
          if (analytics.hasRallies) ...[
            const SizedBox(height: Sx.section),
            const SxSection('Head to head'),
            SxBlock(child: _HeadToHead(match: m, analytics: analytics)),
          ],
        ],
      ],
    );
  }
}

// ─── Scoreboard ──────────────────────────────────────────────────────────

/// The broadcast scoreboard: both sides, the games so far, the points in
/// the game being played (big, flashing when they change), who serves, and
/// the moment (game point, side out) underneath.
class _Scoreboard extends StatelessWidget {
  const _Scoreboard({
    required this.summary,
    required this.match,
    required this.step,
    required this.scored,
    required this.token,
    required this.listening,
    required this.onListen,
  });

  final Match summary;
  final LocalMatch match;
  final LiveStep step;
  final Side? scored;
  final int token;
  final bool listening;
  final VoidCallback onListen;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final score = step.score;
    final over = match.isOver;
    final minutes = DateTime.now().difference(match.startedAt).inMinutes;
    final moment = _moment(match, step);
    final t = summary.tournament;

    return Container(
      key: const Key('liveScoreboard'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [const Color(0xFF060A10), c.deep, Color.lerp(c.deep, c.blue, 0.55)!],
          stops: const [0, 0.55, 1],
        ),
        borderRadius: BorderRadius.circular(Sx.radiusLg + 2),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: c.glowOf(c.blue, strength: 1.2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Sx.radiusLg + 2),
        child: Stack(
          children: [
            // Stadium light from above.
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -1.4),
                      radius: 1.1,
                      colors: [c.cyan.withValues(alpha: 0.22), Colors.transparent],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Sx.s16, Sx.s16, Sx.s16, Sx.s16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: Sx.s8,
                          runSpacing: Sx.s8,
                          children: [
                            SxHeroTag(
                              text: over ? 'FINAL · RESULT PENDING' : 'LIVE · GAME ${score.gameNumber}',
                              live: !over,
                              highlight: over,
                            ),
                            SxHeroTag(text: minutes < 1 ? 'JUST STARTED' : '$minutes MIN', icon: Icons.timer_outlined),
                          ],
                        ),
                      ),
                      const SizedBox(width: Sx.s8),
                      _ListenButton(on: listening, onTap: onListen),
                    ],
                  ),
                  const SizedBox(height: Sx.s12),
                  Semantics(
                    header: true,
                    child: Text(summary.stageLabel.toUpperCase(), style: SxType.title(Colors.white, size: 26)),
                  ),
                  const SizedBox(height: 2),
                  if (t != null)
                    Tappable(
                      key: const Key('headerTournament'),
                      onTap: () => context.push('/player/tournament/${t.id}'),
                      radius: 0,
                      child: Text(
                        '${t.name} · ${t.category}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SxType.caption(Colors.white.withValues(alpha: 0.78), size: 13.5).copyWith(
                          decoration: TextDecoration.underline,
                          decorationColor: Colors.white.withValues(alpha: 0.3),
                        ),
                      ),
                    ),
                  Text(
                    [?summary.court, ?summary.venue, 'Best of ${match.rules.bestOf} · to ${match.rules.pointsToWin}'].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SxType.caption(Colors.white.withValues(alpha: 0.6), size: 12.5),
                  ),
                  const SizedBox(height: Sx.s16),
                  _GamesHeader(match: match, score: score),
                  for (final side in Side.values) ...[
                    _SideLine(
                      match: match,
                      step: step,
                      side: side,
                      flashToken: scored == side ? token : null,
                    ),
                    if (side == Side.a) Divider(height: 1, color: Colors.white.withValues(alpha: 0.1)),
                  ],
                  const SizedBox(height: Sx.s12),
                  _MomentStrip(match: match, step: step, moment: moment),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "G1 G2 PTS" over the score columns.
class _GamesHeader extends StatelessWidget {
  const _GamesHeader({required this.match, required this.score});

  final LocalMatch match;
  final ScoreState score;

  @override
  Widget build(BuildContext context) {
    final done = match.isOver ? score.games.length : score.games.length - 1;
    final style = SxType.label(Colors.white.withValues(alpha: 0.5), size: 10.5);
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            const Spacer(),
            for (var g = 1; g <= done; g++) SizedBox(width: _SideLine.gameW, child: Text('G$g', textAlign: TextAlign.center, style: style)),
            if (!match.isOver)
              SizedBox(width: _SideLine.pointsW, child: Text('G${score.gameNumber}', textAlign: TextAlign.center, style: style)),
          ],
        ),
      ),
    );
  }
}

class _SideLine extends StatelessWidget {
  const _SideLine({required this.match, required this.step, required this.side, required this.flashToken});

  static const gameW = 30.0;
  static const pointsW = 66.0;

  final LocalMatch match;
  final LiveStep step;
  final Side side;

  /// Set when this side just scored: the points box flashes once per token.
  final int? flashToken;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final score = step.score;
    final color = CourtTopView.teamColor(c, side);
    final over = match.isOver;
    final serving = !over && step.court.serveSide == side;
    final won = over && match.winner == side;
    final lost = over && match.winner != side;
    final done = over ? score.games : score.games.take(score.games.length - 1).toList();
    final points = score.currentGame.of(side);
    final names = match.names(side);
    final needed = match.rules.gamesToWin;

    return Semantics(
      label: '${match.teamLabel(side)}: ${score.gamesWon(side)} games'
          '${over ? '' : ', $points points in game ${score.gameNumber}'}${serving ? ', serving' : ''}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 44,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2), boxShadow: c.glowOf(color, strength: 0.8)),
            ),
            const SizedBox(width: 10),
            SideDps(names: names, size: 34, edge: serving ? c.voltFill : color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          shortSide(match, side),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SxType.heading(lost ? Colors.white.withValues(alpha: 0.55) : Colors.white, size: 16.5)
                              .copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      if (serving) ...[
                        const SizedBox(width: 6),
                        const SxBall(size: 15, float: false, glow: false),
                      ],
                      if (won) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.emoji_events_rounded, size: 16, color: c.voltFill),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      // Games won, out of the games needed.
                      for (var i = 0; i < needed; i++)
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i < score.gamesWon(side) ? c.voltFill : Colors.transparent,
                            border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
                          ),
                        ),
                      if (serving) ...[
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            score.serve.serverNumber == null ? 'SERVING' : 'SERVING · ${score.serve.serverNumber}',
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            style: SxType.label(c.voltFill, size: 10.5),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            for (final g in done)
              SizedBox(
                width: gameW,
                child: Text(
                  '${g.of(side)}',
                  textAlign: TextAlign.center,
                  style: SxType.number(19, g.of(side) > g.of(side.opponent) ? Colors.white : Colors.white.withValues(alpha: 0.45),
                      weight: g.of(side) > g.of(side.opponent) ? FontWeight.w800 : FontWeight.w600),
                ),
              ),
            if (!over) _PointsBox(key: Key('points-${side.name}'), points: points, serving: serving, flashToken: flashToken),
          ],
        ),
      ),
    );
  }
}

/// The points in the game being played. The number rolls up when it
/// changes and the box lights up volt for a moment.
class _PointsBox extends StatelessWidget {
  const _PointsBox({super.key, required this.points, required this.serving, required this.flashToken});

  final int points;
  final bool serving;
  final int? flashToken;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final reduce = sxReduceMotion(context);
    Widget box(double glow) => Container(
          width: _SideLine.pointsW - 8,
          height: 58,
          margin: const EdgeInsets.only(left: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Color.lerp(Colors.white.withValues(alpha: serving ? 0.12 : 0.06), c.voltFill, glow),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: serving ? c.voltFill.withValues(alpha: 0.8) : Colors.white.withValues(alpha: 0.14), width: 1.4),
            boxShadow: serving || glow > 0 ? c.glowOf(c.voltFill, strength: 0.5 + glow) : null,
          ),
          child: ClipRect(
            child: AnimatedSwitcher(
              duration: reduce ? Duration.zero : const Duration(milliseconds: 420),
              switchInCurve: Curves.easeOutBack,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, a) => SlideTransition(
                position: Tween(begin: const Offset(0, 0.9), end: Offset.zero).animate(a),
                child: FadeTransition(opacity: a, child: child),
              ),
              child: Text(
                '$points',
                key: ValueKey(points),
                style: SxType.hero(52, Color.lerp(Colors.white, c.onVolt, glow)!),
              ),
            ),
          ),
        );
    if (flashToken == null || reduce) return box(0);
    return TweenAnimationBuilder<double>(
      key: ValueKey('flash$flashToken'),
      tween: Tween(begin: 1, end: 0),
      duration: const Duration(milliseconds: 1100),
      curve: Curves.easeOutCubic,
      builder: (_, v, _) => box(v * 0.85),
    );
  }
}

class _ListenButton extends StatelessWidget {
  const _ListenButton({required this.on, required this.onTap});

  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Semantics(
      button: true,
      toggled: on,
      label: 'Spoken commentary',
      excludeSemantics: true,
      child: Tappable(
        key: const Key('liveCommentary'),
        onTap: onTap,
        radius: 20,
        child: AnimatedContainer(
          duration: Sx.medium,
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? c.voltFill : Colors.white.withValues(alpha: 0.14),
            boxShadow: on ? c.glowOf(c.voltFill) : null,
          ),
          child: Icon(on ? Icons.volume_up_rounded : Icons.volume_off_rounded, size: 20, color: on ? c.onVolt : Colors.white),
        ),
      ),
    );
  }
}

/// What the moment is: match point, game point, or what the last rally did.
typedef _Moment = ({String text, String? detail, bool strong});

_Moment? _moment(LocalMatch match, LiveStep step) {
  final score = step.score;
  if (match.isOver) {
    final w = match.winner!;
    return (text: 'GAME, SET & MATCH', detail: match.teamLabel(w), strong: true);
  }
  for (final side in Side.values) {
    if (isMatchPoint(match, score, side)) return (text: 'MATCH POINT', detail: match.teamLabel(side), strong: true);
  }
  for (final side in Side.values) {
    if (isGamePoint(match, score, side)) return (text: 'GAME POINT', detail: match.teamLabel(side), strong: true);
  }
  final e = step.events;
  final winner = step.rallyWinner;
  if (winner == null) return null;
  if (e.contains(LiveEvent.gameWon)) return (text: 'NEW GAME', detail: '${match.teamLabel(step.court.serveSide)} to serve', strong: false);
  if (e.contains(LiveEvent.endsSwitched)) return (text: 'CHANGE OF ENDS', detail: null, strong: false);
  if (e.contains(LiveEvent.sideOut)) return (text: 'SIDE OUT', detail: '${match.teamLabel(step.court.serveSide)} to serve', strong: false);
  if (e.contains(LiveEvent.secondServer)) {
    return (text: 'SECOND SERVER', detail: match.names(step.court.serveSide)[step.court.serverIndex], strong: false);
  }
  final lead = score.currentGame.of(winner) - score.currentGame.of(winner.opponent);
  if (lead == 0) return (text: 'ALL SQUARE', detail: '${score.currentGame.a}–${score.currentGame.b}', strong: false);
  return (text: 'POINT', detail: match.teamLabel(winner), strong: false);
}

class _MomentStrip extends StatelessWidget {
  const _MomentStrip({required this.match, required this.step, required this.moment});

  final LocalMatch match;
  final LiveStep step;
  final _Moment? moment;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final m = moment;
    final call = match.isOver ? null : match.sport.engine.scoreCall(match.setup, step.score).replaceAll('-', ' – ');
    return Row(
      children: [
        if (call != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Semantics(
              label: 'Score call $call',
              excludeSemantics: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('CALL', style: SxType.label(Colors.white.withValues(alpha: 0.55), size: 10)),
                  const SizedBox(width: 6),
                  Text(call, style: SxType.number(17, Colors.white, weight: FontWeight.w800)),
                ],
              ),
            ),
          ),
        const SizedBox(width: Sx.s8),
        if (m != null)
          Expanded(
            child: AnimatedSwitcher(
              duration: Sx.medium,
              transitionBuilder: (child, a) => FadeTransition(
                opacity: a,
                child: ScaleTransition(scale: Tween(begin: 0.9, end: 1.0).animate(a), child: child),
              ),
              child: Container(
                key: ValueKey('${m.text}${m.detail}${step.score.rallies}'),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  gradient: m.strong ? c.brand : null,
                  color: m.strong ? null : Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: m.strong ? c.glowOf(c.voltFill, strength: 0.8) : null,
                ),
                child: Semantics(
                  liveRegion: true,
                  label: [m.text, ?m.detail].join(', '),
                  excludeSemantics: true,
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: m.text, style: SxType.label(m.strong ? c.onVolt : c.voltFill, size: 12)),
                      if (m.detail != null)
                        TextSpan(
                          text: '  ${m.detail}',
                          style: SxType.caption(m.strong ? c.onVolt : Colors.white, size: 12.5).copyWith(fontWeight: FontWeight.w700),
                        ),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ─── Court ───────────────────────────────────────────────────────────────

/// The court from above, exactly as the scorer sees it, and a line under it
/// saying who serves from where and who receives.
class _Court extends StatelessWidget {
  const _Court({required this.match, required this.step, required this.flash, required this.banner});

  final LocalMatch match;
  final LiveStep step;
  final CourtFlash? flash;
  final CourtBanner? banner;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final court = step.court;
    final over = match.isOver;
    final server = match.names(court.serveSide)[court.serverIndex];
    final receiver = match.names(court.serveSide.opponent)[court.receiverIndex];
    return Container(
      key: const Key('liveCourt'),
      decoration: BoxDecoration(
        color: const Color(0xFF09121E),
        borderRadius: BorderRadius.circular(Sx.radiusLg),
        border: Border.all(color: c.cardEdge),
        boxShadow: c.cardShadow,
      ),
      child: Column(
        children: [
          // Portrait: the ends are top and bottom, so each team gets the
          // full width of the screen and the players have room.
          Padding(
            padding: const EdgeInsets.fromLTRB(Sx.s12, Sx.s12, Sx.s12, Sx.s4),
            child: _EndTag(match: match, side: court.aOnLeft ? Side.a : Side.b),
          ),
          LayoutBuilder(
            builder: (context, box) => SizedBox(
              height: math.min(box.maxWidth * 1.3, 540),
              child: LiveCourtView(
                match: match,
                step: step,
                vertical: true,
                onRally: (_) {},
                enabled: false,
                spectator: true,
                flash: flash,
                banner: banner,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Sx.s12, Sx.s4, Sx.s12, Sx.s8),
            child: _EndTag(match: match, side: court.aOnLeft ? Side.b : Side.a),
          ),
          if (!over)
            Padding(
              padding: const EdgeInsets.fromLTRB(Sx.s16, Sx.s4, Sx.s16, Sx.s12),
              child: Semantics(
                liveRegion: true,
                label: '$server serves from the ${step.court.serverCourt.label.toLowerCase()} court to $receiver',
                excludeSemantics: true,
                child: Row(
                  children: [
                    const SxBall(size: 16, float: false, glow: false),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text.rich(
                        TextSpan(children: [
                          TextSpan(text: _first(server), style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
                          TextSpan(text: ' serves from the ${court.serverCourt.label.toLowerCase()}  →  '),
                          TextSpan(text: _first(receiver), style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
                          const TextSpan(text: ' receives'),
                        ]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SxType.caption(Colors.white.withValues(alpha: 0.7), size: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EndTag extends StatelessWidget {
  const _EndTag({required this.match, required this.side});

  final LocalMatch match;
  final Side side;

  @override
  Widget build(BuildContext context) {
    final color = CourtTopView.teamColor(context.sx, side);
    return Container(
      constraints: const BoxConstraints(maxWidth: 170),
      padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(shortSide(match, side).toUpperCase(),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.label(Colors.white, size: 11.5)),
          ),
        ],
      ),
    );
  }
}

String _first(String name) => name.trim().split(' ').first;

// ─── Pulse ───────────────────────────────────────────────────────────────

/// Four numbers that say how the match is going.
class _Pulse extends StatelessWidget {
  const _Pulse({required this.match, required this.steps, required this.analytics});

  final LocalMatch match;
  final List<LiveStep> steps;
  final MatchAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final sideOuts = steps.where((s) => s.events.contains(LiveEvent.sideOut)).length;
    final a = analytics.stats[Side.a]!, b = analytics.stats[Side.b]!;
    final runSide = a.bestRun >= b.bestRun ? Side.a : Side.b;
    final run = math.max(a.bestRun, b.bestRun);
    final tiles = [
      ('${analytics.rallies.length}', 'RALLIES', null),
      ('$sideOuts', 'SIDE OUTS', null),
      ('${analytics.leadChanges}', 'LEAD CHANGES', null),
      ('$run', 'BEST RUN', run == 0 ? null : CourtTopView.teamColor(c, runSide)),
    ];
    return Row(
      children: [
        for (final (i, (value, label, dot)) in tiles.indexed) ...[
          if (i > 0) const SizedBox(width: Sx.s8),
          Expanded(
            child: Semantics(
              label: '$label: $value',
              excludeSemantics: true,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: Sx.s12, horizontal: 6),
                decoration: BoxDecoration(
                  gradient: c.card,
                  borderRadius: BorderRadius.circular(Sx.radius),
                  border: Border.all(color: c.cardEdge),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SxBump(value: value, child: Text(value, style: SxType.number(26, c.ink, weight: FontWeight.w800))),
                        if (dot != null) ...[
                          const SizedBox(width: 4),
                          Container(width: 7, height: 7, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1, style: SxType.label(c.inkMuted, size: 10))),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Play by play ────────────────────────────────────────────────────────

/// The rallies, newest first, each saying what happened and the score after.
class _PlayByPlay extends StatefulWidget {
  const _PlayByPlay({required this.match, required this.steps});

  final LocalMatch match;
  final List<LiveStep> steps;

  @override
  State<_PlayByPlay> createState() => _PlayByPlayState();
}

class _PlayByPlayState extends State<_PlayByPlay> {
  static const _shown = 8;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final m = widget.match;
    final steps = widget.steps;
    final now = DateTime.now();
    final entries = [
      for (var i = steps.length - 1; i >= 1; i--)
        if (steps[i].rallyWinner != null || steps[i].events.isNotEmpty) i,
    ];
    if (entries.isEmpty) {
      return SxBlock(
        child: Row(
          children: [
            Icon(Icons.sports_tennis_rounded, color: c.inkMuted),
            const SizedBox(width: Sx.s12),
            Expanded(child: Text('First serve coming up. Rallies appear here as they are played.', style: SxType.body(c.inkMuted, size: 14))),
          ],
        ),
      );
    }
    final shown = _all ? entries : entries.take(_shown).toList();
    return SxBlock(
      padding: const EdgeInsets.fromLTRB(Sx.s12, Sx.s8, Sx.s12, Sx.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (n, i) in shown.indexed)
            _PlayRow(
              key: ValueKey('play-$i'),
              match: m,
              before: steps[i - 1],
              step: steps[i],
              at: m.events[i - 1].recordedAt,
              now: now,
              latest: n == 0,
              last: n == shown.length - 1,
            ),
          if (entries.length > _shown)
            Tappable(
              key: const Key('playByPlayAll'),
              onTap: () => setState(() => _all = !_all),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Sx.s12),
                child: Text(
                  _all ? 'Show fewer' : 'Show all ${entries.length} rallies',
                  textAlign: TextAlign.center,
                  style: SxType.caption(c.isDark ? c.cyan : c.blue, size: 13.5).copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PlayRow extends StatelessWidget {
  const _PlayRow({
    super.key,
    required this.match,
    required this.before,
    required this.step,
    required this.at,
    required this.now,
    required this.latest,
    required this.last,
  });

  final LocalMatch match;
  final LiveStep before;
  final LiveStep step;
  final DateTime at;
  final DateTime now;
  final bool latest;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final m = match;
    final e = step.events;
    final w = step.rallyWinner;
    final game = before.score.gameNumber;
    final after = e.contains(LiveEvent.gameWon) || e.contains(LiveEvent.matchWon) ? step.score.games[game - 1] : step.score.currentGame;
    final server = m.names(before.court.serveSide)[before.court.serverIndex];
    final color = w == null ? c.inkMuted : CourtTopView.teamColor(c, w);
    String does(Side s, String one, String many) =>
        m.names(s).length > 1 && (s == Side.a ? m.details.teamA : m.details.teamB) == null ? many : one;

    final (IconData icon, String title, bool big) = switch (e) {
      _ when e.contains(LiveEvent.matchWon) => (Icons.workspace_premium_rounded, '${shortSide(m, w!)} ${does(w, 'wins', 'win')} the match', true),
      _ when e.contains(LiveEvent.gameWon) => (Icons.emoji_events_rounded, '${shortSide(m, w!)} ${does(w, 'takes', 'take')} game $game', true),
      _ when e.contains(LiveEvent.serveCorrected) => (Icons.edit_rounded, 'Service corrected', false),
      _ when e.contains(LiveEvent.sideOut) => (Icons.swap_horiz_rounded, 'Side out · ${shortSide(m, w!)} to serve', false),
      _ when e.contains(LiveEvent.secondServer) =>
        (Icons.looks_two_rounded, 'Second server · ${_first(m.names(step.court.serveSide)[step.court.serverIndex])}', false),
      _ when w != null => () {
          final was = before.score.currentGame;
          final tookLead = was.of(w) <= was.of(w.opponent) && after.of(w) > after.of(w.opponent);
          final level = after.a == after.b;
          final verb = level ? does(w, 'levels', 'level') : tookLead ? does(w, 'takes', 'take') : does(w, 'wins', 'win');
          return (Icons.add_circle_rounded, '${shortSide(m, w)} $verb${level ? ' it up' : tookLead ? ' the lead' : ' the point'}', false);
        }(),
      _ => (Icons.circle_outlined, 'Play', false),
    };
    final detail = 'G$game · ${_first(server)} served · ${timeAgo(at, now)}';
    final strong = big || latest;

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: big ? c.brand : null,
              color: big ? null : color.withValues(alpha: c.isDark ? 0.18 : 0.14),
            ),
            child: Icon(icon, size: 18, color: big ? c.onVolt : (c.isDark ? color : Color.lerp(color, Colors.black, 0.35))),
          ),
          const SizedBox(width: Sx.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SxType.body(c.ink, size: 14.5).copyWith(fontWeight: strong ? FontWeight.w800 : FontWeight.w600)),
                Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.caption(c.inkFaint, size: 12)),
              ],
            ),
          ),
          const SizedBox(width: Sx.s8),
          Text.rich(
            TextSpan(children: [
              TextSpan(text: '${after.a}', style: TextStyle(color: w == Side.a && e.contains(LiveEvent.point) ? c.ink : c.inkMuted)),
              TextSpan(text: '–', style: TextStyle(color: c.inkFaint)),
              TextSpan(text: '${after.b}', style: TextStyle(color: w == Side.b && e.contains(LiveEvent.point) ? c.ink : c.inkMuted)),
            ]),
            style: SxType.number(20, c.inkMuted, weight: FontWeight.w800),
          ),
        ],
      ),
    );

    return Semantics(
      label: '$title. ${after.a} to ${after.b}. $detail',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: c.line.withValues(alpha: 0.6)))),
        child: latest ? SxReveal(offset: 12, child: row) : row,
      ),
    );
  }
}

// ─── Head to head ────────────────────────────────────────────────────────

class _HeadToHead extends StatelessWidget {
  const _HeadToHead({required this.match, required this.analytics});

  final LocalMatch match;
  final MatchAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final a = analytics.stats[Side.a]!, b = analytics.stats[Side.b]!;
    String pct(int won, int of) => of == 0 ? '–' : '${(won * 100 / of).round()}%';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChartLegend(match: match),
        const SizedBox(height: Sx.s8),
        VersusRow(label: 'Points won', a: a.points, b: b.points),
        VersusRow(label: 'Rallies won', a: a.ralliesWon, b: b.ralliesWon),
        VersusRow(
          label: 'Points on serve',
          a: a.servicePoints,
          b: b.servicePoints,
          valueA: '${a.servicePoints}/${a.serveRallies}',
          valueB: '${b.servicePoints}/${b.serveRallies}',
        ),
        VersusRow(
          label: 'Serve won back',
          a: a.returnRalliesWon,
          b: b.returnRalliesWon,
          valueA: pct(a.returnRalliesWon, a.returnRallies),
          valueB: pct(b.returnRalliesWon, b.returnRallies),
        ),
        VersusRow(label: 'Best run', a: a.bestRun, b: b.bestRun),
        VersusRow(label: 'Biggest lead', a: a.biggestLead, b: b.biggestLead),
        const SizedBox(height: Sx.s12),
        Text('ON SERVE', style: SxType.label(c.inkMuted, size: 11)),
        const SizedBox(height: Sx.s8),
        for (final s in analytics.servers)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Semantics(
              label: '${s.name}: ${s.won} points from ${s.served} serves',
              excludeSemantics: true,
              child: Row(
                children: [
                  PlayerDp(name: s.name, size: 26, edge: chartColor(c, s.side)),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 84,
                    child: Text(_first(s.name), maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.body(c.ink, size: 14)),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: s.served == 0 ? 0 : s.won / s.served,
                        minHeight: 8,
                        backgroundColor: c.line,
                        color: chartColor(c, s.side),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 44,
                    child: Text('${s.won}/${s.served}', textAlign: TextAlign.right, style: SxType.number(16, c.ink)),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
