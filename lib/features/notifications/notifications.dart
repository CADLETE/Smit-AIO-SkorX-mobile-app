import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sample_latency.dart';
import '../../core/sample_persona.dart';

enum NotificationKind { matchReminder, tournament, registration, booking, result, rating, achievement, announcement }

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
    if (!kDebugMode) return const [];
    final newcomer = ref.watch(samplePersonaProvider) == SamplePersona.newcomer;
    await simulateLatency(ref.read(sampleLatencyProvider));
    return newcomer ? _welcome(DateTime.now()) : _sample(DateTime.now());
  }

  /// `POST /me/notifications/read`
  void markRead(String id) {
    final list = state.value;
    if (list == null) return;
    state = AsyncData([for (final n in list) n.id == id ? n.markRead() : n]);
  }

  void markAllRead() {
    final list = state.value;
    if (list == null) return;
    state = AsyncData([for (final n in list) n.markRead()]);
  }
}

List<AppNotification> _welcome(DateTime now) => [
      AppNotification(
        id: 'n0',
        kind: NotificationKind.announcement,
        title: 'Welcome to SkorX',
        body: 'Find a tournament near you, or book a court and score your first match.',
        at: now.subtract(const Duration(minutes: 2)),
        route: '/player/explore',
      ),
    ];

List<AppNotification> _sample(DateTime now) => [
      AppNotification(
        id: 'n1',
        kind: NotificationKind.matchReminder,
        priority: NotificationPriority.high,
        title: 'Your quarter-final is on court',
        body: 'Ahmedabad Pickle League · Court 03 · You lead 1–0 in games.',
        at: now.subtract(const Duration(minutes: 24)),
        route: '/player/matches/lg-qf1',
      ),
      AppNotification(
        id: 'n2',
        kind: NotificationKind.rating,
        title: 'Rating updated: 1248',
        body: '+21 across your three pool matches in the league.',
        at: now.subtract(const Duration(hours: 26)),
        route: '/player/paddle',
      ),
      AppNotification(
        id: 'n3',
        kind: NotificationKind.tournament,
        priority: NotificationPriority.high,
        title: 'SkorX Open: registration closes soon',
        body: "Men's Doubles has 6 spots left.",
        at: now.subtract(const Duration(hours: 30)),
        route: '/player/tournament/t-open',
      ),
      AppNotification(
        id: 'n4',
        kind: NotificationKind.achievement,
        title: 'Achievement unlocked: Hot Streak',
        body: '3 wins in a row. Keep it going.',
        at: now.subtract(const Duration(days: 3)),
        read: true,
        route: '/player/achievements',
      ),
      AppNotification(
        id: 'n5',
        kind: NotificationKind.registration,
        title: "You're in: SkorX Open 2026",
        body: 'Mixed Doubles · Intermediate with Riya Shah.',
        at: now.subtract(const Duration(days: 4)),
        read: true,
        route: '/player/tournament/t-open',
      ),
      AppNotification(
        id: 'n6',
        kind: NotificationKind.booking,
        title: 'Court booked',
        body: 'Pickle Blitz Arena · Court 2 · 7 AM.',
        at: now.subtract(const Duration(days: 6)),
        read: true,
        route: '/player/bookings',
      ),
      AppNotification(
        id: 'n7',
        kind: NotificationKind.announcement,
        priority: NotificationPriority.low,
        title: 'CADLETE Pickleball',
        body: 'Parking at CADLETE Club moves to Gate 2 this weekend.',
        at: now.subtract(const Duration(days: 8)),
        read: true,
      ),
    ];
