import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../design/design.dart';
import '../../local_match.dart';
import '../verification.dart';
import '../verification_controller.dart';
import 'verification_widgets.dart';

/// Where a match scored on this phone stands with its players: sent,
/// who has confirmed, and whether it counts yet. Checks again every few
/// seconds while players are still answering.
class LocalVerificationPanel extends ConsumerStatefulWidget {
  const LocalVerificationPanel({super.key, required this.match});

  final LocalMatch match;

  @override
  ConsumerState<LocalVerificationPanel> createState() => _LocalVerificationPanelState();
}

class _LocalVerificationPanelState extends ConsumerState<LocalVerificationPanel> {
  Timer? _poll;
  bool _retrying = false;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 15), (_) {
      final s = ref.read(casualSyncProvider)[widget.match.id];
      if (s?.lifecycle.waiting ?? false) ref.read(casualSyncProvider.notifier).refresh(widget.match.id);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _retry() async {
    setState(() => _retrying = true);
    await ref.read(casualSyncProvider.notifier).retryFailed();
    if (mounted) setState(() => _retrying = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final sync = ref.watch(casualSyncProvider)[widget.match.id];
    final record = sync?.record;
    final v = record?.verification;
    final lifecycle = sync?.lifecycle ?? MatchLifecycle.draft;
    return SxBlock(
      key: const Key('verificationPanel'),
      onTap: sync?.serverId == null ? null : () => context.push('/player/match-requests/${sync!.serverId}'),
      semanticLabel: 'Verification: ${lifecycle.label}. Open details',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Player confirmation', style: SxType.heading(c.ink, size: 16))),
              VerificationChip(lifecycle: lifecycle),
            ],
          ),
          const SizedBox(height: Sx.s8),
          Text(
            v == null
                ? (sync?.error != null
                    ? 'Not sent: ${sync!.error}'
                    : 'Sending to SkorX. It counts once the other players confirm.')
                : lifecycleExplainer(v),
            style: SxType.body(c.inkMuted, size: 14),
          ),
          if (v != null && v.required > 0) ...[
            const SizedBox(height: Sx.s12),
            Row(
              children: [
                for (final p in v.players)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Tooltip(
                      message: '${p.isMe ? 'You' : p.name}: ${p.state.label}',
                      child: Icon(
                        switch (p.state) {
                          PlayerCheckState.confirmed => Icons.check_circle_rounded,
                          PlayerCheckState.rejected => Icons.cancel_rounded,
                          PlayerCheckState.guest || PlayerCheckState.unavailable => Icons.person_off_outlined,
                          _ => Icons.radio_button_unchecked_rounded,
                        },
                        size: 20,
                        color: switch (p.state) {
                          PlayerCheckState.confirmed => c.isDark ? c.volt : c.olive,
                          PlayerCheckState.rejected => c.live,
                          _ => c.inkFaint,
                        },
                      ),
                    ),
                  ),
                const Spacer(),
                Text('${v.confirmed}/${v.required} confirmed', style: SxType.label(c.inkMuted, size: 12.5)),
                Icon(Icons.chevron_right_rounded, color: c.inkFaint),
              ],
            ),
          ],
          if (sync?.error != null && lifecycle == MatchLifecycle.draft) ...[
            const SizedBox(height: Sx.s12),
            SxButton.secondary(key: const Key('retrySend'), label: 'Send again', busy: _retrying, onPressed: _retry, expand: false),
          ],
        ],
      ),
    );
  }
}
