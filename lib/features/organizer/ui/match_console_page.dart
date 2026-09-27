import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../design/player_dp.dart';
import '../../../design/tokens.dart' show SxContext;
import '../../../app/theme/typography.dart';
import '../../../shared/ui/components.dart';
import '../../../sports/core/match_rules.dart';
import '../../../sports/core/score_state.dart';
import '../../casual_match/ui/scoring_screen.dart' show scoringClockProvider;
import '../data/organizer_repository.dart';
import '../data/sample_organizer_repository.dart';
import '../data/tms_models.dart';
import '../scoring/match_console_controller.dart';
import 'org_widgets.dart';

/// Scoring a tournament match from the courtside phone. Each half of the
/// screen is "this side won the rally"; the engine decides point or side
/// out. Taps land on the phone first and sync behind the scenes.
class MatchConsolePage extends ConsumerStatefulWidget {
  const MatchConsolePage({super.key, required this.orgId, required this.tournamentId, required this.matchId});

  final String orgId;
  final String tournamentId;
  final String matchId;

  /// Taps closer together than this are one accidental double tap.
  static const tapGuard = Duration(milliseconds: 400);

  @override
  ConsumerState<MatchConsolePage> createState() => _MatchConsolePageState();
}

class _MatchConsolePageState extends ConsumerState<MatchConsolePage> {
  DateTime _lastTap = DateTime.fromMillisecondsSinceEpoch(0);
  var _resultShown = false;

  (String, String) get _key => (widget.tournamentId, widget.matchId);
  MatchConsoleController get _console => ref.read(matchConsoleProvider(_key).notifier);

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable().catchError((_) {});
  }

  @override
  void dispose() {
    WakelockPlus.disable().catchError((_) {});
    super.dispose();
  }

  Future<void> _rally(Side side) async {
    final now = ref.read(scoringClockProvider)();
    if (now.difference(_lastTap) < MatchConsolePage.tapGuard) return;
    _lastTap = now;
    HapticFeedback.mediumImpact();
    await _console.rally(side);
  }

  Future<void> _command(MatchCommand c) async {
    final problem = await _console.command(c);
    if (problem != null && mounted) showSkxToast(context, problem, icon: Icons.error_outline_rounded);
  }

  Future<void> _confirmResult(ConsoleState s) async {
    if (!s.ready || s.score.winner == null) {
      _resultShown = false;
      return;
    }
    final score = s.score;
    final m = s.match!;
    final winner = score.winner!;
    final colors = context.skorx.colors;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(SkorxSpace.xl, 0, SkorxSpace.xl, SkorxSpace.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('CONFIRM MATCH RESULT?', style: SkorxType.headline(28, color: colors.text)),
              const SizedBox(height: SkorxSpace.lg),
              for (final side in Side.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: SkorxSpace.sm),
                  child: Row(
                    children: [
                      if (side == winner)
                        Padding(
                          padding: const EdgeInsets.only(right: SkorxSpace.sm),
                          child: Icon(Icons.emoji_events_rounded, color: colors.limeText, size: 20),
                        ),
                      SideDps(names: sideNames(m, side), size: 28, edge: colors.surface),
                      const SizedBox(width: SkorxSpace.sm),
                      Expanded(
                        child: Text(
                          m.label(side),
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: side == winner ? FontWeight.w900 : FontWeight.w600,
                          ),
                        ),
                      ),
                      for (final g in score.games)
                        SizedBox(
                          width: 40,
                          child: Text(
                            '${g.of(side)}',
                            textAlign: TextAlign.right,
                            style: SkorxType.score(
                              26,
                              color: g.of(side) > g.of(side.opponent) ? colors.text : colors.textMuted,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: SkorxSpace.sm),
              Text(
                'Results go to both players, the draw and their SkorX Rating and Points as soon as you confirm.',
                style: TextStyle(color: colors.textMuted, height: 1.4),
              ),
              const SizedBox(height: SkorxSpace.xl),
              SkxButton(
                key: const Key('confirmResult'),
                label: 'Confirm result',
                onPressed: () => Navigator.pop(sheet, true),
              ),
              const SizedBox(height: SkorxSpace.sm),
              SkxButton.secondary(
                key: const Key('editScore'),
                label: 'Edit score (undo last point)',
                onPressed: () => Navigator.pop(sheet, false),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (confirmed == true) {
      final problem = await _console.confirmResult();
      if (!mounted) return;
      if (problem != null) {
        _resultShown = false;
        showSkxToast(context, problem, icon: Icons.error_outline_rounded);
      } else {
        HapticFeedback.heavyImpact();
        showSkxToast(context, 'Result confirmed. ${m.label(winner)} advance.');
      }
    } else {
      await _console.undo();
      _resultShown = false;
    }
  }

  Future<void> _enterResult(ConsoleState s) async {
    final games = await showModalBottomSheet<List<GameScore>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ResultEntrySheet(match: s.match!, rules: s.category!.rules),
    );
    if (games == null || !mounted) return;
    await runAction(
      context,
      () => ref.read(organizerRepositoryProvider).enterResult(widget.matchId, games, reason: 'Entered on the console'),
      success: 'Result saved.',
    );
    await _console.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(matchConsoleProvider(_key));
    final colors = context.skorx.colors;
    final can = orgPermissions(ref, widget.orgId);
    final back = '/org/${widget.orgId}/live';

    // The moment the last rally decides the match, ask to confirm it.
    ref.listen(matchConsoleProvider(_key), (prev, next) {
      if (!next.ready || next.match!.state != MatchState.live) return;
      if (next.score.isOver && !_resultShown) {
        _resultShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _confirmResult(ref.read(matchConsoleProvider(_key)));
        });
      }
    });

    if (!can.score) {
      return DetailScaffold(
        title: 'Score',
        fallback: back,
        body: const NoAccess(what: 'score matches'),
      );
    }
    if (!s.ready) {
      return DetailScaffold(
        title: 'Score',
        fallback: back,
        body: Padding(
          padding: const EdgeInsets.all(SkorxSpace.lg),
          child: s.sync == SyncStatus.loading
              ? const SkeletonCard(height: 300)
              : ErrorState(message: s.message ?? "We couldn't open this match.", onRetry: _console.refresh),
        ),
      );
    }

    final m = s.match!;
    final score = s.score;
    final court = ref.watch(courtsProvider(widget.tournamentId)).value?.where((c) => c.id == m.courtId).firstOrNull;
    final repo = ref.watch(organizerRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        automaticallyImplyLeading: false,
        titleSpacing: SkorxSpace.lg,
        title: Row(
          children: [
            SkxBackButton(fallback: back),
            const SizedBox(width: SkorxSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ['M${m.number}', ?court?.name].join(' · ').toUpperCase(),
                    style: SkorxType.headline(22, color: colors.text, weight: FontWeight.w800),
                  ),
                  Text(
                    '${m.roundLabel} · ${m.state == MatchState.completed ? 'Final' : 'Game ${score.gameNumber}'}',
                    style: TextStyle(fontSize: 12, color: colors.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            key: const Key('consoleUndo'),
            tooltip: 'Undo last point',
            onPressed: m.state == MatchState.live && (s.pending.isNotEmpty || s.confirmed.isNotEmpty)
                ? _console.undo
                : null,
            icon: const Icon(Icons.undo_rounded),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (v) async {
              switch (v) {
                case 'serve':
                  final chosen = await _pickServe(context, m, score);
                  if (chosen != null) await _console.correctServe(chosen);
                case 'pause':
                  await _command(MatchCommand.pause);
                case 'resume':
                  await _command(MatchCommand.resume);
                case 'enter':
                  await _enterResult(s);
                case 'offline':
                  final sample = repo as SampleOrganizerRepository;
                  setState(() => sample.offline = !sample.offline);
                  if (!sample.offline) await _console.retryNow();
              }
            },
            itemBuilder: (_) => [
              if (m.state == MatchState.live && !score.isOver)
                const PopupMenuItem(value: 'serve', child: Text('Change service')),
              if (m.state == MatchState.live) const PopupMenuItem(value: 'pause', child: Text('Pause match')),
              if (m.state == MatchState.paused) const PopupMenuItem(value: 'resume', child: Text('Resume match')),
              if (m.ready && s.pending.isEmpty)
                PopupMenuItem(
                  value: 'enter',
                  child: Text(m.state == MatchState.completed ? 'Correct the result' : 'Type in the result'),
                ),
              // Debug builds: try the offline queue without leaving the app.
              if (kDebugMode && repo is SampleOrganizerRepository)
                PopupMenuItem(value: 'offline', child: Text(repo.offline ? 'Reconnect (test)' : 'Go offline (test)')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _SyncBar(state: s, onRetry: _console.retryNow),
            if (s.sync == SyncStatus.conflict) _ConflictCard(state: s, console: _console),
            Expanded(
              child: Stack(
                children: [
                  Column(
                    children: [
                      Expanded(
                        child: _Half(match: m, score: score, side: Side.a, rules: s.category!.rules, onTap: _rally),
                      ),
                      _GamesStrip(score: score, setup: s),
                      Expanded(
                        child: _Half(match: m, score: score, side: Side.b, rules: s.category!.rules, onTap: _rally),
                      ),
                    ],
                  ),
                  if (m.state != MatchState.live)
                    Positioned.fill(
                      child: _Overlay(
                        match: m,
                        onStart: () => _command(MatchCommand.start),
                        onResume: () => _command(MatchCommand.resume),
                        onDone: () => context.canPop() ? context.pop() : context.go(back),
                      ),
                    ),
                ],
              ),
            ),
            if (m.state == MatchState.live && score.isOver)
              BottomCtaBar(
                child: SkxButton(
                  key: const Key('reviewResult'),
                  label: 'Confirm result',
                  onPressed: () => _confirmResult(s),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<ServeState?> _pickServe(BuildContext context, TmsMatch m, ScoreState score) {
    final options = <ServeState>[
      for (final side in Side.values)
        if (score.serve.serverNumber == null) ServeState(side) else ...[ServeState(side, 1), ServeState(side, 2)],
    ];
    return showModalBottomSheet<ServeState>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: SkorxSpace.sm),
              child: Text('Who is serving?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            for (final o in options)
              ListTile(
                title: Text(m.label(o.side)),
                subtitle: o.serverNumber == null ? null : Text('Server ${o.serverNumber}'),
                trailing: o == score.serve ? const Icon(Icons.check_rounded) : null,
                onTap: () => Navigator.pop(sheet, o),
              ),
          ],
        ),
      ),
    );
  }
}

/// Always visible: whether every point is on the server yet.
class _SyncBar extends StatelessWidget {
  const _SyncBar({required this.state, required this.onRetry});

  final ConsoleState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    final waiting = state.pending.length;
    final (IconData icon, Color color, String text) = switch (state.sync) {
      SyncStatus.synced || SyncStatus.loading => (Icons.cloud_done_rounded, colors.success, 'Synced'),
      SyncStatus.syncing => (Icons.cloud_upload_rounded, colors.cyan, 'Syncing $waiting…'),
      SyncStatus.offline => (
        Icons.cloud_off_rounded,
        colors.warning,
        'Offline · $waiting ${waiting == 1 ? 'point' : 'points'} saved on this phone',
      ),
      SyncStatus.conflict => (Icons.sync_problem_rounded, colors.live, 'Score changed on another device'),
      SyncStatus.failed => (Icons.error_outline_rounded, colors.live, state.message ?? 'A point was not accepted'),
    };
    return Semantics(
      liveRegion: true,
      label: text,
      excludeSemantics: true,
      child: Container(
        key: const Key('syncBar'),
        color: color.withValues(alpha: 0.12),
        padding: const EdgeInsets.symmetric(horizontal: SkorxSpace.lg, vertical: SkorxSpace.sm),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: SkorxSpace.sm),
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
            if (state.sync == SyncStatus.offline || state.sync == SyncStatus.failed)
              TextButton(onPressed: onRetry, child: Text(state.sync == SyncStatus.failed ? 'Skip it' : 'Retry now')),
          ],
        ),
      ),
    );
  }
}

class _ConflictCard extends StatelessWidget {
  const _ConflictCard({required this.state, required this.console});

  final ConsoleState state;
  final MatchConsoleController console;

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    final theirs = state.theirs;
    final mine = state.score;
    String line(ScoreState s) => '${s.currentGame.a}–${s.currentGame.b} (game ${s.gameNumber})';
    return Container(
      color: colors.surface,
      padding: const EdgeInsets.all(SkorxSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Another device scored this match. Which score stands?',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: SkorxSpace.sm),
          if (theirs != null) Text('Other device: ${line(theirs)}', style: TextStyle(color: colors.textMuted)),
          Text(
            'This phone adds ${state.pending.length} ${state.pending.length == 1 ? 'point' : 'points'}: ${line(mine)}',
            style: TextStyle(color: colors.textMuted),
          ),
          const SizedBox(height: SkorxSpace.md),
          Row(
            children: [
              Expanded(
                child: SkxButton.secondary(label: 'Use theirs', height: 44, onPressed: console.useServerScore),
              ),
              const SizedBox(width: SkorxSpace.sm),
              Expanded(
                child: SkxButton(label: 'Add mine', height: 44, onPressed: console.addMyTaps),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Half extends StatelessWidget {
  const _Half({required this.match, required this.score, required this.side, required this.rules, required this.onTap});

  final TmsMatch match;
  final ScoreState score;
  final Side side;
  final MatchRules rules;
  final ValueChanged<Side> onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    final serving = score.serve.side == side && !score.isOver;
    final points = score.currentGame.of(side);
    final won = score.winner == side;
    final action = rules.scoring == ScoringSystem.rally || serving
        ? 'POINT'
        : score.serve.serverNumber == 1
        ? '2ND SERVER'
        : 'SIDE OUT';
    final base = side == Side.a ? colors.navy : context.sx.deep;
    final names = match.label(side).split(' / ');
    final enabled = match.state == MatchState.live && !score.isOver;

    return Semantics(
      button: enabled,
      label:
          '${match.label(side)}, $points, ${score.gamesWon(side)} games'
          '${serving ? ', serving${score.serve.serverNumber == null ? '' : ' server ${score.serve.serverNumber}'}' : ''}'
          '${enabled ? '. Tap for $action' : ''}',
      excludeSemantics: true,
      child: Material(
        color: won ? colors.success.withValues(alpha: 0.25) : base,
        child: InkWell(
          key: Key('console-${side.name}'),
          onTap: enabled ? () => onTap(side) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: SkorxSpace.xl, vertical: SkorxSpace.md),
            child: Row(
              children: [
                Expanded(
                  // Scales down rather than overflowing when the half is short
                  // (the result bar is showing, or a small phone).
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final n in names)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                PlayerDp(name: n, size: 30, edge: Colors.white.withValues(alpha: 0.85)),
                                const SizedBox(width: SkorxSpace.sm),
                                Text(
                                  n,
                                  maxLines: 1,
                                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: SkorxSpace.sm),
                        if (serving)
                          Row(
                            children: [
                              Icon(Icons.sports_tennis_rounded, size: 18, color: colors.lime),
                              const SizedBox(width: 6),
                              Text(
                                score.serve.serverNumber == null ? 'Serving' : 'Server ${score.serve.serverNumber}',
                                style: TextStyle(color: colors.lime, fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        if (won)
                          const Text(
                            'WINNER',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 2),
                          ),
                      ],
                    ),
                  ),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Flexible(
                      child: FittedBox(
                        child: Text(
                          '$points',
                          key: Key('consolePoints-${side.name}'),
                          style: SkorxType.score(96, color: Colors.white),
                        ),
                      ),
                    ),
                    if (enabled)
                      Text(
                        action,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GamesStrip extends StatelessWidget {
  const _GamesStrip({required this.score, required this.setup});

  final ScoreState score;
  final ConsoleState setup;

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    final finished = score.isOver ? score.games : score.games.sublist(0, score.games.length - 1);
    final call = consoleEngine.scoreCall(setup.setup, score);
    return Container(
      color: colors.background,
      padding: const EdgeInsets.symmetric(horizontal: SkorxSpace.lg, vertical: SkorxSpace.sm),
      child: Row(
        children: [
          if (!score.isOver)
            Semantics(
              label: 'Score call $call',
              excludeSemantics: true,
              child: Text(call, style: SkorxType.score(24, color: colors.text)),
            ),
          const Spacer(),
          for (final g in finished)
            Padding(
              padding: const EdgeInsets.only(left: SkorxSpace.sm),
              child: SkxPill('$g'),
            ),
        ],
      ),
    );
  }
}

class _Overlay extends StatelessWidget {
  const _Overlay({required this.match, required this.onStart, required this.onResume, required this.onDone});

  final TmsMatch match;
  final VoidCallback onStart;
  final VoidCallback onResume;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    final m = match;
    final (String title, String body, Widget? action) = switch (m.state) {
      MatchState.paused => (
        'PAUSED',
        'Scores are safe. Resume when play restarts.',
        SkxButton(key: const Key('resumeMatch'), label: 'Resume', icon: Icons.play_arrow_rounded, onPressed: onResume),
      ),
      MatchState.completed => ('FINAL', m.scoreLine, SkxButton.secondary(label: 'Back to courts', onPressed: onDone)),
      _ when !m.ready => ('WAITING', 'Both sides must be known before this match can start.', null),
      _ => (
        'READY',
        'Players on court? Start the match to score it.',
        SkxButton(
          key: const Key('consoleStart'),
          label: 'Start match',
          icon: Icons.play_arrow_rounded,
          onPressed: onStart,
        ),
      ),
    };
    return ColoredBox(
      color: colors.background.withValues(alpha: 0.92),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(SkorxSpace.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: SkorxType.headline(44, color: colors.text)),
              const SizedBox(height: SkorxSpace.sm),
              Text(
                '${m.labelA}  v  ${m.labelB}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: SkorxSpace.sm),
              Text(
                body,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textMuted),
              ),
              if (action != null) ...[const SizedBox(height: SkorxSpace.xl), action],
            ],
          ),
        ),
      ),
    );
  }
}

/// Typing in a result (paper scoresheet, or a correction). Checked against
/// the category's rules as the organiser types.
class _ResultEntrySheet extends StatefulWidget {
  const _ResultEntrySheet({required this.match, required this.rules});

  final TmsMatch match;
  final MatchRules rules;

  @override
  State<_ResultEntrySheet> createState() => _ResultEntrySheetState();
}

class _ResultEntrySheetState extends State<_ResultEntrySheet> {
  late final _fields = [
    for (var i = 0; i < widget.rules.bestOf; i++)
      (
        TextEditingController(text: i < widget.match.games.length ? '${widget.match.games[i].a}' : ''),
        TextEditingController(text: i < widget.match.games.length ? '${widget.match.games[i].b}' : ''),
      ),
  ];

  @override
  void dispose() {
    for (final (a, b) in _fields) {
      a.dispose();
      b.dispose();
    }
    super.dispose();
  }

  List<GameScore> get _games => [
    for (final (a, b) in _fields)
      if (a.text.isNotEmpty && b.text.isNotEmpty) GameScore(int.parse(a.text), int.parse(b.text)),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    final problem = validateResult(widget.rules, _games);
    Widget box(TextEditingController c, String label) => SizedBox(
      width: 64,
      child: TextField(
        controller: c,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        style: SkorxType.score(24),
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
        decoration: InputDecoration(hintText: '–', semanticCounterText: label),
        onChanged: (_) => setState(() {}),
      ),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        SkorxSpace.xl,
        0,
        SkorxSpace.xl,
        SkorxSpace.xl + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('RESULT', style: SkorxType.headline(28, color: colors.text)),
          Text(widget.rules.describe(), style: TextStyle(color: colors.textMuted)),
          const SizedBox(height: SkorxSpace.lg),
          for (final (i, (a, b)) in _fields.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: SkorxSpace.sm),
              child: Row(
                children: [
                  SizedBox(
                    width: 70,
                    child: Text('Game ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  box(a, widget.match.labelA),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: SkorxSpace.sm),
                    child: Text('–'),
                  ),
                  box(b, widget.match.labelB),
                ],
              ),
            ),
          Text(
            '${widget.match.labelA} first, then ${widget.match.labelB}.',
            style: TextStyle(color: colors.textMuted, fontSize: 12.5),
          ),
          const SizedBox(height: SkorxSpace.md),
          if (problem != null && _games.isNotEmpty)
            Text(
              problem,
              style: TextStyle(color: colors.warning, fontWeight: FontWeight.w600),
            ),
          const SizedBox(height: SkorxSpace.md),
          SkxButton(
            label: widget.match.state == MatchState.completed ? 'Save correction' : 'Save result',
            onPressed: problem == null ? () => Navigator.pop(context, _games) : null,
          ),
        ],
      ),
    );
  }
}
