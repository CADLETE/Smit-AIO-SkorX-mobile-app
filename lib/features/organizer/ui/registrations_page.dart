import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/theme/typography.dart';
import '../../../shared/format.dart';
import '../../../shared/ui/charts.dart';
import '../../../shared/ui/components.dart';
import '../../shell/workspace_shell.dart';
import '../data/organizer_repository.dart';
import '../data/tms_models.dart';
import 'org_widgets.dart';

enum EntryFilter {
  all('All'),
  pending('To approve'),
  approved('Approved'),
  waitlist('Waitlist'),
  unpaid('Unpaid'),
  checkedIn('Checked in'),
  notArrived('Not arrived');

  const EntryFilter(this.label);
  final String label;

  bool matches(Entry e) => switch (this) {
        EntryFilter.all => true,
        EntryFilter.pending => e.approval == Approval.pending,
        EntryFilter.approved => e.approval == Approval.approved,
        EntryFilter.waitlist => e.approval == Approval.waitlisted,
        EntryFilter.unpaid => e.approval != Approval.rejected && e.payment == PaymentState.pending,
        EntryFilter.checkedIn => e.attendance == Attendance.checkedIn,
        EntryFilter.notArrived => e.inDraw && e.attendance != Attendance.checkedIn,
      };
}

/// A tournament's registrations as its own screen.
class RegistrationsPage extends ConsumerWidget {
  const RegistrationsPage({super.key, required this.orgId, required this.tournamentId, this.filter});

  final String orgId;
  final String tournamentId;
  final String? filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(orgTournamentProvider(tournamentId));
    return DetailScaffold(
      title: 'Registrations',
      fallback: '/org/$orgId/t/$tournamentId',
      body: AsyncBody<OrgTournament>(
        value: t,
        onRetry: () => ref.invalidate(orgTournamentProvider(tournamentId)),
        data: (t) => RegistrationsView(
          orgId: orgId,
          tournament: t,
          initialFilter: EntryFilter.values.asNameMap()[filter] ?? EntryFilter.all,
        ),
      ),
    );
  }
}

/// The Players tab: registrations for the tournament in focus, with a
/// switcher for the others.
class OrgPlayersTab extends ConsumerStatefulWidget {
  const OrgPlayersTab({super.key, required this.orgId});

  final String orgId;

  @override
  ConsumerState<OrgPlayersTab> createState() => _OrgPlayersTabState();
}

class _OrgPlayersTabState extends ConsumerState<OrgPlayersTab> {
  String? _chosen;

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(orgTournamentsProvider(widget.orgId)).value ?? const <OrgTournament>[];
    final focus = ref.watch(focusTournamentProvider(widget.orgId));
    return AsyncBody<OrgTournament?>(
      value: focus,
      onRetry: () => ref.invalidate(orgTournamentsProvider(widget.orgId)),
      loading: const Padding(padding: EdgeInsets.all(SkorxSpace.lg), child: SkeletonCard(height: 300)),
      data: (focused) {
        final t = all.where((t) => t.id == _chosen).firstOrNull ?? focused;
        if (t == null) {
          return const Padding(
            padding: EdgeInsets.all(SkorxSpace.lg),
            child: SkxEmpty(
              icon: Icons.groups_rounded,
              title: 'No players yet',
              message: 'Registrations for your tournaments show here as they arrive.',
            ),
          );
        }
        return RegistrationsView(
          key: ValueKey(t.id),
          orgId: widget.orgId,
          tournament: t,
          header: _TournamentSwitch(
            tournament: t,
            options: all.where((x) => x.status != TournamentStatus.draft).toList(),
            onChanged: (id) => setState(() => _chosen = id),
          ),
          inTab: true,
        );
      },
    );
  }
}

class _TournamentSwitch extends StatelessWidget {
  const _TournamentSwitch({required this.tournament, required this.options, required this.onChanged});

  final OrgTournament tournament;
  final List<OrgTournament> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    return SkxCard(
      padding: const EdgeInsets.symmetric(horizontal: SkorxSpace.lg, vertical: SkorxSpace.md),
      semanticLabel: 'Tournament: ${tournament.name}. Change',
      onTap: () async {
        final id = await showModalBottomSheet<String>(
          context: context,
          builder: (context) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final t in options)
                  ListTile(
                    title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('${t.status.label} · ${dateRange(t.start, t.end)}'),
                    trailing: t.id == tournament.id ? const Icon(Icons.check_rounded) : null,
                    onTap: () => Navigator.pop(context, t.id),
                  ),
              ],
            ),
          ),
        );
        if (id != null) onChanged(id);
      },
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('TOURNAMENT', style: SkorxType.label(color: colors.textMuted, size: 11)),
                Text(tournament.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ],
            ),
          ),
          TournamentStatusPill(tournament.status),
          const SizedBox(width: SkorxSpace.xs),
          Icon(Icons.unfold_more_rounded, color: colors.textMuted),
        ],
      ),
    );
  }
}

class RegistrationsView extends ConsumerStatefulWidget {
  const RegistrationsView({
    super.key,
    required this.orgId,
    required this.tournament,
    this.initialFilter = EntryFilter.all,
    this.header,
    this.inTab = false,
  });

  final String orgId;
  final OrgTournament tournament;
  final EntryFilter initialFilter;
  final Widget? header;

  /// Inside the tab bar, which floats over the bottom of the list.
  final bool inTab;

  @override
  ConsumerState<RegistrationsView> createState() => _RegistrationsViewState();
}

class _RegistrationsViewState extends ConsumerState<RegistrationsView> {
  late var _filter = widget.initialFilter;
  String? _category;
  var _query = '';

  OrgTournament get t => widget.tournament;

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    final can = orgPermissions(ref, widget.orgId);
    final entries = ref.watch(entriesProvider(t.id));
    final filters = [for (final f in EntryFilter.values) if (f != EntryFilter.unpaid || can.money) f];
    final editable = can.manageEntries && t.can(TmsAction.manageEntries);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(entriesProvider(t.id));
        await ref.read(entriesProvider(t.id).future);
      },
      child: ListView(
        padding: EdgeInsets.only(
          top: SkorxSpace.sm,
          bottom: (widget.inTab ? tabBottomPadding(context) + 80 : SkorxSpace.xxl + MediaQuery.paddingOf(context).bottom),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: SkorxSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.header != null) ...[widget.header!, const SizedBox(height: SkorxSpace.md)],
                SkxSearchField(hint: 'Search players', onChanged: (v) => setState(() => _query = v)),
              ],
            ),
          ),
          const SizedBox(height: SkorxSpace.sm),
          SkxChipBar(children: [
            for (final f in filters)
              SkxChip(
                key: Key('filter-${f.name}'),
                label: f.label,
                selected: _filter == f,
                count: entries.value?.where(f.matches).length,
                onTap: () => setState(() => _filter = f),
              ),
          ]),
          if (t.categories.length > 1)
            SkxChipBar(children: [
              SkxChip(label: 'All categories', selected: _category == null, onTap: () => setState(() => _category = null)),
              for (final c in t.categories)
                SkxChip(label: c.title, selected: _category == c.id, onTap: () => setState(() => _category = c.id)),
            ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(SkorxSpace.lg, SkorxSpace.md, SkorxSpace.lg, 0),
            child: AsyncBody<List<Entry>>(
              value: entries,
              onRetry: () => ref.invalidate(entriesProvider(t.id)),
              loading: const Column(children: [SkeletonCard(height: 110), SizedBox(height: 8), SkeletonCard(height: 110)]),
              data: (all) {
                final q = _query.trim().toLowerCase();
                final shown = all
                    .where((e) =>
                        _filter.matches(e) &&
                        (_category == null || e.categoryId == _category) &&
                        (q.isEmpty || e.name.toLowerCase().contains(q) || e.checkInCode.toLowerCase() == q))
                    .toList();
                final pending = shown.where((e) => e.approval == Approval.pending).toList();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!editable && can.manageEntries && t.status.index >= TournamentStatus.live.index)
                      Padding(
                        padding: const EdgeInsets.only(bottom: SkorxSpace.md),
                        child: SkxCard(
                          color: colors.surfaceMuted,
                          padding: const EdgeInsets.all(SkorxSpace.md),
                          child: Row(
                            children: [
                              Icon(Icons.lock_outline_rounded, color: colors.textMuted, size: 18),
                              const SizedBox(width: SkorxSpace.sm),
                              Expanded(
                                child: Text(
                                  'Entries are locked while the tournament is ${t.status.label.toLowerCase()}. Check-in still works.',
                                  style: TextStyle(color: colors.textMuted, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${shown.length} ${shown.length == 1 ? 'entry' : 'entries'}',
                            style: SkorxType.label(color: colors.textMuted, size: 12),
                          ),
                        ),
                        if (editable && pending.length > 1)
                          SkxButton.ghost(
                            key: const Key('approveAll'),
                            label: 'Approve all ${pending.length}',
                            onPressed: () => _approveAll(pending),
                          ),
                      ],
                    ),
                    const SizedBox(height: SkorxSpace.sm),
                    if (shown.isEmpty)
                      SkxEmpty(
                        compact: true,
                        icon: Icons.person_search_rounded,
                        title: all.isEmpty ? 'No registrations yet' : 'Nobody here',
                        message: all.isEmpty
                            ? 'Share the tournament link. Registrations show here the moment players sign up.'
                            : 'Try another filter or search.',
                      ),
                    for (final e in shown) ...[
                      _EntryCard(
                        entry: e,
                        tournament: t,
                        money: can.money,
                        editable: editable,
                        onTap: () => showEntrySheet(context, ref, widget.orgId, t, e),
                        onDecide: (a) => _decide(e, a),
                      ),
                      const SizedBox(height: SkorxSpace.sm),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmAfterDraw() async {
    final warning = TournamentLifecycle.warning(t.status, TmsAction.manageEntries);
    if (warning == null) return true;
    return confirmAction(context, title: 'The draw is made', message: warning, confirm: 'Change anyway');
  }

  Future<void> _decide(Entry e, Approval approval) async {
    if (!await _confirmAfterDraw() || !mounted) return;
    HapticFeedback.selectionClick();
    await runAction(
      context,
      () => ref.read(organizerRepositoryProvider).updateEntry(e.id, EntryChange(approval: approval)),
      success: '${e.shortName}: ${approval.label.toLowerCase()}.',
    );
  }

  Future<void> _approveAll(List<Entry> pending) async {
    final ok = await confirmAction(
      context,
      title: 'Approve ${pending.length} entries?',
      message: 'Entries that do not fit a full category stay pending so you can waitlist them.',
      confirm: 'Approve all',
    );
    if (!ok || !mounted || !await _confirmAfterDraw() || !mounted) return;
    final repo = ref.read(organizerRepositoryProvider);
    var approved = 0;
    for (final e in pending) {
      try {
        await repo.updateEntry(e.id, const EntryChange(approval: Approval.approved));
        approved++;
      } catch (_) {
        // Full category: leave it pending.
      }
    }
    if (mounted) {
      showSkxToast(context, approved == pending.length ? 'All $approved approved.' : '$approved approved. ${pending.length - approved} did not fit.');
    }
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.entry,
    required this.tournament,
    required this.money,
    required this.editable,
    required this.onTap,
    required this.onDecide,
  });

  final Entry entry;
  final OrgTournament tournament;
  final bool money;
  final bool editable;
  final VoidCallback onTap;
  final ValueChanged<Approval> onDecide;

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    final e = entry;
    final c = tournament.category(e.categoryId);
    return SkxCard(
      onTap: onTap,
      semanticLabel: '${e.name}, ${c?.title}, ${e.approval.label}${money ? ', ${e.payment.label}' : ''}',
      padding: const EdgeInsets.all(SkorxSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Avatars(players: e.players),
              const SizedBox(width: SkorxSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.name, maxLines: 2, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(
                      [c?.title ?? '', if (e.rating != null) 'Rating ${e.rating}'].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.textMuted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              if (e.seed != null)
                Padding(
                  padding: const EdgeInsets.only(left: SkorxSpace.sm),
                  child: SkxPill('Seed ${e.seed}', tone: SkxTone.brand),
                ),
            ],
          ),
          const SizedBox(height: SkorxSpace.sm),
          Wrap(
            spacing: SkorxSpace.xs,
            runSpacing: SkorxSpace.xs,
            children: [
              SkxPill(e.approval.label, tone: approvalTone(e.approval)),
              if (money) SkxPill(e.payment.label, tone: paymentTone(e.payment)),
              if (e.inDraw && e.attendance != Attendance.notArrived)
                SkxPill(e.attendance.label, tone: e.attendance == Attendance.checkedIn ? SkxTone.success : SkxTone.live),
              if (e.needsPartner && c != null && c.playersPerSide == 2) const SkxPill('Needs partner', tone: SkxTone.warning),
            ],
          ),
          if (editable && e.approval == Approval.pending) ...[
            const SizedBox(height: SkorxSpace.md),
            Row(
              children: [
                Expanded(
                  child: SkxButton(
                    key: Key('approve-${e.id}'),
                    label: 'Approve',
                    height: 44,
                    onPressed: () => onDecide(Approval.approved),
                  ),
                ),
                const SizedBox(width: SkorxSpace.sm),
                SkxButton.secondary(label: 'Waitlist', height: 44, expand: false, onPressed: () => onDecide(Approval.waitlisted)),
                const SizedBox(width: SkorxSpace.sm),
                SkxButton.secondary(label: 'Reject', height: 44, expand: false, onPressed: () => onDecide(Approval.rejected)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Avatars extends StatelessWidget {
  const _Avatars({required this.players});

  final List<PlayerRef> players;

  @override
  Widget build(BuildContext context) {
    if (players.length < 2) return PlayerAvatar(name: players.firstOrNull?.name ?? '', size: 44);
    return SizedBox(
      width: 64,
      height: 44,
      child: Stack(
        children: [
          PlayerAvatar(name: players[0].name, size: 40),
          Positioned(
            left: 24,
            top: 4,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: context.skorx.colors.surface, width: 2),
              ),
              child: PlayerAvatar(name: players[1].name, size: 38),
            ),
          ),
        ],
      ),
    );
  }
}

/// Everything about one entry, and what can be done to it.
Future<void> showEntrySheet(BuildContext context, WidgetRef ref, String orgId, OrgTournament t, Entry entry) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _EntrySheet(orgId: orgId, tournament: t, entryId: entry.id),
  );
}

class _EntrySheet extends ConsumerWidget {
  const _EntrySheet({required this.orgId, required this.tournament, required this.entryId});

  final String orgId;
  final OrgTournament tournament;
  final String entryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.skorx.colors;
    final can = orgPermissions(ref, orgId);
    final t = tournament;
    final e = ref.watch(entriesProvider(t.id)).value?.where((x) => x.id == entryId).firstOrNull;
    if (e == null) return const SizedBox(height: 200);
    final c = t.category(e.categoryId);
    final repo = ref.read(organizerRepositoryProvider);
    final editable = can.manageEntries && t.can(TmsAction.manageEntries);

    Future<void> change(EntryChange change, String done) async {
      final warning = change.approval != null || change.categoryId != null
          ? TournamentLifecycle.warning(t.status, TmsAction.manageEntries)
          : null;
      if (warning != null && !await confirmAction(context, title: 'The draw is made', message: warning, confirm: 'Change anyway')) {
        return;
      }
      if (context.mounted) await runAction(context, () => repo.updateEntry(e.id, change), success: done);
    }

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: EdgeInsets.fromLTRB(SkorxSpace.xl, 0, SkorxSpace.xl, SkorxSpace.xl + MediaQuery.paddingOf(context).bottom),
        children: [
          Row(
            children: [
              _Avatars(players: e.players),
              const SizedBox(width: SkorxSpace.md),
              Expanded(child: Text(e.name.toUpperCase(), style: SkorxType.headline(24, color: colors.text))),
            ],
          ),
          const SizedBox(height: SkorxSpace.md),
          Wrap(spacing: SkorxSpace.xs, runSpacing: SkorxSpace.xs, children: [
            SkxPill(e.approval.label, tone: approvalTone(e.approval)),
            if (can.money) SkxPill(e.payment.label, tone: paymentTone(e.payment)),
            SkxPill(e.attendance.label, tone: e.attendance == Attendance.checkedIn ? SkxTone.success : SkxTone.neutral),
            if (e.seed != null) SkxPill('Seed ${e.seed}', tone: SkxTone.brand),
          ]),
          const SizedBox(height: SkorxSpace.lg),
          SkxGroup(title: 'From their SkorX profile', children: [
            for (final p in e.players)
              SkxRow(
                icon: Icons.person_rounded,
                label: p.name,
                subtitle: [p.rating == null ? 'Unrated' : 'Rating ${p.rating}', ?p.city].join(' · '),
                showChevron: false,
              ),
          ]),
          Padding(
            padding: const EdgeInsets.only(top: SkorxSpace.sm, left: SkorxSpace.xs),
            child: Text('Only players can change their own profile.', style: TextStyle(color: colors.textMuted, fontSize: 12)),
          ),
          SkxGroup(title: 'Entry', children: [
            SkxRow(icon: Icons.category_rounded, label: c?.title ?? '', subtitle: 'Category', showChevron: false),
            SkxRow(icon: Icons.event_rounded, label: '${dayDate(e.registeredAt)}, ${time12(e.registeredAt)}', subtitle: 'Registered', showChevron: false),
            SkxRow(icon: Icons.confirmation_number_rounded, label: e.checkInCode, subtitle: 'Ticket code', showChevron: false),
            if (can.money) SkxRow(icon: Icons.payments_rounded, label: formatInr(e.amount), subtitle: 'Entry fee', showChevron: false),
          ]),
          if (editable) ...[
            const SkxSectionTitle('Decision'),
            Row(children: [
              for (final a in [Approval.approved, Approval.waitlisted, Approval.rejected]) ...[
                Expanded(
                  child: SkxChip(
                    label: a == Approval.approved ? 'Approve' : a == Approval.waitlisted ? 'Waitlist' : 'Reject',
                    selected: e.approval == a,
                    onTap: () => change(EntryChange(approval: a), '${e.shortName}: ${a.label.toLowerCase()}.'),
                  ),
                ),
                if (a != Approval.rejected) const SizedBox(width: SkorxSpace.sm),
              ],
            ]),
            if (t.categories.where((x) => x.format == c?.format && x.id != e.categoryId).isNotEmpty) ...[
              const SizedBox(height: SkorxSpace.sm),
              SkxButton.secondary(
                label: 'Move to another category',
                icon: Icons.swap_horiz_rounded,
                onPressed: () async {
                  final to = await showModalBottomSheet<String>(
                    context: context,
                    builder: (context) => SafeArea(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        for (final x in t.categories.where((x) => x.format == c?.format && x.id != e.categoryId))
                          ListTile(title: Text(x.title), onTap: () => Navigator.pop(context, x.id)),
                      ]),
                    ),
                  );
                  if (to != null) await change(EntryChange(categoryId: to), 'Moved to ${t.category(to)?.title}.');
                },
              ),
            ],
          ],
          if (can.checkIn && e.inDraw && t.can(TmsAction.checkIn)) ...[
            const SkxSectionTitle('Check-in'),
            Row(children: [
              Expanded(
                child: SkxButton.secondary(
                  label: e.attendance == Attendance.checkedIn ? 'Undo check-in' : 'Check in',
                  icon: Icons.how_to_reg_rounded,
                  onPressed: () => change(
                    EntryChange(attendance: e.attendance == Attendance.checkedIn ? Attendance.notArrived : Attendance.checkedIn),
                    e.attendance == Attendance.checkedIn ? 'Check-in undone.' : '${e.shortName} checked in.',
                  ),
                ),
              ),
              const SizedBox(width: SkorxSpace.sm),
              SkxButton.secondary(
                label: 'Absent',
                expand: false,
                onPressed: e.attendance == Attendance.absent
                    ? null
                    : () => change(const EntryChange(attendance: Attendance.absent), '${e.shortName} marked absent.'),
              ),
            ]),
          ],
          if (can.money) ...[
            const SkxSectionTitle('Payment'),
            if (e.payment == PaymentState.pending)
              SkxButton.secondary(
                label: 'Mark as paid (cash or UPI at desk)',
                icon: Icons.check_circle_outline_rounded,
                onPressed: () => change(const EntryChange(payment: PaymentState.paid), 'Marked as paid.'),
              ),
            if (e.payment == PaymentState.paid)
              SkxButton(
                label: 'Refund ${formatInr(e.amount)}',
                kind: SkxButtonKind.danger,
                height: 52,
                onPressed: () async {
                  final ok = await confirmAction(
                    context,
                    title: 'Refund ${formatInr(e.amount)}?',
                    message: 'The money goes back to ${e.players.first.name} through Razorpay in 5–7 days. This cannot be undone.',
                    confirm: 'Refund',
                    cancel: 'Keep payment',
                    destructive: true,
                  );
                  if (ok) await change(const EntryChange(payment: PaymentState.refunded), 'Refund started.');
                },
              ),
          ],
          if (can.announce) ...[
            const SizedBox(height: SkorxSpace.lg),
            SkxButton.ghost(
              label: 'Message ${e.players.first.name.split(' ').first}',
              icon: Icons.chat_bubble_outline_rounded,
              onPressed: () {
                Navigator.pop(context);
                context.push('/org/$orgId/t/${t.id}/announce?player=${Uri.encodeComponent(e.name)}');
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// Tournament-day check-in: who has arrived, one big tap per player.
/// The Check-in tab: arrivals for the tournament in focus, since only one
/// runs at a time.
class OrgCheckInTab extends ConsumerWidget {
  const OrgCheckInTab({super.key, required this.orgId});

  final String orgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncBody<OrgTournament?>(
      value: ref.watch(focusTournamentProvider(orgId)),
      onRetry: () => ref.invalidate(orgTournamentsProvider(orgId)),
      loading: const Padding(padding: EdgeInsets.all(SkorxSpace.lg), child: SkeletonCard(height: 300)),
      data: (t) => t == null
          ? ListView(
              padding: const EdgeInsets.all(SkorxSpace.lg),
              children: const [
                ScreenHeader(title: 'Check-in'),
                SkxEmpty(
                  icon: Icons.how_to_reg_rounded,
                  title: 'No tournament to check in',
                  message: 'Arrivals for your next tournament show here once registration closes.',
                ),
              ],
            )
          : CheckInPage(key: ValueKey(t.id), orgId: orgId, tournamentId: t.id, inTab: true),
    );
  }
}

class CheckInPage extends ConsumerStatefulWidget {
  const CheckInPage({super.key, required this.orgId, required this.tournamentId, this.inTab = false});

  final String orgId;
  final String tournamentId;

  /// Shown as the Check-in tab: its own header, no back button.
  final bool inTab;

  @override
  ConsumerState<CheckInPage> createState() => _CheckInPageState();
}

class _CheckInPageState extends ConsumerState<CheckInPage> {
  var _query = '';
  var _arrived = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    final can = orgPermissions(ref, widget.orgId);
    final tAsync = ref.watch(orgTournamentProvider(widget.tournamentId));
    final entries = ref.watch(entriesProvider(widget.tournamentId));
    final repo = ref.read(organizerRepositoryProvider);

    final body = !can.checkIn
          ? const NoAccess(what: 'check players in')
          : AsyncBody<OrgTournament>(
              value: tAsync,
              onRetry: () => ref.invalidate(orgTournamentProvider(widget.tournamentId)),
              data: (t) {
                final list = (entries.value ?? const <Entry>[]).where((e) => e.inDraw).toList()
                  ..sort((a, b) => a.name.compareTo(b.name));
                final arrived = list.where((e) => e.attendance == Attendance.checkedIn).length;
                final q = _query.trim().toLowerCase();
                final shown = list
                    .where((e) => (e.attendance == Attendance.checkedIn) == _arrived)
                    .where((e) => q.isEmpty || e.name.toLowerCase().contains(q) || e.checkInCode.toLowerCase() == q)
                    .toList();
                final allowed = t.can(TmsAction.checkIn);
                return ListView(
                  padding: EdgeInsets.fromLTRB(
                    SkorxSpace.lg,
                    SkorxSpace.sm,
                    SkorxSpace.lg,
                    widget.inTab ? tabBottomPadding(context) + 80 : SkorxSpace.xxl + MediaQuery.paddingOf(context).bottom,
                  ),
                  children: [
                    if (widget.inTab) ScreenHeader(title: 'Check-in', eyebrow: t.name),
                    SkxCard(
                      padding: const EdgeInsets.all(SkorxSpace.lg),
                      child: Row(
                        children: [
                          WinRing(percent: list.isEmpty ? 0 : (arrived * 100 / list.length).round(), size: 84, label: 'ARRIVED'),
                          const SizedBox(width: SkorxSpace.lg),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('$arrived of ${list.length}', style: SkorxType.score(32, color: colors.text)),
                                Text('entries checked in', style: TextStyle(color: colors.textMuted)),
                                const SizedBox(height: SkorxSpace.sm),
                                SkxPill(t.checkInOpen ? 'Check-in open' : 'Check-in closed',
                                    tone: t.checkInOpen ? SkxTone.success : SkxTone.neutral),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: SkorxSpace.md),
                    if (!allowed)
                      const SkxEmpty(
                        compact: true,
                        icon: Icons.lock_clock_rounded,
                        title: 'Check-in opens after registration closes',
                      )
                    else ...[
                      Row(
                        children: [
                          Expanded(
                            child: SkxButton(
                              key: const Key('enterCode'),
                              label: 'Ticket code',
                              icon: Icons.qr_code_2_rounded,
                              height: 52,
                              onPressed: t.checkInOpen ? () => _enterCode(t) : null,
                            ),
                          ),
                          const SizedBox(width: SkorxSpace.sm),
                          SkxButton.secondary(
                            key: const Key('toggleCheckIn'),
                            label: t.checkInOpen ? 'Close' : 'Open check-in',
                            expand: false,
                            onPressed: () async {
                              if (t.checkInOpen) {
                                final ok = await confirmAction(
                                  context,
                                  title: 'Close check-in?',
                                  message: 'Players who have not arrived can no longer check in from the app.',
                                  confirm: 'Close check-in',
                                );
                                if (!ok) return;
                              }
                              if (context.mounted) {
                                await runAction(context, () => repo.setCheckInOpen(t.id, !t.checkInOpen),
                                    success: t.checkInOpen ? 'Check-in closed.' : 'Check-in is open. Players can check in from the app.');
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: SkorxSpace.md),
                      SkxSearchField(hint: 'Search name or ticket code', onChanged: (v) => setState(() => _query = v)),
                      const SizedBox(height: SkorxSpace.md),
                      SkxSegmented<bool>(
                        segments: [(false, 'Not arrived (${list.length - arrived})'), (true, 'Checked in ($arrived)')],
                        selected: _arrived,
                        onChanged: (v) => setState(() => _arrived = v),
                      ),
                      const SizedBox(height: SkorxSpace.md),
                      if (!_arrived && list.length > arrived && t.checkInOpen)
                        Align(
                          alignment: Alignment.centerRight,
                          child: SkxButton.ghost(
                            label: 'Check in everyone',
                            onPressed: () async {
                              final ok = await confirmAction(
                                context,
                                title: 'Check in all ${list.length - arrived}?',
                                message: 'Use this when a team manager confirms the whole group has arrived.',
                                confirm: 'Check in all',
                              );
                              if (ok && context.mounted) {
                                await runAction(context, () => repo.checkInAll(t.id), success: 'Everyone checked in.');
                              }
                            },
                          ),
                        ),
                      if (shown.isEmpty)
                        SkxEmpty(
                          compact: true,
                          icon: _arrived ? Icons.hourglass_empty_rounded : Icons.celebration_rounded,
                          title: _arrived ? 'Nobody checked in yet' : 'Everyone is here',
                        ),
                      for (final e in shown) ...[
                        _CheckInRow(
                          entry: e,
                          category: t.category(e.categoryId)?.title ?? '',
                          open: t.checkInOpen,
                          onToggle: () => runAction(
                            context,
                            () => repo.updateEntry(
                              e.id,
                              EntryChange(attendance: e.attendance == Attendance.checkedIn ? Attendance.notArrived : Attendance.checkedIn),
                            ),
                          ),
                        ),
                        const SizedBox(height: SkorxSpace.sm),
                      ],
                    ],
                  ],
                );
              },
            );
    if (widget.inTab) return body;
    return DetailScaffold(
      title: 'Check-in',
      fallback: '/org/${widget.orgId}/t/${widget.tournamentId}',
      body: body,
    );
  }

  Future<void> _enterCode(OrgTournament t) async {
    final controller = TextEditingController();
    final code = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(SkorxSpace.xl, 0, SkorxSpace.xl, SkorxSpace.xl + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('TICKET CODE', style: SkorxType.headline(26, color: context.skorx.colors.text)),
            const SizedBox(height: SkorxSpace.sm),
            Text('The 5 characters under the QR code on the player\'s SkorX ticket.',
                style: TextStyle(color: context.skorx.colors.textMuted)),
            const SizedBox(height: SkorxSpace.lg),
            TextField(
              key: const Key('codeField'),
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              style: SkorxType.score(32),
              textAlign: TextAlign.center,
              inputFormatters: [LengthLimitingTextInputFormatter(5)],
              onSubmitted: (v) => Navigator.pop(context, v),
            ),
            const SizedBox(height: SkorxSpace.lg),
            SkxButton(key: const Key('submitCode'), label: 'Check in', onPressed: () => Navigator.pop(context, controller.text)),
          ],
        ),
      ),
    );
    controller.dispose();
    if (code == null || code.trim().isEmpty || !mounted) return;
    await runAction(context, () async {
      final e = await ref.read(organizerRepositoryProvider).checkInByCode(t.id, code);
      HapticFeedback.heavyImpact();
      if (mounted) showSkxToast(context, '${e.name} checked in.');
    });
  }
}

class _CheckInRow extends StatelessWidget {
  const _CheckInRow({required this.entry, required this.category, required this.open, required this.onToggle});

  final Entry entry;
  final String category;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    final e = entry;
    final done = e.attendance == Attendance.checkedIn;
    return SkxCard(
      padding: const EdgeInsets.fromLTRB(SkorxSpace.md, SkorxSpace.sm, SkorxSpace.sm, SkorxSpace.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                Text('$category · ${e.checkInCode}', style: TextStyle(color: colors.textMuted, fontSize: 12.5)),
              ],
            ),
          ),
          done
              ? SkxButton.ghost(label: 'Undo', onPressed: onToggle)
              : SkxButton(
                  key: Key('checkIn-${e.id}'),
                  label: 'Check in',
                  height: 48,
                  expand: false,
                  onPressed: open ? onToggle : null,
                ),
        ],
      ),
    );
  }
}
