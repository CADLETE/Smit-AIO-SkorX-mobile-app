import 'plans.dart';

/// The account's plan, as the server decides it (`GET /me/subscription`).
/// Everything in the app that asks "Free or Pro?" or "may I show this?"
/// reads this, through `subscriptionProvider`.

enum PlanTier { free, pro }

/// ACTIVE / CANCELLED (Pro until the paid period ends) / EXPIRED (was Pro).
/// PENDING and PAYMENT_FAILED belong to single payments ([PaymentState]).
enum SubscriptionStatus { active, cancelled, expired }

/// The latest payment attempt.
enum PaymentState { none, paid, pending, failed }

/// A Pro period already paid for that starts later (a renewal or a plan
/// change bought while the current one runs).
class UpcomingPeriod {
  const UpcomingPeriod({required this.plan, required this.startsAt, required this.endsAt, required this.autoRenew});

  final ProPlan plan;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool autoRenew;

  factory UpcomingPeriod.fromJson(Map<String, dynamic> j) => UpcomingPeriod(
        plan: ProPlan.fromId(j['planId'] as String?) ?? ProPlan.monthly,
        startsAt: DateTime.parse(j['startsAt'] as String).toLocal(),
        endsAt: DateTime.parse(j['endsAt'] as String).toLocal(),
        autoRenew: j['autoRenew'] as bool? ?? false,
      );
}

class SubscriptionSummary {
  const SubscriptionSummary({
    required this.tier,
    required this.status,
    required this.entitlements,
    this.plan,
    this.startedAt,
    this.endsAt,
    this.nextBillingDate,
    this.autoRenew = false,
    this.payment = PaymentState.none,
    this.pendingOrderId,
    this.upcoming = const [],
    this.testMode = false,
    this.devTools = false,
  });

  /// A new account, and anyone signed out: Free, nothing to renew.
  static const free = SubscriptionSummary(tier: PlanTier.free, status: SubscriptionStatus.active, entitlements: {});

  final PlanTier tier;
  final SubscriptionStatus status;

  /// The running Pro plan; null on Free.
  final ProPlan? plan;
  final DateTime? startedAt;

  /// When the running Pro period ends (the last moment of Pro).
  final DateTime? endsAt;

  /// When the next payment is due; null when nothing will renew.
  final DateTime? nextBillingDate;
  final bool autoRenew;
  final PaymentState payment;

  /// An unpaid checkout the player may still complete.
  final String? pendingOrderId;
  final List<UpcomingPeriod> upcoming;

  /// Feature ids the server allows right now (`ProFeature.key`).
  final Set<String> entitlements;

  /// Payments go through the Razorpay Test Mode simulator: no real money.
  final bool testMode;

  /// The server offers test tools (simulate renewal, expire now).
  final bool devTools;

  bool get isPro => tier == PlanTier.pro;
  bool can(ProFeature feature) => entitlements.contains(feature.key);

  /// The Pro period that runs last: when access would end if nothing renews.
  DateTime? get proUntil => upcoming.isNotEmpty ? upcoming.last.endsAt : endsAt;

  factory SubscriptionSummary.fromJson(Map<String, dynamic> j) {
    DateTime? date(String key) => j[key] == null ? null : DateTime.parse(j[key] as String).toLocal();
    final ents = (j['entitlements'] as Map<String, dynamic>? ?? const {});
    return SubscriptionSummary(
      tier: j['plan'] == 'PRO' ? PlanTier.pro : PlanTier.free,
      status: switch (j['status']) {
        'CANCELLED' => SubscriptionStatus.cancelled,
        'EXPIRED' => SubscriptionStatus.expired,
        _ => SubscriptionStatus.active,
      },
      plan: ProPlan.fromId(j['planId'] as String?),
      startedAt: date('startedAt'),
      endsAt: date('endsAt'),
      nextBillingDate: date('nextBillingDate'),
      autoRenew: j['autoRenew'] as bool? ?? false,
      payment: switch (j['paymentStatus']) {
        'PAID' => PaymentState.paid,
        'PENDING' => PaymentState.pending,
        'FAILED' => PaymentState.failed,
        _ => PaymentState.none,
      },
      pendingOrderId: j['pendingOrderId'] as String?,
      upcoming: [
        for (final u in (j['upcoming'] as List<dynamic>? ?? const [])) UpcomingPeriod.fromJson(u as Map<String, dynamic>),
      ],
      entitlements: {
        for (final e in ents.entries)
          if (e.value == true) e.key,
      },
      testMode: j['testMode'] as bool? ?? false,
      devTools: j['devTools'] as bool? ?? false,
    );
  }
}

/// A server-priced breakdown. The app never works out what to charge.
class PriceQuote {
  const PriceQuote({
    required this.plan,
    required this.subtotalPaise,
    required this.discountPaise,
    required this.gstRate,
    required this.gstPaise,
    required this.totalPaise,
    this.couponCode,
    this.couponLabel,
    this.startsAt,
    this.endsAt,
  });

  final ProPlan plan;
  final int subtotalPaise;
  final int discountPaise;
  final String? couponCode;
  final String? couponLabel;

  /// 0.18 for 18%.
  final double gstRate;
  final int gstPaise;
  final int totalPaise;

  /// When the period being bought would run.
  final DateTime? startsAt;
  final DateTime? endsAt;

  String get gstPercent {
    final p = gstRate * 100;
    return p == p.roundToDouble() ? '${p.round()}%' : '${p.toStringAsFixed(1)}%';
  }

  factory PriceQuote.fromJson(Map<String, dynamic> j) => PriceQuote(
        plan: ProPlan.fromId(j['planId'] as String?) ?? ProPlan.monthly,
        subtotalPaise: j['subtotalPaise'] as int,
        discountPaise: j['discountPaise'] as int? ?? 0,
        couponCode: j['couponCode'] as String?,
        couponLabel: j['couponLabel'] as String?,
        gstRate: (j['gstRate'] as num).toDouble(),
        gstPaise: j['gstPaise'] as int,
        totalPaise: j['totalPaise'] as int,
        startsAt: j['startsAt'] == null ? null : DateTime.parse(j['startsAt'] as String).toLocal(),
        endsAt: j['endsAt'] == null ? null : DateTime.parse(j['endsAt'] as String).toLocal(),
      );
}

/// A created order, ready to pay through Razorpay Checkout.
class CheckoutSession {
  const CheckoutSession({
    required this.orderId,
    required this.razorpayOrderId,
    required this.amountPaise,
    required this.testMode,
    required this.quote,
    this.keyId,
    this.description = 'SkorX Pro',
    this.prefillName = '',
    this.prefillEmail = '',
    this.prefillContact = '',
  });

  /// SkorX's order id (SKX-2026-XXXXX).
  final String orderId;
  final String razorpayOrderId;
  final int amountPaise;

  /// Razorpay's public key id; null in Test Mode. The secret never leaves the server.
  final String? keyId;
  final bool testMode;
  final String description;
  final String prefillName;
  final String prefillEmail;
  final String prefillContact;
  final PriceQuote quote;

  factory CheckoutSession.fromJson(Map<String, dynamic> j) {
    final prefill = j['prefill'] as Map<String, dynamic>? ?? const {};
    return CheckoutSession(
      orderId: j['orderId'] as String,
      razorpayOrderId: j['razorpayOrderId'] as String,
      amountPaise: j['amountPaise'] as int,
      keyId: j['keyId'] as String?,
      testMode: j['testMode'] as bool? ?? false,
      description: j['description'] as String? ?? 'SkorX Pro',
      prefillName: prefill['name'] as String? ?? '',
      prefillEmail: prefill['email'] as String? ?? '',
      prefillContact: prefill['contact'] as String? ?? '',
      quote: PriceQuote.fromJson(j['quote'] as Map<String, dynamic>),
    );
  }
}

/// What Razorpay Checkout hands back after a payment. Only the server can
/// tell whether it is genuine.
class GatewayPayment {
  const GatewayPayment({required this.orderId, required this.paymentId, required this.signature});

  final String orderId;
  final String paymentId;
  final String signature;

  Map<String, dynamic> toJson() =>
      {'razorpay_order_id': orderId, 'razorpay_payment_id': paymentId, 'razorpay_signature': signature};

  factory GatewayPayment.fromJson(Map<String, dynamic> j) => GatewayPayment(
        orderId: j['razorpay_order_id'] as String,
        paymentId: j['razorpay_payment_id'] as String,
        signature: j['razorpay_signature'] as String,
      );
}

enum BillingStatus { paid, pending, failed, cancelled, refunded }

/// One payment in the player's billing history.
class BillingRecord {
  const BillingRecord({
    required this.orderId,
    required this.date,
    required this.plan,
    required this.subtotalPaise,
    required this.discountPaise,
    required this.gstPaise,
    required this.totalPaise,
    required this.status,
    this.invoiceNumber,
    this.couponCode,
    this.periodStart,
    this.periodEnd,
    this.renewal = false,
    this.paymentId,
    this.failureReason,
    this.testMode = false,
  });

  final String orderId;
  final String? invoiceNumber;
  final DateTime date;
  final ProPlan plan;
  final int subtotalPaise;
  final int discountPaise;
  final String? couponCode;
  final int gstPaise;
  final int totalPaise;
  final BillingStatus status;
  final DateTime? periodStart;
  final DateTime? periodEnd;

  /// Charged automatically, not bought by hand.
  final bool renewal;
  final String? paymentId;
  final String? failureReason;
  final bool testMode;

  bool get hasInvoice => status == BillingStatus.paid && invoiceNumber != null;

  factory BillingRecord.fromJson(Map<String, dynamic> j) {
    DateTime? date(String key) => j[key] == null ? null : DateTime.parse(j[key] as String).toLocal();
    return BillingRecord(
      orderId: j['orderId'] as String,
      invoiceNumber: j['invoiceNumber'] as String?,
      date: date('date')!,
      plan: ProPlan.fromId(j['planId'] as String?) ?? ProPlan.monthly,
      subtotalPaise: j['subtotalPaise'] as int,
      discountPaise: j['discountPaise'] as int? ?? 0,
      couponCode: j['couponCode'] as String?,
      gstPaise: j['gstPaise'] as int,
      totalPaise: j['totalPaise'] as int,
      status: switch (j['paymentStatus']) {
        'PAID' => BillingStatus.paid,
        'PENDING' => BillingStatus.pending,
        'CANCELLED' => BillingStatus.cancelled,
        'REFUNDED' || 'PARTIALLY_REFUNDED' => BillingStatus.refunded,
        _ => BillingStatus.failed,
      },
      periodStart: date('periodStart'),
      periodEnd: date('periodEnd'),
      renewal: j['renewal'] as bool? ?? false,
      paymentId: j['razorpayPaymentId'] as String?,
      failureReason: j['failureReason'] as String?,
      testMode: j['testMode'] as bool? ?? false,
    );
  }
}

/// A tax invoice for one paid order (`GET /me/billing/:orderId/invoice`).
class Invoice {
  const Invoice({
    required this.number,
    required this.date,
    required this.sellerName,
    required this.customerName,
    required this.plan,
    required this.basePaise,
    required this.discountPaise,
    required this.gstRate,
    required this.gstPaise,
    required this.totalPaise,
    required this.orderId,
    required this.razorpayOrderId,
    this.sellerGstin,
    this.sellerAddress,
    this.customerEmail,
    this.customerPhone,
    this.couponCode,
    this.paymentId,
    this.periodStart,
    this.periodEnd,
    this.pdfUrl,
    this.testMode = false,
  });

  final String number;
  final DateTime date;
  final String sellerName;
  final String? sellerGstin;
  final String? sellerAddress;
  final String customerName;
  final String? customerEmail;
  final String? customerPhone;
  final ProPlan plan;
  final int basePaise;
  final int discountPaise;
  final String? couponCode;
  final double gstRate;
  final int gstPaise;
  final int totalPaise;
  final String orderId;
  final String razorpayOrderId;
  final String? paymentId;
  final DateTime? periodStart;
  final DateTime? periodEnd;

  /// Set once the server renders PDFs.
  final String? pdfUrl;
  final bool testMode;

  factory Invoice.fromJson(Map<String, dynamic> j) {
    DateTime? date(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();
    final seller = j['seller'] as Map<String, dynamic>? ?? const {};
    final customer = j['customer'] as Map<String, dynamic>? ?? const {};
    final plan = j['plan'] as Map<String, dynamic>? ?? const {};
    final amounts = j['amounts'] as Map<String, dynamic>;
    final payment = j['payment'] as Map<String, dynamic>;
    final period = j['period'] as Map<String, dynamic>? ?? const {};
    return Invoice(
      number: j['invoiceNumber'] as String,
      date: date(j['invoiceDate'])!,
      sellerName: seller['name'] as String? ?? 'SkorX',
      sellerGstin: seller['gstin'] as String?,
      sellerAddress: seller['address'] as String?,
      customerName: customer['name'] as String? ?? '',
      customerEmail: customer['email'] as String?,
      customerPhone: customer['phone'] as String?,
      plan: ProPlan.fromId(plan['id'] as String?) ?? ProPlan.monthly,
      basePaise: amounts['basePaise'] as int,
      discountPaise: amounts['discountPaise'] as int? ?? 0,
      couponCode: amounts['couponCode'] as String?,
      gstRate: (amounts['gstRate'] as num).toDouble(),
      gstPaise: amounts['gstPaise'] as int,
      totalPaise: amounts['totalPaise'] as int,
      orderId: payment['orderId'] as String,
      razorpayOrderId: payment['razorpayOrderId'] as String,
      paymentId: payment['razorpayPaymentId'] as String?,
      periodStart: date(period['startsAt']),
      periodEnd: date(period['endsAt']),
      pdfUrl: j['pdfUrl'] as String?,
      testMode: j['testMode'] as bool? ?? false,
    );
  }
}
