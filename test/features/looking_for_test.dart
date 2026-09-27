import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skorx/features/looking_for/data/looking_for.dart';
import 'package:skorx/features/looking_for/data/sample_looking_for.dart';
import 'package:skorx/features/notifications/notifications.dart';

import '../support/fakes.dart' show useInMemoryPreferences;
import 'package:skorx/features/looking_for/ui/looking_for_home_page.dart';

import 'player_app_test.dart' show goTo, openExplore, pageScroll, pumpSignedIn, routerOf, tapVisible, usePhone;

String locationOf(WidgetTester tester) => routerOf(tester).routerDelegate.currentConfiguration.uri.toString();

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUp(useInMemoryPreferences);

  group('API shapes', () {
    // Captured from the running API (backend src/looking-for) against PostgreSQL.
    final fixture = jsonDecode(File('test/fixtures/looking_for_api.json').readAsStringSync()) as Map<String, dynamic>;

    test('a feed item parses with every field', () {
      final p = LfPost.fromJson(fixture['feedItem'] as Map<String, dynamic>);
      expect(p.categoryId, 'referee');
      expect(p.subcategoryLabel, 'Referee');
      expect(p.status, LfStatus.partiallyFilled);
      expect(p.fillLabel, '1 of 2 filled');
      expect(p.paymentLabel, 'Paid · ₹1,500 per day');
      expect(p.placeLabel, 'CADLETE Club · Ahmedabad');
      expect(p.details['courts'], 4);
      expect(p.detailLabels['courts'], 'Courts');
      expect(p.isOwner, isFalse);
      expect(p.myResponse?.status, LfResponseStatus.accepted);
    });

    test("the owner's detail carries matching; a response carries facts and consented contact", () {
      final p = LfPost.fromJson(fixture['ownerDetail'] as Map<String, dynamic>);
      expect(p.isOwner, isTrue);
      expect(p.matching!.count, greaterThan(0));
      expect(p.matching!.summary.first.$1, 'Registered referee');
      final r = LfResponse.fromJson(fixture['response'] as Map<String, dynamic>);
      expect(r.status, LfResponseStatus.accepted);
      expect(r.availabilityConfirmed, isTrue);
      expect(r.person!.name, 'Fixture Responder');
      expect(r.contact.theyShared, isTrue);
      expect(r.contact.phone, isNotNull, reason: 'they shared, so the poster sees it');
    });

    test('alert settings and categories parse', () {
      final a = LfAlerts.fromJson(fixture['alerts'] as Map<String, dynamic>);
      expect(a.isDefault, isTrue);
      expect(a.categories, containsAll(['player', 'match']));
      expect(a.knownCities, contains('Ahmedabad'));
      final c = LfCategory.fromJson(fixture['category'] as Map<String, dynamic>);
      expect(c.form.needs('when'), isTrue);
      expect(c.form.details.map((d) => d.key), containsAll(['courts', 'matches', 'experience']));
    });

    test('a server notification maps to the Looking For kind', () {
      final n = AppNotification.fromJson({
        'id': 'n1',
        'type': 'looking_for.match',
        'title': 'New Looking For near you',
        'body': '2 Players needed',
        'route': '/player/looking-for/abc',
        'priority': 'high',
        'read': false,
        'at': '2026-09-27T10:00:00.000Z',
      });
      expect(n.kind, NotificationKind.lookingFor);
      expect(n.priority, NotificationPriority.high);
      expect(n.route, '/player/looking-for/abc');
    });
  });

  group('sample rules match the server', () {
    test('accepting fills places, then the post; phones only after consent', () async {
      final repo = SampleLookingForRepository();
      final mine = await repo.post('lf-mine');
      expect(mine.status, LfStatus.responsesReceived);
      final responses = await repo.responses('lf-mine');
      expect(responses.map((r) => r.person!.name), ['Kavya Iyer', 'Dev Trivedi', 'Isha Rao'], reason: 'in response order, never ranked');

      await repo.act(responses[0].id, 'accept');
      expect((await repo.post('lf-mine')).status, LfStatus.partiallyFilled);
      await repo.act(responses[1].id, 'accept');
      expect((await repo.post('lf-mine')).status, LfStatus.filled);
      await expectLater(repo.act(responses[2].id, 'accept'), throwsA(anything));

      var accepted = (await repo.responses('lf-mine')).first;
      expect(accepted.contact.phone, isNull);
      await expectLater(repo.act(responses[2].id, 'share-contact'), throwsA(anything), reason: 'not accepted');
      await repo.act(accepted.id, 'share-contact');
      accepted = (await repo.responses('lf-mine')).first;
      expect(accepted.contact.iShared, isTrue);
      expect(accepted.contact.phone, isNull, reason: 'their number needs their consent');
    });

    test('one response per person, never to your own post', () async {
      final repo = SampleLookingForRepository();
      final a = await repo.respond('lf-1', message: 'In!');
      final b = await repo.respond('lf-1');
      expect(b.id, a.id);
      await expectLater(repo.respond('lf-mine'), throwsA(anything));
      expect((await repo.post('lf-1')).myResponse?.status, LfResponseStatus.pending);
    });

    test('search reads categories out of words', () async {
      final repo = SampleLookingForRepository();
      final refs = await repo.feed(const LfQuery(tab: LfTab.latest, text: 'referee'));
      expect(refs.items.map((p) => p.categoryId).toSet(), {'referee'});
      final paid = await repo.feed(const LfQuery(tab: LfTab.latest, paid: true));
      expect(paid.items.every((p) => p.paymentType == LfPaymentType.paid), isTrue);
    });

    test('a new player sees nothing', () async {
      final repo = SampleLookingForRepository(newcomer: true);
      expect((await repo.feed(const LfQuery(tab: LfTab.latest))).items, isEmpty);
    });
  });

  group('Looking For', () {
    testWidgets('opens from Explore and goes back', (tester) async {
      usePhone(tester);
      await pumpSignedIn(tester);
      await openExplore(tester);
      await tapVisible(tester, find.byKey(const Key('explore-looking-for')));
      // Opens on top of Explore (pushed), so the location underneath stays put.
      expect(find.byType(LookingForHomePage), findsOneWidget);
      await tester.tap(find.byKey(const Key('back')));
      await tester.pumpAndSettle();
      expect(find.byType(LookingForHomePage), findsNothing);
      expect(locationOf(tester), '/player/explore');
    });

    testWidgets('Home leads to it', (tester) async {
      usePhone(tester);
      await pumpSignedIn(tester);
      await tester.scrollUntilVisible(find.byKey(const Key('homeLookingFor')), 250, scrollable: pageScroll);
      // New responses to my own request come before what is open nearby.
      expect(find.text('3 new responses'), findsOneWidget);
      await tester.tap(find.byKey(const Key('homeLookingFor')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('lfMine-responses')), findsOneWidget);
    });

    testWidgets('browse, search and filter', (tester) async {
      usePhone(tester);
      await pumpSignedIn(tester);
      await goTo(tester, '/player/explore');
      routerOf(tester).push('/player/looking-for?tab=latest');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('lfCard-lf-1')), findsOneWidget);

      await tester.enterText(find.byKey(const Key('lfSearch')), 'referee');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('lfCard-lf-2')), findsOneWidget);
      expect(find.byKey(const Key('lfCard-lf-1')), findsNothing);

      await tester.enterText(find.byKey(const Key('lfSearch')), 'no such thing zzz');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('Nothing nearby yet.'), findsOneWidget);
      expect(find.byKey(const Key('lfEmptyPost')), findsOneWidget);
    });

    testWidgets('a need tile narrows the feed, and its chip clears it', (tester) async {
      usePhone(tester);
      await pumpSignedIn(tester);
      await goTo(tester, '/player/explore');
      routerOf(tester).push('/player/looking-for?tab=latest');
      await tester.pumpAndSettle();
      expect(find.text('Find players, officials and courts'), findsOneWidget);
      await tapKey(tester, 'lfNeed-officials');
      await tester.scrollUntilVisible(find.byKey(const Key('lfCard-lf-2')), 250, scrollable: pageScroll);
      expect(find.byKey(const Key('lfCard-lf-1')), findsNothing);
      await tapKey(tester, 'lfActive-Officials');
      await tester.scrollUntilVisible(find.byKey(const Key('lfCard-lf-1')), 250, scrollable: pageScroll);
      expect(find.byKey(const Key('lfCard-lf-1')), findsOneWidget);
    });

    testWidgets("I'm interested from a request, then withdraw", (tester) async {
      usePhone(tester);
      await pumpSignedIn(tester);
      await goTo(tester, '/player/explore');
      routerOf(tester).push('/player/looking-for/lf-1');
      await tester.pumpAndSettle();
      expect(find.text('2 Players needed tonight'), findsOneWidget);
      await tapKey(tester, 'lfInterestedDetail');
      expect(find.byKey(const Key('lfInterestMessage')), findsOneWidget);
      await tapKey(tester, 'lfSendInterest');
      expect(find.byKey(const Key('lfInterestedDetail')), findsNothing);
      await tester.scrollUntilVisible(find.textContaining('Waiting for Rahul'), 250, scrollable: pageScroll);
      await tapKey(tester, 'lfWithdraw');
      expect(find.byKey(const Key('lfInterestedDetail')), findsOneWidget);
    });

    testWidgets('post a requirement in a few taps', (tester) async {
      usePhone(tester);
      await pumpSignedIn(tester);
      await goTo(tester, '/player/explore');
      routerOf(tester).push('/player/looking-for');
      await tester.pumpAndSettle();
      await tapKey(tester, 'lfHeroPost');
      await tapKey(tester, 'lfPick-player');
      await tapKey(tester, 'lfQty-2');
      await tapKey(tester, 'lfDay-tomorrow');
      await tester.enterText(find.byKey(const Key('lfPlace')), 'XYZ Club');
      await tapKey(tester, 'lfReview');
      expect(find.text('Review requirement'), findsOneWidget);
      await tapKey(tester, 'lfSubmit');
      expect(find.text("It's live"), findsOneWidget);
      expect(find.textContaining('may match your requirement'), findsOneWidget);
      await tapKey(tester, 'lfViewPosted');
      expect(find.textContaining('2 Players needed'), findsWidgets);
      expect(find.text('No responses yet'), findsOneWidget);
    });

    testWidgets('type it as a sentence and review what SkorX read', (tester) async {
      usePhone(tester);
      await pumpSignedIn(tester);
      await goTo(tester, '/player/explore');
      routerOf(tester).push('/player/looking-for/new');
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('lfSentence')), 'Need 2 intermediate players at XYZ Club tomorrow at 8 pm');
      await tapKey(tester, 'lfParse');
      expect(find.text('Review requirement'), findsOneWidget);
      expect(find.textContaining('Xyz Club'), findsWidgets);
      expect(find.text('Intermediate'), findsOneWidget);
    });

    testWidgets('the poster accepts responses until the request fills', (tester) async {
      usePhone(tester);
      await pumpSignedIn(tester);
      await goTo(tester, '/player/explore');
      routerOf(tester).push('/player/looking-for?tab=mine');
      await tester.pumpAndSettle();
      await tapKey(tester, 'lfCard-lf-mine');
      expect(find.text('Potential matches'), findsOneWidget);
      await tapKey(tester, 'lfManageResponses');
      expect(find.text('Kavya Iyer'), findsOneWidget);
      await tapKey(tester, 'lfAccept-r-seed-1');
      expect(find.text('1 OF 2 FILLED'), findsOneWidget);
      await tapKey(tester, 'lfAccept-r-seed-2');
      expect(find.text('FILLED'), findsOneWidget);
      expect(find.text('Every place is filled. Edit the request to take more people.'), findsOneWidget);
      expect(find.byKey(const Key('lfShareContact')), findsNWidgets(2));
    });

    testWidgets('alerts: switch to a daily digest and add a role', (tester) async {
      usePhone(tester);
      await pumpSignedIn(tester);
      await goTo(tester, '/player/explore');
      routerOf(tester).push('/player/looking-for/alerts');
      await tester.pumpAndSettle();
      await tapKey(tester, 'lfMode-daily_digest');
      await tapKey(tester, 'lfRole-Referee');
      await tapKey(tester, 'lfSaveAlerts');
      routerOf(tester).push('/player/looking-for/alerts');
      await tester.pumpAndSettle();
      final digest = tester.widget<Icon>(find.descendant(of: find.byKey(const Key('lfMode-daily_digest')), matching: find.byType(Icon)).last);
      expect(digest.icon, Icons.radio_button_checked_rounded);
    });

    testWidgets('every screen fits a small phone', (tester) async {
      usePhone(tester, const Size(360, 690));
      await pumpSignedIn(tester);
      for (final route in [
        '/player/looking-for',
        '/player/looking-for?tab=latest',
        '/player/looking-for?tab=mine',
        '/player/looking-for/new',
        '/player/looking-for/alerts',
        '/player/looking-for/lf-1',
        '/player/looking-for/lf-2',
        '/player/looking-for/lf-mine',
        '/player/looking-for/lf-mine/responses',
      ]) {
        await goTo(tester, '/player/home');
        routerOf(tester).push(route);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: route);
      }
    });
  });
}
