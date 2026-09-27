import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/theme/typography.dart';
import '../../../design/design.dart' show SxHeroCard, SxHeroTag, SxContext;
import '../../../shared/format.dart';
import '../../../shared/ui/components.dart';
import '../../auth/auth_controller.dart';
import '../../player/home/player_home_page.dart' show greetingFor;
import '../../shell/workspace_shell.dart';
import '../data/organizer_repository.dart';
import '../data/tms_models.dart';
import 'org_widgets.dart';

/// Numbers for a live tournament, derived from its matches and courts.
class LiveSummary {
  LiveSummary(List<TmsMatch> matches, List<TmsCourt> courts, DateTime now)
      : total = matches.length,
        completed = matches.where((m) => m.state == MatchState.completed).length,
        board = courtBoard(courts, matches, now) {
    final live = matches.where((m) => m.state == MatchState.live || m.state == MatchState.paused).toList();
    onCourt = live.length;
    waiting = matches.where((m) => m.state == MatchState.called).length;
    delayed = matches.where((m) => m.isDelayed(now)).length;
    // The round most matches on court are in, e.g. "Quarter-final".
    final rounds = <String, int>{};
    for (final m in live) {
      rounds[m.roundLabel] = (rounds[m.roundLabel] ?? 0) + 1;
    }
    round = rounds.isEmpty ? null : (rounds.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
  }

  final int total;
  final int completed;
  final List<CourtSlot> board;
  late final int onCourt;
  late final int waiting;
  late final int delayed;
  late final String? round;

  int get remaining => total - completed;
  int get courtsLive => board.where((s) => s.status == CourtStatus.live).length;
}

/// Organiser home: what is live, what needs me, what I can do next.
class OrgHomePage extends ConsumerWidget {
  const OrgHomePage({super.key, required this.orgId});

  final String orgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.skorx.colors;
    final auth = ref.watch(authControllerProvider);
    final name = auth is SignedIn ? auth.user.firstName : '';
    final can = orgPermissions(ref, orgId);
    final tournaments = ref.watch(orgTournamentsProvider(orgId));

    Future<void> refresh() async {
      ref.invalidate(orgTournamentsProvider(orgId));
      ref.invalidate(orgOverviewProvider(orgId));
      await ref.read(orgTournamentsProvider(orgId).future);
    }

    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        padding: EdgeInsets.fromLTRB(SkorxSpace.lg, SkorxSpace.sm, SkorxSpace.lg, tabBottomPadding(context) + 80),
        children: [
          Text(
            '${greetingFor(DateTime.now())}${name.isEmpty ? '' : ', $name'}'.toUpperCase(),
            style: SkorxType.headline(32, color: colors.text),
          ),
          const SizedBox(height: SkorxSpace.xs),
          Text("Here's what's happening with your tournaments.", style: TextStyle(color: colors.textMuted)),
          const SizedBox(height: SkorxSpace.xl),
          AsyncBody<List<OrgTournament>>(
            value: tournaments,
            onRetry: () => ref.invalidate(orgTournamentsProvider(orgId)),
            loading: const Column(children: [SkeletonCard(height: 220), SizedBox(height: 12), SkeletonCard()]),
            errorMessage: "We couldn't load your tournaments. Your data is safe; try again.",
            data: (all) {
              if (all.isEmpty) {
                return SkxEmpty(
                  icon: Icons.emoji_events_rounded,
                  title: 'No tournaments yet',
                  message: 'Create your first tournament and run registrations, draws, courts and live scoring from one place.',
                  actionLabel: can.editTournaments ? 'Create tournament' : null,
                  onAction: () => context.push('/org/$orgId/new-tournament'),
                );
              }
              final live = all.where((t) => t.status == TournamentStatus.live).toList();
              final upcoming = all.where((t) => t.status.isActive && t.status != TournamentStatus.live).toList();
              final focus = live.firstOrNull ?? upcoming.firstOrNull;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final t in live) ...[
                    _LiveCommandCard(orgId: orgId, tournament: t),
                    const SizedBox(height: SkorxSpace.md),
                  ],
                  _NeedsAttention(orgId: orgId, active: [...live, ...upcoming]),
                  const SkxSectionTitle('Quick actions'),
                  QuickActionRow(actions: [
                    if (can.checkIn && focus != null)
                      QuickAction(
                        icon: Icons.qr_code_scanner_rounded,
                        label: 'Check-in',
                        onTap: () => context.push('/org/$orgId/t/${focus.id}/check-in'),
                      ),
                    if (can.score && live.isNotEmpty)
                      QuickAction(
                        icon: Icons.scoreboard_rounded,
                        label: 'Start scoring',
                        primary: true,
                        onTap: () => context.go('/org/$orgId/live'),
                      ),
                    if (live.isNotEmpty)
                      QuickAction(icon: Icons.grid_view_rounded, label: 'View live', onTap: () => context.go('/org/$orgId/live')),
                    if (can.announce && focus != null)
                      QuickAction(
                        icon: Icons.campaign_rounded,
                        label: 'Announce',
                        onTap: () => context.push('/org/$orgId/t/${focus.id}/announce'),
                      ),
                    if (can.editTournaments)
                      QuickAction(
                        icon: Icons.add_rounded,
                        label: 'New tournament',
                        primary: live.isEmpty,
                        onTap: () => context.push('/org/$orgId/new-tournament'),
                      ),
                  ].take(4).toList()),
                  _Stats(orgId: orgId, money: can.money),
                  if (upcoming.isNotEmpty) ...[
                    SkxSectionTitle('Coming up', action: 'All', onAction: () => context.push('/org/$orgId/tournaments')),
                    for (final t in upcoming.take(3)) ...[
                      TournamentCard(orgId: orgId, tournament: t),
                      const SizedBox(height: SkorxSpace.md),
                    ],
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// The live tournament at a glance, one tap from the control room.
class _LiveCommandCard extends ConsumerWidget {
  const _LiveCommandCard({required this.orgId, required this.tournament});

  final String orgId;
  final OrgTournament tournament;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.skorx.colors;
    final matches = ref.watch(tmsMatchesProvider(tournament.id)).value;
    final courts = ref.watch(courtsProvider(tournament.id)).value;
    final s = matches == null || courts == null ? null : LiveSummary(matches, courts, DateTime.now());
    const ink = Colors.white;

    Widget fact(String value, String label, [Color? color]) => Expanded(
          child: StatBlock(
              value: value, label: label, size: 28, color: color ?? ink, labelColor: Colors.white.withValues(alpha: 0.8)),
        );

    return Semantics(
      container: true,
      label: 'Live now: ${tournament.name}',
      child: SxHeroCard(
        key: const Key('liveCommandCard'),
        padding: const EdgeInsets.all(SkorxSpace.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SxHeroTag(text: 'LIVE NOW', live: true),
                const SizedBox(width: SkorxSpace.sm),
                if (s?.round != null) Flexible(child: SxHeroTag(text: s!.round!.toUpperCase())),
              ],
            ),
            const SizedBox(height: SkorxSpace.md),
            Text(tournament.name.toUpperCase(), style: SkorxType.headline(30, color: ink)),
            const SizedBox(height: SkorxSpace.lg),
            if (s == null)
              const Skeleton(height: 60)
            else ...[
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: '${s.completed}', style: SkorxType.score(44, color: colors.lime)),
                  TextSpan(text: ' / ${s.total}', style: SkorxType.score(24, color: Colors.white70)),
                  const TextSpan(text: '  matches done', style: TextStyle(color: Colors.white70, fontSize: 13)),
                ]),
              ),
              const SizedBox(height: SkorxSpace.sm),
              Container(
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(4),
                ),
                alignment: Alignment.centerLeft,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: s.total == 0 ? 0 : s.completed / s.total),
                  duration: const Duration(milliseconds: 1200),
                  curve: Curves.easeOutCubic,
                  builder: (context, v, _) => FractionallySizedBox(
                    widthFactor: v,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: context.sx.brand,
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: context.sx.glowOf(colors.lime, strength: 0.8),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: SkorxSpace.lg),
              Row(
                children: [
                  fact('${s.courtsLive}', 'Courts live'),
                  fact(
                    '${matches!.where((m) => m.state == MatchState.live || m.state == MatchState.paused).fold(0, (n, m) => n + 2 * (tournament.category(m.categoryId)?.playersPerSide ?? 1))}',
                    'Playing',
                  ),
                  fact('${s.waiting}', 'Waiting'),
                  fact('${s.delayed}', 'Delayed', s.delayed > 0 ? colors.lime : null),
                ],
              ),
            ],
            const SizedBox(height: SkorxSpace.xl),
            SkxButton(
              key: const Key('openControlRoom'),
              label: 'Open live control room',
              icon: Icons.grid_view_rounded,
              onPressed: () => context.go('/org/$orgId/live'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Attention {
  const _Attention(this.icon, this.tone, this.title, this.subtitle, this.route);

  final IconData icon;
  final SkxTone tone;
  final String title;
  final String subtitle;
  final String route;
}

/// Things only a person can resolve, most urgent first. "All clear" when none.
class _NeedsAttention extends ConsumerWidget {
  const _NeedsAttention({required this.orgId, required this.active});

  final String orgId;
  final List<OrgTournament> active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final can = orgPermissions(ref, orgId);
    final now = DateTime.now();
    final items = <_Attention>[];
    for (final t in active) {
      final base = '/org/$orgId/t/${t.id}';
      if (t.status == TournamentStatus.live) {
        final delayed = ref.watch(tmsMatchesProvider(t.id)).value?.where((m) => m.isDelayed(now)).length ?? 0;
        if (delayed > 0) {
          items.add(_Attention(Icons.schedule_rounded, SkxTone.warning, '$delayed ${delayed == 1 ? 'match' : 'matches'} delayed',
              '${t.name} · open the control room', '/org/$orgId/live'));
        }
      }
      final entries = ref.watch(entriesProvider(t.id)).value ?? const <Entry>[];
      final pending = entries.where((e) => e.approval == Approval.pending).length;
      if (pending > 0 && can.manageEntries && t.can(TmsAction.manageEntries)) {
        items.add(_Attention(Icons.how_to_reg_rounded, SkxTone.warning, '$pending ${pending == 1 ? 'registration' : 'registrations'} to approve',
            t.name, '$base/registrations?filter=pending'));
      }
      final unpaid = entries.where((e) => e.approval != Approval.rejected && e.payment == PaymentState.pending).toList();
      if (unpaid.isNotEmpty && can.money) {
        items.add(_Attention(Icons.payments_rounded, SkxTone.warning,
            '${formatInr(unpaid.fold(0, (s, e) => s + e.amount))} unpaid', '${unpaid.length} entries · ${t.name}',
            '$base/registrations?filter=unpaid'));
      }
      if (t.status == TournamentStatus.live || t.status == TournamentStatus.scheduled) {
        final expected = entries.where((e) => e.inDraw).length;
        final arrived = entries.where((e) => e.inDraw && e.attendance == Attendance.checkedIn).length;
        if (expected > arrived && can.checkIn) {
          items.add(_Attention(Icons.qr_code_scanner_rounded, SkxTone.info, '${expected - arrived} not checked in',
              '$arrived of $expected arrived · ${t.name}', '$base/check-in'));
        }
      }
      final next = TournamentLifecycle.nextStep(t.status);
      if (can.editTournaments &&
          next != null &&
          next != TmsAction.scoreMatches &&
          next != TmsAction.closeRegistration &&
          t.start.difference(now).inDays < 7) {
        items.add(_Attention(Icons.arrow_circle_right_rounded, SkxTone.info, nextStepLabel(next), '${t.name} · ${relativeDay(t.start, now)}', base));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SkxSectionTitle('Needs attention', padding: EdgeInsets.only(top: SkorxSpace.md, bottom: SkorxSpace.md)),
        if (items.isEmpty)
          const SkxEmpty(
            compact: true,
            icon: Icons.task_alt_rounded,
            title: 'All clear',
            message: 'Approvals, unpaid entries, late check-ins and delays show here.',
          )
        else
          SkxGroup(children: [
            for (final i in items.take(5))
              SkxRow(
                icon: i.icon,
                iconColor: toneColor(context, i.tone),
                label: i.title,
                subtitle: i.subtitle,
                onTap: () => context.push(i.route),
              ),
          ]),
      ],
    );
  }
}

/// The next step's button text, in the organiser's words.
String nextStepLabel(TmsAction action) => switch (action) {
      TmsAction.openRegistration => 'Publish and open registration',
      TmsAction.closeRegistration => 'Close registration',
      TmsAction.generateDraw => 'Make the draws',
      TmsAction.generateSchedule => 'Make the schedule',
      TmsAction.startTournament => 'Start the tournament',
      TmsAction.scoreMatches => 'Open live control room',
      _ => 'Continue',
    };

class _Stats extends ConsumerWidget {
  const _Stats({required this.orgId, required this.money});

  final String orgId;
  final bool money;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(orgOverviewProvider(orgId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SkxSectionTitle('At a glance'),
        AsyncBody<OrgOverview>(
          value: overview,
          onRetry: () => ref.invalidate(orgOverviewProvider(orgId)),
          loading: const SkeletonCard(height: 240),
          data: (o) => MetricGrid(children: [
            MetricCard(
              label: 'Live now',
              value: '${o.activeTournaments}',
              icon: Icons.sensors_rounded,
              tone: o.activeTournaments > 0 ? SkxTone.live : null,
            ),
            MetricCard(label: 'Upcoming', value: '${o.upcomingTournaments}', icon: Icons.event_rounded),
            MetricCard(label: 'Players', value: '${o.players}', icon: Icons.groups_rounded),
            MetricCard(
              label: 'To approve',
              value: '${o.pendingApprovals}',
              icon: Icons.how_to_reg_rounded,
              tone: o.pendingApprovals > 0 ? SkxTone.warning : null,
            ),
            MetricCard(label: "Today's matches", value: '${o.todaysMatches}', icon: Icons.sports_tennis_rounded),
            if (money)
              MetricCard(
                label: 'Collected',
                value: formatInr(o.collected, freeWhenZero: false),
                icon: Icons.account_balance_wallet_rounded,
                caption: o.outstanding > 0 ? '${formatInr(o.outstanding)} pending' : 'Nothing pending',
                onTap: () => context.push('/org/$orgId/finance'),
              ),
          ]),
        ),
      ],
    );
  }
}

/// A tournament in a list: status, dates, venue, and how full it is.
class TournamentCard extends ConsumerWidget {
  const TournamentCard({super.key, required this.orgId, required this.tournament});

  final String orgId;
  final OrgTournament tournament;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.skorx.colors;
    final t = tournament;
    final entries = ref.watch(entriesProvider(t.id)).value;
    final approved = entries?.where((e) => e.inDraw).length;
    final capacity = t.categories.fold(0, (s, c) => s + c.capacity);
    return SkxCard(
      onTap: () => context.push('/org/$orgId/t/${t.id}'),
      semanticLabel: '${t.name}, ${t.status.label}, ${dateRange(t.start, t.end)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(child: Align(alignment: Alignment.centerLeft, child: TournamentStatusPill(t.status))),
              const SizedBox(width: SkorxSpace.sm),
              Text(relativeDay(t.start, DateTime.now()), maxLines: 1, style: SkorxType.label(color: colors.textMuted, size: 12)),
            ],
          ),
          const SizedBox(height: SkorxSpace.md),
          Text(t.name.toUpperCase(), style: SkorxType.headline(24, color: colors.text, weight: FontWeight.w800)),
          const SizedBox(height: SkorxSpace.xs),
          Text(
            '${dateRange(t.start, t.end)} · ${t.venue}, ${t.city}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.textMuted, fontSize: 13),
          ),
          const SizedBox(height: SkorxSpace.md),
          ProgressLine(
            label: '${t.categories.length} ${t.categories.length == 1 ? 'category' : 'categories'} · entries',
            done: approved ?? 0,
            total: capacity,
          ),
        ],
      ),
    );
  }
}
