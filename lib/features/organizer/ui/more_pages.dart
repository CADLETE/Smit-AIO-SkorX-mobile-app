import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/theme/typography.dart';
import '../../../shared/format.dart';
import '../../../shared/ui/components.dart';
import '../../workspace/workspace.dart';
import '../data/organizer_repository.dart';
import '../data/tms_models.dart';
import 'org_widgets.dart';

EdgeInsets _pagePadding(BuildContext context) =>
    EdgeInsets.fromLTRB(SkorxSpace.lg, SkorxSpace.sm, SkorxSpace.lg, SkorxSpace.xxl + MediaQuery.paddingOf(context).bottom);

/// Money in, money out, and what is still owed.
class FinancePage extends ConsumerWidget {
  const FinancePage({super.key, required this.orgId});

  final String orgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.skorx.colors;
    final can = orgPermissions(ref, orgId);
    final finance = ref.watch(financeProvider(orgId));
    return DetailScaffold(
      title: 'Finance',
      fallback: '/org/$orgId/profile',
      body: !can.money
          ? const NoAccess(what: 'see payments')
          : AsyncBody<OrgFinance>(
              value: finance,
              onRetry: () => ref.invalidate(financeProvider(orgId)),
              data: (f) => ListView(
                padding: _pagePadding(context),
                children: [
                  SkxCard(
                    padding: const EdgeInsets.all(SkorxSpace.xl),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('NET', style: SkorxType.label(color: colors.textMuted, size: 12)),
                        Text(formatInr(f.net, freeWhenZero: false),
                            style: SkorxType.score(48, color: f.net >= 0 ? colors.success : colors.live)),
                        const SizedBox(height: SkorxSpace.xs),
                        Text('${formatInr(f.revenue, freeWhenZero: false)} in · ${formatInr(f.spent, freeWhenZero: false)} out',
                            style: TextStyle(color: colors.textMuted)),
                      ],
                    ),
                  ),
                  const SizedBox(height: SkorxSpace.md),
                  MetricGrid(children: [
                    MetricCard(label: 'Collected', value: formatInr(f.collected, freeWhenZero: false), icon: Icons.check_circle_rounded),
                    MetricCard(
                      label: 'Pending',
                      value: formatInr(f.outstanding, freeWhenZero: false),
                      icon: Icons.hourglass_bottom_rounded,
                      tone: f.outstanding > 0 ? SkxTone.warning : null,
                    ),
                    MetricCard(label: 'Refunded', value: formatInr(f.refunded, freeWhenZero: false), icon: Icons.undo_rounded),
                    MetricCard(label: 'Sponsorship', value: formatInr(f.sponsorship, freeWhenZero: false), icon: Icons.handshake_rounded),
                  ]),
                  const SkxSectionTitle('Expenses'),
                  if (f.expenses.isEmpty)
                    const SkxEmpty(compact: true, icon: Icons.receipt_long_rounded, title: 'No expenses recorded'),
                  if (f.expenses.isNotEmpty)
                    SkxGroup(children: [
                      for (final e in f.expenses)
                        SkxRow(
                          icon: _expenseIcon(e.kind),
                          label: e.label,
                          subtitle: e.kind.name[0].toUpperCase() + e.kind.name.substring(1),
                          trailing: Text(formatInr(e.amount), style: SkorxType.score(18, color: colors.text)),
                        ),
                    ]),
                  const SkxSectionTitle('Sponsors'),
                  SkxGroup(children: [
                    for (final s in f.sponsors)
                      SkxRow(
                        icon: Icons.workspace_premium_rounded,
                        label: s.name,
                        subtitle: '${s.package} · ${s.placements.join(', ')}',
                        trailing: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(formatInr(s.amount), style: SkorxType.score(17, color: colors.text)),
                            SkxPill(s.paid ? 'Paid' : 'Due', tone: s.paid ? SkxTone.success : SkxTone.warning),
                          ],
                        ),
                      ),
                  ]),
                ],
              ),
            ),
    );
  }

  static IconData _expenseIcon(ExpenseKind k) => switch (k) {
        ExpenseKind.venue => Icons.stadium_rounded,
        ExpenseKind.officials || ExpenseKind.staff => Icons.badge_rounded,
        ExpenseKind.equipment => Icons.sports_tennis_rounded,
        ExpenseKind.marketing => Icons.campaign_rounded,
        ExpenseKind.food => Icons.restaurant_rounded,
        ExpenseKind.prizes => Icons.emoji_events_rounded,
        ExpenseKind.other => Icons.receipt_rounded,
      };
}

/// A few numbers that matter, each answering one question.
class AnalyticsPage extends ConsumerWidget {
  const AnalyticsPage({super.key, required this.orgId});

  final String orgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final can = orgPermissions(ref, orgId);
    final focus = ref.watch(focusTournamentProvider(orgId));
    return DetailScaffold(
      title: 'Analytics',
      fallback: '/org/$orgId/profile',
      body: !can.analytics
          ? const NoAccess(what: 'see analytics')
          : AsyncBody<OrgTournament?>(
              value: focus,
              onRetry: () => ref.invalidate(orgTournamentsProvider(orgId)),
              data: (t) => t == null
                  ? const Padding(
                      padding: EdgeInsets.all(SkorxSpace.lg),
                      child: SkxEmpty(icon: Icons.query_stats_rounded, title: 'Numbers appear once registrations do'),
                    )
                  : _TournamentAnalytics(tournament: t),
            ),
    );
  }
}

class _TournamentAnalytics extends ConsumerWidget {
  const _TournamentAnalytics({required this.tournament});

  final OrgTournament tournament;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.skorx.colors;
    final t = tournament;
    final entries = ref.watch(entriesProvider(t.id)).value ?? const <Entry>[];
    final matches = ref.watch(tmsMatchesProvider(t.id)).value ?? const <TmsMatch>[];
    final courts = ref.watch(courtsProvider(t.id)).value ?? const <TmsCourt>[];
    final approved = entries.where((e) => e.inDraw).toList();
    final arrived = approved.where((e) => e.attendance == Attendance.checkedIn).length;
    final noShows = approved.where((e) => e.attendance == Attendance.absent).length;
    final done = matches.where((m) => m.state == MatchState.completed && m.startedAt != null && m.completedAt != null).toList();
    final avgMinutes = done.isEmpty
        ? null
        : (done.fold(0, (s, m) => s + m.completedAt!.difference(m.startedAt!).inMinutes) / done.length).round();
    final now = DateTime.now();
    final delayed = matches.where((m) => m.isDelayed(now)).length;
    final perCourt = {
      for (final c in courts) c.name: matches.where((m) => m.courtId == c.id && m.state == MatchState.completed).length,
    };

    return ListView(
      padding: _pagePadding(context),
      children: [
        TournamentBanner(tournament: t),
        MetricGrid(children: [
          MetricCard(label: 'Registrations', value: '${entries.length}', icon: Icons.how_to_reg_rounded, caption: '${approved.length} approved'),
          MetricCard(
            label: 'Attendance',
            value: approved.isEmpty ? '–' : '${(arrived * 100 / approved.length).round()}%',
            icon: Icons.qr_code_scanner_rounded,
            caption: '$noShows no-shows',
          ),
          MetricCard(
            label: 'Completion',
            value: matches.isEmpty ? '–' : '${(matches.where((m) => m.state == MatchState.completed).length * 100 / matches.length).round()}%',
            icon: Icons.sports_score_rounded,
            caption: '${matches.length} matches',
          ),
          MetricCard(
            label: 'Avg match',
            value: avgMinutes == null ? '–' : '${avgMinutes}m',
            icon: Icons.timer_outlined,
            caption: '$delayed delayed now',
            tone: delayed > 0 ? SkxTone.warning : null,
          ),
        ]),
        const SkxSectionTitle('Entries by category'),
        _Bars(values: {
          for (final c in t.categories) c.title: entries.where((e) => e.categoryId == c.id && e.approval != Approval.rejected).length,
        }, max: {for (final c in t.categories) c.title: c.capacity}),
        if (perCourt.values.any((v) => v > 0)) ...[
          const SkxSectionTitle('Matches finished per court'),
          _Bars(values: perCourt),
        ],
        const SizedBox(height: SkorxSpace.lg),
        Text('Showing ${t.name}. Retention and revenue trends across tournaments are on the web dashboard.',
            style: TextStyle(color: colors.textMuted, fontSize: 12.5)),
      ],
    );
  }
}

/// Horizontal magnitude bars, one hue; the value is written beside each bar
/// so nothing depends on reading the bar length alone.
class _Bars extends StatelessWidget {
  const _Bars({required this.values, this.max});

  final Map<String, int> values;

  /// Optional capacity per row, drawn as the track.
  final Map<String, int>? max;

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    final top = values.values.fold(1, (a, b) => a > b ? a : b);
    return SkxCard(
      padding: const EdgeInsets.all(SkorxSpace.lg),
      child: Column(
        children: [
          for (final MapEntry(key: label, value: v) in values.entries) ...[
            Semantics(
              label: '$label: $v${max?[label] == null ? '' : ' of ${max![label]}'}',
              excludeSemantics: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                    Text(max?[label] == null ? '$v' : '$v / ${max![label]}', style: SkorxType.score(16, color: colors.text)),
                  ]),
                  const SizedBox(height: 6),
                  LayoutBuilder(
                    builder: (context, box) {
                      final denominator = max?[label] ?? top;
                      final w = denominator == 0 ? 0.0 : box.maxWidth * (v / denominator).clamp(0, 1);
                      return Stack(children: [
                        Container(height: 10, decoration: BoxDecoration(color: colors.surfaceInteractive, borderRadius: BorderRadius.circular(4))),
                        Container(width: w, height: 10, decoration: BoxDecoration(color: colors.cyan, borderRadius: BorderRadius.circular(4))),
                      ]);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: SkorxSpace.md),
          ],
        ],
      ),
    );
  }
}

const _roleCapabilities = <String, List<String>>{
  'owner': ['Everything, including roles and payouts'],
  'tournament_admin': ['Create and run tournaments', 'Draws, schedule, courts', 'Scoring and results', 'Announcements'],
  'scorer': ['Score matches', 'See the live board'],
  'check_in_staff': ['Check players in', 'See registrations'],
  'finance': ['Payments, refunds, expenses', 'Sponsors'],
  'viewer': ['Read only'],
};

/// Who helps run the organisation, and what each role can do.
class StaffPage extends ConsumerWidget {
  const StaffPage({super.key, required this.orgId});

  final String orgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.skorx.colors;
    final can = orgPermissions(ref, orgId);
    final profile = ref.watch(orgProfileProvider(orgId));
    return DetailScaffold(
      title: 'Staff & roles',
      fallback: '/org/$orgId/profile',
      body: !can.settings
          ? const NoAccess(what: 'manage staff')
          : AsyncBody<OrgProfile>(
              value: profile,
              onRetry: () => ref.invalidate(orgProfileProvider(orgId)),
              data: (p) => ListView(
                padding: _pagePadding(context),
                children: [
                  SkxGroup(title: '${p.staff.length} people', children: [
                    for (final s in p.staff)
                      SkxRow(
                        icon: Icons.person_rounded,
                        label: s.name,
                        subtitle: roleLabel(s.role),
                        trailing: SkxPill(roleLabel(s.role), tone: s.role == 'owner' ? SkxTone.brand : SkxTone.neutral),
                      ),
                  ]),
                  const SizedBox(height: SkorxSpace.md),
                  SkxButton.secondary(
                    label: 'Invite by phone number',
                    icon: Icons.person_add_alt_1_rounded,
                    onPressed: () => showSkxToast(context, 'Invites are sent from the web dashboard for now.', icon: Icons.info_outline_rounded),
                  ),
                  const SkxSectionTitle('What each role can do'),
                  for (final MapEntry(key: role, value: caps) in _roleCapabilities.entries) ...[
                    SkxCard(
                      padding: const EdgeInsets.all(SkorxSpace.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(roleLabel(role), style: const TextStyle(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text(caps.join(' · '), style: TextStyle(color: colors.textMuted, fontSize: 13)),
                        ],
                      ),
                    ),
                    const SizedBox(height: SkorxSpace.sm),
                  ],
                  Text('The server enforces every role, whatever the app shows.', style: TextStyle(color: colors.textMuted, fontSize: 12)),
                ],
              ),
            ),
    );
  }
}

/// Every administrative change: who, what, when, before and after.
class AuditLogPage extends ConsumerWidget {
  const AuditLogPage({super.key, required this.orgId});

  final String orgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.skorx.colors;
    final can = orgPermissions(ref, orgId);
    final log = ref.watch(auditProvider(orgId));
    return DetailScaffold(
      title: 'Activity log',
      fallback: '/org/$orgId/profile',
      body: !can.settings
          ? const NoAccess(what: 'see the activity log')
          : AsyncBody<List<AuditEntry>>(
              value: log,
              onRetry: () => ref.invalidate(auditProvider(orgId)),
              data: (list) => ListView(
                padding: _pagePadding(context),
                children: [
                  if (list.isEmpty) const SkxEmpty(icon: Icons.history_rounded, title: 'No changes yet'),
                  for (final a in list) ...[
                    SkxCard(
                      padding: const EdgeInsets.all(SkorxSpace.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(child: Text(a.action, style: const TextStyle(fontWeight: FontWeight.w800))),
                            Text(timeAgo(a.at, DateTime.now()), style: TextStyle(color: colors.textMuted, fontSize: 12)),
                          ]),
                          const SizedBox(height: 2),
                          Text('${a.subject} · by ${a.actor}', style: TextStyle(color: colors.textMuted, fontSize: 13)),
                          if (a.before != null || a.after != null) ...[
                            const SizedBox(height: SkorxSpace.sm),
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: SkorxSpace.sm,
                              children: [
                                if (a.before != null) Text(a.before!, style: TextStyle(color: colors.textMuted, decoration: TextDecoration.lineThrough)),
                                if (a.before != null && a.after != null) Icon(Icons.arrow_forward_rounded, size: 14, color: colors.textMuted),
                                if (a.after != null) Text(a.after!, style: const TextStyle(fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: SkorxSpace.sm),
                  ],
                ],
              ),
            ),
    );
  }
}

/// The organisation as players see it: record, venues, reviews.
class OrgProfilePage extends ConsumerWidget {
  const OrgProfilePage({super.key, required this.orgId});

  final String orgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.skorx.colors;
    final name = orgWorkspace(ref, orgId)?.title ?? '';
    final profile = ref.watch(orgProfileProvider(orgId));
    final can = orgPermissions(ref, orgId);
    return DetailScaffold(
      title: 'Public profile',
      fallback: '/org/$orgId/profile',
      body: AsyncBody<OrgProfile>(
        value: profile,
        onRetry: () => ref.invalidate(orgProfileProvider(orgId)),
        data: (p) => ListView(
          padding: _pagePadding(context),
          children: [
            Row(
              children: [
                PlayerAvatar(name: name, size: 72, ring: true),
                const SizedBox(width: SkorxSpace.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name.toUpperCase(), style: SkorxType.headline(28, color: colors.text)),
                      const SizedBox(height: 4),
                      if (p.verified) const SkxPill('Verified organiser', tone: SkxTone.brand, icon: Icons.verified_rounded),
                      const SizedBox(height: 4),
                      Text('${p.city} · since ${monthsShort[p.since.month - 1]} ${p.since.year}',
                          style: TextStyle(color: colors.textMuted, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: SkorxSpace.xl),
            MetricGrid(children: [
              MetricCard(label: 'Tournaments', value: '${p.tournaments}', icon: Icons.emoji_events_rounded, caption: '${p.completed} completed'),
              MetricCard(label: 'Players hosted', value: '${p.playersHosted}', icon: Icons.groups_rounded, caption: '${p.repeatPlayerPercent}% come back'),
              MetricCard(label: 'Matches run', value: '${p.matchesManaged}', icon: Icons.scoreboard_rounded),
              MetricCard(label: 'Rating', value: p.averageRating.toStringAsFixed(1), icon: Icons.star_rounded, caption: '${p.reviews.length} recent reviews'),
            ]),
            SkxGroup(title: 'Contact', children: [
              if (p.contact != null) SkxRow(icon: Icons.phone_rounded, label: p.contact!, showChevron: false),
              if (p.website != null) SkxRow(icon: Icons.language_rounded, label: p.website!, showChevron: false),
            ]),
            SkxGroup(title: 'Venues', children: [
              for (final v in p.venues)
                SkxRow(
                  icon: v.indoor ? Icons.roofing_rounded : Icons.wb_sunny_rounded,
                  label: v.name,
                  subtitle: '${v.address} · ${v.courts} courts${v.amenities.isEmpty ? '' : ' · ${v.amenities.join(', ')}'}',
                  showChevron: false,
                ),
            ]),
            const SkxSectionTitle('Reviews'),
            for (final r in p.reviews) ...[
              SkxCard(
                padding: const EdgeInsets.all(SkorxSpace.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(child: Text(r.author, style: const TextStyle(fontWeight: FontWeight.w800))),
                      Semantics(
                        label: '${r.rating} of 5 stars',
                        excludeSemantics: true,
                        child: Row(children: [
                          for (var i = 0; i < 5; i++)
                            Icon(i < r.rating ? Icons.star_rounded : Icons.star_outline_rounded, size: 16, color: colors.warning),
                        ]),
                      ),
                    ]),
                    Text('${r.tournament} · ${timeAgo(r.at, DateTime.now())}', style: TextStyle(color: colors.textMuted, fontSize: 12)),
                    const SizedBox(height: SkorxSpace.sm),
                    Text(r.text, style: const TextStyle(height: 1.35)),
                    if (r.reply != null) ...[
                      const SizedBox(height: SkorxSpace.sm),
                      Container(
                        padding: const EdgeInsets.all(SkorxSpace.sm),
                        decoration: BoxDecoration(color: colors.surfaceInteractive, borderRadius: BorderRadius.circular(SkorxRadius.sm)),
                        child: Text('You replied: ${r.reply}', style: TextStyle(color: colors.textMuted, fontSize: 13)),
                      ),
                    ] else if (can.editTournaments)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SkxButton.ghost(
                          label: 'Reply',
                          onPressed: () => showSkxToast(context, 'Replies post from the web dashboard for now.', icon: Icons.info_outline_rounded),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: SkorxSpace.sm),
            ],
            Text("Reviews are the players' own words. Organisers can reply but never edit them.",
                style: TextStyle(color: colors.textMuted, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
