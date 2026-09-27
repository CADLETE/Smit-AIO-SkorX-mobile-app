import '../../player/data/player_repository.dart' show PlayCategory;
import '../../casual_match/verification/verification.dart' show MatchLifecycle;
import '../../rating/arc_engine.dart' show ArcImpact;

/// The core record of SkorX. Tournaments contain matches; a player's record,
/// rating and journey are all worked out from matches (docs/PLAYER-APP.md §2).
enum MatchStatus { live, upcoming, completed, cancelled }

enum MatchKind {
  tournament('Tournament'),
  league('League'),
  friendly('Friendly');

  const MatchKind(this.label);
  final String label;
}

/// Casual play or a tournament: the split My Paddle and the Matches filters
/// use. League matches belong to a tournament, so they count as tournament.
enum MatchCategory {
  casual('Casual'),
  tournament('Tournament');

  const MatchCategory(this.label);
  final String label;
}

/// Where a match is played, so matches can be found by place across SkorX.
class MatchPlace {
  const MatchPlace({required this.city, this.region, this.country = 'India'});

  final String city;

  /// State or province; null where there is none (Singapore).
  final String? region;
  final String country;

  /// "Ahmedabad, Gujarat" / "Singapore".
  String get label => [city, if (region != null && region != city) region!].join(', ');
}

/// Where a match sits in a tournament.
class TournamentRef {
  const TournamentRef({required this.id, required this.name, required this.category, required this.round, this.pool});

  final String id;
  final String name;

  /// "Men's Doubles · Intermediate".
  final String category;

  /// "Quarter-final", "Pool A · Match 2".
  final String round;

  /// "Pool A", for pool matches.
  final String? pool;
}

/// A match being streamed, as viewers see it: only the public video. The
/// scorer's stream key never leaves their phone and the API.
class LiveBroadcast {
  const LiveBroadcast({required this.videoId, this.title, this.channel});

  /// The YouTube video id of the live broadcast, as in `youtube.com/watch?v=<id>`.
  final String videoId;
  final String? title;

  /// Who is streaming it, e.g. "SkorX Ahmedabad".
  final String? channel;
}

/// The game being played right now.
class LiveGame {
  const LiveGame({required this.number, required this.mine, required this.theirs, this.myServe});

  /// 1-based game number.
  final int number;
  final int mine;
  final int theirs;

  /// Whether the player's side is serving, when known.
  final bool? myServe;
}

/// A match seen from one player's side of the net: [mine] is the player's
/// side (the player first), and every score is (mine, theirs). A match the
/// player is not in ([involvesMe] false) keeps side A in [mine].
class Match {
  const Match({
    required this.id,
    required this.status,
    required this.kind,
    required this.format,
    required this.mine,
    required this.theirs,
    required this.scheduledAt,
    this.games = const [],
    this.live,
    this.involvesMe = true,
    this.tournament,
    this.venue,
    this.court,
    this.startedAt,
    this.completedAt,
    this.pointsBefore,
    this.pointsEarned,
    this.arc,
    this.pointsToWin = 11,
    this.bestOf = 3,
    this.theirsPlaceholder,
    this.cancelReason,
    this.place,
    this.broadcast,
    this.wonByDefault,
    this.verification,
  });

  final String id;
  final MatchStatus status;
  final MatchKind kind;
  final PlayCategory format;
  final List<String> mine;

  /// Empty until the opponent is known; see [theirsPlaceholder].
  final List<String> theirs;
  final DateTime scheduledAt;

  /// Finished games, (mine, theirs).
  final List<(int, int)> games;
  final LiveGame? live;
  final bool involvesMe;
  final TournamentRef? tournament;
  final String? venue;

  /// "Court 03".
  final String? court;
  final DateTime? startedAt;
  final DateTime? completedAt;

  /// SkorX Points before this match and earned by it, once the match is
  /// rated, as shown: 2 decimals.
  final double? pointsBefore;
  final double? pointsEarned;

  /// What the match did to the player's SkorX Rating and SkorX Points, with
  /// the full breakdown. [pointsBefore] and [pointsEarned] are its SXP,
  /// rounded to 2 decimals so the changes add up to the header.
  final ArcImpact? arc;
  final int pointsToWin;
  final int bestOf;

  /// "Winner of QF 2", while [theirs] is unknown.
  final String? theirsPlaceholder;
  final String? cancelReason;

  /// City, state and country, once known.
  final MatchPlace? place;

  /// The match on video, for people watching, while it is being streamed.
  final LiveBroadcast? broadcast;

  /// Set when the match was decided by walkover or retirement rather than
  /// on the scoreboard: whether [mine] was given it.
  final bool? wonByDefault;

  /// Casual matches scored in the app: where player verification stands.
  /// Null for tournament matches (verified by their organizer) and for
  /// matches SkorX already counts.
  final MatchLifecycle? verification;

  /// Whether the match may count toward stats, rating, rankings and
  /// achievements: never while its players have not all confirmed it.
  bool get isOfficial => verification == null || verification!.official;

  MatchCategory get category => tournament == null ? MatchCategory.casual : MatchCategory.tournament;

  bool get isLive => status == MatchStatus.live;
  bool get isUpcoming => status == MatchStatus.upcoming;
  bool get isCompleted => status == MatchStatus.completed;
  bool get isCancelled => status == MatchStatus.cancelled;

  int get gamesWon => games.where((g) => g.$1 > g.$2).length;
  int get gamesLost => games.where((g) => g.$2 > g.$1).length;

  /// Only meaningful once [isCompleted].
  bool get won => wonByDefault ?? gamesWon > gamesLost;

  double? get pointsAfter => pointsBefore == null || pointsEarned == null
      ? null
      : ((pointsBefore! * 100).round() + (pointsEarned! * 100).round()) / 100;

  bool get opponentKnown => theirs.isNotEmpty;

  /// When the result counts: completion time, else the scheduled time.
  DateTime get playedAt => completedAt ?? scheduledAt;

  Duration? get duration =>
      startedAt != null && completedAt != null ? completedAt!.difference(startedAt!) : null;

  /// "Quarter-final" / "Friendly" / "League".
  String get stageLabel => tournament?.round ?? kind.label;

  /// "SkorX Open" or "Friendly · Pickle Blitz Arena".
  String get contextLabel => tournament?.name ?? [kind.label, ?venue].join(' · ');

  int get pointsWon => games.fold(0, (s, g) => s + g.$1);
  int get pointsLost => games.fold(0, (s, g) => s + g.$2);

  /// Whether [name] plays in this match ("You" is the signed-in player).
  bool hasPlayer(String name) => mine.contains(name) || theirs.contains(name);

  /// Every player on court, both sides.
  Iterable<String> get players => [...mine, ...theirs];

  /// The same match from [name]'s side of the net, or null when they did not
  /// play in it. The result, form and rows then read as theirs; the rating
  /// change is kept only when it is the signed-in player's own match.
  Match? seenBy(String name) {
    if (mine.contains(name)) {
      if (involvesMe && name == 'You') return this;
      return _copy(involvesMe: true, keepRating: false);
    }
    if (!theirs.contains(name)) return null;
    return _copy(
      mine: theirs,
      theirs: mine,
      games: [for (final g in games) (g.$2, g.$1)],
      live: live == null
          ? null
          : LiveGame(
              number: live!.number,
              mine: live!.theirs,
              theirs: live!.mine,
              myServe: live!.myServe == null ? null : !live!.myServe!,
            ),
      involvesMe: true,
      wonByDefault: wonByDefault == null ? null : !wonByDefault!,
      keepRating: false,
    );
  }

  /// This match with its place filled in.
  Match placedIn(MatchPlace place) => _copy(place: place, keepRating: true);

  Match _copy({
    List<String>? mine,
    List<String>? theirs,
    List<(int, int)>? games,
    LiveGame? live,
    bool? involvesMe,
    MatchPlace? place,
    bool? wonByDefault,
    required bool keepRating,
  }) =>
      Match(
        id: id,
        status: status,
        kind: kind,
        format: format,
        mine: mine ?? this.mine,
        theirs: theirs ?? this.theirs,
        scheduledAt: scheduledAt,
        games: games ?? this.games,
        live: games == null ? this.live : live,
        involvesMe: involvesMe ?? this.involvesMe,
        tournament: tournament,
        venue: venue,
        court: court,
        startedAt: startedAt,
        completedAt: completedAt,
        pointsBefore: keepRating ? pointsBefore : null,
        pointsEarned: keepRating ? pointsEarned : null,
        arc: keepRating ? arc : null,
        pointsToWin: pointsToWin,
        bestOf: bestOf,
        theirsPlaceholder: theirsPlaceholder,
        cancelReason: cancelReason,
        place: place ?? this.place,
        broadcast: broadcast,
        wonByDefault: wonByDefault ?? this.wonByDefault,
        verification: verification,
      );
}

/// A player's name as it fits a match row: "You", "Kamal P.".
String shortName(String name) {
  if (name == 'You') return name;
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length < 2) return name;
  return '${parts.first} ${parts.last[0]}.';
}

/// "You & Kamal" / "Rahul & Jay" / "Vivek Rana".
String sideLabel(List<String> names) {
  if (names.isEmpty) return 'TBD';
  if (names.length == 1) return names.first;
  return names.map((n) => n == 'You' ? n : n.split(' ').first).join(' & ');
}

/// What the player's matches add up to. Worked out here and nowhere else.
class PlayerRecord {
  PlayerRecord(Iterable<Match> matches)
      : finished = [
          for (final m in matches)
            // Pending, disputed or rejected casual matches never count.
            if (m.isCompleted && m.involvesMe && m.isOfficial) m,
        ]..sort((a, b) => b.playedAt.compareTo(a.playedAt));

  /// Newest first.
  final List<Match> finished;

  int get played => finished.length;
  int get wins => finished.where((m) => m.won).length;
  int get losses => played - wins;

  /// 0–100, or null before the first match.
  int? get winRate => played == 0 ? null : (wins * 100 / played).round();

  int get winStreak {
    var streak = 0;
    for (final m in finished) {
      if (!m.won) break;
      streak++;
    }
    return streak;
  }

  int get bestWinStreak {
    var best = 0;
    var run = 0;
    for (final m in finished.reversed) {
      run = m.won ? run + 1 : 0;
      if (run > best) best = run;
    }
    return best;
  }

  /// Last results, newest first: true for a win.
  List<bool> form([int n = 5]) => [for (final m in finished.take(n)) m.won];

  int get pointsWon => finished.fold(0, (s, m) => s + m.pointsWon);
  int get pointsLost => finished.fold(0, (s, m) => s + m.pointsLost);

  int get tournamentsPlayed => {for (final m in finished) ?m.tournament?.id}.length;

  /// The format played most, which rankings are shown for. Doubles until
  /// there is a record.
  PlayCategory get preferredFormat {
    if (finished.isEmpty) return PlayCategory.doubles;
    final counts = <PlayCategory, int>{};
    for (final m in finished) {
      counts[m.format] = (counts[m.format] ?? 0) + 1;
    }
    return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  }
}
