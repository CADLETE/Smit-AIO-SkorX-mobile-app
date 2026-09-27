import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sample_persona.dart';
import '../../player/data/player_repository.dart' show PlayCategory;
import 'journey.dart';
import 'match.dart';
import 'match_repository.dart' show SampleSeason;

/// The one sample universe for this run of the app (debug builds only).
final sampleUniverseProvider = Provider<SampleUniverse>(
  (ref) => SampleUniverse(DateTime.now(), includeMe: ref.watch(samplePersonaProvider) != SamplePersona.newcomer),
);

/// A player as the sample data knows them.
typedef SamplePlayer = ({String id, String name, String city, String level, int? points});

/// Debug builds: every match on SkorX, not just the signed-in player's. The
/// player's own season ([SampleSeason]) plus casual and tournament matches in
/// other cities, states and countries, all placed, all with real players.
/// Deterministic, so screens and tests always see the same universe.
///
/// Every sample repository that needs more than the player's own matches
/// (global Matches, player stats, rivals, head-to-head) reads this one
/// object, so a player's numbers agree on every screen.
class SampleUniverse {
  SampleUniverse(this.now, {this.includeMe = true}) : season = SampleSeason(now) {
    _build();
  }

  final DateTime now;

  /// False for the "new player" sample: the rest of SkorX still plays, but
  /// the signed-in player has no matches.
  final bool includeMe;
  final SampleSeason season;

  /// Every match, placed.
  final List<Match> matches = [];
  final Map<String, List<TournamentRound>> rounds = {};

  final Map<String, SamplePlayer> _byName = {};
  final Map<String, SamplePlayer> _byId = {};

  /// A player by id or name, or null when SkorX does not know them.
  SamplePlayer? player(String idOrName) => _byId[idOrName] ?? _byName[idOrName];

  Iterable<SamplePlayer> get players => _byId.values;

  /// Where [city] is.
  static MatchPlace placeOf(String city) {
    final (region, country) = cities[city] ?? (null, 'India');
    return MatchPlace(city: city, region: region, country: country);
  }

  /// City → (state, country).
  static const cities = <String, (String?, String)>{
    'Ahmedabad': ('Gujarat', 'India'),
    'Surat': ('Gujarat', 'India'),
    'Vadodara': ('Gujarat', 'India'),
    'Rajkot': ('Gujarat', 'India'),
    'Gandhinagar': ('Gujarat', 'India'),
    'Mumbai': ('Maharashtra', 'India'),
    'Pune': ('Maharashtra', 'India'),
    'Bengaluru': ('Karnataka', 'India'),
    'Singapore': (null, 'Singapore'),
    'Dubai': ('Dubai', 'United Arab Emirates'),
  };

  /// Venue → city.
  static const venues = <String, String>{
    'CADLETE Club': 'Ahmedabad',
    'Riverside Courts': 'Ahmedabad',
    'Pickle Blitz Arena': 'Ahmedabad',
    'Smash Arena': 'Ahmedabad',
    'Diamond Sports Hub': 'Surat',
    'Vesu Pickle Courts': 'Surat',
    'Sayaji Sports Complex': 'Vadodara',
    'Racecourse Pickle Park': 'Rajkot',
    'Capital Courts': 'Gandhinagar',
    'NSCI Dome': 'Mumbai',
    'Bandra Pickle House': 'Mumbai',
    'Baner Pickle Yard': 'Pune',
    'Koramangala Paddle Club': 'Bengaluru',
    'Indiranagar Courts': 'Bengaluru',
    'Kallang Pickle Centre': 'Singapore',
    'Tampines Hub Courts': 'Singapore',
    'Marina Pickleball Courts': 'Dubai',
  };

  /// Players with a known rating and level (the Explore sample), then
  /// everyone else by city.
  static const _known = <(String, String, String, int?, String)>[
    ('SKX-10021', 'Aarav Shah', 'Ahmedabad', 1420, 'Advanced'),
    ('SKX-10388', 'Kavya Mehta', 'Ahmedabad', 1394, 'Advanced'),
    ('SKX-10412', 'Diya Joshi', 'Ahmedabad', 1368, 'Advanced'),
    ('SKX-10477', 'Meera Iyer', 'Ahmedabad', 1342, 'Intermediate'),
    ('SKX-10503', 'Vivaan Gupta', 'Ahmedabad', 1303, 'Intermediate'),
    ('SKX-10519', 'Riya Shah', 'Ahmedabad', 1277, 'Intermediate'),
    ('SKX-10544', 'Hardik Suthar', 'Ahmedabad', 1231, 'Intermediate'),
    ('SKX-10233', 'Ishaan Patel', 'Surat', 1407, 'Advanced'),
    ('SKX-10291', 'Rohan Desai', 'Vadodara', 1381, 'Advanced'),
    ('SKX-10302', 'Arjun Trivedi', 'Rajkot', 1355, 'Intermediate'),
    ('SKX-10355', 'Kabir Rao', 'Gandhinagar', 1329, 'Intermediate'),
    ('SKX-10366', 'Anaya Nair', 'Surat', 1316, 'Intermediate'),
    ('SKX-10590', 'Sara Khan', 'Vadodara', 1290, 'Intermediate'),
    ('SKX-10611', 'Dev Patel', 'Ahmedabad', 1264, 'Intermediate'),
    ('SKX-10009', 'Vikram Singh', 'Mumbai', 1612, 'Pro'),
    ('SKX-10014', 'Tara Menon', 'Mumbai', 1588, 'Pro'),
    ('SKX-10718', 'Parth Bhatt', 'Gandhinagar', 1096, 'Beginner'),
    ('SKX-10731', 'Zoya Qureshi', 'Surat', 1122, 'Beginner'),
  ];

  static const _others = <String, List<String>>{
    'Ahmedabad': [
      'Anand Varsada', 'Kamal Parmar', 'Om Trivedi', 'Jay Desai', 'Rahul Mehta', 'Vivek Rana', 'Karan Shah',
      'Nikhil Jain', 'Nisha Joshi',
    ],
    'Surat': ['Harsh Vora', 'Pooja Desai'],
    'Vadodara': ['Manav Shah', 'Isha Pandya', 'Aarav Mehta'],
    'Rajkot': ['Jeet Jadeja', 'Krisha Mehta', 'Yash Kotecha'],
    'Gandhinagar': ['Aditi Joshi', 'Dhruv Patel'],
    'Mumbai': ['Aditya Kulkarni', 'Neha Sawant', 'Rohit Nair', 'Sameer Khan', 'Ananya Pillai', 'Kunal Shetty'],
    'Pune': ['Omkar Deshmukh', 'Rutuja Patil', 'Siddharth Joshi', 'Mrunal Kale'],
    'Bengaluru': ['Arvind Rao', 'Priya Hegde', 'Karthik Iyer', 'Sneha Reddy', 'Varun Gowda', 'Nikita Shenoy', 'Rahul Bhat', 'Divya Nair'],
    'Singapore': ['Wei Jie Tan', 'Rachel Lim', 'Daniel Ong', 'Hui Min Goh', 'Marcus Chua', 'Jasmine Koh', 'Ryan Teo', 'Chloe Ng'],
    'Dubai': ['Omar Haddad', 'Aisha Rahman', 'Faisal Khan', 'Leena Joseph'],
  };

  /// The sample data's older 1000–1700 ratings as career SkorX Points, so
  /// every player sits on the same scale as the ARC engine's SXP.
  static int sxpFromLegacy(int rating) => ((rating - 1000) * 1.5).round().clamp(0, 2000);

  void _addPlayer(String id, String name, String city, String level, int? points) {
    if (_byName.containsKey(name)) return;
    final p = (id: id, name: name, city: city, level: level, points: points == null ? null : sxpFromLegacy(points));
    _byName[name] = p;
    _byId[id] = p;
  }

  static String _levelFor(int points) => points < 1150
      ? 'Beginner'
      : points < 1300
          ? 'Intermediate'
          : points < 1450
              ? 'Advanced'
              : 'Pro';

  final _r = Random(20260927);

  DateTime _day(int d, int hour, [int minute = 0]) => DateTime(now.year, now.month, now.day + d, hour, minute);

  List<(int, int)> _games(bool aWins, {bool? deciding}) {
    int lose() => 2 + _r.nextInt(8);
    (int, int) game(bool a) {
      final close = _r.nextInt(8) == 0;
      final (w, l) = close ? (12, 10) : (11, lose());
      return a ? (w, l) : (l, w);
    }

    final three = deciding ?? _r.nextInt(3) == 0;
    return three ? [game(aWins), game(!aWins), game(aWins)] : [game(aWins), game(aWins)];
  }

  Match _done(
    String id,
    List<String> a,
    List<String> b,
    DateTime at,
    String venue, {
    PlayCategory format = PlayCategory.doubles,
    TournamentRef? t,
    bool? aWins,
    String? court,
  }) {
    final games = _games(aWins ?? _r.nextBool());
    return Match(
      id: id,
      status: MatchStatus.completed,
      kind: t == null ? MatchKind.friendly : MatchKind.tournament,
      format: format,
      mine: a,
      theirs: b,
      involvesMe: false,
      scheduledAt: at,
      startedAt: at,
      completedAt: at.add(Duration(minutes: 22 + games.length * 9 + _r.nextInt(8))),
      games: games,
      tournament: t,
      venue: venue,
      court: court ?? 'Court 0${1 + _r.nextInt(4)}',
    );
  }

  Match _live(String id, List<String> a, List<String> b, int minutesAgo, String venue,
      {PlayCategory format = PlayCategory.doubles, TournamentRef? t, String? court}) {
    final at = now.subtract(Duration(minutes: minutesAgo));
    final games = minutesAgo > 20 ? _games(_r.nextBool(), deciding: false).take(1).toList() : const <(int, int)>[];
    return Match(
      id: id,
      status: MatchStatus.live,
      kind: t == null ? MatchKind.friendly : MatchKind.tournament,
      format: format,
      mine: a,
      theirs: b,
      involvesMe: false,
      scheduledAt: at,
      startedAt: at,
      games: games,
      live: LiveGame(number: games.length + 1, mine: _r.nextInt(10), theirs: _r.nextInt(10), myServe: _r.nextBool()),
      tournament: t,
      venue: venue,
      court: court ?? 'Court 0${1 + _r.nextInt(4)}',
    );
  }

  Match _upcoming(String id, List<String> a, List<String> b, DateTime at, String venue,
          {PlayCategory format = PlayCategory.doubles, TournamentRef? t, String? placeholder, String? court}) =>
      Match(
        id: id,
        status: MatchStatus.upcoming,
        kind: t == null ? MatchKind.friendly : MatchKind.tournament,
        format: format,
        mine: a,
        theirs: b,
        theirsPlaceholder: placeholder,
        involvesMe: false,
        scheduledAt: at,
        tournament: t,
        venue: venue,
        court: court ?? 'Court 0${1 + _r.nextInt(4)}',
      );

  void _build() {
    // ── Players ──
    for (final (id, name, city, points, level) in _known) {
      _addPlayer(id, name, city, level, points);
    }
    var next = 10900;
    for (final e in _others.entries) {
      for (final name in e.value) {
        final points = 1060 + (name.codeUnits.fold(0, (a, b) => a * 31 + b) % 520).abs();
        _addPlayer('SKX-${next++}', name, e.key, _levelFor(points), points);
      }
    }

    final all = <Match>[
      for (final m in season.matches)
        if (includeMe || !m.involvesMe) m,
    ];
    rounds.addAll(season.rounds);

    List<String> pool(String city) => [
          for (final p in _byName.values)
            if (p.city == city) p.name,
        ];

    // ── Casual play, city by city ──
    const casual = <String, (int, int, int)>{
      // completed, live, upcoming
      'Ahmedabad': (22, 1, 3),
      'Surat': (8, 0, 1),
      'Vadodara': (6, 0, 1),
      'Rajkot': (5, 1, 0),
      'Gandhinagar': (5, 0, 1),
      'Mumbai': (10, 1, 2),
      'Pune': (6, 0, 1),
      'Bengaluru': (10, 1, 2),
      'Singapore': (8, 1, 1),
      'Dubai': (5, 0, 1),
    };
    for (final MapEntry(key: city, value: (done, live, upcoming)) in casual.entries) {
      final people = pool(city);
      final places = [
        for (final v in venues.entries)
          if (v.value == city) v.key,
      ];
      final slug = city.substring(0, 3).toLowerCase();
      (List<String>, List<String>, PlayCategory) pick() {
        final shuffled = [...people]..shuffle(_r);
        final format = PlayCategory.values[_r.nextInt(people.length >= 4 ? 3 : 1)];
        if (format == PlayCategory.singles || shuffled.length < 4) return ([shuffled[0]], [shuffled[1]], PlayCategory.singles);
        return ([shuffled[0], shuffled[1]], [shuffled[2], shuffled[3]], format);
      }

      for (var i = 0; i < done; i++) {
        final (a, b, f) = pick();
        final at = _day(-(i * 2 + _r.nextInt(2)), 6 + _r.nextInt(14), _r.nextBool() ? 0 : 30);
        if (at.isAfter(now)) continue;
        all.add(_done('u-$slug-$i', a, b, at, places[i % places.length], format: f));
      }
      for (var i = 0; i < live; i++) {
        final (a, b, f) = pick();
        all.add(_live('u-$slug-live-$i', a, b, 8 + _r.nextInt(30), places[i % places.length], format: f));
      }
      for (var i = 0; i < upcoming; i++) {
        final (a, b, f) = pick();
        all.add(_upcoming('u-$slug-next-$i', a, b, _day(1 + i, 7 + _r.nextInt(12)), places[i % places.length], format: f));
      }
    }

    // ── Tournaments across SkorX ──
    all.addAll(_bracket(
      id: 't-spt-amd',
      name: 'SPT 2026 Ahmedabad',
      category: "Men's Doubles · Open",
      venue: 'Riverside Courts',
      format: PlayCategory.doubles,
      teams: _teams(['Aarav Shah', 'Vivaan Gupta', 'Hardik Suthar', 'Karan Shah', 'Nikhil Jain', 'Rahul Mehta', 'Jay Desai',
          'Om Trivedi', 'Ishaan Patel', 'Harsh Vora', 'Rohan Desai', 'Manav Shah', 'Jeet Jadeja', 'Yash Kotecha', 'Dhruv Patel',
          'Parth Bhatt'], 2),
      qf: (_day(-1, 10), true),
      // Relative to now, so the day is always mid-tournament.
      sf: (now.subtract(const Duration(hours: 2)), 'live'),
      finalAt: now.add(const Duration(hours: 3)),
    ));
    all.addAll(_bracket(
      id: 't-spt-surat',
      name: 'SPT 2026 Surat',
      category: 'Mixed Doubles · Open',
      venue: 'Diamond Sports Hub',
      format: PlayCategory.mixed,
      teams: _teams(['Ishaan Patel', 'Anaya Nair', 'Harsh Vora', 'Zoya Qureshi', 'Rohan Desai', 'Sara Khan', 'Kabir Rao',
          'Pooja Desai', 'Aarav Shah', 'Kavya Mehta', 'Dev Patel', 'Riya Shah', 'Manav Shah', 'Isha Pandya', 'Arjun Trivedi',
          'Krisha Mehta'], 2),
      qf: (_day(-20, 9), true),
      sf: (_day(-19, 11), 'done'),
      finalAt: _day(-19, 17),
      finalDone: true,
    ));
    all.addAll(_bracket(
      id: 't-mumbai',
      name: 'Mumbai Pickleball Masters',
      category: "Men's Singles · Advanced",
      venue: 'NSCI Dome',
      format: PlayCategory.singles,
      teams: _teams(['Vikram Singh', 'Aditya Kulkarni', 'Rohit Nair', 'Sameer Khan', 'Kunal Shetty', 'Omkar Deshmukh',
          'Siddharth Joshi', 'Arvind Rao'], 1),
      qf: (now.subtract(const Duration(hours: 2)), false),
      sf: (_day(1, 10), null),
      finalAt: null,
    ));
    all.addAll(_bracket(
      id: 't-blr',
      name: 'Bengaluru Paddle Open',
      category: 'Open Doubles · Intermediate',
      venue: 'Koramangala Paddle Club',
      format: PlayCategory.doubles,
      teams: _teams(['Arvind Rao', 'Karthik Iyer', 'Varun Gowda', 'Rahul Bhat', 'Priya Hegde', 'Sneha Reddy', 'Nikita Shenoy',
          'Divya Nair', 'Omkar Deshmukh', 'Siddharth Joshi', 'Rutuja Patil', 'Mrunal Kale', 'Aditya Kulkarni', 'Rohit Nair',
          'Neha Sawant', 'Ananya Pillai'], 2),
      qf: (_day(2, 9), null),
      sf: null,
      finalAt: null,
    ));
    all.addAll(_bracket(
      id: 't-sg',
      name: 'Singapore Pickle Cup',
      category: 'Mixed Doubles · Open',
      venue: 'Kallang Pickle Centre',
      format: PlayCategory.mixed,
      teams: _teams(['Wei Jie Tan', 'Rachel Lim', 'Daniel Ong', 'Hui Min Goh', 'Marcus Chua', 'Jasmine Koh', 'Ryan Teo',
          'Chloe Ng', 'Omar Haddad', 'Aisha Rahman', 'Faisal Khan', 'Leena Joseph', 'Tara Menon', 'Kunal Shetty', 'Varun Gowda',
          'Divya Nair'], 2),
      qf: (_day(-11, 9), true),
      sf: (_day(-10, 11), 'done'),
      finalAt: _day(-10, 17),
      finalDone: true,
    ));

    matches.addAll([
      for (final m in all) m.placedIn(placeOf(venues[m.venue] ?? 'Ahmedabad')),
    ]);
  }

  static List<List<String>> _teams(List<String> names, int size) => [
        for (var i = 0; i + size <= names.length; i += size) names.sublist(i, i + size),
      ];

  /// An eight-entry knockout. [qf]: when, and whether finished (null:
  /// upcoming, false: two done and two on court). [sf]: when, and 'done',
  /// 'live' (one each) or null (upcoming, sides not known yet).
  List<Match> _bracket({
    required String id,
    required String name,
    required String category,
    required String venue,
    required PlayCategory format,
    required List<List<String>> teams,
    required (DateTime, bool?) qf,
    required (DateTime, String?)? sf,
    required DateTime? finalAt,
    bool finalDone = false,
  }) {
    TournamentRef ref(String round) => TournamentRef(id: id, name: name, category: category, round: round);
    rounds[id] = [
      TournamentRound('Quarter-final', knockout: true, startsAt: qf.$1, short: 'QF'),
      TournamentRound('Semi-final', knockout: true, startsAt: sf?.$1, short: 'SF'),
      TournamentRound('Final', knockout: true, startsAt: finalAt, short: 'F'),
    ];
    final out = <Match>[];
    final winners = <List<String>>[];
    for (var i = 0; i < 4; i++) {
      final a = teams[i * 2], b = teams[i * 2 + 1];
      final at = qf.$1.add(Duration(minutes: 50 * (i ~/ 2)));
      final court = 'Court 0${i + 1}';
      if (qf.$2 == null) {
        out.add(_upcoming('$id-qf${i + 1}', a, b, at, venue, format: format, t: ref('Quarter-final'), court: court));
      } else if (qf.$2 == false && i >= 2) {
        out.add(_live('$id-qf${i + 1}', a, b, 12 + i * 9, venue, format: format, t: ref('Quarter-final'), court: court));
      } else {
        final aWins = _r.nextInt(3) != 0;
        out.add(_done('$id-qf${i + 1}', a, b, at, venue, format: format, t: ref('Quarter-final'), aWins: aWins, court: court));
        winners.add(aWins ? a : b);
      }
    }
    if (sf == null) return out;
    final (sfAt, sfState) = sf;
    final finalists = <List<String>>[];
    for (var i = 0; i < 2; i++) {
      final sid = '$id-sf${i + 1}';
      final court = 'Court 0${i + 1}';
      if (winners.length < 4) {
        // Sides fill in as the quarter-finals finish.
        final a = i * 2 < winners.length ? winners[i * 2] : const <String>[];
        final b = i * 2 + 1 < winners.length ? winners[i * 2 + 1] : const <String>[];
        out.add(_upcoming(sid, a, b, sfAt.add(Duration(minutes: 60 * i)), venue,
            format: format, t: ref('Semi-final'), placeholder: b.isEmpty ? 'Winner of QF ${i * 2 + 2}' : null, court: court));
        continue;
      }
      final a = winners[i * 2], b = winners[i * 2 + 1];
      if (sfState == 'live' && i == 1) {
        out.add(_live(sid, a, b, 26, venue, format: format, t: ref('Semi-final'), court: court));
      } else {
        final aWins = _r.nextBool();
        out.add(_done(sid, a, b, sfAt.add(Duration(minutes: 60 * i)), venue,
            format: format, t: ref('Semi-final'), aWins: aWins, court: court));
        finalists.add(aWins ? a : b);
      }
    }
    if (finalAt == null) return out;
    if (finalDone && finalists.length == 2) {
      out.add(_done('$id-f', finalists[0], finalists[1], finalAt, venue, format: format, t: ref('Final'), court: 'Centre Court'));
    } else {
      out.add(_upcoming('$id-f', finalists.isEmpty ? const [] : finalists.first, const [], finalAt, venue,
          format: format, t: ref('Final'), placeholder: 'Winner of SF 2', court: 'Centre Court'));
    }
    return out;
  }
}
