import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/sync/connectivity.dart';
import '../../../../design/design.dart';
import '../../../../shared/format.dart';
import '../../../../sports/core/score_state.dart';
import '../../../auth/auth_controller.dart';
import '../../local_match.dart';
import '../../played_matches.dart';
import '../../scoring_controller.dart';
import '../sync_engine.dart';

// Offline scoring on screen (docs/OFFLINE-SCORING.md §8): a small status
// chip, short floating notices, and the Offline matches page. Nothing here
// ever blocks scoring.

(Color, IconData) _look(SxColors c, SyncBadge b) => switch (b) {
      SyncBadge.saved => (c.inkMuted, Icons.phone_android_rounded),
      SyncBadge.online => (c.isDark ? c.volt : c.olive, Icons.circle),
      SyncBadge.offline => (c.caution, Icons.cloud_off_rounded),
      SyncBadge.syncing => (c.info, Icons.sync_rounded),
      SyncBadge.synced => (c.isDark ? c.volt : c.olive, Icons.check_circle_rounded),
      SyncBadge.failed => (c.live, Icons.error_outline_rounded),
      SyncBadge.attention => (c.live, Icons.warning_amber_rounded),
    };

/// The scoring header's status: Online, Offline · Saved, Syncing, Synced,
/// or Needs attention. Tap for what it means and "Sync now".
class SyncStatusChip extends ConsumerWidget {
  const SyncStatusChip({super.key, required this.localId});

  final String localId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final badge = ref.watch(syncBadgeProvider(localId));
    final (color, icon) = _look(c, badge);
    return Semantics(
      button: true,
      label: '${badge.label}. Open sync status',
      child: InkWell(
        key: const Key('savedChip'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => showSyncSheet(context, localId),
        child: Container(
          margin: const EdgeInsets.only(right: Sx.s12),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: c.surfaceAlt,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: badge == SyncBadge.saved ? c.cardEdge : color.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (badge == SyncBadge.syncing)
                SizedBox(width: 11, height: 11, child: CircularProgressIndicator(strokeWidth: 1.6, color: color))
              else
                Icon(icon, size: badge == SyncBadge.online ? 8 : 13, color: color),
              const SizedBox(width: 4),
              Text(badge.short, key: Key('syncBadge.${badge.name}'), style: SxType.label(badge == SyncBadge.saved ? c.inkMuted : color, size: 11)),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showSyncSheet(BuildContext context, String localId) => showSxSheet<void>(
      context,
      scrollable: false,
      builder: (_) => _SyncSheet(localId: localId),
    );

class _SyncSheet extends ConsumerStatefulWidget {
  const _SyncSheet({required this.localId});

  final String localId;

  @override
  ConsumerState<_SyncSheet> createState() => _SyncSheetState();
}

class _SyncSheetState extends ConsumerState<_SyncSheet> {
  bool _busy = false;

  Future<void> _syncNow() async {
    setState(() => _busy = true);
    await ref.read(casualSyncProvider.notifier).retryFailed();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final badge = ref.watch(syncBadgeProvider(widget.localId));
    final s = ref.watch(casualSyncProvider)[widget.localId];
    final (color, icon) = _look(c, badge);
    final text = switch (badge) {
      SyncBadge.saved => 'Every point is saved on this phone as it is scored.',
      SyncBadge.online => 'Every point is saved on this phone first, then sent to SkorX a few seconds later.',
      SyncBadge.offline =>
        "You're offline. Don't worry: scoring continues and your match syncs automatically when you're back online.",
      SyncBadge.syncing => 'Sending this match to SkorX…',
      SyncBadge.synced => 'SkorX has every point of this match.',
      SyncBadge.failed => 'SkorX could not accept this match: ${s?.error ?? 'unknown error'}. It is still saved on this phone and will be tried again.',
      SyncBadge.attention => 'This match was also changed on another device. Nothing was overwritten. Resolve it under My Paddle › Offline matches.',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sx.s20, 0, Sx.s20, Sx.s24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: badge == SyncBadge.online ? 12 : 22),
              const SizedBox(width: Sx.s8),
              Expanded(child: Text(badge.label, style: SxType.heading(c.ink, size: 18))),
            ],
          ),
          const SizedBox(height: Sx.s12),
          Text(text, style: SxType.body(c.inkMuted)),
          if (s?.lastSyncedAt != null) ...[
            const SizedBox(height: Sx.s8),
            Text('Last synced ${timeAgo(s!.lastSyncedAt!, DateTime.now())}', style: SxType.caption(c.inkFaint)),
          ],
          if (s != null && badge != SyncBadge.synced && badge != SyncBadge.attention) ...[
            const SizedBox(height: Sx.s20),
            SxButton.secondary(
              key: const Key('syncNow'),
              label: 'Sync now',
              icon: Icons.sync_rounded,
              busy: _busy,
              onPressed: _syncNow,
            ),
          ],
        ],
      ),
    );
  }
}

/// Short floating notices when the connection drops or returns during a
/// match: once offline per match, "Back online · Syncing match…", then
/// "✓ Match synced". Never a banner over the court.
class SyncNotices extends ConsumerStatefulWidget {
  const SyncNotices({super.key, required this.localId, required this.child});

  final String? localId;
  final Widget child;

  @override
  ConsumerState<SyncNotices> createState() => _SyncNoticesState();
}

class _SyncNoticesState extends ConsumerState<SyncNotices> {
  final _toldOffline = <String>{};
  bool _awaitingSynced = false;

  void _say(String text, {IconData? icon}) {
    final c = context.sx;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        content: Row(
          children: [
            if (icon != null) ...[Icon(icon, size: 18, color: c.onPrimary), const SizedBox(width: Sx.s8)],
            Expanded(child: Text(text)),
          ],
        ),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.localId;
    if (id != null) {
      ref.listen<NetStatus>(connectivityProvider, (previous, next) {
        if (next == NetStatus.offline && previous != NetStatus.offline && _toldOffline.add(id)) {
          _say("You're offline. Scoring continues and your match syncs when you're back online.", icon: Icons.cloud_off_rounded);
        } else if (next == NetStatus.online && previous == NetStatus.offline) {
          final s = ref.read(casualSyncProvider)[id];
          if (s != null && s.phase != SyncPhase.synced) {
            _awaitingSynced = true;
            _say('Back online · Syncing match…', icon: Icons.sync_rounded);
          }
        }
      });
      ref.listen<SyncBadge>(syncBadgeProvider(id), (previous, next) {
        if (next == SyncBadge.synced && _awaitingSynced) {
          _awaitingSynced = false;
          _say('Match synced', icon: Icons.check_circle_rounded);
        }
      });
    }
    return widget.child;
  }
}

// ─── My Paddle row ─────────────────────────────────────────────────────

/// "3 matches waiting to sync" / "All matches synced", to the Offline
/// matches page. Hidden until a match has been scored on this phone.
class OfflineMatchesRow extends ConsumerWidget {
  const OfflineMatchesRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final sum = ref.watch(offlineSummaryProvider);
    final net = ref.watch(connectivityProvider);
    if (sum.outstanding + sum.synced + sum.otherAccounts == 0) return const SizedBox.shrink();
    final (title, color, icon) = sum.conflicts > 0
        ? ('Match sync needs attention', c.live, Icons.warning_amber_rounded)
        : sum.failed > 0
            ? ('${_n(sum.failed)} failed to sync', c.live, Icons.error_outline_rounded)
            : sum.waiting > 0
                ? ('${_n(sum.waiting)} waiting to sync', c.caution, net == NetStatus.offline ? Icons.cloud_off_rounded : Icons.sync_rounded)
                : ('All matches synced', c.isDark ? c.volt : c.olive, Icons.cloud_done_rounded);
    return Padding(
      padding: const EdgeInsets.only(bottom: Sx.s12),
      child: SxBlock(
        key: const Key('offlineMatchesRow'),
        onTap: () => context.push('/player/offline-matches'),
        semanticLabel: 'Offline matches: $title',
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: Sx.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Offline matches', style: SxType.caption(c.inkMuted, size: 12)),
                  Text(title, style: SxType.heading(c.ink, size: 15)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: c.inkFaint),
          ],
        ),
      ),
    );
  }

  static String _n(int n) => n == 1 ? '1 match' : '$n matches';
}

// ─── Offline matches page ──────────────────────────────────────────────

class OfflineMatchesPage extends ConsumerStatefulWidget {
  const OfflineMatchesPage({super.key});

  @override
  ConsumerState<OfflineMatchesPage> createState() => _OfflineMatchesPageState();
}

class _OfflineMatchesPageState extends ConsumerState<OfflineMatchesPage> {
  bool _syncing = false;
  bool _retrying = false;

  Future<void> _go(bool failedToo) async {
    setState(() => failedToo ? _retrying = true : _syncing = true);
    final sync = ref.read(casualSyncProvider.notifier);
    await (failedToo ? sync.retryFailed() : sync.syncNow());
    if (mounted) setState(() => _syncing = _retrying = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final me = ref.watch(currentUserProvider)?.id;
    final ledger = ref.watch(casualSyncProvider);
    final sum = ref.watch(offlineSummaryProvider);
    final net = ref.watch(connectivityProvider);
    final active = ref.watch(scoringControllerProvider);
    final matches = {for (final m in ref.watch(playedMatchesProvider)) m.id: m};
    // The match on court, finished or not, as the scorer sees it now.
    if (active != null) matches[active.id] = active;
    final mine = [
      for (final s in ledger.values)
        if ((s.ownerUserId == null || s.ownerUserId == me) && matches[s.localId] != null) (s, matches[s.localId]!),
    ]..sort((x, y) {
        // Needing attention first, then waiting, then synced; newest first within each.
        int rank(CasualSync s) => switch (s.phase) {
              SyncPhase.conflict => 0,
              SyncPhase.failed => 1,
              SyncPhase.pending || SyncPhase.syncing => 2,
              SyncPhase.synced => 3,
            };
        final r = rank(x.$1).compareTo(rank(y.$1));
        return r != 0 ? r : (y.$2.finishedAt ?? y.$2.startedAt).compareTo(x.$2.finishedAt ?? x.$2.startedAt);
      });

    final headline = sum.outstanding == 0
        ? 'All matches synced'
        : '${sum.outstanding} ${sum.outstanding == 1 ? 'match' : 'matches'} waiting to sync';
    final status = switch (net) {
      NetStatus.offline => "You're offline. Matches sync automatically when you're back online.",
      NetStatus.online => 'Online. Matches sync automatically in the background.',
      NetStatus.unknown => 'Checking the connection…',
    };

    return Scaffold(
      backgroundColor: c.canvas,
      body: SafeArea(
        child: Column(
          children: [
            const SxBackBar(title: 'Offline matches'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(Sx.s16, Sx.s8, Sx.s16, Sx.s32),
                children: [
                  Text(headline, key: const Key('offlineHeadline'), style: SxType.title(c.ink, size: 26)),
                  const SizedBox(height: Sx.s4),
                  Text(status, style: SxType.body(c.inkMuted, size: 14)),
                  const SizedBox(height: Sx.s16),
                  Row(
                    children: [
                      Expanded(
                        child: SxButton(
                          key: const Key('syncAll'),
                          label: 'Sync now',
                          icon: Icons.sync_rounded,
                          busy: _syncing,
                          height: 48,
                          onPressed: sum.waiting + sum.failed == 0 ? null : () => _go(false),
                        ),
                      ),
                      if (sum.failed > 0) ...[
                        const SizedBox(width: Sx.s12),
                        Expanded(
                          child: SxButton.secondary(
                            key: const Key('retryFailed'),
                            label: 'Retry failed sync',
                            busy: _retrying,
                            height: 48,
                            onPressed: () => _go(true),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (sum.otherAccounts > 0) ...[
                    const SizedBox(height: Sx.s16),
                    SxBlock(
                      child: Text(
                        '${sum.otherAccounts} ${sum.otherAccounts == 1 ? 'match' : 'matches'} on this phone '
                        'belong to another SkorX account. They stay saved here and sync when that account signs in.',
                        style: SxType.caption(c.inkMuted),
                      ),
                    ),
                  ],
                  const SizedBox(height: Sx.s24),
                  if (mine.isEmpty)
                    const EmptyBlock(title: 'No matches yet', message: 'Matches you score on this phone appear here until SkorX has them.')
                  else
                    for (final (s, m) in mine) ...[_OfflineMatchCard(sync: s, match: m), const SizedBox(height: Sx.s12)],
                  const SizedBox(height: Sx.s16),
                  const _Diagnostics(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfflineMatchCard extends ConsumerWidget {
  const _OfflineMatchCard({required this.sync, required this.match});

  final CasualSync sync;
  final LocalMatch match;

  String _games(List<(int, int)> games) => games.map((g) => '${g.$1}–${g.$2}').join(', ');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final badge = ref.watch(syncBadgeProvider(match.id));
    final (color, icon) = _look(c, badge);
    final games = [
      for (final g in match.score.games)
        if (g.a + g.b > 0) (g.a, g.b),
    ];
    final now = DateTime.now();
    final when = match.finishedAt == null ? 'In progress · started ${timeAgo(match.startedAt, now)}' : 'Completed ${timeAgo(match.finishedAt!, now)}';
    final state = switch (badge) {
      SyncBadge.offline => 'Waiting for internet',
      SyncBadge.online => 'Waiting to sync',
      SyncBadge.failed => 'Sync failed: ${sync.error ?? 'unknown error'}',
      _ => badge.label,
    };
    return SxBlock(
      key: Key('offlineMatch.${match.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(match.displayCode, style: SxType.label(c.inkFaint, size: 11)),
          const SizedBox(height: 2),
          Text('${match.label(Side.a)} vs ${match.label(Side.b)}', style: SxType.heading(c.ink, size: 15)),
          if (games.isNotEmpty) Text(_games(games), style: SxType.number(18, c.ink)),
          const SizedBox(height: 2),
          Text(when, style: SxType.caption(c.inkMuted, size: 12)),
          const SizedBox(height: Sx.s8),
          Row(
            children: [
              if (badge == SyncBadge.syncing)
                SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.6, color: color))
              else
                Icon(icon, size: badge == SyncBadge.online ? 8 : 14, color: color),
              const SizedBox(width: 6),
              Expanded(child: Text(state, style: SxType.caption(color, size: 12.5).copyWith(fontWeight: FontWeight.w700))),
            ],
          ),
          if (sync.phase == SyncPhase.conflict && sync.conflict != null) ...[
            const SizedBox(height: Sx.s12),
            _ConflictPanel(sync: sync, match: match, games: games),
          ],
        ],
      ),
    );
  }
}

/// "Match sync needs attention": both scores side by side, and the
/// scorer's choice. Nothing is overwritten until they choose.
class _ConflictPanel extends ConsumerStatefulWidget {
  const _ConflictPanel({required this.sync, required this.match, required this.games});

  final CasualSync sync;
  final LocalMatch match;
  final List<(int, int)> games;

  @override
  ConsumerState<_ConflictPanel> createState() => _ConflictPanelState();
}

class _ConflictPanelState extends ConsumerState<_ConflictPanel> {
  bool _busy = false;

  Future<void> _choose(bool keepMine) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(keepMine ? "Keep this phone's score?" : "Use SkorX's score?"),
        content: Text(keepMine
            ? "SkorX replaces the other device's points with this phone's. They stay on record, and the players confirm the result as usual."
            : "This phone's points are replaced by SkorX's. A copy of this phone's version is kept on the phone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(keepMine ? 'Keep mine' : "Use SkorX's")),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final sync = ref.read(casualSyncProvider.notifier);
    await (keepMine ? sync.keepMine(widget.match.id) : sync.useServer(widget.match.id));
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final theirs = widget.sync.conflict!;
    String label(List<(int, int)> g) => g.isEmpty ? 'No points' : g.map((x) => '${x.$1}–${x.$2}').join(', ');
    return Container(
      padding: const EdgeInsets.all(Sx.s12),
      decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(Sx.s12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Match sync needs attention', style: SxType.heading(c.ink, size: 14)),
          const SizedBox(height: Sx.s8),
          Text('This phone: ${label(widget.games)} (${widget.match.events.length} actions)', style: SxType.caption(c.ink)),
          Text('SkorX: ${label(theirs.games)} (${theirs.events.length} actions)', style: SxType.caption(c.ink)),
          const SizedBox(height: Sx.s12),
          Row(
            children: [
              Expanded(
                child: SxButton.secondary(
                  key: const Key('keepMine'),
                  label: "Keep this phone's",
                  height: 44,
                  busy: _busy,
                  onPressed: () => _choose(true),
                ),
              ),
              const SizedBox(width: Sx.s8),
              Expanded(
                child: SxButton.secondary(
                  key: const Key('useServer'),
                  label: "Use SkorX's",
                  height: 44,
                  onPressed: _busy ? null : () => _choose(false),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Client-side sync analytics, for support and debugging.
class _Diagnostics extends ConsumerWidget {
  const _Diagnostics();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final s = ref.watch(syncStatsProvider);
    final rows = <(String, String)>[
      ('Matches started offline', '${s.offlineCreated}'),
      ('Matches finished offline', '${s.offlineCompleted}'),
      ('Sync requests', '${s.requests}'),
      ('Matches synced', '${s.synced}'),
      ('Refused by SkorX', '${s.failed}'),
      ('Attempts without internet', '${s.networkFailures}'),
      ('Success rate', s.successRate == null ? '–' : '${(s.successRate! * 100).round()}%'),
      ('Average request', s.averageMs == null ? '–' : '${s.averageMs} ms'),
      ('Duplicates prevented', '${s.duplicates}'),
      ('Conflicts', '${s.conflicts}'),
      if (s.lastSyncAt != null) ('Last sync', timeAgo(s.lastSyncAt!, DateTime.now())),
      if (s.lastError != null) ('Last error', s.lastError!),
    ];
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const Key('syncDiagnostics'),
        tilePadding: EdgeInsets.zero,
        title: Text('Sync diagnostics', style: SxType.heading(c.inkMuted, size: 14)),
        children: [
          for (final (k, v) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Text(k, style: SxType.caption(c.inkMuted))),
                  const SizedBox(width: Sx.s12),
                  Flexible(child: Text(v, textAlign: TextAlign.end, style: SxType.caption(c.ink))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
