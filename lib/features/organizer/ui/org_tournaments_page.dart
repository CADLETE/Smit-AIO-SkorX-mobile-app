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
import 'org_home_page.dart';
import 'org_widgets.dart';

enum _View { active, drafts, past }

/// Every tournament the organisation runs, by where it is in its life.
class OrgTournamentsPage extends ConsumerStatefulWidget {
  const OrgTournamentsPage({super.key, required this.orgId});

  final String orgId;

  @override
  ConsumerState<OrgTournamentsPage> createState() => _OrgTournamentsPageState();
}

class _OrgTournamentsPageState extends ConsumerState<OrgTournamentsPage> {
  var _view = _View.active;

  @override
  Widget build(BuildContext context) {
    final orgId = widget.orgId;
    final can = orgPermissions(ref, orgId);
    final all = ref.watch(orgTournamentsProvider(orgId));
    // Every tournament, past and future: opened from Home or Profile, since
    // one tournament at a time is what the tabs are for.
    return DetailScaffold(
      title: 'Tournaments',
      fallback: '/org/$orgId/home',
      actions: [
        if (can.editTournaments)
          SkxButton(
            key: const Key('newTournament'),
            label: 'New',
            icon: Icons.add_rounded,
            height: 44,
            expand: false,
            onPressed: () => context.push('/org/$orgId/new-tournament'),
          ),
      ],
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(orgTournamentsProvider(orgId));
          await ref.read(orgTournamentsProvider(orgId).future);
        },
        child: ListView(
          padding: EdgeInsets.fromLTRB(SkorxSpace.lg, SkorxSpace.sm, SkorxSpace.lg, SkorxSpace.xxl + MediaQuery.paddingOf(context).bottom),
          children: [
            SkxSegmented<_View>(
              segments: const [(_View.active, 'Active'), (_View.drafts, 'Drafts'), (_View.past, 'Past')],
              selected: _view,
              onChanged: (v) => setState(() => _view = v),
            ),
            const SizedBox(height: SkorxSpace.lg),
            AsyncBody<List<OrgTournament>>(
              value: all,
              onRetry: () => ref.invalidate(orgTournamentsProvider(orgId)),
              loading: const Column(children: [SkeletonCard(height: 170), SizedBox(height: 12), SkeletonCard(height: 170)]),
              data: (list) {
                final shown = list.where((t) => switch (_view) {
                      _View.active => t.status.isActive,
                      _View.drafts => t.status == TournamentStatus.draft,
                      _View.past => t.status.isFinished,
                    }).toList();
                if (_view == _View.past) shown.sort((a, b) => b.start.compareTo(a.start));
                if (shown.isEmpty) {
                  return SkxEmpty(
                    icon: Icons.emoji_events_rounded,
                    title: switch (_view) {
                      _View.active => 'Nothing running',
                      _View.drafts => 'No drafts',
                      _View.past => 'No past tournaments yet',
                    },
                    message: _view == _View.past
                        ? 'Completed and cancelled tournaments are kept here with their results.'
                        : 'Create a tournament, add categories and publish when you are ready.',
                    actionLabel: _view != _View.past && can.editTournaments ? 'Create tournament' : null,
                    onAction: () => context.push('/org/$orgId/new-tournament'),
                  );
                }
                return Column(
                  children: [
                    for (final t in shown) ...[
                      TournamentCard(orgId: orgId, tournament: t),
                      const SizedBox(height: SkorxSpace.md),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// One tournament: where it is, the next step, and every tool for it.
class TournamentHubPage extends ConsumerWidget {
  const TournamentHubPage({super.key, required this.orgId, required this.tournamentId});

  final String orgId;
  final String tournamentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tournament = ref.watch(orgTournamentProvider(tournamentId));
    final name = tournament.value?.name ?? 'Tournament';
    return DetailScaffold(
      title: name,
      fallback: '/org/$orgId/tournaments',
      actions: [if (tournament.value != null) _HubMenu(orgId: orgId, tournament: tournament.value!)],
      body: AsyncBody<OrgTournament>(
        value: tournament,
        onRetry: () => ref.invalidate(orgTournamentProvider(tournamentId)),
        loading: const Padding(padding: EdgeInsets.all(SkorxSpace.lg), child: SkeletonCard(height: 260)),
        errorMessage: "We couldn't open this tournament. Check your connection and try again.",
        data: (t) => _HubBody(orgId: orgId, tournament: t),
      ),
    );
  }
}

class _HubBody extends ConsumerWidget {
  const _HubBody({required this.orgId, required this.tournament});

  final String orgId;
  final OrgTournament tournament;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.skorx.colors;
    final t = tournament;
    final can = orgPermissions(ref, orgId);
    final entries = ref.watch(entriesProvider(t.id)).value ?? const <Entry>[];
    final matches = ref.watch(tmsMatchesProvider(t.id)).value ?? const <TmsMatch>[];
    final approved = entries.where((e) => e.inDraw).length;
    final pending = entries.where((e) => e.approval == Approval.pending).length;
    final arrived = entries.where((e) => e.inDraw && e.attendance == Attendance.checkedIn).length;
    final done = matches.where((m) => m.state == MatchState.completed).length;
    final capacity = t.categories.fold(0, (s, c) => s + c.capacity);
    final base = '/org/$orgId/t/${t.id}';

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(orgTournamentProvider(t.id));
        ref.invalidate(entriesProvider(t.id));
        ref.invalidate(tmsMatchesProvider(t.id));
        await ref.read(orgTournamentProvider(t.id).future);
      },
      child: ListView(
        padding: EdgeInsets.fromLTRB(SkorxSpace.lg, SkorxSpace.sm, SkorxSpace.lg, SkorxSpace.xxl + MediaQuery.paddingOf(context).bottom),
        children: [
          Row(
            children: [
              TournamentStatusPill(t.status),
              const SizedBox(width: SkorxSpace.sm),
              Expanded(
                child: Text(
                  '${dateRange(t.start, t.end)} · ${t.venue}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.textMuted, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: SkorxSpace.lg),
          LifecycleStepper(status: t.status),
          const SizedBox(height: SkorxSpace.lg),
          _NextStepCard(orgId: orgId, tournament: t, can: can),
          const SkxSectionTitle('Overview'),
          MetricGrid(children: [
            MetricCard(
              label: 'Entries',
              value: '$approved/$capacity',
              icon: Icons.groups_rounded,
              onTap: () => context.push('$base/registrations'),
            ),
            MetricCard(
              label: 'To approve',
              value: '$pending',
              icon: Icons.how_to_reg_rounded,
              tone: pending > 0 ? SkxTone.warning : null,
              onTap: () => context.push('$base/registrations?filter=pending'),
            ),
            MetricCard(
              label: 'Checked in',
              value: '$arrived/$approved',
              icon: Icons.qr_code_scanner_rounded,
              onTap: () => context.push('$base/check-in'),
            ),
            MetricCard(
              label: 'Matches done',
              value: '$done/${matches.length}',
              icon: Icons.scoreboard_rounded,
              onTap: () => context.push('$base/results'),
            ),
          ]),
          const SkxSectionTitle('Run the tournament'),
          SkxGroup(children: [
            SkxRow(
              key: const Key('hubRegistrations'),
              icon: Icons.groups_rounded,
              label: 'Registrations',
              subtitle: '${entries.length} registered · $pending to approve',
              onTap: () => context.push('$base/registrations'),
            ),
            SkxRow(
              icon: Icons.qr_code_scanner_rounded,
              label: 'Check-in',
              subtitle: t.checkInOpen ? 'Open · $arrived of $approved arrived' : 'Closed',
              onTap: () => context.push('$base/check-in'),
            ),
            SkxRow(
              key: const Key('hubDraws'),
              icon: Icons.account_tree_rounded,
              label: 'Draws',
              subtitle: '${t.publishedDraws.length} of ${t.categories.length} published',
              onTap: () => context.push('$base/draw'),
            ),
            SkxRow(
              icon: Icons.calendar_month_rounded,
              label: 'Schedule',
              subtitle: matches.isEmpty
                  ? 'After the draws'
                  : '${matches.where((m) => m.scheduledAt != null).length} of ${matches.length} matches timed',
              onTap: () => context.push('$base/schedule'),
            ),
            SkxRow(icon: Icons.grid_on_rounded, label: 'Courts', subtitle: 'Status, breaks and moves', onTap: () => context.push('$base/courts')),
            if (t.status == TournamentStatus.live)
              SkxRow(
                icon: Icons.sensors_rounded,
                iconColor: colors.live,
                label: 'Live control room',
                subtitle: 'Every court and score',
                onTap: () => context.go('/org/$orgId/live'),
              ),
            SkxRow(icon: Icons.campaign_rounded, label: 'Announcements', subtitle: 'Message players', onTap: () => context.push('$base/announce')),
            SkxRow(icon: Icons.emoji_events_rounded, label: 'Results', subtitle: '$done matches final', onTap: () => context.push('$base/results')),
          ]),
          const SkxSectionTitle('Categories'),
          for (final c in t.categories) ...[
            _CategoryRow(category: c, approved: entries.where((e) => e.categoryId == c.id && e.inDraw).length, money: can.money),
            const SizedBox(height: SkorxSpace.sm),
          ],
          if (t.description.isNotEmpty) ...[
            const SkxSectionTitle('About'),
            Text(t.description, style: TextStyle(color: colors.textMuted, height: 1.4)),
          ],
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.category, required this.approved, required this.money});

  final OrgCategory category;
  final int approved;
  final bool money;

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    final c = category;
    return SkxCard(
      padding: const EdgeInsets.all(SkorxSpace.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 2),
                Text(
                  [c.drawFormat.label, c.rules.describe(), if (money) formatInr(c.fee)].join(' · '),
                  maxLines: 2,
                  style: TextStyle(color: colors.textMuted, fontSize: 12.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: SkorxSpace.md),
          Text('$approved/${c.capacity}', style: SkorxType.score(20, color: colors.text)),
        ],
      ),
    );
  }
}

/// Registration → Draw → Schedule → Live → Done, with the current step lit.
class LifecycleStepper extends StatelessWidget {
  const LifecycleStepper({super.key, required this.status});

  final TournamentStatus status;

  static const _steps = [
    ('Setup', TournamentStatus.draft),
    ('Entries', TournamentStatus.registrationOpen),
    ('Draw', TournamentStatus.drawGenerated),
    ('Schedule', TournamentStatus.scheduled),
    ('Live', TournamentStatus.live),
    ('Done', TournamentStatus.completed),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    final stopped = status == TournamentStatus.cancelled || status == TournamentStatus.archived;
    // Registration closed still counts as the entries step.
    final at = switch (status) {
      TournamentStatus.registrationClosed => 1,
      TournamentStatus.archived => 5,
      _ => _steps.indexWhere((s) => s.$2 == status),
    };
    return Semantics(
      label: stopped ? 'Tournament ${status.label.toLowerCase()}' : 'Step ${at + 1} of ${_steps.length}: ${_steps[at].$1}',
      excludeSemantics: true,
      child: Row(
        children: [
          for (final (i, (label, _)) in _steps.indexed) ...[
            Expanded(
              child: Column(
                children: [
                  Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: stopped
                          ? colors.surfaceInteractive
                          : i < at || status == TournamentStatus.completed
                              ? colors.lime
                              : i == at
                                  ? colors.cyan
                                  : colors.surfaceInteractive,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: i == at ? FontWeight.w800 : FontWeight.w500,
                      color: i == at && !stopped ? colors.text : colors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (i < _steps.length - 1) const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }
}

/// What to do next and one button that does it.
class _NextStepCard extends ConsumerWidget {
  const _NextStepCard({required this.orgId, required this.tournament, required this.can});

  final String orgId;
  final OrgTournament tournament;
  final OrgPermissions can;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.skorx.colors;
    final t = tournament;
    final next = TournamentLifecycle.nextStep(t.status);
    final base = '/org/$orgId/t/${t.id}';
    final repo = ref.read(organizerRepositoryProvider);

    final (String title, String body) = switch (t.status) {
      TournamentStatus.draft => ('Ready to publish?', 'Publishing lists the tournament in the SkorX app and opens registration.'),
      TournamentStatus.registrationOpen => (
          'Registration is open',
          'Closes ${relativeDay(t.registrationCloses, DateTime.now()).toLowerCase()} at ${time12(t.registrationCloses)}. Approve entries as they arrive.',
        ),
      TournamentStatus.registrationClosed => ('Make the draws', 'Seed the players, check the brackets and publish them.'),
      TournamentStatus.drawGenerated => ('Make the schedule', 'Choose courts and match length. Nobody is double-booked.'),
      TournamentStatus.scheduled => ('Ready to start', 'Starting opens live scoring on every court.'),
      TournamentStatus.live => ('Tournament is live', 'Run every court from the control room.'),
      TournamentStatus.completed => ('Tournament complete', 'Results are final and on every player profile.'),
      TournamentStatus.cancelled => ('Tournament cancelled', 'Players were told. It stays here for your records.'),
      TournamentStatus.archived => ('Archived', 'Kept for your records.'),
    };

    Future<void> go() async {
      switch (next) {
        case TmsAction.openRegistration:
          final ok = await confirmAction(
            context,
            title: 'Publish tournament?',
            message: 'Players will be able to find ${t.name} and register straight away.',
            confirm: 'Publish',
          );
          if (ok && context.mounted) {
            await runAction(context, () => repo.transition(t.id, TmsAction.openRegistration), success: 'Published. Registration is open.');
          }
        case TmsAction.closeRegistration:
          final ok = await confirmAction(
            context,
            title: 'Close registration?',
            message: 'No new entries after this. You can reopen it until the draw is made.',
            confirm: 'Close registration',
          );
          if (ok && context.mounted) {
            await runAction(context, () => repo.transition(t.id, TmsAction.closeRegistration), success: 'Registration closed.');
          }
        case TmsAction.generateDraw:
          await context.push('$base/draw');
        case TmsAction.generateSchedule:
          await context.push('$base/schedule');
        case TmsAction.startTournament:
          final ok = await confirmAction(
            context,
            title: 'Start the tournament?',
            message: 'Live scores go out to players and the public scoreboard. The draw and entries lock.',
            confirm: 'Start',
          );
          if (ok && context.mounted) {
            final started = await runAction(context, () => repo.transition(t.id, TmsAction.startTournament));
            if (started && context.mounted) context.go('/org/$orgId/live');
          }
        case TmsAction.scoreMatches:
          context.go('/org/$orgId/live');
        default:
          await context.push('$base/results');
      }
    }

    final allowed = switch (next) {
      TmsAction.generateDraw || TmsAction.generateSchedule => can.schedule || can.editTournaments,
      TmsAction.scoreMatches => true,
      null => true,
      _ => can.editTournaments,
    };

    return SkxCard(
      color: colors.surfaceElevated,
      padding: const EdgeInsets.all(SkorxSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(), style: SkorxType.headline(24, color: colors.text, weight: FontWeight.w800)),
          const SizedBox(height: SkorxSpace.sm),
          Text(body, style: TextStyle(color: colors.textMuted, height: 1.4)),
          if (allowed && (next != null || t.status == TournamentStatus.completed)) ...[
            const SizedBox(height: SkorxSpace.lg),
            SkxButton(
              key: const Key('nextStep'),
              label: next == null ? 'View results' : nextStepLabel(next),
              onPressed: go,
            ),
          ],
          if (t.status == TournamentStatus.live && can.editTournaments) ...[
            const SizedBox(height: SkorxSpace.sm),
            Center(
              child: SkxButton.ghost(
                label: 'Finish tournament',
                onPressed: () async {
                  final ok = await confirmAction(
                    context,
                    title: 'Finish the tournament?',
                    message: 'Results lock and go onto player profiles and rankings. Corrections after this are audited.',
                    confirm: 'Finish',
                  );
                  if (ok && context.mounted) {
                    await runAction(context, () => repo.transition(t.id, TmsAction.completeTournament),
                        success: 'Tournament complete.');
                  }
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HubMenu extends ConsumerWidget {
  const _HubMenu({required this.orgId, required this.tournament});

  final String orgId;
  final OrgTournament tournament;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = tournament;
    final can = orgPermissions(ref, orgId);
    final repo = ref.read(organizerRepositoryProvider);
    return PopupMenuButton<String>(
      tooltip: 'More',
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (value) async {
        switch (value) {
          case 'share':
            await Clipboard.setData(ClipboardData(text: 'https://skorx.in/t/${t.id}'));
            if (context.mounted) showSkxToast(context, 'Link copied. Share it anywhere.');
          case 'duplicate':
            await runAction(context, () async {
              final copy = await repo.duplicate(t.id);
              if (context.mounted) context.pushReplacement('/org/$orgId/t/${copy.id}');
            }, success: 'Copied as a new draft.');
          case 'cancel':
            final ok = await confirmAction(
              context,
              title: 'Cancel tournament?',
              message: 'Players will be notified and registration will close. Paid entries need refunds from Payments.',
              confirm: 'Cancel tournament',
              cancel: 'Keep tournament',
              destructive: true,
            );
            if (ok && context.mounted) {
              await runAction(context, () => repo.transition(t.id, TmsAction.cancel), success: 'Tournament cancelled.');
            }
          case 'archive':
            await runAction(context, () => repo.transition(t.id, TmsAction.archive), success: 'Archived.');
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'share', child: Text('Copy link')),
        if (can.editTournaments && t.can(TmsAction.duplicate)) const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
        if (can.editTournaments && t.can(TmsAction.archive)) const PopupMenuItem(value: 'archive', child: Text('Archive')),
        if (can.editTournaments && t.can(TmsAction.cancel)) const PopupMenuItem(value: 'cancel', child: Text('Cancel tournament')),
      ],
    );
  }
}
