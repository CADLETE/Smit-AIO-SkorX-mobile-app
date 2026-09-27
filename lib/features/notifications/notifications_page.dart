import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../design/design.dart';
import '../../shared/format.dart';
import 'notifications.dart';

IconData _icon(NotificationKind k) => switch (k) {
      NotificationKind.matchReminder => Icons.sports_tennis_rounded,
      NotificationKind.result => Icons.scoreboard_outlined,
      NotificationKind.tournament => Icons.emoji_events_outlined,
      NotificationKind.registration => Icons.how_to_reg_outlined,
      NotificationKind.booking => Icons.calendar_month_outlined,
      NotificationKind.rating => Icons.trending_up_rounded,
      NotificationKind.achievement => Icons.workspace_premium_outlined,
      NotificationKind.announcement => Icons.campaign_outlined,
    };

const _tabs = ['/player/home', '/player/matches', '/player/explore', '/player/paddle', '/player/profile'];

/// Unread first, one line each, and every item goes where it is about.
class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final list = ref.watch(notificationsProvider);
    final ctl = ref.read(notificationsProvider.notifier);
    final unread = ref.watch(unreadNotificationsProvider);
    final now = DateTime.now();

    void open(AppNotification n) {
      ctl.markRead(n.id);
      final route = n.route;
      if (route == null) return;
      if (_tabs.any((t) => route == t || route.startsWith('$t?'))) {
        context.go(route);
      } else {
        context.push(route);
      }
    }

    Widget row(AppNotification n) => Semantics(
          button: n.route != null,
          label: '${n.read ? '' : 'Unread. '}${n.title}. ${n.body}',
          excludeSemantics: true,
          child: Tappable(
            onTap: () => open(n),
            radius: 0,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Sx.s16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c.line)),
                    child: Icon(_icon(n.kind), size: 20, color: n.read ? c.inkMuted : c.ink),
                  ),
                  const SizedBox(width: Sx.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                n.title,
                                style: SxType.heading(n.read ? c.inkMuted : c.ink, size: 15)
                                    .copyWith(fontWeight: n.read ? FontWeight.w500 : FontWeight.w700),
                              ),
                            ),
                            Text(timeAgo(n.at, now), style: SxType.caption(c.inkFaint, size: 12)),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(n.body, maxLines: 2, overflow: TextOverflow.ellipsis, style: SxType.caption(c.inkMuted)),
                      ],
                    ),
                  ),
                  if (!n.read)
                    Padding(
                      padding: const EdgeInsets.only(left: Sx.s8, top: 6),
                      child: Container(width: 8, height: 8, decoration: BoxDecoration(color: c.live, shape: BoxShape.circle)),
                    ),
                ],
              ),
            ),
          ),
        );

    return Scaffold(
      body: SafeArea(
        child: SxWidth(
          child: Column(
            children: [
              SxBackBar(
                onBack: () => context.canPop() ? context.pop() : context.go('/player/home'),
                actions: [
                  if (unread > 0)
                    SxButton.quiet(key: const Key('markAllRead'), label: 'Mark all read', onPressed: ctl.markAllRead),
                ],
              ),
              const SxTitleBar(title: 'Notifications'),
              Expanded(
                child: switch (list) {
                  AsyncData(:final value) when value.isEmpty => const EmptyBlock(
                      icon: Icons.notifications_none_rounded,
                      title: "You're all caught up",
                      message: 'Match calls, results and tournament news will land here.',
                    ),
                  AsyncData(:final value) => ListView(
                      padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s8, Sx.gutter, Sx.s48),
                      children: [
                        for (final (title, items) in [
                          ('New', value.where((n) => !n.read).toList()),
                          ('Earlier', value.where((n) => n.read).toList()),
                        ])
                          if (items.isNotEmpty) ...[
                            SxSection(title, padding: const EdgeInsets.only(top: Sx.s8)),
                            for (final (i, n) in items.indexed) ...[
                              if (i > 0) Divider(height: 1, color: c.line),
                              row(n),
                            ],
                            const SizedBox(height: Sx.s16),
                          ],
                      ],
                    ),
                  _ => const Padding(padding: EdgeInsets.all(Sx.gutter), child: SkeletonList()),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
