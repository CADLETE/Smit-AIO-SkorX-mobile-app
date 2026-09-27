import 'package:flutter_test/flutter_test.dart';
import 'package:skorx/sports/core/match_rules.dart';
import 'package:skorx/sports/sport_registry.dart';

void main() {
  group('MatchRules.parse', () {
    test('reads the API shape, including optional fields', () {
      final rules = MatchRules.parse({
        'pointsToWin': 21,
        'winByTwo': true,
        'bestOf': 3,
        'pointCap': 30,
        'scoring': 'rally',
      }).rules;
      expect(rules, const MatchRules(pointsToWin: 21, winByTwo: true, bestOf: 3, pointCap: 30));
    });

    test('round-trips through toJson', () {
      const rules = MatchRules(pointsToWin: 11, winByTwo: true, bestOf: 3, scoring: ScoringSystem.sideOut);
      expect(MatchRules.parse(rules.toJson()).rules, rules);
    });

    test('rejects rules no match could finish under, with the server messages', () {
      expect(MatchRules.parse({'pointsToWin': 11, 'winByTwo': true, 'bestOf': 2}).reason,
          'Best of must be 1, 3, 5 or 7 games.');
      expect(MatchRules.parse({'pointsToWin': 0, 'winByTwo': true, 'bestOf': 3}).reason,
          'Points to win must be a whole number from 1 to 99.');
      expect(MatchRules.parse({'pointsToWin': 21, 'winByTwo': true, 'bestOf': 3, 'pointCap': 20}).reason,
          'The point cap must be higher than points to win.');
      expect(MatchRules.parse({'pointsToWin': 11, 'winByTwo': 'yes', 'bestOf': 3}).reason,
          'Win by two must be true or false.');
      expect(MatchRules.parse({'pointsToWin': 11, 'winByTwo': true, 'bestOf': 3, 'scoring': 'tennis'}).reason,
          'Scoring must be rally or side out.');
      expect(MatchRules.parse(null).reason, 'Match rules are missing.');
    });
  });

  test('describes rules in plain language', () {
    expect(pickleball.defaultRules.describe(), 'Best of 3 · first to 11, win by 2');
    expect(badminton.defaultRules.describe(), 'Best of 3 · first to 21, win by 2, max 30');
  });

  group('SportRegistry', () {
    test('knows the sports this build can score', () {
      expect(SportRegistry.standard.of('pickleball'), same(pickleball));
      expect(SportRegistry.standard.of('badminton'), same(badminton));
      expect(SportRegistry.standard.of('table_tennis'), same(tableTennis));
      expect(SportRegistry.standard.of('padel'), isNull);
    });

    test('offers only the scoring systems a sport uses', () {
      const sideOut = MatchRules(pointsToWin: 21, winByTwo: true, bestOf: 3, scoring: ScoringSystem.sideOut);
      expect(badminton.rulesProblem(sideOut), 'Badminton does not use side-out scoring.');
      expect(pickleball.rulesProblem(sideOut), isNull);
    });

    test('offers one game or best of 3, never longer', () {
      for (final sport in SportRegistry.standard.all) {
        expect(sport.bestOfOptions, [1, 3]);
      }
      const bestOf5 = MatchRules(pointsToWin: 11, winByTwo: true, bestOf: 5, scoring: ScoringSystem.sideOut);
      expect(pickleball.rulesProblem(bestOf5), 'Matches are one game or best of 3.');
    });

    test('default rules match what the API seeds', () {
      // Keep in step with backend/prisma/reference-data.ts.
      expect(pickleball.defaultRules.toJson(),
          {'pointsToWin': 11, 'winByTwo': true, 'bestOf': 3, 'scoring': 'side_out'});
      expect(badminton.defaultRules.toJson(),
          {'pointsToWin': 21, 'winByTwo': true, 'bestOf': 3, 'pointCap': 30, 'scoring': 'rally'});
      expect(tableTennis.defaultRules.toJson(), {'pointsToWin': 11, 'winByTwo': true, 'bestOf': 3, 'scoring': 'rally'});
    });

    test('every sport offers singles and doubles with the right team sizes', () {
      for (final sport in SportRegistry.standard.all) {
        expect(sport.category('singles')?.playersPerSide, 1, reason: sport.id);
        expect(sport.category('mixed_doubles')?.playersPerSide, 2, reason: sport.id);
      }
    });
  });
}
