import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sample_latency.dart';
import '../../../core/sample_persona.dart';
import '../../auth/auth_controller.dart';
import '../../matches/data/match_repository.dart' show SampleSeason;
import '../../matches/data/sample_universe.dart' show SampleUniverse, sampleUniverseProvider;
import '../../rating/arc_career.dart';
import 'x_code.dart';

/// Match formats a rating and ranking are kept for.
enum PlayCategory {
  singles('Singles'),
  doubles('Doubles'),
  mixed('Mixed');

  const PlayCategory(this.label);
  final String label;
}

enum RankScope {
  city('City'),
  state('State'),
  country('Country'),
  global('Global');

  const RankScope(this.label);
  final String label;
}

class RatingPoint {
  const RatingPoint(this.date, this.rating);

  final DateTime date;
  final int rating;
}

/// The player's position in one scope and category.
class Ranking {
  const Ranking({
    required this.scope,
    required this.category,
    required this.place,
    required this.rank,
    required this.of,
    required this.change,
  });

  final RankScope scope;
  final PlayCategory category;

  /// "Ahmedabad", "Gujarat", "India", "World".
  final String place;
  final int rank;

  /// Ranked players in this scope.
  final int of;

  /// Places moved since last month: positive is up.
  final int change;
}

enum ActivityKind { matchWon, matchLost, rating, registration, achievement, booking }

class ActivityItem {
  const ActivityItem({required this.kind, required this.title, required this.at, this.detail});

  final ActivityKind kind;
  final String title;
  final String? detail;
  final DateTime at;
}

/// Everything the Home and My Paddle headers need about the player.
class PlayerOverview {
  const PlayerOverview({
    required this.playerId,
    required this.rating,
    required this.ratingChange30d,
    required this.level,
    required this.ratingHistory,
    required this.rankings,
    required this.insights,
    required this.activity,
    this.city,
    this.arc,
  });

  /// Public id shown on the player card, e.g. "SKX-10482".
  final String playerId;

  /// Career SkorX Points (SXP); null until the player has rated matches.
  final int? rating;
  final int ratingChange30d;

  /// The SkorX ARC level ("Kitchen Regular"), or "New player".
  final String level;
  final List<RatingPoint> ratingHistory;
  final List<Ranking> rankings;

  /// One-line observations, strongest first.
  final List<String> insights;
  final List<ActivityItem> activity;
  final String? city;

  /// Power Index, Heat, formats and level progress; null until rated.
  final ArcSummary? arc;

  static PlayerOverview empty(String playerId) => PlayerOverview(
        playerId: playerId,
        rating: null,
        ratingChange30d: 0,
        level: 'New player',
        ratingHistory: const [],
        rankings: const [],
        insights: const [],
        activity: const [],
      );
}

enum AchievementTier { bronze, silver, gold, elite }

class Achievement {
  const Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.tier,
    this.unlockedAt,
    this.progress = 0,
    this.progressLabel,
  });

  final String id;
  final String title;

  /// How to earn it, in one sentence.
  final String description;

  /// Icon key the UI maps to a glyph (trophy, fire, bolt, medal, target, crown…).
  final String icon;
  final AchievementTier tier;
  final DateTime? unlockedAt;

  /// 0–1 towards unlocking; 1 once unlocked.
  final double progress;

  /// "3 / 5 wins".
  final String? progressLabel;

  bool get unlocked => unlockedAt != null;
}

class LeaderboardEntry {
  const LeaderboardEntry({
    required this.rank,
    required this.name,
    required this.city,
    required this.rating,
    required this.change,
    required this.winRate,
    this.isMe = false,
  });

  final int rank;
  final String name;
  final String city;
  final int rating;

  /// Places moved since last week.
  final int change;
  final int winRate;
  final bool isMe;
}

/// Another player as Explore shows them: enough to recognise and size up.
class PlayerSummary {
  const PlayerSummary({
    required this.playerId,
    required this.name,
    required this.city,
    required this.level,
    required this.matches,
    required this.winRate,
    this.rating,
    this.bestFormat,
    this.xCode,
  });

  /// Public id, e.g. "SKX-10482".
  final String playerId;

  /// Their X code ("7K2Q"), the short code players share to be found.
  final String? xCode;
  final String name;
  final String city;
  final String level;

  /// Null until they have rated matches.
  final int? rating;
  final int matches;

  /// 0–100.
  final int winRate;
  final PlayCategory? bestFormat;
}

const playerLevels = ['Beginner', 'Intermediate', 'Advanced', 'Pro'];

enum PlayerSort {
  rating('Top rated'),
  matches('Most active'),
  winRate('Best win rate'),
  name('Name');

  const PlayerSort(this.label);
  final String label;
}

/// How Explore narrows and orders a player search.
class PlayerFilters {
  const PlayerFilters({
    this.city,
    this.levels = const {},
    this.formats = const {},
    this.minRating,
    this.sort = PlayerSort.rating,
  });

  /// Null: anywhere.
  final String? city;
  final Set<String> levels;

  /// Matched against the player's best format.
  final Set<PlayCategory> formats;
  final int? minRating;
  final PlayerSort sort;

  /// How many filters beyond sort are on, for the filter button badge.
  int get activeCount => (city != null ? 1 : 0) + levels.length + formats.length + (minRating != null ? 1 : 0);

  PlayerFilters copyWith({
    String? Function()? city,
    Set<String>? levels,
    Set<PlayCategory>? formats,
    int? Function()? minRating,
    PlayerSort? sort,
  }) =>
      PlayerFilters(
        city: city == null ? this.city : city(),
        levels: levels ?? this.levels,
        formats: formats ?? this.formats,
        minRating: minRating == null ? this.minRating : minRating(),
        sort: sort ?? this.sort,
      );

  PlayerFilters cleared() => PlayerFilters(sort: sort);

  bool matches(PlayerSummary p) {
    if (city != null && p.city != city) return false;
    if (levels.isNotEmpty && !levels.contains(p.level)) return false;
    if (formats.isNotEmpty && !formats.contains(p.bestFormat)) return false;
    if (minRating != null && (p.rating ?? 0) < minRating!) return false;
    return true;
  }

  int compare(PlayerSummary a, PlayerSummary b) => switch (sort) {
        PlayerSort.rating => (b.rating ?? 0).compareTo(a.rating ?? 0),
        PlayerSort.matches => b.matches.compareTo(a.matches),
        PlayerSort.winRate => b.winRate.compareTo(a.winRate),
        PlayerSort.name => a.name.compareTo(b.name),
      };
}

class PlayerFiltersController extends Notifier<PlayerFilters> {
  @override
  PlayerFilters build() => const PlayerFilters();

  void update(PlayerFilters Function(PlayerFilters) change) => state = change(state);
}

typedef LeaderboardQuery = ({RankScope scope, PlayCategory category, String gender, String age});

/// Player performance data. Method names mirror the endpoints they will
/// call; none exist in the new API yet (docs/PLAYER-APP.md §2).
abstract class PlayerRepository {
  /// `GET /me/player/overview`
  Future<PlayerOverview> overview();

  /// `GET /me/achievements`
  Future<List<Achievement>> achievements();

  /// `GET /rankings?scope&category&gender&age`
  Future<List<LeaderboardEntry>> leaderboard(LeaderboardQuery query);

  /// `GET /players?q` — by name, player id, X code or city. A query that is an
  /// X code returns just that player. Empty query: everyone, top rated first.
  Future<List<PlayerSummary>> searchPlayers(String query);
}

final playerRepositoryProvider = Provider<PlayerRepository>((ref) {
  final name = ref.watch(currentUserProvider.select((u) => u?.name)) ?? '';
  if (!kDebugMode || ref.watch(samplePersonaProvider) == SamplePersona.newcomer) return const EmptyPlayerRepository();
  return SamplePlayerRepository(name, latency: ref.watch(sampleLatencyProvider), season: ref.watch(sampleUniverseProvider).season);
});

final playerOverviewProvider =
    FutureProvider<PlayerOverview>((ref) => ref.watch(playerRepositoryProvider).overview());

final achievementsProvider =
    FutureProvider<List<Achievement>>((ref) => ref.watch(playerRepositoryProvider).achievements());

final playerSearchProvider = FutureProvider.autoDispose.family<List<PlayerSummary>, String>(
  (ref, query) => ref.watch(playerRepositoryProvider).searchPlayers(query),
);

final playerFiltersProvider = NotifierProvider<PlayerFiltersController, PlayerFilters>(PlayerFiltersController.new);

/// Search results with Explore's player filters and sort applied. An X code
/// finds its one player whatever the filters say.
final filteredPlayersProvider = Provider.autoDispose.family<AsyncValue<List<PlayerSummary>>, String>((ref, query) {
  if (XCode.parse(query) != null) return ref.watch(playerSearchProvider(query));
  final filters = ref.watch(playerFiltersProvider);
  return ref.watch(playerSearchProvider(query)).whenData((all) => all.where(filters.matches).toList()..sort(filters.compare));
});

final leaderboardProvider = FutureProvider.family<List<LeaderboardEntry>, LeaderboardQuery>(
  (ref, query) => ref.watch(playerRepositoryProvider).leaderboard(query),
);

/// Release builds until the endpoints exist: honest empty states.
class EmptyPlayerRepository implements PlayerRepository {
  const EmptyPlayerRepository();

  @override
  Future<PlayerOverview> overview() async => PlayerOverview.empty('—');

  @override
  Future<List<Achievement>> achievements() async => _catalogue(DateTime.now(), unlockedCount: 0);

  @override
  Future<List<LeaderboardEntry>> leaderboard(LeaderboardQuery query) async => const [];

  @override
  Future<List<PlayerSummary>> searchPlayers(String query) async => const [];
}

/// Debug builds: realistic data to design and test against.
class SamplePlayerRepository implements PlayerRepository {
  SamplePlayerRepository(this.name, {this.latency = const Duration(milliseconds: 350), SampleSeason? season})
      : _season = season;

  final String name;
  final Duration latency;

  /// The season the rating is worked out from, so the header agrees with
  /// every match's change.
  final SampleSeason? _season;

  @override
  Future<PlayerOverview> overview() async {
    await simulateLatency(latency);
    final now = DateTime.now();
    final season = _season ?? SampleSeason(now);
    final mine = season.matches.where((m) => m.involvesMe && m.isCompleted && m.ratingAfter != null).toList()
      ..sort((a, b) => a.playedAt.compareTo(b.playedAt));
    final arc = ArcSummary.fromMatches(mine)!;
    final history = [
      RatingPoint(mine.first.playedAt.subtract(const Duration(days: 1)), mine.first.ratingBefore!),
      for (final m in mine) RatingPoint(m.playedAt, m.ratingAfter!),
    ];
    final monthAgo = history.lastWhere((p) => p.date.isBefore(now.subtract(const Duration(days: 30))),
        orElse: () => history.first);
    final last = mine.last;
    return PlayerOverview(
      playerId: 'SKX-10482',
      rating: arc.points,
      ratingChange30d: arc.points - monthAgo.rating,
      level: arc.level.name,
      city: 'Ahmedabad',
      arc: arc,
      ratingHistory: history,
      rankings: const [
        Ranking(scope: RankScope.city, category: PlayCategory.doubles, place: 'Ahmedabad', rank: 14, of: 612, change: 3),
        Ranking(scope: RankScope.state, category: PlayCategory.doubles, place: 'Gujarat', rank: 58, of: 2140, change: 6),
        Ranking(scope: RankScope.country, category: PlayCategory.doubles, place: 'India', rank: 412, of: 18400, change: 21),
        Ranking(scope: RankScope.global, category: PlayCategory.doubles, place: 'World', rank: 3981, of: 96000, change: 140),
        Ranking(scope: RankScope.city, category: PlayCategory.singles, place: 'Ahmedabad', rank: 22, of: 540, change: -2),
        Ranking(scope: RankScope.state, category: PlayCategory.singles, place: 'Gujarat', rank: 91, of: 1880, change: 4),
        Ranking(scope: RankScope.country, category: PlayCategory.singles, place: 'India', rank: 688, of: 16200, change: 12),
        Ranking(scope: RankScope.global, category: PlayCategory.singles, place: 'World', rank: 6120, of: 88000, change: 95),
        Ranking(scope: RankScope.city, category: PlayCategory.mixed, place: 'Ahmedabad', rank: 9, of: 380, change: 5),
        Ranking(scope: RankScope.state, category: PlayCategory.mixed, place: 'Gujarat', rank: 37, of: 1320, change: 8),
        Ranking(scope: RankScope.country, category: PlayCategory.mixed, place: 'India', rank: 301, of: 11700, change: 30),
        Ranking(scope: RankScope.global, category: PlayCategory.mixed, place: 'World', rank: 2870, of: 64000, change: 210),
      ],
      insights: [
        'You earned ${arc.points - monthAgo.rating} SkorX Points in the last 30 days.',
        'Your strongest format is mixed doubles: 75% wins.',
        'You win 80% of matches that go to a deciding game.',
      ],
      activity: [
        ActivityItem(
          kind: ActivityKind.matchWon,
          title: 'Won vs Anand & Hardik',
          detail: '11–7 · 9–11 · 11–9',
          at: now.subtract(const Duration(days: 1, hours: 2)),
        ),
        ActivityItem(
          kind: ActivityKind.rating,
          title: 'SkorX Points up to ${arc.points}',
          detail: '+${last.ratingChange} after your last match',
          at: now.subtract(const Duration(days: 1, hours: 2)),
        ),
        ActivityItem(
          kind: ActivityKind.achievement,
          title: 'Unlocked Hot Streak',
          detail: '3 wins in a row',
          at: now.subtract(const Duration(days: 3)),
        ),
        ActivityItem(
          kind: ActivityKind.registration,
          title: 'Registered for SkorX Open 2026',
          detail: "Mixed Doubles · Intermediate",
          at: now.subtract(const Duration(days: 4)),
        ),
        ActivityItem(
          kind: ActivityKind.booking,
          title: 'Booked Pickle Blitz Arena',
          detail: 'Court 2 · Sat 7 AM',
          at: now.subtract(const Duration(days: 6)),
        ),
      ],
    );
  }

  @override
  Future<List<Achievement>> achievements() async {
    await simulateLatency(latency);
    return _catalogue(DateTime.now(), unlockedCount: 6);
  }

  @override
  Future<List<LeaderboardEntry>> leaderboard(LeaderboardQuery query) async {
    await simulateLatency(latency);
    const names = [
      ('Aarav Shah', 'Ahmedabad'),
      ('Ishaan Patel', 'Surat'),
      ('Kavya Mehta', 'Ahmedabad'),
      ('Rohan Desai', 'Vadodara'),
      ('Diya Joshi', 'Ahmedabad'),
      ('Arjun Trivedi', 'Rajkot'),
      ('Meera Iyer', 'Ahmedabad'),
      ('Kabir Rao', 'Gandhinagar'),
      ('Anaya Nair', 'Surat'),
      ('Vivaan Gupta', 'Ahmedabad'),
      ('Sara Khan', 'Vadodara'),
      ('Dev Patel', 'Ahmedabad'),
      ('Riya Shah', 'Ahmedabad'),
      ('Hardik Suthar', 'Ahmedabad'),
    ];
    final base = switch (query.scope) {
      RankScope.city => 1420,
      RankScope.state => 1510,
      RankScope.country => 1690,
      RankScope.global => 1905,
    };
    final entries = <LeaderboardEntry>[
      for (final (i, (n, city)) in names.indexed)
        LeaderboardEntry(
          rank: i + 1,
          name: n,
          city: city,
          rating: SampleUniverse.sxpFromLegacy(base - i * 13 - (query.category.index * 7)),
          change: const [0, 1, -1, 2, 0, 3, -2, 1, 0, -1, 4, 0, 1, -3][i],
          winRate: 78 - i,
        ),
    ];
    final mine = switch (query.scope) {
      RankScope.city => 14 + query.category.index * 3,
      RankScope.state => 58,
      RankScope.country => 412,
      RankScope.global => 3981,
    };
    entries.add(LeaderboardEntry(
      rank: mine,
      name: name.isEmpty ? 'You' : name,
      city: 'Ahmedabad',
      rating: _season?.currentRating ?? 0,
      change: 3,
      winRate: 67,
      isMe: true,
    ));
    return entries;
  }

  @override
  Future<List<PlayerSummary>> searchPlayers(String query) async {
    await simulateLatency(latency);
    const people = [
      ('SKX-10021', 'A7SH', 'Aarav Shah', 'Ahmedabad', 1420, 'Advanced', 142, 78, PlayCategory.doubles),
      ('SKX-10388', 'M3KV', 'Kavya Mehta', 'Ahmedabad', 1394, 'Advanced', 118, 76, PlayCategory.mixed),
      ('SKX-10412', 'J3DY', 'Diya Joshi', 'Ahmedabad', 1368, 'Advanced', 96, 74, PlayCategory.singles),
      ('SKX-10477', 'Q7MY', 'Meera Iyer', 'Ahmedabad', 1342, 'Intermediate', 88, 72, PlayCategory.doubles),
      ('SKX-10503', 'G5VP', 'Vivaan Gupta', 'Ahmedabad', 1303, 'Intermediate', 71, 69, PlayCategory.doubles),
      ('SKX-10519', 'R2SH', 'Riya Shah', 'Ahmedabad', 1277, 'Intermediate', 64, 66, PlayCategory.mixed),
      ('SKX-10544', 'H9ST', 'Hardik Suthar', 'Ahmedabad', 1231, 'Intermediate', 52, 61, PlayCategory.doubles),
      ('SKX-10560', '7AVE', 'Anand Verma', 'Ahmedabad', 1188, 'Intermediate', 47, 55, PlayCategory.singles),
      ('SKX-10233', '3PQE', 'Ishaan Patel', 'Surat', 1407, 'Advanced', 130, 77, PlayCategory.singles),
      ('SKX-10291', 'R8DZ', 'Rohan Desai', 'Vadodara', 1381, 'Advanced', 104, 75, PlayCategory.doubles),
      ('SKX-10302', '5TJW', 'Arjun Trivedi', 'Rajkot', 1355, 'Intermediate', 93, 73, PlayCategory.doubles),
      ('SKX-10355', 'K2BR', 'Kabir Rao', 'Gandhinagar', 1329, 'Intermediate', 80, 71, PlayCategory.mixed),
      ('SKX-10366', 'N6AY', 'Anaya Nair', 'Surat', 1316, 'Intermediate', 77, 70, PlayCategory.mixed),
      ('SKX-10590', 'S3KZ', 'Sara Khan', 'Vadodara', 1290, 'Intermediate', 69, 68, PlayCategory.singles),
      ('SKX-10611', 'D8PT', 'Dev Patel', 'Ahmedabad', 1264, 'Intermediate', 58, 67, PlayCategory.doubles),
      ('SKX-10702', 'N4KP', 'Nisha Kapoor', 'Ahmedabad', null, 'Beginner', 3, 33, null),
      ('SKX-10009', '9VKR', 'Vikram Singh', 'Mumbai', 1612, 'Pro', 310, 84, PlayCategory.singles),
      ('SKX-10014', 'T4MN', 'Tara Menon', 'Mumbai', 1588, 'Pro', 276, 82, PlayCategory.mixed),
      ('SKX-10718', 'P5BT', 'Parth Bhatt', 'Gandhinagar', 1096, 'Beginner', 14, 43, PlayCategory.doubles),
      ('SKX-10731', 'Z7QU', 'Zoya Qureshi', 'Surat', 1122, 'Beginner', 19, 47, PlayCategory.mixed),
    ];
    final code = XCode.parse(query);
    final q = query.trim().toLowerCase();
    return [
      for (final (id, xCode, n, city, rating, level, matches, winRate, best) in people)
        if (code != null ? xCode == code : q.isEmpty || '$n $id $city'.toLowerCase().contains(q))
          PlayerSummary(
            playerId: id,
            xCode: xCode,
            name: n,
            city: city,
            rating: rating == null ? null : SampleUniverse.sxpFromLegacy(rating),
            level: level,
            matches: matches,
            winRate: winRate,
            bestFormat: best,
          ),
    ];
  }
}

List<Achievement> _catalogue(DateTime now, {required int unlockedCount}) {
  const all = [
    ('first-match', 'First Serve', 'Play your first match on SkorX.', 'ball', AchievementTier.bronze, 1, 1),
    ('first-win', 'First Victory', 'Win your first match.', 'trophy', AchievementTier.bronze, 1, 1),
    ('first-tournament', 'Tournament Debut', 'Play in your first tournament.', 'medal', AchievementTier.silver, 1, 1),
    ('streak-3', 'Hot Streak', 'Win 3 matches in a row.', 'fire', AchievementTier.silver, 3, 3),
    ('rating-1200', 'Rising Star', 'Reach a 1200 rating.', 'target', AchievementTier.silver, 1200, 1200),
    ('matches-25', 'Regular', 'Play 25 matches.', 'bolt', AchievementTier.bronze, 25, 25),
    ('streak-5', 'On Fire', 'Win 5 matches in a row.', 'fire', AchievementTier.gold, 3, 5),
    ('matches-100', 'Century', 'Play 100 matches.', 'bolt', AchievementTier.gold, 41, 100),
    ('rating-1500', 'Elite 1500', 'Reach a 1500 rating.', 'target', AchievementTier.gold, 1248, 1500),
    ('tournament-win', 'Champion', 'Win a tournament category.', 'crown', AchievementTier.gold, 0, 1),
    ('top-100', 'Top 100', 'Reach the top 100 in your country.', 'rank', AchievementTier.elite, 0, 1),
    ('bagel', 'Bagel', 'Win a game 11–0.', 'star', AchievementTier.silver, 0, 1),
  ];
  return [
    for (final (i, (id, title, description, icon, tier, have, need)) in all.indexed)
      Achievement(
        id: id,
        title: title,
        description: description,
        icon: icon,
        tier: tier,
        unlockedAt: i < unlockedCount ? now.subtract(Duration(days: 60 - i * 9)) : null,
        progress: i < unlockedCount ? 1 : (unlockedCount == 0 ? 0 : (have / need).clamp(0, 0.99).toDouble()),
        progressLabel: i < unlockedCount || unlockedCount == 0 ? null : '$have / $need',
      ),
  ];
}
