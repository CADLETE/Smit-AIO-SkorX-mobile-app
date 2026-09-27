import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../design/design.dart';
import '../../../../sports/core/score_state.dart';
import '../../live/live_court.dart';
import '../../local_match.dart';

/// The break between games: who won it, and one question: did the players
/// change ends? Kept to what the scorer needs to carry on; the numbers are
/// on the result screen.
class GameBreakView extends StatelessWidget {
  const GameBreakView({super.key, required this.match, required this.steps, required this.onAnswer, required this.onUndo});

  final LocalMatch match;
  final List<LiveStep> steps;
  final ValueChanged<bool> onAnswer;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final score = steps.last.score;
    final finished = score.gameNumber - 1;
    final game = score.games[finished - 1];
    final winner = game.a > game.b ? Side.a : Side.b;

    void answer(bool switched) {
      HapticFeedback.mediumImpact();
      onAnswer(switched);
    }

    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.72),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Sx.s16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SxReveal(
              child: Container(
                key: const Key('gameBreak'),
                padding: const EdgeInsets.fromLTRB(Sx.s20, Sx.s20, Sx.s20, Sx.s12),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(Sx.radiusLg),
                  border: Border.all(color: c.voltFill.withValues(alpha: 0.45)),
                  boxShadow: c.glowOf(c.voltFill, strength: 0.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. What just happened.
                    Text('GAME $finished', textAlign: TextAlign.center, style: SxType.label(c.inkMuted, size: 12)),
                    const SizedBox(height: 4),
                    Text(
                      '${game.of(winner)}–${game.of(winner.opponent)}',
                      key: const Key('breakGameScore'),
                      textAlign: TextAlign.center,
                      style: SxType.hero(64, c.volt),
                    ),
                    Text(
                      '${match.teamLabel(winner)} win',
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: SxType.heading(c.ink, size: 16),
                    ),
                    const SizedBox(height: Sx.s20),
                    Divider(color: c.line, height: 1),
                    const SizedBox(height: Sx.s20),

                    // 2. The one question.
                    Text('Did the players change ends?', textAlign: TextAlign.center, style: SxType.title(c.ink, size: 26)),
                    const SizedBox(height: Sx.s16),
                    SxButton(
                      key: const Key('endsSwitched'),
                      label: 'Yes, changed ends',
                      icon: Icons.swap_vert_rounded,
                      onPressed: () => answer(true),
                    ),
                    const SizedBox(height: Sx.s8),
                    SxButton.secondary(
                      key: const Key('endsSame'),
                      label: 'No, same ends',
                      onPressed: () => answer(false),
                    ),
                    const SizedBox(height: Sx.s8),
                    Center(
                      child: SxButton.quiet(
                        key: const Key('breakUndo'),
                        label: 'Undo last point',
                        icon: Icons.undo_rounded,
                        onPressed: onUndo,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
