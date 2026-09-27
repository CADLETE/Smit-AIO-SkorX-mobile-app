import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skorx/app/app.dart';
import 'package:skorx/app/routing/router.dart';
import 'package:skorx/core/api/api_exception.dart';
import 'package:skorx/features/auth/data/auth_repository.dart';
import 'package:skorx/features/subscription/data/billing_repository.dart';
import 'package:skorx/features/subscription/data/dev_billing_repository.dart';
import 'package:skorx/features/subscription/data/plans.dart';
import 'package:skorx/features/subscription/data/subscription.dart';
import 'package:skorx/features/subscription/subscription_controller.dart';
import 'package:skorx/shared/format.dart';

import '../support/fakes.dart';

/// SkorX Pro: the purchase lifecycle against the Razorpay Test Mode
/// stand-in (the same rules as the server), then the screens.
void main() {
  setUp(useInMemoryPreferences);

  group('SkorX Pro billing rules', () {
    // 27 Sep 2026, 10:00 India time.
    var now = DateTime.parse('2026-09-27T10:00:00+05:30');
    DevBillingRepository repo() => DevBillingRepository(
          SharedPreferencesAsync(),
          userId: 'u1',
          customerName: 'Smit Ramani',
          customerPhone: '+919586545430',
          clock: () => now,
        );
    setUp(() => now = DateTime.parse('2026-09-27T10:00:00+05:30'));

    Future<VerifiedPayment> buy(DevBillingRepository r, ProPlan plan, {String? coupon}) async {
      final session = await r.checkout(plan, coupon: coupon);
      return r.verify(session.orderId, await r.simulatePayment(session.orderId, succeed: true));
    }

    test('a new account is Free with no Pro features', () async {
      final s = await repo().summary();
      expect(s.tier, PlanTier.free);
      expect(s.status, SubscriptionStatus.active);
      expect(ProFeature.values.where(s.can), isEmpty);
    });

    test('1: Free → Monthly Pro → paid → Pro, renewing on the same date next month', () async {
      final r = repo();
      final q = await r.quote(ProPlan.monthly);
      expect(q.subtotalPaise, 9900);
      expect(q.gstPaise, 1782);
      expect(q.totalPaise, 11682);
      final paid = await buy(r, ProPlan.monthly);
      expect(paid.summary.isPro, isTrue);
      expect(paid.summary.plan, ProPlan.monthly);
      expect(ProFeature.values.every(paid.summary.can), isTrue);
      expect(billingDate(paid.summary.nextBillingDate!), '27 Oct 2026');
      expect(paid.record.status, BillingStatus.paid);
    });

    test('2: Free → Annual Pro at ₹999 + GST → Pro until next year', () async {
      final r = repo();
      final paid = await buy(r, ProPlan.annual);
      expect(paid.record.totalPaise, 117882, reason: '₹999 + ₹179.82 GST');
      expect(formatPaise(paid.record.totalPaise), '₹1,178.82');
      expect(paid.summary.plan, ProPlan.annual);
      expect(billingDate(paid.summary.startedAt!), '27 Sep 2026');
      expect(billingDate(paid.summary.nextBillingDate!), '27 Sep 2027');
      expect(paid.summary.autoRenew, isTrue);
    });

    test('3: an invalid coupon is rejected and no order is made', () async {
      final r = repo();
      await expectLater(
        r.quote(ProPlan.annual, coupon: 'NOPE'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'COUPON_INVALID')),
      );
      await expectLater(r.checkout(ProPlan.annual, coupon: 'NOPE'), throwsA(isA<ApiException>()));
      expect(await r.history(), isEmpty);
    });

    test('4: a valid coupon comes off before GST, with each rule enforced', () async {
      final r = repo();
      final q = await r.quote(ProPlan.annual, coupon: ' skorx50 ');
      expect(q.couponCode, 'SKORX50');
      expect(q.discountPaise, 5000);
      expect(q.gstPaise, 17082, reason: '18% of ₹949');
      expect(q.totalPaise, 111982);
      expect((await r.quote(ProPlan.annual, coupon: 'PRO10')).discountPaise, 9990);

      Future<String> why(ProPlan p, String code) async {
        try {
          await r.quote(p, coupon: code);
          return 'accepted';
        } on ApiException catch (e) {
          return e.message;
        }
      }

      expect(await why(ProPlan.monthly, 'ANNUAL200'), 'ANNUAL200 only works on the annual plan.');
      expect(await why(ProPlan.annual, 'MONTHLY20'), 'MONTHLY20 only works on the monthly plan.');
      expect(await why(ProPlan.annual, 'EXPIRED10'), 'That coupon has expired.');
      expect(await why(ProPlan.annual, 'SOLDOUT'), 'That coupon has been fully redeemed.');

      final paid = await buy(r, ProPlan.monthly, coupon: 'WELCOME');
      expect(paid.record.discountPaise, 9800, reason: '₹100 off, but never below ₹1 payable');
      expect(await why(ProPlan.annual, 'WELCOME'), "You've already used WELCOME.");
    });

    test('5: a failed payment leaves the player on Free', () async {
      final r = repo();
      final session = await r.checkout(ProPlan.annual);
      await expectLater(r.simulatePayment(session.orderId, succeed: false), throwsA(isA<PaymentDeclined>()));
      final s = await r.reportFailure(session.orderId, cancelled: false, reason: 'Declined');
      expect(s.isPro, isFalse);
      expect(s.payment, PaymentState.failed);
      expect((await r.history()).single.status, BillingStatus.failed);
    });

    test('Pro only after the server checks the payment: a forged one is refused', () async {
      final r = repo();
      final session = await r.checkout(ProPlan.annual);
      final forged = GatewayPayment(orderId: session.razorpayOrderId, paymentId: 'pay_TESTfake', signature: 'x' * 64);
      await expectLater(
        r.verify(session.orderId, forged),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'PAYMENT_VERIFICATION_FAILED')),
      );
      expect((await r.summary()).isPro, isFalse);
    });

    test('a repeated verify (app + webhook) makes one payment and one invoice', () async {
      final r = repo();
      final session = await r.checkout(ProPlan.annual);
      final payment = await r.simulatePayment(session.orderId, succeed: true);
      final first = await r.verify(session.orderId, payment);
      final again = await r.verify(session.orderId, payment);
      expect(again.record.invoiceNumber, first.record.invoiceNumber);
      expect(first.record.invoiceNumber, 'SKX-INV-2026-00001');
      expect((await r.history()).where((h) => h.status == BillingStatus.paid), hasLength(1));
    });

    test('6: a paid order has a full invoice; numbers never repeat', () async {
      final r = repo();
      final paid = await buy(r, ProPlan.annual, coupon: 'SKORX50');
      final inv = await r.invoice(paid.record.orderId);
      expect(inv.number, 'SKX-INV-2026-00001');
      expect(inv.customerName, 'Smit Ramani');
      expect(inv.basePaise, 99900);
      expect(inv.discountPaise, 5000);
      expect(inv.gstPaise, 17082);
      expect(inv.totalPaise, 111982);
      expect(inv.paymentId, startsWith('pay_TEST'));
      expect(billingDate(inv.periodStart!), '27 Sep 2026');
      expect(billingDate(inv.periodEnd!), '26 Sep 2027');

      final renewal = await r.simulateRenewal();
      expect(renewal.upcoming, hasLength(1));
      final rows = await r.history();
      expect(rows.first.invoiceNumber, 'SKX-INV-2026-00002');
      expect(rows.first.renewal, isTrue);
    });

    test('7: Pro falls back to Free when the period ends; history is kept', () async {
      final r = repo();
      await buy(r, ProPlan.monthly);
      now = DateTime.parse('2026-10-27T00:00:01+05:30');
      final s = await r.summary();
      expect(s.isPro, isFalse);
      expect(s.status, SubscriptionStatus.expired);
      expect(ProFeature.values.where(s.can), isEmpty);
      expect((await r.history()).single.status, BillingStatus.paid);
    });

    test('turning off auto-renew keeps Pro to the end of the period, then ends it', () async {
      final r = repo();
      await buy(r, ProPlan.monthly);
      final s = await r.setAutoRenew(false);
      expect(s.isPro, isTrue);
      expect(s.status, SubscriptionStatus.cancelled);
      expect(s.nextBillingDate, isNull);
      expect(billingDate(s.proUntil!), '26 Oct 2026');
      now = DateTime.parse('2026-10-27T09:00:00+05:30');
      expect((await r.summary()).isPro, isFalse);
    });

    test('monthly → annual starts when the month ends; one queued period at a time', () async {
      final r = repo();
      await buy(r, ProPlan.monthly);
      final q = await r.quote(ProPlan.annual);
      expect(billingDate(q.startsAt!), '27 Oct 2026');
      final s = (await buy(r, ProPlan.annual)).summary;
      expect(s.plan, ProPlan.monthly, reason: 'the month already paid for runs first');
      expect(s.upcoming.single.plan, ProPlan.annual);
      expect(billingDate(s.nextBillingDate!), '27 Oct 2027');
      await expectLater(
        r.checkout(ProPlan.monthly),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'SUBSCRIPTION_CONFLICT')),
      );
      now = DateTime.parse('2026-11-01T09:00:00+05:30');
      expect((await r.summary()).plan, ProPlan.annual);
    });

    test('10: Pro survives a restart (a new session reads the same account)', () async {
      await buy(repo(), ProPlan.annual);
      final after = await repo().summary();
      expect(after.isPro, isTrue);
      expect(after.plan, ProPlan.annual);
    });

    test('closing Checkout changes nothing and can be retried', () async {
      final r = repo();
      final session = await r.checkout(ProPlan.annual);
      final s = await r.reportFailure(session.orderId, cancelled: true);
      expect(s.isPro, isFalse);
      expect((await r.history()).single.status, BillingStatus.cancelled);
      expect((await buy(r, ProPlan.annual)).summary.isPro, isTrue);
    });
  });

  group('SkorX Pro screens', () {
    void usePhone(WidgetTester tester, [Size size = const Size(390, 844)]) {
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
    }

    Future<ProviderContainer> pump(WidgetTester tester, {bool pro = false}) async {
      useReducedMotion(tester);
      await tester.pumpWidget(ProviderScope(
        overrides: appOverrides(FakeAuthRepository(stored: RestoredUser(user(), fromCache: false)), realBilling: !pro),
        child: const SkorxApp(),
      ));
      await tester.pumpAndSettle();
      return ProviderScope.containerOf(tester.element(find.byType(SkorxApp)));
    }

    Future<void> go(WidgetTester tester, String location) async {
      ProviderScope.containerOf(tester.element(find.byType(SkorxApp))).read(routerProvider).go(location);
      await tester.pumpAndSettle();
    }

    Future<void> tapKey(WidgetTester tester, String key) async {
      final f = find.byKey(Key(key));
      // Below the fold of a lazy list: scroll until it is built.
      if (f.evaluate().isEmpty) await tester.scrollUntilVisible(f, 300, scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    testWidgets('8: a Free player sees Match Analytics marked PRO and gets the upgrade prompt', (tester) async {
      usePhone(tester);
      await pump(tester);
      await go(tester, '/player/players/me');
      await tapKey(tester, 'proLocked-matchAnalytics');
      expect(find.byKey(const Key('proUpsell')), findsOneWidget);
      expect(find.text('Unlock Match Analytics'), findsOneWidget);
      expect(find.text('Rival player stats'), findsOneWidget);
      await tapKey(tester, 'maybeLater');
      expect(find.byKey(const Key('proUpsell')), findsNothing);

      await go(tester, '/player/rankings');
      expect(find.byKey(const Key('proLocked-leaderboard')), findsOneWidget);
      expect(find.byKey(const Key('proLocked-localRanking')), findsOneWidget);
      await tapKey(tester, 'proLocked-leaderboard');
      await tapKey(tester, 'viewProPlans');
      expect(find.byKey(const Key('proPlans')), findsOneWidget);
      expect(find.text('Leaderboards is part of SkorX Pro.'), findsOneWidget);
    });

    testWidgets('9: a Pro player uses Match Analytics and leaderboards directly', (tester) async {
      usePhone(tester);
      await pump(tester, pro: true);
      await go(tester, '/player/players/me');
      expect(find.byKey(const Key('proLocked-matchAnalytics')), findsNothing);
      await go(tester, '/player/rankings');
      expect(find.byKey(const Key('proLocked-leaderboard')), findsNothing);
      await go(tester, '/player/profile');
      expect(find.byKey(const Key('idCardPro')), findsOneWidget);
      expect(find.byKey(const Key('planCard-pro')), findsOneWidget);
    });

    testWidgets('Free → plans → monthly → coupon → Test Mode payment → Pro everywhere → invoice', (tester) async {
      usePhone(tester);
      final container = await pump(tester);
      await go(tester, '/player/profile');
      expect(find.byKey(const Key('planCard-free')), findsOneWidget);
      expect(find.text('₹0'), findsOneWidget);
      expect(find.byKey(const Key('idCardPro')), findsNothing);

      await tapKey(tester, 'upgradeToPro');
      expect(find.text('SKORX PRO'), findsOneWidget);
      expect(find.byKey(const Key('annualSaving')), findsOneWidget);
      expect(find.text('SAVE ₹189'), findsOneWidget);
      expect(find.byKey(const Key('comparison')), findsOneWidget);
      await tapKey(tester, 'plan-monthly');
      await tapKey(tester, 'continueToCheckout');

      expect(find.byKey(const Key('checkout')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('priceTotal'))).data, '₹116.82');
      await tester.enterText(find.byKey(const Key('couponField')), 'nope');
      await tapKey(tester, 'applyCoupon');
      expect(find.text("That coupon code isn't valid."), findsOneWidget);
      await tester.enterText(find.byKey(const Key('couponField')), 'skorx50');
      await tapKey(tester, 'applyCoupon');
      expect(find.byKey(const Key('couponApplied')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('priceDiscount'))).data, '−₹50');
      expect(tester.widget<Text>(find.byKey(const Key('priceGst'))).data, '₹8.82');
      expect(tester.widget<Text>(find.byKey(const Key('priceTotal'))).data, '₹57.82');

      await tapKey(tester, 'payNow');
      expect(find.byKey(const Key('testCheckout')), findsOneWidget);
      await tapKey(tester, 'testPaySuccess');
      expect(find.byKey(const Key('proWelcome')), findsOneWidget);
      expect(find.text('Welcome to SkorX Pro 🎉'), findsOneWidget);
      expect(container.read(isProProvider), isTrue, reason: 'no sign-out needed');
      expect(container.read(canAccessProvider(ProFeature.matchAnalytics)), isTrue);

      await tapKey(tester, 'exploreProFeatures');
      await go(tester, '/player/rankings');
      expect(find.byKey(const Key('proLocked-leaderboard')), findsNothing);

      await go(tester, '/player/profile');
      expect(find.byKey(const Key('planCard-pro')), findsOneWidget);
      expect(find.byKey(const Key('idCardPro')), findsOneWidget);
      expect(find.text('Monthly plan · ₹99 + GST / month'), findsOneWidget);

      await go(tester, '/player/billing');
      final row = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('billing-SKX-'));
      expect(row, findsOneWidget);
      expect(find.text('PAID'), findsOneWidget);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('invoiceNumber'))).data, 'SKX-INV-${DateTime.now().year}-00001');
      expect(tester.widget<Text>(find.byKey(const Key('invoiceTotal'))).data, '₹57.82');
      expect(find.byKey(const Key('downloadInvoice')), findsOneWidget);
    });

    testWidgets('5: a failed payment says the Free plan is still active, with a way to retry', (tester) async {
      usePhone(tester);
      final container = await pump(tester);
      await go(tester, '/player/pro/checkout?plan=annual');
      expect(tester.widget<Text>(find.byKey(const Key('priceTotal'))).data, '₹1,178.82');
      await tapKey(tester, 'payNow');
      await tapKey(tester, 'testPayFail');
      expect(find.byKey(const Key('paymentFailed')), findsOneWidget);
      expect(find.text('Your Free plan is still active.'), findsOneWidget);
      expect(container.read(isProProvider), isFalse);
      await tapKey(tester, 'tryAgain');
      expect(find.byKey(const Key('checkout')), findsOneWidget);
    });

    testWidgets('closing the Test Mode checkout leaves the plan unchanged', (tester) async {
      usePhone(tester);
      final container = await pump(tester);
      await go(tester, '/player/pro/checkout?plan=monthly');
      await tapKey(tester, 'payNow');
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(find.text('Payment cancelled. You have not been charged.'), findsOneWidget);
      expect(container.read(isProProvider), isFalse);
    });

    testWidgets('7: Test Mode tools: renew, then expire back to Free with history kept', (tester) async {
      usePhone(tester);
      final container = await pump(tester);
      final repo = container.read(billingRepositoryProvider);
      final session = await repo.checkout(ProPlan.annual);
      await repo.verify(session.orderId, await repo.simulatePayment(session.orderId, succeed: true));
      await container.read(subscriptionProvider.notifier).refresh();
      await go(tester, '/player/subscription');
      expect(find.text('Next billing date'), findsOneWidget);
      await tapKey(tester, 'devExpire');
      expect(container.read(isProProvider), isFalse);
      expect(find.byKey(const Key('planCard-free')), findsOneWidget);
      expect(find.text('Renew Pro'), findsWidgets);
      expect(find.text('PAID'), findsOneWidget, reason: 'billing history is kept');
    });

    for (final pro in [false, true]) {
      testWidgets('every Pro screen lays out at 360×690 dark (${pro ? 'Pro' : 'Free'})', (tester) async {
        usePhone(tester, const Size(360, 690));
        tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await pump(tester, pro: pro);
        for (final screen in [
          '/player/profile',
          '/player/pro',
          '/player/pro?feature=rivalStats',
          '/player/pro/checkout?plan=annual',
          '/player/pro/welcome',
          '/player/pro/failed?plan=monthly&reason=Declined',
          '/player/subscription',
          '/player/billing',
          '/player/rankings',
          '/player/players/me',
          '/player/players/SKX-10611',
        ]) {
          await go(tester, screen);
          for (var i = 0; i < 4; i++) {
            await tester.drag(find.byType(Scrollable).first, const Offset(0, -600), warnIfMissed: false);
            await tester.pumpAndSettle();
          }
        }
      });
    }
  });
}
