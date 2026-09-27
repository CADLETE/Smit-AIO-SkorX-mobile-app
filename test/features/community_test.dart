import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skorx/core/api/api_exception.dart';
import 'package:skorx/core/sample_persona.dart';
import 'package:skorx/features/community/data/community.dart';
import 'package:skorx/features/community/data/community_query.dart';
import 'package:skorx/features/community/data/messages.dart';
import 'package:skorx/features/community/data/personalize.dart';
import 'package:skorx/features/community/data/sample_community.dart';

import '../support/fakes.dart' show useInMemoryPreferences;
import 'player_app_test.dart' show goTo, openCommunity, pageScroll, pumpSignedIn, routerOf, tapNav, tapVisible, usePhone;

/// The top-most location, including screens pushed over the tabs.
String locationOf(WidgetTester tester) => routerOf(tester).state.uri.toString();

Future<void> typeSearch(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('communitySearchField')), text);
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pumpAndSettle();
}

void main() {
  setUp(useInMemoryPreferences);

  group('search understands plain sentences', () {
    test('the spec examples', () {
      var q = CommunityQuery.parse('Find a referee near Ahmedabad');
      expect(q.roles, {CommunityRole.referee});
      expect(q.city, 'Ahmedabad');
      expect(q.text, isEmpty);

      q = CommunityQuery.parse('Find scorekeepers in Gujarat');
      expect(q.roles, {CommunityRole.scorekeeper});
      expect(q.state, 'Gujarat');
      expect(q.city, isNull);

      q = CommunityQuery.parse('Pickleball academy near me');
      expect(q.kinds, {PlaceKind.academy});
      expect(q.nearMe, isTrue);
      expect(q.resolveNearMe('Surat').city, 'Surat');
      expect(q.resolveNearMe(null).city, isNull, reason: 'no location: never guessed');

      q = CommunityQuery.parse('Indoor pickleball courts Ahmedabad');
      expect(q.kinds, {PlaceKind.venue});
      expect(q.setting, PlaceSetting.indoor);
      expect(q.city, 'Ahmedabad');

      q = CommunityQuery.parse('Tournament organizers India');
      expect(q.roles, {CommunityRole.organizer});
      expect(q.text, isEmpty);

      expect(CommunityQuery.parse('Pickleball streamer').roles, {CommunityRole.streamer});

      q = CommunityQuery.parse('Coach for beginner training');
      expect(q.roles, {CommunityRole.coach});
      expect(q.level, 'Beginner');

      q = CommunityQuery.parse('doubles partner Surat');
      expect(q.roles, {CommunityRole.player});
      expect(q.tag, 'Doubles');
      expect(q.city, 'Surat');

      q = CommunityQuery.parse('score keeper, verified');
      expect(q.roles, {CommunityRole.scorekeeper});
      expect(q.verifiedOnly, isTrue);
    });

    test('unknown words stay as text and match names', () {
      final q = CommunityQuery.parse('rohan');
      expect(q.text, 'rohan');
      expect(sampleMembers.where(q.matchesMember).map((m) => m.id), ['cm-rohan']);
    });

    test('a referee who travels to a city is found there', () {
      final q = CommunityQuery.parse('referee near Ahmedabad');
      final ids = sampleMembers.where(q.matchesMember).map((m) => m.id).toSet();
      expect(ids, containsAll(['cm-hetal', 'cm-rohan']), reason: 'Rohan lives in Vadodara but works in Ahmedabad');
      expect(ids, isNot(contains('cm-imran')), reason: 'Imran works in Surat only');
      expect(samplePlaces.where(q.matchesPlace), isEmpty, reason: 'asking for people shows no places');
    });

    test('filters narrow people and places', () {
      final verified = const CommunityQuery(roles: {CommunityRole.referee}, verifiedOnly: true);
      expect(sampleMembers.where(verified.matchesMember).every((m) => m.verifiedAs(CommunityRole.referee)), isTrue);

      const available = CommunityQuery(roles: {CommunityRole.referee}, availableOnly: true);
      expect(sampleMembers.where(available.matchesMember).map((m) => m.id), isNot(contains('cm-imran')));

      final outdoor = CommunityQuery.parse('outdoor courts');
      expect(samplePlaces.where(outdoor.matchesPlace).map((p) => p.id), ['pl-riverside']);

      const gujarati = CommunityQuery(language: 'Gujarati', roles: {CommunityRole.commentator});
      expect(sampleMembers.where(gujarati.matchesMember).map((m) => m.id), ['cm-mihir']);
    });

    test('sample links point at real sample data', () {
      final memberIds = {for (final m in sampleMembers) m.id};
      final placeIds = {for (final p in samplePlaces) p.id};
      final groupIds = {for (final g in sampleGroups) g.id};
      expect(memberIds.length, sampleMembers.length, reason: 'unique member ids');
      for (final m in sampleMembers) {
        expect(m.roles, isNotEmpty, reason: m.id);
        expect(placeIds.containsAll(m.placeIds), isTrue, reason: m.id);
        expect(groupIds.containsAll(m.groupIds), isTrue, reason: m.id);
      }
      for (final p in samplePlaces) {
        expect(memberIds.containsAll(p.staffIds), isTrue, reason: p.id);
      }
    });
  });

  group('the server rules, in the sample repository', () {
    test('connect, accept, withdraw', () async {
      final repo = SampleCommunityRepository();
      expect(await repo.connect('cm-diya'), ConnectionStatus.pendingOut);
      expect(await repo.connect('cm-meera'), ConnectionStatus.connected, reason: 'she asked first: connecting accepts');
      await repo.disconnect('cm-diya');
      expect((await repo.graph()).connectionWith('cm-diya'), ConnectionStatus.none);
    });

    test('blocking hides both ways and stops messages', () async {
      final repo = SampleCommunityRepository();
      await repo.block('cm-kavya', on: true);
      final g = await repo.graph();
      expect(g.connectionWith('cm-kavya'), ConnectionStatus.none, reason: 'the connection goes');
      expect(await repo.members(const CommunityQuery(text: 'kavya')), isEmpty);
      expect((await repo.conversations()).where((c) => c.targetId == 'cm-kavya'), isEmpty);
      await expectLater(repo.openConversation(ConversationKind.direct, 'cm-kavya'),
          throwsA(isA<ApiException>().having((e) => e.code, 'code', 'BLOCKED')));
      await expectLater(repo.connect('cm-kavya'), throwsA(isA<ApiException>()));
    });

    test('someone who takes messages from connections only cannot be messaged cold', () async {
      final repo = SampleCommunityRepository();
      await expectLater(repo.openConversation(ConversationKind.direct, 'cm-hetal'),
          throwsA(isA<ApiException>().having((e) => e.code, 'code', 'MESSAGES_RESTRICTED')));
    });

    test('a cold message waits for a reply before the next', () async {
      final repo = SampleCommunityRepository();
      final c = await repo.openConversation(ConversationKind.direct, 'cm-diya');
      expect(c.awaitingReply, isTrue);
      await repo.send(c.id, 'Hi Diya, fancy a hit on Saturday?');
      await expectLater(repo.send(c.id, 'Are you there?'),
          throwsA(isA<ApiException>().having((e) => e.code, 'code', 'AWAITING_REPLY')));
      // Connected people can write freely.
      final k = await repo.openConversation(ConversationKind.direct, 'cm-kavya');
      await repo.send(k.id, 'See you at 7');
      await repo.send(k.id, 'Bringing balls too');
      expect((await repo.messages(k.id)).where((m) => m.mine).length, 2 + 1);
    });

    test('messages are checked', () async {
      final repo = SampleCommunityRepository();
      await expectLater(repo.send('cv-kavya', '   '), throwsA(isA<ApiException>()));
      await expectLater(repo.send('cv-kavya', 'x' * (maxMessageLength + 1)), throwsA(isA<ApiException>()));
    });

    test('group chats are for members', () async {
      final repo = SampleCommunityRepository();
      await expectLater(repo.openConversation(ConversationKind.group, 'g-coaches'), throwsA(isA<ApiException>()));
      expect((await repo.openConversation(ConversationKind.group, 'g-amd')).id, 'cv-g-amd');
    });

    test('public groups let you in; private ones take a request', () async {
      final repo = SampleCommunityRepository();
      expect(await repo.joinGroup('g-women'), GroupStatus.member);
      expect(await repo.joinGroup('g-organisers'), GroupStatus.requested);
    });

    test('creating a community', () async {
      final repo = SampleCommunityRepository();
      await expectLater(repo.createGroup(name: 'ab', about: '', access: GroupAccess.public), throwsA(isA<ApiException>()));
      await expectLater(repo.createGroup(name: 'Ahmedabad pickleball', about: '', access: GroupAccess.public),
          throwsA(isA<ApiException>().having((e) => e.code, 'code', 'DUPLICATE')));
      await expectLater(repo.createGroup(name: 'Official refs', about: '', access: GroupAccess.verified),
          throwsA(isA<ApiException>().having((e) => e.code, 'code', 'FORBIDDEN')));
      final g = await repo.createGroup(name: 'Paldi Evening Crew', about: '6 AM doubles', access: GroupAccess.private, city: 'Ahmedabad');
      expect((await repo.graph()).groupStatus(g.id), GroupStatus.member, reason: 'the creator is in');
      expect((await repo.groups(city: 'Ahmedabad')).map((x) => x.id), contains(g.id));
    });

    test('reports are filed, never sent to the person', () async {
      final repo = SampleCommunityRepository();
      await repo.report(ReportTarget.member, 'cm-imran', ReportReason.spam);
      expect(repo.reports.single, (ReportTarget.member, 'cm-imran', ReportReason.spam));
    });

    test('suggestions skip people already connected or pending, and say why', () async {
      final repo = SampleCommunityRepository();
      final list = await repo.suggestions(city: 'Ahmedabad', forRoles: const {CommunityRole.player});
      final ids = list.map((s) => s.member.id);
      expect(ids, isNot(contains('cm-kavya')), reason: 'connected');
      expect(ids, isNot(contains('cm-meera')), reason: 'asked to connect');
      expect(list.every((s) => s.reason.isNotEmpty), isTrue);
      final organiser = await repo.suggestions(city: 'Ahmedabad', forRoles: const {CommunityRole.organizer});
      expect(organiser.first.member.roles.any((r) => rolesOfInterest({CommunityRole.organizer}).contains(r.role)), isTrue,
          reason: 'an organiser is shown officials and media first');
    });
  });

  test('the hub leads with what each role needs', () {
    expect(sectorsFor({CommunityRole.player}).take(2), [CommunitySector.players, CommunitySector.training]);
    expect(sectorsFor({CommunityRole.organizer}).first, CommunitySector.officials);
    expect(sectorsFor({CommunityRole.referee}).first, CommunitySector.organizers);
    expect(sectorsFor({CommunityRole.streamer}).first, CommunitySector.organizers);
    for (final roles in [<CommunityRole>{}, {CommunityRole.coach, CommunityRole.photographer}]) {
      expect(sectorsFor(roles).toSet(), CommunitySector.values.toSet(), reason: 'every sector stays');
    }
  });

  group('Community tab', () {
    testWidgets('opens from Explore, whose tab carries the badge, and shows what is near', (tester) async {
      usePhone(tester);
      await pumpSignedIn(tester);
      expect(find.byKey(const Key('navBadge-Explore')), findsOneWidget, reason: 'a request and unread messages');
      await openCommunity(tester);
      expect(locationOf(tester), '/player/community');
      expect(find.text('Connect. Discover. Collaborate. Grow pickleball.'), findsOneWidget);
      expect(find.byKey(const Key('requestsBanner')), findsOneWidget);
      for (final title in [
        'People you may know',
        'Communities near you',
        'Places to play in Ahmedabad',
        'Clinics, open play & meetups',
        'From your network',
        'Tournaments',
      ]) {
        await tester.scrollUntilVisible(find.text(title), 250, scrollable: pageScroll);
        expect(find.text(title), findsOneWidget, reason: title);
      }
    });

    testWidgets('a sector opens inside the tab with its roles as chips', (tester) async {
      usePhone(tester);
      await pumpSignedIn(tester);
      await openCommunity(tester);
      // A player's strip leads with players; officials are further along.
      await tester.dragUntilVisible(
          find.byKey(const Key('sector-officials')), find.byKey(const Key('sector-players')), const Offset(-200, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sector-officials')));
      await tester.pumpAndSettle();
      expect(locationOf(tester), '/player/community/browse/officials');
      expect(find.text('Hetal Parikh'), findsOneWidget);
      await tester.dragUntilVisible(
          find.byKey(const Key('chip-scorekeeper')), find.byKey(const Key('chip-all')), const Offset(-150, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chip-scorekeeper')));
      await tester.pumpAndSettle();
      expect(find.text('Sameer Qureshi'), findsOneWidget);
      expect(find.text('Hetal Parikh'), findsNothing);
      await tester.tap(find.byKey(const Key('communityBack')));
      await tester.pumpAndSettle();
      expect(locationOf(tester), '/player/community');
    });

    testWidgets('search: "referee near Ahmedabad" finds the referees who work there', (tester) async {
      usePhone(tester);
      await pumpSignedIn(tester);
      await openCommunity(tester);
      await tester.tap(find.byKey(const Key('communitySearch')));
      await tester.pumpAndSettle();
      await typeSearch(tester, 'referee near Ahmedabad');
      expect(find.text('Showing referees in Ahmedabad'), findsOneWidget);
      expect(find.text('Rohan Desai'), findsOneWidget);
      expect(find.text('Hetal Parikh'), findsOneWidget);
      expect(find.text('Imran Sheikh'), findsNothing);

      await typeSearch(tester, 'underwater hockey');
      expect(find.byKey(const Key('communityNoResults')), findsOneWidget);
    });

    testWidgets('connect from a profile: Connect → Pending → withdraw', (tester) async {
      usePhone(tester);
      await pumpSignedIn(tester);
      await goTo(tester, '/player/community/people/cm-diya');
      expect(find.text('Diya Joshi'), findsOneWidget);
      await tester.tap(find.byKey(const Key('connect-cm-diya')));
      await tester.pumpAndSettle();
      expect(find.text('Pending'), findsOneWidget);
      await tester.tap(find.byKey(const Key('connect-cm-diya')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Withdraw'));
      await tester.pumpAndSettle();
      expect(find.text('Connect'), findsOneWidget);
    });

    testWidgets('accepting a request clears the badge', (tester) async {
      usePhone(tester);
      await pumpSignedIn(tester);
      await goTo(tester, '/player/community/connections?tab=requests');
      expect(find.text('Meera Iyer'), findsOneWidget);
      await tester.tap(find.byKey(const Key('connect-cm-meera')));
      await tester.pumpAndSettle();
      expect(find.text('Connected'), findsOneWidget, reason: 'the row stays and shows its new state');
      await goTo(tester, '/player/community');
      expect(find.byKey(const Key('requestsBanner')), findsNothing);
    });

    testWidgets('a role profile shows its evidence and links to the player\'s SkorX stats', (tester) async {
      usePhone(tester);
      await pumpSignedIn(tester);
      await goTo(tester, '/player/community/people/cm-rohan');
      expect(find.text('Referee'), findsWidgets);
      await tester.scrollUntilVisible(find.byKey(const Key('role-referee')), 250, scrollable: pageScroll);
      expect(find.text('Verified by SkorX'), findsOneWidget);
      expect(find.text('312'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Full stats'), -250, scrollable: pageScroll);
      await tester.tap(find.text('Full stats'));
      await tester.pumpAndSettle();
      expect(locationOf(tester), '/player/players/SKX-10291');
    });

    testWidgets('messaging someone new: one message, then wait for a reply', (tester) async {
      usePhone(tester);
      await pumpSignedIn(tester);
      await goTo(tester, '/player/community/people/cm-diya');
      await tester.tap(find.byKey(const Key('messageMember')));
      await tester.pumpAndSettle();
      expect(locationOf(tester), startsWith('/player/community/messages/'));
      await tester.enterText(find.byKey(const Key('composer')), 'Hi Diya! Singles on Sunday?');
      await tester.pump();
      await tester.tap(find.byKey(const Key('send')));
      await tester.pumpAndSettle();
      expect(find.text('Hi Diya! Singles on Sunday?'), findsOneWidget);
      expect(find.byKey(const Key('awaitingReply')), findsOneWidget);
    });

    testWidgets('someone who takes messages from connections only says so', (tester) async {
      usePhone(tester);
      await pumpSignedIn(tester);
      await goTo(tester, '/player/community/people/cm-hetal');
      await tester.tap(find.byKey(const Key('messageMember')));
      await tester.pumpAndSettle();
      expect(find.textContaining('takes messages from connections only'), findsOneWidget);
      expect(locationOf(tester), '/player/community/people/cm-hetal');
    });

    testWidgets('a message request: accept to reply', (tester) async {
      usePhone(tester);
      await pumpSignedIn(tester);
      await goTo(tester, '/player/community/messages?tab=requests');
      await tester.tap(find.byKey(const Key('conversation-cv-rohan')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('composer')), findsNothing, reason: 'no reply until accepted');
      await tester.tap(find.byKey(const Key('acceptRequest')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('composer')), findsOneWidget);
    });

    testWidgets('block from a profile, then unblock', (tester) async {
      usePhone(tester);
      await pumpSignedIn(tester);
      await goTo(tester, '/player/community/people/cm-imran');
      await tester.tap(find.byKey(const Key('overflow')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('menu-Block')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmBlock')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('blockedProfile')), findsOneWidget);
      await tester.tap(find.byKey(const Key('unblock')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('blockedProfile')), findsNothing);
    });

    testWidgets('report a profile', (tester) async {
      usePhone(tester);
      await pumpSignedIn(tester);
      await goTo(tester, '/player/community/people/cm-imran');
      await tester.tap(find.byKey(const Key('overflow')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('menu-Report')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('report-spam')));
      await tester.pumpAndSettle();
      expect(find.text('Thanks. Our team will review this report.'), findsOneWidget);
    });

    testWidgets('a venue page books through the courts module', (tester) async {
      usePhone(tester);
      await pumpSignedIn(tester);
      await goTo(tester, '/player/community/places/pl-blitz');
      expect(find.text('Pickle Blitz Arena'), findsWidgets);
      await tester.tap(find.byKey(const Key('bookCourt')));
      await tester.pumpAndSettle();
      expect(locationOf(tester), '/player/venue/v-blitz');
    });

    testWidgets('an academy enquiry opens a message with a draft, never sent without a tap', (tester) async {
      usePhone(tester);
      await pumpSignedIn(tester);
      await goTo(tester, '/player/community/places/pl-smashacad');
      await tapVisible(tester, find.byKey(const Key('program-Start pickleball')));
      expect(locationOf(tester), startsWith('/player/community/messages/'));
      final field = tester.widget<TextField>(find.byKey(const Key('composer')));
      expect(field.controller!.text, contains('Start pickleball'));
    });

    testWidgets('a club page lists its tournaments from the TMS', (tester) async {
      usePhone(tester);
      await pumpSignedIn(tester);
      await goTo(tester, '/player/community/places/pl-cadlete');
      await tapVisible(tester, find.byKey(const Key('placeTournament-t-monsoon')));
      expect(locationOf(tester), '/player/tournament/t-monsoon');
    });

    testWidgets('communities: join a public one, ask to join a private one', (tester) async {
      usePhone(tester);
      await pumpSignedIn(tester);
      await goTo(tester, '/player/community/groups/g-women');
      await tester.tap(find.byKey(const Key('joinGroup')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('groupChat')), findsOneWidget);
      await goTo(tester, '/player/community/groups/g-organisers');
      expect(find.text('Ask to join'), findsOneWidget);
      await tester.tap(find.byKey(const Key('joinGroup')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cancelGroupRequest')), findsOneWidget);
    });

    testWidgets('start a community', (tester) async {
      usePhone(tester);
      await pumpSignedIn(tester);
      await goTo(tester, '/player/community/groups');
      await tester.tap(find.byKey(const Key('createGroup')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('groupName')), 'Paldi Evening Crew');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('createGroupSubmit')));
      await tester.pumpAndSettle();
      expect(locationOf(tester), startsWith('/player/community/groups/g-new-'));
      expect(find.text('Paldi Evening Crew'), findsOneWidget);
    });

    testWidgets('a new member picks several roles and the hub changes for them', (tester) async {
      usePhone(tester);
      await pumpSignedIn(tester, persona: SamplePersona.newcomer);
      await openCommunity(tester);
      expect(find.byKey(const Key('navBadge-Explore')), findsNothing, reason: 'nothing waiting for a new member');
      await tester.tap(find.byKey(const Key('chooseRoles')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('myRole-referee')));
      await tester.tap(find.byKey(const Key('myRole-organizer')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('saveMyCommunity')));
      await tester.pumpAndSettle();
      expect(locationOf(tester), '/player/community');
      expect(find.byKey(const Key('chooseRoles')), findsNothing, reason: 'asked once');
      expect(find.text('Officials, streamers and venues for your next event.'), findsOneWidget);
    });

    testWidgets('Account links to my side of Community', (tester) async {
      usePhone(tester);
      await pumpSignedIn(tester);
      await tapNav(tester, 'Account');
      await tapVisible(tester, find.byKey(const Key('myConnectionsRow')));
      expect(locationOf(tester), '/player/community/connections?tab=requests');
    });
  });
}
