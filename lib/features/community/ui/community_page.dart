import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design/design.dart';
import '../../../shared/format.dart';
import '../../explore/explore_modules.dart';
import '../../explore/ui/coming_soon.dart';
import '../../explore/ui/explore_cards.dart';
import '../../notifications/notifications.dart';
import '../../player/player_pages.dart';
import '../../tournaments/data/tournaments.dart';
import '../../tournaments/ui/tournament_banner.dart';
import '../community_controller.dart';
import '../data/community.dart';
import '../data/community_query.dart';
import '../data/personalize.dart';
import '../data/content.dart';
import 'community_widgets.dart';
import 'events_pages.dart';
import 'posts_pages.dart';

/// The Community tab: the people and places of pickleball, near you first
/// and ordered for what you do (docs/COMMUNITY.md §3).
class CommunityPage extends ConsumerWidget {
  const CommunityPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final roles = ref.watch(myCommunityRoles);
    final profile = ref.watch(myCommunityProfileProvider).value;
    final incoming = ref.watch(incomingRequestsProvider);
    return PlayerTabList(
      onRefresh: () async {
        ref.invalidate(communitySuggestionsProvider);
        ref.invalidate(communityGroupsProvider);
        ref.invalidate(communityPlacesProvider);
        ref.invalidate(communityGraphProvider);
        ref.invalidate(conversationsProvider);
        await ref.read(communityGraphProvider.future);
      },
      header: SxTitleBar(
        title: 'Community',
        leading: SxIconAction(
          key: const Key('communityHubBack'),
          icon: Icons.arrow_back_rounded,
          label: 'Back to Explore',
          onTap: () => context.go('/player/explore'),
        ),
        actions: [
          SxIconAction(
            key: const Key('openMessages'),
            icon: Icons.chat_bubble_outline_rounded,
            label: 'Messages',
            dot: ref.watch(unreadConversationsProvider) > 0,
            onTap: () => context.push('/player/community/messages'),
          ),
          SxIconAction(
            icon: Icons.notifications_none_rounded,
            label: 'Notifications',
            dot: ref.watch(unreadNotificationsProvider) > 0,
            onTap: () => context.push('/player/notifications'),
          ),
        ],
      ),
      children: [
        Text(hubPrompt(roles), style: SxType.body(c.inkMuted)),
        const SizedBox(height: Sx.s16),
        const _SearchEntry(),
        const SizedBox(height: Sx.s12),
        const _LocationAndCreate(),
        if (profile != null && !profile.rolesChosen) ...[const SizedBox(height: Sx.s16), const _RolesPrompt()],
        if (incoming > 0) ...[const SizedBox(height: Sx.s16), _RequestsBanner(count: incoming)],
        const SizedBox(height: Sx.section),
        SxSection('Browse', action: 'All', onAction: () => context.push('/player/community/search')),
        _SectorStrip(sectors: sectorsFor(roles)),
        const _PeopleYouMayKnow(),
        const _NearbyGroups(),
        const _PlacesNearby(),
        const _CommunityEvents(),
        const _NetworkPosts(),
        const _UpcomingEvents(),
        const _TrendingGroups(),
        const SizedBox(height: Sx.section),
        SxRows(children: [
          SxRow(
            key: const Key('openLookingFor'),
            icon: Icons.radar_rounded,
            label: 'Looking For',
            subtitle: 'Referee, scorekeeper, partner or court needed? Post it',
            onTap: () => context.push('/player/looking-for'),
          ),
        ]),
        if (upcomingCommunityModules.isNotEmpty) ...[
          const SizedBox(height: Sx.s16),
          const SxSection('Coming to Community'),
          ComingSoonList(modules: upcomingCommunityModules, onTap: (m) => showComingSoon(context, m)),
        ],
      ],
    );
  }
}

/// Later phases of Community (docs/COMMUNITY.md §7), shown so people know
/// what is coming, never faked. Empty while nothing is waiting.
const upcomingCommunityModules = <ExploreModule>[];

/// Clinics, open play and meetups: the local, non-tournament sessions.
class _CommunityEvents extends ConsumerWidget {
  const _CommunityEvents();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final city = ref.watch(communityLocationProvider).city;
    return _section(
      ref.watch(communityEventsProvider((city: city, groupId: null, placeId: null))),
      title: 'Clinics, open play & meetups',
      action: 'All',
      onAction: () => context.push('/player/community/events'),
      loadingHeight: 180,
      build: (list) => SideStrip(height: 196, children: [for (final e in list.take(8)) EventCard(event: e)]),
    );
  }
}

/// A taste of the feed; the rest is one tap away.
class _NetworkPosts extends ConsumerWidget {
  const _NetworkPosts();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final posts = ref.watch(communityFeedProvider(FeedScope.network));
    final empty = posts.hasValue && posts.value!.posts.isEmpty;
    return Padding(
      padding: const EdgeInsets.only(top: Sx.section),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SxSection('From your network', action: empty ? null : 'All', onAction: () => context.push('/player/community/posts')),
          const PostFeed(scope: FeedScope.network, limit: 2),
          if (empty)
            Text('Connect with players and follow clubs to see their news here.', style: SxType.body(c.inkMuted, size: 14)),
          const SizedBox(height: Sx.s8),
          Align(
            alignment: Alignment.centerLeft,
            child: SxButton.quiet(
              key: const Key('writePost'),
              label: 'Write a post',
              icon: Icons.edit_outlined,
              onPressed: () => showPostComposer(context, ref),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchEntry extends StatelessWidget {
  const _SearchEntry();

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Semantics(
      button: true,
      label: 'Search Community',
      excludeSemantics: true,
      child: Tappable(
        key: const Key('communitySearch'),
        onTap: () => context.push('/player/community/search'),
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: Sx.s16),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(Sx.radius),
            border: Border.all(color: c.line),
          ),
          child: Row(
            children: [
              Icon(Icons.search_rounded, color: c.inkMuted),
              const SizedBox(width: Sx.s12),
              Expanded(
                child: Text('Referees, coaches, clubs, courts…',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.body(c.inkFaint)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocationAndCreate extends ConsumerWidget {
  const _LocationAndCreate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(communityLocationProvider);
    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: SxChip(
              key: const Key('communityLocation'),
              icon: location.city == null ? Icons.public_rounded : Icons.place_rounded,
              label: location.mine ? '${location.label} · you' : location.label,
              selected: false,
              onTap: () => showLocationPicker(context, ref),
            ),
          ),
        ),
        const SizedBox(width: Sx.s8),
        SxChip(
          key: const Key('createOrJoin'),
          icon: Icons.add_rounded,
          label: 'Create / Join',
          selected: true,
          onTap: () => context.push('/player/community/groups'),
        ),
      ],
    );
  }
}

/// Anywhere, your city, or any city Community knows. No location permission.
Future<void> showLocationPicker(BuildContext context, WidgetRef ref) => showSxSheet<void>(
      context,
      builder: (ctx) {
        final c = ctx.sx;
        final current = ref.read(communityLocationProvider).city;
        final byState = <String, List<String>>{};
        for (final e in communityCities.entries) {
          byState.putIfAbsent(e.value, () => []).add(e.key);
        }
        Widget option(String? city, String label) => SxRow(
              key: Key('city-${city ?? 'anywhere'}'),
              icon: city == null ? Icons.public_rounded : Icons.place_outlined,
              label: label,
              trailing: current == city ? Icon(Icons.check_rounded, color: c.volt) : const SizedBox(width: 24),
              onTap: () {
                ref.read(communityLocationProvider.notifier).choose(city);
                Navigator.pop(ctx);
              },
            );
        return Padding(
          padding: const EdgeInsets.fromLTRB(Sx.gutter, 0, Sx.gutter, Sx.s24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Where to look', style: SxType.title(c.ink, size: 26)),
              const SizedBox(height: Sx.s4),
              Text('Pick a city. SkorX never needs your location to show Community.', style: SxType.body(c.inkMuted, size: 14)),
              const SizedBox(height: Sx.s16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SxRows(children: [option(null, 'Anywhere')]),
                      for (final e in byState.entries) ...[
                        const SizedBox(height: Sx.s16),
                        SxRows(title: e.key, children: [for (final city in e.value) option(city, city)]),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

/// First visit: what do you do in pickleball? Personalises the hub.
class _RolesPrompt extends StatelessWidget {
  const _RolesPrompt();

  @override
  Widget build(BuildContext context) {
    return SxHeroCard(
      padding: const EdgeInsets.all(Sx.s20),
      child: SxOnHero(
        child: Builder(builder: (context) {
          final c = context.sx;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('WHAT DO YOU DO IN PICKLEBALL?', style: SxType.label(c.inkMuted, size: 12)),
              const SizedBox(height: Sx.s8),
              Padding(
                padding: const EdgeInsets.only(right: 64),
                child: Text('Player, referee, coach, organiser? Pick all that fit.', style: SxType.title(c.ink, size: 24)),
              ),
              const SizedBox(height: Sx.s8),
              Text('Community shows you the people and places that matter for what you do.',
                  style: SxType.body(c.inkMuted, size: 14)),
              const SizedBox(height: Sx.s16),
              SxButton(
                key: const Key('chooseRoles'),
                label: 'Choose my roles',
                icon: Icons.badge_outlined,
                expand: false,
                height: 48,
                onPressed: () => context.push('/player/community/me'),
              ),
            ],
          );
        }),
      ),
    );
  }
}

class _RequestsBanner extends StatelessWidget {
  const _RequestsBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return SxBlock(
      semanticLabel: '$count connection requests',
      onTap: () => context.push('/player/community/connections?tab=requests'),
      child: Row(
        key: const Key('requestsBanner'),
        children: [
          SxIconTile(icon: Icons.person_add_alt_1_rounded, size: 40, colors: [c.voltFill, c.olive]),
          const SizedBox(width: Sx.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(count == 1 ? '1 person wants to connect' : '$count people want to connect',
                    style: SxType.heading(c.ink, size: 16)),
                Text('Review requests', style: SxType.caption(c.inkMuted)),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: c.inkFaint),
        ],
      ),
    );
  }
}

/// Sector cards, ordered for the member's roles.
class _SectorStrip extends StatelessWidget {
  const _SectorStrip({required this.sectors});

  final List<CommunitySector> sectors;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return SideStrip(
      height: 142,
      children: [
        for (final (i, s) in sectors.indexed)
          SizedBox(
            width: 136,
            child: Semantics(
              button: true,
              label: '${s.title}, ${s.tagline}',
              excludeSemantics: true,
              child: Tappable(
                key: Key('sector-${s.name}'),
                onTap: () => context.go('/player/community/browse/${s.name}'),
                radius: Sx.radiusLg,
                child: Container(
                  padding: const EdgeInsets.all(Sx.s12),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    gradient: c.card,
                    borderRadius: BorderRadius.circular(Sx.radiusLg),
                    border: Border.all(color: c.cardEdge),
                    boxShadow: c.cardShadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SxIconTile(icon: s.icon, size: 38, solid: i == 0, colors: sxTileColors(c, i)),
                      const Spacer(),
                      Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.heading(c.ink, size: 15.5)),
                      const SizedBox(height: 2),
                      Text(s.tagline, maxLines: 2, overflow: TextOverflow.ellipsis, style: SxType.caption(c.inkMuted, size: 12)),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A section that disappears when it has nothing to show, and shows a
/// quiet skeleton while loading.
Widget _section<T>(
  AsyncValue<List<T>> value, {
  required String title,
  String? action,
  VoidCallback? onAction,
  required Widget Function(List<T>) build,
  double loadingHeight = 160,
}) {
  return value.when(
    loading: () => Padding(
      padding: const EdgeInsets.only(top: Sx.section),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [SxSection(title), Skeleton(height: loadingHeight, radius: Sx.radiusLg)],
      ),
    ),
    error: (_, _) => const SizedBox.shrink(),
    data: (list) => list.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: Sx.section),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [SxSection(title, action: action, onAction: onAction), build(list)],
            ),
          ),
  );
}

class _PeopleYouMayKnow extends ConsumerWidget {
  const _PeopleYouMayKnow();

  @override
  Widget build(BuildContext context, WidgetRef ref) => _section(
        ref.watch(communitySuggestionsProvider),
        title: 'People you may know',
        action: 'See all',
        onAction: () => context.go('/player/community/browse/players'),
        loadingHeight: 196,
        build: (list) => SideStrip(
          height: 208,
          children: [for (final s in list) MemberCard(member: s.member, reason: s.reason)],
        ),
      );
}

class _NearbyGroups extends ConsumerWidget {
  const _NearbyGroups();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(communityLocationProvider);
    final groups = ref.watch(communityGroupsProvider(location.city)).whenData(
          (all) => [
            for (final g in all)
              if (location.city == null || g.city == location.city || (g.city == null && g.state == location.state)) g,
          ],
        );
    return _section(
      groups,
      title: location.city == null ? 'Communities' : 'Communities near you',
      action: 'All',
      onAction: () => context.push('/player/community/groups'),
      loadingHeight: 180,
      build: (list) => SideStrip(height: 196, children: [for (final g in list) GroupCard(group: g)]),
    );
  }
}

class _PlacesNearby extends ConsumerWidget {
  const _PlacesNearby();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final city = ref.watch(communityLocationProvider).city;
    final query = CommunityQuery(city: city, kinds: const {PlaceKind.club, PlaceKind.academy, PlaceKind.venue});
    return _section(
      ref.watch(communityPlacesProvider(query)).whenData((l) => l.take(4).toList()),
      title: city == null ? 'Clubs, academies & courts' : 'Places to play in $city',
      action: 'See all',
      onAction: () => context.go('/player/community/browse/places'),
      build: (list) => ListCard(children: [for (final p in list) PlaceRow(place: p)]),
    );
  }
}

/// Tournaments from SkorX TMS, not a copy: each opens the tournament hub.
class _UpcomingEvents extends ConsumerWidget {
  const _UpcomingEvents();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final city = ref.watch(communityLocationProvider).city;
    final now = DateTime.now();
    final events = ref.watch(discoverTournamentsProvider).whenData((all) {
      final upcoming = all.where((t) => t.phase(now) != TournamentPhase.completed).toList()
        ..sort((a, b) {
          final local = (b.city == city ? 1 : 0) - (a.city == city ? 1 : 0);
          return local != 0 ? local : a.start.compareTo(b.start);
        });
      return upcoming.take(6).toList();
    });
    return _section(
      events,
      title: 'Tournaments',
      action: 'All',
      onAction: () => context.go('/player/explore/tournaments'),
      loadingHeight: 200,
      build: (list) => SideStrip(height: 214, children: [for (final t in list) _EventCard(tournament: t)]),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.tournament});

  final Tournament tournament;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final t = tournament;
    final live = t.phase(DateTime.now()) == TournamentPhase.live;
    return SizedBox(
      width: 248,
      child: Semantics(
        button: true,
        label: '${t.name}, ${dateRange(t.start, t.end)}, ${t.city}${live ? ', live' : ''}',
        excludeSemantics: true,
        child: Tappable(
          key: Key('event-${t.id}'),
          onTap: () => context.push('/player/tournament/${t.id}'),
          radius: Sx.radiusLg,
          child: Container(
            decoration: BoxDecoration(
              gradient: c.card,
              borderRadius: BorderRadius.circular(Sx.radiusLg),
              border: Border.all(color: c.cardEdge),
              boxShadow: c.cardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TournamentBanner.of(
                  t,
                  height: 96,
                  radius: Sx.radiusLg,
                  child: live
                      ? const Align(alignment: Alignment.topLeft, child: Padding(padding: EdgeInsets.all(Sx.s8), child: BannerTag(text: 'LIVE', live: true)))
                      : null,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Sx.s12, Sx.s12, Sx.s12, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.heading(c.ink, size: 16)),
                      const SizedBox(height: 2),
                      Text('${dateRange(t.start, t.end)} · ${t.city}',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.caption(c.inkMuted, size: 12.5)),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Flexible(
                            child: Text(t.organizer,
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.caption(c.inkFaint, size: 12)),
                          ),
                          if (t.organizerVerified) ...[const SizedBox(width: 4), const VerifiedMark(size: 13)],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Most active this week, as a share of members, so a small busy group
/// beats a big quiet one.
class _TrendingGroups extends ConsumerWidget {
  const _TrendingGroups();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trending = ref.watch(communityGroupsProvider(null)).whenData(
          (all) => ([...all]..sort((a, b) => b.activity.compareTo(a.activity))).take(3).toList(),
        );
    return _section(
      trending,
      title: 'Active this week',
      build: (list) => ListCard(children: [for (final g in list) GroupRow(group: g)]),
    );
  }
}
