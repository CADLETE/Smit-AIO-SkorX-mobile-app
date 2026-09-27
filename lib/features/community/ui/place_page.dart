import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design/design.dart';
import '../../../shared/format.dart';
import '../../courts/data/courts.dart';
import '../../courts/ui/venue_art.dart';
import '../../tournaments/data/tournaments.dart';
import '../../tournaments/ui/tournament_banner.dart';
import '../community_controller.dart';
import '../data/community.dart';
import '../data/messages.dart';
import '../data/content.dart';
import 'community_widgets.dart';
import 'events_pages.dart';
import 'posts_pages.dart';

/// A club, academy, venue or business. Courts, prices and reviews come from
/// the courts module and tournaments from the TMS, by id, so a club that
/// already uses SkorX never enters anything twice (docs/COMMUNITY.md §4).
class PlacePage extends ConsumerWidget {
  const PlacePage({super.key, required this.placeId});

  final String placeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final place = ref.watch(communityPlaceProvider(placeId));
    return Scaffold(
      body: SafeArea(
        child: SxWidth(
          child: place.when(
            loading: () => const Column(children: [SxBackBar(), Expanded(child: Center(child: BallLoader()))]),
            error: (_, _) => const Column(
              children: [
                SxBackBar(),
                Expanded(
                  child: EmptyBlock(
                    icon: Icons.location_off_outlined,
                    title: 'Page not found',
                    message: 'This club or venue is not on SkorX yet.',
                  ),
                ),
              ],
            ),
            data: (p) => Column(
              children: [
                SxBackBar(
                  title: p.name,
                  actions: [
                    SaveAction(targetId: p.id, type: CommunityTarget.place),
                    OverflowMenu(items: [
                      ('Report', Icons.flag_outlined, () => showReportSheet(context, ref, ReportTarget.place, p.id, p.name), true),
                    ]),
                  ],
                ),
                Expanded(child: _Body(place: p)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.place});

  final CommunityPlace place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final p = place;
    final venue = p.venueId == null ? null : ref.watch(venueProvider(p.venueId!)).value;
    final following = ref.watch(communityGraphProvider.select((g) => g.value?.follows(p.id))) ?? false;

    Future<void> toggleFollow() async {
      try {
        await ref.read(communityGraphProvider.notifier).follow(p.id, on: !following, type: CommunityTarget.place);
        if (context.mounted && !following) showCommunityNote(context, 'You will see updates from ${p.name}.');
      } catch (e) {
        if (context.mounted) showCommunityError(context, e);
      }
    }

    void message(String draft) => openConversation(context, ref, ConversationKind.place, p.id, draft: draft);

    // The one primary action depends on what the place is for.
    final primary = switch (p.kind) {
      PlaceKind.venue when p.bookable => SxButton(
          key: const Key('bookCourt'),
          label: 'Book a court',
          icon: Icons.calendar_month_rounded,
          onPressed: () => context.push('/player/venue/${p.venueId}'),
        ),
      PlaceKind.academy => SxButton(
          key: const Key('enquire'),
          label: 'Enquire about training',
          icon: Icons.school_rounded,
          onPressed: () => message('Hi, I would like to know more about training at ${p.name}.'),
        ),
      PlaceKind.club => SxButton(
          key: const Key('joinClub'),
          label: 'Ask to join',
          icon: Icons.group_add_rounded,
          onPressed: () => message('Hi, I would like to join ${p.name}. How do I become a member?'),
        ),
      _ => SxButton(
          key: const Key('contactPlace'),
          label: 'Message',
          icon: Icons.chat_bubble_outline_rounded,
          onPressed: () => message('Hi ${p.name}, '),
        ),
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s8, Sx.gutter, Sx.s48),
      children: [
        // Banner: the venue's own art when it has courts, else its mark.
        if (venue != null)
          VenueBanner(venue: venue, height: 150)
        else
          Container(
            height: 120,
            alignment: Alignment.center,
            decoration: BoxDecoration(gradient: c.hero, borderRadius: BorderRadius.circular(Sx.radiusLg)),
            child: Icon(p.kind.icon, size: 56, color: Colors.white.withValues(alpha: 0.85)),
          ),
        const SizedBox(height: Sx.s16),
        Row(
          children: [
            Text(p.kind.label.toUpperCase(), style: SxType.label(c.inkMuted)),
            if (p.verified) ...[
              const SizedBox(width: Sx.s8),
              const VerifiedMark(size: 15),
              const SizedBox(width: 4),
              Text('VERIFIED', style: SxType.label(c.isDark ? c.cyan : c.blue)),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Semantics(header: true, child: Text(p.name, style: SxType.title(c.ink, size: 32))),
        const SizedBox(height: 4),
        Text([p.placeLabel, if (p.state != null) p.state!].join(', '), style: SxType.body(c.inkMuted, size: 14)),
        const SizedBox(height: Sx.s12),
        Wrap(
          spacing: Sx.s16,
          runSpacing: Sx.s8,
          children: [
            if (venue != null) _Stat(value: venue.rating.toStringAsFixed(1), label: '${venue.reviews} reviews', icon: Icons.star_rounded),
            if (p.members > 0) _Stat(value: compactCount(p.members), label: 'members'),
            _Stat(value: compactCount(p.followers + (following ? 1 : 0)), label: 'followers'),
            if (p.founded != null) _Stat(value: '${p.founded}', label: 'founded'),
          ],
        ),
        const SizedBox(height: Sx.s16),
        Text(p.about, style: SxType.body(c.ink)),
        const SizedBox(height: Sx.s20),
        primary,
        const SizedBox(height: Sx.s8),
        Row(
          children: [
            Expanded(
              child: SxButton.secondary(
                key: const Key('followPlace'),
                label: following ? 'Following' : 'Follow',
                icon: following ? Icons.check_rounded : Icons.add_rounded,
                height: 46,
                onPressed: toggleFollow,
              ),
            ),
            if (p.kind != PlaceKind.business) ...[
              const SizedBox(width: Sx.s8),
              Expanded(
                child: SxButton.secondary(
                  key: const Key('messagePlace'),
                  label: 'Message',
                  icon: Icons.chat_bubble_outline_rounded,
                  height: 46,
                  onPressed: () => message(''),
                ),
              ),
            ],
          ],
        ),

        // The facility, from the courts module when it is on SkorX.
        if (p.courts != null || venue != null)
          DetailSection(
            title: 'Facility',
            action: p.bookable && p.kind != PlaceKind.venue ? 'Book' : null,
            onAction: p.bookable ? () => context.push('/player/venue/${p.venueId}') : null,
            child: ListCard(children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Sx.s8),
                child: Column(
                  children: [
                    if ((venue?.courts ?? p.courts) != null)
                      FactLine(icon: Icons.grid_view_rounded, label: 'Courts', value: '${venue?.courts ?? p.courts}'),
                    if (venue != null || p.setting != null)
                      FactLine(
                        icon: Icons.roofing_rounded,
                        label: 'Setting',
                        value: venue == null ? p.setting!.label : (venue.indoor ? 'Indoor' : 'Outdoor'),
                      ),
                    if ((venue?.surface ?? p.surface) != null)
                      FactLine(icon: Icons.layers_outlined, label: 'Surface', value: venue?.surface ?? p.surface!),
                    FactLine(
                      icon: Icons.schedule_rounded,
                      label: 'Hours',
                      value: venue == null
                          ? (p.hours ?? 'Ask the club')
                          : '${_hour(venue.openHour)} – ${_hour(venue.closeHour)}',
                    ),
                    if (venue != null)
                      FactLine(
                        icon: Icons.currency_rupee_rounded,
                        label: 'Court price',
                        value: '${formatInr(venue.pricePerHour)}–${formatInr(venue.peakPricePerHour)} an hour',
                      ),
                    if (venue?.address != null) FactLine(icon: Icons.place_outlined, label: 'Address', value: venue!.address!),
                  ],
                ),
              ),
            ]),
          ),
        if ((venue?.facilities ?? p.amenities).isNotEmpty)
          DetailSection(
            title: 'Amenities',
            child: Wrap(
              spacing: Sx.s8,
              runSpacing: Sx.s8,
              children: [
                for (final a in venue?.facilities ?? p.amenities)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: c.cardEdge),
                    ),
                    child: Text(a, style: SxType.caption(c.ink).copyWith(fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
          ),

        if (p.programs.isNotEmpty)
          DetailSection(
            title: p.kind == PlaceKind.academy ? 'Programs' : 'Club sessions',
            child: ListCard(children: [
              for (final prog in p.programs)
                _ProgramRow(
                  program: prog,
                  onEnquire: () => message('Hi, I am interested in "${prog.name}" (${prog.level}, ${prog.schedule}).'),
                ),
            ]),
          ),
        if (p.staffIds.isNotEmpty) _Staff(place: p),
        if (p.tournamentIds.isNotEmpty) _Tournaments(ids: p.tournamentIds),
        _PlaceEvents(place: p),
        _PlacePosts(place: p),
        DetailSection(
          title: 'Photos and reviews',
          child: Text(
            venue == null
                ? 'Photos and reviews appear here once ${p.name} adds them on SkorX.'
                : 'Rated ${venue.rating.toStringAsFixed(1)} from ${venue.reviews} reviews by players who booked on SkorX. '
                    'Photos appear here once ${p.name} adds them.',
            style: SxType.body(c.inkMuted, size: 14),
          ),
        ),
      ],
    );
  }

  static String _hour(int h) => h == 24 || h == 0 ? '12 AM' : h == 12 ? '12 PM' : h < 12 ? '$h AM' : '${h - 12} PM';
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.icon});

  final String value;
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Semantics(
      label: '$value $label',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[Icon(icon, size: 18, color: c.caution), const SizedBox(width: 3)],
          Text(value, style: SxType.number(22, c.ink, weight: FontWeight.w800)),
          const SizedBox(width: 5),
          Text(label, style: SxType.caption(c.inkMuted)),
        ],
      ),
    );
  }
}

class _ProgramRow extends StatelessWidget {
  const _ProgramRow({required this.program, required this.onEnquire});

  final Program program;
  final VoidCallback onEnquire;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final p = program;
    return Tappable(
      key: Key('program-${p.name}'),
      onTap: onEnquire,
      radius: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Sx.s12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(child: Text(p.name, style: SxType.heading(c.ink, size: 16))),
                      if (p.juniors) ...[
                        const SizedBox(width: 6),
                        Text('JUNIORS', style: SxType.label(c.info, size: 10.5, weight: FontWeight.w800)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text('${p.level} · ${p.schedule}', style: SxType.caption(c.inkMuted, size: 12.5)),
                ],
              ),
            ),
            if (p.fee != null) ...[
              const SizedBox(width: Sx.s8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(formatInr(p.fee!), style: SxType.heading(c.ink, size: 15)),
                  Text('a month', style: SxType.caption(c.inkFaint, size: 11.5)),
                ],
              ),
            ],
            const SizedBox(width: Sx.s4),
            Icon(Icons.chevron_right_rounded, color: c.inkFaint),
          ],
        ),
      ),
    );
  }
}

class _Staff extends ConsumerWidget {
  const _Staff({required this.place});

  final CommunityPlace place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final people = ref.watch(communityMembersByIdProvider(place.staffIds.join(','))).value ?? const [];
    if (people.isEmpty) return const SizedBox.shrink();
    return DetailSection(
      title: place.kind == PlaceKind.academy ? 'Coaches' : 'People',
      child: ListCard(children: [for (final m in people) MemberRow(member: m)]),
    );
  }
}

/// Tournaments from the TMS: held here, or run by them.
class _Tournaments extends ConsumerWidget {
  const _Tournaments({required this.ids});

  final List<String> ids;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final now = DateTime.now();
    final all = ref.watch(discoverTournamentsProvider).value ?? const [];
    final list = [for (final t in all) if (ids.contains(t.id)) t]..sort((a, b) => b.start.compareTo(a.start));
    if (list.isEmpty) return const SizedBox.shrink();
    return DetailSection(
      title: 'Tournaments',
      child: ListCard(children: [
        for (final t in list)
          Tappable(
            key: Key('placeTournament-${t.id}'),
            onTap: () => context.push('/player/tournament/${t.id}'),
            radius: 0,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Sx.s12),
              child: Row(
                children: [
                  SizedBox(width: 64, child: TournamentBanner.of(t, height: 44, radius: Sx.radiusSm, logo: false)),
                  const SizedBox(width: Sx.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.heading(c.ink, size: 15.5)),
                        Text(
                          '${dateRange(t.start, t.end)} · ${switch (t.phase(now)) {
                            TournamentPhase.upcoming => 'Upcoming',
                            TournamentPhase.live => 'Live now',
                            TournamentPhase.completed => 'Finished',
                          }}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SxType.caption(t.phase(now) == TournamentPhase.live ? c.live : c.inkMuted, size: 12.5),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: c.inkFaint),
                ],
              ),
            ),
          ),
      ]),
    );
  }
}

/// Clinics, open play and meetups held here. Anyone can host at a venue;
/// a club or academy's own sessions come from its staff.
class _PlaceEvents extends ConsumerWidget {
  const _PlaceEvents({required this.place});

  final CommunityPlace place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(communityEventsProvider((city: null, groupId: null, placeId: place.id))).value ?? const [];
    final open = place.kind == PlaceKind.venue;
    if (events.isEmpty && !open) return const SizedBox.shrink();
    return DetailSection(
      title: 'Events here',
      action: open ? 'Host' : null,
      onAction: open ? () => context.push('/player/community/events/new?placeId=${place.id}') : null,
      child: events.isEmpty
          ? Text('Nothing planned here yet. Host open play for your crew.', style: SxType.body(context.sx.inkMuted, size: 14))
          : SideStrip(height: 196, children: [for (final e in events) EventCard(event: e)]),
    );
  }
}

/// News from the place itself.
class _PlacePosts extends ConsumerWidget {
  const _PlacePosts({required this.place});

  final CommunityPlace place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = FeedScope(placeId: place.id);
    final posts = ref.watch(communityFeedProvider(scope)).value?.posts ?? const [];
    if (posts.isEmpty) return const SizedBox.shrink();
    return DetailSection(title: 'Updates', child: PostFeed(scope: scope, limit: 3));
  }
}
