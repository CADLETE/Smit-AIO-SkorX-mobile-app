import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/theme/typography.dart';
import '../../../shared/format.dart';
import '../../../shared/ui/components.dart';
import '../data/organizer_repository.dart';
import '../data/tms_models.dart';
import 'org_widgets.dart';

/// Top right of every organiser tab: every tournament action one tap away,
/// for the tournament that is running (or next).
class OrgActionsButton extends StatelessWidget {
  const OrgActionsButton({super.key, required this.orgId});

  final String orgId;

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    final accent = context.skorx.highlight;
    return Semantics(
      button: true,
      label: 'Tournament actions',
      excludeSemantics: true,
      child: InkWell(
        key: const Key('orgActions'),
        borderRadius: BorderRadius.circular(SkorxRadius.xl),
        onTap: () {
          HapticFeedback.selectionClick();
          showTournamentActions(context, orgId);
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: SkorxSpace.md),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(SkorxRadius.xl),
            border: Border.all(color: accent.withValues(alpha: 0.45)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bolt_rounded, size: 20, color: accent),
              const SizedBox(width: SkorxSpace.xs),
              Text('Actions', style: TextStyle(fontWeight: FontWeight.w800, color: colors.text)),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showTournamentActions(BuildContext context, String orgId) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ActionsSheet(orgId: orgId),
    );

class _Action {
  const _Action(this.key, this.icon, this.label, this.route, {this.badge, this.primary = false, this.go = false});

  final String key;
  final IconData icon;
  final String label;
  final String route;
  final int? badge;
  final bool primary;

  /// A tab rather than a page on top.
  final bool go;
}

class _ActionsSheet extends ConsumerWidget {
  const _ActionsSheet({required this.orgId});

  final String orgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.skorx.colors;
    final can = orgPermissions(ref, orgId);
    final t = ref.watch(focusTournamentProvider(orgId)).value;
    final entries = t == null ? const <Entry>[] : ref.watch(entriesProvider(t.id)).value ?? const <Entry>[];
    final toApprove = entries.where((e) => e.approval == Approval.pending).length;
    final unpaid = entries.where((e) => e.approval != Approval.rejected && e.payment == PaymentState.pending).length;
    final notArrived = entries.where((e) => e.inDraw && e.attendance != Attendance.checkedIn).length;
    final live = t?.status == TournamentStatus.live;
    final base = t == null ? '' : '/org/$orgId/t/${t.id}';

    final actions = <_Action>[
      if (t != null) ...[
        if (can.score && live) _Action('live', Icons.scoreboard_rounded, 'Score & live', '/org/$orgId/live', primary: true, go: true),
        if (can.checkIn)
          _Action('checkIn', Icons.qr_code_scanner_rounded, 'Check-in', '/org/$orgId/check-in',
              badge: t.checkInOpen ? notArrived : null, go: true),
        if (can.manageEntries)
          _Action('approve', Icons.how_to_reg_rounded, 'Approve', '$base/registrations?filter=pending', badge: toApprove),
        _Action('registrations', Icons.groups_rounded, 'Entries', '$base/registrations'),
        if (can.money) _Action('payments', Icons.payments_rounded, 'Payments', '$base/registrations?filter=unpaid', badge: unpaid),
        if (can.announce) _Action('announce', Icons.campaign_rounded, 'Announce', '$base/announce'),
        _Action('draw', Icons.account_tree_rounded, 'Draws', '$base/draw'),
        _Action('schedule', Icons.calendar_month_rounded, 'Schedule', '$base/schedule'),
        if (can.schedule) _Action('courts', Icons.grid_on_rounded, 'Courts', '$base/courts'),
        _Action('results', Icons.emoji_events_rounded, 'Results', '$base/results'),
      ],
    ];

    // The router outlives the sheet, so take it before closing.
    final router = GoRouter.of(context);
    void open(String route, {bool go = false}) {
      Navigator.of(context).pop();
      go ? router.go(route) : router.push(route);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(SkorxSpace.lg, 0, SkorxSpace.lg, SkorxSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('TOURNAMENT ACTIONS', style: SkorxType.headline(28, color: colors.text)),
          const SizedBox(height: SkorxSpace.md),
          if (t == null)
            const SkxEmpty(
              compact: true,
              icon: Icons.emoji_events_rounded,
              title: 'No tournament running',
              message: 'Create one to run registrations, check-in, draws and scoring from here.',
            )
          else ...[
            SkxCard(
              key: const Key('actionsTournament'),
              padding: const EdgeInsets.all(SkorxSpace.md),
              onTap: () => open(base),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        const SizedBox(height: 2),
                        Text(
                          '${dayDate(t.start)} · ${t.venue}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: colors.textMuted, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: SkorxSpace.sm),
                  TournamentStatusPill(t.status),
                  Icon(Icons.chevron_right_rounded, color: colors.textMuted),
                ],
              ),
            ),
            const SizedBox(height: SkorxSpace.md),
            LayoutBuilder(builder: (context, box) {
              final perRow = box.maxWidth >= 480 ? 5 : 4;
              final width = (box.maxWidth - SkorxSpace.sm * (perRow - 1)) / perRow;
              return Wrap(
                spacing: SkorxSpace.sm,
                runSpacing: SkorxSpace.sm,
                children: [
                  for (final a in actions)
                    SizedBox(width: width, child: _ActionTile(action: a, onTap: () => open(a.route, go: a.go))),
                ],
              );
            }),
          ],
          const SizedBox(height: SkorxSpace.lg),
          SkxGroup(children: [
            if (can.editTournaments)
              SkxRow(
                key: const Key('actionsNewTournament'),
                icon: Icons.add_circle_outline_rounded,
                iconColor: context.skorx.highlight,
                label: 'New tournament',
                onTap: () => open('/org/$orgId/new-tournament'),
              ),
            SkxRow(
              key: const Key('actionsAllTournaments'),
              icon: Icons.format_list_bulleted_rounded,
              label: 'All tournaments',
              subtitle: 'Active, drafts and past',
              onTap: () => open('/org/$orgId/tournaments'),
            ),
          ]),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.action, required this.onTap});

  final _Action action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    final accent = context.skorx.highlight;
    final badge = action.badge ?? 0;
    return Semantics(
      button: true,
      label: badge > 0 ? '${action.label}, $badge' : action.label,
      excludeSemantics: true,
      child: InkWell(
        key: Key('action-${action.key}'),
        borderRadius: BorderRadius.circular(SkorxRadius.md),
        onTap: onTap,
        child: Container(
          height: 84,
          decoration: BoxDecoration(
            color: action.primary ? accent.withValues(alpha: 0.16) : colors.surfaceMuted,
            borderRadius: BorderRadius.circular(SkorxRadius.md),
            border: Border.all(color: action.primary ? accent.withValues(alpha: 0.5) : colors.border),
          ),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(action.icon, color: action.primary ? accent : colors.text, size: 26),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        action.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              if (badge > 0)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: colors.warning, borderRadius: BorderRadius.circular(10)),
                    child: Text('$badge', style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.w900)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
