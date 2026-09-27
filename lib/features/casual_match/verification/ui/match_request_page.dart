import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/api/api_exception.dart';
import '../../../../design/design.dart';
import '../../../../shared/format.dart';
import '../../data/match_setup.dart';
import '../verification.dart';
import '../verification_controller.dart';
import 'verification_widgets.dart';

/// "Casual Match", "Men's Doubles".
String casualCategoryLabel(String id) {
  final parsed = parseCategoryId(id);
  if (parsed == null) return 'Casual match';
  final (format, division) = parsed;
  return switch (division) {
    null || Division.open => format.label,
    Division.kids => 'Kids ${format.label}',
    final d => '${d.label} ${format.label}',
  };
}

/// One casual match's confirmation: the line-up, score and who has
/// confirmed, with Accept and Reject / Dispute for a player who was added,
/// and Remind / Cancel for the player who created it.
class MatchRequestPage extends ConsumerStatefulWidget {
  const MatchRequestPage({super.key, required this.matchId});

  final String matchId;

  @override
  ConsumerState<MatchRequestPage> createState() => _MatchRequestPageState();
}

class _MatchRequestPageState extends ConsumerState<MatchRequestPage> {
  bool _busy = false;

  /// Shown once the player has answered here, until they leave.
  String? _answered;

  void _toast(String message) =>
      ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(message)));

  Future<void> _act(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on ApiException catch (e) {
      if (!mounted) return;
      // The match changed while this screen was open: show the new details.
      if (e.code == 'STALE_CONFIRMATION') ref.invalidate(casualMatchProvider(widget.matchId));
      _toast(e.isNetwork ? 'No connection. Your answer was not sent; try again.' : e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _accept(CasualMatchRecord m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => const _ConfirmParticipationDialog(),
    );
    if (ok != true) return;
    await _act(() async {
      final updated = await ref.read(casualVerificationRepositoryProvider).accept(m.id, m.verification.round);
      refreshVerification(ref.invalidate);
      if (!mounted) return;
      setState(() => _answered = updated.verification.official ? 'verified' : 'accepted');
    });
  }

  Future<void> _reject(CasualMatchRecord m) async {
    final answer = await showSxSheet<(RejectionReason, String?)>(context, builder: (_) => const _RejectSheet());
    if (answer == null) return;
    await _act(() async {
      await ref.read(casualVerificationRepositoryProvider).reject(m.id, m.verification.round, answer.$1, note: answer.$2);
      refreshVerification(ref.invalidate);
      if (mounted) setState(() => _answered = 'disputed');
    });
  }

  Future<void> _remind(CasualMatchRecord m) => _act(() async {
        final n = await ref.read(casualVerificationRepositoryProvider).remind(m.id);
        _toast(n == 1 ? 'Reminder sent.' : 'Reminded $n players.');
      });

  Future<void> _cancel(CasualMatchRecord m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this match?'),
        content: const Text('The other players will be told. It will not count for anyone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep it')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cancel match')),
        ],
      ),
    );
    if (ok != true) return;
    await _act(() async {
      await ref.read(casualVerificationRepositoryProvider).cancel(m.id);
      refreshVerification(ref.invalidate);
    });
  }

  @override
  Widget build(BuildContext context) {
    final match = ref.watch(casualMatchProvider(widget.matchId));
    return Scaffold(
      body: SafeArea(
        child: SxWidth(
          child: Column(
            children: [
              SxBackBar(onBack: () => context.canPop() ? context.pop() : context.go('/player/notifications?tab=requests')),
              Expanded(
                child: switch (match) {
                  AsyncData(:final value) => RefreshIndicator(
                      onRefresh: () async => ref.invalidate(casualMatchProvider(widget.matchId)),
                      child: _Body(match: value, answered: _answered),
                    ),
                  AsyncError(:final error) => ErrorBlock(
                      message: error is ApiException && error.status == 404
                          ? 'This match is no longer on SkorX, or you are not in it.'
                          : 'The match did not load.',
                      onRetry: () => ref.invalidate(casualMatchProvider(widget.matchId)),
                    ),
                  _ => const Padding(padding: EdgeInsets.all(Sx.gutter), child: SkeletonList(rows: 5)),
                },
              ),
              if (match.value case final m?) _Actions(
                match: m,
                busy: _busy,
                answered: _answered != null,
                onAccept: () => _accept(m),
                onReject: () => _reject(m),
                onRemind: () => _remind(m),
                onCancel: () => _cancel(m),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.match, required this.answered});

  final CasualMatchRecord match;
  final String? answered;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final v = match.verification;
    final status = v.canRespond
        ? 'Awaiting your confirmation'
        : v.lifecycle == MatchLifecycle.completed && v.isCreator
            ? 'Awaiting ${v.waitingFor.length} ${v.waitingFor.length == 1 ? 'player' : 'players'}'
            : v.lifecycle.label;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Sx.gutter, 0, Sx.gutter, Sx.s32),
      children: [
        Row(
          children: [
            Expanded(child: Text('Match confirmation', style: SxType.title(c.ink, size: 28))),
            VerificationChip(lifecycle: v.lifecycle),
          ],
        ),
        const SizedBox(height: Sx.s16),
        if (answered != null) ...[
          _AnsweredBanner(kind: answered!, waiting: v.waitingFor.length),
          const SizedBox(height: Sx.s16),
        ],
        _Teams(match: match),
        const SizedBox(height: Sx.s16),
        Text(lifecycleExplainer(v), style: SxType.body(c.inkMuted, size: 14)),
        if (v.correction case final fix?) ...[
          const SizedBox(height: Sx.s16),
          SxBlock(
            color: c.caution.withValues(alpha: 0.1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${fix.proposedBy} wants to correct the score', style: SxType.heading(c.ink, size: 15)),
                const SizedBox(height: 4),
                Text('${match.scoreLabel}  →  ${fix.games.map((g) => '${g.$1}–${g.$2}').join(', ')}',
                    style: SxType.number(16, c.ink)),
                if (fix.reason != null) ...[const SizedBox(height: 4), Text('“${fix.reason}”', style: SxType.caption(c.inkMuted))],
                const SizedBox(height: 4),
                Text('The verified score counts until every player accepts the change.', style: SxType.caption(c.inkMuted)),
              ],
            ),
          ),
        ],
        const SizedBox(height: Sx.s24),
        SxRows(children: [
          SxRow(label: 'Match type', value: 'Casual · ${casualCategoryLabel(match.categoryId)}'),
          SxRow(label: 'Created by', value: v.isCreator ? 'You' : (v.createdBy ?? '—')),
          SxRow(label: 'Date', value: longDate(match.startedAt)),
          if (match.locationName != null) SxRow(label: 'Court', value: match.locationName),
          SxRow(label: 'Score', value: match.hasResult ? match.scoreLabel : 'Not in yet'),
          SxRow(label: 'Status', value: status),
          if (v.confirmBy != null && v.lifecycle.waiting)
            SxRow(label: 'Confirm by', value: longDate(v.confirmBy!)),
        ]),
        const SizedBox(height: Sx.s24),
        VerificationProgress(verification: v),
      ],
    );
  }
}

class _Teams extends StatelessWidget {
  const _Teams({required this.match});

  final CasualMatchRecord match;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    Widget side(List<String> names, String key) {
      final won = match.winnerSide == key;
      return Expanded(
        child: Column(
          children: [
            for (final n in names)
              Text(n == 'You' ? 'You' : n, textAlign: TextAlign.center, style: SxType.heading(c.ink, size: 16).copyWith(
                fontWeight: won ? FontWeight.w800 : FontWeight.w600,
              )),
            if (won) ...[
              const SizedBox(height: 4),
              Text('WON', style: SxType.label(c.isDark ? c.volt : c.olive, size: 11)),
            ],
          ],
        ),
      );
    }

    return SxBlock(
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              side(match.sideA, 'a'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Sx.s8),
                child: Text('vs', style: SxType.label(c.inkFaint, size: 13)),
              ),
              side(match.sideB, 'b'),
            ],
          ),
          if (match.hasResult) ...[
            const SizedBox(height: Sx.s12),
            Divider(height: 1, color: c.line),
            const SizedBox(height: Sx.s12),
            Text(match.scoreLabel, style: SxType.number(24, c.ink)),
          ],
        ],
      ),
    );
  }
}

class _AnsweredBanner extends StatelessWidget {
  const _AnsweredBanner({required this.kind, required this.waiting});

  final String kind;
  final int waiting;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final (icon, title, line, color) = switch (kind) {
      'verified' => (Icons.verified_rounded, 'Match verified', 'Everyone confirmed. It now counts for all players.', c.voltFill),
      'disputed' => (Icons.flag_rounded, 'Dispute sent', 'The player who created it has been told why.', c.live),
      _ => (
          Icons.check_circle_rounded,
          'Match accepted',
          waiting == 0 ? 'Waiting for the result.' : 'Waiting for the remaining ${waiting == 1 ? 'player' : '$waiting players'}.',
          c.voltFill,
        ),
    };
    return Semantics(
      liveRegion: true,
      child: SxBlock(
        color: color.withValues(alpha: 0.14),
        child: Row(
          children: [
            Icon(icon, color: kind == 'disputed' ? c.live : (c.isDark ? c.volt : c.olive), size: 28),
            const SizedBox(width: Sx.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: SxType.heading(c.ink, size: 16)),
                  Text(line, style: SxType.caption(c.inkMuted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.match,
    required this.busy,
    required this.answered,
    required this.onAccept,
    required this.onReject,
    required this.onRemind,
    required this.onCancel,
  });

  final CasualMatchRecord match;
  final bool busy;
  final bool answered;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onRemind;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final v = match.verification;
    final respond = v.canRespond && !answered;
    final creator = v.isCreator && (v.canRemind || v.canCancel);
    if (!respond && !creator) return const SizedBox.shrink();
    final acceptLabel = switch (v.request) {
      RequestKind.join => 'Accept match',
      RequestKind.correction => 'Accept correction',
      _ => 'Accept match',
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s12, Sx.gutter, Sx.s16),
      decoration: BoxDecoration(color: c.canvas, border: Border(top: BorderSide(color: c.line))),
      child: respond
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SxButton(key: const Key('acceptMatch'), label: acceptLabel, icon: Icons.check_rounded, busy: busy, onPressed: onAccept),
                const SizedBox(height: Sx.s8),
                SxButton.secondary(
                  key: const Key('rejectMatch'),
                  label: v.request == RequestKind.correction ? 'Keep original score' : 'Reject / Dispute',
                  icon: Icons.close_rounded,
                  onPressed: busy ? null : onReject,
                ),
              ],
            )
          : Row(
              children: [
                if (v.canCancel)
                  Expanded(child: SxButton.secondary(key: const Key('cancelMatch'), label: 'Cancel match', onPressed: busy ? null : onCancel)),
                if (v.canCancel && v.canRemind) const SizedBox(width: Sx.s12),
                if (v.canRemind)
                  Expanded(
                    child: SxButton(
                      key: const Key('remindPlayers'),
                      label: 'Remind players',
                      icon: Icons.notifications_active_outlined,
                      height: 50,
                      busy: busy,
                      onPressed: onRemind,
                    ),
                  ),
              ],
            ),
    );
  }
}

/// The spec's confirmation: what accepting means, in plain words.
class _ConfirmParticipationDialog extends StatelessWidget {
  const _ConfirmParticipationDialog();

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    Widget point(String s) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.check_rounded, size: 18, color: c.isDark ? c.volt : c.olive),
              const SizedBox(width: 8),
              Expanded(child: Text(s, style: SxType.body(c.ink, size: 14))),
            ],
          ),
        );
    return AlertDialog(
      title: const Text('Confirm match participation'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('You are confirming that:', style: SxType.body(c.inkMuted, size: 14)),
          point('You participated in this match.'),
          point('The listed players are correct.'),
          point('The match result shown is accurate.'),
          const SizedBox(height: Sx.s12),
          Text(
            'Once all participating players confirm, this match becomes a verified SkorX casual match and may '
            'affect player statistics, rating and rankings.',
            style: SxType.caption(c.inkMuted),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
        FilledButton(key: const Key('confirmMatch'), onPressed: () => Navigator.pop(context, true), child: const Text('Confirm match')),
      ],
    );
  }
}

/// Why the player is saying no. A reason is required; details are optional.
class _RejectSheet extends StatefulWidget {
  const _RejectSheet();

  @override
  State<_RejectSheet> createState() => _RejectSheetState();
}

class _RejectSheetState extends State<_RejectSheet> {
  RejectionReason? _reason;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Sx.gutter, 0, Sx.gutter, Sx.s24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Why are you rejecting this match?', style: SxType.title(c.ink, size: 22)),
          const SizedBox(height: Sx.s8),
          RadioGroup<RejectionReason>(
            groupValue: _reason,
            onChanged: (r) => setState(() => _reason = r),
            child: Column(
              children: [
                for (final r in RejectionReason.values)
                  RadioListTile<RejectionReason>(
                    key: Key('reason-${r.id}'),
                    value: r,
                    contentPadding: EdgeInsets.zero,
                    title: Text(r.label, style: SxType.body(c.ink, size: 15)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Sx.s8),
          TextField(
            key: const Key('rejectNote'),
            controller: _note,
            maxLength: 300,
            maxLines: 3,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Add additional details (optional)'),
          ),
          const SizedBox(height: Sx.s12),
          SxButton(
            key: const Key('submitDispute'),
            label: 'Submit dispute',
            onPressed: _reason == null ? null : () => Navigator.pop(context, (_reason!, _note.text.trim().isEmpty ? null : _note.text.trim())),
          ),
        ],
      ),
    );
  }
}
