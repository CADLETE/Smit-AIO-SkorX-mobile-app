import '../../../sports/core/match_rules.dart';
import '../../../sports/core/score_state.dart';
import '../../player/data/player_repository.dart' show PlayCategory;

/// The tournament's place in its life cycle. Every screen asks
/// [TournamentLifecycle] what is allowed; nothing checks a status by hand.
/// Mirrors `TournamentStatus` in the API (docs/ORGANIZER-TMS.md §4).
enum TournamentStatus {
  draft('Draft'),
  registrationOpen('Registration open'),
  registrationClosed('Registration closed'),
  drawGenerated('Draw ready'),
  scheduled('Scheduled'),
  live('Live'),
  completed('Completed'),
  cancelled('Cancelled'),
  archived('Archived');

  const TournamentStatus(this.label);
  final String label;

  bool get isActive => index >= registrationOpen.index && index <= live.index;
  bool get isFinished => this == completed || this == cancelled || this == archived;
}

/// What an organiser can do to a tournament.
enum TmsAction {
  editDetails,
  editCategories,
  openRegistration,
  closeRegistration,
  manageEntries,
  checkIn,
  generateDraw,
  publishDraw,
  generateSchedule,
  manageCourts,
  startTournament,
  scoreMatches,
  completeTournament,
  correctResults,
  announce,
  cancel,
  archive,
  duplicate,
}

/// Which actions each status allows, and where each action leads. The API
/// applies the same table; the app uses it to hide what would be refused.
abstract final class TournamentLifecycle {
  static const _allowed = <TournamentStatus, Set<TmsAction>>{
    TournamentStatus.draft: {
      TmsAction.editDetails,
      TmsAction.editCategories,
      TmsAction.openRegistration,
      TmsAction.cancel,
      TmsAction.duplicate,
    },
    TournamentStatus.registrationOpen: {
      TmsAction.editDetails,
      TmsAction.editCategories,
      TmsAction.closeRegistration,
      TmsAction.manageEntries,
      TmsAction.announce,
      TmsAction.cancel,
      TmsAction.duplicate,
    },
    TournamentStatus.registrationClosed: {
      TmsAction.editDetails,
      TmsAction.openRegistration,
      TmsAction.manageEntries,
      TmsAction.checkIn,
      TmsAction.generateDraw,
      TmsAction.announce,
      TmsAction.cancel,
      TmsAction.duplicate,
    },
    TournamentStatus.drawGenerated: {
      TmsAction.editDetails,
      TmsAction.manageEntries,
      TmsAction.checkIn,
      TmsAction.generateDraw,
      TmsAction.publishDraw,
      TmsAction.generateSchedule,
      TmsAction.announce,
      TmsAction.cancel,
      TmsAction.duplicate,
    },
    TournamentStatus.scheduled: {
      TmsAction.editDetails,
      TmsAction.manageEntries,
      TmsAction.checkIn,
      TmsAction.publishDraw,
      TmsAction.generateSchedule,
      TmsAction.manageCourts,
      TmsAction.startTournament,
      TmsAction.announce,
      TmsAction.cancel,
      TmsAction.duplicate,
    },
    // Structure is frozen once play starts: no draw or entry changes.
    TournamentStatus.live: {
      TmsAction.checkIn,
      TmsAction.manageCourts,
      TmsAction.scoreMatches,
      TmsAction.completeTournament,
      TmsAction.announce,
      TmsAction.cancel,
      TmsAction.duplicate,
    },
    // Results are locked; correcting one needs the override capability.
    TournamentStatus.completed: {
      TmsAction.correctResults,
      TmsAction.announce,
      TmsAction.archive,
      TmsAction.duplicate,
    },
    TournamentStatus.cancelled: {TmsAction.archive, TmsAction.duplicate},
    TournamentStatus.archived: {TmsAction.duplicate},
  };

  static bool allows(TournamentStatus status, TmsAction action) => _allowed[status]!.contains(action);

  /// The status after [action], or null when the action does not move the
  /// tournament (or is not allowed from [from]).
  static TournamentStatus? after(TournamentStatus from, TmsAction action) {
    if (!allows(from, action)) return null;
    return switch (action) {
      TmsAction.openRegistration => TournamentStatus.registrationOpen,
      TmsAction.closeRegistration => TournamentStatus.registrationClosed,
      TmsAction.generateDraw => TournamentStatus.drawGenerated,
      TmsAction.generateSchedule => TournamentStatus.scheduled,
      TmsAction.startTournament => TournamentStatus.live,
      TmsAction.completeTournament => TournamentStatus.completed,
      TmsAction.cancel => TournamentStatus.cancelled,
      TmsAction.archive => TournamentStatus.archived,
      _ => null,
    };
  }

  /// A caution to show before [action], when it has consequences players
  /// will notice. Null when the action is routine.
  static String? warning(TournamentStatus status, TmsAction action) => switch ((status, action)) {
        (TournamentStatus.drawGenerated || TournamentStatus.scheduled, TmsAction.manageEntries) =>
          'The draw is already made. Adding or removing players means generating it again.',
        (TournamentStatus.drawGenerated, TmsAction.generateDraw) =>
          'This replaces the current draw, including any swaps you made.',
        (TournamentStatus.scheduled, TmsAction.generateSchedule) =>
          'Players will get new match times. Matches already called keep their court.',
        _ => null,
      };

  /// The one thing to do next, shown as the hub's primary button.
  static TmsAction? nextStep(TournamentStatus status) => switch (status) {
        TournamentStatus.draft => TmsAction.openRegistration,
        TournamentStatus.registrationOpen => TmsAction.closeRegistration,
        TournamentStatus.registrationClosed => TmsAction.generateDraw,
        TournamentStatus.drawGenerated => TmsAction.generateSchedule,
        TournamentStatus.scheduled => TmsAction.startTournament,
        TournamentStatus.live => TmsAction.scoreMatches,
        _ => null,
      };
}

/// How a category's draw is played.
enum DrawFormat {
  knockout('Knockout'),
  roundRobin('Round robin'),
  pools('Pool play');

  const DrawFormat(this.label);
  final String label;
}

/// How players are placed in a generated draw.
enum DrawMethod {
  seeded('Seeded'),
  random('Random');

  const DrawMethod(this.label);
  final String label;
}

/// One event inside a tournament, e.g. "Men's Doubles · Intermediate".
class OrgCategory {
  const OrgCategory({
    required this.id,
    required this.name,
    required this.format,
    required this.level,
    required this.drawFormat,
    required this.fee,
    required this.capacity,
    required this.rules,
  });

  final String id;
  final String name;
  final PlayCategory format;
  final String level;
  final DrawFormat drawFormat;

  /// Entry fee per entry (a player, or a pair in doubles), in rupees.
  final int fee;

  /// Maximum entries. Extra registrations go to the waitlist.
  final int capacity;
  final MatchRules rules;

  String get title => '$name · $level';
  int get playersPerSide => format == PlayCategory.singles ? 1 : 2;

  OrgCategory copyWith({String? id}) => OrgCategory(
        id: id ?? this.id,
        name: name,
        format: format,
        level: level,
        drawFormat: drawFormat,
        fee: fee,
        capacity: capacity,
        rules: rules,
      );
}

class OrgTournament {
  const OrgTournament({
    required this.id,
    required this.organizationId,
    required this.name,
    required this.status,
    required this.venue,
    required this.city,
    required this.start,
    required this.end,
    required this.registrationOpens,
    required this.registrationCloses,
    required this.categories,
    this.description = '',
    this.indoor = true,
    this.checkInOpen = false,
    this.publishedDraws = const {},
    this.liveScoring = true,
    this.streaming = false,
    this.waitlist = true,
    this.earlyBirdDiscount = 0,
  });

  final String id;
  final String organizationId;
  final String name;
  final String description;
  final TournamentStatus status;
  final String venue;
  final String city;
  final bool indoor;
  final DateTime start;
  final DateTime end;
  final DateTime registrationOpens;
  final DateTime registrationCloses;
  final List<OrgCategory> categories;
  final bool checkInOpen;

  /// Categories whose draw players can see.
  final Set<String> publishedDraws;
  final bool liveScoring;
  final bool streaming;
  final bool waitlist;

  /// Rupees off each entry before [registrationCloses] minus a week.
  final int earlyBirdDiscount;

  OrgCategory? category(String id) => categories.where((c) => c.id == id).firstOrNull;

  bool can(TmsAction action) => TournamentLifecycle.allows(status, action);

  OrgTournament copyWith({
    TournamentStatus? status,
    bool? checkInOpen,
    Set<String>? publishedDraws,
    String? id,
    String? name,
    DateTime? start,
    DateTime? end,
    DateTime? registrationOpens,
    DateTime? registrationCloses,
    List<OrgCategory>? categories,
  }) =>
      OrgTournament(
        id: id ?? this.id,
        organizationId: organizationId,
        name: name ?? this.name,
        description: description,
        status: status ?? this.status,
        venue: venue,
        city: city,
        indoor: indoor,
        start: start ?? this.start,
        end: end ?? this.end,
        registrationOpens: registrationOpens ?? this.registrationOpens,
        registrationCloses: registrationCloses ?? this.registrationCloses,
        categories: categories ?? this.categories,
        checkInOpen: checkInOpen ?? this.checkInOpen,
        publishedDraws: publishedDraws ?? this.publishedDraws,
        liveScoring: liveScoring,
        streaming: streaming,
        waitlist: waitlist,
        earlyBirdDiscount: earlyBirdDiscount,
      );
}

/// A SkorX player as the organiser sees them. It is a reference to the
/// player's own profile, never a copy the organiser can edit.
class PlayerRef {
  const PlayerRef({required this.id, required this.name, this.rating, this.city});

  final String id;
  final String name;

  /// SkorX Rating (0–100), which seeding uses; null until the player has
  /// rated matches.
  final double? rating;
  final String? city;
}

enum Approval {
  pending('Pending'),
  approved('Approved'),
  waitlisted('Waitlist'),
  rejected('Rejected');

  const Approval(this.label);
  final String label;
}

enum PaymentState {
  paid('Paid'),
  pending('Unpaid'),
  refunded('Refunded'),
  waived('Waived');

  const PaymentState(this.label);
  final String label;
}

enum Attendance {
  notArrived('Not arrived'),
  checkedIn('Checked in'),
  absent('Absent');

  const Attendance(this.label);
  final String label;
}

/// One registration: a player, or a pair in doubles, in one category.
class Entry {
  const Entry({
    required this.id,
    required this.tournamentId,
    required this.categoryId,
    required this.players,
    required this.registeredAt,
    required this.amount,
    this.approval = Approval.pending,
    this.payment = PaymentState.pending,
    this.attendance = Attendance.notArrived,
    this.seed,
    required this.checkInCode,
  });

  final String id;
  final String tournamentId;
  final String categoryId;
  final List<PlayerRef> players;
  final DateTime registeredAt;

  /// What this entry owes or paid, in rupees.
  final int amount;
  final Approval approval;
  final PaymentState payment;
  final Attendance attendance;
  final int? seed;

  /// Short code on the player's ticket, for check-in without a camera.
  final String checkInCode;

  /// "Riya Shah" or "Riya Shah / Kamal Parmar".
  String get name => players.map((p) => p.name).join(' / ');

  /// "Riya S. / Kamal P.": fits a scoreboard.
  String get shortName => players.map((p) => shortPlayerName(p.name)).join(' / ');

  /// The team's SkorX Rating: the mean of the rated players.
  double? get rating {
    final rated = players.map((p) => p.rating).whereType<double>().toList();
    if (rated.isEmpty) return null;
    return rated.reduce((a, b) => a + b) / rated.length;
  }

  bool get inDraw => approval == Approval.approved;
  bool get needsPartner => players.length == 1;

  Entry copyWith({
    Approval? approval,
    PaymentState? payment,
    Attendance? attendance,
    String? categoryId,
    int? Function()? seed,
    List<PlayerRef>? players,
  }) =>
      Entry(
        id: id,
        tournamentId: tournamentId,
        categoryId: categoryId ?? this.categoryId,
        players: players ?? this.players,
        registeredAt: registeredAt,
        amount: amount,
        approval: approval ?? this.approval,
        payment: payment ?? this.payment,
        attendance: attendance ?? this.attendance,
        seed: seed == null ? this.seed : seed(),
        checkInCode: checkInCode,
      );
}

/// "Riya Shah" → "Riya S.".
String shortPlayerName(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length < 2) return name.trim();
  return '${parts.first} ${parts.last[0]}.';
}

/// Where a tournament match is in its day. Mirrors the API's match state
/// machine (ARCHITECTURE.md §8): scheduled → called → live ⇄ paused →
/// completed. "Delayed" is not stored; it is a scheduled match whose time
/// has passed (see [TmsMatch.isDelayed]).
enum MatchState {
  pending('Waiting'),
  scheduled('Scheduled'),
  called('Called'),
  live('Live'),
  paused('Paused'),
  completed('Final');

  const MatchState(this.label);
  final String label;

  bool get onCourt => this == called || this == live || this == paused;
}

/// A match in a tournament draw.
class TmsMatch {
  const TmsMatch({
    required this.id,
    required this.tournamentId,
    required this.categoryId,
    required this.round,
    required this.roundLabel,
    required this.number,
    this.entryA,
    this.entryB,
    this.labelA = 'TBD',
    this.labelB = 'TBD',
    this.sourceA,
    this.sourceB,
    this.pool,
    this.courtId,
    this.scheduledAt,
    this.state = MatchState.pending,
    this.games = const [],
    this.serve,
    this.winner,
    this.scoreVersion = 0,
    this.startedAt,
    this.completedAt,
  });

  final String id;
  final String tournamentId;
  final String categoryId;

  /// 1-based round within the category's draw.
  final int round;
  final String roundLabel;

  /// Match number within the tournament, shown to players ("Match 14").
  final int number;
  final String? entryA;
  final String? entryB;
  final String labelA;
  final String labelB;

  /// The matches whose winners fill each side, in a knockout.
  final String? sourceA;
  final String? sourceB;

  /// "A", "B"… in pool play.
  final String? pool;
  final String? courtId;
  final DateTime? scheduledAt;
  final MatchState state;

  /// Game scores, the last one in progress while live.
  final List<GameScore> games;
  final ServeState? serve;
  final Side? winner;

  /// Bumped by every accepted score write. Writes carry the version they
  /// were based on, so two devices scoring at once cannot silently overwrite.
  final int scoreVersion;
  final DateTime? startedAt;
  final DateTime? completedAt;

  bool get ready => entryA != null && entryB != null;

  /// A bye: one side will never be filled, so the other advances.
  bool get isBye => state == MatchState.completed && (entryA == null || entryB == null) && winner != null;

  bool isDelayed(DateTime now) =>
      (state == MatchState.scheduled || state == MatchState.called) &&
      scheduledAt != null &&
      now.difference(scheduledAt!) > const Duration(minutes: 10);

  String label(Side side) => side == Side.a ? labelA : labelB;
  String? entry(Side side) => side == Side.a ? entryA : entryB;

  GameScore get currentGame => games.isEmpty ? GameScore.zero : games.last;

  int gamesWon(Side side) {
    var won = 0;
    for (final (i, g) in games.indexed) {
      final last = i == games.length - 1;
      if (last && state != MatchState.completed) break;
      if (g.of(side) > g.of(side.opponent)) won++;
    }
    return won;
  }

  /// "11-8, 9-11, 11-6".
  String get scoreLine => games.map((g) => '${g.a}-${g.b}').join(', ');

  TmsMatch copyWith({
    String? Function()? entryA,
    String? Function()? entryB,
    String? labelA,
    String? labelB,
    String? Function()? courtId,
    DateTime? Function()? scheduledAt,
    MatchState? state,
    List<GameScore>? games,
    ServeState? Function()? serve,
    Side? Function()? winner,
    int? scoreVersion,
    DateTime? Function()? startedAt,
    DateTime? Function()? completedAt,
  }) =>
      TmsMatch(
        id: id,
        tournamentId: tournamentId,
        categoryId: categoryId,
        round: round,
        roundLabel: roundLabel,
        number: number,
        entryA: entryA == null ? this.entryA : entryA(),
        entryB: entryB == null ? this.entryB : entryB(),
        labelA: labelA ?? this.labelA,
        labelB: labelB ?? this.labelB,
        sourceA: sourceA,
        sourceB: sourceB,
        pool: pool,
        courtId: courtId == null ? this.courtId : courtId(),
        scheduledAt: scheduledAt == null ? this.scheduledAt : scheduledAt(),
        state: state ?? this.state,
        games: games ?? this.games,
        serve: serve == null ? this.serve : serve(),
        winner: winner == null ? this.winner : winner(),
        scoreVersion: scoreVersion ?? this.scoreVersion,
        startedAt: startedAt == null ? this.startedAt : startedAt(),
        completedAt: completedAt == null ? this.completedAt : completedAt(),
      );
}

/// What the organiser set on a court. Whether it is live or waiting comes
/// from its matches (see [courtBoard]).
enum CourtMode {
  open('Available'),
  onBreak('Break'),
  maintenance('Maintenance'),
  blocked('Blocked');

  const CourtMode(this.label);
  final String label;
}

class TmsCourt {
  const TmsCourt({required this.id, required this.tournamentId, required this.name, this.mode = CourtMode.open, this.note});

  final String id;
  final String tournamentId;
  final String name;
  final CourtMode mode;

  /// e.g. "Back at 5:30 PM", "Net being replaced".
  final String? note;

  TmsCourt copyWith({String? name, CourtMode? mode, String? Function()? note}) => TmsCourt(
        id: id,
        tournamentId: tournamentId,
        name: name ?? this.name,
        mode: mode ?? this.mode,
        note: note == null ? this.note : note(),
      );
}

/// What a court shows on the board right now.
enum CourtStatus {
  live('Live'),
  ready('Ready'),
  delayed('Delayed'),
  idle('Free'),
  onBreak('Break'),
  maintenance('Maintenance'),
  blocked('Blocked');

  const CourtStatus(this.label);
  final String label;
}

class CourtSlot {
  const CourtSlot({required this.court, required this.status, this.current, this.next});

  final TmsCourt court;
  final CourtStatus status;

  /// The match on court (called, live or paused).
  final TmsMatch? current;

  /// The next match scheduled on this court.
  final TmsMatch? next;
}

/// The live board: one slot per court, derived from courts and matches so it
/// can never disagree with the match list.
List<CourtSlot> courtBoard(List<TmsCourt> courts, List<TmsMatch> matches, DateTime now) {
  return [
    for (final court in courts)
      () {
        final onCourt = matches.where((m) => m.courtId == court.id && m.state.onCourt).toList()
          ..sort((a, b) => b.state.index.compareTo(a.state.index));
        final upcoming = matches.where((m) => m.courtId == court.id && m.state == MatchState.scheduled).toList()
          ..sort((a, b) => (a.scheduledAt ?? now).compareTo(b.scheduledAt ?? now));
        final current = onCourt.firstOrNull;
        final next = upcoming.firstOrNull;
        final status = switch (court.mode) {
          CourtMode.maintenance => CourtStatus.maintenance,
          CourtMode.blocked => CourtStatus.blocked,
          CourtMode.onBreak when current == null => CourtStatus.onBreak,
          _ => current != null
              ? (current.state == MatchState.called
                  ? (current.isDelayed(now) ? CourtStatus.delayed : CourtStatus.ready)
                  : CourtStatus.live)
              : (next != null && next.isDelayed(now) ? CourtStatus.delayed : CourtStatus.idle),
        };
        return CourtSlot(court: court, status: status, current: current, next: next);
      }(),
  ];
}

/// Why a typed-in result cannot be accepted, or null when it is valid under
/// [rules]. The API runs the same check (`isGameComplete` per game).
String? validateResult(MatchRules rules, List<GameScore> games) {
  if (games.isEmpty) return 'Enter at least one game.';
  var wonA = 0;
  var wonB = 0;
  for (final (i, game) in games.indexed) {
    final n = i + 1;
    if (wonA >= rules.gamesToWin || wonB >= rules.gamesToWin) {
      return 'Game $n was not needed: the match was already decided.';
    }
    final high = game.a > game.b ? game.a : game.b;
    final low = game.a > game.b ? game.b : game.a;
    if (game.a == game.b) return 'Game $n is tied. A game needs a winner.';
    if (high < rules.pointsToWin) return 'Game $n: the winner needs at least ${rules.pointsToWin} points.';
    final cap = rules.pointCap;
    if (cap != null && high > cap) return 'Game $n: no game goes past $cap points.';
    final lead = high - low;
    if (cap != null && high == cap) {
      // Only reachable from deuce: 30-29 or 30-28 in badminton.
      if (low < cap - 2) return 'Game $n: the game would have ended before $cap. Check the score.';
    } else if (rules.winByTwo) {
      if (lead < 2) return 'Game $n must be won by 2.';
      if (high > rules.pointsToWin && lead != 2) {
        return 'Game $n: past ${rules.pointsToWin}, a game ends at a 2-point lead. Check the score.';
      }
    } else if (high > rules.pointsToWin) {
      return 'Game $n ends at ${rules.pointsToWin} points.';
    }
    if (game.a > game.b) {
      wonA++;
    } else {
      wonB++;
    }
  }
  if (wonA < rules.gamesToWin && wonB < rules.gamesToWin) {
    return 'Nobody has won ${rules.gamesToWin} ${rules.gamesToWin == 1 ? 'game' : 'games'} yet.';
  }
  return null;
}

enum AnnouncementKind {
  general('General'),
  match('Match call'),
  court('Court'),
  schedule('Schedule change'),
  delay('Delay'),
  emergency('Emergency');

  const AnnouncementKind(this.label);
  final String label;
}

enum Audience {
  everyone('All players'),
  category('A category'),
  court('Players on a court'),
  player('One player');

  const Audience(this.label);
  final String label;
}

class Announcement {
  const Announcement({
    required this.id,
    required this.tournamentId,
    required this.kind,
    required this.audience,
    required this.message,
    required this.sentAt,
    required this.sentBy,
    required this.recipients,
    this.targetLabel,
    this.push = true,
  });

  final String id;
  final String tournamentId;
  final AnnouncementKind kind;
  final Audience audience;

  /// e.g. "Mixed Doubles · Open", "Court 3", "Riya Shah".
  final String? targetLabel;
  final String message;
  final DateTime sentAt;
  final String sentBy;
  final int recipients;
  final bool push;
}

/// One logged administrative change (who, what, before → after).
class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.at,
    required this.actor,
    required this.action,
    required this.subject,
    this.before,
    this.after,
  });

  final String id;
  final DateTime at;
  final String actor;
  final String action;
  final String subject;
  final String? before;
  final String? after;
}

/// Organisation-wide numbers for the dashboard.
class OrgOverview {
  const OrgOverview({
    required this.activeTournaments,
    required this.upcomingTournaments,
    required this.players,
    required this.pendingApprovals,
    required this.unpaid,
    required this.todaysMatches,
    required this.collected,
    required this.outstanding,
  });

  final int activeTournaments;
  final int upcomingTournaments;
  final int players;
  final int pendingApprovals;
  final int unpaid;
  final int todaysMatches;
  final int collected;
  final int outstanding;
}

enum ExpenseKind { venue, officials, staff, equipment, marketing, food, prizes, other }

class Expense {
  const Expense({required this.kind, required this.label, required this.amount, required this.tournamentId});

  final ExpenseKind kind;
  final String label;
  final int amount;
  final String tournamentId;
}

class Sponsor {
  const Sponsor({required this.name, required this.package, required this.amount, required this.paid, required this.placements});

  final String name;
  final String package;
  final int amount;
  final bool paid;

  /// Tournament page, scoreboard, stream overlay…
  final List<String> placements;
}

class OrgFinance {
  const OrgFinance({
    required this.collected,
    required this.outstanding,
    required this.refunded,
    required this.sponsorship,
    required this.expenses,
    required this.sponsors,
  });

  final int collected;
  final int outstanding;
  final int refunded;
  final int sponsorship;
  final List<Expense> expenses;
  final List<Sponsor> sponsors;

  int get revenue => collected + sponsorship;
  int get spent => expenses.fold(0, (sum, e) => sum + e.amount);
  int get net => revenue - spent;
}

class Venue {
  const Venue({required this.id, required this.name, required this.address, required this.courts, required this.indoor, this.amenities = const []});

  final String id;
  final String name;
  final String address;
  final int courts;
  final bool indoor;
  final List<String> amenities;
}

class StaffMember {
  const StaffMember({required this.name, required this.role, this.phone});

  final String name;

  /// The API role: owner, tournament_admin, scorer, check_in_staff, finance, viewer.
  final String role;
  final String? phone;
}

class Review {
  const Review({required this.author, required this.tournament, required this.rating, required this.text, required this.at, this.reply});

  final String author;
  final String tournament;
  final int rating;
  final String text;
  final DateTime at;

  /// The organiser's public response. The review itself is never editable.
  final String? reply;
}

class OrgProfile {
  const OrgProfile({
    required this.name,
    required this.city,
    required this.verified,
    required this.since,
    required this.tournaments,
    required this.completed,
    required this.playersHosted,
    required this.matchesManaged,
    required this.repeatPlayerPercent,
    required this.averageRating,
    required this.venues,
    required this.staff,
    required this.reviews,
    this.contact,
    this.website,
  });

  final String name;
  final String city;
  final bool verified;
  final DateTime since;
  final int tournaments;
  final int completed;
  final int playersHosted;
  final int matchesManaged;
  final int repeatPlayerPercent;
  final double averageRating;
  final List<Venue> venues;
  final List<StaffMember> staff;
  final List<Review> reviews;
  final String? contact;
  final String? website;
}
