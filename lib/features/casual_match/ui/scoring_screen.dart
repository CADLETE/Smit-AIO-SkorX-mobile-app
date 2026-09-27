import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../design/design.dart';
import '../../../sports/core/score_state.dart';
import '../live/commentary.dart';
import '../live/live_court.dart';
import '../local_match.dart';
import '../scoring_controller.dart';
import 'court_top_view.dart';
import 'live/live_court_view.dart';
import '../handover/handover_prompt.dart';
import '../handover/scoring_handover.dart';
import 'live/game_break_view.dart';
import 'live/live_sheets.dart';
import 'live/match_complete_view.dart';
import 'live/share_result.dart';
import '../live/match_analytics.dart';
import 'scoring_labels.dart';
import '../offline/ui/offline_ui.dart';

export 'scoring_labels.dart' show rallyActionLabel;

/// The clock behind the double-tap guard; tests replace it.
final scoringClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Live scoring: one rally, one tap.
///
/// The court is the interface. The scorer taps the half of the side that won
/// the rally; the engine works out the point or side-out, the next server,
/// and where everyone now stands, and the court animates to match. Undo
/// takes back everything the last tap did, because the whole state is
/// replayed from the recorded rallies.
class ScoringScreen extends ConsumerStatefulWidget {
  const ScoringScreen({super.key});

  /// Taps closer together than this are treated as one accidental double tap.
  static const tapGuard = Duration(milliseconds: 400);

  @override
  ConsumerState<ScoringScreen> createState() => _ScoringScreenState();
}

class _ScoringScreenState extends ConsumerState<ScoringScreen> {
  DateTime _lastTap = DateTime.fromMillisecondsSinceEpoch(0);
  int _token = 0;
  CourtFlash? _flash;
  CourtBanner? _banner;
  bool _settingsReady = false;
  int _tutorialStep = 0;

  @override
  void initState() {
    super.initState();
    // The screen stays on while scoring; a dark phone mid-rally loses points.
    WakelockPlus.enable().catchError((_) {});
    // The court has room to breathe sideways, so scoring may turn landscape.
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    ref.read(liveSettingsProvider.notifier).ready.then((_) {
      if (mounted) setState(() => _settingsReady = true);
    });
  }

  @override
  void dispose() {
    WakelockPlus.disable().catchError((_) {});
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    super.dispose();
  }

  Future<void> _rally(Side side) async {
    final now = ref.read(scoringClockProvider)();
    if (now.difference(_lastTap) < ScoringScreen.tapGuard) return;
    _lastTap = now;
    HapticFeedback.mediumImpact();
    await ref.read(scoringControllerProvider.notifier).rallyWonBy(side);
  }

  Future<void> _undo() async {
    HapticFeedback.lightImpact();
    await ref.read(scoringControllerProvider.notifier).undo();
  }

  Future<void> _pause() async {
    final reason = await showPauseReasons(context);
    if (reason != null) await ref.read(scoringControllerProvider.notifier).pause(reason);
  }

  Future<void> _toggleSound() async {
    final on = !ref.read(liveSettingsProvider).sound;
    if (!on) ref.read(commentatorProvider).stop();
    HapticFeedback.selectionClick();
    await ref.read(liveSettingsProvider.notifier).update((s) => s.copyWith(sound: on));
  }

  Future<void> _menu(LocalMatch match, LiveStep step) async {
    final action = await showLiveMenu(context, match);
    if (action == null || !mounted) return;
    switch (action) {
      case LiveMenuAction.rules:
        await showRulesSheet(context, ref, match);
      case LiveMenuAction.sound:
        await showSoundSheet(context);
      case LiveMenuAction.serve:
        await showServeCorrection(context, ref, match, step);
      case LiveMenuAction.info:
        await showMatchInfo(context, match);
      case LiveMenuAction.walkover:
        await showEarlyEnd(context, ref, match, EarlyEnd.walkover);
      case LiveMenuAction.retire:
        await showEarlyEnd(context, ref, match, EarlyEnd.retired);
      case LiveMenuAction.scorer:
        await showChangeScorer(context, ref, match);
      case LiveMenuAction.swapEnds:
        await ref.read(scoringControllerProvider.notifier).adjustCourt(CourtFix.swapEnds);
      case LiveMenuAction.swapServing:
        await ref.read(scoringControllerProvider.notifier).adjustCourt(CourtFix.swapServingPlayers);
      case LiveMenuAction.swapReceiving:
        await ref.read(scoringControllerProvider.notifier).adjustCourt(CourtFix.swapReceivingPlayers);
    }
  }

  /// Leaving mid-match is easy to do by accident, so it asks first.
  Future<void> _confirmExit() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) {
        final c = context.sx;
        return AlertDialog(
          backgroundColor: c.surface,
          title: Text('Leave live scoring?', style: SxType.heading(c.ink, size: 19)),
          content: Text(
            'The match stays saved on this phone, exactly as it is. Come back any time from the Resume bar.',
            style: SxType.body(c.inkMuted),
          ),
          actions: [
            TextButton(key: const Key('leaveScoring'), onPressed: () => Navigator.pop(context, true), child: const Text('Leave')),
            FilledButton(
              key: const Key('stayScoring'),
              style: FilledButton.styleFrom(backgroundColor: c.voltFill, foregroundColor: c.onVolt),
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep scoring'),
            ),
          ],
        );
      },
    );
    if (leave == true && mounted) {
      await ref.read(commentatorProvider).stop();
      if (mounted) context.go('/player/home');
    }
  }

  Future<void> _finish() async {
    await ref.read(commentatorProvider).stop();
    await ref.read(scoringControllerProvider.notifier).close();
    if (mounted) context.go('/player/home');
  }

  /// Everything a recorded rally sets off: flash, banner, haptics, sound, voice.
  void _react(LocalMatch? before, LocalMatch? after) {
    if (before == null || after == null || before.id != after.id) return;
    final settings = ref.read(liveSettingsProvider);
    if (after.outcome != null && before.outcome == null) {
      HapticFeedback.heavyImpact();
      if (settings.speaks) ref.read(commentatorProvider).say(earlyEndCommentary(after));
      return;
    }
    if (before.awaitingHandover && !after.awaitingHandover && after.scorers.length == before.scorers.length) {
      final who = ref.read(scoringControllerProvider.notifier).lastDeclined;
      setState(() => _banner = who == null
          ? CourtBanner('REQUEST CANCELLED', detail: 'Scoring carries on here', token: ++_token)
          : CourtBanner('DECLINED', detail: '$who said no · scoring carries on here', token: ++_token));
      ref.read(scoringControllerProvider.notifier).lastDeclined = null;
      return;
    }
    if (after.scorers.length > before.scorers.length) {
      setState(() => _banner = CourtBanner('NEW SCORER', detail: after.scorers.last.name, token: ++_token));
      return;
    }
    if (after.adjustments.length != before.adjustments.length && after.events.length == before.events.length) {
      final added = after.adjustments.length > before.adjustments.length;
      setState(() => _banner = CourtBanner(
            added ? after.adjustments.last.fix.label.toUpperCase() : 'UNDONE',
            detail: added ? 'Court updated' : '${before.adjustments.last.fix.label} taken back',
            token: ++_token,
          ));
      return;
    }
    if (after.endChanges.length > before.endChanges.length) {
      // The break is over: the next game starts on the ends just confirmed.
      final step = replayLive(after).last;
      final serving = after.teamLabel(step.court.serveSide);
      setState(() => _banner = CourtBanner('GAME ${step.score.gameNumber}', detail: '$serving to serve', token: ++_token, strong: true));
      if (settings.speaks) ref.read(commentatorProvider).say('Game ${step.score.gameNumber}. ${spokenSide(after, step.court.serveSide)} to serve.');
      return;
    }
    if (after.rules != before.rules) {
      setState(() => _banner = CourtBanner('NEW FORMAT', detail: after.rules.describe(), token: ++_token));
      return;
    }
    if (after.events.length < before.events.length || (before.outcome != null && after.outcome == null)) {
      ref.read(commentatorProvider).stop();
      setState(() {
        _flash = null;
        _banner = CourtBanner('UNDONE', detail: 'Last rally taken back', token: ++_token);
      });
      return;
    }
    if (after.events.length <= before.events.length) return;

    final steps = replayLive(after);
    final step = steps.last;
    final prev = steps[steps.length - 2];
    final events = step.events;
    final winner = step.rallyWinner;
    final line = commentaryFor(after, step, settings.commentary, before: prev);
    if (settings.sound) SystemSound.play(SystemSoundType.click);

    if (events.contains(LiveEvent.matchWon) || events.contains(LiveEvent.gameWon)) HapticFeedback.heavyImpact();
    final banner = rallyBanner(after, step, ++_token);

    setState(() {
      if (winner != null) _flash = CourtFlash(winner, point: events.contains(LiveEvent.point), token: ++_token);
      _banner = banner ?? _banner;
    });
    if (settings.speaks && line != null) ref.read(commentatorProvider).say(line);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<LocalMatch?>(scoringControllerProvider, _react);
    final match = ref.watch(scoringControllerProvider);
    final settings = ref.watch(liveSettingsProvider);
    final c = context.sx;

    if (match == null) {
      return Scaffold(
        backgroundColor: c.canvas,
        body: SafeArea(
          child: Column(
            children: [
              SxBackBar(onBack: () => context.go('/player/home')),
              const Expanded(
                child: EmptyBlock(title: 'No match in progress', message: 'Start a match from Home to score it here.'),
              ),
            ],
          ),
        ),
      );
    }

    if (match.isOver) {
      return Scaffold(
        backgroundColor: c.canvas,
        body: SafeArea(
          child: Column(
            children: [
              SxBackBar(
                title: 'Result',
                onBack: _finish,
                actions: [
                  SxIconAction(
                    key: const Key('shareResult'),
                    icon: Icons.ios_share_rounded,
                    label: 'Share result',
                    onTap: () => shareMatchResult(context, match, analyzeMatch(match)),
                  ),
                ],
              ),
              Expanded(child: MatchCompleteView(match: match, onDone: _finish, onUndo: _undo)),
            ],
          ),
        ),
      );
    }

    final steps = replayLive(match);
    final step = steps.last;
    final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    final atBreak = match.awaitingEndChange;
    final showTutorial = _settingsReady && !settings.tutorialSeen && match.events.isEmpty && !match.isPaused;

    final court = LiveCourtView(
      match: match,
      step: step,
      vertical: !landscape,
      onRally: _rally,
      enabled: !match.isPaused && !showTutorial && !atBreak && !match.awaitingHandover,
      flash: _flash,
      banner: _banner,
    );
    final header = _LiveHeader(match: match, step: step, onBack: _confirmExit);
    final board = _ScoreBoard(match: match, step: step);
    final call = _CallStrip(match: match, step: step);
    final controls = _ControlBar(
      canUndo: match.events.isNotEmpty,
      sound: settings.sound,
      onUndo: _undo,
      onPause: _pause,
      onSound: _toggleSound,
      onMenu: () => _menu(match, step),
    );

    final body = landscape
        ? Row(
            children: [
              Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(Sx.s8, Sx.s8, 0, Sx.s8), child: court)),
              SizedBox(
                width: 340,
                child: Column(
                  children: [
                    header,
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: Sx.s12),
                        children: [board, const SizedBox(height: Sx.s8), call],
                      ),
                    ),
                    controls,
                  ],
                ),
              ),
            ],
          )
        : Column(
            children: [
              header,
              Padding(padding: const EdgeInsets.symmetric(horizontal: Sx.s12), child: board),
              const SizedBox(height: Sx.s8),
              Padding(padding: const EdgeInsets.symmetric(horizontal: Sx.s12), child: call),
              Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(Sx.s12, Sx.s8, Sx.s12, Sx.s8), child: court)),
              controls,
            ],
          );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit();
      },
      child: SyncNotices(
      localId: match.id,
      child: Scaffold(
      backgroundColor: c.canvas,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: body),
            if (atBreak && !match.isPaused)
              Positioned.fill(
                child: GameBreakView(
                  match: match,
                  steps: steps,
                  onUndo: _undo,
                  onAnswer: (switched) => ref
                      .read(scoringControllerProvider.notifier)
                      .setEndChange(step.score.gameNumber - 1, switched: switched),
                ),
              ),
            if (match.isPaused) Positioned.fill(child: _PausedOverlay(match: match, step: step)),
            if (match.handover != null)
              Positioned.fill(
                child: HandoverWaitingOverlay(
                  request: match.handover!,
                  simulated: ref.watch(scoringHandoverServiceProvider) is SimulatedHandoverService,
                ),
              ),
            if (showTutorial)
              Positioned.fill(
                child: _Tutorial(
                  step: _tutorialStep,
                  onNext: () => setState(() => _tutorialStep++),
                  onDone: () => ref.read(liveSettingsProvider.notifier).update((s) => s.copyWith(tutorialSeen: true)),
                ),
              ),
          ],
        ),
      ),
      ),
      ),
    );
  }

}

// ─── Header ──────────────────────────────────────────────────────────────

class _LiveHeader extends StatelessWidget {
  const _LiveHeader({required this.match, required this.step, required this.onBack});

  final LocalMatch match;
  final LiveStep step;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final score = step.score;
    final game = match.rules.bestOf == 1 ? '1 game' : 'Game ${score.gameNumber} of ${match.rules.bestOf}';
    final where = match.details.courtLabel ?? match.locationName;
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          const SizedBox(width: Sx.s4),
          SxIconAction(icon: Icons.arrow_back_rounded, label: 'Back to home. The match stays saved.', onTap: onBack),
          const SizedBox(width: Sx.s4),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    LivePulse(size: 7, color: match.isPaused ? c.caution : c.live),
                    const SizedBox(width: 6),
                    Text(match.isPaused ? 'PAUSED' : 'LIVE', style: SxType.label(match.isPaused ? c.caution : c.live, size: 12)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(matchTypeLabel(match),
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.heading(c.ink, size: 16)),
                    ),
                  ],
                ),
                Text(
                  [?where, game, 'to ${match.rules.pointsToWin}'].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SxType.caption(c.inkMuted, size: 12),
                ),
              ],
            ),
          ),
          // Every point is saved on this phone first; this says where SkorX is.
          SyncStatusChip(localId: match.id),
        ],
      ),
    );
  }
}

// ─── Scoreboard ──────────────────────────────────────────────────────────

/// Broadcast-style score bug: one row per side in court order, earlier
/// games small, the current game big.
class _ScoreBoard extends StatelessWidget {
  const _ScoreBoard({required this.match, required this.step});

  final LocalMatch match;
  final LiveStep step;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final score = step.score;
    final order = step.court.onLeft(Side.a) ? const [Side.a, Side.b] : const [Side.b, Side.a];
    final finished = score.games.sublist(0, score.games.length - 1);
    return Container(
      padding: const EdgeInsets.fromLTRB(Sx.s12, Sx.s8, Sx.s12, Sx.s8),
      decoration: BoxDecoration(
        gradient: c.card,
        borderRadius: BorderRadius.circular(Sx.radius),
        border: Border.all(color: c.cardEdge),
      ),
      child: Column(
        children: [
          if (finished.isNotEmpty || match.rules.bestOf > 1)
            Row(
              children: [
                const Expanded(child: SizedBox()),
                for (var i = 0; i < finished.length; i++)
                  SizedBox(width: 30, child: Text('G${i + 1}', textAlign: TextAlign.center, style: SxType.label(c.inkFaint, size: 10))),
                SizedBox(
                  width: 64,
                  child: Text('GAME ${score.gameNumber}', textAlign: TextAlign.right, style: SxType.label(c.inkMuted, size: 10)),
                ),
              ],
            ),
          for (final side in order) _ScoreRow(match: match, step: step, side: side, finished: finished),
        ],
      ),
    );
  }
}

class _ScoreRow extends StatelessWidget {
  const _ScoreRow({required this.match, required this.step, required this.side, required this.finished});

  final LocalMatch match;
  final LiveStep step;
  final Side side;
  final List<GameScore> finished;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final score = step.score;
    final serving = step.court.serveSide == side;
    final points = score.currentGame.of(side);
    final color = CourtTopView.teamColor(c, side);
    final matchPoint = isMatchPoint(match, score, side);
    final gamePoint = !matchPoint && isGamePoint(match, score, side);
    final server = serving ? match.names(side)[step.court.serverIndex].split(' ').first : null;

    return Semantics(
      label: '${match.teamLabel(side)}, $points points, ${score.gamesWon(side)} games${serving ? ', serving' : ''}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Container(width: 4, height: 38, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: Sx.s8),
            SizedBox(
              width: 22,
              child: AnimatedSwitcher(
                duration: Sx.medium,
                transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
                child: serving
                    ? const SxBall(key: ValueKey('serve'), size: 18, float: false, glow: false)
                    : const SizedBox(key: ValueKey('no')),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    match.teamLabel(side),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SxType.heading(c.ink, size: 16).copyWith(fontWeight: serving ? FontWeight.w800 : FontWeight.w600),
                  ),
                  if (matchPoint || gamePoint)
                    Text(matchPoint ? 'MATCH POINT' : 'GAME POINT', style: SxType.label(c.volt, size: 11))
                  else if (server != null)
                    Text(
                      score.serve.serverNumber == null ? '$server serving' : '$server serving · server ${score.serve.serverNumber}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SxType.caption(c.inkMuted, size: 11.5),
                    ),
                ],
              ),
            ),
            for (final g in finished)
              SizedBox(
                width: 30,
                child: Text(
                  '${g.of(side)}',
                  textAlign: TextAlign.center,
                  style: SxType.number(18, g.of(side) > g.of(side.opponent) ? c.ink : c.inkFaint,
                      weight: g.of(side) > g.of(side.opponent) ? FontWeight.w800 : FontWeight.w500),
                ),
              ),
            SizedBox(
              width: 64,
              child: Align(
                alignment: Alignment.centerRight,
                child: SxBump(
                  value: points,
                  child: Text(
                    '$points',
                    key: Key('points-${side.name}'),
                    style: SxType.number(42, serving ? c.volt : c.ink, weight: FontWeight.w800),
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

/// The score call with every number named, so nobody has to remember that
/// "4-3-2" means server's score, receiver's score, server two.
class _CallStrip extends StatelessWidget {
  const _CallStrip({required this.match, required this.step});

  final LocalMatch match;
  final LiveStep step;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final parts = scoreCallParts(match, step.score);
    final court = step.court;
    final server = match.names(court.serveSide)[court.serverIndex].split(' ').first;
    return Semantics(
      label: 'Score call ${parts.map((p) => p.$1).join(' ')}. $server serves from the ${court.serverCourt.label} court',
      excludeSemantics: true,
      child: Row(
        children: [
          Text('CALL', style: SxType.label(c.inkMuted, size: 11)),
          const SizedBox(width: Sx.s8),
          for (final (i, (number, label)) in parts.indexed) ...[
            if (i > 0) Text('–', style: SxType.number(20, c.inkFaint)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(number, key: Key('call-$i'), style: SxType.number(26, i == 2 ? c.cyan : c.ink, weight: FontWeight.w800)),
                  Text(label, style: SxType.label(c.inkFaint, size: 9)),
                ],
              ),
            ),
          ],
          const Spacer(),
          Flexible(
            flex: 3,
            child: Container(
              padding: const EdgeInsets.fromLTRB(6, 5, 10, 5),
              decoration: BoxDecoration(
                color: c.voltFill.withValues(alpha: c.isDark ? 0.12 : 0.25),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.voltFill.withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SxBall(size: 16, float: false, glow: false),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '$server · ${court.serverCourt.label.toUpperCase()}',
                      key: const Key('serverTag'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SxType.label(c.ink, size: 12),
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

// ─── Controls ────────────────────────────────────────────────────────────

class _ControlBar extends StatelessWidget {
  const _ControlBar({
    required this.canUndo,
    required this.sound,
    required this.onUndo,
    required this.onPause,
    required this.onSound,
    required this.onMenu,
  });

  final bool canUndo;
  final bool sound;
  final VoidCallback onUndo;
  final VoidCallback onPause;
  final VoidCallback onSound;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Container(
      padding: const EdgeInsets.fromLTRB(Sx.s12, Sx.s8, Sx.s12, Sx.s8),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: _ControlButton(
              key: const Key('undo'),
              icon: Icons.undo_rounded,
              label: 'UNDO',
              onTap: canUndo ? onUndo : null,
              strong: true,
            ),
          ),
          const SizedBox(width: Sx.s8),
          Expanded(child: _ControlButton(key: const Key('pause'), icon: Icons.pause_rounded, label: 'PAUSE', onTap: onPause)),
          const SizedBox(width: Sx.s8),
          Expanded(
            child: _ControlButton(
              key: const Key('sound'),
              icon: sound ? Icons.volume_up_rounded : Icons.volume_off_rounded,
              label: sound ? 'SOUND' : 'MUTED',
              onTap: onSound,
            ),
          ),
          const SizedBox(width: Sx.s8),
          Expanded(child: _ControlButton(key: const Key('menu'), icon: Icons.more_horiz_rounded, label: 'MENU', onTap: onMenu)),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({super.key, required this.icon, required this.label, required this.onTap, this.strong = false});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final enabled = onTap != null;
    final fg = strong && enabled ? c.volt : c.ink;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: Opacity(
        opacity: enabled ? 1 : 0.35,
        child: Tappable(
          onTap: onTap,
          radius: Sx.radiusSm,
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              color: c.surface.withValues(alpha: c.isDark ? 0.7 : 1),
              borderRadius: BorderRadius.circular(Sx.radiusSm),
              border: Border.all(color: strong && enabled ? c.voltFill.withValues(alpha: 0.6) : c.cardEdge),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: fg),
                const SizedBox(height: 2),
                Text(label, style: SxType.label(fg, size: 10.5)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Overlays ────────────────────────────────────────────────────────────

class _PausedOverlay extends ConsumerWidget {
  const _PausedOverlay({required this.match, required this.step});

  final LocalMatch match;
  final LiveStep step;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final since = match.pausedAt!;
    return ColoredBox(
      color: c.canvas.withValues(alpha: 0.94),
      child: SxWidth(
        child: Padding(
          padding: const EdgeInsets.all(Sx.gutter),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SxPop(child: Icon(Icons.pause_circle_filled_rounded, size: 72, color: c.caution)),
              const SizedBox(height: Sx.s16),
              Text('MATCH PAUSED', key: const Key('pausedTitle'), style: SxType.verdict(40, c.ink)),
              const SizedBox(height: Sx.s8),
              Text('${match.pauseReason ?? 'Paused'} · since ${TimeOfDay.fromDateTime(since).format(context)}',
                  style: SxType.body(c.inkMuted)),
              const SizedBox(height: Sx.s24),
              Text(
                '${match.teamLabel(Side.a)}  ${step.score.currentGame.a} – ${step.score.currentGame.b}  ${match.teamLabel(Side.b)}',
                textAlign: TextAlign.center,
                style: SxType.heading(c.ink, size: 16),
              ),
              const SizedBox(height: Sx.s8),
              Text('Taps on the court are locked until you resume.', style: SxType.caption(c.inkMuted)),
              const SizedBox(height: Sx.s32),
              SxButton(
                key: const Key('resume'),
                label: 'Resume match',
                icon: Icons.play_arrow_rounded,
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  ref.read(scoringControllerProvider.notifier).resume();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Three quick cards the first time someone scores. Never again after.
class _Tutorial extends StatelessWidget {
  const _Tutorial({required this.step, required this.onNext, required this.onDone});

  final int step;
  final VoidCallback onNext;
  final VoidCallback onDone;

  static const _steps = [
    (Icons.touch_app_rounded, 'Tap the winning side',
        'Tap the half of the court that won the rally. SkorX handles the score, the serve and where everyone stands.'),
    (Icons.sports_tennis_rounded, 'The ball shows the server',
        'The glowing ball and SERVE tag follow the server. The dashed arrow points at the receiver.'),
    (Icons.undo_rounded, 'Made a mistake? Undo',
        'UNDO takes back the last rally completely: score, server and positions.'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final i = step.clamp(0, _steps.length - 1);
    final (icon, title, body) = _steps[i];
    final last = i == _steps.length - 1;
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.6),
      child: SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: SxWidth(
            child: Padding(
              padding: const EdgeInsets.all(Sx.gutter),
              child: SxReveal(
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
                          if (i == 1)
                            const SxBall(size: 40, float: false)
                          else
                            SxIconTile(icon: icon, size: 44, colors: [c.voltFill, c.olive]),
                          const Spacer(),
                          Text('${i + 1} / ${_steps.length}', style: SxType.label(c.inkMuted)),
                        ],
                      ),
                      const SizedBox(height: Sx.s12),
                      Text(title, style: SxType.title(c.ink, size: 28)),
                      const SizedBox(height: Sx.s8),
                      Text(body, style: SxType.body(c.inkMuted)),
                      const SizedBox(height: Sx.s16),
                      Row(
                        children: [
                          if (!last) SxButton.quiet(key: const Key('tutorialSkip'), label: 'Skip', onPressed: onDone),
                          const Spacer(),
                          SxButton(
                            key: const Key('tutorialNext'),
                            label: last ? 'Start scoring' : 'Next',
                            expand: false,
                            height: 48,
                            onPressed: last ? onDone : onNext,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
