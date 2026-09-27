import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/routing/router.dart';
import '../../../design/design.dart';
import '../../../sports/core/score_state.dart';
import '../scoring_controller.dart';
import '../ui/scoring_labels.dart';
import 'scoring_handover.dart';

/// The scoring request waiting for this player's answer, if any.
final incomingHandoverProvider = NotifierProvider<IncomingHandoverController, IncomingHandover?>(IncomingHandoverController.new);

class IncomingHandoverController extends Notifier<IncomingHandover?> {
  @override
  IncomingHandover? build() {
    final sub = ref.watch(scoringHandoverServiceProvider).incoming.listen((request) {
      HapticFeedback.heavyImpact();
      state = request;
    });
    ref.onDispose(sub.cancel);
    return null;
  }

  /// Accepts: the match moves to this phone and scoring carries on here.
  Future<void> accept() async {
    final incoming = state;
    if (incoming == null) return;
    state = null;
    // In the debug preview the sender is this same phone, whose answer
    // handler records the new scorer; a real request is adopted here.
    if (!incoming.simulated) await ref.read(scoringControllerProvider.notifier).adoptHandedOver(incoming.match);
    await ref.read(scoringHandoverServiceProvider).respond(incoming, HandoverAnswer.accepted);
    ref.read(routerProvider).go('/player/match');
  }

  Future<void> decline() async {
    final incoming = state;
    if (incoming == null) return;
    state = null;
    await ref.read(scoringHandoverServiceProvider).respond(incoming, HandoverAnswer.declined);
  }
}

/// Puts the accept prompt over whatever screen is open when a request arrives.
class IncomingHandoverLayer extends ConsumerWidget {
  const IncomingHandoverLayer({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final incoming = ref.watch(incomingHandoverProvider);
    return Stack(
      children: [
        child,
        if (incoming != null) Positioned.fill(child: _HandoverPrompt(incoming: incoming)),
      ],
    );
  }
}

class _HandoverPrompt extends ConsumerWidget {
  const _HandoverPrompt({required this.incoming});

  final IncomingHandover incoming;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final m = incoming.match;
    final r = incoming.request;
    final score = m.score;
    final controller = ref.read(incomingHandoverProvider.notifier);
    final where = m.details.courtLabel;
    return Material(
      type: MaterialType.transparency,
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.7),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Sx.s16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: SxReveal(
                  child: Container(
                    key: const Key('handoverPrompt'),
                    padding: const EdgeInsets.all(Sx.s20),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(Sx.radiusLg),
                      border: Border.all(color: c.voltFill.withValues(alpha: 0.5)),
                      boxShadow: c.glowOf(c.voltFill, strength: 0.6),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (incoming.simulated)
                          Padding(
                            padding: const EdgeInsets.only(bottom: Sx.s12),
                            child: Text(
                              'PREVIEW · In the live app this appears on ${r.toName}\'s phone',
                              textAlign: TextAlign.center,
                              style: SxType.label(c.caution, size: 10.5),
                            ),
                          ),
                        const Center(child: SxBall(size: 44, float: false)),
                        const SizedBox(height: Sx.s12),
                        Text('Scoring request', textAlign: TextAlign.center, style: SxType.title(c.ink, size: 28)),
                        const SizedBox(height: 4),
                        Text(
                          '${r.fromName} asked ${incoming.simulated ? r.toName : 'you'} to take over scoring.',
                          textAlign: TextAlign.center,
                          style: SxType.body(c.inkMuted),
                        ),
                        const SizedBox(height: Sx.s16),
                        Container(
                          padding: const EdgeInsets.all(Sx.s12),
                          decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(Sx.radiusSm)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text([matchTypeLabel(m), ?where].join(' · ').toUpperCase(), style: SxType.label(c.inkMuted, size: 11)),
                              const SizedBox(height: 6),
                              Text('${m.teamLabel(Side.a)}  vs  ${m.teamLabel(Side.b)}',
                                  maxLines: 2, overflow: TextOverflow.ellipsis, style: SxType.heading(c.ink, size: 15)),
                              const SizedBox(height: 6),
                              Text(
                                m.events.isEmpty
                                    ? 'Not started yet'
                                    : 'Game ${score.gameNumber} · ${score.currentGame.a}–${score.currentGame.b}',
                                style: SxType.number(22, c.volt, weight: FontWeight.w800),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: Sx.s12),
                        Text('Scoring moves to this phone and carries on from exactly this point.',
                            textAlign: TextAlign.center, style: SxType.caption(c.inkMuted)),
                        const SizedBox(height: Sx.s16),
                        SxButton(
                          key: const Key('acceptHandover'),
                          label: 'Accept & start scoring',
                          icon: Icons.check_rounded,
                          onPressed: controller.accept,
                        ),
                        const SizedBox(height: Sx.s8),
                        SxButton.secondary(key: const Key('declineHandover'), label: 'Decline', onPressed: controller.decline),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// On the sender's phone while the request is open: scoring is paused.
class HandoverWaitingOverlay extends ConsumerWidget {
  const HandoverWaitingOverlay({super.key, required this.request, required this.simulated});

  final ScoringHandover request;
  final bool simulated;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    return ColoredBox(
      color: c.canvas.withValues(alpha: 0.94),
      child: SxWidth(
        child: Padding(
          padding: const EdgeInsets.all(Sx.gutter),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SxPop(child: Icon(Icons.send_to_mobile_rounded, size: 64, color: c.cyan)),
              const SizedBox(height: Sx.s16),
              Text('WAITING FOR ${request.toName.split(' ').first.toUpperCase()}',
                  key: const Key('handoverWaiting'), textAlign: TextAlign.center, style: SxType.verdict(34, c.ink)),
              const SizedBox(height: Sx.s8),
              Text(
                'Scoring is paused on this phone. ${request.toName} has been asked to accept on their phone, and scoring '
                'carries on there from this point.',
                textAlign: TextAlign.center,
                style: SxType.body(c.inkMuted),
              ),
              if (simulated) ...[
                const SizedBox(height: Sx.s12),
                Text('Preview build: the request pops up on this phone in a moment.',
                    textAlign: TextAlign.center, style: SxType.caption(c.caution)),
              ],
              const SizedBox(height: Sx.s32),
              SxButton.secondary(
                key: const Key('cancelHandover'),
                label: 'Cancel request',
                icon: Icons.close_rounded,
                onPressed: () => ref.read(scoringControllerProvider.notifier).cancelHandover(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
