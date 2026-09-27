import 'package:flutter_test/flutter_test.dart';
import 'package:skorx/features/notifications/notifications.dart';

void main() {
  test('every server type in docs/NOTIFICATIONS.md gets its own kind', () {
    const expected = {
      'account.new_sign_in': NotificationKind.account,
      'match.invite': NotificationKind.matchReminder,
      'match.result_win': NotificationKind.result,
      'tournament.match_call': NotificationKind.tournament,
      'tournament.result_loss': NotificationKind.result,
      'tournament.champion': NotificationKind.result,
      'tournament.walkover': NotificationKind.result,
      'registration.partner_invite': NotificationKind.registration,
      'booking.reminder': NotificationKind.booking,
      'official.request': NotificationKind.official,
      'rating.band_up': NotificationKind.rating,
      'points.level_up': NotificationKind.rating,
      'ranking.overtaken': NotificationKind.rating,
      'stats.monthly': NotificationKind.rating,
      'achievement.unlocked': NotificationKind.achievement,
      'community.message': NotificationKind.community,
      'looking_for.response': NotificationKind.lookingFor,
      'subscription.payment_failed': NotificationKind.subscription,
      'org.court_idle': NotificationKind.organizer,
      'explore.weekend': NotificationKind.explore,
      'system.maintenance': NotificationKind.announcement,
      '': NotificationKind.announcement,
    };
    for (final MapEntry(key: type, value: kind) in expected.entries) {
      expect(notificationKindOf(type), kind, reason: type);
    }
  });
}
