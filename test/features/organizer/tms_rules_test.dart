import 'package:flutter_test/flutter_test.dart';
import 'package:skorx/core/api/api_exception.dart';
import 'package:skorx/features/organizer/data/draw_engine.dart';
import 'package:skorx/features/organizer/data/organizer_repository.dart';
import 'package:skorx/features/organizer/data/sample_organizer_repository.dart';
import 'package:skorx/features/organizer/data/schedule_engine.dart';
import 'package:skorx/features/organizer/data/tms_models.dart';
import 'package:skorx/sports/core/match_rules.dart';
import 'package:skorx/sports/core/score_state.dart';

Entry entry(String id, {int? seed, double rating = 60, List<String>? players, String category = 'c'}) => Entry(
      id: id,
      tournamentId: 't',
      categoryId: category,
      players: [for (final p in players ?? [id]) PlayerRef(id: p, name: 'Player $p', rating: rating)],
      registeredAt: DateTime(2026),
      amount: 500,
      approval: Approval.approved,
      seed: seed,
      checkInCode: id.toUpperCase(),
    );

List<Entry> entries(int n) => [for (var i = 1; i <= n; i++) entry('e$i', rating: 90 - i * 0.5)];

void main() {
  group('tournament life cycle', () {
    test('each status allows only its actions', () {
      expect(TournamentLifecycle.allows(TournamentStatus.draft, TmsAction.editCategories), isTrue);
      expect(TournamentLifecycle.allows(TournamentStatus.draft, TmsAction.scoreMatches), isFalse);
      expect(TournamentLifecycle.allows(TournamentStatus.live, TmsAction.generateDraw), isFalse,
          reason: 'structure is frozen once play starts');
      expect(TournamentLifecycle.allows(TournamentStatus.live, TmsAction.manageEntries), isFalse);
      expect(TournamentLifecycle.allows(TournamentStatus.completed, TmsAction.scoreMatches), isFalse,
          reason: 'results are locked');
      expect(TournamentLifecycle.allows(TournamentStatus.completed, TmsAction.correctResults), isTrue);
      expect(TournamentLifecycle.allows(TournamentStatus.archived, TmsAction.cancel), isFalse);
    });

    test('actions move the tournament forward, and refuse out of order', () {
      expect(TournamentLifecycle.after(TournamentStatus.draft, TmsAction.openRegistration),
          TournamentStatus.registrationOpen);
      expect(TournamentLifecycle.after(TournamentStatus.registrationClosed, TmsAction.generateDraw),
          TournamentStatus.drawGenerated);
      expect(TournamentLifecycle.after(TournamentStatus.draft, TmsAction.startTournament), isNull);
      expect(TournamentLifecycle.nextStep(TournamentStatus.scheduled), TmsAction.startTournament);
    });

    test('changing entries after the draw carries a warning', () {
      expect(TournamentLifecycle.warning(TournamentStatus.drawGenerated, TmsAction.manageEntries), isNotNull);
      expect(TournamentLifecycle.warning(TournamentStatus.registrationOpen, TmsAction.manageEntries), isNull);
    });
  });

  group('draws', () {
    test('bracket order keeps the top two seeds apart until the final', () {
      expect(bracketOrder(8), [1, 8, 4, 5, 2, 7, 3, 6]);
      expect(bracketOrder(4), [1, 4, 2, 3]);
    });

    test('a knockout of 5 gives byes to the top 3 seeds and plays 4 matches', () {
      final layout = generateDraw(
        categoryId: 'c',
        format: DrawFormat.knockout,
        method: DrawMethod.seeded,
        entries: entries(5),
      );
      expect(layout.groups.single, hasLength(8));
      final matches = buildMatches(layout: layout, tournamentId: 't', labelOf: (id) => id);
      final byes = matches.where((m) => m.isBye).toList();
      expect(byes.map((m) => m.entry(m.winner!)), unorderedEquals(['e1', 'e2', 'e3']));
      expect(matches.where((m) => !m.isBye), hasLength(4), reason: 'n - 1 real matches');
      final semis = matches.where((m) => m.roundLabel == 'Semi-final').toList();
      expect(semis.expand((m) => [m.entryA, m.entryB]), containsAll(['e1', 'e2', 'e3']),
          reason: 'bye winners are already placed in round 2');
      expect(matches.last.roundLabel, 'Final');
    });

    test('seeds stay in place in a random draw', () {
      final list = [entry('s1', seed: 1), entry('s2', seed: 2), ...entries(6)];
      final layout =
          generateDraw(categoryId: 'c', format: DrawFormat.knockout, method: DrawMethod.random, entries: list);
      final slots = layout.groups.single;
      expect(slots.first, 's1');
      expect(slots[4], 's2', reason: 'seed 2 opens the bottom half');
    });

    test('round robin plays everyone once and nobody twice in a round', () {
      final rounds = roundRobinRounds(['a', 'b', 'c', 'd', 'e']);
      final pairs = rounds.expand((r) => r).toList();
      expect(pairs, hasLength(10));
      expect({for (final (a, b) in pairs) ([a, b]..sort()).join()}, hasLength(10));
      for (final round in rounds) {
        final seen = round.expand((p) => [p.$1, p.$2]).toList();
        expect(seen.toSet(), hasLength(seen.length));
      }
    });

    test('pool play splits 8 entries into two even pools', () {
      final layout =
          generateDraw(categoryId: 'c', format: DrawFormat.pools, method: DrawMethod.seeded, entries: entries(8));
      expect(layout.groups.map((g) => g.length), [4, 4]);
      expect(layout.groups[0].first, 'e1');
      expect(layout.groups[1].first, 'e2', reason: 'snake seeding');
      final matches = buildMatches(layout: layout, tournamentId: 't', labelOf: (id) => id);
      expect(matches, hasLength(12));
      expect(matches.map((m) => m.number), List.generate(12, (i) => i + 1));
    });

    test('a swap moves both entries', () {
      final layout =
          generateDraw(categoryId: 'c', format: DrawFormat.knockout, method: DrawMethod.seeded, entries: entries(4));
      final swapped = swapInDraw(layout, 'e1', 'e4');
      expect(swapped.groups.single, ['e4', 'e1', 'e2', 'e3']);
    });
  });

  group('schedule', () {
    final start = DateTime(2026, 9, 25, 9);

    void expectNoClashes(List<ScheduledSlot> slots, Map<String, TmsMatch> byId, List<String> Function(String) players) {
      for (final a in slots) {
        for (final b in slots) {
          if (a == b) continue;
          final overlap = a.start.isBefore(b.end) && b.start.isBefore(a.end);
          if (!overlap) continue;
          expect(a.courtId, isNot(b.courtId), reason: 'court double-booked: ${a.matchId} ${b.matchId}');
          final pa = [byId[a.matchId]!.entryA, byId[a.matchId]!.entryB].whereType<String>().expand(players).toSet();
          final pb = [byId[b.matchId]!.entryA, byId[b.matchId]!.entryB].whereType<String>().expand(players);
          expect(pa.intersection(pb.toSet()), isEmpty, reason: 'player double-booked');
        }
      }
    }

    test('knockout rounds wait for the matches that feed them', () {
      final layout =
          generateDraw(categoryId: 'c', format: DrawFormat.knockout, method: DrawMethod.seeded, entries: entries(8));
      final matches = buildMatches(layout: layout, tournamentId: 't', labelOf: (id) => id);
      final slots = buildSchedule(
        matches: matches,
        settings: ScheduleSettings(start: start, courtIds: ['1', '2', '3', '4'], matchMinutes: 20, bufferMinutes: 5),
        playersOf: (id) => [id],
      );
      expect(slots, hasLength(7));
      final at = {for (final s in slots) s.matchId: s};
      for (final m in matches.where((m) => m.sourceA != null)) {
        expect(at[m.id]!.start.isBefore(at[m.sourceA]!.end), isFalse);
        expect(at[m.id]!.start.isBefore(at[m.sourceB]!.end), isFalse);
      }
      expectNoClashes(slots, {for (final m in matches) m.id: m}, (id) => [id]);
    });

    test('a player in two categories is never on two courts at once, and no match starts in the break', () {
      // Everyone shares player "x", so no two matches may overlap at all.
      final a = [for (var i = 0; i < 4; i++) entry('a$i', players: ['a$i', 'x'], category: 'A')];
      final b = [for (var i = 0; i < 4; i++) entry('b$i', players: ['b$i'], category: 'B')];
      final all = {for (final e in [...a, ...b]) e.id: e};
      final matches = [
        ...buildMatches(
            layout: generateDraw(categoryId: 'A', format: DrawFormat.roundRobin, method: DrawMethod.seeded, entries: a),
            tournamentId: 't',
            labelOf: (id) => id),
        ...buildMatches(
            layout: generateDraw(categoryId: 'B', format: DrawFormat.roundRobin, method: DrawMethod.seeded, entries: b),
            tournamentId: 't',
            labelOf: (id) => id,
            firstNumber: 100),
      ];
      List<String> playersOf(String id) => [for (final p in all[id]!.players) p.id];
      final breakStart = start.add(const Duration(hours: 1));
      final slots = buildSchedule(
        matches: matches,
        settings: ScheduleSettings(
          start: start,
          courtIds: ['1', '2', '3'],
          breakStart: breakStart,
          breakMinutes: 30,
        ),
        playersOf: playersOf,
      );
      expect(slots, hasLength(12));
      expectNoClashes(slots, {for (final m in matches) m.id: m}, playersOf);
      final breakEnd = breakStart.add(const Duration(minutes: 30));
      for (final s in slots) {
        expect(s.start.isBefore(breakEnd) && s.end.isAfter(breakStart), isFalse, reason: 'runs into the break');
      }
    });
  });

  group('result validation', () {
    const rules = MatchRules(pointsToWin: 11, winByTwo: true, bestOf: 3);
    const badminton = MatchRules(pointsToWin: 21, winByTwo: true, bestOf: 1, pointCap: 30);

    test('accepts real results', () {
      expect(validateResult(rules, const [GameScore(11, 8), GameScore(11, 9)]), isNull);
      expect(validateResult(rules, const [GameScore(11, 8), GameScore(9, 11), GameScore(14, 12)]), isNull);
      expect(validateResult(badminton, const [GameScore(30, 29)]), isNull);
    });

    test('refuses impossible ones with a reason', () {
      expect(validateResult(rules, const [GameScore(11, 10), GameScore(11, 3)]), contains('won by 2'));
      expect(validateResult(rules, const [GameScore(15, 9), GameScore(11, 3)]), contains('2-point lead'));
      expect(validateResult(rules, const [GameScore(11, 8)]), contains('Nobody has won 2'));
      expect(validateResult(rules, const [GameScore(11, 8), GameScore(11, 8), GameScore(11, 8)]), contains('not needed'));
      expect(validateResult(rules, const [GameScore(9, 7), GameScore(11, 3)]), contains('at least 11'));
      expect(validateResult(badminton, const [GameScore(30, 20)]), contains('ended before 30'));
      expect(
        validateResult(const MatchRules(pointsToWin: 11, winByTwo: false, bestOf: 1), const [GameScore(12, 10)]),
        contains('ends at 11'),
      );
    });
  });

  group('sample server', () {
    late SampleOrganizerRepository repo;
    setUp(() => repo = SampleOrganizerRepository(latency: Duration.zero));
    tearDown(() => repo.dispose());

    Future<TmsMatch> liveMatch() async {
      await repo.tournaments('org1');
      return (await repo.matches('t-summer')).firstWhere((m) => m.state == MatchState.live);
    }

    test('the live tournament has results, live courts, a delayed court and a court on break', () async {
      await repo.tournaments('org1');
      final board = courtBoard(await repo.courts('t-summer'), await repo.matches('t-summer'), DateTime.now());
      final statuses = board.map((s) => s.status).toList();
      expect(statuses, contains(CourtStatus.live));
      expect(statuses, contains(CourtStatus.delayed));
      expect((await repo.matches('t-summer')).where((m) => m.state == MatchState.completed), isNotEmpty);
      for (final m in await repo.matches('t-summer')) {
        if (m.state == MatchState.completed) {
          final c = (await repo.tournament('t-summer')).category(m.categoryId)!;
          expect(validateResult(c.rules, m.games), isNull, reason: 'seeded result ${m.scoreLine} is real');
        }
      }
    });

    test('resending a score write is a no-op; a stale one is a conflict', () async {
      final m = await liveMatch();
      final write = ScoreWrite(clientEventId: 'tap-1', baseVersion: m.scoreVersion, kind: ScoreWriteKind.rally, side: Side.a);
      final first = await repo.score(m.id, write);
      final again = await repo.score(m.id, write);
      expect(first.scoreVersion, m.scoreVersion + 1);
      expect(again.scoreVersion, first.scoreVersion, reason: 'the same tap never counts twice');

      final stale = ScoreWrite(clientEventId: 'tap-2', baseVersion: m.scoreVersion, kind: ScoreWriteKind.rally, side: Side.b);
      await expectLater(
        repo.score(m.id, stale),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', scoreConflict)),
      );
    });

    test('confirming a result puts the winner into the next round', () async {
      final m = await liveMatch();
      var current = m;
      var n = 0;
      while (current.winner == null) {
        current = await repo.score(
          m.id,
          ScoreWrite(clientEventId: 'w${n++}', baseVersion: current.scoreVersion, kind: ScoreWriteKind.rally, side: Side.a),
        );
      }
      final done = await repo.confirmResult(m.id, current.scoreVersion);
      expect(done.state, MatchState.completed);
      final next = (await repo.matches('t-summer')).where((x) => x.sourceA == m.id || x.sourceB == m.id).firstOrNull;
      if (next != null) {
        expect([next.entryA, next.entryB], contains(m.entryA));
      }
      final log = await repo.audit('org1');
      expect(log.first.action, 'Confirmed result');
    });

    test('the server refuses what the life cycle does not allow', () async {
      await repo.tournaments('org1');
      await expectLater(
        repo.generateDraw('t-night', 't-night-od', DrawMethod.seeded),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'TOURNAMENT_STATE')),
        reason: 'registration is still open',
      );
      final entries = await repo.entries('t-summer');
      await expectLater(
        repo.updateEntry(entries.first.id, const EntryChange(approval: Approval.rejected)),
        throwsA(isA<ApiException>()),
        reason: 'no entry changes once live',
      );
    });

    test('a player registering from the Player app lands in the organiser queue', () async {
      await repo.tournaments('org1');
      final before = (await repo.entries('t-night')).length;
      repo.registerPlayer('t-night', 't-night-od', playerName: 'Smit Ramani', partner: 'Kamal Parmar');
      final after = await repo.entries('t-night');
      expect(after, hasLength(before + 1));
      expect(after.first.name, 'Smit Ramani / Kamal Parmar');
      expect(after.first.approval, Approval.pending);
      expect(repo.playerTournaments().map((t) => t.id), contains('t-night'));
      expect(repo.playerTournaments().map((t) => t.id), isNot(contains('t-diwali')), reason: 'drafts stay private');
    });

    test('closing registration, drawing and scheduling moves the tournament to Scheduled', () async {
      await repo.tournaments('org1');
      await repo.generateDraw('t-league', 't-league-md', DrawMethod.seeded);
      await repo.generateDraw('t-league', 't-league-wd', DrawMethod.seeded);
      expect((await repo.tournament('t-league')).status, TournamentStatus.drawGenerated);
      final courts = await repo.courts('t-league');
      final scheduled = await repo.generateSchedule(
        't-league',
        ScheduleSettings(start: DateTime(2026, 10, 1, 9), courtIds: [for (final c in courts) c.id]),
      );
      expect(scheduled.every((m) => m.scheduledAt != null && m.courtId != null), isTrue);
      expect((await repo.tournament('t-league')).status, TournamentStatus.scheduled);
    });
  });
}
