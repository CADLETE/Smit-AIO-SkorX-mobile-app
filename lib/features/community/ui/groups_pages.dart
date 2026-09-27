import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../design/design.dart';
import '../community_controller.dart';
import '../data/community.dart';
import '../data/community_query.dart';
import '../data/content.dart';
import '../data/messages.dart';
import 'community_widgets.dart';
import 'events_pages.dart';
import 'posts_pages.dart';

enum _GroupsView { near, joined, all }

/// `/player/community/groups`: find a community to join, or start one.
class GroupsPage extends ConsumerStatefulWidget {
  const GroupsPage({super.key});

  @override
  ConsumerState<GroupsPage> createState() => _GroupsPageState();
}

class _GroupsPageState extends ConsumerState<GroupsPage> {
  _GroupsView _view = _GroupsView.near;

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(communityLocationProvider);
    final graph = ref.watch(communityGraphProvider).value ?? const CommunityGraph();
    final all = ref.watch(communityGroupsProvider(null));
    return Scaffold(
      body: SafeArea(
        child: SxWidth(
          child: Column(
            children: [
              SxBackBar(onBack: () => context.canPop() ? context.pop() : context.go('/player/community')),
              SxTitleBar(
                title: 'Communities',
                actions: [
                  SxIconAction(
                    key: const Key('createGroup'),
                    icon: Icons.add_rounded,
                    label: 'Create a community',
                    onTap: () => showCreateGroup(context, ref),
                  ),
                ],
              ),
              SxTabs<_GroupsView>(
                tabs: [
                  (_GroupsView.near, location.city == null ? 'Featured' : 'Near you', null),
                  (_GroupsView.joined, 'Joined', graph.joinedGroups.length),
                  (_GroupsView.all, 'All', null),
                ],
                selected: _view,
                onSelect: (v) => setState(() => _view = v),
              ),
              Expanded(
                child: all.when(
                  loading: () => const Padding(padding: EdgeInsets.all(Sx.gutter), child: SkeletonList()),
                  error: (_, _) => ErrorBlock(message: 'Could not load communities.', onRetry: () => ref.invalidate(communityGroupsProvider)),
                  data: (groups) {
                    final list = switch (_view) {
                      _GroupsView.near => [
                          for (final g in groups)
                            if (location.city == null ||
                                g.city == location.city ||
                                (g.city == null && (g.state == null || g.state == location.state)))
                              g,
                        ],
                      _GroupsView.joined => [
                          for (final g in groups)
                            if (graph.groupStatus(g.id) != GroupStatus.none) g,
                        ],
                      _GroupsView.all => groups,
                    };
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s8, Sx.gutter, Sx.s48),
                      children: [
                        if (list.isEmpty)
                          EmptyBlock(
                            icon: Icons.diversity_3_rounded,
                            title: _view == _GroupsView.joined ? 'No communities yet' : 'Nothing here yet',
                            message: _view == _GroupsView.joined
                                ? 'Join your city\'s community to find games, partners and news.'
                                : 'Start the first community for your area.',
                            action: SxButton(
                              label: _view == _GroupsView.joined ? 'Find communities' : 'Create a community',
                              expand: false,
                              onPressed: () => _view == _GroupsView.joined
                                  ? setState(() => _view = _GroupsView.near)
                                  : showCreateGroup(context, ref),
                            ),
                          )
                        else
                          ListCard(children: [for (final g in list) GroupRow(group: g)]),
                        const SizedBox(height: Sx.s24),
                        SxBlock(
                          semanticLabel: 'Create a community',
                          onTap: () => showCreateGroup(context, ref),
                          child: Row(
                            children: [
                              const SxIconTile(icon: Icons.add_rounded, size: 40, solid: true),
                              const SizedBox(width: Sx.s12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Start a community', style: SxType.heading(context.sx.ink, size: 16)),
                                    Text('For your club night, city or crew.', style: SxType.caption(context.sx.inkMuted)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Name, what it is for, public or private, and where.
Future<void> showCreateGroup(BuildContext context, WidgetRef ref) => showSxSheet<void>(
      context,
      builder: (ctx) => const _CreateGroupSheet(),
    );

class _CreateGroupSheet extends ConsumerStatefulWidget {
  const _CreateGroupSheet();

  @override
  ConsumerState<_CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends ConsumerState<_CreateGroupSheet> {
  final _name = TextEditingController();
  final _about = TextEditingController();
  GroupAccess _access = GroupAccess.public;
  late String? _city = ref.read(communityLocationProvider).city;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _about.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final g = await ref
          .read(communityRepositoryProvider)
          .createGroup(name: _name.text, about: _about.text, access: _access, city: _city);
      ref.read(communityGraphProvider.notifier).addCreatedGroup(g.id);
      ref.invalidate(communityGroupsProvider);
      if (!mounted) return;
      Navigator.pop(context);
      context.push(groupRoute(g.id));
    } catch (e) {
      setState(() => _error = e is ApiException ? e.message : 'Could not create the community. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sx.gutter, 0, Sx.gutter, Sx.s24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Start a community', style: SxType.title(c.ink, size: 26)),
            const SizedBox(height: Sx.s16),
            TextField(
              key: const Key('groupName'),
              controller: _name,
              maxLength: 60,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Bodakdev Morning Crew'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: Sx.s8),
            TextField(
              key: const Key('groupAbout'),
              controller: _about,
              maxLength: 280,
              maxLines: 3,
              minLines: 2,
              decoration: const InputDecoration(labelText: 'What is it for?'),
            ),
            const SizedBox(height: Sx.s12),
            Text('WHO CAN JOIN', style: SxType.label(c.inkMuted)),
            const SizedBox(height: Sx.s8),
            Wrap(
              spacing: Sx.s8,
              children: [
                for (final a in [GroupAccess.public, GroupAccess.private])
                  SxChip(
                    key: Key('access-${a.name}'),
                    label: a.label,
                    icon: a == GroupAccess.public ? Icons.public_rounded : Icons.lock_rounded,
                    selected: _access == a,
                    onTap: () => setState(() => _access = a),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text('${_access.detail}. Verified communities are for verified organisations.', style: SxType.caption(c.inkMuted)),
            const SizedBox(height: Sx.s16),
            Text('WHERE', style: SxType.label(c.inkMuted)),
            const SizedBox(height: Sx.s8),
            Wrap(
              spacing: Sx.s8,
              runSpacing: Sx.s8,
              children: [
                SxChip(label: 'Online / India', selected: _city == null, onTap: () => setState(() => _city = null)),
                for (final city in communityCities.keys)
                  SxChip(label: city, selected: _city == city, onTap: () => setState(() => _city = city)),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: Sx.s12),
              Text(_error!, key: const Key('groupError'), style: SxType.body(c.live, size: 14)),
            ],
            const SizedBox(height: Sx.s20),
            SxButton(
              key: const Key('createGroupSubmit'),
              label: 'Create community',
              busy: _busy,
              onPressed: _name.text.trim().length < 3 ? null : _create,
            ),
          ],
        ),
      ),
    );
  }
}

/// `/player/community/groups/:id`
class GroupPage extends ConsumerWidget {
  const GroupPage({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = ref.watch(communityGroupProvider(groupId));
    return Scaffold(
      body: SafeArea(
        child: SxWidth(
          child: group.when(
            loading: () => const Column(children: [SxBackBar(), Expanded(child: Center(child: BallLoader()))]),
            error: (_, _) => const Column(
              children: [
                SxBackBar(),
                Expanded(
                  child: EmptyBlock(
                    icon: Icons.group_off_outlined,
                    title: 'Community not found',
                    message: 'It may have been closed.',
                  ),
                ),
              ],
            ),
            data: (g) => Column(
              children: [
                SxBackBar(
                  actions: [
                    OverflowMenu(items: [
                      ('Report', Icons.flag_outlined, () => showReportSheet(context, ref, ReportTarget.group, g.id, g.name), true),
                    ]),
                  ],
                ),
                Expanded(child: _GroupBody(group: g)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GroupBody extends ConsumerStatefulWidget {
  const _GroupBody({required this.group});

  final CommunityGroup group;

  @override
  ConsumerState<_GroupBody> createState() => _GroupBodyState();
}

class _GroupBodyState extends ConsumerState<_GroupBody> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) showCommunityError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final g = widget.group;
    final status = ref.watch(communityGraphProvider.select((x) => x.value?.groupStatus(g.id))) ?? GroupStatus.none;
    final graph = ref.read(communityGraphProvider.notifier);
    final manager = g.managedBy == null ? null : ref.watch(communityPlaceProvider(g.managedBy!)).value;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s8, Sx.gutter, Sx.s48),
      children: [
        SxHeroCard(
          padding: const EdgeInsets.all(Sx.s20),
          child: SxOnHero(
            child: Builder(builder: (context) {
              final h = context.sx;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GroupAccessMark(access: g.access),
                  const SizedBox(height: Sx.s8),
                  Padding(
                    padding: const EdgeInsets.only(right: 56),
                    child: Semantics(header: true, child: Text(g.name, style: SxType.title(h.ink, size: 30))),
                  ),
                  const SizedBox(height: Sx.s8),
                  Text('${g.placeLabel} · ${compactCount(g.members)} members', style: SxType.body(h.inkMuted, size: 14)),
                  const SizedBox(height: Sx.s16),
                  Row(
                    children: [
                      Text(compactCount(g.activeThisWeek), style: SxType.number(30, h.ink, weight: FontWeight.w800)),
                      const SizedBox(width: Sx.s8),
                      Expanded(child: Text('active this week', style: SxType.caption(h.inkMuted))),
                    ],
                  ),
                  const SizedBox(height: Sx.s8),
                  ActivityBar(group: g),
                ],
              );
            }),
          ),
        ),
        const SizedBox(height: Sx.s20),
        switch (status) {
          GroupStatus.none => SxButton(
              key: const Key('joinGroup'),
              label: g.access == GroupAccess.public ? 'Join community' : 'Ask to join',
              icon: Icons.group_add_rounded,
              busy: _busy,
              onPressed: () => _run(() async {
                final s = await graph.join(g);
                if (context.mounted && s == GroupStatus.requested) {
                  showCommunityNote(context, 'Request sent. The admins will let you in.');
                }
              }),
            ),
          GroupStatus.requested => SxButton.secondary(
              key: const Key('cancelGroupRequest'),
              label: 'Requested · Cancel',
              icon: Icons.schedule_rounded,
              busy: _busy,
              onPressed: () => _run(() => graph.leave(g.id)),
            ),
          GroupStatus.member => Row(
              children: [
                Expanded(
                  child: SxButton(
                    key: const Key('groupChat'),
                    label: 'Open chat',
                    icon: Icons.forum_rounded,
                    onPressed: () => openConversation(context, ref, ConversationKind.group, g.id),
                  ),
                ),
                const SizedBox(width: Sx.s8),
                Expanded(
                  child: SxButton.secondary(
                    key: const Key('leaveGroup'),
                    label: 'Leave',
                    icon: Icons.logout_rounded,
                    busy: _busy,
                    onPressed: () => _run(() => graph.leave(g.id)),
                  ),
                ),
              ],
            ),
        },
        DetailSection(title: 'About', child: Text(g.about, style: SxType.body(c.ink))),
        if (g.focus != null || manager != null)
          DetailSection(
            title: 'Details',
            child: ListCard(children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Sx.s8),
                child: Column(
                  children: [
                    FactLine(icon: Icons.lock_open_rounded, label: 'Access', value: g.access.detail),
                    if (g.focus != null) FactLine(icon: g.focus!.icon, label: 'For', value: g.focus!.plural),
                  ],
                ),
              ),
              if (manager != null) PlaceRow(place: manager),
            ]),
          ),
        if (g.rules.isNotEmpty)
          DetailSection(
            title: 'Rules',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, r) in g.rules.indexed)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 24, child: Text('${i + 1}', style: SxType.number(18, c.volt, weight: FontWeight.w800))),
                        Expanded(child: Text(r, style: SxType.body(c.ink, size: 14))),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        if (ref.watch(communityGraphProvider.select((x) => x.value?.admins(g.id))) ?? false) _JoinRequests(group: g),
        _GroupEvents(group: g, member: status == GroupStatus.member),
        _GroupPosts(group: g, member: status == GroupStatus.member),
      ],
    );
  }
}

/// Admins decide who gets into a private or verified community.
class _JoinRequests extends ConsumerWidget {
  const _JoinRequests({required this.group});

  final CommunityGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(groupRequestsProvider(group.id)).value ?? const [];
    if (requests.isEmpty) return const SizedBox.shrink();
    Future<void> decide(String memberId, bool approve) async {
      try {
        await ref.read(communityRepositoryProvider).decideGroupRequest(group.id, memberId, approve: approve);
        ref.invalidate(groupRequestsProvider(group.id));
        ref.invalidate(communityGroupProvider(group.id));
      } catch (e) {
        if (context.mounted) showCommunityError(context, e);
      }
    }

    return DetailSection(
      title: 'Asking to join · ${requests.length}',
      child: ListCard(children: [
        for (final m in requests)
          MemberRow(
            key: Key('joinRequest-${m.id}'),
            member: m,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: Key('declineJoin-${m.id}'),
                  tooltip: 'Decline ${m.name}',
                  icon: Icon(Icons.close_rounded, color: context.sx.inkMuted),
                  onPressed: () => decide(m.id, false),
                ),
                IconButton.filled(
                  key: Key('approveJoin-${m.id}'),
                  tooltip: 'Let ${m.name} in',
                  icon: const Icon(Icons.check_rounded),
                  onPressed: () => decide(m.id, true),
                ),
              ],
            ),
          ),
      ]),
    );
  }
}

class _GroupEvents extends ConsumerWidget {
  const _GroupEvents({required this.group, required this.member});

  final CommunityGroup group;
  final bool member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(communityEventsProvider((city: null, groupId: group.id, placeId: null))).value ?? const [];
    if (events.isEmpty && !member) return const SizedBox.shrink();
    return DetailSection(
      title: 'Events',
      action: member ? 'Host' : null,
      onAction: member ? () => context.push('/player/community/events/new?groupId=${group.id}') : null,
      child: events.isEmpty
          ? Text('No sessions planned. Host the next one.', style: SxType.body(context.sx.inkMuted, size: 14))
          : SideStrip(height: 196, children: [for (final e in events) EventCard(event: e)]),
    );
  }
}

class _GroupPosts extends ConsumerWidget {
  const _GroupPosts({required this.group, required this.member});

  final CommunityGroup group;
  final bool member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    // Private and verified communities show posts to members only.
    if (!member && group.access != GroupAccess.public) {
      return DetailSection(
        title: 'Posts',
        child: Text('Posts are visible to members.', style: SxType.body(c.inkMuted, size: 14)),
      );
    }
    final scope = FeedScope(groupId: group.id);
    return DetailSection(
      title: 'Posts',
      action: member ? 'Post' : null,
      onAction: member ? () => showPostComposer(context, ref, scope: scope, groupId: group.id, groupName: group.name) : null,
      child: PostFeed(
        scope: scope,
        empty: Text(member ? 'Be the first to post here.' : 'No posts yet.', style: SxType.body(c.inkMuted, size: 14)),
      ),
    );
  }
}
