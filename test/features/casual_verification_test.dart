import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skorx/app/app.dart';
import 'package:skorx/core/api/api_exception.dart';
import 'package:skorx/features/auth/data/auth_repository.dart';
import 'package:skorx/features/casual_match/verification/verification.dart';
import 'package:skorx/features/casual_match/verification/verification_repository.dart';
import 'package:skorx/features/matches/data/match.dart';
import 'package:skorx/features/notifications/notifications.dart';
import 'package:skorx/features/player/data/player_repository.dart' show PlayCategory;

import '../support/fakes.dart';
import 'player_app_test.dart' show goTo, usePhone;

/// A casual match of mine that won, with a given verification state.
Match casual(String id, {MatchLifecycle? verification}) => Match(
      id: id,
      status: MatchStatus.completed,
      kind: MatchKind.friendly,
      format: PlayCategory.doubles,
      mine: const ['You', 'Kamal Parmar'],
      theirs: const ['Riya Shah', 'Dev Patel'],
      scheduledAt: DateTime(2026, 9, 27, 18),
      completedAt: DateTime(2026, 9, 27, 18, 40),
      games: const [(11, 7), (11, 9)],
      verification: verification,
    );

/// The server's DTO for a doubles match, as `toLiveMatchDto` sends it.
Map<String, dynamic> serverMatch({String lifecycle = 'completed', int round = 1, bool canRespond = true}) => {
      'id': 'cm1',
      'kind': 'casual',
      'category': 'doubles',
      'clientRef': 'local-1',
      'status': 'completed',
      'startedAt': '2026-09-27T12:00:00.000Z',
      'completedAt': '2026-09-27T12:40:00.000Z',
      'locationName': 'ABC Pickleball Club',
      'winnerSide': 'a',
      'sideA': {'name': 'Ava / Ben', 'score': [11, 11]},
      'sideB': {'name': 'Cal / Dia', 'score': [7, 9]},
      'participants': [
        {'side': 'a', 'slot': 1, 'displayName': 'Ava Test'},
        {'side': 'a', 'slot': 2, 'displayName': 'Ben Test'},
        {'side': 'b', 'slot': 1, 'displayName': 'Cal Test'},
        {'side': 'b', 'slot': 2, 'displayName': 'Dia Test'},
      ],
      'verification': {
        'status': 'pending',
        'lifecycle': lifecycle,
        'round': round,
        'official': lifecycle == 'verified',
        'resultSubmitted': true,
        'expired': false,
        'flagged': false,
        'createdBy': {'userId': 'u-ava', 'name': 'Ava Test'},
        'progress': {'confirmed': 3, 'required': 4},
        'players': [
          {'side': 'a', 'slot': 1, 'name': 'Ava Test', 'userId': 'u-ava', 'isCreator': true, 'isMe': false, 'state': 'confirmed'},
          {'side': 'a', 'slot': 2, 'name': 'Ben Test', 'userId': 'u-ben', 'isCreator': false, 'isMe': false, 'state': 'confirmed'},
          {'side': 'b', 'slot': 1, 'name': 'Cal Test', 'userId': 'u-cal', 'isCreator': false, 'isMe': false, 'state': 'confirmed'},
          {'side': 'b', 'slot': 2, 'name': 'Dia Test', 'userId': 'u-dia', 'isCreator': false, 'isMe': true, 'state': 'joined'},
        ],
        'viewer': {'role': 'player', 'state': 'joined', 'request': canRespond ? 'result' : null, 'canRespond': canRespond},
      },
    };

void main() {
  group('rating and stats protection', () {
    test('only verified casual matches reach the record', () {
      final record = PlayerRecord([
        casual('verified', verification: MatchLifecycle.verified),
        casual('pending', verification: MatchLifecycle.completed),
        casual('disputed', verification: MatchLifecycle.disputed),
        casual('rejected', verification: MatchLifecycle.rejected),
        casual('guest', verification: MatchLifecycle.unofficial),
        casual('offline', verification: MatchLifecycle.draft),
        casual('server'),
      ]);
      expect([for (final m in record.finished) m.id], unorderedEquals(['verified', 'server']));
      expect(record.played, 2);
      expect(record.wins, 2);
    });

    test('tournament matches and matches SkorX already counts are official', () {
      expect(casual('x').isOfficial, isTrue);
      expect(casual('x', verification: MatchLifecycle.verified).isOfficial, isTrue);
      for (final l in MatchLifecycle.values.where((l) => l != MatchLifecycle.verified)) {
        expect(casual('x', verification: l).isOfficial, isFalse, reason: l.name);
      }
    });
  });

  group('server verification block', () {
    test('parses players, progress and what the viewer can do', () {
      final m = CasualMatchRecord.fromJson(serverMatch());
      expect(m.lineup, 'Ava + Ben vs Cal + Dia');
      expect(m.scoreLabel, '11–7, 11–9');
      expect(m.verification.lifecycle, MatchLifecycle.completed);
      expect(m.verification.round, 1);
      expect(m.verification.confirmed, 3);
      expect(m.verification.required, 4);
      expect(m.verification.createdBy, 'Ava Test');
      expect(m.verification.canRespond, isTrue);
      expect(m.verification.request, RequestKind.result);
      expect([for (final p in m.verification.waitingFor) p.name], ['Dia Test']);
    });

    test('match_request notifications have their own kind', () {
      expect(notificationKindOf('match_request.added'), NotificationKind.matchRequest);
      expect(notificationKindOf('match_request.result'), NotificationKind.matchRequest);
      expect(notificationKindOf('match.verified'), NotificationKind.matchReminder);
    });
  });

  group('sample verification (debug stand-in for the API)', () {
    late DateTime now;
    late SampleCasualVerificationRepository repo;

    setUp(() {
      useInMemoryPreferences();
      now = DateTime(2026, 9, 27, 18);
      repo = SampleCasualVerificationRepository(SharedPreferencesAsync(), latency: Duration.zero, clock: () => now);
    });

    NewCasualMatch doubles({String ref = 'local-1', bool guest = false}) => NewCasualMatch(
          clientRef: ref,
          sportId: 'pickleball',
          categoryId: 'doubles',
          sideA: const [LineupPlayer.me(), LineupPlayer.registered('SKX-10412')],
          sideB: [const LineupPlayer.registered('SKX-10519'), guest ? const LineupPlayer.guest('Fake X') : const LineupPlayer.registered('SKX-10611')],
          sideANames: const ['You', 'Kamal Parmar'],
          sideBNames: [ 'Riya Shah', guest ? 'Fake X' : 'Dev Patel'],
          rules: const {'pointsToWin': 11, 'bestOf': 3},
          startedAt: now,
        );

    final result = CasualResult(games: const [(11, 7), (11, 9)], completedAt: DateTime(2026, 9, 27, 18, 40));

    test('a match only verifies once every other player confirms the result', () async {
      final created = await repo.create(doubles());
      expect(created.verification.lifecycle, MatchLifecycle.pendingConfirmation);
      expect(created.verification.isCreator, isTrue);

      final again = await repo.create(doubles());
      expect(again.id, created.id, reason: 'a retried create returns the same match');

      final submitted = await repo.submitResult(created.id, result);
      expect(submitted.verification.lifecycle, MatchLifecycle.completed);
      expect(submitted.verification.official, isFalse);

      now = now.add(SampleCasualVerificationRepository.answerAfter * 2);
      final partial = await repo.match(created.id);
      expect(partial.verification.lifecycle, MatchLifecycle.completed, reason: '3 of 4 confirmed is still pending');
      expect(partial.verification.waitingFor, hasLength(2));

      now = now.add(SampleCasualVerificationRepository.answerAfter * 5);
      final done = await repo.match(created.id);
      expect(done.verification.lifecycle, MatchLifecycle.verified);
      expect(done.verification.official, isTrue);
    });

    test('a match with a guest never verifies', () async {
      final created = await repo.create(doubles(ref: 'g', guest: true));
      await repo.submitResult(created.id, result);
      now = now.add(const Duration(hours: 1));
      final m = await repo.match(created.id);
      expect(m.verification.lifecycle, MatchLifecycle.unofficial);
      expect(m.verification.official, isFalse);
    });

    test('three requests are waiting for "You"', () async {
      final requests = await repo.requests();
      expect(requests.map((r) => r.id), containsAll(['cm-seed-1', 'cm-seed-2', 'cm-seed-3']));
    });

    test('accepting an older round is refused as stale', () async {
      await expectLater(
        repo.accept('cm-seed-1', 0),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'STALE_CONFIRMATION')),
      );
    });

    test('rejecting disputes or rejects the match, never verifies it', () async {
      final wrongScore = await repo.reject('cm-seed-1', 1, RejectionReason.wrongScore, note: 'It was 9–11');
      expect(wrongScore.verification.lifecycle, MatchLifecycle.disputed);
      final didNotPlay = await repo.reject('cm-seed-2', 1, RejectionReason.didNotPlay);
      expect(didNotPlay.verification.lifecycle, MatchLifecycle.rejected);
      expect((await repo.requests()).map((r) => r.id), ['cm-seed-3']);
    });

    test('accept all accepts each request on its own; a stale one fails alone', () async {
      final result = await repo.acceptAll([('cm-seed-1', 1), ('cm-seed-2', 0), ('cm-seed-3', 0)]);
      expect(result.accepted, 2);
      expect(result.failed.keys, ['cm-seed-2']);
    });

    test('a cancelled match cannot be accepted', () async {
      final created = await repo.create(doubles(ref: 'c'));
      await repo.cancel(created.id);
      expect((await repo.match(created.id)).verification.lifecycle, MatchLifecycle.cancelled);
    });
  });

  group('screens', () {
    setUp(useInMemoryPreferences);

    Future<void> open(WidgetTester tester, String route) async {
      usePhone(tester);
      useReducedMotion(tester);
      await tester.pumpWidget(ProviderScope(
        overrides: appOverrides(FakeAuthRepository(stored: RestoredUser(user(), fromCache: false))),
        child: const SkorxApp(),
      ));
      await tester.pumpAndSettle();
      await goTo(tester, route);
    }

    testWidgets('a player reviews and accepts a match request', (tester) async {
      await open(tester, '/player/match-requests/cm-seed-1');
      expect(find.text('Match confirmation'), findsOneWidget);
      expect(find.text('Awaiting your confirmation'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Verification progress'), 300, scrollable: find.byType(Scrollable).last);
      expect(find.text('Verification progress'), findsOneWidget);

      await tester.tap(find.byKey(const Key('acceptMatch')));
      await tester.pumpAndSettle();
      expect(find.text('Confirm match participation'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirmMatch')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Match accepted'), -300, scrollable: find.byType(Scrollable).last);
      expect(find.text('Match accepted'), findsOneWidget);
      expect(find.byKey(const Key('acceptMatch')), findsNothing);
    });

    testWidgets('a player disputes with a reason', (tester) async {
      await open(tester, '/player/match-requests/cm-seed-2');
      await tester.tap(find.byKey(const Key('rejectMatch')));
      await tester.pumpAndSettle();
      expect(find.text('Why are you rejecting this match?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('reason-wrong_score')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('submitDispute')));
      await tester.pumpAndSettle();
      expect(find.text('Dispute sent'), findsOneWidget);
      expect(find.text('Disputed'), findsWidgets);
    });

    testWidgets('match requests have their own tab with Accept all', (tester) async {
      await open(tester, '/player/notifications?tab=requests');
      expect(find.byKey(const Key('request-cm-seed-1')), findsOneWidget);
      expect(find.byKey(const Key('acceptAll')), findsOneWidget);
      await tester.tap(find.byKey(const Key('acceptAll')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmAcceptAll')));
      await tester.pumpAndSettle();
      expect(find.text('No match requests'), findsOneWidget);
    });
  });
}
