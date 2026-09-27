import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/auth_controller.dart';
import '../../features/auth/ui/profile_setup_screen.dart';
import '../../features/auth/ui/sign_in_screen.dart';
import '../../features/auth/ui/verify_screen.dart';
import '../../features/casual_match/offline/ui/offline_ui.dart';
import '../../features/casual_match/ui/create_match_screen.dart';
import '../../features/casual_match/ui/scoring_screen.dart';
import '../../features/community/data/community.dart' show CommunitySector;
import '../../features/community/data/content.dart' show FeedScope;
import '../../features/community/ui/community_page.dart';
import '../../features/community/ui/community_search_page.dart';
import '../../features/community/ui/events_pages.dart';
import '../../features/community/ui/groups_pages.dart';
import '../../features/community/ui/member_page.dart';
import '../../features/community/ui/messages_pages.dart';
import '../../features/community/ui/my_community_pages.dart';
import '../../features/community/ui/place_page.dart';
import '../../features/community/ui/posts_pages.dart';
import '../../features/courts/ui/booking_pages.dart';
import '../../features/explore/ui/explore_hub_page.dart';
import '../../features/looking_for/ui/alerts_page.dart';
import '../../features/looking_for/ui/create_post_page.dart';
import '../../features/looking_for/ui/looking_for_home_page.dart';
import '../../features/looking_for/ui/post_detail_page.dart';
import '../../features/looking_for/ui/responses_page.dart';
import '../../features/matches/ui/match_detail_page.dart';
import '../../features/matches/ui/matches_page.dart';
import '../../features/notifications/notifications_page.dart';
import '../../features/onboarding/onboarding_controller.dart';
import '../../features/onboarding/ui/arrival_screens.dart';
import '../../features/onboarding/ui/guest_explore_page.dart';
import '../../features/onboarding/ui/onboarding_kit.dart';
import '../../features/onboarding/ui/welcome_flow.dart';
import '../../features/organizer/organizer_routes.dart';
import '../../features/paddle/my_play_pages.dart';
import '../../features/paddle/paddle_pages.dart';
import '../../features/player/home/player_home_page.dart';
import '../../features/player/data/player_repository.dart' show PlayCategory, RankScope;
import '../../features/player/player_pages.dart';
import '../../features/player/ui/player_stats_page.dart';
import '../../features/profile/profile_pages.dart';
import '../../features/subscription/data/plans.dart';
import '../../features/subscription/ui/billing_pages.dart';
import '../../features/subscription/ui/checkout_page.dart';
import '../../features/subscription/ui/pro_plans_page.dart';
import '../../features/subscription/ui/pro_result_pages.dart';
import '../../features/subscription/ui/subscription_page.dart';
import '../../features/tournaments/ui/tournament_hub_page.dart';
import '../../features/shell/workspace_shell.dart';
import '../../features/workspace/workspace_controller.dart';
import '../../shared/widgets.dart';
import '../theme/tokens.dart';
import 'redirect.dart';
import '../../features/casual_match/verification/ui/match_request_page.dart';

final routerProvider = Provider<GoRouter>((ref) {
  // Re-run redirects when sign-in or the set of workspaces changes, not on
  // every recorded location.
  final refresh = ValueNotifier<int>(0);
  ref.listen(authControllerProvider, (_, _) => refresh.value++);
  ref.listen(onboardingControllerProvider, (previous, next) {
    if (previous?.ready != next.ready) refresh.value++;
  });
  ref.listen(workspaceControllerProvider, (previous, next) {
    if (previous?.ready != next.ready || previous?.available != next.available) refresh.value++;
  });

  final router = GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) => redirectFor(
      auth: ref.read(authControllerProvider),
      onboarding: ref.read(onboardingControllerProvider),
      workspaces: ref.read(workspaceControllerProvider),
      location: state.uri.path,
    ),
    routes: [
      GoRoute(path: Routes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(path: Routes.welcome, pageBuilder: (_, state) => onboardPage(state, const WelcomeFlow())),
      GoRoute(path: Routes.guest, pageBuilder: (_, state) => onboardPage(state, const GuestExplorePage())),
      GoRoute(
        path: Routes.login,
        pageBuilder: (_, state) => onboardPage(state, const SignInScreen()),
        routes: [
          GoRoute(
            path: 'verify',
            // Opened without a number (an old link): start from the number.
            redirect: (_, state) =>
                RegExp(r'^\d{10}$').hasMatch(state.uri.queryParameters['mobile'] ?? '') ? null : Routes.login,
            pageBuilder: (_, state) => onboardPage(
              state,
              VerifyScreen(
                mobile: state.uri.queryParameters['mobile']!,
                resendAfter: Duration(seconds: int.tryParse(state.uri.queryParameters['resend'] ?? '') ?? 30),
              ),
            ),
          ),
        ],
      ),
      GoRoute(path: Routes.profileSetup, pageBuilder: (_, state) => onboardPage(state, const ProfileSetupScreen())),
      GoRoute(path: Routes.profileComplete, pageBuilder: (_, state) => onboardPage(state, const ProfileCompleteScreen())),
      GoRoute(path: Routes.welcomeBack, pageBuilder: (_, state) => onboardPage(state, const WelcomeBackScreen())),
      // Full-screen, outside the tab bar, but still in the Player workspace
      // (docs/PLAYER-APP.md §2.3).
      GoRoute(
        path: '/player/match/new',
        builder: (_, state) => CreateMatchScreen(initialCategoryId: state.uri.queryParameters['type']),
      ),
      GoRoute(path: '/player/match', builder: (_, _) => const ScoringScreen()),
      GoRoute(path: '/player/offline-matches', builder: (_, _) => const OfflineMatchesPage()),
      GoRoute(
        path: '/player/matches/:id',
        builder: (_, state) => MatchDetailPage(matchId: state.pathParameters['id']!),
      ),
      // Casual match verification: one match's confirmation (docs/CASUAL-VERIFICATION.md).
      GoRoute(path: '/player/match-requests', redirect: (_, _) => '/player/notifications?tab=requests'),
      GoRoute(
        path: '/player/match-requests/:id',
        builder: (_, state) => MatchRequestPage(matchId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/player/tournaments/mine', builder: (_, _) => const MyTournamentsPlayedPage()),
      // Any player's full stats, and two players head-to-head.
      GoRoute(
        path: '/player/players/:id',
        builder: (_, state) => PlayerStatsPage(playerId: state.pathParameters['id']!),
        routes: [
          GoRoute(
            path: 'vs/:other',
            builder: (_, state) => HeadToHeadPage(a: state.pathParameters['id']!, b: state.pathParameters['other']!),
          ),
        ],
      ),
      // My Paddle: only the signed-in player's own matches.
      GoRoute(
        path: '/player/paddle/matches',
        builder: (_, state) => MyMatchesPage(category: state.uri.queryParameters['category']),
      ),
      GoRoute(
        path: '/player/paddle/tournament/:id',
        builder: (_, state) => MyTournamentMatchesPage(tournamentId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/player/tournament/:id',
        builder: (_, state) =>
            TournamentHubPage(tournamentId: state.pathParameters['id']!, view: state.uri.queryParameters['view']),
      ),
      GoRoute(
        path: '/player/tournament/:id/registered',
        builder: (_, state) => RegisteredPage(tournamentId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/player/venue/:id',
        builder: (_, state) => VenuePage(
          venueId: state.pathParameters['id']!,
          initialDate: DateTime.tryParse(state.uri.queryParameters['date'] ?? ''),
          initialHour: int.tryParse(state.uri.queryParameters['hour'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/player/venue/:id/confirm',
        builder: (_, state) => ConfirmBookingPage.fromQuery(state.pathParameters['id']!, state.uri.queryParameters),
      ),
      GoRoute(path: '/player/bookings', builder: (_, _) => const MyBookingsPage()),
      GoRoute(
        path: '/player/rankings',
        builder: (_, state) => RankingsPage(
          scope: RankScope.values.asNameMap()[state.uri.queryParameters['scope']],
          category: PlayCategory.values.asNameMap()[state.uri.queryParameters['format']],
        ),
      ),
      GoRoute(path: '/player/achievements', builder: (_, _) => const AchievementsPage()),
      GoRoute(
        path: '/player/notifications',
        builder: (_, state) => NotificationsPage(
          initialTab: state.uri.queryParameters['tab'] == 'requests' ? NotificationsTab.requests : NotificationsTab.all,
        ),
      ),
      GoRoute(path: '/player/settings', builder: (_, _) => const SettingsPage()),
      GoRoute(path: '/player/edit-profile', builder: (_, _) => const EditProfilePage()),
      // SkorX Pro: plans, checkout, the result, managing the plan, billing.
      GoRoute(
        path: '/player/pro',
        builder: (_, state) => ProPlansPage(feature: ProFeature.fromName(state.uri.queryParameters['feature'])),
      ),
      GoRoute(
        path: '/player/pro/checkout',
        builder: (_, state) => CheckoutPage(plan: ProPlan.fromName(state.uri.queryParameters['plan']) ?? ProPlan.annual),
      ),
      GoRoute(path: '/player/pro/welcome', builder: (_, state) => ProWelcomePage(orderId: state.uri.queryParameters['order'])),
      GoRoute(
        path: '/player/pro/failed',
        builder: (_, state) => PaymentFailedPage(
          plan: ProPlan.fromName(state.uri.queryParameters['plan']) ?? ProPlan.annual,
          reason: state.uri.queryParameters['reason'],
        ),
      ),
      GoRoute(path: '/player/subscription', builder: (_, _) => const SubscriptionPage()),
      GoRoute(path: '/player/billing', builder: (_, _) => const BillingHistoryPage()),
      GoRoute(
        path: '/player/billing/:orderId',
        builder: (_, state) => InvoicePage(orderId: state.pathParameters['orderId']!),
      ),
      // Looking For (docs/LOOKING-FOR.md §9). Fixed paths before ':id'.
      GoRoute(
        path: '/player/looking-for',
        builder: (_, state) => LookingForHomePage(initialTab: state.uri.queryParameters['tab']),
      ),
      GoRoute(
        path: '/player/looking-for/new',
        builder: (_, state) => CreateLookingForPage(initialCategory: state.uri.queryParameters['category']),
      ),
      GoRoute(path: '/player/looking-for/alerts', builder: (_, _) => const LookingForAlertsPage()),
      GoRoute(path: '/player/looking-for/mine', redirect: (_, _) => '/player/looking-for?tab=mine'),
      GoRoute(
        path: '/player/looking-for/:id',
        builder: (_, state) => LookingForPostPage(postId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/player/looking-for/:id/responses',
        builder: (_, state) => LookingForResponsesPage(postId: state.pathParameters['id']!),
      ),
      // Shared links (https://skorx.in/looking-for/:id) open the request.
      GoRoute(path: '/looking-for/:id', redirect: (_, state) => '/player/looking-for/${state.pathParameters['id']}'),
      // Locations saved by earlier versions of the app.
      GoRoute(path: '/player/tournaments', redirect: (_, _) => '/player/explore/tournaments'),
      GoRoute(path: '/player/courts', redirect: (_, _) => '/player/explore/courts'),
      GoRoute(path: '/player/leaderboard', redirect: (_, _) => '/player/rankings'),
      GoRoute(path: '/player/venue/:id/review', redirect: (_, state) => state.uri.toString().replaceFirst('/review', '/confirm')),
      // Community detail screens, full screen above the tabs
      // (docs/COMMUNITY.md §3). Sector pages open inside the tab.
      GoRoute(
        path: '/player/community/search',
        builder: (_, state) => Scaffold(body: CommunitySearchPage(initialText: state.uri.queryParameters['q'] ?? '')),
      ),
      GoRoute(
        path: '/player/community/people/:id',
        builder: (_, state) => MemberPage(memberId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/player/community/places/:id',
        builder: (_, state) => PlacePage(placeId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/player/community/groups', builder: (_, _) => const GroupsPage()),
      GoRoute(
        path: '/player/community/groups/:id',
        builder: (_, state) => GroupPage(groupId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/player/community/messages',
        builder: (_, state) => MessagesPage(requests: state.uri.queryParameters['tab'] == 'requests'),
      ),
      GoRoute(
        path: '/player/community/messages/:id',
        builder: (_, state) =>
            ThreadPage(conversationId: state.pathParameters['id']!, draft: state.uri.queryParameters['draft']),
      ),
      GoRoute(path: '/player/community/me', builder: (_, _) => const MyCommunityPage()),
      GoRoute(
        path: '/player/community/connections',
        builder: (_, state) => ConnectionsPage(
          initial: ConnectionsView.values.where((v) => v.name == state.uri.queryParameters['tab']).firstOrNull ??
              ConnectionsView.connected,
        ),
      ),
      GoRoute(path: '/player/community/saved', builder: (_, _) => const SavedPage()),
      GoRoute(path: '/player/community/events', builder: (_, _) => const EventsPage()),
      GoRoute(
        path: '/player/community/events/new',
        builder: (_, state) =>
            CreateEventPage(placeId: state.uri.queryParameters['placeId'], groupId: state.uri.queryParameters['groupId']),
      ),
      GoRoute(
        path: '/player/community/events/:id',
        builder: (_, state) => EventPage(eventId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/player/community/posts', builder: (_, _) => const PostsPage()),
      GoRoute(
        path: '/player/community/posts/:id',
        builder: (_, state) => PostPage(
          postId: state.pathParameters['id']!,
          scope: FeedScope(
            groupId: state.uri.queryParameters['groupId'],
            placeId: state.uri.queryParameters['placeId'],
            authorId: state.uri.queryParameters['authorId'],
          ),
        ),
      ),
      _shell(
        playerDestinations,
        [
          _tab('/player/home', const PlayerHomePage()),
          GoRoute(
            path: '/player/matches',
            pageBuilder: (_, state) => NoTransitionPage(child: MatchesPage(view: state.uri.queryParameters['view'])),
          ),
          GoRoute(
            path: '/player/explore',
            // Old `?view=courts` links open that module.
            redirect: (_, state) =>
                state.uri.path == '/player/explore' && state.uri.queryParameters['view'] != null
                    ? '/player/explore/${state.uri.queryParameters['view']}'
                    : null,
            pageBuilder: (_, _) => const NoTransitionPage(child: ExploreHubPage()),
            routes: [
              GoRoute(
                path: ':module',
                redirect: (_, state) => exploreModuleRedirect(state.pathParameters['module']!),
                builder: (_, state) => ExploreModulePage(id: state.pathParameters['module']!),
              ),
            ],
          ),
          GoRoute(
            path: '/player/community',
            pageBuilder: (_, _) => const NoTransitionPage(child: CommunityPage()),
            routes: [
              GoRoute(
                path: 'browse/:sector',
                redirect: (_, state) =>
                    CommunitySector.byName(state.pathParameters['sector']) == null ? '/player/community' : null,
                builder: (_, state) => CommunitySearchPage(
                  key: ValueKey(state.pathParameters['sector']),
                  sector: CommunitySector.byName(state.pathParameters['sector']),
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/player/paddle',
            // Old `?tab=matches` links go to my matches.
            redirect: (_, state) => state.uri.queryParameters['tab'] == 'matches' ? '/player/paddle/matches' : null,
            pageBuilder: (_, _) => const NoTransitionPage(child: MyPaddlePage()),
          ),
          _tab('/player/profile', const ProfilePage()),
        ],
        fullBleedTabs: const {0, 1, 2, 3, 4},
        overlay: const ResumeMatchBar(),
        tour: true,
        // Community opens from its card in Explore and stays in the Explore
        // tab (docs/COMMUNITY.md §1).
        mergeIntoPrevious: const {3},
      ),
      ...organizerRoutes(),
    ],
  );

  // Remember where the user is, per workspace. Deferred so the provider is
  // never written while widgets are building.
  void record() {
    final location = router.routerDelegate.currentConfiguration.uri.path;
    scheduleMicrotask(() => ref.read(workspaceControllerProvider.notifier).recordLocation(location));
  }

  router.routerDelegate.addListener(record);
  ref.onDispose(() {
    router.routerDelegate.removeListener(record);
    router.dispose();
    refresh.dispose();
  });
  return router;
});

GoRoute _tab(String path, Widget page) => GoRoute(path: path, pageBuilder: (_, _) => NoTransitionPage(child: page));

/// One workspace's navigation shell. Each tab keeps its own stack.
StatefulShellRoute _shell(
  List<ShellDestination> destinations,
  List<GoRoute> tabs, {
  Set<int> fullBleedTabs = const {},
  Widget? overlay,
  bool tour = false,
  Set<int> mergeIntoPrevious = const {},
}) {
  // Each tab is a branch; a route in [mergeIntoPrevious] joins the branch
  // before it (a second root in the same tab).
  final branches = <List<GoRoute>>[];
  for (final (i, tab) in tabs.indexed) {
    mergeIntoPrevious.contains(i) ? branches.last.add(tab) : branches.add([tab]);
  }
  assert(branches.length == destinations.length, 'one branch per tab');
  return StatefulShellRoute.indexedStack(
    builder: (_, _, navigationShell) => WorkspaceShell.stateful(
      navigationShell: navigationShell,
      destinations: destinations,
      fullBleedTabs: fullBleedTabs,
      overlay: overlay,
      tour: tour,
    ),
    branches: [
      for (final routes in branches) StatefulShellBranch(routes: routes)
    ],
  );
}

/// Shown for the moment the session is restored. Matches the native splash
/// (logo on the dark SkorX background) so the launch reads as one piece.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: SkorxColors.dark.background,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // As large as the intro draws it, so the hand-over is seamless.
              SkorxLogo(
                height: (MediaQuery.sizeOf(context).width * 0.78).clamp(0, 380) / SkorxLogo.aspectRatio,
                glow: true,
              ),
              const SizedBox(height: 36),
              const BallLoader(color: Color(0xFFCFE524), width: 44, label: 'Opening SkorX'),
            ],
          ),
        ),
      );
}
