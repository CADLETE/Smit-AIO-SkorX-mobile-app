import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design/design.dart';
import '../../../shared/format.dart';
import '../community_controller.dart';
import '../data/community.dart';
import '../data/content.dart';
import 'community_widgets.dart';

/// The post, read from the feed it was opened from.
String postRoute(String id, [FeedScope scope = FeedScope.network]) {
  final q = scope.toParams();
  return Uri(path: '/player/community/posts/$id', queryParameters: q.isEmpty ? null : q).toString();
}

/// What a post links to on SkorX, in words.
String _linkLabel(String link) => switch (link.split('/').elementAtOrNull(2)) {
      'tournament' => 'View tournament',
      'matches' => 'View match',
      'venue' => 'View courts',
      'community' => 'Open in Community',
      _ => 'Open',
    };

/// One post: who, what kind, the words, what it links to, and reactions.
class PostCard extends ConsumerWidget {
  const PostCard({super.key, required this.post, required this.scope, this.open = true});

  final CommunityPost post;

  /// The feed it sits in, so likes update that list.
  final FeedScope scope;

  /// Tapping opens the post and its comments.
  final bool open;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final p = post;
    final byline = [
      if (p.placeName != null) 'as ${p.placeName}',
      if (p.groupName != null) 'in ${p.groupName}',
      timeAgo(p.at, DateTime.now()),
    ].join(' · ');
    return Semantics(
      container: true,
      child: Tappable(
        key: Key('post-${p.id}'),
        onTap: open ? () => context.push(postRoute(p.id, scope)) : null,
        radius: Sx.radiusLg,
        child: Container(
          padding: const EdgeInsets.all(Sx.s16),
          decoration: BoxDecoration(
            gradient: c.card,
            borderRadius: BorderRadius.circular(Sx.radiusLg),
            border: Border.all(color: p.hidden ? c.caution.withValues(alpha: 0.6) : c.cardEdge),
            boxShadow: c.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Tappable(
                    onTap: p.mine ? null : () => context.push(memberRoute(p.authorId)),
                    radius: 20,
                    child: SxAvatar(name: p.authorName, size: 38),
                  ),
                  const SizedBox(width: Sx.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.mine ? 'You' : p.authorName, maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.heading(c.ink, size: 15)),
                        Text(byline, maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.caption(c.inkFaint, size: 12)),
                      ],
                    ),
                  ),
                  const SizedBox(width: Sx.s8),
                  Icon(p.kind.icon, size: 15, color: c.inkMuted),
                  const SizedBox(width: 4),
                  Text(p.kind.label.toUpperCase(), style: SxType.label(c.inkMuted, size: 10.5)),
                ],
              ),
              if (p.hidden) ...[
                const SizedBox(height: Sx.s8),
                Text('Hidden while SkorX reviews reports. Only you can see it.',
                    key: const Key('postHidden'), style: SxType.caption(c.caution)),
              ],
              const SizedBox(height: Sx.s12),
              Text(p.body, style: SxType.body(c.ink)),
              if (p.link != null || p.eventId != null) ...[
                const SizedBox(height: Sx.s12),
                Wrap(
                  spacing: Sx.s8,
                  runSpacing: Sx.s8,
                  children: [
                    if (p.eventId != null)
                      _LinkChip(
                        icon: Icons.event_rounded,
                        label: p.eventTitle ?? 'View event',
                        onTap: () => context.push('/player/community/events/${p.eventId}'),
                      ),
                    if (p.link != null)
                      _LinkChip(icon: Icons.arrow_outward_rounded, label: _linkLabel(p.link!), onTap: () => context.push(p.link!)),
                  ],
                ),
              ],
              const SizedBox(height: Sx.s12),
              Row(
                children: [
                  _Reaction(
                    key: Key('like-${p.id}'),
                    icon: p.likedByMe ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    color: p.likedByMe ? c.live : c.inkMuted,
                    label: '${p.likes}',
                    semantic: p.likedByMe ? 'Unlike, ${p.likes} likes' : 'Like, ${p.likes} likes',
                    onTap: () async {
                      HapticFeedback.selectionClick();
                      try {
                        await ref.read(communityFeedProvider(scope).notifier).like(p);
                      } catch (e) {
                        if (context.mounted) showCommunityError(context, e);
                      }
                    },
                  ),
                  const SizedBox(width: Sx.s16),
                  _Reaction(
                    icon: Icons.chat_bubble_outline_rounded,
                    color: c.inkMuted,
                    label: '${p.comments}',
                    semantic: '${p.comments} comments',
                    onTap: open ? () => context.push(postRoute(p.id, scope)) : null,
                  ),
                  const Spacer(),
                  SxIconAction(
                    key: Key('postMenu-${p.id}'),
                    icon: Icons.more_horiz_rounded,
                    label: 'More',
                    onTap: () => showSxSheet<void>(
                      context,
                      builder: (ctx) => Padding(
                        padding: const EdgeInsets.fromLTRB(Sx.gutter, 0, Sx.gutter, Sx.s24),
                        child: SxRows(children: [
                          if (p.mine)
                            SxRow(
                              key: const Key('deletePost'),
                              icon: Icons.delete_outline_rounded,
                              label: 'Delete post',
                              danger: true,
                              onTap: () async {
                                Navigator.pop(ctx);
                                try {
                                  await ref.read(communityFeedProvider(scope).notifier).delete(p.id);
                                  if (context.mounted) showCommunityNote(context, 'Post deleted.');
                                } catch (e) {
                                  if (context.mounted) showCommunityError(context, e);
                                }
                              },
                            )
                          else
                            SxRow(
                              key: const Key('reportPost'),
                              icon: Icons.flag_outlined,
                              label: 'Report post',
                              danger: true,
                              onTap: () {
                                Navigator.pop(ctx);
                                showReportSheet(context, ref, ReportTarget.post, p.id, 'this post');
                              },
                            ),
                        ]),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LinkChip extends StatelessWidget {
  const _LinkChip({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Tappable(
      onTap: onTap,
      radius: 20,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(color: c.info.withValues(alpha: c.isDark ? 0.14 : 0.08), borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: c.info),
            const SizedBox(width: 5),
            Flexible(
              child: Text(label,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.caption(c.info, size: 12.5).copyWith(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Reaction extends StatelessWidget {
  const _Reaction({super.key, required this.icon, required this.color, required this.label, required this.semantic, this.onTap});

  final IconData icon;
  final Color color;
  final String label;
  final String semantic;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: onTap != null,
        label: semantic,
        excludeSemantics: true,
        child: Tappable(
          onTap: onTap,
          radius: 16,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 19, color: color),
                const SizedBox(width: 5),
                Text(label, style: SxType.caption(context.sx.inkMuted).copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      );
}

/// A feed of posts with an empty state, for the network, a group or a place.
class PostFeed extends ConsumerWidget {
  const PostFeed({super.key, required this.scope, this.limit, this.empty});

  final FeedScope scope;

  /// Show only the first few (hub previews).
  final int? limit;
  final Widget? empty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(communityFeedProvider(scope));
    return feed.when(
      loading: () => const SkeletonList(rows: 2, rowHeight: 140),
      error: (_, _) => ErrorBlock(message: 'Could not load posts.', onRetry: () => ref.invalidate(communityFeedProvider(scope))),
      data: (page) {
        final posts = limit == null ? page.posts : page.posts.take(limit!).toList();
        if (posts.isEmpty) return empty ?? const SizedBox.shrink();
        return Column(
          children: [
            for (final (i, p) in posts.indexed) ...[
              if (i > 0) const SizedBox(height: Sx.s12),
              PostCard(post: p, scope: scope),
            ],
          ],
        );
      },
    );
  }
}

/// Write a post: kind, words, and where it goes. Pickleball only.
Future<void> showPostComposer(BuildContext context, WidgetRef ref, {FeedScope scope = FeedScope.network, String? groupId, String? groupName}) =>
    showSxSheet<void>(context, builder: (ctx) => _Composer(scope: scope, groupId: groupId, groupName: groupName));

class _Composer extends ConsumerStatefulWidget {
  const _Composer({required this.scope, this.groupId, this.groupName});

  final FeedScope scope;
  final String? groupId;
  final String? groupName;

  @override
  ConsumerState<_Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<_Composer> {
  final _body = TextEditingController();
  PostKind _kind = PostKind.tip;
  bool _busy = false;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    setState(() => _busy = true);
    try {
      final p = await ref.read(communityRepositoryProvider).createPost(kind: _kind, body: _body.text, groupId: widget.groupId);
      ref.read(communityFeedProvider(widget.scope).notifier).added(p);
      if (widget.scope != FeedScope.network) ref.invalidate(communityFeedProvider(FeedScope.network));
      if (mounted) {
        Navigator.pop(context);
        showCommunityNote(context, 'Posted.');
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sx.gutter, 0, Sx.gutter, Sx.s24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.groupName == null ? 'New post' : 'Post in ${widget.groupName}', style: SxType.title(c.ink, size: 26)),
            const SizedBox(height: Sx.s4),
            Text('Share something useful: results, tips, news, sessions.', style: SxType.body(c.inkMuted, size: 14)),
            const SizedBox(height: Sx.s16),
            Wrap(
              spacing: Sx.s8,
              runSpacing: Sx.s8,
              children: [
                for (final k in PostKind.values)
                  SxChip(
                    key: Key('postKind-${k.name}'),
                    label: k.label,
                    icon: k.icon,
                    selected: _kind == k,
                    onTap: () => setState(() => _kind = k),
                  ),
              ],
            ),
            const SizedBox(height: Sx.s16),
            TextField(
              key: const Key('postBody'),
              controller: _body,
              autofocus: true,
              minLines: 3,
              maxLines: 8,
              maxLength: 1000,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'What happened on court?'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: Sx.s12),
            SxButton(
              key: const Key('submitPost'),
              label: 'Post',
              busy: _busy,
              onPressed: _body.text.trim().isEmpty ? null : _post,
            ),
          ],
        ),
      ),
    );
  }
}

/// `/player/community/posts`: what my network is posting.
class PostsPage extends ConsumerWidget {
  const PostsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const scope = FeedScope.network;
    return Scaffold(
      body: SafeArea(
        child: SxWidth(
          child: Column(
            children: [
              SxBackBar(onBack: () => context.canPop() ? context.pop() : context.go('/player/community')),
              SxTitleBar(
                title: 'Posts',
                actions: [
                  SxIconAction(
                    key: const Key('newPost'),
                    icon: Icons.edit_outlined,
                    label: 'New post',
                    onTap: () => showPostComposer(context, ref),
                  ),
                ],
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => ref.invalidate(communityFeedProvider(scope)),
                  color: context.sx.onVolt,
                  backgroundColor: context.sx.voltFill,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (n) {
                      if (n.metrics.extentAfter < 400) ref.read(communityFeedProvider(scope).notifier).loadMore();
                      return false;
                    },
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s8, Sx.gutter, Sx.s48),
                      children: [
                        PostFeed(
                          scope: scope,
                          empty: EmptyBlock(
                            key: const Key('postsEmpty'),
                            icon: Icons.dynamic_feed_rounded,
                            title: 'Nothing here yet',
                            message: 'Posts from people you connect with, places you follow and communities you join show up here.',
                            action: SxButton.secondary(
                              label: 'Write the first post',
                              expand: false,
                              onPressed: () => showPostComposer(context, ref),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `/player/community/posts/:id`: the post and its comments.
class PostPage extends ConsumerStatefulWidget {
  const PostPage({super.key, required this.postId, this.scope = FeedScope.network});

  final String postId;
  final FeedScope scope;

  @override
  ConsumerState<PostPage> createState() => _PostPageState();
}

class _PostPageState extends ConsumerState<PostPage> {
  final _text = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send(FeedScope scope) async {
    final body = _text.text.trim();
    if (body.isEmpty) return;
    setState(() => _sending = true);
    try {
      await ref.read(communityRepositoryProvider).comment(widget.postId, body);
      _text.clear();
      ref.invalidate(postCommentsProvider(widget.postId));
      ref.read(communityFeedProvider(scope).notifier).commented(widget.postId, 1);
    } catch (e) {
      if (mounted) showCommunityError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final scope = widget.scope;
    final feed = ref.watch(communityFeedProvider(scope));
    final post = feed.value?.posts.where((p) => p.id == widget.postId).firstOrNull;
    final comments = ref.watch(postCommentsProvider(widget.postId));
    return Scaffold(
      body: SafeArea(
        child: SxWidth(
          child: Column(
            children: [
              SxBackBar(title: 'Post', onBack: () => context.canPop() ? context.pop() : context.go('/player/community/posts')),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s8, Sx.gutter, Sx.s24),
                  children: [
                    if (post != null)
                      PostCard(post: post, scope: scope, open: false)
                    else if (feed.isLoading)
                      const Skeleton(height: 160, radius: Sx.radiusLg)
                    else
                      const EmptyBlock(icon: Icons.dynamic_feed_rounded, title: 'Post unavailable', message: 'It may have been deleted.'),
                    const SizedBox(height: Sx.s20),
                    const SxSection('Comments'),
                    comments.when(
                      loading: () => const SkeletonList(rows: 2, rowHeight: 56),
                      error: (_, _) => const SizedBox.shrink(),
                      data: (list) => list.isEmpty
                          ? Text('No comments yet. Say something kind.', style: SxType.body(c.inkMuted, size: 14))
                          : ListCard(children: [
                              for (final cm in list)
                                Padding(
                                  key: Key('comment-${cm.id}'),
                                  padding: const EdgeInsets.symmetric(vertical: Sx.s12),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      SxAvatar(name: cm.authorName, size: 32),
                                      const SizedBox(width: Sx.s12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('${cm.mine ? 'You' : cm.authorName} · ${timeAgo(cm.at, DateTime.now())}',
                                                style: SxType.caption(c.inkMuted, size: 12)),
                                            const SizedBox(height: 2),
                                            Text(cm.body, style: SxType.body(c.ink, size: 14)),
                                          ],
                                        ),
                                      ),
                                      if (cm.mine)
                                        IconButton(
                                          tooltip: 'Delete comment',
                                          icon: Icon(Icons.close_rounded, size: 18, color: c.inkFaint),
                                          onPressed: () async {
                                            try {
                                              await ref.read(communityRepositoryProvider).deleteComment(cm.id);
                                              ref.invalidate(postCommentsProvider(widget.postId));
                                              ref.read(communityFeedProvider(scope).notifier).commented(widget.postId, -1);
                                            } catch (e) {
                                              if (context.mounted) showCommunityError(context, e);
                                            }
                                          },
                                        ),
                                    ],
                                  ),
                                ),
                            ]),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(Sx.s12, Sx.s8, Sx.s12, Sx.s12),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('commentField'),
                        controller: _text,
                        maxLength: 500,
                        buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(hintText: 'Add a comment', contentPadding: EdgeInsets.symmetric(horizontal: Sx.s16, vertical: 12)),
                        onSubmitted: (_) => _send(scope),
                      ),
                    ),
                    const SizedBox(width: Sx.s8),
                    IconButton.filled(
                      key: const Key('sendComment'),
                      tooltip: 'Send',
                      onPressed: _sending ? null : () => _send(scope),
                      icon: const Icon(Icons.send_rounded),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

