import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design/design.dart';
import '../../../shared/format.dart';
import '../data/looking_for.dart';
import '../looking_for_controller.dart';
import 'lf_widgets.dart';

/// My Looking For: what I posted, what I answered, who answered me, what I
/// saved, and what is done (docs/LOOKING-FOR.md §9).
class MyLookingForView extends ConsumerStatefulWidget {
  const MyLookingForView({super.key, this.initial = LfMineTab.posted});

  final LfMineTab initial;

  @override
  ConsumerState<MyLookingForView> createState() => _MyLookingForViewState();
}

class _MyLookingForViewState extends ConsumerState<MyLookingForView> {
  late LfMineTab _tab = widget.initial;

  @override
  Widget build(BuildContext context) {
    final counts = ref.watch(lfCountsProvider).value;
    return Column(
      children: [
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Sx.gutter),
            children: [
              for (final t in LfMineTab.values) ...[
                SxChip(
                  key: Key('lfMine-${t.name}'),
                  label: switch (t) {
                    LfMineTab.posted when (counts?.posted ?? 0) > 0 => '${t.label} · ${counts!.posted}',
                    LfMineTab.responses when (counts?.pendingResponses ?? 0) > 0 => '${t.label} · ${counts!.pendingResponses} new',
                    LfMineTab.interested when (counts?.interested ?? 0) > 0 => '${t.label} · ${counts!.interested}',
                    LfMineTab.saved when (counts?.saved ?? 0) > 0 => '${t.label} · ${counts!.saved}',
                    _ => t.label,
                  },
                  selected: _tab == t,
                  onTap: () => setState(() => _tab = t),
                ),
                const SizedBox(width: Sx.s8),
              ],
            ],
          ),
        ),
        Expanded(
          child: switch (_tab) {
            LfMineTab.interested => const _Interests(),
            LfMineTab.responses => const _Incoming(),
            _ => _Posts(tab: _tab),
          },
        ),
      ],
    );
  }
}

Widget _list(BuildContext context, List<Widget> children, Future<void> Function() onRefresh) => RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(Sx.gutter, Sx.s8, Sx.gutter, MediaQuery.paddingOf(context).bottom + Sx.s32),
        itemCount: children.length,
        separatorBuilder: (_, _) => const SizedBox(height: Sx.s12),
        itemBuilder: (_, i) => children[i],
      ),
    );

Widget _loading() => ListView(padding: const EdgeInsets.all(Sx.gutter), children: const [SkeletonList(rows: 3, rowHeight: 150)]);

class _Posts extends ConsumerWidget {
  const _Posts({required this.tab});

  final LfMineTab tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(lfMyPostsProvider(tab));
    return page.when(
      loading: _loading,
      error: (e, _) => ErrorBlock(message: 'Could not load your requests.', onRetry: () => ref.invalidate(lfMyPostsProvider(tab))),
      data: (p) {
        if (p.items.isEmpty) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s32, Sx.gutter, Sx.s32),
            children: [
              switch (tab) {
                LfMineTab.saved => const EmptyBlock(
                    icon: Icons.bookmark_border_rounded,
                    title: 'Nothing saved',
                    message: 'Save a request to come back to it before it fills.',
                  ),
                LfMineTab.completed => const EmptyBlock(
                    icon: Icons.task_alt_rounded,
                    title: 'Nothing completed yet',
                    message: 'Requests that fill, expire or that you cancel move here.',
                  ),
                _ => EmptyBlock(
                    icon: Icons.campaign_rounded,
                    title: 'Be the first.',
                    message: 'Need a player, referee, scorer or court?',
                    action: SxButton(
                      label: 'Post Looking For',
                      expand: false,
                      onPressed: () => context.push('/player/looking-for/new'),
                    ),
                  ),
              },
            ],
          );
        }
        return _list(context, [for (final post in p.items) LfPostCard(post: post)], () async {
          ref.invalidate(lfMyPostsProvider(tab));
          await ref.read(lfMyPostsProvider(tab).future);
        });
      },
    );
  }
}

class _Interests extends ConsumerWidget {
  const _Interests();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(lfInterestsProvider);
    return page.when(
      loading: _loading,
      error: (e, _) => ErrorBlock(message: 'Could not load your responses.', onRetry: () => ref.invalidate(lfInterestsProvider)),
      data: (p) => p.items.isEmpty
          ? ListView(
              padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s32, Sx.gutter, Sx.s32),
              children: const [
                EmptyBlock(
                  icon: Icons.front_hand_outlined,
                  title: 'No responses yet',
                  message: "Tap I'm interested on a request and it shows here, with the poster's answer.",
                ),
              ],
            )
          : _list(context, [for (final i in p.items) LfPostCard(post: i.post)], () async {
              ref.invalidate(lfInterestsProvider);
              await ref.read(lfInterestsProvider.future);
            }),
    );
  }
}

class _Incoming extends ConsumerWidget {
  const _Incoming();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final page = ref.watch(lfIncomingProvider);
    return page.when(
      loading: _loading,
      error: (e, _) => ErrorBlock(message: 'Could not load responses.', onRetry: () => ref.invalidate(lfIncomingProvider)),
      data: (p) => p.items.isEmpty
          ? ListView(
              padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s32, Sx.gutter, Sx.s32),
              children: const [
                EmptyBlock(
                  icon: Icons.inbox_outlined,
                  title: 'No one has answered yet',
                  message: 'People who respond to your requests show here.',
                ),
              ],
            )
          : _list(context, [
              for (final i in p.items)
                SxBlock(
                  key: Key('lfIncoming-${i.response.id}'),
                  onTap: () => context.push('/player/looking-for/${i.postId}/responses'),
                  child: Row(
                    children: [
                      SxAvatar(name: i.response.person?.name ?? '?', size: 40),
                      const SizedBox(width: Sx.s12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(i.response.person?.name ?? 'SkorX player', style: SxType.heading(c.ink, size: 15)),
                            Text(i.postTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.caption(c.inkMuted)),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            switch (i.response.status) {
                              LfResponseStatus.pending => 'NEW',
                              LfResponseStatus.accepted => 'ACCEPTED',
                              LfResponseStatus.declined => 'DECLINED',
                              LfResponseStatus.withdrawn => 'WITHDRAWN',
                            },
                            style: SxType.label(i.response.status == LfResponseStatus.pending ? c.info : c.inkMuted, size: 11),
                          ),
                          Text(timeAgo(i.response.respondedAt, DateTime.now()), style: SxType.caption(c.inkFaint, size: 12)),
                        ],
                      ),
                    ],
                  ),
                ),
            ], () async {
              ref.invalidate(lfIncomingProvider);
              await ref.read(lfIncomingProvider.future);
            }),
    );
  }
}
