import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design/design.dart';
import '../../../shared/format.dart';
import '../data/billing_repository.dart';
import '../data/subscription.dart';
import '../subscription_controller.dart';

/// How a Checkout ended, before the server has checked anything.
sealed class GatewayOutcome {
  const GatewayOutcome();
}

/// Checkout says it was paid. Means nothing until the server verifies it.
class GatewayPaid extends GatewayOutcome {
  const GatewayPaid(this.payment);

  final GatewayPayment payment;
}

class GatewayFailed extends GatewayOutcome {
  const GatewayFailed(this.reason);

  final String reason;
}

/// The player closed Checkout without paying.
class GatewayDismissed extends GatewayOutcome {
  const GatewayDismissed();
}

/// Razorpay Checkout, or its Test Mode stand-in. Chosen per order from what
/// the server says ([CheckoutSession.testMode]), so switching to live keys
/// on the server switches the app too.
abstract class PaymentGateway {
  Future<GatewayOutcome> pay(BuildContext context, CheckoutSession session);
}

/// Live Razorpay Checkout. This build has no Razorpay SDK yet, so a live
/// order is refused here rather than half-paid; override this provider with
/// a `razorpay_flutter` implementation to take live payments (see
/// docs/SUBSCRIPTIONS.md, "Test Mode to Live").
final livePaymentGatewayProvider = Provider<PaymentGateway>((ref) => const _NoLiveGateway());

PaymentGateway gatewayFor(WidgetRef ref, CheckoutSession session) =>
    session.testMode ? TestModeGateway(ref.read(billingRepositoryProvider)) : ref.read(livePaymentGatewayProvider);

class _NoLiveGateway implements PaymentGateway {
  const _NoLiveGateway();

  @override
  Future<GatewayOutcome> pay(BuildContext context, CheckoutSession session) async =>
      const GatewayFailed('Live payments are not available in this version of the app yet.');
}

/// Razorpay Test Mode: a stand-in for the Checkout popup. The payment it
/// "makes" is issued by the server (or its on-phone stand-in), so the
/// server's signature check still runs. No real money moves.
class TestModeGateway implements PaymentGateway {
  TestModeGateway(this._repo);

  final BillingRepository _repo;

  @override
  Future<GatewayOutcome> pay(BuildContext context, CheckoutSession session) async {
    final choice = await showSxSheet<bool>(context, builder: (_) => _TestCheckout(session: session));
    if (choice == null) return const GatewayDismissed();
    try {
      return GatewayPaid(await _repo.simulatePayment(session.orderId, succeed: choice));
    } on PaymentDeclined catch (e) {
      return GatewayFailed(e.reason);
    }
  }
}

class _TestCheckout extends StatelessWidget {
  const _TestCheckout({required this.session});

  final CheckoutSession session;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return SingleChildScrollView(
      key: const Key('testCheckout'),
      padding: const EdgeInsets.fromLTRB(Sx.gutter, 0, Sx.gutter, Sx.s24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined, color: c.info, size: 20),
              const SizedBox(width: Sx.s8),
              Expanded(child: Text('Razorpay · Test Mode', style: SxType.heading(c.ink, size: 16))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: c.caution.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(6)),
                child: Text('TEST', style: SxType.label(c.caution, size: 10.5)),
              ),
            ],
          ),
          const SizedBox(height: Sx.s20),
          Text(session.description, style: SxType.body(c.inkMuted)),
          const SizedBox(height: Sx.s4),
          Text(formatPaise(session.amountPaise), style: SxType.number(40, c.ink, weight: FontWeight.w800)),
          const SizedBox(height: Sx.s4),
          Text('Order ${session.razorpayOrderId}', style: SxType.caption(c.inkFaint, size: 12)),
          if (session.prefillContact.isNotEmpty) ...[
            const SizedBox(height: Sx.s12),
            Text('Paying as ${session.prefillName} · ${formatPhone(session.prefillContact)}', style: SxType.caption(c.inkMuted)),
          ],
          const SizedBox(height: Sx.s20),
          Container(
            padding: const EdgeInsets.all(Sx.s12),
            decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(Sx.radiusSm)),
            child: Text(
              'No real money moves. Choose how this test payment ends; SkorX then verifies it as it would a real one.',
              style: SxType.caption(c.inkMuted, size: 12.5),
            ),
          ),
          const SizedBox(height: Sx.s20),
          SxButton(
            key: const Key('testPaySuccess'),
            label: 'Pay ${formatPaise(session.amountPaise)}',
            icon: Icons.check_rounded,
            onPressed: () => Navigator.of(context).pop(true),
          ),
          const SizedBox(height: Sx.s8),
          SxButton.secondary(
            key: const Key('testPayFail'),
            label: 'Simulate a failed payment',
            icon: Icons.close_rounded,
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    );
  }
}
