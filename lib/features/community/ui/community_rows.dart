import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design/design.dart';
import '../community_controller.dart';
import '../data/community.dart';

/// My side of Community, on the Account tab (spec §28). Community itself
/// stays a main tab; these are shortcuts to what is mine.
class CommunityRows extends ConsumerWidget {
  const CommunityRows({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(myCommunityProfileProvider).value;
    final graph = ref.watch(communityGraphProvider).value ?? const CommunityGraph();
    final unread = ref.watch(unreadConversationsProvider);
    final roles = profile == null || !profile.rolesChosen ? null : profile.roles.map((r) => r.label).join(', ');
    return SxRows(
      title: 'Community',
      children: [
        SxRow(
          key: const Key('myRolesRow'),
          icon: Icons.badge_outlined,
          label: 'My roles',
          value: roles ?? 'Choose',
          onTap: () => context.push('/player/community/me'),
        ),
        SxRow(
          key: const Key('myConnectionsRow'),
          icon: Icons.people_alt_outlined,
          label: 'Connections',
          value: graph.incomingCount > 0 ? '${graph.incomingCount} new' : '${graph.connectedCount}',
          onTap: () => context.push(
              '/player/community/connections${graph.incomingCount > 0 ? '?tab=requests' : ''}'),
        ),
        SxRow(
          icon: Icons.diversity_3_outlined,
          label: 'My communities',
          value: '${graph.joinedGroups.length}',
          onTap: () => context.push('/player/community/groups'),
        ),
        SxRow(
          icon: Icons.chat_bubble_outline_rounded,
          label: 'Messages',
          value: unread > 0 ? '$unread new' : null,
          onTap: () => context.push('/player/community/messages'),
        ),
        SxRow(
          icon: Icons.bookmark_border_rounded,
          label: 'Saved',
          value: graph.saved.isEmpty ? null : '${graph.saved.length}',
          onTap: () => context.push('/player/community/saved'),
        ),
      ],
    );
  }
}
