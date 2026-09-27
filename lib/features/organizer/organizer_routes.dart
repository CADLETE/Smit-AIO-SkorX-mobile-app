import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../shell/workspace_shell.dart';
import 'organizer_pages.dart';
import 'ui/create_tournament_page.dart';
import 'ui/draw_schedule_pages.dart';
import 'ui/live_room_page.dart';
import 'ui/match_console_page.dart';
import 'ui/more_pages.dart';
import 'ui/org_home_page.dart';
import 'ui/org_tournaments_page.dart';
import 'ui/org_widgets.dart';
import 'ui/registrations_page.dart';
import 'ui/results_announce_pages.dart';
import 'ui/tournament_actions.dart';

/// Path segment of each organizer tab, in navigation order.
const organizerTabs = ['home', 'live', 'check-in', 'players', 'profile'];

/// Tabs from before the tournament-day redesign, so saved locations and old
/// links still land somewhere sensible.
const _renamedTabs = {'dashboard': 'home', 'matches': 'live', 'schedule': 'tournaments', 'more': 'profile'};

/// Every organiser route. Everything lives under /org/:orgId so the
/// workspace rules (membership, remembered place) apply to all of it.
List<RouteBase> organizerRoutes() {
  String org(GoRouterState s) => s.pathParameters['orgId']!;
  String tid(GoRouterState s) => s.pathParameters['tid']!;

  GoRoute tab(String name, Widget Function(String orgId) page) => GoRoute(
        path: '/org/:orgId/$name',
        pageBuilder: (_, s) => NoTransitionPage(child: page(org(s))),
      );

  /// Full screen, above the tab bar, still kept current by realtime.
  GoRoute page(String path, Widget Function(GoRouterState s) build) => GoRoute(
        path: '/org/:orgId/$path',
        builder: (_, s) => OrgRealtimeScope(orgId: org(s), child: build(s)),
      );

  return [
    for (final MapEntry(key: old, value: now) in _renamedTabs.entries)
      GoRoute(path: '/org/:orgId/$old', redirect: (_, s) => '/org/${org(s)}/$now'),
    // Organizer tabs live under /org/:orgId, and go_router's tab branches
    // cannot start on a parameterized path, so this shell works out the
    // selected tab from the location instead.
    ShellRoute(
      builder: (context, state, child) {
        final orgId = org(state);
        final tab = state.uri.pathSegments.length > 2 ? state.uri.pathSegments[2] : organizerTabs.first;
        return OrgRealtimeScope(
          orgId: orgId,
          child: WorkspaceShell(
            destinations: organizerDestinations,
            currentIndex: organizerTabs.indexOf(tab).clamp(0, organizerTabs.length - 1),
            onSelect: (index) => GoRouter.of(context).go('/org/$orgId/${organizerTabs[index]}'),
            action: OrgActionsButton(orgId: orgId),
            child: child,
          ),
        );
      },
      routes: [
        tab('home', (o) => OrgHomePage(orgId: o)),
        tab('live', (o) => OrgLiveTab(orgId: o)),
        tab('check-in', (o) => OrgCheckInTab(orgId: o)),
        tab('players', (o) => OrgPlayersTab(orgId: o)),
        tab('profile', (o) => OrganizerProfileTab(organizationId: o)),
      ],
    ),
    page('tournaments', (s) => OrgTournamentsPage(orgId: org(s))),
    page('new-tournament', (s) => CreateTournamentPage(orgId: org(s))),
    page('t/:tid', (s) => TournamentHubPage(orgId: org(s), tournamentId: tid(s))),
    page('t/:tid/registrations',
        (s) => RegistrationsPage(orgId: org(s), tournamentId: tid(s), filter: s.uri.queryParameters['filter'])),
    page('t/:tid/check-in', (s) => CheckInPage(orgId: org(s), tournamentId: tid(s))),
    page('t/:tid/draw', (s) => DrawPage(orgId: org(s), tournamentId: tid(s))),
    page('t/:tid/schedule', (s) => SchedulePage(orgId: org(s), tournamentId: tid(s))),
    page('t/:tid/courts', (s) => CourtsPage(orgId: org(s), tournamentId: tid(s))),
    page('t/:tid/results', (s) => ResultsPage(orgId: org(s), tournamentId: tid(s))),
    page('t/:tid/announce', (s) => AnnouncePage(
          orgId: org(s),
          tournamentId: tid(s),
          kind: s.uri.queryParameters['kind'],
          player: s.uri.queryParameters['player'],
        )),
    page('t/:tid/match/:mid',
        (s) => MatchConsolePage(orgId: org(s), tournamentId: tid(s), matchId: s.pathParameters['mid']!)),
    page('finance', (s) => FinancePage(orgId: org(s))),
    page('analytics', (s) => AnalyticsPage(orgId: org(s))),
    page('staff', (s) => StaffPage(orgId: org(s))),
    page('audit', (s) => AuditLogPage(orgId: org(s))),
    page('profile/public', (s) => OrgProfilePage(orgId: org(s))),
  ];
}
