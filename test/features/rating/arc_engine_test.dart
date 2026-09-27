import 'package:flutter_test/flutter_test.dart';
import 'package:skorx/features/matches/data/match_repository.dart';
import 'package:skorx/features/player/data/player_repository.dart' show PlayCategory;
import 'package:skorx/features/rating/arc_career.dart';
import 'package:skorx/features/rating/arc_engine.dart';
import 'package:skorx/shared/format.dart';

/// The scenarios of the rating spec (docs/RATING-SYSTEM.md): the app and the
/// published numbers must agree.
void main() {
  const arjun = ArcPlayerState(spi: 72, sxpUnits: 0, matches: 60);
  const bhavin = ArcPlayerState(spi: 32, sxpUnits: 0, matches: 25);
  const chirag = ArcPlayerState(spi: 50, sxpUnits: 0, matches: 40);
  const farhan = ArcPlayerState(spi: 66, sxpUnits: 0, matches: 50);

  ArcImpact singles(ArcPlayerState me, ArcPlayerState them, int pf, int pa,
          {ArcMatchType type = ArcMatchType.league, ArcStage stage = ArcStage.pool, ArcTrust trust = ArcTrust.organiser}) =>
      arcRate(
        me,
        ArcMatchInput(
          mySide: [me.spi],
          theirSide: [them.spi],
          pointsFor: pf,
          pointsAgainst: pa,
          won: pf > pa,
          type: type,
          stage: stage,
          trust: trust,
          otherPlayersMatches: [them.matches],
        ),
      );

  /// SXP one player earns from [games] (their side's score first), with
  /// [players] on each side.
  double earned(List<(int, int)> games, {required bool tournament, int players = 1}) {
    final pf = games.fold(0, (s, g) => s + g.$1), pa = games.fold(0, (s, g) => s + g.$2);
    return arcRate(
      ArcPlayerState.newPlayer,
      ArcMatchInput(
        mySide: List.filled(players, 40.0),
        theirSide: List.filled(players, 40.0),
        pointsFor: pf,
        pointsAgainst: pa,
        won: pf > pa,
        type: tournament ? ArcMatchType.tournament : ArcMatchType.casual,
        trust: tournament ? ArcTrust.tournament : ArcTrust.players,
      ),
    ).sxpGain;
  }

  /// Both sides of a match: (A casual, B casual, A tournament, B tournament).
  (double, double, double, double) both(List<(int, int)> games, {int players = 1}) {
    final flipped = [for (final g in games) (g.$2, g.$1)];
    return (
      earned(games, tournament: false, players: players),
      earned(flipped, tournament: false, players: players),
      earned(games, tournament: true, players: players),
      earned(flipped, tournament: true, players: players),
    );
  }

  group('SkorX Points: actual points ÷ 20 casual, ÷ 10 tournament', () {
    test('singles: the player\'s own points, converted directly', () {
      final cases = <List<(int, int)>, (double, double, double, double)>{
        [(11, 0)]: (0.55, 0, 1.10, 0),
        [(11, 1)]: (0.55, 0.05, 1.10, 0.10),
        [(11, 5)]: (0.55, 0.25, 1.10, 0.50),
        [(11, 8)]: (0.55, 0.40, 1.10, 0.80),
        [(11, 9)]: (0.55, 0.45, 1.10, 0.90),
        [(12, 10)]: (0.60, 0.50, 1.20, 1.00),
        [(15, 13)]: (0.75, 0.65, 1.50, 1.30),
        [(21, 17)]: (1.05, 0.85, 2.10, 1.70),
        [(11, 7), (9, 11), (11, 6)]: (1.55, 1.20, 3.10, 2.40),
        // A retires in game 2 at 3–6: only points played count, and B wins.
        [(11, 4), (3, 6)]: (0.70, 0.50, 1.40, 1.00),
      };
      for (final MapEntry(key: games, value: want) in cases.entries) {
        final got = both(games);
        expect(got.$1, closeTo(want.$1, 1e-9), reason: '$games A casual');
        expect(got.$2, closeTo(want.$2, 1e-9), reason: '$games B casual');
        expect(got.$3, closeTo(want.$3, 1e-9), reason: '$games A tournament');
        expect(got.$4, closeTo(want.$4, 1e-9), reason: '$games B tournament');
      }
    });

    test('doubles: team points converted, then shared equally by the two partners', () {
      final cases = <List<(int, int)>, (double, double, double, double)>{
        [(11, 0)]: (0.275, 0, 0.55, 0),
        [(11, 2)]: (0.275, 0.05, 0.55, 0.10),
        [(11, 6)]: (0.275, 0.15, 0.55, 0.30),
        [(11, 8)]: (0.275, 0.20, 0.55, 0.40),
        [(11, 9)]: (0.275, 0.225, 0.55, 0.45),
        [(13, 11)]: (0.325, 0.275, 0.65, 0.55),
        [(15, 13)]: (0.375, 0.325, 0.75, 0.65),
        [(21, 19)]: (0.525, 0.475, 1.05, 0.95),
        [(11, 8), (8, 11), (11, 9)]: (0.75, 0.70, 1.50, 1.40),
        [(11, 6), (11, 9), (9, 11), (11, 7)]: (1.05, 0.825, 2.10, 1.65),
      };
      for (final MapEntry(key: games, value: want) in cases.entries) {
        final got = both(games, players: 2);
        expect(got.$1, closeTo(want.$1, 1e-9), reason: '$games A casual');
        expect(got.$2, closeTo(want.$2, 1e-9), reason: '$games B casual');
        expect(got.$3, closeTo(want.$3, 1e-9), reason: '$games A tournament');
        expect(got.$4, closeTo(want.$4, 1e-9), reason: '$games B tournament');
      }
    });

    test('mixed doubles uses exactly the doubles maths', () {
      final cases = <List<(int, int)>, (double, double, double, double)>{
        [(11, 9)]: (0.275, 0.225, 0.55, 0.45),
        [(11, 4)]: (0.275, 0.10, 0.55, 0.20),
        [(12, 10)]: (0.30, 0.25, 0.60, 0.50),
        [(11, 5), (11, 7)]: (0.55, 0.30, 1.10, 0.60),
        [(9, 11), (11, 9), (12, 10)]: (0.80, 0.75, 1.60, 1.50),
      };
      for (final MapEntry(key: games, value: want) in cases.entries) {
        final got = both(games, players: 2);
        expect([got.$1, got.$2, got.$3, got.$4], [
          closeTo(want.$1, 1e-9),
          closeTo(want.$2, 1e-9),
          closeTo(want.$3, 1e-9),
          closeTo(want.$4, 1e-9),
        ], reason: '$games');
      }
    });

    test('a tournament is worth exactly twice the same casual match', () {
      for (final g in [(11, 0), (11, 9), (15, 13), (21, 19)]) {
        for (final players in [1, 2]) {
          expect(earned([g], tournament: true, players: players), 2 * earned([g], tournament: false, players: players));
        }
      }
    });

    test('league and championship convert like a tournament, club like casual', () {
      expect(ArcMatchType.league.divisor, 10);
      expect(ArcMatchType.championship.divisor, 10);
      expect(ArcMatchType.club.divisor, 20);
      expect(ArcMatchType.casual.sxpLabel, 'Casual');
      expect(ArcMatchType.league.sxpLabel, 'Tournament');
    });

    test('nothing hidden: opponent, winning, stage and skill change nothing', () {
      final base = singles(bhavin, arjun, 11, 9).sxpUnits;
      expect(singles(arjun, bhavin, 11, 9).sxpUnits, base, reason: 'opponent strength');
      expect(singles(bhavin, arjun, 11, 13).sxpUnits, base, reason: 'winning or losing');
      expect(singles(bhavin, arjun, 11, 9, stage: ArcStage.finalRound).sxpUnits, base, reason: 'final round');
      expect(singles(chirag, farhan, 11, 7, type: ArcMatchType.championship, stage: ArcStage.finalRound).sxpGain, 1.10);
    });

    test('only verified matches add SkorX Points; all or nothing', () {
      for (final t in [ArcTrust.tournament, ArcTrust.organiser, ArcTrust.players]) {
        expect(singles(chirag, chirag, 11, 6, type: ArcMatchType.casual, trust: t).sxpGain, 0.55, reason: t.label);
      }
      final self = singles(chirag, chirag, 11, 6, type: ArcMatchType.casual, trust: ArcTrust.selfReported);
      expect(self.sxpGain, 0);
      expect(self.credited, isFalse);
      expect(singles(chirag, chirag, 11, 6, trust: ArcTrust.unverified).sxpGain, 0);
    });

    test('the Career Score adds every contribution: 0.55 + 0.45 + 1.10 + 0.80 = 2.90', () {
      var units = 0;
      for (final (pts, tournament) in [(11, false), (9, false), (11, true), (8, true)]) {
        final i = arcRate(
          ArcPlayerState(spi: 40, sxpUnits: units, matches: 0),
          ArcMatchInput(
            mySide: const [40],
            theirSide: const [40],
            pointsFor: pts,
            pointsAgainst: 11,
            won: pts == 11,
            type: tournament ? ArcMatchType.tournament : ArcMatchType.casual,
            trust: tournament ? ArcTrust.tournament : ArcTrust.players,
          ),
        );
        expect(i.sxpBeforeUnits, units);
        units = i.sxpAfterUnits;
      }
      expect(Sxp.of(units), 2.90);
    });

    test('precision: exact to the end, rounded to 2 decimals only for display', () {
      expect(Sxp.units(points: 11, divisor: 20, players: 2), 11, reason: '0.275 is 11 fortieths');
      expect(Sxp.of(11), 0.275);
      expect(Sxp.shown(11), 0.28, reason: 'half up');
      expect(Sxp.shown(9), 0.23);
      expect(Sxp.shown(-11), -0.28);
      // 40 casual doubles wins at 11: 40 × 0.275 = 11.00 exactly, not 40 × 0.28.
      final i = arcRate(
        const ArcPlayerState(spi: 40, sxpUnits: 39 * 11, matches: 0),
        const ArcMatchInput(mySide: [40, 40], theirSide: [40, 40], pointsFor: 11, pointsAgainst: 5, won: true),
      );
      expect(i.sxpAfter, 11.0);
      expect(sxpText(i.shownAfter), '11.00');
    });

    test('the shown update always adds up: previous + earned = new', () {
      // 684.225 shows 684.23; +0.275 takes it to 684.50 exactly, so the
      // change shown is +0.27, not the rounded 0.28.
      final i = arcRate(
        ArcPlayerState(spi: 40, sxpUnits: Sxp.unitsOf(684.225), matches: 0),
        const ArcMatchInput(mySide: [40, 40], theirSide: [40, 40], pointsFor: 11, pointsAgainst: 9, won: true),
      );
      expect(i.shownBefore, 684.23);
      expect(i.shownAfter, 684.50);
      expect(i.shownGain, closeTo(0.27, 1e-9));
      for (var start = 0; start < 200; start++) {
        final j = arcRate(
          ArcPlayerState(spi: 40, sxpUnits: start, matches: 0),
          const ArcMatchInput(mySide: [40, 40], theirSide: [40, 40], pointsFor: 11, pointsAgainst: 9, won: true),
        );
        expect(((j.shownBefore + j.shownGain) * 100).round(), (j.shownAfter * 100).round());
      }
    });

    test('the formula line and display text', () {
      final d = arcRate(
        ArcPlayerState.newPlayer,
        const ArcMatchInput(mySide: [40, 40], theirSide: [40, 40], pointsFor: 11, pointsAgainst: 8, won: true),
      );
      expect(d.formula, '11 points ÷ 20 ÷ 2 players');
      expect(singles(chirag, chirag, 11, 6, trust: ArcTrust.tournament, type: ArcMatchType.tournament).formula,
          '11 points ÷ 10');
      expect(sxpText(1842.3), '1,842.30');
      expect(sxpText(10000), '10,000.00');
      expect(sxpDeltaText(0.55), '+0.55');
      expect(sxpDeltaText(0), '0.00');
    });

    test('SXP never goes down through play; a shut-out earns nothing', () {
      expect(singles(arjun, bhavin, 0, 11).sxpGain, 0);
      expect(singles(arjun, bhavin, 1, 11).sxpGain, greaterThan(0));
    });
  });

  group('SkorX Rating is unchanged', () {
    test('A: a dominant win over a weaker player', () {
      final a = singles(arjun, bhavin, 11, 2);
      expect(a.expectedShare, closeTo(0.700, 0.001));
      expect(a.spiAfter, closeTo(73.6, 0.05));
      expect(singles(bhavin, arjun, 2, 11).spiAfter, closeTo(29.7, 0.05));
    });

    test('B/C: a scrappy win, and the close loser gains SPI', () {
      expect(singles(arjun, bhavin, 11, 9).spiAfter, closeTo(70.3, 0.05));
      expect(singles(bhavin, arjun, 9, 11).spiAfter, closeTo(34.5, 0.05));
    });

    test('D: an upset', () {
      expect(singles(bhavin, arjun, 11, 9).spiAfter, closeTo(36.3, 0.05));
    });

    test('H: a championship final', () {
      final h = singles(chirag, farhan, 11, 7,
          type: ArcMatchType.championship, stage: ArcStage.finalRound, trust: ArcTrust.tournament);
      expect(h.matchWeight, 1.6);
      expect(h.spiAfter, closeTo(53.1, 0.05));
    });

    test('I: self-reported matches never move SPI', () {
      final i = singles(chirag, chirag, 11, 6, type: ArcMatchType.casual, trust: ArcTrust.selfReported);
      expect(i.spiAfter, closeTo(50, 1e-9));
    });

    test('K: a new player upsetting a star is capped', () {
      const neel = ArcPlayerState(spi: 35, sxpUnits: 800, matches: 2);
      final k = singles(neel, arjun, 11, 9, type: ArcMatchType.tournament, trust: ArcTrust.tournament);
      expect(k.spiAfter, closeTo(45.8, 0.05));
      final star = arcRate(
        arjun,
        const ArcMatchInput(
          mySide: [72],
          theirSide: [35],
          pointsFor: 9,
          pointsAgainst: 11,
          won: false,
          type: ArcMatchType.tournament,
          trust: ArcTrust.tournament,
          otherPlayersMatches: [2],
        ),
      );
      expect(star.spiAfter, closeTo(70.5, 0.05));
    });

    test('U: a blowout between equals moves SPI at most 0.20', () {
      expect(singles(chirag, chirag, 11, 1).spiAfter, closeTo(55.0, 0.05));
    });

    test('weak-link team strength, and doubles SPI', () {
      expect(arcTeamSpi([72, 32]), closeTo(50.3, 0.05));
      expect(arcTeamSpi([60, 52]), closeTo(55.6, 0.05));
      final chiragSide = arcRate(
        chirag,
        const ArcMatchInput(
          mySide: [50, 48],
          theirSide: [50, 55],
          pointsFor: 11,
          pointsAgainst: 8,
          won: true,
          type: ArcMatchType.league,
          trust: ArcTrust.organiser,
          otherPlayersMatches: [30, 40, 35],
        ),
      );
      expect(chiragSide.expectedShare, closeTo(0.483, 0.001));
      expect(chiragSide.spiAfter, closeTo(51.4, 0.05));
      expect(chiragSide.sxpGain, 0.55, reason: '11 ÷ 10 ÷ 2');
    });

    test('heat needs 3 rated matches and is signed', () {
      final win = singles(chirag, chirag, 11, 5);
      final loss = singles(chirag, chirag, 5, 11);
      expect(arcHeat([win, win]), isNull);
      expect(arcHeat([win, win, win])!, greaterThan(20));
      expect(arcHeat([loss, loss, loss])!, lessThan(-20));
      expect(arcHeatLabel(12.5), 'Hot');
    });
  });

  group('levels', () {
    test('fourteen levels from 0 to 10,000, by Career Score alone', () {
      expect(ArcLevel.all, hasLength(14));
      expect(ArcLevel.all.first.minSxp, 0);
      expect(ArcLevel.all.last.minSxp, 10000);
      for (var i = 1; i < ArcLevel.all.length; i++) {
        expect(ArcLevel.all[i].minSxp, greaterThan(ArcLevel.all[i - 1].minSxp));
        expect(ArcLevel.all[i].number, i + 1);
      }
      expect(ArcLevel.of(0).name, 'First Serve');
      expect(ArcLevel.of(9.99).name, 'First Serve');
      expect(ArcLevel.of(10).name, 'Baseliner');
      expect(ArcLevel.of(100).name, 'Centurion');
      expect(ArcLevel.of(684.75).name, 'Net Raider');
      expect(ArcLevel.of(10000).name, 'SkorX Legend');
      expect(ArcLevel.of(25000).name, 'SkorX Legend', reason: 'the score keeps counting past 10,000');
      expect(ArcLevel.of(800).progress(800), 0.5);
      expect(ArcLevel.of(12000).progress(12000), 1);
    });
  });

  test('the sample season is one consistent career', () {
    final season = SampleSeason(DateTime(2026, 9, 25, 14));
    final mine = season.matches.where((m) => m.involvesMe && m.isCompleted).toList();
    final summary = ArcSummary.fromMatches(mine)!;
    expect(summary.points, season.currentPoints);
    expect(mine.every((m) => m.pointsEarned! >= 0), isTrue);
    expect(summary.formats.keys, containsAll(PlayCategory.values));
    for (final m in mine.where((m) => m.arc != null)) {
      expect(m.arc!.sxpUnits,
          Sxp.units(points: m.pointsWon, divisor: m.arc!.divisor, players: m.mine.length),
          reason: '${m.id}: actual points ÷ divisor ÷ players');
    }
  });

  group('SkorX Rating and SkorX Points stay apart', () {
    final season = SampleSeason(DateTime(2026, 9, 25, 14));
    final summary = ArcSummary.fromMatches(season.matches.where((m) => m.involvesMe && m.isCompleted))!;

    test('bands cover 0–100 in the words players use', () {
      expect(SkorxBand.of(0), SkorxBand.beginner);
      expect(SkorxBand.of(ArcWeights.newPlayerSpi), SkorxBand.beginner, reason: 'everyone starts a Beginner');
      expect(SkorxBand.of(39.9), SkorxBand.beginner);
      expect(SkorxBand.of(40), SkorxBand.intermediate);
      expect(SkorxBand.of(55), SkorxBand.advanced);
      expect(SkorxBand.of(70), SkorxBand.pro);
      expect(SkorxBand.pro.next, isNull);
    });

    test('the timeline ends on today\'s rating and points', () {
      expect(summary.timeline.last.rating, closeTo(summary.rating, 1e-9));
      expect(Sxp.shown(summary.timeline.last.pointsUnits), summary.points);
      expect(summary.timeline.first.points, SampleSeason.startSxp, reason: 'the day before the first match');
    });

    test('points only go up; the rating moves both ways', () {
      final t = summary.timeline;
      for (var i = 1; i < t.length; i++) {
        expect(t[i].points, greaterThanOrEqualTo(t[i - 1].points));
      }
      final moves = [for (var i = 1; i < t.length; i++) t[i].rating - t[i - 1].rating];
      expect(moves.any((d) => d > 0), isTrue);
      expect(moves.any((d) => d < 0), isTrue);
    });

    test('30-day change is measured from the last point before then', () {
      final now = DateTime(2026, 9, 25, 14);
      final before = summary.timeline.lastWhere((p) => p.date.isBefore(now.subtract(const Duration(days: 30))));
      expect(summary.ratingChange(now), closeTo(summary.rating - before.rating, 1e-9));
      expect(summary.pointsEarned(now), closeTo(summary.points - Sxp.shown(before.pointsUnits), 1e-9));
    });
  });
}
