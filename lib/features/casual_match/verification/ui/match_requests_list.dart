import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/api/api_exception.dart';
import '../../../../design/design.dart';
import '../verification.dart';
import '../verification_controller.dart';
import 'verification_widgets.dart';

/// Casual matches waiting for the signed-in player's confirmation, with
/// Accept all for the ones that can safely be accepted together.
class MatchRequestsList extends ConsumerStatefulWidget {
  const MatchRequestsList({super.key});

  @override
  ConsumerState<MatchRequestsList> createState() => _MatchRequestsListState();
}

class _MatchRequestsListState extends ConsumerState<MatchRequestsList> {
  bool _busy = false;

  /// Each request is accepted exactly as shown here (its round), and each
  /// stands alone on the server, so one changed or expired request never
  /// affects the others. Score corrections are left to be reviewed one by one.
  Future<void> _acceptAll(List<CasualMatchRecord> batch) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Accept ${batch.length} matches?'),
        content: Text(
          'You confirm that you played each of these matches with the players and results shown. '
          'Each one counts once all of its players confirm.\n\n${batch.map((m) => '• ${m.lineup}${m.hasResult ? ' · ${m.scoreLabel}' : ''}').join('\n')}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Review one by one')),
          FilledButton(key: const Key('confirmAcceptAll'), onPressed: () => Navigator.pop(context, true), child: const Text('Accept all')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(casualVerificationRepositoryProvider)
          .acceptAll([for (final m in batch) (m.id, m.verification.round)]);
      refreshVerification(ref.invalidate);
      if (!mounted) return;
      final skipped = result.failed.length;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(skipped == 0
            ? 'Accepted ${result.accepted} matches.'
            : 'Accepted ${result.accepted}. $skipped changed or expired; review ${skipped == 1 ? 'it' : 'them'} again.'),
      ));
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.isNetwork ? 'No connection. Nothing was accepted.' : e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final requests = ref.watch(matchRequestsProvider);
    return switch (requests) {
      AsyncData(:final value) when value.isEmpty => const EmptyBlock(
          icon: Icons.fact_check_outlined,
          title: 'No match requests',
          message: 'When a player adds you to a casual match, you confirm it here so it counts toward your stats.',
        ),
      AsyncData(:final value) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(matchRequestsProvider),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s8, Sx.gutter, Sx.s48),
            children: [
              if (value.where((m) => m.verification.request != RequestKind.correction).toList() case final batch
                  when batch.length > 1) ...[
                SxButton(
                  key: const Key('acceptAll'),
                  label: 'Accept all (${batch.length})',
                  icon: Icons.done_all_rounded,
                  busy: _busy,
                  onPressed: () => _acceptAll(batch),
                ),
                const SizedBox(height: Sx.s16),
              ],
              for (final m in value) ...[
                MatchRequestCard(record: m, onReview: () => context.push('/player/match-requests/${m.id}')),
                const SizedBox(height: Sx.s12),
              ],
            ],
          ),
        ),
      AsyncError() => ErrorBlock(message: 'Match requests did not load.', onRetry: () => ref.invalidate(matchRequestsProvider)),
      _ => const Padding(padding: EdgeInsets.all(Sx.gutter), child: SkeletonList(rows: 3, rowHeight: 140)),
    };
  }
}
