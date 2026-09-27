import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../design/design.dart';
import '../data/plans.dart';
import '../data/subscription.dart';
import '../subscription_controller.dart';
import 'billing_pages.dart';
import 'plan_card.dart';

/// Profile › Subscription: the plan, its dates and renewal, changing plan,
/// and the billing history.
class SubscriptionPage extends ConsumerStatefulWidget {
  const SubscriptionPage({super.key});

  @override
  ConsumerState<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends ConsumerState<SubscriptionPage> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, {String? done}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(billingHistoryProvider);
      if (mounted && done != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleRenew(SubscriptionSummary s, bool on) async {
    if (!on) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Turn off auto-renew?'),
          content: Text(
            'You keep Pro until ${s.proUntil == null ? 'the end of your paid period' : billingDate(s.proUntil!)}. After that your account moves to Free; your matches and history stay.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep Pro')),
            FilledButton(key: const Key('confirmCancel'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Turn off')),
          ],
        ),
      );
      if (ok != true) return;
    }
    await _run(() => ref.read(subscriptionProvider.notifier).setAutoRenew(on),
        done: on ? 'Auto-renew is on.' : 'Auto-renew is off. Pro stays until the end of your paid period.');
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(subscriptionProvider).value;
    final c = context.sx;
    return Scaffold(
      body: SafeArea(
        child: SxWidth(
          child: Column(
            children: [
              SxBackBar(onBack: () => context.canPop() ? context.pop() : context.go('/player/profile')),
              const SxTitleBar(title: 'Subscription'),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    await ref.read(subscriptionProvider.notifier).refresh();
                    ref.invalidate(billingHistoryProvider);
                  },
                  color: c.onVolt,
                  backgroundColor: c.voltFill,
                  child: ListView(
                    key: const Key('subscriptionPage'),
                    padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s8, Sx.gutter, Sx.s48),
                    children: [
                      const YourPlanCard(showManage: false),
                      if (s != null && s.isPro) ...[
                        const SizedBox(height: Sx.section),
                        SxRows(title: 'Details', children: [
                          SxRow(label: 'Plan', value: 'SkorX Pro'),
                          SxRow(label: 'Billing cycle', value: s.plan == null ? '—' : '${s.plan!.label} · ₹${s.plan!.price} + GST'),
                          SxRow(label: 'Started on', value: s.startedAt == null ? '—' : billingDate(s.startedAt!)),
                          SxRow(
                            label: s.nextBillingDate == null ? 'Pro until' : 'Next billing date',
                            value: billingDate((s.nextBillingDate ?? s.proUntil)!),
                          ),
                          SxRow(label: 'Status', value: s.status == SubscriptionStatus.cancelled ? 'Active · ends ${billingDate(s.proUntil!)}' : 'Active'),
                          SxRow(
                            key: const Key('autoRenewRow'),
                            label: 'Auto-renew',
                            subtitle: s.autoRenew ? 'Renews automatically' : 'Will not renew',
                            trailing: Switch(
                              key: const Key('autoRenewSwitch'),
                              value: s.autoRenew,
                              onChanged: _busy ? null : (on) => _toggleRenew(s, on),
                            ),
                          ),
                          for (final u in s.upcoming)
                            SxRow(label: 'Then', value: '${u.plan.label} · ${billingDate(u.startsAt)} – ${billingDate(u.endsAt)}'),
                        ]),
                        const SizedBox(height: Sx.s16),
                        if (s.upcoming.isEmpty)
                          SxButton.secondary(
                            key: const Key('changePlan'),
                            label: 'Change plan',
                            icon: Icons.swap_horiz_rounded,
                            onPressed: () => context.push('/player/pro'),
                          ),
                      ] else if (s != null) ...[
                        const SizedBox(height: Sx.s16),
                        SxButton(
                          key: const Key('upgradeToPro'),
                          label: s.status == SubscriptionStatus.expired ? 'Renew Pro' : 'Upgrade to Pro',
                          icon: Icons.bolt_rounded,
                          onPressed: () => context.push('/player/pro'),
                        ),
                      ],
                      const SizedBox(height: Sx.section),
                      const BillingHistoryList(limit: 3),
                      if (s != null && s.devTools) ...[
                        const SizedBox(height: Sx.section),
                        SxRows(title: 'Test Mode tools', children: [
                          SxRow(
                            key: const Key('devRenew'),
                            icon: Icons.autorenew_rounded,
                            label: 'Simulate renewal',
                            subtitle: 'Charge the next period now, as auto-renew will',
                            onTap: s.isPro && !_busy
                                ? () => _run(() => ref.read(subscriptionProvider.notifier).simulateRenewal(), done: 'Renewed (simulated).')
                                : null,
                          ),
                          SxRow(
                            key: const Key('devExpire'),
                            icon: Icons.timer_off_outlined,
                            label: 'Expire Pro now',
                            subtitle: 'End the paid period, to check the Free fallback',
                            onTap: s.isPro && !_busy
                                ? () => _run(() => ref.read(subscriptionProvider.notifier).expireNow(), done: 'Pro has expired (simulated).')
                                : null,
                          ),
                        ]),
                        const SizedBox(height: Sx.s8),
                        Text(
                          'Test coupons: SKORX50 (₹50 off) · PRO10 (10%) · WELCOME (₹100, once) · ANNUAL200 (annual only) · MONTHLY20 (monthly only) · EXPIRED10 (expired) · SOLDOUT (used up)',
                          style: SxType.caption(c.inkMuted, size: 12),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
