import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design/design.dart';
import '../data/plans.dart';
import '../data/subscription.dart';
import '../subscription_controller.dart';
import 'pro_widgets.dart';

/// "Your plan": Free with what it includes and what Pro adds, or Pro with
/// its cycle, dates and renewal. Answers "what plan am I on, what do I get,
/// and what happens if I upgrade?" at a glance.
class YourPlanCard extends ConsumerWidget {
  const YourPlanCard({super.key, this.showManage = true});

  /// The "Manage plan" / "Upgrade" action; off on the manage page itself.
  final bool showManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sub = ref.watch(subscriptionProvider);
    // A reload keeps the plan on screen.
    if (sub.value case final s?) {
      return s.isPro ? _ProCard(s: s, showManage: showManage) : _FreeCard(s: s, showManage: showManage);
    }
    if (sub.hasError) return ErrorBlock(message: 'Your plan did not load.', onRetry: () => ref.invalidate(subscriptionProvider));
    return const Skeleton(height: 180, radius: Sx.radiusLg);
  }
}

/// Pro: a compact header (PRO, active, the plan) that opens on tap to show
/// the dates, renewal and Manage Plan. Starts closed on Profile, open on the
/// Subscription page. No ball: this card sits under the ID card, which has one.
class _ProCard extends StatefulWidget {
  const _ProCard({required this.s, required this.showManage});

  final SubscriptionSummary s;
  final bool showManage;

  @override
  State<_ProCard> createState() => _ProCardState();
}

class _ProCardState extends State<_ProCard> {
  late bool _open = !widget.showManage;

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final plan = s.plan ?? ProPlan.monthly;
    return Semantics(
      button: true,
      expanded: _open,
      label: 'Your plan: Pro, ${plan.label}. ${_open ? 'Hide' : 'Show'} details',
      child: Tappable(
        key: const Key('planCard-pro'),
        radius: Sx.radiusLg + 2,
        onTap: () => setState(() => _open = !_open),
        child: SxHeroCard(
          ball: false,
          padding: const EdgeInsets.all(Sx.s20),
          child: SxOnHero(
            child: Builder(builder: (context) {
              final c = context.sx;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('YOUR PLAN', style: SxType.label(c.inkMuted, size: 12)),
                  const SizedBox(height: Sx.s4),
                  Row(
                    children: [
                      Text('PRO', style: SxType.hero(40, c.ink)),
                      const SizedBox(width: Sx.s12),
                      _StatePill(cancelled: s.status == SubscriptionStatus.cancelled),
                      const Spacer(),
                      AnimatedRotation(
                        turns: _open ? 0.5 : 0,
                        duration: Sx.fast,
                        child: Icon(Icons.expand_more_rounded, color: c.ink, size: 28),
                      ),
                    ],
                  ),
                  Text('${plan.label} plan · ₹${plan.price} + GST / ${plan.per}', style: SxType.body(c.ink)),
                  AnimatedSize(
                    duration: Sx.medium,
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: !_open
                        ? const SizedBox(width: double.infinity)
                        : Column(
                            key: const Key('planDetails'),
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(height: Sx.s16),
                              _Line('Started', s.startedAt == null ? '—' : billingDate(s.startedAt!)),
                              if (s.nextBillingDate != null)
                                _Line('Next billing', billingDate(s.nextBillingDate!))
                              else if (s.proUntil != null)
                                _Line('Pro until', billingDate(s.proUntil!)),
                              _Line('Auto-renew', s.autoRenew ? 'ON' : 'OFF'),
                              if (s.upcoming.isNotEmpty)
                                _Line('Then', '${s.upcoming.first.plan.label} from ${billingDate(s.upcoming.first.startsAt)}'),
                              if (widget.showManage) ...[
                                const SizedBox(height: Sx.s16),
                                SxButton.secondary(
                                  key: const Key('managePlan'),
                                  label: 'Manage Plan',
                                  icon: Icons.tune_rounded,
                                  onPressed: () => context.push('/player/subscription'),
                                ),
                              ],
                            ],
                          ),
                  ),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _StatePill extends StatelessWidget {
  const _StatePill({required this.cancelled});

  final bool cancelled;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: cancelled ? Colors.white.withValues(alpha: 0.16) : c.voltFill,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(cancelled ? 'ENDS SOON' : 'ACTIVE', style: SxType.label(cancelled ? Colors.white : c.onVolt, size: 11)),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(width: 108, child: Text(label, style: SxType.caption(c.inkMuted))),
          Expanded(child: Text(value, style: SxType.caption(c.ink).copyWith(fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }
}

class _FreeCard extends StatelessWidget {
  const _FreeCard({required this.s, required this.showManage});

  final SubscriptionSummary s;
  final bool showManage;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final expired = s.status == SubscriptionStatus.expired;
    return SxBlock(
      key: const Key('planCard-free'),
      padding: const EdgeInsets.all(Sx.s20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('YOUR PLAN', style: SxType.label(c.inkMuted, size: 12)),
          const SizedBox(height: Sx.s8),
          Row(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      Text('FREE', style: SxType.hero(44, c.ink)),
                      const SizedBox(width: Sx.s12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(20)),
                        child: Text('ACTIVE', style: SxType.label(c.ink, size: 11)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: Sx.s12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('₹0', style: SxType.number(24, c.ink, weight: FontWeight.w800)),
                  Text('Forever', style: SxType.caption(c.inkMuted, size: 12)),
                ],
              ),
            ],
          ),
          if (expired) ...[
            const SizedBox(height: Sx.s4),
            Text('Your Pro plan has ended. Everything you played is still here.', style: SxType.caption(c.caution)),
          ],
          const SizedBox(height: Sx.s12),
          Wrap(
            spacing: Sx.s12,
            runSpacing: Sx.s8,
            children: [
              for (final label in const ['Live Match Scoring', 'Match & Tournament History', 'Court Booking', 'Achievements'])
                _Included(label: label),
            ],
          ),
          const SizedBox(height: Sx.s16),
          Container(
            padding: const EdgeInsets.all(Sx.s12),
            decoration: BoxDecoration(
              color: c.voltFill.withValues(alpha: c.isDark ? 0.08 : 0.14),
              borderRadius: BorderRadius.circular(Sx.radiusSm),
              border: Border.all(color: c.voltFill.withValues(alpha: 0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const ProBadge(size: 10),
                  const SizedBox(width: Sx.s8),
                  Text('Pro unlocks', style: SxType.heading(c.ink, size: 14)),
                ]),
                const SizedBox(height: Sx.s8),
                for (final f in ProFeature.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(children: [
                      Icon(Icons.check_rounded, size: 16, color: c.volt),
                      const SizedBox(width: Sx.s8),
                      Expanded(child: Text(f.short, style: SxType.caption(c.ink, size: 13))),
                    ]),
                  ),
              ],
            ),
          ),
          if (showManage) ...[
            const SizedBox(height: Sx.s16),
            SxButton(
              key: const Key('upgradeToPro'),
              label: expired ? 'Renew Pro' : 'Upgrade to Pro',
              icon: Icons.bolt_rounded,
              onPressed: () => context.push('/player/pro'),
            ),
          ],
        ],
      ),
    );
  }
}

class _Included extends StatelessWidget {
  const _Included({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_rounded, size: 16, color: c.volt),
        const SizedBox(width: 4),
        Flexible(child: Text(label, style: SxType.caption(c.ink, size: 13))),
      ],
    );
  }
}
