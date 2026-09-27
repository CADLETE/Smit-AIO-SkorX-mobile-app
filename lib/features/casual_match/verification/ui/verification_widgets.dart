import 'package:flutter/material.dart';

import '../../../../design/design.dart';
import '../../../../shared/format.dart';
import '../verification.dart';

/// The colour of a status: volt when it counts, amber while waiting, red
/// when a player said no, grey when it never will.
(Color bg, Color fg, IconData icon) lifecycleStyle(SxColors c, MatchLifecycle l) => switch (l) {
      MatchLifecycle.verified => (c.voltFill, c.onVolt, Icons.verified_rounded),
      MatchLifecycle.pendingConfirmation || MatchLifecycle.inProgress || MatchLifecycle.completed =>
        (c.caution.withValues(alpha: 0.16), c.caution, Icons.hourglass_top_rounded),
      MatchLifecycle.disputed || MatchLifecycle.rejected || MatchLifecycle.expired =>
        (c.live.withValues(alpha: 0.14), c.live, Icons.report_gmailerrorred_rounded),
      MatchLifecycle.draft => (c.info.withValues(alpha: 0.14), c.info, Icons.cloud_upload_outlined),
      MatchLifecycle.cancelled || MatchLifecycle.unofficial => (c.surfaceAlt, c.inkMuted, Icons.block_rounded),
    };

/// "✓ Verified" / "⧗ Pending" pill.
class VerificationChip extends StatelessWidget {
  const VerificationChip({super.key, required this.lifecycle, this.compact = false});

  final MatchLifecycle lifecycle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon) = lifecycleStyle(context.sx, lifecycle);
    final label = compact
        ? switch (lifecycle) {
            MatchLifecycle.pendingConfirmation || MatchLifecycle.inProgress || MatchLifecycle.completed => 'Pending',
            final l => l.label,
          }
        : lifecycle.label;
    return Semantics(
      label: 'Status: $label',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 3 : 5),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: compact ? 12 : 14, color: fg),
            const SizedBox(width: 4),
            Text(label, style: SxType.label(fg, size: compact ? 11 : 12)),
          ],
        ),
      ),
    );
  }
}

/// One line saying what the status means for the player.
String lifecycleExplainer(MatchVerification v) => switch (v.lifecycle) {
      MatchLifecycle.verified => v.flagged
          ? 'Verified. A player flagged it; SkorX will review it. The result stands for now.'
          : 'Every player confirmed it. It counts toward stats, rating and rankings.',
      MatchLifecycle.pendingConfirmation => 'Waiting for players to confirm they are in this match.',
      MatchLifecycle.inProgress => 'Everyone is in. It is sent to confirm once the result is in.',
      MatchLifecycle.completed => v.waitingFor.isEmpty
          ? 'Waiting for confirmation.'
          : 'Waiting for ${_names(v.waitingFor)}. It counts once everyone confirms.',
      MatchLifecycle.disputed => 'A player disputed the details. It does not count until they are fixed.',
      MatchLifecycle.rejected => 'A player rejected this match. It does not count.',
      MatchLifecycle.cancelled => 'Cancelled. Nothing to confirm.',
      MatchLifecycle.expired => 'Nobody confirmed in time, so it does not count.',
      MatchLifecycle.unofficial => 'A guest without a SkorX account played, so it can never count toward stats.',
      MatchLifecycle.draft => 'Not sent to SkorX yet. It will be sent when you are online.',
    };

String _names(List<PlayerCheck> players) {
  final names = [for (final p in players) p.isMe ? 'you' : p.name.split(' ').first];
  if (names.length == 1) return names.single;
  return '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
}

/// The verification progress: every player and whether they confirmed.
class VerificationProgress extends StatelessWidget {
  const VerificationProgress({super.key, required this.verification});

  final MatchVerification verification;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final v = verification;
    return SxBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Verification progress', style: SxType.heading(c.ink, size: 16))),
              Text('${v.confirmed}/${v.required} confirmed', style: SxType.label(c.inkMuted, size: 12.5)),
            ],
          ),
          const SizedBox(height: Sx.s8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: v.required == 0 ? 0 : v.confirmed / v.required,
              minHeight: 6,
              backgroundColor: c.surfaceAlt,
              color: v.lifecycle.official ? c.voltFill : c.caution,
            ),
          ),
          const SizedBox(height: Sx.s8),
          for (final p in v.players) _PlayerLine(player: p),
        ],
      ),
    );
  }
}

class _PlayerLine extends StatelessWidget {
  const _PlayerLine({required this.player});

  final PlayerCheck player;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final p = player;
    final (icon, color) = switch (p.state) {
      PlayerCheckState.confirmed => (Icons.check_circle_rounded, c.isDark ? c.volt : c.olive),
      PlayerCheckState.joined => (Icons.timelapse_rounded, c.caution),
      PlayerCheckState.pending => (Icons.radio_button_unchecked_rounded, c.inkFaint),
      PlayerCheckState.rejected => (Icons.cancel_rounded, c.live),
      PlayerCheckState.guest => (Icons.person_off_outlined, c.inkMuted),
      PlayerCheckState.unavailable => (Icons.person_off_outlined, c.inkMuted),
    };
    final name = '${p.isMe ? 'You' : p.name}${p.isCreator ? ' · created it' : ''}';
    final state = switch (p.state) {
      PlayerCheckState.joined => 'Joined · result pending',
      PlayerCheckState.guest => 'Guest · cannot confirm',
      final s => s.label,
    };
    return Semantics(
      label: '$name, $state',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: Sx.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: SxType.body(c.ink, size: 14.5).copyWith(fontWeight: p.isMe ? FontWeight.w700 : FontWeight.w500)),
                  if (p.rejection != null)
                    Text(
                      [p.rejection!.label, if (p.rejectionNote != null && p.rejectionNote!.isNotEmpty) '“${p.rejectionNote}”'].join(' · '),
                      style: SxType.caption(c.live, size: 12.5),
                    ),
                ],
              ),
            ),
            Text(state, style: SxType.caption(color == c.inkFaint ? c.inkMuted : color, size: 12.5).copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

/// A request in the Match requests list: who, what, and a Review button.
class MatchRequestCard extends StatelessWidget {
  const MatchRequestCard({super.key, required this.record, required this.onReview});

  final CasualMatchRecord record;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final v = record.verification;
    final ask = switch (v.request) {
      RequestKind.join => 'added you to a casual match',
      RequestKind.correction => 'wants to correct a score',
      _ => 'submitted a result for you to confirm',
    };
    return SxBlock(
      key: Key('request-${record.id}'),
      onTap: onReview,
      semanticLabel: '${v.createdBy ?? 'A player'} $ask. ${record.lineup}. Review',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SxAvatar(name: v.createdBy ?? '?', size: 36),
              const SizedBox(width: Sx.s12),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: v.createdBy ?? 'A player', style: const TextStyle(fontWeight: FontWeight.w800)),
                    TextSpan(text: ' $ask'),
                  ]),
                  style: SxType.body(c.ink, size: 14.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: Sx.s12),
          Text(record.lineup, style: SxType.heading(c.ink, size: 16)),
          const SizedBox(height: 2),
          Text(
            [
              if (record.hasResult) record.scoreLabel else 'No score yet',
              dayDate(record.startedAt),
              ?record.locationName,
            ].join(' · '),
            style: SxType.caption(c.inkMuted),
          ),
          const SizedBox(height: Sx.s12),
          Row(
            children: [
              Expanded(child: Text('${v.confirmed}/${v.required} confirmed', style: SxType.caption(c.inkMuted, size: 12.5))),
              SxButton.secondary(key: Key('review-${record.id}'), label: 'Review', icon: Icons.chevron_right_rounded, expand: false, height: 40, onPressed: onReview),
            ],
          ),
        ],
      ),
    );
  }
}
