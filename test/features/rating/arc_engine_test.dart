import 'package:flutter_test/flutter_test.dart';
import 'package:skorx/features/matches/data/match_repository.dart';
import 'package:skorx/features/player/data/player_repository.dart' show PlayCategory;
import 'package:skorx/features/rating/arc_career.dart';
import 'package:skorx/features/rating/arc_engine.dart';

/// The scenarios of the rating spec (docs/RATING-SYSTEM.md §19): the app and
/// the published numbers must agree.
void main() {
  const arjun = ArcPlayerState(spi: 72, sxp: 640, matches: 60);
  const bhavin = ArcPlayerState(spi: 32, sxp: 150, matches: 25);
  const chirag = ArcPlayerState(spi: 50, sxp: 400, matches: 40);
  const farhan = ArcPlayerState(spi: 66, sxp: 560, matches: 50);

  ArcImpact singles(ArcPlayerState me, ArcPlayerState them, int pf, int pa,
          {ArcMatchType type = ArcMatchType.league, ArcStage stage = ArcStage.pool, ArcTrust trust = ArcTrust.organiser,
          int meetings = 0, int today = 0}) =>
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
          previousMeetings: meetings,
          matchesEarlierToday: today,
        ),
      );

  group('singles scenarios', () {
    test('A: a dominant win over a weaker player', () {
      final a = singles(arjun, bhavin, 11, 2);
      expect(a.expectedShare, closeTo(0.700, 0.001));
      expect(a.sxpGain, closeTo(15.5, 0.05));
      expect(a.spiAfter, closeTo(73.6, 0.05));
      final b = singles(bhavin, arjun, 2, 11);
      expect(b.sxpGain, closeTo(4.2, 0.05));
      expect(b.spiAfter, closeTo(29.7, 0.05));
    });

    test('B/C: a scrappy win earns less, and the close loser gains SPI', () {
      final win = singles(arjun, bhavin, 11, 9);
      expect(win.sxpGain, closeTo(8.9, 0.05));
      expect(win.spiAfter, closeTo(70.3, 0.05));
      final loss = singles(bhavin, arjun, 9, 11);
      expect(loss.sxpGain, closeTo(12.3, 0.05));
      expect(loss.spiAfter, closeTo(34.5, 0.05));
    });

    test('D: an upset is worth the most', () {
      final d = singles(bhavin, arjun, 11, 9);
      expect(d.sxpGain, closeTo(21.8, 0.05));
      expect(d.spiAfter, closeTo(36.3, 0.05));
    });

    test('H: a championship final', () {
      final h = singles(chirag, farhan, 11, 7,
          type: ArcMatchType.championship, stage: ArcStage.finalRound, trust: ArcTrust.tournament);
      expect(h.matchWeight, 1.6);
      expect(h.sxpGain, closeTo(34.0, 0.05));
      expect(h.spiAfter, closeTo(53.1, 0.05));
    });

    test('I: self-reported matches never move SPI', () {
      final i = singles(chirag, chirag, 11, 6, type: ArcMatchType.casual, trust: ArcTrust.selfReported);
      expect(i.sxpGain, closeTo(6.2, 0.05));
      expect(i.spiAfter, closeTo(50, 1e-9));
    });

    test('J: repeat matches against one opponent fade', () {
      final gains = [
        for (var k = 0; k < 5; k++)
          singles(arjun, bhavin, 11, 4, type: ArcMatchType.club, trust: ArcTrust.players, meetings: k).sxpGain,
      ];
      expect(gains.map((g) => (g * 10).round() / 10), [8.0, 5.6, 3.9, 2.8, 1.9]);
    });

    test('K: a new player upsetting a star is capped', () {
      const neel = ArcPlayerState(spi: 35, sxp: 20, matches: 2);
      final k = singles(neel, arjun, 11, 9, type: ArcMatchType.tournament, trust: ArcTrust.tournament);
      expect(k.sxpGain, closeTo(27.0, 0.05));
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

    test('P: gravity slows a grinder above their skill', () {
      const grinder = ArcPlayerState(spi: 32, sxp: 700, matches: 120);
      const gauri = ArcPlayerState(spi: 48, sxp: 300, matches: 30);
      final p = singles(grinder, gauri, 11, 7);
      expect(p.gravity, closeTo(0.29, 0.005));
      expect(p.sxpGain, closeTo(4.8, 0.05));
    });

    test('U: a blowout between equals moves SPI at most 0.20', () {
      final u = singles(chirag, chirag, 11, 1);
      expect(u.sxpGain, closeTo(27.5, 0.05));
      expect(u.spiAfter, closeTo(55.0, 0.05));
    });

    test('9th match of the day counts half', () {
      final t = singles(chirag, chirag, 11, 8, type: ArcMatchType.casual, trust: ArcTrust.players, today: 8);
      expect(t.fatigueFactor, 0.5);
      expect(t.sxpGain, closeTo(3.5, 0.05));
    });
  });

  group('doubles', () {
    test('weak-link team strength', () {
      expect(arcTeamSpi([72, 32]), closeTo(50.3, 0.05));
      expect(arcTeamSpi([60, 52]), closeTo(55.6, 0.05));
    });

    test('F: both partners get the full per-player credit', () {
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
      expect(chiragSide.sxpGain, closeTo(14.5, 0.05));
      expect(chiragSide.spiAfter, closeTo(51.4, 0.05));
    });
  });

  group('explaining a change', () {
    test('the breakdown lines add up to the headline', () {
      for (final i in [
        singles(bhavin, arjun, 9, 11),
        singles(chirag, farhan, 11, 7, type: ArcMatchType.championship, stage: ArcStage.finalRound),
        singles(chirag, chirag, 11, 6, type: ArcMatchType.casual, trust: ArcTrust.selfReported),
      ]) {
        final sum = i.displayLines.fold<double>(0, (s, l) => s + l.value);
        expect(sum, closeTo((i.sxpGain * 10).round() / 10, 1e-9));
      }
    });

    test('SXP never goes down', () {
      expect(singles(arjun, bhavin, 0, 11).sxpGain, greaterThan(0));
    });
  });

  group('levels and heat', () {
    test('levels follow SXP and their gates', () {
      expect(ArcLevel.of(0).name, 'First Serve');
      expect(ArcLevel.of(684).name, 'Net Commander');
      expect(ArcLevel.of(1500).name, 'SkorX Legend');
      expect(ArcLevel.reached(684, verified: 30, tournament: 2, confirmed: true).name, 'Transition Hunter');
      expect(ArcLevel.of(650).progress(650), 0.5);
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

  test('the sample season is one consistent career', () {
    final season = SampleSeason(DateTime(2026, 9, 25, 14));
    final mine = season.matches.where((m) => m.involvesMe && m.isCompleted).toList();
    final summary = ArcSummary.fromMatches(mine)!;
    expect(summary.points, season.currentRating);
    expect(mine.every((m) => m.ratingChange! >= 0), isTrue);
    expect(summary.formats.keys, containsAll(PlayCategory.values));
  });
}

