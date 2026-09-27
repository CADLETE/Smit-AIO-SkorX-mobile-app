import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/sample_latency.dart';
import 'billing_repository.dart';
import 'plans.dart';
import 'subscription.dart';

/// GST charged in the Test Mode stand-in; the real rate comes from the server
/// (GST_RATE). Build with `--dart-define=GST_RATE=0.05` to try another rate.
final double devGstRate = double.tryParse(const String.fromEnvironment('GST_RATE')) ?? 0.18;

/// DEVELOPMENT / TEST COUPONS, the same codes and rules as the server's
/// Test Mode list (backend/src/commerce/coupons.ts). Never used in release
/// builds, which bill through the API.
const devCoupons = <DevCoupon>[
  DevCoupon('SKORX50', flat: 50, label: '₹50 off'),
  DevCoupon('PRO10', percent: 10, maxDiscount: 150, label: '10% off, up to ₹150'),
  DevCoupon('WELCOME', flat: 100, perUserLimit: 1, label: '₹100 off your first Pro plan'),
  DevCoupon('ANNUAL200', flat: 200, minSubtotal: 999, only: ProPlan.annual, label: '₹200 off the annual plan'),
  DevCoupon('MONTHLY20', flat: 20, only: ProPlan.monthly, label: '₹20 off the monthly plan'),
  DevCoupon('EXPIRED10', percent: 10, expiresOn: '2026-01-31', label: '10% off'),
  DevCoupon('SOLDOUT', flat: 30, maxRedemptions: 0, label: '₹30 off'),
];

class DevCoupon {
  const DevCoupon(
    this.code, {
    this.flat,
    this.percent,
    this.maxDiscount,
    this.minSubtotal,
    this.only,
    this.perUserLimit,
    this.maxRedemptions,
    this.expiresOn,
    required this.label,
  });

  final String code;
  final int? flat;
  final int? percent;
  final int? maxDiscount;
  final int? minSubtotal;
  final ProPlan? only;
  final int? perUserLimit;
  final int? maxRedemptions;

  /// Last valid day, India time.
  final String? expiresOn;
  final String label;

  int discountPaise(int subtotalPaise) {
    if (minSubtotal != null && subtotalPaise < minSubtotal! * 100) return 0;
    var off = flat != null ? flat! * 100 : (subtotalPaise * percent! / 100).round();
    if (percent != null && maxDiscount != null) off = min(off, maxDiscount! * 100);
    // Never below ₹1 payable (Razorpay's minimum charge).
    return max(0, min(off, subtotalPaise - 100));
  }
}

const _ist = Duration(hours: 5, minutes: 30);

/// The end of a period of [months] from [start]: the last moment, India time,
/// of the day before the same date [months] later (27 Sep 2026 runs to the
/// end of 26 Sep 2027). Same rule as the server's `periodEnd`.
DateTime proPeriodEnd(DateTime start, int months) {
  final local = start.toUtc().add(_ist);
  final m = local.month + months;
  final lastDay = DateTime.utc(local.year, m + 1, 0).day;
  final day = min(local.day, lastDay);
  return DateTime.utc(local.year, m, day - 1, 23, 59, 59, 999).subtract(_ist);
}

/// Razorpay Test Mode, on the phone: debug builds have no SkorX server, so
/// this stands in for it with the server's rules. It prices every order
/// itself (from [ProPlan] and [devCoupons]), only activates Pro after
/// checking the payment signature it issued, starts a period bought during
/// another when that one ends, and numbers invoices SKX-INV-2026-00001.
/// State is kept on the phone per account, so Pro survives a restart.
class DevBillingRepository implements BillingRepository {
  DevBillingRepository(
    this._prefs, {
    required this.userId,
    required this.customerName,
    this.customerPhone,
    this.customerEmail,
    this.latency = Duration.zero,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final SharedPreferencesAsync _prefs;
  final String userId;
  final String customerName;
  final String? customerPhone;
  final String? customerEmail;
  final Duration latency;
  final DateTime Function() _clock;
  final _random = Random();

  String get _key => 'skorx.dev.billing.$userId';

  Future<_State> _load() async {
    await simulateLatency(latency);
    final raw = await _prefs.getString(_key);
    return raw == null ? _State() : _State.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> _save(_State s) => _prefs.setString(_key, jsonEncode(s.toJson()));

  String _hex(int bytes) => List.generate(bytes, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

  DateTime get _now => _clock();

  // ─── Rules (as in backend/src/subscriptions) ────────────────────────────

  void _sweepExpired(_State s) {
    final now = _now;
    for (final p in s.periods) {
      if (p.paid && p.endsAt!.isBefore(now)) p.status = 'expired';
    }
  }

  _Period? _current(_State s) {
    final now = _now;
    final running = s.periods.where((p) => p.paid && !p.startsAt!.isAfter(now) && !now.isAfter(p.endsAt!)).toList()
      ..sort((a, b) => b.endsAt!.compareTo(a.endsAt!));
    return running.firstOrNull;
  }

  List<_Period> _upcoming(_State s) =>
      s.periods.where((p) => p.paid && p.startsAt!.isAfter(_now)).toList()..sort((a, b) => a.startsAt!.compareTo(b.startsAt!));

  DateTime _nextStart(_State s) {
    final running = s.periods.where((p) => p.paid && p.endsAt!.isAfter(_now)).toList()
      ..sort((a, b) => b.endsAt!.compareTo(a.endsAt!));
    return running.isEmpty ? _now : running.first.endsAt!.add(const Duration(milliseconds: 1));
  }

  DevCoupon? _coupon(_State s, String? code, ProPlan plan) {
    final wanted = (code ?? '').trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
    if (wanted.isEmpty) return null;
    Never reject(String why) => throw ApiException('COUPON_INVALID', why, status: 422);
    final c = devCoupons.where((c) => c.code == wanted).firstOrNull;
    if (c == null) reject("That coupon code isn't valid.");
    final used = s.orders.where((o) => o.status == 'paid' && o.couponCode == c.code).length;
    if (c.expiresOn != null && _now.isAfter(DateTime.parse('${c.expiresOn}T23:59:59.999+05:30'))) {
      reject('That coupon has expired.');
    }
    if (c.maxRedemptions != null && used >= c.maxRedemptions!) reject('That coupon has been fully redeemed.');
    if (c.only != null && c.only != plan) reject('${c.code} only works on the ${c.only!.label.toLowerCase()} plan.');
    if (c.perUserLimit != null && used >= c.perUserLimit!) reject("You've already used ${c.code}.");
    if (c.minSubtotal != null && plan.price < c.minSubtotal!) {
      reject('${c.code} needs a cart of at least ₹${c.minSubtotal} before GST.');
    }
    return c;
  }

  PriceQuote _price(_State s, ProPlan plan, DevCoupon? coupon) {
    final subtotal = plan.price * 100;
    final discount = coupon?.discountPaise(subtotal) ?? 0;
    final gst = ((subtotal - discount) * devGstRate).round();
    final start = _nextStart(s);
    return PriceQuote(
      plan: plan,
      subtotalPaise: subtotal,
      discountPaise: discount,
      couponCode: discount > 0 ? coupon!.code : null,
      couponLabel: discount > 0 ? coupon!.label : null,
      gstRate: devGstRate,
      gstPaise: gst,
      totalPaise: subtotal - discount + gst,
      startsAt: start,
      endsAt: proPeriodEnd(start, plan.months),
    );
  }

  _Order _owned(_State s, String orderId) {
    final o = s.orders.where((o) => o.id == orderId).firstOrNull;
    if (o == null) throw const ApiException('RESOURCE_NOT_FOUND', 'Order not found.', status: 404);
    return o;
  }

  void _closeUnpaid(_State s, _Order o, String status, String reason) {
    if (o.status == 'paid') return;
    o
      ..status = status
      ..failureReason = reason;
    for (final p in s.periods.where((p) => p.orderId == o.id && p.status == 'pending')) {
      p
        ..status = 'payment_failed'
        ..failureReason = reason;
    }
  }

  _Order _createOrder(_State s, ProPlan plan, DevCoupon? coupon, {String? renews}) {
    final price = _price(s, plan, coupon);
    final alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final id = 'SKX-${_now.year}-${List.generate(5, (_) => alphabet[_random.nextInt(alphabet.length)]).join()}';
    final order = _Order(
      id: id,
      razorpayOrderId: 'order_TEST${_hex(7)}',
      planId: plan.id,
      subtotalPaise: price.subtotalPaise,
      discountPaise: price.discountPaise,
      couponCode: price.couponCode,
      gstRate: price.gstRate,
      gstPaise: price.gstPaise,
      totalPaise: price.totalPaise,
      status: 'pending',
      createdAt: _now,
      renewal: renews != null,
    );
    s.orders.add(order);
    s.periods.add(_Period(id: 'sub_${_hex(6)}', orderId: id, planId: plan.id, status: 'pending', autoRenew: true, renewsId: renews));
    return order;
  }

  /// Marks paid, numbers the invoice and activates the period: once.
  void _markPaid(_State s, _Order o, String paymentId) {
    if (o.status == 'paid') return;
    final year = _now.year;
    final seq = (s.invoiceSeq['$year'] ?? 0) + 1;
    s.invoiceSeq['$year'] = seq;
    o
      ..status = 'paid'
      ..paidAt = _now
      ..paymentId = paymentId
      ..failureReason = null
      ..invoiceNumber = 'SKX-INV-$year-${seq.toString().padLeft(5, '0')}';
    final period = s.periods.firstWhere((p) => p.orderId == o.id);
    final start = _nextStart(s);
    period
      ..status = 'active'
      ..startsAt = start
      ..endsAt = proPeriodEnd(start, ProPlan.fromId(period.planId)!.months)
      ..failureReason = null;
  }

  SubscriptionSummary _summary(_State s) {
    _sweepExpired(s);
    final current = _current(s);
    final upcoming = _upcoming(s);
    final last = upcoming.lastOrNull ?? current;
    final latest = s.orders.lastOrNull;
    final everPro = s.periods.any((p) => p.paid || p.status == 'expired');
    return SubscriptionSummary(
      tier: current == null ? PlanTier.free : PlanTier.pro,
      status: current != null
          ? (current.status == 'cancelled' ? SubscriptionStatus.cancelled : SubscriptionStatus.active)
          : everPro
              ? SubscriptionStatus.expired
              : SubscriptionStatus.active,
      plan: current == null ? null : ProPlan.fromId(current.planId),
      startedAt: current?.startsAt,
      endsAt: current?.endsAt,
      nextBillingDate: last != null && last.autoRenew ? last.endsAt!.add(const Duration(milliseconds: 1)) : null,
      autoRenew: current?.autoRenew ?? false,
      payment: switch (latest?.status) {
        null => PaymentState.none,
        'paid' => PaymentState.paid,
        'pending' => PaymentState.pending,
        _ => PaymentState.failed,
      },
      pendingOrderId: latest?.status == 'pending' ? latest!.id : null,
      upcoming: [
        for (final p in upcoming)
          UpcomingPeriod(plan: ProPlan.fromId(p.planId)!, startsAt: p.startsAt!, endsAt: p.endsAt!, autoRenew: p.autoRenew),
      ],
      entitlements: current == null ? const {} : {for (final f in ProFeature.values) f.key},
      testMode: true,
      devTools: true,
    );
  }

  BillingRecord _record(_State s, _Order o) {
    final p = s.periods.firstWhere((p) => p.orderId == o.id);
    return BillingRecord(
      orderId: o.id,
      invoiceNumber: o.invoiceNumber,
      date: o.paidAt ?? o.createdAt,
      plan: ProPlan.fromId(o.planId)!,
      subtotalPaise: o.subtotalPaise,
      discountPaise: o.discountPaise,
      couponCode: o.couponCode,
      gstPaise: o.gstPaise,
      totalPaise: o.totalPaise,
      status: switch (o.status) {
        'paid' => BillingStatus.paid,
        'pending' => BillingStatus.pending,
        'cancelled' => BillingStatus.cancelled,
        _ => BillingStatus.failed,
      },
      periodStart: p.startsAt,
      periodEnd: p.endsAt,
      renewal: o.renewal,
      paymentId: o.paymentId,
      failureReason: o.failureReason,
      testMode: true,
    );
  }

  // ─── BillingRepository ──────────────────────────────────────────────────

  @override
  Future<SubscriptionSummary> summary() async {
    final s = await _load();
    final summary = _summary(s);
    await _save(s);
    return summary;
  }

  @override
  Future<PriceQuote> quote(ProPlan plan, {String? coupon}) async {
    final s = await _load();
    _sweepExpired(s);
    return _price(s, plan, _coupon(s, coupon, plan));
  }

  @override
  Future<CheckoutSession> checkout(ProPlan plan, {String? coupon}) async {
    final s = await _load();
    _sweepExpired(s);
    if (_upcoming(s).isNotEmpty) {
      throw const ApiException(
        'SUBSCRIPTION_CONFLICT',
        'Your next Pro period is already paid for. You can buy another once it starts.',
        status: 409,
      );
    }
    final c = _coupon(s, coupon, plan);
    for (final o in s.orders.where((o) => o.status == 'pending')) {
      _closeUnpaid(s, o, 'cancelled', 'Replaced by a newer checkout.');
    }
    final order = _createOrder(s, plan, c);
    await _save(s);
    return CheckoutSession(
      orderId: order.id,
      razorpayOrderId: order.razorpayOrderId,
      amountPaise: order.totalPaise,
      testMode: true,
      description: plan == ProPlan.annual ? 'SkorX Pro · Annual' : 'SkorX Pro · Monthly',
      prefillName: customerName,
      prefillEmail: customerEmail ?? '',
      prefillContact: customerPhone ?? '',
      quote: _price(s, plan, c),
    );
  }

  @override
  Future<GatewayPayment> simulatePayment(String orderId, {required bool succeed}) async {
    final s = await _load();
    final o = _owned(s, orderId);
    if (!succeed) throw const PaymentDeclined('Payment declined by the test bank (simulated).');
    final payment = GatewayPayment(orderId: o.razorpayOrderId, paymentId: 'pay_TEST${_hex(7)}', signature: _hex(32));
    // What the server's HMAC would be: only a payment "signed" here verifies.
    o.issuedSignatures[payment.paymentId] = payment.signature;
    await _save(s);
    return payment;
  }

  @override
  Future<VerifiedPayment> verify(String orderId, GatewayPayment payment) async {
    final s = await _load();
    final o = _owned(s, orderId);
    if (o.status != 'paid') {
      final valid = payment.orderId == o.razorpayOrderId && o.issuedSignatures[payment.paymentId] == payment.signature;
      if (!valid) {
        _closeUnpaid(s, o, 'failed', 'Payment could not be verified.');
        await _save(s);
        throw const ApiException(
          'PAYMENT_VERIFICATION_FAILED',
          "We couldn't verify this payment. Your plan hasn't changed.",
          status: 400,
        );
      }
      _markPaid(s, o, payment.paymentId);
    }
    final summary = _summary(s);
    await _save(s);
    return VerifiedPayment(summary, _record(s, o));
  }

  @override
  Future<SubscriptionSummary> reportFailure(String orderId, {required bool cancelled, String? reason}) async {
    final s = await _load();
    final o = _owned(s, orderId);
    _closeUnpaid(s, o, cancelled ? 'cancelled' : 'failed', reason ?? (cancelled ? 'Checkout closed.' : 'Payment failed.'));
    final summary = _summary(s);
    await _save(s);
    return summary;
  }

  @override
  Future<SubscriptionSummary> setAutoRenew(bool on) async {
    final s = await _load();
    _sweepExpired(s);
    final running = [?_current(s), ..._upcoming(s)];
    if (running.isEmpty) throw const ApiException('VALIDATION_ERROR', "You don't have an active Pro plan.", status: 422);
    for (final p in running) {
      p
        ..autoRenew = on
        ..status = on ? 'active' : 'cancelled';
    }
    final summary = _summary(s);
    await _save(s);
    return summary;
  }

  @override
  Future<List<BillingRecord>> history() async {
    final s = await _load();
    return [for (final o in s.orders.reversed) _record(s, o)];
  }

  @override
  Future<Invoice> invoice(String orderId) async {
    final s = await _load();
    final o = _owned(s, orderId);
    if (o.status != 'paid' || o.invoiceNumber == null) {
      throw const ApiException('RESOURCE_NOT_FOUND', 'An invoice is issued once the payment is complete.', status: 404);
    }
    final p = s.periods.firstWhere((p) => p.orderId == o.id);
    return Invoice(
      number: o.invoiceNumber!,
      date: o.paidAt!,
      sellerName: 'SkorX',
      customerName: customerName,
      customerEmail: customerEmail,
      customerPhone: customerPhone,
      plan: ProPlan.fromId(o.planId)!,
      basePaise: o.subtotalPaise,
      discountPaise: o.discountPaise,
      couponCode: o.couponCode,
      gstRate: o.gstRate,
      gstPaise: o.gstPaise,
      totalPaise: o.totalPaise,
      orderId: o.id,
      razorpayOrderId: o.razorpayOrderId,
      paymentId: o.paymentId,
      periodStart: p.startsAt,
      periodEnd: p.endsAt,
      testMode: true,
    );
  }

  @override
  Future<SubscriptionSummary> simulateRenewal() async {
    final s = await _load();
    _sweepExpired(s);
    final last = _upcoming(s).lastOrNull ?? _current(s);
    if (last == null) throw const ApiException('VALIDATION_ERROR', "You don't have an active Pro plan to renew.", status: 422);
    if (!last.autoRenew) throw const ApiException('VALIDATION_ERROR', 'Auto-renew is off, so this plan will not renew.', status: 422);
    final order = _createOrder(s, ProPlan.fromId(last.planId)!, null, renews: last.id);
    _markPaid(s, order, 'pay_TEST${_hex(7)}');
    final summary = _summary(s);
    await _save(s);
    return summary;
  }

  @override
  Future<SubscriptionSummary> expireNow() async {
    final s = await _load();
    _sweepExpired(s);
    final end = _now.subtract(const Duration(seconds: 1));
    for (final p in [?_current(s), ..._upcoming(s)]) {
      p
        ..status = 'expired'
        ..endsAt = end
        ..startsAt = p.startsAt!.isAfter(end) ? end : p.startsAt;
    }
    final summary = _summary(s);
    await _save(s);
    return summary;
  }
}

class _State {
  _State({List<_Order>? orders, List<_Period>? periods, Map<String, int>? invoiceSeq})
      : orders = orders ?? [],
        periods = periods ?? [],
        invoiceSeq = invoiceSeq ?? {};

  final List<_Order> orders;
  final List<_Period> periods;
  final Map<String, int> invoiceSeq;

  Map<String, dynamic> toJson() => {
        'orders': [for (final o in orders) o.toJson()],
        'periods': [for (final p in periods) p.toJson()],
        'invoiceSeq': invoiceSeq,
      };

  factory _State.fromJson(Map<String, dynamic> j) => _State(
        orders: [for (final o in j['orders'] as List<dynamic>) _Order.fromJson(o as Map<String, dynamic>)],
        periods: [for (final p in j['periods'] as List<dynamic>) _Period.fromJson(p as Map<String, dynamic>)],
        invoiceSeq: (j['invoiceSeq'] as Map<String, dynamic>).map((k, v) => MapEntry(k, v as int)),
      );
}

DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String);

class _Order {
  _Order({
    required this.id,
    required this.razorpayOrderId,
    required this.planId,
    required this.subtotalPaise,
    required this.discountPaise,
    required this.gstRate,
    required this.gstPaise,
    required this.totalPaise,
    required this.status,
    required this.createdAt,
    this.couponCode,
    this.renewal = false,
    this.paymentId,
    this.paidAt,
    this.invoiceNumber,
    this.failureReason,
    Map<String, String>? issuedSignatures,
  }) : issuedSignatures = issuedSignatures ?? {};

  final String id;
  final String razorpayOrderId;
  final String planId;
  final int subtotalPaise;
  final int discountPaise;
  final String? couponCode;
  final double gstRate;
  final int gstPaise;
  final int totalPaise;
  final DateTime createdAt;
  final bool renewal;
  String status;
  String? paymentId;
  DateTime? paidAt;
  String? invoiceNumber;
  String? failureReason;
  final Map<String, String> issuedSignatures;

  Map<String, dynamic> toJson() => {
        'id': id,
        'razorpayOrderId': razorpayOrderId,
        'planId': planId,
        'subtotalPaise': subtotalPaise,
        'discountPaise': discountPaise,
        'couponCode': couponCode,
        'gstRate': gstRate,
        'gstPaise': gstPaise,
        'totalPaise': totalPaise,
        'status': status,
        'createdAt': createdAt.toIso8601String(),
        'renewal': renewal,
        'paymentId': paymentId,
        'paidAt': paidAt?.toIso8601String(),
        'invoiceNumber': invoiceNumber,
        'failureReason': failureReason,
        'issuedSignatures': issuedSignatures,
      };

  factory _Order.fromJson(Map<String, dynamic> j) => _Order(
        id: j['id'] as String,
        razorpayOrderId: j['razorpayOrderId'] as String,
        planId: j['planId'] as String,
        subtotalPaise: j['subtotalPaise'] as int,
        discountPaise: j['discountPaise'] as int,
        couponCode: j['couponCode'] as String?,
        gstRate: (j['gstRate'] as num).toDouble(),
        gstPaise: j['gstPaise'] as int,
        totalPaise: j['totalPaise'] as int,
        status: j['status'] as String,
        createdAt: _date(j['createdAt'])!,
        renewal: j['renewal'] as bool? ?? false,
        paymentId: j['paymentId'] as String?,
        paidAt: _date(j['paidAt']),
        invoiceNumber: j['invoiceNumber'] as String?,
        failureReason: j['failureReason'] as String?,
        issuedSignatures: (j['issuedSignatures'] as Map<String, dynamic>? ?? const {}).cast<String, String>(),
      );
}

class _Period {
  _Period({
    required this.id,
    required this.orderId,
    required this.planId,
    required this.status,
    required this.autoRenew,
    this.startsAt,
    this.endsAt,
    this.renewsId,
    this.failureReason,
  });

  final String id;
  final String orderId;
  final String planId;
  String status;
  DateTime? startsAt;
  DateTime? endsAt;
  bool autoRenew;
  final String? renewsId;
  String? failureReason;

  /// Paid periods are the only ones that ever give Pro.
  bool get paid => (status == 'active' || status == 'cancelled') && startsAt != null && endsAt != null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'orderId': orderId,
        'planId': planId,
        'status': status,
        'startsAt': startsAt?.toIso8601String(),
        'endsAt': endsAt?.toIso8601String(),
        'autoRenew': autoRenew,
        'renewsId': renewsId,
        'failureReason': failureReason,
      };

  factory _Period.fromJson(Map<String, dynamic> j) => _Period(
        id: j['id'] as String,
        orderId: j['orderId'] as String,
        planId: j['planId'] as String,
        status: j['status'] as String,
        startsAt: _date(j['startsAt']),
        endsAt: _date(j['endsAt']),
        autoRenew: j['autoRenew'] as bool? ?? true,
        renewsId: j['renewsId'] as String?,
        failureReason: j['failureReason'] as String?,
      );
}
