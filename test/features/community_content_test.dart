import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skorx/app/app.dart';
import 'package:skorx/core/api/api_exception.dart';
import 'package:skorx/features/auth/data/auth_repository.dart';
import 'package:skorx/features/auth/data/current_user.dart';
import 'package:skorx/features/community/data/community.dart';
import 'package:skorx/features/community/data/community_json.dart';
import 'package:skorx/features/community/data/content.dart';
import 'package:skorx/features/community/data/sample_community.dart';

import '../support/fakes.dart';
import 'player_app_test.dart' show goTo, pageScroll, pumpSignedIn, routerOf, tapVisible, usePhone;

String locationOf(WidgetTester tester) => routerOf(tester).state.uri.toString();

/// Signed in as someone who runs tournaments for an organisation.
Future<void> pumpOrganiser(WidgetTester tester) async {
  useReducedMotion(tester);
  final organiser = user(memberships: const [
    Membership(organizationId: 'org-cadlete', organizationName: 'CADLETE', role: 'owner', capabilities: {}),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: appOverrides(FakeAuthRepository(stored: RestoredUser(organiser, fromCache: false))),
    child: const SkorxApp(),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(useInMemoryPreferences);

  group('reads the Community API', () {
    test('a member with role reputation, never a phone number', () {
      final m = memberFromJson({
        'id': 'u1',
        'name': 'Bharat Referee',
        'city': 'Vadodara',
        'state': 'Gujarat',
        'headline': null,
        'playerId': 'pp1',
        'tags': [],
        'languages': ['Gujarati'],
        'serviceArea': ['Ahmedabad'],
        'availability': 'open',
        'acceptsMessagesFrom': 'connections',
        'mutualConnections': 2,
        'placeIds': [],
        'groupIds': ['g1'],
        'roles': [
          {
            'role': 'referee',
            'verified': true,
            'since': 2021,
            'highlights': [],
            'metrics': [
              {'label': 'Organiser feedback', 'value': '100% positive (1)'},
            ],
          },
          {'role': 'astronaut', 'verified': false, 'metrics': []},
        ],
      });
      expect(m.primaryRole, CommunityRole.referee);
      expect(m.roles, hasLength(1), reason: 'unknown roles are skipped');
      expect(m.verifiedAs(CommunityRole.referee), isTrue);
      expect(m.record(CommunityRole.referee)!.metrics.single, ('Organiser feedback', '100% positive (1)'));
      expect(m.availability, Availability.open);
      expect(m.acceptsMessagesFrom, MessagePermission.connections);
      expect(m.serviceArea, ['Ahmedabad']);
    });

    test('my graph, with saved types and the communities I run', () {
      final g = graphFromJson({
        'connections': {'a': 'connected', 'b': 'pendingIn', 'c': 'nonsense'},
        'following': ['p1'],
        'groups': {'g1': 'member', 'g2': 'requested'},
        'adminOf': ['g1'],
        'blocked': ['x'],
        'saved': [
          {'type': 'place', 'id': 'p1'},
          {'type': 'member', 'id': 'a'},
        ],
      });
      expect(g.connectionWith('a'), ConnectionStatus.connected);
      expect(g.incomingCount, 1);
      expect(g.connections.containsKey('c'), isFalse);
      expect(g.admins('g1'), isTrue);
      expect(g.savedOf(CommunityTarget.place), ['p1']);
      expect(g.hasBlocked('x'), isTrue);
    });

    test('events, posts, conversations and messages', () {
      final e = eventFromJson({
        'id': 'e1',
        'kind': 'open_play',
        'title': 'Sunday open play',
        'about': '',
        'startsAt': '2026-10-04T00:30:00.000Z',
        'endsAt': '2026-10-04T03:30:00.000Z',
        'city': 'Ahmedabad',
        'organizer': {'id': 'u1', 'name': 'Asha'},
        'capacity': 2,
        'going': 2,
        'interested': 1,
        'myRsvp': null,
        'cancelled': false,
        'mine': false,
      });
      expect(e.kind, EventKind.openPlay);
      expect(e.full, isTrue);
      final p = postFromJson({
        'id': 'p1',
        'kind': 'tip',
        'body': 'Paddle up',
        'link': '/player/tournament/t-open',
        'author': {'id': 'u1', 'name': 'Asha', 'photoUrl': null},
        'place': null,
        'group': {'id': 'g1', 'name': 'Open Play'},
        'event': null,
        'likes': 1,
        'comments': 0,
        'likedByMe': true,
        'savedByMe': false,
        'mine': false,
        'hidden': false,
        'at': '2026-09-27T16:52:05.838Z',
      });
      expect((p.kind, p.groupName, p.likedByMe), (PostKind.tip, 'Open Play', true));
      final c = conversationFromJson({
        'id': 'c1',
        'kind': 'direct',
        'targetId': 'u2',
        'title': 'Dev',
        'lastText': 'Hi',
        'lastAt': '2026-09-27T16:52:05.838Z',
        'unread': 1,
        'request': true,
        'awaitingReply': false,
      });
      expect((c.request, c.unread), (true, 1));
      final m = messageFromJson({'id': 'm1', 'conversationId': 'c1', 'senderId': 'me', 'senderName': 'Asha', 'text': 'Hi', 'at': '2026-09-27T16:52:05.838Z'});
      expect(m.mine, isTrue);
    });
  });

  group('sample events and posts follow the server rules', () {
    test('RSVP, capacity and cancelling', () async {
      final repo = SampleCommunityRepository();
      final clinic = await repo.rsvp('ev-clinic', RsvpStatus.going);
      expect((clinic.going, clinic.myRsvp), (10, RsvpStatus.going));
      expect((await repo.rsvp('ev-clinic', null)).going, 9);
      await expectLater(repo.rsvp('ev-women', RsvpStatus.going), throwsA(isA<ApiException>()));
      expect((await repo.rsvp('ev-women', RsvpStatus.interested)).interested, 6);
      final mine = await repo.createEvent(EventDraft(
        kind: EventKind.openPlay,
        title: 'Test open play',
        startsAt: DateTime.now().add(const Duration(days: 1)),
        endsAt: DateTime.now().add(const Duration(days: 1, hours: 2)),
        city: 'Ahmedabad',
      ));
      expect((mine.mine, mine.going), (true, 1));
      await repo.cancelEvent(mine.id);
      expect((await repo.events(city: 'Ahmedabad')).map((e) => e.id), isNot(contains(mine.id)));
      await expectLater(repo.cancelEvent('ev-clinic'), throwsA(isA<ApiException>()), reason: 'only the organiser');
    });

    test('the network feed: connections, followed places, my groups; never blocked authors', () async {
      final repo = SampleCommunityRepository();
      final ids = (await repo.feed(FeedScope.network)).posts.map((p) => p.id).toSet();
      expect(ids, containsAll(['ps-tip', 'ps-win', 'ps-club', 'ps-amd']));
      expect(ids, isNot(contains('ps-refs')), reason: 'not in Gujarat Referees, not following Hetal');
      await repo.block('cm-kavya', on: true);
      expect((await repo.feed(FeedScope.network)).posts.map((p) => p.id), isNot(contains('ps-tip')));
    });

    test('likes count once; comments add up; links stay inside SkorX', () async {
      final repo = SampleCommunityRepository();
      expect(await repo.like('ps-tip', on: true), 32);
      expect(await repo.like('ps-tip', on: true), 32);
      expect(await repo.like('ps-tip', on: false), 31);
      await repo.comment('ps-tip', 'Great drill');
      expect((await repo.feed(FeedScope.network)).posts.firstWhere((p) => p.id == 'ps-tip').comments, 5);
      await expectLater(repo.createPost(kind: PostKind.tip, body: 'x', link: 'https://evil.example'), throwsA(isA<ApiException>()));
      await expectLater(repo.createPost(kind: PostKind.tip, body: 'x', groupId: 'g-coaches'), throwsA(isA<ApiException>()),
          reason: 'not a member');
    });

    test('verification is per saved role, one request at a time', () async {
      final repo = SampleCommunityRepository();
      await expectLater(repo.requestVerification(role: CommunityRole.referee, evidence: 'Level 2 referee, 18 events.'),
          throwsA(isA<ApiException>()), reason: 'not one of my roles');
      await repo.saveProfile(const MyCommunityProfile(roles: {CommunityRole.player, CommunityRole.referee}));
      await expectLater(repo.requestVerification(role: CommunityRole.referee, evidence: 'too short'), throwsA(isA<ApiException>()));
      final v = await repo.requestVerification(role: CommunityRole.referee, evidence: 'Level 2 referee, 18 events worked.');
      expect(v.status, VerificationStatus.pending);
      await expectLater(repo.requestVerification(role: CommunityRole.referee, evidence: 'Level 2 referee, 18 events worked.'),
          throwsA(isA<ApiException>()));
    });

    test('organiser feedback becomes role reputation', () async {
      final repo = SampleCommunityRepository();
      await repo.feedback(memberId: 'cm-imran', role: CommunityRole.referee, recommend: true, onTime: true);
      final m = await repo.member('cm-imran');
      expect(m.record(CommunityRole.referee)!.metrics, contains(('Organiser feedback', '100% positive (1)')));
      await expectLater(repo.feedback(memberId: 'cm-imran', role: CommunityRole.coach, recommend: true), throwsA(isA<ApiException>()));
    });

    test('admins see and decide join requests', () async {
      final repo = SampleCommunityRepository();
      expect((await repo.groupRequests('g-bodakdev')).map((m) => m.id), ['cm-nisha', 'cm-parth']);
      await repo.decideGroupRequest('g-bodakdev', 'cm-nisha', approve: true);
      expect((await repo.groupRequests('g-bodakdev')).map((m) => m.id), ['cm-parth']);
      await expectLater(repo.groupRequests('g-amd'), throwsA(isA<ApiException>()), reason: 'not an admin there');
    });
  });

  group('screens', () {
    testWidgets('an event: RSVP, then the event chat', (tester) async {
      usePhone(tester);
      await pumpSignedIn(tester);
      await goTo(tester, '/player/community/events/ev-clinic');
      expect(find.text('Beginner clinic: dinks and resets'), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('rsvpGoing')));
      expect(find.text("You're going. See you there!"), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('eventChat')));
      expect(locationOf(tester), startsWith('/player/community/messages/'));
    });

    testWidgets('a full event cannot be joined, only watched', (tester) async {
      usePhone(tester);
      await pumpSignedIn(tester);
      await goTo(tester, '/player/community/events/ev-women');
      await tester.scrollUntilVisible(find.byKey(const Key('rsvpGoing')), 200, scrollable: pageScroll);
      expect(find.text('Full'), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('rsvpInterested')));
      expect(find.text('Interested · Undo'), findsOneWidget);
    });

    testWidgets('host an event', (tester) async {
      usePhone(tester);
      await pumpSignedIn(tester);
      await goTo(tester, '/player/community/events/new');
      await tester.enterText(find.byKey(const Key('eventTitle')), 'Paldi evening doubles');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('createEvent')));
      await tester.pumpAndSettle();
      expect(locationOf(tester), startsWith('/player/community/events/ev-new-'));
      expect(find.text('Paldi evening doubles'), findsOneWidget);
      expect(find.text("You're hosting this event."), findsOneWidget);
    });

    testWidgets('write a post and like one', (tester) async {
      usePhone(tester);
      await pumpSignedIn(tester);
      await goTo(tester, '/player/community/posts');
      await tester.tap(find.byKey(const Key('newPost')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('postBody')), 'Great session at Blitz tonight!');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('submitPost')));
      await tester.pumpAndSettle();
      expect(find.text('Great session at Blitz tonight!'), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('like-ps-tip')));
      expect(find.bySemanticsLabel('Unlike, 32 likes'), findsOneWidget);
    });

    testWidgets('comment on a post', (tester) async {
      usePhone(tester);
      await pumpSignedIn(tester);
      await goTo(tester, '/player/community/posts/ps-win');
      await tester.enterText(find.byKey(const Key('commentField')), 'Well played!');
      await tester.tap(find.byKey(const Key('sendComment')));
      await tester.pumpAndSettle();
      expect(find.text('Well played!'), findsOneWidget);
    });

    testWidgets('a community admin lets someone in', (tester) async {
      usePhone(tester);
      await pumpSignedIn(tester);
      await goTo(tester, '/player/community/groups/g-bodakdev');
      await tester.scrollUntilVisible(find.byKey(const Key('approveJoin-cm-nisha')), 250, scrollable: pageScroll);
      await tester.tap(find.byKey(const Key('approveJoin-cm-nisha')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('joinRequest-cm-nisha')), findsNothing);
      expect(find.byKey(const Key('joinRequest-cm-parth')), findsOneWidget);
    });

    testWidgets('ask SkorX to verify a role', (tester) async {
      usePhone(tester);
      await pumpSignedIn(tester);
      await goTo(tester, '/player/community/me');
      await tester.tap(find.byKey(const Key('myRole-referee')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('saveMyCommunity')));
      await tester.pumpAndSettle();
      await goTo(tester, '/player/community/me');
      await tapVisible(tester, find.byKey(const Key('verify-referee')));
      await tester.enterText(find.byKey(const Key('verifyEvidence')), 'Level 2 referee, 18 tournaments across Gujarat.');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('submitVerification')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byKey(const Key('verify-referee')), 250, scrollable: pageScroll);
      expect(find.text('With the SkorX team'), findsOneWidget);
    });

    testWidgets('organisers rate officials; players do not see the button', (tester) async {
      usePhone(tester);
      await pumpSignedIn(tester);
      await goTo(tester, '/player/community/people/cm-imran');
      expect(find.byKey(const Key('rate-referee')), findsNothing);
    });

    testWidgets('an organiser leaves feedback and it shows on the profile', (tester) async {
      usePhone(tester);
      await pumpOrganiser(tester);
      await goTo(tester, '/player/community/people/cm-imran');
      await tapVisible(tester, find.byKey(const Key('rate-referee')));
      await tester.tap(find.byKey(const Key('recommend-yes')));
      await tester.tap(find.byKey(const Key('onTime-yes')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('submitFeedback')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('100% positive (1)'), 250, scrollable: pageScroll);
      expect(find.text('100% positive (1)'), findsOneWidget);
    });

    testWidgets('the hub shows sessions and my network', (tester) async {
      usePhone(tester);
      await pumpSignedIn(tester);
      await goTo(tester, '/player/community');
      await tester.scrollUntilVisible(find.byKey(const Key('eventCard-ev-clinic')), 300, scrollable: pageScroll);
      await tester.scrollUntilVisible(find.byKey(const Key('writePost')), 300, scrollable: pageScroll);
      expect(find.text('From your network'), findsOneWidget);
    });
  });
}
