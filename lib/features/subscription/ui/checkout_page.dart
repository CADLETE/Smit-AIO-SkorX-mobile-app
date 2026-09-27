import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../design/design.dart';
import '../../../shared/format.dart';
import '../data/plans.dart';
import '../data/subscription.dart';
import '../subscription_controller.dart';
import 'payment_gateway.dart';
import 'pro_widgets.dart';

/// Pay for [plan]: coupon, the server's price breakdown, Razorpay (or its
/// Test Mode stand-in), then the server's verification. Pro is only shown as
/// active once the server has verified the payment.
class CheckoutPage extends ConsumerStatefulWidget {
  const CheckoutPage({super.key, required this.plan});

  final ProPlan plan;

  @override
  ConsumerState<CheckoutPage> createState() => _CheckoutPageState();
}

enum _Stage { ready, paying, verifying, unconfirmed }

class _CheckoutPageState extends ConsumerState<CheckoutPage> {
  final _code = TextEditingController();
  PriceQuote? _quote;
  String? _coupon;
  String? _couponError;
  String? _error;
  bool _applying = false;
  _Stage _stage = _Stage.ready;

  /// A payment Checkout reported that the server has not confirmed yet.
  ({String orderId, GatewayPayment payment})? _unconfirmed;

  @override
  void initState() {
    super.initState();
    _loadQuote();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _loadQuote() async {
    try {
      final q = await ref.read(billingRepositoryProvider).quote(widget.plan, coupon: _coupon);
      if (mounted) setState(() => _quote = q);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _applyCoupon() async {
    final code = _code.text.trim();
    if (code.isEmpty || _applying) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _applying = true;
      _couponError = null;
    });
    try {
      final q = await ref.read(billingRepositoryProvider).quote(widget.plan, coupon: code);
      if (!mounted) return;
      setState(() {
        _quote = q;
        _coupon = q.couponCode;
        if (q.couponCode == null) _couponError = "That coupon doesn't take anything off this plan.";
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _couponError = e.message);
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  void _removeCoupon() {
    _code.clear();
    setState(() {
      _coupon = null;
      _couponError = null;
    });
    _loadQuote();
  }

  Future<void> _pay() async {
    final repo = ref.read(billingRepositoryProvider);
    final subscription = ref.read(subscriptionProvider.notifier);
    setState(() {
      _stage = _Stage.paying;
      _error = null;
    });
    try {
      final session = await repo.checkout(widget.plan, coupon: _coupon);
      if (!mounted) return;
      final outcome = await gatewayFor(ref, session).pay(context, session);
      switch (outcome) {
        case GatewayPaid(:final payment):
          await _verify(session.orderId, payment);
        case GatewayFailed(:final reason):
          await _report(() => repo.reportFailure(session.orderId, cancelled: false, reason: reason));
          if (mounted) context.pushReplacement('/player/pro/failed?plan=${widget.plan.name}&reason=${Uri.encodeComponent(reason)}');
        case GatewayDismissed():
          await _report(() => repo.reportFailure(session.orderId, cancelled: true));
          if (!mounted) return;
          setState(() => _stage = _Stage.ready);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment cancelled. You have not been charged.')));
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _stage = _Stage.ready;
          _error = e.message;
        });
      }
    } finally {
      // Whatever happened, show the plan the server now has.
      await subscription.refresh();
    }
  }

  /// A failure report that does not reach the server changes nothing: the
  /// order stays unpaid and is closed by the server later.
  Future<void> _report(Future<SubscriptionSummary> Function() call) async {
    try {
      ref.read(subscriptionProvider.notifier).apply(await call());
    } catch (_) {}
  }

  Future<void> _verify(String orderId, GatewayPayment payment) async {
    setState(() => _stage = _Stage.verifying);
    try {
      final verified = await ref.read(billingRepositoryProvider).verify(orderId, payment);
      ref.read(subscriptionProvider.notifier).apply(verified.summary);
      if (mounted) context.pushReplacement('/player/pro/welcome?order=${Uri.encodeComponent(orderId)}');
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isNetwork) {
        // Paid, maybe, but not confirmed: never show Pro on the app's word.
        setState(() {
          _stage = _Stage.unconfirmed;
          _unconfirmed = (orderId: orderId, payment: payment);
        });
      } else {
        context.pushReplacement('/player/pro/failed?plan=${widget.plan.name}&reason=${Uri.encodeComponent(e.message)}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final q = _quote;
    final plan = widget.plan;
    final busy = _stage == _Stage.paying || _stage == _Stage.verifying;
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        body: SafeArea(
          child: SxWidth(
            child: Column(
              children: [
                SxBackBar(onBack: busy ? null : () => context.canPop() ? context.pop() : context.go('/player/pro')),
                const SxTitleBar(title: 'Checkout'),
                Expanded(
                  child: _stage == _Stage.unconfirmed
                      ? _Unconfirmed(onRetry: () => _verify(_unconfirmed!.orderId, _unconfirmed!.payment))
                      : ListView(
                          key: const Key('checkout'),
                          padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s8, Sx.gutter, Sx.s24),
                          children: [
                            _PlanSummary(plan: plan, quote: q),
                            const SizedBox(height: Sx.section),
                            const SxSection('Have a coupon?'),
                            if (_coupon != null && q != null)
                              _AppliedCoupon(code: _coupon!, label: q.couponLabel, discountPaise: q.discountPaise, onRemove: busy ? null : _removeCoupon)
                            else
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: TextField(
                                      key: const Key('couponField'),
                                      controller: _code,
                                      enabled: !busy,
                                      textCapitalization: TextCapitalization.characters,
                                      textInputAction: TextInputAction.done,
                                      onSubmitted: (_) => _applyCoupon(),
                                      decoration: InputDecoration(hintText: 'ENTER COUPON CODE', errorText: _couponError, errorMaxLines: 2),
                                    ),
                                  ),
                                  const SizedBox(width: Sx.s8),
                                  SizedBox(
                                    width: 104,
                                    child: SxButton.secondary(
                                      key: const Key('applyCoupon'),
                                      label: 'Apply',
                                      busy: _applying,
                                      onPressed: busy ? null : _applyCoupon,
                                    ),
                                  ),
                                ],
                              ),
                            const SizedBox(height: Sx.section),
                            const SxSection('Price'),
                            if (q == null && _error == null) const Skeleton(height: 160, radius: Sx.radiusLg) else if (q != null) _Breakdown(quote: q),
                            if (_error != null) ...[
                              const SizedBox(height: Sx.s16),
                              Text(_error!, key: const Key('checkoutError'), style: SxType.body(c.live, size: 14)),
                            ],
                            if (q != null && ref.watch(subscriptionProvider).value?.testMode == true) ...[
                              const SizedBox(height: Sx.s16),
                              Text('Test Mode: the payment is simulated. No real money moves.', style: SxType.caption(c.caution, size: 12.5)),
                            ],
                          ],
                        ),
                ),
                if (_stage != _Stage.unconfirmed)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s8, Sx.gutter, Sx.s16),
                    child: SxButton(
                      key: const Key('payNow'),
                      label: q == null ? 'Pay' : 'Pay ${formatPaise(q.totalPaise)}',
                      icon: Icons.lock_rounded,
                      busy: busy,
                      onPressed: q == null ? null : _pay,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlanSummary extends StatelessWidget {
  const _PlanSummary({required this.plan, required this.quote});

  final ProPlan plan;
  final PriceQuote? quote;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final starts = quote?.startsAt;
    final now = DateTime.now();
    final later = starts != null && starts.difference(now) > const Duration(minutes: 5);
    return SxBlock(
      child: Row(
        children: [
          SxIconTile(icon: Icons.bolt_rounded, colors: [c.voltFill, c.olive]),
          const SizedBox(width: Sx.s16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text('SkorX Pro', style: SxType.heading(c.ink, size: 17)),
                  const SizedBox(width: Sx.s8),
                  const ProBadge(size: 10),
                ]),
                Text('${plan.label} · ₹${plan.price} + GST / ${plan.per}', style: SxType.caption(c.inkMuted)),
                if (quote?.endsAt case final ends?) ...[
                  const SizedBox(height: Sx.s4),
                  Text(
                    later
                        ? 'Starts ${billingDate(starts)}, after your current plan · runs to ${billingDate(ends)}'
                        : 'Starts today · renews ${billingDate(ends.add(const Duration(milliseconds: 1)))}',
                    key: const Key('periodLine'),
                    style: SxType.caption(c.ink, size: 12.5),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AppliedCoupon extends StatelessWidget {
  const _AppliedCoupon({required this.code, required this.label, required this.discountPaise, required this.onRemove});

  final String code;
  final String? label;
  final int discountPaise;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Container(
      key: const Key('couponApplied'),
      padding: const EdgeInsets.all(Sx.s16),
      decoration: BoxDecoration(
        color: c.voltFill.withValues(alpha: c.isDark ? 0.1 : 0.16),
        borderRadius: BorderRadius.circular(Sx.radius),
        border: Border.all(color: c.voltFill.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded, color: c.volt),
          const SizedBox(width: Sx.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Coupon applied', style: SxType.heading(c.ink, size: 15)),
                Text('$code · Discount ${formatPaise(discountPaise)}', style: SxType.caption(c.inkMuted)),
              ],
            ),
          ),
          TextButton(key: const Key('removeCoupon'), onPressed: onRemove, child: const Text('Remove')),
        ],
      ),
    );
  }
}

class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.quote});

  final PriceQuote quote;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    Widget line(String label, String value, {Key? key, bool strong = false, Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(label, style: strong ? SxType.heading(c.ink, size: 17) : SxType.body(c.inkMuted, size: 15)),
              ),
              Text(
                value,
                key: key,
                style: strong ? SxType.number(24, c.ink, weight: FontWeight.w800) : SxType.body(color ?? c.ink, size: 15),
              ),
            ],
          ),
        );
    return SxBlock(
      key: const Key('priceBreakdown'),
      child: Column(
        children: [
          line('SkorX Pro ${quote.plan.label}', formatPaise(quote.subtotalPaise), key: const Key('pricePlan')),
          if (quote.discountPaise > 0)
            line('Coupon ${quote.couponCode ?? ''}', formatPaise(-quote.discountPaise), key: const Key('priceDiscount'), color: c.volt),
          line('GST (${quote.gstPercent})', formatPaise(quote.gstPaise), key: const Key('priceGst')),
          Divider(height: Sx.s24, color: c.line),
          line('Total', formatPaise(quote.totalPaise), key: const Key('priceTotal'), strong: true),
        ],
      ),
    );
  }
}

class _Unconfirmed extends StatelessWidget {
  const _Unconfirmed({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(Sx.gutter),
      child: EmptyBlock(
        key: const Key('paymentUnconfirmed'),
        icon: Icons.hourglass_top_rounded,
        title: 'Confirming your payment',
        message:
            'We could not reach SkorX to confirm it. If money left your account, Pro turns on as soon as Razorpay confirms the payment; you will not be charged twice.',
        action: SxButton.secondary(label: 'Check again', expand: false, onPressed: onRetry),
      ),
    );
  }
}
