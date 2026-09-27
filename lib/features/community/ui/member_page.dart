import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design/design.dart';
import '../community_controller.dart';
import '../data/community.dart';
import '../data/content.dart';
import '../data/messages.dart';
import 'community_widgets.dart';

/// A person's Community profile: who they are, each role with its evidence,
/// and how to reach them. Players link to their SkorX stats rather than
/// repeating them (docs/COMMUNITY.md §4).
class MemberPage extends ConsumerWidget {
  const MemberPage({super.key, required this.memberId});

  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final member = ref.watch(communityMemberProvider(memberId));
    final blocked = ref.watch(communityGraphProvider.select((g) => g.value?.hasBlocked(memberId))) ?? false;
    return Scaffold(
      body: SafeArea(
        child: SxWidth(
          child: member.when(
            loading: () => const Column(children: [SxBackBar(), Expanded(child: Center(child: BallLoader()))]),
            error: (e, _) => Column(
              children: [
                const SxBackBar(),
                Expanded(
                  child: EmptyBlock(
                    icon: Icons.person_off_outlined,
                    title: 'Profile not found',
                    message: 'This profile is not on SkorX, or is hidden.',
                  ),
                ),
              ],
            ),
            data: (m) => Column(
              children: [
                SxBackBar(
                  actions: [
                    if (!blocked) SaveAction(targetId: m.id, type: CommunityTarget.member),
                    OverflowMenu(items: [
                      if (blocked)
                        ('Unblock', Icons.lock_open_rounded, () => _unblock(context, ref, m), false)
                      else
                        ('Block', Icons.block_rounded, () => confirmBlock(context, ref, m), true),
                      ('Report', Icons.flag_outlined, () => showReportSheet(context, ref, ReportTarget.member, m.id, m.name), true),
                    ]),
                  ],
                ),
                Expanded(child: blocked ? _Blocked(member: m) : _Profile(member: m)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Future<void> _unblock(BuildContext context, WidgetRef ref, CommunityMember m) async {
    try {
      await ref.read(communityGraphProvider.notifier).block(m.id, on: false);
      if (context.mounted) showCommunityNote(context, '${m.name.split(' ').first} is unblocked.');
    } catch (e) {
      if (context.mounted) showCommunityError(context, e);
    }
  }
}

class _Blocked extends ConsumerWidget {
  const _Blocked({required this.member});

  final CommunityMember member;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListView(
        padding: const EdgeInsets.all(Sx.gutter),
        children: [
          EmptyBlock(
            key: const Key('blockedProfile'),
            icon: Icons.block_rounded,
            title: 'You blocked ${member.name.split(' ').first}',
            message: 'They cannot find you, connect or message you.',
            action: SxButton.secondary(
              key: const Key('unblock'),
              label: 'Unblock',
              expand: false,
              onPressed: () => MemberPage._unblock(context, ref, member),
            ),
          ),
        ],
      );
}

class _Profile extends ConsumerWidget {
  const _Profile({required this.member});

  final CommunityMember member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final m = member;
    final now = DateTime.now();
    final following = ref.watch(communityGraphProvider.select((g) => g.value?.follows(m.id))) ?? false;
    final work = [for (final r in m.roles) if (r.role != CommunityRole.player) r];
    final playing = m.record(CommunityRole.player);
    final canRate = ref.watch(isOrganiserProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s8, Sx.gutter, Sx.s48),
      children: [
        // Who.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SxAvatar(name: m.name, size: 84, ring: m.verified),
            const SizedBox(width: Sx.s16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Semantics(
                          header: true,
                          child: Text(m.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: SxType.title(c.ink, size: 30)),
                        ),
                      ),
                      if (m.verified) ...[const SizedBox(width: 6), const VerifiedMark(size: 20)],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(m.placeLabel, style: SxType.body(c.inkMuted, size: 14)),
                  if (m.availability != null) ...[const SizedBox(height: 6), AvailabilityMark(m.availability!)],
                ],
              ),
            ),
          ],
        ),
        if (m.headline != null) ...[
          const SizedBox(height: Sx.s16),
          Text(m.headline!, style: SxType.body(c.ink)),
        ],
        const SizedBox(height: Sx.s12),
        Wrap(
          spacing: Sx.s8,
          runSpacing: Sx.s8,
          children: [for (final r in m.roles) RoleBadge(role: r.role, verified: r.verified)],
        ),
        if (m.mutualConnections > 0) ...[
          const SizedBox(height: Sx.s12),
          Row(
            children: [
              Icon(Icons.people_alt_outlined, size: 16, color: c.inkMuted),
              const SizedBox(width: 6),
              Text(
                m.mutualConnections == 1 ? '1 mutual connection' : '${m.mutualConnections} mutual connections',
                style: SxType.caption(c.inkMuted),
              ),
            ],
          ),
        ],

        // Reach them.
        const SizedBox(height: Sx.s20),
        Row(
          children: [
            Expanded(child: ConnectButton(member: m)),
            const SizedBox(width: Sx.s8),
            Expanded(
              child: SxButton.secondary(
                key: const Key('messageMember'),
                label: 'Message',
                icon: Icons.chat_bubble_outline_rounded,
                height: 48,
                onPressed: () => openConversation(context, ref, ConversationKind.direct, m.id),
              ),
            ),
          ],
        ),
        const SizedBox(height: Sx.s4),
        Row(
          children: [
            SxButton.quiet(
              key: const Key('followMember'),
              label: following ? 'Following' : 'Follow',
              icon: following ? Icons.notifications_active_rounded : Icons.notifications_none_rounded,
              onPressed: () async {
                try {
                  await ref.read(communityGraphProvider.notifier).follow(m.id, on: !following);
                } catch (e) {
                  if (context.mounted) showCommunityError(context, e);
                }
              },
            ),
            const Spacer(),
            Flexible(
              flex: 3,
              child: Text(
                'Contact details stay private. Talk on SkorX.',
                textAlign: TextAlign.end,
                style: SxType.caption(c.inkFaint, size: 12),
              ),
            ),
          ],
        ),

        // Their game, from SkorX, not retyped.
        if (playing != null) _PlayerBlock(member: m, record: playing),

        // Each professional role with its evidence.
        for (final r in work)
          _RoleBlock(
            record: r,
            years: r.yearsIn(now),
            onRate: canRate && feedbackRoles.contains(r.role) ? () => showFeedbackSheet(context, ref, m, r.role) : null,
          ),

        // About.
        DetailSection(
          title: 'About',
          child: ListCard(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Sx.s8),
                child: Column(
                  children: [
                    if (m.bio != null) FactLine(icon: Icons.notes_rounded, label: 'Bio', value: m.bio!),
                    if (m.languages.isNotEmpty)
                      FactLine(icon: Icons.translate_rounded, label: 'Languages', value: m.languages.join(', ')),
                    if (m.serviceArea.isNotEmpty)
                      FactLine(icon: Icons.map_outlined, label: 'Works in', value: m.serviceArea.join(', ')),
                    if (m.availability != null)
                      FactLine(icon: Icons.event_available_outlined, label: 'Availability', value: m.availability!.detail),
                    FactLine(icon: Icons.place_outlined, label: 'Based in', value: m.placeLabel),
                  ],
                ),
              ),
            ],
          ),
        ),

        if (m.placeIds.isNotEmpty) _Affiliations(ids: m.placeIds),
        if (m.groupIds.isNotEmpty) _Groups(ids: m.groupIds),
      ],
    );
  }
}

class _PlayerBlock extends StatelessWidget {
  const _PlayerBlock({required this.member, required this.record});

  final CommunityMember member;
  final RoleRecord record;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final m = member;
    return DetailSection(
      title: 'On court',
      action: m.playerId == null ? null : 'Full stats',
      onAction: m.playerId == null ? null : () => context.push('/player/players/${m.playerId}'),
      child: SxBlock(
        semanticLabel: m.playerId == null ? null : 'Open ${m.name}\'s SkorX stats',
        onTap: m.playerId == null ? null : () => context.push('/player/players/${m.playerId}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: Sx.s8,
              runSpacing: Sx.s8,
              children: [
                if (m.level != null) _Tag(m.level!),
                for (final t in m.tags) _Tag(t),
              ],
            ),
            if (record.metrics.isNotEmpty) ...[
              const SizedBox(height: Sx.s12),
              MetricGrid(metrics: record.metrics),
            ],
            if (m.playerId != null) ...[
              const SizedBox(height: Sx.s12),
              Row(
                children: [
                  Expanded(
                    child: Text('SkorX ID ${m.playerId}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.caption(c.inkFaint, size: 12)),
                  ),
                  Text('View stats', style: SxType.caption(c.inkMuted, size: 12.5)),
                  Icon(Icons.chevron_right_rounded, size: 18, color: c.inkFaint),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: SxType.caption(c.ink, size: 12.5).copyWith(fontWeight: FontWeight.w600)),
    );
  }
}

/// One role: verified or not, how long, the numbers and the portfolio.
class _RoleBlock extends StatelessWidget {
  const _RoleBlock({required this.record, required this.years, this.onRate});

  final RoleRecord record;
  final int? years;

  /// Organisers rate officials, media and coaches they worked with.
  final VoidCallback? onRate;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final r = record;
    return DetailSection(
      title: r.role.label,
      child: SxBlock(
        child: Column(
          key: Key('role-${r.role.name}'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (r.verified) ...[
                  const VerifiedMark(size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('Verified by SkorX',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SxType.caption(c.isDark ? c.cyan : c.blue).copyWith(fontWeight: FontWeight.w700)),
                  ),
                ] else
                  Expanded(
                    child: Text('Not verified yet',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.caption(c.inkFaint)),
                  ),
                const SizedBox(width: Sx.s8),
                if (years != null)
                  Text(years == 0 ? 'New this year' : years == 1 ? '1 year' : '$years years',
                      style: SxType.caption(c.inkMuted).copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
            if (r.metrics.isNotEmpty) ...[const SizedBox(height: Sx.s12), MetricGrid(metrics: r.metrics)],
            if (r.highlights.isNotEmpty) ...[
              const SizedBox(height: Sx.s12),
              for (final h in r.highlights)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Icon(Icons.workspace_premium_outlined, size: 15, color: c.volt),
                      ),
                      const SizedBox(width: Sx.s8),
                      Expanded(child: Text(h, style: SxType.body(c.ink, size: 14))),
                    ],
                  ),
                ),
            ],
            if (onRate != null) ...[
              const SizedBox(height: Sx.s8),
              Align(
                alignment: Alignment.centerLeft,
                child: SxButton.quiet(
                  key: Key('rate-${r.role.name}'),
                  label: 'Rate their work',
                  icon: Icons.rate_review_outlined,
                  onPressed: onRate,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// An organiser's word on someone who worked their event: would you book
/// them again, and were they on time. Adds to their role reputation.
Future<void> showFeedbackSheet(BuildContext context, WidgetRef ref, CommunityMember m, CommunityRole role) => showSxSheet<void>(
      context,
      builder: (ctx) => _FeedbackSheet(member: m, role: role),
    );

class _FeedbackSheet extends ConsumerStatefulWidget {
  const _FeedbackSheet({required this.member, required this.role});

  final CommunityMember member;
  final CommunityRole role;

  @override
  ConsumerState<_FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends ConsumerState<_FeedbackSheet> {
  bool? _recommend;
  bool? _onTime;
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      await ref.read(communityRepositoryProvider).feedback(
            memberId: widget.member.id,
            role: widget.role,
            recommend: _recommend!,
            onTime: _onTime,
            note: _note.text,
          );
      ref.invalidate(communityMemberProvider(widget.member.id));
      if (mounted) {
        Navigator.pop(context);
        showCommunityNote(context, 'Thanks. Your feedback now counts on their profile.');
      }
    } catch (e) {
      if (mounted) showCommunityError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final first = widget.member.name.split(' ').first;
    Widget yesNo(String key, bool? value, ValueChanged<bool> pick) => Row(
          children: [
            SxChip(key: Key('$key-yes'), label: 'Yes', icon: Icons.thumb_up_alt_outlined, selected: value == true, onTap: () => setState(() => pick(true))),
            const SizedBox(width: Sx.s8),
            SxChip(key: Key('$key-no'), label: 'No', icon: Icons.thumb_down_alt_outlined, selected: value == false, onTap: () => setState(() => pick(false))),
          ],
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sx.gutter, 0, Sx.gutter, Sx.s24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('$first as ${widget.role.label.toLowerCase()}', style: SxType.title(c.ink, size: 26)),
            const SizedBox(height: Sx.s4),
            Text('For organisers who worked with them. Shown as a share of positive feedback, never as stars.',
                style: SxType.body(c.inkMuted, size: 14)),
            const SizedBox(height: Sx.s20),
            Text('Would you book $first again?', style: SxType.heading(c.ink, size: 16)),
            const SizedBox(height: Sx.s8),
            yesNo('recommend', _recommend, (v) => _recommend = v),
            const SizedBox(height: Sx.s16),
            Text('Were they on time?', style: SxType.heading(c.ink, size: 16)),
            const SizedBox(height: Sx.s8),
            yesNo('onTime', _onTime, (v) => _onTime = v),
            const SizedBox(height: Sx.s16),
            TextField(
              controller: _note,
              maxLength: 300,
              maxLines: 3,
              minLines: 2,
              decoration: const InputDecoration(labelText: 'Note for SkorX (optional, not shown publicly)'),
            ),
            const SizedBox(height: Sx.s12),
            SxButton(
              key: const Key('submitFeedback'),
              label: 'Send feedback',
              busy: _busy,
              onPressed: _recommend == null ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

class _Affiliations extends ConsumerWidget {
  const _Affiliations({required this.ids});

  final List<String> ids;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final places = ref.watch(communityPlacesByIdProvider(ids.join(','))).value ?? const [];
    if (places.isEmpty) return const SizedBox.shrink();
    return DetailSection(
      title: 'Clubs and academies',
      child: ListCard(children: [for (final p in places) PlaceRow(place: p)]),
    );
  }
}

class _Groups extends ConsumerWidget {
  const _Groups({required this.ids});

  final List<String> ids;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = [
      for (final id in ids) ?ref.watch(communityGroupProvider(id)).value,
    ];
    if (groups.isEmpty) return const SizedBox.shrink();
    return DetailSection(
      title: 'Communities',
      child: ListCard(children: [for (final g in groups) GroupRow(group: g)]),
    );
  }
}
