import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design/design.dart';
import '../data/plans.dart';
import '../data/subscription.dart';
import '../subscription_controller.dart';
import 'pro_widgets.dart';

/// SkorX Pro: the two ways to pay, what Free and Pro each include, and the
/// way to checkout. Reached from Profile, the plan card and every locked
/// Pro feature ([feature] is the one that brought the player here).
class ProPlansPage extends ConsumerStatefulWidget {
  const ProPlansPage({super.key, this.feature});

  final ProFeature? feature;

  @override
  ConsumerState<ProPlansPage> createState() => _ProPlansPageState();
}

class _ProPlansPageState extends ConsumerState<ProPlansPage> {
  ProPlan? _picked;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final s = ref.watch(subscriptionProvider).value ?? SubscriptionSummary.free;
    // Pro players see the other cycle first: that is the change they can make.
    final plan = _picked ?? (s.isPro && s.plan != null ? s.plan!.other : ProPlan.annual);
    final queued = s.upcoming.isNotEmpty;
    final String cta;
    if (!s.isPro) {
      cta = 'Continue · ₹${plan.price} + GST / ${plan.per}';
    } else if (plan == s.plan) {
      cta = 'Add another ${plan.per} · ₹${plan.price} + GST';
    } else {
      cta = 'Switch to ${plan.label} · ₹${plan.price} + GST';
    }

    return Scaffold(
      body: SafeArea(
        child: SxWidth(
          child: Column(
            children: [
              SxBackBar(onBack: () => context.canPop() ? context.pop() : context.go('/player/profile')),
              Expanded(
                child: ListView(
                  key: const Key('proPlans'),
                  padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s8, Sx.gutter, Sx.s24),
                  children: [
                    SxReveal(child: _Header(current: s)),
                    if (widget.feature != null && !s.isPro) ...[
                      const SizedBox(height: Sx.s16),
                      Row(
                        children: [
                          Icon(widget.feature!.icon, size: 18, color: c.inkMuted),
                          const SizedBox(width: Sx.s8),
                          Expanded(
                            child: Text('${widget.feature!.title} is part of SkorX Pro.', style: SxType.caption(c.inkMuted)),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: Sx.section),
                    const SxSection('Choose how you pay'),
                    for (final p in [ProPlan.monthly, ProPlan.annual]) ...[
                      _PlanOption(
                        plan: p,
                        selected: p == plan,
                        current: s.isPro && s.plan == p,
                        onTap: () => setState(() => _picked = p),
                      ),
                      const SizedBox(height: Sx.s12),
                    ],
                    if (s.isPro && !queued && s.proUntil != null)
                      Text(
                        'Your new ${plan.label.toLowerCase()} period starts when your current plan ends on ${billingDate(s.proUntil!)}. No paid day is lost.',
                        style: SxType.caption(c.inkMuted),
                      ),
                    const SizedBox(height: Sx.section),
                    const SxSection('Free and Pro'),
                    const _Comparison(),
                    const SizedBox(height: Sx.s16),
                    Text(
                      'Prices exclude GST, which is added at checkout. Turn off auto-renew any time; Pro stays until the end of the period you paid for.',
                      style: SxType.caption(c.inkMuted, size: 12.5),
                    ),
                    if (s.testMode) ...[
                      const SizedBox(height: Sx.s8),
                      Text('Test Mode: payments are simulated, no real money moves.', style: SxType.caption(c.caution, size: 12.5)),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s8, Sx.gutter, Sx.s16),
                child: queued
                    ? Text(
                        'Your next Pro period is already paid for. You can buy another once it starts.',
                        textAlign: TextAlign.center,
                        style: SxType.caption(c.inkMuted),
                      )
                    : SxButton(
                        key: const Key('continueToCheckout'),
                        label: cta,
                        icon: Icons.arrow_forward_rounded,
                        onPressed: () => context.push('/player/pro/checkout?plan=${plan.name}'),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.current});

  final SubscriptionSummary current;

  @override
  Widget build(BuildContext context) {
    return SxHeroCard(
      watermark: true,
      padding: const EdgeInsets.fromLTRB(Sx.s24, Sx.s24, Sx.s24, Sx.s32),
      child: SxOnHero(
        child: Builder(builder: (context) {
          final c = context.sx;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ProBadge(size: 12),
              const SizedBox(height: Sx.s12),
              Text('SKORX PRO', style: SxType.hero(56, c.ink)),
              const SizedBox(height: Sx.s8),
              Text('Unlock more ways to understand and improve your game.', style: SxType.body(c.inkMuted, size: 16)),
              if (current.isPro && current.plan != null) ...[
                const SizedBox(height: Sx.s16),
                SxHeroTag(text: 'YOU\'RE ON PRO · ${current.plan!.label.toUpperCase()}', icon: Icons.check_rounded, highlight: true),
              ],
            ],
          );
        }),
      ),
    );
  }
}

class _PlanOption extends StatelessWidget {
  const _PlanOption({required this.plan, required this.selected, required this.current, required this.onTap});

  final ProPlan plan;
  final bool selected;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final annual = plan == ProPlan.annual;
    return Semantics(
      button: true,
      selected: selected,
      label: '${plan.label}, ₹${plan.price} plus GST per ${plan.per}${annual ? ', save ₹$annualSaving' : ''}',
      excludeSemantics: true,
      child: Tappable(
        key: Key('plan-${plan.name}'),
        onTap: onTap,
        radius: Sx.radiusLg,
        child: AnimatedContainer(
          duration: Sx.fast,
          padding: const EdgeInsets.all(Sx.s16),
          decoration: BoxDecoration(
            gradient: c.card,
            borderRadius: BorderRadius.circular(Sx.radiusLg),
            border: Border.all(color: selected ? c.voltFill : c.cardEdge, width: selected ? 2 : 1),
            boxShadow: selected ? c.glowOf(c.voltFill, strength: 0.5) : c.cardShadow,
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: Sx.fast,
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? c.voltFill : Colors.transparent,
                  border: Border.all(color: selected ? c.voltFill : c.inkFaint, width: 2),
                ),
                child: selected ? Icon(Icons.check_rounded, size: 16, color: c.onVolt) : null,
              ),
              const SizedBox(width: Sx.s16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(plan.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.heading(c.ink, size: 17)),
                    if (current) Text('Your plan', style: SxType.caption(c.volt, size: 12).copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      annual ? 'Billed once a year · about ₹${(plan.price / 12).round()} a month' : 'Billed every month',
                      style: SxType.caption(c.inkMuted, size: 12.5),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (annual)
                    Container(
                      key: const Key('annualSaving'),
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(gradient: c.brand, borderRadius: BorderRadius.circular(6)),
                      child: Text('SAVE ₹$annualSaving', style: SxType.label(c.onVolt, size: 10.5, weight: FontWeight.w900)),
                    ),
                  Text('₹${plan.price} + GST', style: SxType.number(20, c.ink, weight: FontWeight.w800)),
                  Text('per ${plan.per}', style: SxType.caption(c.inkMuted, size: 12)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Free vs Pro, one row per feature.
class _Comparison extends StatelessWidget {
  const _Comparison();

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    Widget mark(bool on, {bool pro = false}) => SizedBox(
          width: 52,
          child: Center(
            child: on
                ? Icon(Icons.check_rounded, size: 20, color: pro ? c.volt : c.ink)
                : Text('—', style: SxType.body(c.inkFaint)),
          ),
        );
    return Container(
      key: const Key('comparison'),
      decoration: BoxDecoration(
        gradient: c.card,
        borderRadius: BorderRadius.circular(Sx.radiusLg),
        border: Border.all(color: c.cardEdge),
      ),
      padding: const EdgeInsets.symmetric(horizontal: Sx.s16, vertical: Sx.s8),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Sx.s8),
            child: Row(
              children: [
                Expanded(child: Text('FEATURE', style: SxType.label(c.inkMuted, size: 11))),
                SizedBox(width: 52, child: Center(child: Text('FREE', style: SxType.label(c.inkMuted, size: 11)))),
                const SizedBox(width: 52, child: Center(child: ProBadge(size: 10))),
              ],
            ),
          ),
          for (final (label, free) in comparisonRows) ...[
            Divider(height: 1, color: c.line.withValues(alpha: 0.6)),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Sx.s12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(label,
                        style: SxType.body(c.ink, size: 14).copyWith(fontWeight: free ? FontWeight.w500 : FontWeight.w700)),
                  ),
                  mark(free),
                  mark(true, pro: !free),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
