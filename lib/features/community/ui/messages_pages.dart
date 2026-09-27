import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design/design.dart';
import '../../../shared/format.dart';
import '../community_controller.dart';
import '../data/community.dart';
import '../data/messages.dart';
import 'community_widgets.dart';

enum _InboxView { chats, requests }

/// `/player/community/messages`: conversations, and message requests from
/// people who are not connections kept apart.
class MessagesPage extends ConsumerStatefulWidget {
  const MessagesPage({super.key, this.requests = false});

  final bool requests;

  @override
  ConsumerState<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends ConsumerState<MessagesPage> {
  late _InboxView _view = widget.requests ? _InboxView.requests : _InboxView.chats;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final all = ref.watch(conversationsProvider);
    final requests = all.value?.where((x) => x.request).length ?? 0;
    final profile = ref.watch(myCommunityProfileProvider).value;
    return Scaffold(
      body: SafeArea(
        child: SxWidth(
          child: Column(
            children: [
              SxBackBar(onBack: () => context.canPop() ? context.pop() : context.go('/player/community')),
              const SxTitleBar(title: 'Messages'),
              SxTabs<_InboxView>(
                tabs: [(_InboxView.chats, 'Chats', null), (_InboxView.requests, 'Requests', requests)],
                selected: _view,
                onSelect: (v) => setState(() => _view = v),
              ),
              Expanded(
                child: all.when(
                  loading: () => const Padding(padding: EdgeInsets.all(Sx.gutter), child: SkeletonList()),
                  error: (_, _) => ErrorBlock(message: 'Could not load messages.', onRetry: () => ref.invalidate(conversationsProvider)),
                  data: (list) {
                    final shown = [for (final x in list) if (x.request == (_view == _InboxView.requests)) x];
                    return RefreshIndicator(
                      onRefresh: () async => ref.invalidate(conversationsProvider),
                      color: c.onVolt,
                      backgroundColor: c.voltFill,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s8, Sx.gutter, Sx.s48),
                        children: [
                          if (_view == _InboxView.requests)
                            Padding(
                              padding: const EdgeInsets.only(bottom: Sx.s12),
                              child: Text(
                                'Messages from people you are not connected to. They do not know you have seen them until you reply.',
                                style: SxType.caption(c.inkMuted),
                              ),
                            ),
                          if (shown.isEmpty)
                            EmptyBlock(
                              key: const Key('inboxEmpty'),
                              icon: _view == _InboxView.chats ? Icons.forum_outlined : Icons.mark_email_read_outlined,
                              title: _view == _InboxView.chats ? 'No conversations yet' : 'No requests',
                              message: _view == _InboxView.chats
                                  ? 'Message a player, coach, club or referee from their profile.'
                                  : 'You are all caught up.',
                              action: _view == _InboxView.chats
                                  ? SxButton.secondary(
                                      label: 'Find people',
                                      expand: false,
                                      onPressed: () => context.push('/player/community/search'),
                                    )
                                  : null,
                            )
                          else
                            ListCard(children: [for (final x in shown) _ConversationRow(conversation: x)]),
                          const SizedBox(height: Sx.s24),
                          SxRows(children: [
                            SxRow(
                              key: const Key('messagePrivacy'),
                              icon: Icons.shield_outlined,
                              label: 'Who can message me',
                              value: (profile?.messagesFrom ?? MessagePermission.everyone).label,
                              onTap: () => context.push('/player/community/me'),
                            ),
                          ]),
                        ],
                      ),
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

class _ConversationRow extends StatelessWidget {
  const _ConversationRow({required this.conversation});

  final Conversation conversation;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final x = conversation;
    final unread = x.unread > 0 || x.request;
    return Semantics(
      button: true,
      label: '${x.title}${unread ? ', unread' : ''}. ${x.lastText ?? ''}',
      excludeSemantics: true,
      child: Tappable(
        key: Key('conversation-${x.id}'),
        onTap: () => context.push('/player/community/messages/${x.id}'),
        radius: 0,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Sx.s12),
          child: Row(
            children: [
              _ConversationMark(conversation: x),
              const SizedBox(width: Sx.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(x.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: SxType.heading(c.ink, size: 16).copyWith(fontWeight: unread ? FontWeight.w800 : FontWeight.w600)),
                        ),
                        const SizedBox(width: Sx.s8),
                        Text(timeAgo(x.lastAt, DateTime.now()), style: SxType.caption(c.inkFaint, size: 12)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(x.lastText ?? 'Say hello',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: SxType.caption(unread ? c.ink : c.inkMuted, size: 13)),
                        ),
                        if (x.unread > 0) ...[
                          const SizedBox(width: Sx.s8),
                          Container(
                            constraints: const BoxConstraints(minWidth: 20),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(gradient: c.brand, borderRadius: BorderRadius.circular(10)),
                            child: Text('${x.unread}', textAlign: TextAlign.center, style: SxType.number(13, c.onVolt, weight: FontWeight.w800)),
                          ),
                        ],
                      ],
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

class _ConversationMark extends StatelessWidget {
  const _ConversationMark({required this.conversation});

  final Conversation conversation;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final x = conversation;
    return switch (x.kind) {
      ConversationKind.direct => SxAvatar(name: x.title, size: 46),
      ConversationKind.place => SxIconTile(icon: Icons.storefront_rounded, size: 46, colors: sxTileColors(c, 3)),
      ConversationKind.group => SxIconTile(icon: Icons.diversity_3_rounded, size: 46, colors: sxTileColors(c, 1)),
      ConversationKind.event => SxIconTile(icon: Icons.event_rounded, size: 46, colors: sxTileColors(c, 2)),
    };
  }
}

/// `/player/community/messages/:id`: one conversation.
class ThreadPage extends ConsumerStatefulWidget {
  const ThreadPage({super.key, required this.conversationId, this.draft});

  final String conversationId;

  /// Pre-filled text, e.g. an academy enquiry. Never sent without a tap.
  final String? draft;

  @override
  ConsumerState<ThreadPage> createState() => _ThreadPageState();
}

class _ThreadPageState extends ConsumerState<ThreadPage> {
  late final _text = TextEditingController(text: widget.draft ?? '');
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(conversationsProvider.notifier).markRead(widget.conversationId));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref.read(threadProvider(widget.conversationId).notifier).send(text);
      HapticFeedback.lightImpact();
      _text.clear();
    } catch (e) {
      if (mounted) showCommunityError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _openTarget(Conversation x) => switch (x.kind) {
        ConversationKind.direct => context.push(memberRoute(x.targetId)),
        ConversationKind.place => context.push(placeRoute(x.targetId)),
        ConversationKind.group => context.push(groupRoute(x.targetId)),
        ConversationKind.event => context.push('/player/community/events/${x.targetId}'),
      };

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final conversation =
        ref.watch(conversationsProvider.select((v) => v.value?.where((x) => x.id == widget.conversationId).firstOrNull));
    final messages = ref.watch(threadProvider(widget.conversationId));
    final x = conversation;
    final sentOne = messages.value?.any((m) => m.mine) ?? false;
    final waiting = x != null && x.awaitingReply && sentOne;
    return Scaffold(
      body: SafeArea(
        child: SxWidth(
          child: Column(
            children: [
              SxBackBar(
                title: x?.title ?? 'Conversation',
                onBack: () => context.canPop() ? context.pop() : context.go('/player/community/messages'),
                actions: [
                  if (x != null)
                    OverflowMenu(items: [
                      (
                        switch (x.kind) {
                          ConversationKind.direct => 'View profile',
                          ConversationKind.place => 'View page',
                          ConversationKind.group => 'View community',
                          ConversationKind.event => 'View event',
                        },
                        Icons.open_in_new_rounded,
                        () => _openTarget(x),
                        false,
                      ),
                      if (x.kind == ConversationKind.direct)
                        ('Report', Icons.flag_outlined, () => showReportSheet(context, ref, ReportTarget.member, x.targetId, x.title), true),
                      ('Delete conversation', Icons.delete_outline_rounded, () => _delete(x), true),
                    ]),
                ],
              ),
              if (x != null && x.request) _RequestBar(conversation: x),
              Expanded(
                child: messages.when(
                  loading: () => const Center(child: BallLoader()),
                  error: (e, _) => EmptyBlock(
                    icon: Icons.forum_outlined,
                    title: 'Conversation unavailable',
                    message: 'It may have been deleted.',
                  ),
                  data: (list) => list.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(Sx.gutter),
                            child: Text(
                              x?.awaitingReply ?? false
                                  ? 'You are not connected yet. Your first message arrives as a request; you can send more once they reply.'
                                  : 'Say hello.',
                              textAlign: TextAlign.center,
                              style: SxType.body(c.inkMuted, size: 14),
                            ),
                          ),
                        )
                      : ListView.builder(
                          reverse: true,
                          padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s12, Sx.gutter, Sx.s12),
                          itemCount: list.length,
                          itemBuilder: (_, i) {
                            final m = list[list.length - 1 - i];
                            final prev = i + 1 < list.length ? list[list.length - 2 - i] : null;
                            final showName = x?.kind != ConversationKind.direct && !m.mine && prev?.senderId != m.senderId;
                            return _Bubble(message: m, showName: showName);
                          },
                        ),
                ),
              ),
              if (waiting)
                Padding(
                  padding: const EdgeInsets.fromLTRB(Sx.gutter, 0, Sx.gutter, Sx.s8),
                  child: Text(
                    key: const Key('awaitingReply'),
                    'Sent as a request. You can write again once ${x.title.split(' ').first} replies or connects with you.',
                    style: SxType.caption(c.inkMuted),
                  ),
                ),
              if (x == null || !x.request)
                _Composer(controller: _text, sending: _sending, enabled: !waiting, onSend: _send),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _delete(Conversation x) async {
    try {
      await ref.read(conversationsProvider.notifier).delete(x.id);
      if (mounted) context.canPop() ? context.pop() : context.go('/player/community/messages');
    } catch (e) {
      if (mounted) showCommunityError(context, e);
    }
  }
}

/// A message request: accept to reply, or decline or block without them
/// being told.
class _RequestBar extends ConsumerWidget {
  const _RequestBar({required this.conversation});

  final Conversation conversation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final x = conversation;
    final first = x.title.split(' ').first;
    return Container(
      margin: const EdgeInsets.fromLTRB(Sx.gutter, 0, Sx.gutter, Sx.s8),
      padding: const EdgeInsets.all(Sx.s16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Sx.radius),
        border: Border.all(color: c.cardEdge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('$first wants to message you', style: SxType.heading(c.ink, size: 16)),
          const SizedBox(height: 2),
          Text('You are not connected. Accept to reply; they are not told if you decline.', style: SxType.caption(c.inkMuted)),
          const SizedBox(height: Sx.s12),
          Row(
            children: [
              Expanded(
                child: SxButton(
                  key: const Key('acceptRequest'),
                  label: 'Accept',
                  height: 44,
                  onPressed: () async {
                    try {
                      await ref.read(conversationsProvider.notifier).accept(x.id);
                    } catch (e) {
                      if (context.mounted) showCommunityError(context, e);
                    }
                  },
                ),
              ),
              const SizedBox(width: Sx.s8),
              Expanded(
                child: SxButton.secondary(
                  key: const Key('declineRequest'),
                  label: 'Decline',
                  height: 44,
                  onPressed: () async {
                    try {
                      await ref.read(conversationsProvider.notifier).delete(x.id);
                      if (context.mounted) context.canPop() ? context.pop() : context.go('/player/community/messages');
                    } catch (e) {
                      if (context.mounted) showCommunityError(context, e);
                    }
                  },
                ),
              ),
            ],
          ),
          if (x.kind == ConversationKind.direct)
            Align(
              alignment: Alignment.centerLeft,
              child: SxButton.quiet(
                key: const Key('blockFromRequest'),
                label: 'Block $first',
                onPressed: () async {
                  try {
                    final m = await ref.read(communityMemberProvider(x.targetId).future);
                    if (!context.mounted) return;
                    if (await confirmBlock(context, ref, m) && context.mounted) {
                      context.canPop() ? context.pop() : context.go('/player/community/messages');
                    }
                  } catch (e) {
                    if (context.mounted) showCommunityError(context, e);
                  }
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.showName});

  final ChatMessage message;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final m = message;
    final mine = m.mine;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (showName)
            Padding(
              padding: const EdgeInsets.only(left: 12, top: 6, bottom: 2),
              child: Text(m.senderName, style: SxType.caption(c.inkMuted, size: 12).copyWith(fontWeight: FontWeight.w700)),
            ),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.76),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              decoration: BoxDecoration(
                gradient: mine ? c.brand : null,
                color: mine ? null : c.surface,
                border: mine ? null : Border.all(color: c.cardEdge),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(mine ? 18 : 4),
                  bottomRight: Radius.circular(mine ? 4 : 18),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    widthFactor: 1,
                    child: Text(m.text, style: SxType.body(mine ? c.onVolt : c.ink, size: 15)),
                  ),
                  const SizedBox(height: 2),
                  Text(time12(m.at), style: SxType.caption(mine ? c.onVolt.withValues(alpha: 0.6) : c.inkFaint, size: 11)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.sending, required this.enabled, required this.onSend});

  final TextEditingController controller;
  final bool sending;
  final bool enabled;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Container(
      padding: const EdgeInsets.fromLTRB(Sx.s12, Sx.s8, Sx.s12, Sx.s12),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              key: const Key('composer'),
              controller: controller,
              enabled: enabled,
              minLines: 1,
              maxLines: 5,
              maxLength: maxMessageLength,
              buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: enabled ? 'Message' : 'Waiting for a reply',
                contentPadding: const EdgeInsets.symmetric(horizontal: Sx.s16, vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: Sx.s8),
          ValueListenableBuilder(
            valueListenable: controller,
            builder: (context, value, _) {
              final ready = enabled && !sending && value.text.trim().isNotEmpty;
              return Semantics(
                button: true,
                enabled: ready,
                label: 'Send',
                excludeSemantics: true,
                child: Tappable(
                  key: const Key('send'),
                  onTap: ready ? onSend : null,
                  radius: 24,
                  child: AnimatedOpacity(
                    duration: Sx.fast,
                    opacity: ready ? 1 : 0.4,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(gradient: c.brand, shape: BoxShape.circle),
                      child: sending
                          ? Padding(padding: const EdgeInsets.all(14), child: CircularProgressIndicator(strokeWidth: 2, color: c.onVolt))
                          : Icon(Icons.send_rounded, color: c.onVolt, size: 20),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
