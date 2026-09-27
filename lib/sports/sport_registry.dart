import 'badminton/badminton_scoring_engine.dart';
import 'core/match_rules.dart';
import 'core/sport_definition.dart';
import 'pickleball/pickleball_scoring_engine.dart';
import 'table_tennis/table_tennis_scoring_engine.dart';

/// Sports this build can score. Adding a sport means adding its engine and
/// one entry here; nothing else in the app changes. Whether a sport is
/// offered to users is still decided by the API (`playable`).
class SportRegistry {
  const SportRegistry(this._sports);

  static const standard = SportRegistry([pickleball, badminton, tableTennis]);

  final List<SportDefinition> _sports;

  List<SportDefinition> get all => List.unmodifiable(_sports);

  /// The definition for [id], or null when this build cannot score it yet
  /// (the UI shows it as "coming soon").
  SportDefinition? of(String id) {
    for (final sport in _sports) {
      if (sport.id == id) return sport;
    }
    return null;
  }
}

const pickleball = SportDefinition(
  id: 'pickleball',
  name: 'Pickleball',
  engine: PickleballScoringEngine(),
  defaultRules: MatchRules(pointsToWin: 11, winByTwo: true, bestOf: 3, scoring: ScoringSystem.sideOut),
  categories: racketCategories,
  scoringSystems: [ScoringSystem.sideOut, ScoringSystem.rally],
  pointTargets: [11, 15, 21],
  bestOfOptions: playableBestOf,
);

const badminton = SportDefinition(
  id: 'badminton',
  name: 'Badminton',
  engine: BadmintonScoringEngine(),
  defaultRules: MatchRules(pointsToWin: 21, winByTwo: true, bestOf: 3, pointCap: 30),
  categories: racketCategories,
  scoringSystems: [ScoringSystem.rally],
  pointTargets: [11, 15, 21],
  bestOfOptions: playableBestOf,
);

const tableTennis = SportDefinition(
  id: 'table_tennis',
  name: 'Table Tennis',
  engine: TableTennisScoringEngine(),
  defaultRules: MatchRules(pointsToWin: 11, winByTwo: true, bestOf: 3),
  categories: racketCategories,
  scoringSystems: [ScoringSystem.rally],
  pointTargets: [11, 21],
  bestOfOptions: playableBestOf,
);
