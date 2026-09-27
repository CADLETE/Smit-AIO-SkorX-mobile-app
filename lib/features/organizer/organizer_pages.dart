import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.dart';
import '../../app/theme/typography.dart';
import '../../shared/format.dart';
import '../../shared/ui/components.dart';
import '../shell/workspace_shell.dart';
import '../workspace/workspace.dart';
import '../workspace/workspace_controller.dart';
import '../workspace/workspace_switcher.dart';
import 'data/organizer_repository.dart';
import 'data/tms_models.dart';
import 'ui/org_widgets.dart';

/// Tournament-day navigation (docs/ORGANIZER-TMS.md §2): what matters
/// standing beside a court, one thumb away. One tournament runs at a time,
/// so the full list lives on Home and Profile rather than taking a tab.
const organizerDestinations = [
  ShellDestination('Home', Icons.space_dashboard_outlined, Icons.space_dashboard_rounded),
  ShellDestination('Live', Icons.sensors_outlined, Icons.sensors_rounded),
  ShellDestination('Check-in', Icons.how_to_reg_outlined, Icons.how_to_reg_rounded),
  ShellDestination('Players', Icons.groups_outlined, Icons.groups_rounded),
  ShellDestination('Profile', Icons.storefront_outlined, Icons.storefront_rounded),
];

/// The organizer workspace open for [organizationId], or null when the user
/// is not a member (the router already sends them home in that case).
OrganizerWorkspace? organizerWorkspace(WidgetRef ref, String organizationId) => orgWorkspace(ref, organizationId);

/// A tool on the organiser Profile. [capability] hides it from roles that
/// cannot use it.
class OrganizerModule {
  const OrganizerModule(this.label, this.icon, this.route, [this.capability, this.subtitle]);

  final String label;
  final IconData icon;

  /// Under /org/:orgId.
  final String route;
  final String? capability;
  final String? subtitle;
}

// Tournament tools (check-in, draws, payments…) live in the top-right
// Actions sheet; these are about the organisation as a whole.
const organizerModules = [
  OrganizerModule('Finance', Icons.account_balance_wallet_rounded, 'finance', 'managePayments', 'Revenue, expenses, sponsors'),
  OrganizerModule('Analytics', Icons.query_stats_rounded, 'analytics', 'viewAnalytics', 'Attendance, completion, courts'),
  OrganizerModule('Staff & roles', Icons.badge_rounded, 'staff', 'manageSettings'),
  OrganizerModule('Activity log', Icons.history_rounded, 'audit', 'manageSettings', 'Every change, who made it'),
];

/// The Profile tab: the organisation, its record as an organiser, every
/// tool that is not needed on court, and the way back to playing.
class OrganizerProfileTab extends ConsumerWidget {
  const OrganizerProfileTab({super.key, required this.organizationId});

  final String organizationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orgId = organizationId;
    final workspace = organizerWorkspace(ref, orgId);
    final modules = organizerModules.where((m) => m.capability == null || (workspace?.can(m.capability!) ?? false)).toList();
    final profile = ref.watch(orgProfileProvider(orgId));
    final colors = context.skorx.colors;
    final name = workspace?.title ?? '';

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(orgProfileProvider(orgId));
        await ref.read(orgProfileProvider(orgId).future);
      },
      child: ListView(
        padding: EdgeInsets.fromLTRB(SkorxSpace.lg, SkorxSpace.sm, SkorxSpace.lg, tabBottomPadding(context) + 80),
        children: [
          Row(
            children: [
              PlayerAvatar(name: name, size: 64, ring: true),
              const SizedBox(width: SkorxSpace.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(name.toUpperCase(), style: SkorxType.headline(28, color: colors.text)),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: SkorxSpace.xs,
                      runSpacing: SkorxSpace.xs,
                      children: [
                        if (workspace != null) SkxPill(workspace.subtitle, icon: Icons.badge_rounded),
                        if (profile.value?.verified ?? false)
                          const SkxPill('Verified', tone: SkxTone.brand, icon: Icons.verified_rounded),
                      ],
                    ),
                    if (profile.value case final p?) ...[
                      const SizedBox(height: 4),
                      Text('${p.city} · since ${monthsShort[p.since.month - 1]} ${p.since.year}',
                          style: TextStyle(color: colors.textMuted, fontSize: 13)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SkxSectionTitle('Organiser stats'),
          AsyncBody<OrgProfile>(
            value: profile,
            onRetry: () => ref.invalidate(orgProfileProvider(orgId)),
            loading: const SkeletonCard(height: 200),
            data: (p) => MetricGrid(children: [
              MetricCard(label: 'Tournaments', value: '${p.tournaments}', icon: Icons.emoji_events_rounded, caption: '${p.completed} completed'),
              MetricCard(label: 'Players hosted', value: '${p.playersHosted}', icon: Icons.groups_rounded, caption: '${p.repeatPlayerPercent}% come back'),
              MetricCard(label: 'Matches run', value: '${p.matchesManaged}', icon: Icons.scoreboard_rounded),
              MetricCard(label: 'Rating', value: p.averageRating.toStringAsFixed(1), icon: Icons.star_rounded, caption: '${p.reviews.length} recent reviews'),
            ]),
          ),
          const SizedBox(height: SkorxSpace.md),
          SkxGroup(children: [
            SkxRow(
              key: const Key('publicProfile'),
              icon: Icons.storefront_rounded,
              iconColor: context.skorx.highlight,
              label: 'Public profile',
              subtitle: 'Venues, contact and reviews, as players see them',
              onTap: () => context.push('/org/$orgId/profile/public'),
            ),
          ]),
          SkxGroup(title: 'Organisation', children: [
            SkxRow(
              icon: Icons.emoji_events_rounded,
              iconColor: context.skorx.highlight,
              label: 'All tournaments',
              subtitle: 'Active, drafts and past',
              onTap: () => context.push('/org/$orgId/tournaments'),
            ),
            for (final m in modules)
              SkxRow(
                icon: m.icon,
                iconColor: context.skorx.highlight,
                label: m.label,
                subtitle: m.subtitle,
                onTap: () => context.push('/org/$orgId/${m.route}'),
              ),
          ]),
          const _ModeGroup(),
          const SizedBox(height: SkorxSpace.lg),
          Text(
            'Streaming, certificates and integrations are managed on the SkorX web dashboard.',
            style: TextStyle(color: colors.textMuted, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

/// Organiser ⇄ Player, kept out of the top bar because organisers rarely
/// switch mid-tournament. The same account either way.
class _ModeGroup extends ConsumerWidget {
  const _ModeGroup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workspaceControllerProvider);
    final organisations = state.available.whereType<OrganizerWorkspace>().length;
    return SkxGroup(title: 'Mode', children: [
      SkxRow(
        key: const Key('switchToPlayer'),
        icon: Icons.sports_tennis_rounded,
        iconColor: context.skorx.colors.cyan,
        label: 'Switch to Player',
        subtitle: 'Your matches, stats and courts',
        onTap: () => switchWorkspace(context, const PlayerWorkspace()),
      ),
      if (organisations > 1)
        SkxRow(
          key: const Key('switchOrganisation'),
          icon: Icons.swap_horiz_rounded,
          label: 'Switch organisation',
          subtitle: '$organisations organisations',
          onTap: () => showWorkspaceSwitcher(context),
        ),
    ]);
  }
}
