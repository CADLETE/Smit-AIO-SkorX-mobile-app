import '../../../sports/core/match_rules.dart';
import '../../../sports/core/score_state.dart';
import '../local_match.dart';

/// What a tap on [side]'s half does right now, in the old app's words.
String rallyActionLabel(LocalMatch match, ScoreState score, Side side) {
  if (match.rules.scoring == ScoringSystem.rally || side == score.serve.side) return 'POINT';
  if (score.serve.serverNumber == 1) return '2ND SERVER';
  return 'SIDE OUT';
}

/// "Men's Doubles", from the match's category.
String matchTypeLabel(LocalMatch match) => match.sport.category(match.categoryId)?.label ?? match.sport.name;

/// The score call split into its numbers, each with what it means:
/// server's score, receiver's score and, in side-out doubles, server 1 or 2.
List<(String, String)> scoreCallParts(LocalMatch match, ScoreState score) {
  final numbers = match.sport.engine.scoreCall(match.setup, score).split('-');
  const labels = ['SERVER', 'RECEIVER', 'SERVER #'];
  return [for (final (i, n) in numbers.indexed) (n, labels[i.clamp(0, labels.length - 1)])];
}

/// "1:05:12" or "42:07".
String clockText(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}
