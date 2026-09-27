import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sample_latency.dart';
import '../../core/sample_persona.dart';
import '../auth/auth_controller.dart';

/// What a notification is about; picks its icon. The full catalogue of types
/// and their copy is `docs/NOTIFICATIONS.md`.
enum NotificationKind {
  account,
  matchReminder,

  /// A player added you to a casual match: confirm it (Match requests).
  matchRequest,
  result,
  tournament,
  registration,
  booking,
  official,
  rating,
  achievement,
  community,
  lookingFor,
  subscription,
  organizer,
  explore,
  announcement,
}

/// The kind for a server type such as "tournament.match_call". Results of
/// either kind of match read as results, whatever feature sent them.
NotificationKind notificationKindOf(String type) {
  final [prefix, ...rest] = type.split('.');
  final event = rest.join('.');
  if (event.startsWith('result_') || const {'champion', 'runner_up', 'walkover'}.contains(event)) {
    return NotificationKind.result;
  }
  return switch (prefix) {
    'account' => NotificationKind.account,
    'match_request' => NotificationKind.matchRequest,
    'match' => NotificationKind.matchReminder,
    'result' => NotificationKind.result,
    'tournament' => NotificationKind.tournament,
    'registration' => NotificationKind.registration,
    'booking' => NotificationKind.booking,
    'official' => NotificationKind.official,
    'rating' || 'points' || 'ranking' || 'stats' => NotificationKind.rating,
    'achievement' => NotificationKind.achievement,
    'community' => NotificationKind.community,
    'looking_for' => NotificationKind.lookingFor,
    'subscription' => NotificationKind.subscription,
    'org' => NotificationKind.organizer,
    'explore' => NotificationKind.explore,
    _ => NotificationKind.announcement,
  };
}

/// High shows first with an accent; low is grouped quietly.
enum NotificationPriority { high, normal, low }

class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.at,
    this.priority = NotificationPriority.normal,
    this.read = false,
    this.route,
  });

  final String id;
  final NotificationKind kind;
  final NotificationPriority priority;
  final String title;
  final String body;
  final DateTime at;
  final bool read;

  /// Where tapping it goes, e.g. "/player/tournament/t-open".
  final String? route;

  /// A row of `GET /me/notifications`. The type picks the kind
  /// ("looking_for.match" → Looking For).
  factory AppNotification.fromJson(Map<String, dynamic> j) {
    return AppNotification(
      id: j['id'] as String,
      kind: notificationKindOf(j['type'] as String? ?? ''),
      title: j['title'] as String,
      body: j['body'] as String,
      at: DateTime.parse(j['at'] as String).toLocal(),
      priority: switch (j['priority']) {
        'high' => NotificationPriority.high,
        'low' => NotificationPriority.low,
        _ => NotificationPriority.normal,
      },
      read: j['read'] as bool? ?? false,
      route: j['route'] as String?,
    );
  }

  AppNotification markRead() => AppNotification(
        id: id,
        kind: kind,
        title: title,
        body: body,
        at: at,
        priority: priority,
        read: true,
        route: route,
      );
}

/// In-app notification centre. Push (FCM/APNs) arrives with build step 7;
/// these are the same items, read from `GET /me/notifications`.
final notificationsProvider =
    AsyncNotifierProvider<NotificationsController, List<AppNotification>>(NotificationsController.new);

final unreadNotificationsProvider = Provider<int>(
  (ref) => ref.watch(notificationsProvider).value?.where((n) => !n.read).length ?? 0,
);

class NotificationsController extends AsyncNotifier<List<AppNotification>> {
  @override
  Future<List<AppNotification>> build() async {
    if (useRealApi || !kDebugMode) return _fromApi();

    final newcomer = ref.watch(samplePersonaProvider) == SamplePersona.newcomer;
    await simulateLatency(ref.read(sampleLatencyProvider));
    return newcomer ? _welcome(DateTime.now()) : _sample(DateTime.now());
  }

  /// `GET /me/notifications`
  Future<List<AppNotification>> _fromApi() async {
    if (ref.watch(currentUserProvider) == null) return const [];
    final data = await ref.read(apiClientProvider).get<List<dynamic>>('/me/notifications');
    return [for (final n in data.cast<Map<String, dynamic>>()) AppNotification.fromJson(n)];
  }

  /// `POST /me/notifications/read`
  void markRead(String id) {
    final list = state.value;
    if (list == null) return;
    state = AsyncData([for (final n in list) n.id == id ? n.markRead() : n]);
    _sendRead([id]);
  }

  void markAllRead() {
    final list = state.value;
    if (list == null) return;
    state = AsyncData([for (final n in list) n.markRead()]);
    _sendRead(const []);
  }

  /// Best effort: a failed call leaves them unread on the server, never the app broken.
  void _sendRead(List<String> ids) {
    if (!useRealApi && kDebugMode) return;
    ref.read(apiClientProvider).post<Object?>('/me/notifications/read', body: {'ids': ids}).ignore();
  }
}

// Sample copy follows docs/NOTIFICATIONS.md word for word.

List<AppNotification> _welcome(DateTime now) => [
      AppNotification(
        id: 'n0',
        kind: NotificationKind.account,
        title: 'Welcome to the court',
        body: 'Your player card is live. Book a court, find a tournament or score your first rally.',
        at: now.subtract(const Duration(minutes: 2)),
        route: '/player/explore',
      ),
    ];

List<AppNotification> _sample(DateTime now) {
  AppNotification n(
    String id,
    NotificationKind kind,
    String title,
    String body,
    Duration ago, {
    String? route,
    NotificationPriority priority = NotificationPriority.normal,
    bool read = false,
  }) =>
      AppNotification(id: id, kind: kind, title: title, body: body, at: now.subtract(ago), route: route, priority: priority, read: read);

  const m = Duration(minutes: 1), h = Duration(hours: 1), d = Duration(days: 1);
  return [
    // Match day
    n('n-call', NotificationKind.tournament, "You're up on Court 03", 'Quarter-final vs Arjun & Kabir. The referee is waiting.', m * 4,
        route: '/player/matches/lg-qf1', priority: NotificationPriority.high),
    n('n-mr1', NotificationKind.matchRequest, 'Kamal Parmar added you to a casual match', 'You + Hardik vs Kamal + Anand · 27 Sep 2026. Confirm you played so it counts.', m * 10,
        route: '/player/match-requests/cm-seed-1', priority: NotificationPriority.high),
    n('n-lf1', NotificationKind.lookingFor, 'Wanted: 2 Players needed tonight', 'Pickle Blitz Arena · Today 8:00 PM. Near you, and you fit the bill. Be the first to say yes.', m * 20,
        route: '/player/looking-for/lf-1', priority: NotificationPriority.high),
    n('n-partner', NotificationKind.registration, 'Riya Shah wants you as their partner', 'Mixed Doubles at SkorX Open 2026. Say yes before entries close Thu 2 Oct.', m * 45,
        route: '/player/tournament/t-open', priority: NotificationPriority.high),
    n('n-msg', NotificationKind.community, 'Meera Iyer', 'Up for a game at 7 tomorrow? Court 2 is free.', h,
        route: '/player/community/messages', priority: NotificationPriority.high),
    n('n-cm1', NotificationKind.community, 'Rohan Desai wants to connect', '3 mutual connections · Ahmedabad Pickleball.', h * 2,
        route: '/player/community/connections?tab=requests'),
    n('n-booking', NotificationKind.booking, 'Court time in 2 hours', 'Pickle Blitz Arena · Court 2 at 7:00 PM. Paddle, balls, water.', h * 3,
        route: '/player/bookings', priority: NotificationPriority.high),
    n('n-win', NotificationKind.result, 'Through to the quarter-final!', 'Won 11–7, 11–9 vs Dev & Ishaan. Next up: Arjun & Kabir, Today 6:30 PM.', h * 5,
        route: '/player/matches/lg-qf1'),
    n('n-close', NotificationKind.tournament, 'Last call: SkorX Open 2026', "Entries close Thu 2 Oct. Men's Doubles has 6 spots left.", h * 9,
        route: '/player/tournament/t-open', priority: NotificationPriority.high),
    n('n-rating', NotificationKind.rating, 'SkorX Rating up to 44.8', '+0.9 from three league pool wins. Keep stacking.', h * 26, route: '/player/paddle'),
    n('n-streak', NotificationKind.achievement, 'Unlocked: Hot Streak', '3 wins in a row. Somebody call the fire brigade.', h * 27, route: '/player/achievements'),
    n('n-rank', NotificationKind.rating, "You're #12 in Ahmedabad", 'Up 3 places this week. Meera Iyer is next in your sights.', h * 30, route: '/player/rankings'),
    n('n-rival', NotificationKind.subscription, 'Arjun Patel has your number', "They've won 3 of your last 4. See their weak side with Pro.", d * 2,
        route: '/player/pro', priority: NotificationPriority.low),
    // Earlier
    n('n-in', NotificationKind.registration, "You're in: SkorX Open 2026", 'Mixed Doubles with Riya Shah. The draw drops Thu 2 Oct.', d * 4,
        route: '/player/tournament/t-open', read: true),
    n('n-court', NotificationKind.booking, 'Court 2 is yours', 'Pickle Blitz Arena · Sat 7:00 AM. See you on the baseline.', d * 6, route: '/player/bookings', read: true),
    n('n-lf2', NotificationKind.lookingFor, 'Kabir Mehta raised a paddle', '"Free after 7, happy to play either side" · Doubles partner for Sunday', d * 6,
        route: '/player/looking-for?tab=mine', read: true),
    n('n-weekend', NotificationKind.explore, 'This weekend in Ahmedabad', '3 tournaments · 12 open courts · 7 games need players.', d * 7,
        route: '/player/explore', priority: NotificationPriority.low, read: true),
    n('n-news', NotificationKind.announcement, 'Parking moves to Gate 2', 'CADLETE Pickleball: Parking at CADLETE Club moves to Gate 2 this weekend.', d * 8,
        route: '/player/tournament/t-open', priority: NotificationPriority.low, read: true),
  ];
}
