import 'match_rules.dart';
import 'scoring_engine.dart';

/// A casual match type, e.g. Mixed Doubles. Ids match the API's
/// `Sport.matchCategories`.
class MatchCategory {
  const MatchCategory({required this.id, required this.label, required this.playersPerSide});

  final String id;
  final String label;
  final int playersPerSide;
}

/// Everything sport-specific the app needs. Screens ask the definition,
/// never `if (sport == pickleball)`.
///
/// The API's `GET /sports` is the source of truth for which sports are
/// playable and their default rules; these definitions add what only the app
/// needs (engine, wording, the options offered under "Customize") and are the
/// offline fallback.
class SportDefinition {
  const SportDefinition({
    required this.id,
    required this.name,
    required this.engine,
    required this.defaultRules,
    required this.categories,
    required this.scoringSystems,
    required this.pointTargets,
    required this.bestOfOptions,
    this.gameLabel = 'Game',
  });

  final String id;
  final String name;
  final ScoringEngine engine;
  final MatchRules defaultRules;
  final List<MatchCategory> categories;

  /// Scoring systems a player can choose; one entry means no choice is shown.
  final List<ScoringSystem> scoringSystems;

  /// Common "play to" targets offered as quick picks.
  final List<int> pointTargets;
  final List<int> bestOfOptions;

  /// What one scoring unit is called on screen ("Game", later "Set" for padel).
  final String gameLabel;

  MatchCategory? category(String id) {
    for (final category in categories) {
      if (category.id == id) return category;
    }
    return null;
  }

  /// Why [rules] cannot be used for this sport, or null when they can.
  String? rulesProblem(MatchRules rules) {
    if (!scoringSystems.contains(rules.scoring)) {
      return '$name does not use ${rules.scoring == ScoringSystem.sideOut ? 'side-out' : 'rally'} scoring.';
    }
    if (!bestOfOptions.contains(rules.bestOf)) return 'Matches are one game or best of 3.';
    return null;
  }
}

/// The match types every racket sport offers today.
const racketCategories = [
  MatchCategory(id: 'singles', label: 'Singles', playersPerSide: 1),
  MatchCategory(id: 'doubles', label: 'Doubles', playersPerSide: 2),
  MatchCategory(id: 'mixed_doubles', label: 'Mixed Doubles', playersPerSide: 2),
  MatchCategory(id: 'mens_singles', label: "Men's Singles", playersPerSide: 1),
  MatchCategory(id: 'womens_singles', label: "Women's Singles", playersPerSide: 1),
  MatchCategory(id: 'mens_doubles', label: "Men's Doubles", playersPerSide: 2),
  MatchCategory(id: 'womens_doubles', label: "Women's Doubles", playersPerSide: 2),
  MatchCategory(id: 'kids_singles', label: 'Kids Singles', playersPerSide: 1),
  MatchCategory(id: 'kids_doubles', label: 'Kids Doubles', playersPerSide: 2),
  MatchCategory(id: 'kids_mixed_doubles', label: 'Kids Mixed Doubles', playersPerSide: 2),
];
