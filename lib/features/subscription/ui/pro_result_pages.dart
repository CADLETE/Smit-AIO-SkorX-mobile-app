import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design/design.dart';
import '../data/plans.dart';
import '../subscription_controller.dart';
import 'pro_widgets.dart';

/// After a verified payment: Pro is on, everywhere, right now.
class ProWelcomePage extends ConsumerWidget {
  const ProWelcomePage({super.key, this.orderId});

  /// The order just paid, for its receipt.
  final String? orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(subscriptionProvider).value;
    final c = context.sx;
    return Scaffold(
      body: SafeArea(
        child: SxWidth(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  key: const Key('proWelcome'),
                  padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s32, Sx.gutter, Sx.s24),
                  children: [
                    SxReveal(
                      child: SxHeroCard(
                        watermark: true,
                        child: SxOnHero(
                          child: Builder(builder: (context) {
                            final c = context.sx;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const ProBadge(size: 13),
                                const SizedBox(height: Sx.s16),
                                Text('Welcome to SkorX Pro 🎉', style: SxType.title(c.ink, size: 34)),
                                const SizedBox(height: Sx.s8),
                                Text('Your Pro plan is now active.', style: SxType.body(c.inkMuted, size: 16)),
                                if (s?.plan != null && s?.nextBillingDate != null) ...[
                                  const SizedBox(height: Sx.s12),
                                  Text(
                                    '${s!.plan!.label} · next billing ${billingDate(s.nextBillingDate!)}',
                                    style: SxType.caption(c.ink).copyWith(fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ],
                            );
                          }),
                        ),
                      ),
                    ),
                    const SizedBox(height: Sx.section),
                    Text('You now have access to:', style: SxType.heading(c.ink, size: 17)),
                    const SizedBox(height: Sx.s16),
                    const SxReveal(index: 1, child: ProFeatureList(titles: true)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s8, Sx.gutter, Sx.s16),
                child: Column(
                  children: [
                    SxButton(
                      key: const Key('exploreProFeatures'),
                      label: 'Explore Pro Features',
                      icon: Icons.bolt_rounded,
                      onPressed: () => context.go('/player/paddle'),
                    ),
                    if (orderId != null) ...[
                      const SizedBox(height: Sx.s8),
                      SxButton.quiet(
                        key: const Key('viewReceipt'),
                        label: 'View invoice',
                        onPressed: () => context.pushReplacement('/player/billing/${Uri.encodeComponent(orderId!)}'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The payment did not go through. Nothing changed on the account.
class PaymentFailedPage extends ConsumerWidget {
  const PaymentFailedPage({super.key, required this.plan, this.reason});

  final ProPlan plan;
  final String? reason;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final pro = ref.watch(isProProvider);
    return Scaffold(
      body: SafeArea(
        child: SxWidth(
          child: Column(
            children: [
              SxBackBar(onBack: () => context.canPop() ? context.pop() : context.go('/player/pro')),
              Expanded(
                child: ListView(
                  key: const Key('paymentFailed'),
                  padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s24, Sx.gutter, Sx.s24),
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(color: c.live.withValues(alpha: 0.12), shape: BoxShape.circle),
                      child: Icon(Icons.close_rounded, color: c.live, size: 36),
                    ),
                    const SizedBox(height: Sx.s24),
                    Text('Payment Failed', style: SxType.title(c.ink, size: 34)),
                    const SizedBox(height: Sx.s8),
                    Text('Your payment could not be completed.', style: SxType.body(c.ink, size: 16)),
                    const SizedBox(height: Sx.s4),
                    Text(
                      pro ? 'Your Pro plan has not changed.' : 'Your Free plan is still active.',
                      key: const Key('planUnchanged'),
                      style: SxType.body(c.inkMuted, size: 16),
                    ),
                    if (reason != null && reason!.isNotEmpty) ...[
                      const SizedBox(height: Sx.s16),
                      Text(reason!, style: SxType.caption(c.inkMuted)),
                    ],
                    const SizedBox(height: Sx.s8),
                    Text('If any money left your account, it is refunded automatically.', style: SxType.caption(c.inkMuted)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s8, Sx.gutter, Sx.s16),
                child: Column(
                  children: [
                    SxButton(
                      key: const Key('tryAgain'),
                      label: 'Try Again',
                      icon: Icons.refresh_rounded,
                      onPressed: () => context.pushReplacement('/player/pro/checkout?plan=${plan.name}'),
                    ),
                    const SizedBox(height: Sx.s8),
                    SxButton.secondary(
                      key: const Key('chooseAnotherPlan'),
                      label: 'Choose Another Plan',
                      onPressed: () => context.pushReplacement('/player/pro'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
