import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../design/design.dart';
import '../../../../sports/core/match_rules.dart';
import '../../../../sports/core/score_state.dart';
import '../../../auth/auth_controller.dart';
import '../../../player/data/x_code.dart';
import '../../handover/scoring_handover.dart';
import '../../live/commentary.dart';
import '../../data/match_setup.dart';
import '../../live/live_court.dart';
import '../../local_match.dart';
import '../../scoring_controller.dart';
import '../court_top_view.dart';
import '../rules_controls.dart';
import '../scoring_labels.dart';

/// Live-scoring sheets open over a softly blurred court, so the sheet is
/// clearly in front while the match stays visible behind it.
Future<T?> showBlurredSheet<T>(BuildContext context, Widget Function(BuildContext) builder) {
  final navigator = Navigator.of(context);
  return navigator.push(_BlurredSheetRoute<T>(
    builder: (context) => SxKeyboardSafe(child: builder(context)),
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.sx.canvas,
    modalBarrierColor: Colors.black.withValues(alpha: 0.35),
    barrierLabel: MaterialLocalizations.of(context).scrimLabel,
    capturedThemes: InheritedTheme.capture(from: context, to: navigator.context),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Sx.radiusLg))),
  ));
}

class _BlurredSheetRoute<T> extends ModalBottomSheetRoute<T> {
  _BlurredSheetRoute({
    required super.builder,
    required super.isScrollControlled,
    super.useSafeArea,
    super.backgroundColor,
    super.modalBarrierColor,
    super.barrierLabel,
    super.capturedThemes,
    super.shape,
  });

  /// A slight blur: the court stays recognisable behind the sheet.
  static const _sigma = 5.0;

  @override
  Widget buildModalBarrier() => Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            child: AnimatedBuilder(
              animation: animation!,
              builder: (context, _) {
                final sigma = _sigma * Curves.easeOut.transform(animation!.value);
                return BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                  child: const SizedBox.expand(),
                );
              },
            ),
          ),
          super.buildModalBarrier(),
        ],
      );
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.title, this.subtitle, required this.children});

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Sx.gutter, 0, Sx.gutter, Sx.s24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: SxType.title(c.ink, size: 28)),
          if (subtitle != null) ...[const SizedBox(height: 4), Text(subtitle!, style: SxType.body(c.inkMuted, size: 14))],
          const SizedBox(height: Sx.s16),
          ...children,
        ],
      ),
    );
  }
}

// ─── Menu ────────────────────────────────────────────────────────────────

enum LiveMenuAction { swapEnds, swapServing, swapReceiving, serve, rules, scorer, sound, info, walkover, retire }

Future<LiveMenuAction?> showLiveMenu(BuildContext context, LocalMatch match) {
  final started = match.events.isNotEmpty;
  final doubles = match.names(Side.a).length > 1;
  final scorers = scorersOf(match, ProviderScope.containerOf(context).read(currentUserProvider));
  final scorer = scorers.isEmpty ? null : scorers.last.name;
  return showBlurredSheet(
    context,
    (context) {
      final c = context.sx;
      Widget row(LiveMenuAction a, IconData icon, String label, String detail, {bool danger = false}) => ListTile(
            key: Key('menu-${a.name}'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: SxIconTile(icon: icon, size: 38, colors: danger ? [c.live, c.live] : null),
            title: Text(label, style: SxType.heading(danger ? c.live : c.ink, size: 15.5)),
            subtitle: Text(detail, style: SxType.caption(c.inkMuted, size: 12)),
            onTap: () => Navigator.pop(context, a),
          );
      Widget head(String t) => Padding(
            padding: const EdgeInsets.only(top: Sx.s8, bottom: 2),
            child: Text(t, style: SxType.label(c.inkMuted, size: 11)),
          );
      return _SheetFrame(
        title: 'Match settings',
        subtitle: '${matchTypeLabel(match)} · ${match.rules.describe()}',
        children: [
          head('COURT'),
          row(LiveMenuAction.swapEnds, Icons.swap_vert_rounded, 'Swap ends', 'The teams are at the other ends'),
          if (doubles) ...[
            row(LiveMenuAction.swapServing, Icons.sports_tennis_rounded, 'Swap the server',
                'The partner is actually serving: switch the serving pair'),
            row(LiveMenuAction.swapReceiving, Icons.swap_horiz_rounded, 'Switch receiving players',
                'The receiving pair are the other way round'),
          ],
          row(LiveMenuAction.serve, Icons.published_with_changes_rounded, 'Correct the serving side',
              'The serve should be with the other team'),
          head('MATCH'),
          row(LiveMenuAction.rules, Icons.tune_rounded, 'Format', 'Games, scoring, points, win by'),
          row(LiveMenuAction.scorer, Icons.edit_note_rounded, 'Change scorer',
              scorer == null ? 'Hand this phone to someone else' : 'Now scoring: $scorer'),
          row(LiveMenuAction.sound, Icons.record_voice_over_rounded, 'Sound & commentary', 'Clicks and the voice announcer'),
          row(LiveMenuAction.info, Icons.info_outline_rounded, 'Match information', 'Match ID, players, court, stream'),
          const SizedBox(height: Sx.s8),
          Divider(color: c.line),
          if (!started)
            row(LiveMenuAction.walkover, Icons.flag_rounded, 'Walkover', 'A player or team did not turn up', danger: true)
          else
            row(LiveMenuAction.retire, Icons.healing_rounded, 'End match: retirement', 'A player or team cannot go on',
                danger: true),
        ],
      );
    },
  );
}

// ─── Change scorer ───────────────────────────────────────────────────────

/// Hands scoring to someone else on this phone. Nothing about the match
/// changes; the result credits both scorers.
Future<void> showChangeScorer(BuildContext context, WidgetRef ref, LocalMatch match) async {
  final pick = await showBlurredSheet<(String, String?, bool)>(context, (context) => _ChangeScorer(match: match));
  if (pick == null) return;
  final (name, id, toTheirPhone) = pick;
  HapticFeedback.mediumImpact();
  final scoring = ref.read(scoringControllerProvider.notifier);
  if (toTheirPhone && id != null) {
    await scoring.requestHandover(name, id);
  } else {
    await scoring.changeScorer(name, playerId: id);
  }
}

String? _idOf(LocalMatch match, Side side, int index) {
  final ids = side == Side.a ? match.details.sideAIds : match.details.sideBIds;
  return index < ids.length ? ids[index] : null;
}

class _ChangeScorer extends ConsumerStatefulWidget {
  const _ChangeScorer({required this.match});

  final LocalMatch match;

  @override
  ConsumerState<_ChangeScorer> createState() => _ChangeScorerState();
}

/// Who will take over: a name, and the SkorX player id when they have one.
typedef _Scorer = ({String name, String? id, String? xCode});

class _ChangeScorerState extends ConsumerState<_ChangeScorer> {
  final _query = TextEditingController();
  _Scorer? _chosen;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _choose(_Scorer s) {
    HapticFeedback.selectionClick();
    FocusScope.of(context).unfocus();
    setState(() => _chosen = s);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final match = widget.match;
    final scorers = scorersOf(match, ref.watch(currentUserProvider));
    final current = scorers.isEmpty ? null : scorers.last.name;
    final q = _query.text.trim();
    final code = XCode.parse(q);
    final mobile = mobileKey(q);

    // Quick picks: the players on court, then starred players.
    final starred = ref.watch(starredPlayersProvider);
    final seen = <String>{};
    final quick = <_Scorer>[
      for (final side in Side.values)
        for (final (i, n) in match.names(side).indexed)
          if (n != current && seen.add(n)) (name: n, id: _idOf(match, side, i), xCode: null),
      for (final p in starred)
        if (p.name != current && seen.add(p.name)) (name: p.name, id: p.isGuest ? null : p.id, xCode: p.xCode),
    ];

    final chosen = _chosen;
    // Requests reach SkorX players (not guests, not this phone's own player).
    final remote = chosen?.id != null &&
        chosen!.id!.startsWith('SKX-') &&
        ref.watch(scoringHandoverServiceProvider).available;
    return _SheetFrame(
      title: 'Change scorer',
      subtitle: 'Give this phone to the new scorer. Score, server and positions carry on exactly as they are.',
      children: [
        if (current != null)
          Padding(
            padding: const EdgeInsets.only(bottom: Sx.s12),
            child: Row(
              children: [
                Text('NOW SCORING', style: SxType.label(c.inkMuted, size: 11)),
                const SizedBox(width: Sx.s8),
                Expanded(child: Text(current, style: SxType.heading(c.ink, size: 15))),
              ],
            ),
          ),
        TextField(
          key: const Key('scorerSearch'),
          controller: _query,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Find the new scorer',
            hintText: 'Name, mobile number or X code',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: q.isEmpty
                ? null
                : IconButton(tooltip: 'Clear', icon: const Icon(Icons.close_rounded), onPressed: () => setState(_query.clear)),
          ),
        ),
        const SizedBox(height: Sx.s12),
        if (q.isEmpty) ...[
          if (quick.isNotEmpty) ...[
            Text('QUICK PICK', style: SxType.label(c.inkMuted, size: 11)),
            const SizedBox(height: Sx.s8),
            Wrap(
              spacing: Sx.s8,
              runSpacing: Sx.s8,
              children: [
                for (final s in quick)
                  SxChip(
                    key: Key('scorer-${s.name}'),
                    label: s.name.split(' ').first,
                    selected: chosen?.name == s.name,
                    onTap: () => _choose(s),
                  ),
              ],
            ),
          ],
        ] else
          ...ref.watch(matchPlayerSearchProvider(q)).when(
                loading: () => [const Padding(padding: EdgeInsets.all(Sx.s12), child: Center(child: BallLoader()))],
                error: (_, _) => [Text('Search is not available right now.', style: SxType.caption(c.inkMuted))],
                data: (found) {
                  final results = found.where((p) => p.name != current).take(8).toList();
                  return [
                    for (final p in results)
                      _ScorerRow(
                        key: Key('scorerResult-${p.id}'),
                        name: p.name,
                        detail: [
                          if (p.xCode != null) XCode.display(p.xCode!),
                          p.id,
                          if (mobile != null) 'Mobile ····${mobile.substring(6)}',
                        ].join(' · '),
                        selected: chosen?.id == p.id,
                        onTap: () => _choose((name: p.name, id: p.id, xCode: p.xCode)),
                      ),
                    if (results.isEmpty && (code != null || mobile != null))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: Sx.s8),
                        child: Text(
                          code != null ? 'No SkorX player has ${XCode.display(code)}.' : 'No SkorX player has this mobile number.',
                          key: const Key('scorerNotFound'),
                          style: SxType.caption(c.inkMuted),
                        ),
                      ),
                    // Anyone can score, on SkorX or not.
                    if (code == null && mobile == null && !results.any((p) => p.name.toLowerCase() == q.toLowerCase()))
                      _ScorerRow(
                        key: const Key('scorerGuest'),
                        name: q,
                        detail: 'Not on SkorX · score under this name',
                        guest: true,
                        selected: chosen != null && chosen.id == null && chosen.name == q,
                        onTap: () => _choose((name: q, id: null, xCode: null)),
                      ),
                  ];
                },
              ),
        const SizedBox(height: Sx.s16),
        if (chosen != null && remote) ...[
          // A SkorX player: they accept on their own phone, and scoring moves there.
          SxButton(
            key: const Key('sendHandover'),
            label: 'Send scoring request to ${chosen.name.split(' ').first}',
            icon: Icons.send_to_mobile_rounded,
            onPressed: () => Navigator.pop(context, (chosen.name, chosen.id, true)),
          ),
          const SizedBox(height: Sx.s8),
          Text('Scoring pauses on this phone until they accept on theirs.',
              textAlign: TextAlign.center, style: SxType.caption(c.inkMuted, size: 12)),
          Center(
            child: SxButton.quiet(
              key: const Key('confirmScorer'),
              label: 'They\'re here: hand this phone over now',
              onPressed: () => Navigator.pop(context, (chosen.name, chosen.id, false)),
            ),
          ),
        ] else
          SxButton(
            key: const Key('confirmScorer'),
            label: chosen == null ? 'Choose the new scorer' : 'Hand this phone to ${chosen.name.split(' ').first}',
            icon: Icons.swap_horiz_rounded,
            onPressed: chosen == null ? null : () => Navigator.pop(context, (chosen.name, chosen.id, false)),
          ),
      ],
    );
  }
}

class _ScorerRow extends StatelessWidget {
  const _ScorerRow({
    super.key,
    required this.name,
    required this.detail,
    required this.selected,
    required this.onTap,
    this.guest = false,
  });

  final String name;
  final String detail;
  final bool selected;
  final bool guest;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Padding(
      padding: const EdgeInsets.only(bottom: Sx.s8),
      child: Semantics(
        button: true,
        selected: selected,
        label: '$name, $detail',
        excludeSemantics: true,
        child: Tappable(
          onTap: onTap,
          radius: Sx.radiusSm,
          child: AnimatedContainer(
            duration: Sx.fast,
            padding: const EdgeInsets.symmetric(horizontal: Sx.s12, vertical: 10),
            decoration: BoxDecoration(
              gradient: c.card,
              borderRadius: BorderRadius.circular(Sx.radiusSm),
              border: Border.all(color: selected ? c.voltFill : c.cardEdge, width: selected ? 2 : 1),
            ),
            child: Row(
              children: [
                if (guest)
                  SxIconTile(icon: Icons.person_add_alt_1_rounded, size: 36, colors: [c.blue, c.cyan])
                else
                  PlayerDp(name: name, size: 36),
                const SizedBox(width: Sx.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(guest ? 'Use "$name"' : name,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.heading(c.ink, size: 15)),
                      Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.caption(c.inkMuted, size: 12)),
                    ],
                  ),
                ),
                AnimatedSwitcher(
                  duration: Sx.fast,
                  child: selected
                      ? Icon(Icons.check_circle_rounded, key: const ValueKey('on'), color: c.volt)
                      : Icon(Icons.circle_outlined, key: const ValueKey('off'), color: c.inkFaint),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Pause ───────────────────────────────────────────────────────────────

const pauseReasons = ['Injury', 'Water break', 'Court issue', 'Tournament delay', 'Other'];

Future<String?> showPauseReasons(BuildContext context) => showBlurredSheet(
      context,
      (context) => _SheetFrame(
        title: 'Pause match',
        subtitle: 'Scoring is locked until you resume.',
        children: [
          for (final r in pauseReasons)
            Padding(
              padding: const EdgeInsets.only(bottom: Sx.s8),
              child: SxButton.secondary(
                key: Key('pause-$r'),
                label: r,
                icon: switch (r) {
                  'Injury' => Icons.healing_rounded,
                  'Water break' => Icons.local_drink_rounded,
                  'Court issue' => Icons.grid_off_rounded,
                  'Tournament delay' => Icons.schedule_rounded,
                  _ => Icons.pause_rounded,
                },
                onPressed: () => Navigator.pop(context, r),
              ),
            ),
        ],
      ),
    );

// ─── Match settings ──────────────────────────────────────────────────────

/// Edits the format. On a match under way it warns first: new rules restart
/// the score, and a live game is never reset silently.
Future<void> showRulesSheet(BuildContext context, WidgetRef ref, LocalMatch match) async {
  var rules = match.rules;
  final chosen = await showBlurredSheet<MatchRules>(
    context,
    (context) => StatefulBuilder(
      builder: (context, setState) => _SheetFrame(
        title: 'Match settings',
        subtitle: match.events.isEmpty ? 'Change anything before the first rally.' : 'Changing the format restarts the score.',
        children: [
          RulesBlock(sport: match.sport, rules: rules, onChanged: (r) => setState(() => rules = r)),
          const SizedBox(height: Sx.s16),
          SxButton(
            key: const Key('applyRules'),
            label: 'Apply',
            onPressed: rules == match.rules ? null : () => Navigator.pop(context, rules),
          ),
        ],
      ),
    ),
  );
  if (chosen == null || !context.mounted) return;
  if (match.events.isNotEmpty) {
    final ok = await confirmAction(
      context,
      title: 'Change the match format?',
      message: 'Changing the match format will reset the current scoring to 0–0. Players, ends and the first server stay '
          'as they were set up.',
      confirm: 'Change & reset',
      confirmKey: 'confirmReset',
    );
    if (!ok) return;
  }
  await ref.read(scoringControllerProvider.notifier).changeRules(chosen);
}

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirm,
  required String confirmKey,
}) async {
  final c = context.sx;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: c.surface,
      title: Text(title, style: SxType.heading(c.ink, size: 19)),
      content: Text(message, style: SxType.body(c.inkMuted)),
      actions: [
        TextButton(key: const Key('cancelAction'), onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          key: Key(confirmKey),
          style: FilledButton.styleFrom(backgroundColor: c.live, foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return ok ?? false;
}

// ─── Sound & commentary ──────────────────────────────────────────────────

Future<void> showSoundSheet(BuildContext context) => showBlurredSheet(context, (context) => const _SoundSheet());

class _SoundSheet extends ConsumerWidget {
  const _SoundSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final s = ref.watch(liveSettingsProvider);
    final settings = ref.read(liveSettingsProvider.notifier);
    return _SheetFrame(
      title: 'Sound & commentary',
      subtitle: 'Only points, serves and results are announced, never menus.',
      children: [
        SxBlock(
          padding: const EdgeInsets.symmetric(horizontal: Sx.s16, vertical: Sx.s4),
          child: SwitchListTile(
            key: const Key('soundSwitch'),
            contentPadding: EdgeInsets.zero,
            value: s.sound,
            onChanged: (v) {
              if (!v) ref.read(commentatorProvider).stop();
              settings.update((x) => x.copyWith(sound: v));
            },
            secondary: Icon(s.sound ? Icons.volume_up_rounded : Icons.volume_off_rounded, color: c.ink),
            title: Text('Sound', style: SxType.heading(c.ink, size: 16)),
            subtitle: Text(s.sound ? 'On' : 'Off: silent scoring', style: SxType.caption(c.inkMuted, size: 12)),
          ),
        ),
        const SizedBox(height: Sx.s16),
        Text('COMMENTARY', style: SxType.label(c.inkMuted)),
        const SizedBox(height: Sx.s8),
        Opacity(
          opacity: s.sound ? 1 : 0.4,
          child: SegmentedPills<CommentaryLevel>(
            keyPrefix: 'commentary',
            options: [for (final l in CommentaryLevel.values) (l, l.label)],
            selected: s.commentary,
            onChanged: (l) => settings.update((x) => x.copyWith(commentary: l, sound: l == CommentaryLevel.off ? x.sound : true)),
          ),
        ),
        const SizedBox(height: Sx.s8),
        Text(
          switch (s.commentary) {
            CommentaryLevel.off => 'No voice.',
            CommentaryLevel.basic => 'Just the score: "4, 3, 2."',
            CommentaryLevel.advanced => 'Names and moments: "Smit and Kamal win the point. 4, 3, 2. Game point."',
          },
          style: SxType.caption(c.inkMuted),
        ),
        const SizedBox(height: Sx.s16),
        SxButton.secondary(
          key: const Key('testVoice'),
          label: 'Test the voice',
          icon: Icons.campaign_rounded,
          onPressed: s.speaks
              ? () => ref.read(commentatorProvider).say(
                    s.commentary == CommentaryLevel.basic ? '4, 3, 2. Game point.' : 'Smit and Kamal win the point. 4, 3, 2.')
              : null,
        ),
      ],
    );
  }
}

// ─── Walkover / retirement ───────────────────────────────────────────────

/// Declares a walkover (nobody played) or a retirement (someone stopped).
/// Two deliberate steps: pick the side, then confirm.
Future<void> showEarlyEnd(BuildContext context, WidgetRef ref, LocalMatch match, EarlyEnd kind) async {
  final walkover = kind == EarlyEnd.walkover;
  final picked = await showBlurredSheet<Side>(
    context,
    (context) {
      final c = context.sx;
      return _SheetFrame(
        title: walkover ? 'Declare walkover' : 'Retirement',
        subtitle: walkover ? 'Who wins? The other side did not turn up.' : 'Who retired? The other side wins the match.',
        children: [
          for (final side in Side.values)
            Padding(
              padding: const EdgeInsets.only(bottom: Sx.s12),
              child: SxBlock(
                key: Key('early-${side.name}'),
                onTap: () => Navigator.pop(context, side),
                semanticLabel: match.teamLabel(side),
                child: Row(
                  children: [
                    SideDps(names: match.names(side), size: 40, edge: CourtTopView.teamColor(c, side)),
                    const SizedBox(width: Sx.s12),
                    Expanded(child: Text(match.teamLabel(side), style: SxType.heading(c.ink, size: 16))),
                    Text(walkover ? 'WINS' : 'RETIRED',
                        style: SxType.label(walkover ? c.volt : c.live, size: 12)),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
  if (picked == null || !context.mounted) return;
  final winner = walkover ? picked : picked.opponent;
  final ok = await confirmAction(
    context,
    title: walkover ? 'Confirm walkover' : 'Confirm retirement',
    message: walkover
        ? 'Walkover will mark ${match.teamLabel(winner)} as the match winner. No score is recorded.'
        : 'The match goes to ${match.teamLabel(winner)} because ${match.teamLabel(picked)} cannot go on. The score so far '
            'is kept.',
    confirm: walkover ? 'Confirm walkover' : 'End match',
    confirmKey: 'confirmEarlyEnd',
  );
  if (!ok) return;
  HapticFeedback.heavyImpact();
  await ref.read(scoringControllerProvider.notifier).endEarly(kind, winner);
}

// ─── Server correction ───────────────────────────────────────────────────

Future<void> showServeCorrection(BuildContext context, WidgetRef ref, LocalMatch match, LiveStep step) async {
  final score = step.score;
  final options = <ServeState>[
    for (final side in Side.values)
      if (score.serve.serverNumber == null) ServeState(side) else ...[ServeState(side, 1), ServeState(side, 2)],
  ];
  final chosen = await showBlurredSheet<ServeState>(
    context,
    (context) {
      final c = context.sx;
      return _SheetFrame(
        title: 'Who is serving?',
        subtitle: 'Only needed if the serve went to the wrong player. The score does not change.',
        children: [
          for (final option in options)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: SideDps(names: match.names(option.side), size: 32),
              title: Text(match.teamLabel(option.side), style: SxType.heading(c.ink, size: 15)),
              subtitle: option.serverNumber == null ? null : Text('Server ${option.serverNumber}'),
              trailing: option == score.serve ? Icon(Icons.check_rounded, color: c.volt) : null,
              onTap: () => Navigator.pop(context, option),
            ),
        ],
      );
    },
  );
  if (chosen != null && chosen != score.serve) {
    await ref.read(scoringControllerProvider.notifier).correctServe(chosen);
  }
}

// ─── Match information ───────────────────────────────────────────────────

Future<void> showMatchInfo(BuildContext context, LocalMatch match) => showBlurredSheet(
      context,
      (context) {
        final c = context.sx;
        final d = match.details;
        final scorers = scorersOf(match, ProviderScope.containerOf(context).read(currentUserProvider));
        Widget row(String k, String v) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 110, child: Text(k.toUpperCase(), style: SxType.label(c.inkMuted, size: 11))),
                  Expanded(child: Text(v, style: SxType.body(c.ink, size: 14))),
                ],
              ),
            );
        return _SheetFrame(
          title: 'Match information',
          children: [
            row('Match', matchTypeLabel(match)),
            row(match.details.teamA ?? 'Side A', match.label(Side.a)),
            row(match.details.teamB ?? 'Side B', match.label(Side.b)),
            row('Format', match.rules.describe()),
            row('Scoring', match.rules.scoring == ScoringSystem.rally ? 'Rally' : 'Side out'),
            if (d.courtLabel != null) row('Court', d.courtLabel!),
            row('Started', TimeOfDay.fromDateTime(match.startedAt).format(context)),
            row('Rallies', '${match.events.length}'),
            if (d.stream != null) row('YouTube', '${d.stream!.title} · ${d.stream!.privacy.label}'),
            row('Match ID', match.displayCode),
            if (scorers.isNotEmpty) row('Scored by', scorers.map((s) => s.name).join(', then ')),
            row('Saved', 'On this phone after every point'),
          ],
        );
      },
    );
