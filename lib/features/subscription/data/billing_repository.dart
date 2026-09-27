import '../../../core/api/api_client.dart';
import 'plans.dart';
import 'subscription.dart';

/// A payment the server verified: the new plan and the billing record.
class VerifiedPayment {
  const VerifiedPayment(this.summary, this.record);

  final SubscriptionSummary summary;
  final BillingRecord record;
}

/// SkorX Pro plans, checkout and billing. The server prices every order,
/// verifies every payment and decides access; the app only asks.
///
/// Errors are [ApiException]s: COUPON_INVALID (with the reason),
/// PAYMENT_VERIFICATION_FAILED, SUBSCRIPTION_CONFLICT, network.
abstract class BillingRepository {
  Future<SubscriptionSummary> summary();

  /// The price breakdown for [plan], with [coupon] applied if it is valid.
  Future<PriceQuote> quote(ProPlan plan, {String? coupon});

  /// Creates the order to pay with Razorpay Checkout.
  Future<CheckoutSession> checkout(ProPlan plan, {String? coupon});

  /// Razorpay Test Mode only: stands in for the Checkout popup. Returns what
  /// Checkout would, or throws [PaymentDeclined].
  Future<GatewayPayment> simulatePayment(String orderId, {required bool succeed});

  /// Hands Checkout's result to the server, which checks the signature (and
  /// with live keys asks Razorpay) before activating Pro. Safe to repeat.
  Future<VerifiedPayment> verify(String orderId, GatewayPayment payment);

  /// The payment failed, or the player closed Checkout. Never undoes a payment.
  Future<SubscriptionSummary> reportFailure(String orderId, {required bool cancelled, String? reason});

  /// Off cancels at the end of the paid period; Pro stays until then.
  Future<SubscriptionSummary> setAutoRenew(bool on);

  Future<List<BillingRecord>> history();
  Future<Invoice> invoice(String orderId);

  /// Test Mode tools: what an automatic renewal does, and the end of Pro.
  Future<SubscriptionSummary> simulateRenewal();
  Future<SubscriptionSummary> expireNow();
}

/// The bank (or the test bank) declined the payment.
class PaymentDeclined implements Exception {
  const PaymentDeclined(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// `/me/subscription` and `/me/billing` on the SkorX API.
class ApiBillingRepository implements BillingRepository {
  ApiBillingRepository(this._api);

  final ApiClient _api;

  @override
  Future<SubscriptionSummary> summary() async =>
      SubscriptionSummary.fromJson(await _api.get<Map<String, dynamic>>('/me/subscription'));

  @override
  Future<PriceQuote> quote(ProPlan plan, {String? coupon}) async => PriceQuote.fromJson(
        await _api.post<Map<String, dynamic>>('/me/subscription/quote', body: {
          'planId': plan.id,
          if (coupon != null && coupon.isNotEmpty) 'couponCode': coupon,
        }),
      );

  @override
  Future<CheckoutSession> checkout(ProPlan plan, {String? coupon}) async => CheckoutSession.fromJson(
        await _api.post<Map<String, dynamic>>('/me/subscription/checkout', body: {
          'planId': plan.id,
          if (coupon != null && coupon.isNotEmpty) 'couponCode': coupon,
        }),
      );

  @override
  Future<GatewayPayment> simulatePayment(String orderId, {required bool succeed}) async {
    final result = await _api.post<Map<String, dynamic>>(
      '/me/subscription/checkout/${Uri.encodeComponent(orderId)}/simulate',
      body: {'outcome': succeed ? 'success' : 'failure'},
    );
    if (result['ok'] != true) {
      final error = result['error'] as Map<String, dynamic>? ?? const {};
      throw PaymentDeclined(error['description'] as String? ?? 'The payment was declined.');
    }
    return GatewayPayment.fromJson(result['response'] as Map<String, dynamic>);
  }

  @override
  Future<VerifiedPayment> verify(String orderId, GatewayPayment payment) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/me/subscription/checkout/${Uri.encodeComponent(orderId)}/verify',
      body: payment.toJson(),
    );
    return VerifiedPayment(
      SubscriptionSummary.fromJson(data['summary'] as Map<String, dynamic>),
      BillingRecord.fromJson(data['payment'] as Map<String, dynamic>),
    );
  }

  @override
  Future<SubscriptionSummary> reportFailure(String orderId, {required bool cancelled, String? reason}) async =>
      SubscriptionSummary.fromJson(await _api.post<Map<String, dynamic>>(
        '/me/subscription/checkout/${Uri.encodeComponent(orderId)}/fail',
        body: {'status': cancelled ? 'cancelled' : 'failed', 'reason': ?reason},
      ));

  @override
  Future<SubscriptionSummary> setAutoRenew(bool on) async => SubscriptionSummary.fromJson(
        await _api.patch<Map<String, dynamic>>('/me/subscription/auto-renew', body: {'autoRenew': on}),
      );

  @override
  Future<List<BillingRecord>> history() async => [
        for (final r in await _api.get<List<dynamic>>('/me/billing')) BillingRecord.fromJson(r as Map<String, dynamic>),
      ];

  @override
  Future<Invoice> invoice(String orderId) async =>
      Invoice.fromJson(await _api.get<Map<String, dynamic>>('/me/billing/${Uri.encodeComponent(orderId)}/invoice'));

  @override
  Future<SubscriptionSummary> simulateRenewal() async =>
      SubscriptionSummary.fromJson(await _api.post<Map<String, dynamic>>('/me/subscription/dev/renew'));

  @override
  Future<SubscriptionSummary> expireNow() async =>
      SubscriptionSummary.fromJson(await _api.post<Map<String, dynamic>>('/me/subscription/dev/expire'));
}
