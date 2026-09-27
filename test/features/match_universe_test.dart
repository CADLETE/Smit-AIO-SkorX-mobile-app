import 'package:flutter_test/flutter_test.dart';
import 'package:skorx/features/matches/data/match.dart';
import 'package:skorx/features/matches/data/match_feed.dart';
import 'package:skorx/features/matches/data/sample_universe.dart';
import 'package:skorx/features/paddle/data/my_play.dart';
import 'package:skorx/features/player/data/player_repository.dart' show PlayCategory;
import 'package:skorx/features/player/data/player_stats.dart';
import 'package:skorx/features/tournaments/data/tournaments.dart';

void main() {
  final universe = SampleUniverse(DateTime.now());
  final feed = SampleMatchFeedRepository(universe, latency: Duration.zero);
  final stats = SamplePlayerStatsRepository(universe, myName: 'Smit Ramani', latency: Duration.zero);
  final myPlay = SampleMyPlayRepository(universe, tournaments: SampleTournamentRepository(latency: Duration.zero), latency: Duration.zero);

  group('the SkorX universe', () {
    test('every match has a place, across cities, states and countries', () {
      expect(universe.matches.every((m) => m.place != null), isTrue);
      final countries = {for (final m in universe.matches) m.place!.country};
      final cities = {for (final m in universe.matches) m.place!.city};
      expect(countries, containsAll(['India', 'Singapore', 'United Arab Emirates']));
      expect(cities.length, greaterThanOrEqualTo(8));
      expect({for (final m in universe.matches.where((m) => m.isLive)) m.place!.city}.length, greaterThan(2),
          reason: 'live matches in more than one city');
    });

    test('match ids are unique', () {
      final ids = universe.matches.map((m) => m.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('a new player has no matches, but SkorX still does', () {
      final fresh = SampleUniverse(DateTime.now(), includeMe: false);
      expect(fresh.matches.where((m) => m.involvesMe), isEmpty);
      expect(fresh.matches.length, greaterThan(100));
    });
  });

  group('a match from another player\'s side', () {
    final m = universe.matches.firstWhere((m) => m.id == 'fr-1'); // You beat Dev Patel 11–5 11–8.

    test('flips the sides, the games and the result', () {
      final dev = m.seenBy('Dev Patel')!;
      expect(dev.mine, ['Dev Patel']);
      expect(dev.theirs, ['You']);
      expect(dev.games, [(5, 11), (8, 11)]);
      expect(dev.won, isFalse);
      expect(dev.pointsEarned, isNull, reason: 'the rating change is the signed-in player\'s');
      expect(m.seenBy('You'), same(m));
      expect(m.seenBy('Rahul Mehta'), isNull);
    });
  });

  group('player stats', () {
    test('the signed-in player\'s career agrees with their record', () async {
      final mine = universe.matches.where((m) => m.involvesMe && m.isCompleted).toList();
      final s = await stats.stats('me');
      expect(s.career.played, mine.length);
      expect(s.career.wins, mine.where((m) => m.won).length);
      expect(s.formats.fold(0, (n, f) => n + f.played), s.career.played, reason: 'formats add up');
      expect(s.casual.played + s.tournament.played, s.career.played, reason: 'casual + tournament add up');
      expect(s.form, hasLength(10));
    });

    test('are summed from matches, for anyone', () async {
      final profile = await stats.profile('Dev Patel');
      expect(profile.id, 'SKX-10611');
      expect(profile.placeLabel, 'Ahmedabad, Gujarat');
      final s = await stats.stats(profile.id);
      final played = universe.matches.where((m) => m.isCompleted && m.hasPlayer('Dev Patel')).length;
      expect(s.career.played, played);
      expect(s.career.wins + s.career.losses, played);
    });

    test('the streak counts the current run', () {
      Match m(int day, bool won) => Match(
            id: 'm$day',
            status: MatchStatus.completed,
            kind: MatchKind.friendly,
            format: PlayCategory.singles,
            mine: const ['A'],
            theirs: const ['B'],
            scheduledAt: DateTime(2026, 1, day),
            games: won ? const [(11, 3), (11, 4)] : const [(3, 11), (4, 11)],
          );
      final s = PlayerStats.from('A', [m(1, true), m(2, true), m(3, true), m(4, false), m(5, true), m(6, true)]);
      expect(s.streak, 2);
      expect(s.streakLabel, 'W2');
      expect(s.bestWinStreak, 3);
      expect(s.winRateOfLast(5), 80);
      expect(PlayerStats.from('B', [m(5, true), m(6, true)]).streakLabel, 'L2');
    });

    test('rivals and head-to-head tell the same story', () async {
      final rivals = await stats.rivals('me');
      expect(rivals, isNotEmpty);
      expect(rivals.map((r) => r.player.name), isNot(contains('Kamal Parmar')), reason: 'a partner is not a rival');
      final top = rivals.first;
      final h2h = await stats.headToHead('me', top.player.id);
      expect(h2h.played, top.record.played);
      expect(h2h.aWins, top.record.wins);
      expect(h2h.aWins + h2h.bWins, h2h.played);
      expect(h2h.meetings.every((m) => m.mine.contains('You') && m.theirs.contains(top.player.matchName)), isTrue);
      // And from the other side.
      final back = await stats.headToHead(top.player.id, 'me');
      expect(back.aWins, h2h.bWins);
    });

    test('match history pages from the player\'s side, with no repeats', () async {
      final first = await stats.matches('SKX-10611', limit: 3);
      final next = await stats.matches('SKX-10611', before: first.matches.last.playedAt, limit: 3);
      expect(first.matches.every((m) => m.mine.contains('Dev Patel')), isTrue);
      expect({...first.matches.map((m) => m.id)}.intersection({...next.matches.map((m) => m.id)}), isEmpty);
    });
  });

  group('the Matches feed', () {
    Future<List<Match>> everything(MatchQuery q) async {
      final out = <Match>[];
      String? cursor;
      do {
        final page = await feed.feed(q, cursor: cursor, limit: 7);
        out.addAll(page.matches);
        cursor = page.nextCursor;
      } while (cursor != null);
      return out;
    }

    test('pages through every match once, live first', () async {
      final all = await everything(const MatchQuery());
      expect(all.map((m) => m.id).toSet().length, all.length);
      expect(all.length, universe.matches.where((m) => !m.isCancelled).length);
      expect(all.first.isLive, isTrue);
      final firstCompleted = all.indexWhere((m) => m.isCompleted);
      expect(all.skip(firstCompleted).every((m) => m.isCompleted), isTrue);
    });

    test('filters by place, format, category and status on the server', () async {
      final amd = await everything(const MatchQuery(place: PlaceFilter(city: 'Ahmedabad')));
      expect(amd, isNotEmpty);
      expect(amd.every((m) => m.place!.city == 'Ahmedabad'), isTrue);

      final gujarat = await everything(const MatchQuery(place: PlaceFilter(country: 'India', region: 'Gujarat')));
      expect({for (final m in gujarat) m.place!.city}, containsAll(['Ahmedabad', 'Surat']));

      final sg = await everything(const MatchQuery(place: PlaceFilter(country: 'Singapore')));
      expect(sg.every((m) => m.place!.country == 'Singapore'), isTrue);

      final singlesLive = await everything(const MatchQuery(status: MatchStatus.live, formats: {PlayCategory.singles}));
      expect(singlesLive.every((m) => m.isLive && m.format == PlayCategory.singles), isTrue);

      final casual = await everything(const MatchQuery(category: MatchCategory.casual));
      expect(casual.every((m) => m.tournament == null), isTrue);

      final spt = await everything(const MatchQuery(tournamentId: 't-spt-amd'));
      expect(spt.every((m) => m.tournament!.id == 't-spt-amd'), isTrue);
      expect(spt.where((m) => m.isLive), isNotEmpty);
    });

    test('search finds players, tournaments, venues and match ids', () async {
      final kavya = await everything(const MatchQuery(text: 'kavya'));
      expect(kavya, isNotEmpty);
      expect(kavya.every((m) => m.players.any((p) => p.toLowerCase().contains('kavya'))), isTrue);

      final spt = await everything(const MatchQuery(text: 'SPT 2026'));
      expect({for (final m in spt) m.tournament!.id}, {'t-spt-amd', 't-spt-surat'});

      expect(await everything(const MatchQuery(text: 'NSCI')), everyElement(predicate<Match>((m) => m.venue == 'NSCI Dome')));
      expect((await everything(const MatchQuery(text: 'lg-qf1'))).single.id, 'lg-qf1');

      final suggestions = await feed.suggest('SPT');
      expect(suggestions.where((s) => s.kind == SuggestionKind.tournament).map((s) => s.label),
          containsAll(['SPT 2026 Ahmedabad', 'SPT 2026 Surat']));
    });

    test('tournaments carry their live, upcoming and completed counts', () async {
      final list = await feed.tournaments(const MatchQuery());
      final spt = list.firstWhere((t) => t.id == 't-spt-amd');
      final matches = universe.matches.where((m) => m.tournament?.id == 't-spt-amd');
      expect(spt.live, matches.where((m) => m.isLive).length);
      expect(spt.upcoming, matches.where((m) => m.isUpcoming).length);
      expect(spt.completed, matches.where((m) => m.isCompleted).length);
      expect(list.first.live, greaterThan(0), reason: 'live tournaments first');
    });

    test('the location filter lists every place with matches, without hard-coding any', () async {
      final options = placeOptions([for (final v in await feed.places()) (country: v.place.country, region: v.place.region, city: v.place.city)]);
      expect(options.first.country, 'India');
      expect(options.firstWhere((o) => o.country == 'India').regions['Gujarat'], containsAll(['Ahmedabad', 'Surat', 'Vadodara']));
      expect(options.map((o) => o.country), contains('Singapore'));
    });
  });

  group('My Paddle only ever shows the player\'s own matches', () {
    test('casual and tournament splits', () async {
      final casual = await myPlay.myMatches(MatchCategory.casual, limit: 100);
      final tournament = await myPlay.myMatches(MatchCategory.tournament, limit: 100);
      expect(casual.matches.every((m) => m.involvesMe && m.tournament == null), isTrue);
      expect(tournament.matches.every((m) => m.involvesMe && m.tournament != null), isTrue);
      final summary = await myPlay.summary(MatchCategory.casual);
      expect(summary.played, casual.matches.length);
    });

    test('my matches in a tournament are mine, not the whole draw', () async {
      final league = universe.matches.where((m) => m.tournament?.id == 't-league').toList();
      final mine = await myPlay.tournamentMatches('t-league');
      expect(mine, isNotEmpty);
      expect(mine.length, lessThan(league.length));
      expect(mine.every((m) => m.involvesMe && m.mine.contains('You')), isTrue);
      expect(await myPlay.tournamentMatches('t-spt-amd'), isEmpty, reason: 'a tournament the player is not in');
    });

    test('my tournaments are the ones I entered or played', () async {
      final list = await myPlay.tournaments();
      expect(list.map((t) => t.tournament.id), containsAll(['t-league', 't-monsoon', 't-open']));
      expect(list.map((t) => t.tournament.id), isNot(contains('t-spt-amd')));
      final monsoon = list.firstWhere((t) => t.tournament.id == 't-monsoon');
      expect((monsoon.played, monsoon.wins, monsoon.losses), (5, 3, 2));
    });
  });

  group('tournament discovery filters', () {
    final now = DateTime.now();
    final all = SampleTournamentRepository(latency: Duration.zero);

    test('status, place and dates', () async {
      final list = await all.discover();
      List<String> ids(TournamentFilters f) => [for (final t in list) if (f.matches(t, now)) t.id];

      expect(ids(const TournamentFilters()), isNot(contains('t-monsoon')), reason: 'past tournaments are hidden by default');
      expect(ids(const TournamentFilters(phases: {TournamentPhase.live})), containsAll(['t-league', 't-spt-amd', 't-mumbai']));
      expect(ids(const TournamentFilters(dates: DateWindow.past)), containsAll(['t-monsoon', 't-sg', 't-spt-surat']));
      expect(ids(const TournamentFilters(place: PlaceFilter(country: 'India', region: 'Maharashtra'))), ['t-mumbai']);
      expect(ids(const TournamentFilters(text: 'SPT', phases: {TournamentPhase.live, TournamentPhase.completed})),
          containsAll(['t-spt-amd', 't-spt-surat']));
    });

    test('saved filters survive a restart', () {
      const f = TournamentFilters(place: PlaceFilter(country: 'India', city: 'Surat'), phases: {TournamentPhase.live}, dates: DateWindow.today);
      final back = TournamentFilters.fromJson(f.toJson());
      expect(back.place, f.place);
      expect(back.phases, f.phases);
      expect(back.dates, DateWindow.today);
    });
  });
}
