import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../sports/core/score_state.dart';
import '../../../sports/core/scoring_engine.dart';
import 'draw_engine.dart';
import 'sample_organizer_repository.dart';
import 'schedule_engine.dart';
import 'tms_models.dart';

/// Everything the organiser typed into the create-tournament wizard.
class TournamentDraft {
  const TournamentDraft({
    required this.name,
    required this.venue,
    required this.city,
    required this.start,
    required this.end,
    required this.registrationOpens,
    required this.registrationCloses,
    required this.categories,
    required this.courts,
    this.description = '',
    this.indoor = true,
    this.waitlist = true,
    this.earlyBirdDiscount = 0,
  });

  final String name;
  final String description;
  final String venue;
  final String city;
  final bool indoor;
  final DateTime start;
  final DateTime end;
  final DateTime registrationOpens;
  final DateTime registrationCloses;
  final List<OrgCategory> categories;
  final int courts;
  final bool waitlist;
  final int earlyBirdDiscount;

  /// Why the draft cannot be saved yet, or null. The API checks the same.
  String? get problem {
    if (name.trim().length < 3) return 'Give the tournament a name.';
    if (venue.trim().isEmpty) return 'Add the venue.';
    if (end.isBefore(start)) return 'The tournament ends before it starts.';
    if (registrationCloses.isAfter(start)) return 'Registration must close before the tournament starts.';
    if (registrationCloses.isBefore(registrationOpens)) return 'Registration closes before it opens.';
    if (categories.isEmpty) return 'Add at least one category.';
    if (courts < 1) return 'A tournament needs at least one court.';
    return null;
  }
}

/// A change to one registration. Null fields are left as they are.
class EntryChange {
  const EntryChange({this.approval, this.payment, this.attendance, this.categoryId});

  final Approval? approval;
  final PaymentState? payment;
  final Attendance? attendance;
  final String? categoryId;
}

enum MatchCommand { call, start, pause, resume }

enum ScoreWriteKind { rally, undo, serve }

/// One scoring action from a device. [clientEventId] is made on the device
/// when the tap happens, so sending it twice is always safe; [baseVersion]
/// is the score version the device saw, so a write made on stale data is
/// refused with `SCORE_CONFLICT` instead of overwriting.
class ScoreWrite {
  const ScoreWrite({required this.clientEventId, required this.baseVersion, required this.kind, this.side, this.serve});

  final String clientEventId;
  final int baseVersion;
  final ScoreWriteKind kind;
  final Side? side;
  final ServeState? serve;

  Map<String, dynamic> toJson() => {
        'clientEventId': clientEventId,
        'baseVersion': baseVersion,
        'kind': kind.name,
        if (side != null) 'side': side!.name,
        if (serve != null) 'serve': {'side': serve!.side.name, 'serverNumber': serve!.serverNumber},
      };

  factory ScoreWrite.fromJson(Map<String, dynamic> json) {
    final serve = json['serve'] as Map<String, dynamic>?;
    return ScoreWrite(
      clientEventId: json['clientEventId'] as String,
      baseVersion: json['baseVersion'] as int,
      kind: ScoreWriteKind.values.byName(json['kind'] as String),
      side: json['side'] == null ? null : Side.values.byName(json['side'] as String),
      serve: serve == null
          ? null
          : ServeState(Side.values.byName(serve['side'] as String), serve['serverNumber'] as int?),
    );
  }

  ScoreWrite rebased(int version) =>
      ScoreWrite(clientEventId: clientEventId, baseVersion: version, kind: kind, side: side, serve: serve);
}

const scoreConflict = 'SCORE_CONFLICT';

/// The server's scoring record for a match: every applied event, and the
/// version they add up to. A device replays it with the sport's engine.
class ScoreLog {
  const ScoreLog(this.version, this.events);

  final int version;
  final List<ScoringEvent> events;
}

/// What changed, from the realtime stream (ARCHITECTURE.md §7). Screens do
/// not listen to it directly: [tmsRealtimeProvider] refreshes exactly the
/// providers each event affects.
enum TmsEventType { tournament, entries, draw, matches, score, courts, announcement }

class TmsEvent {
  const TmsEvent(this.type, {required this.organizationId, this.tournamentId, this.matchId});

  final TmsEventType type;
  final String organizationId;
  final String? tournamentId;
  final String? matchId;
}

/// Organiser data. Method names mirror the endpoints they call
/// (docs/ORGANIZER-TMS.md §6). The server enforces every permission and
/// every life-cycle rule; the app only hides what would be refused.
abstract class OrganizerRepository {
  /// `GET /organizations/:orgId/overview`
  Future<OrgOverview> overview(String orgId);

  /// `GET /organizations/:orgId/tournaments`
  Future<List<OrgTournament>> tournaments(String orgId);

  /// `GET /tournaments/:id`
  Future<OrgTournament> tournament(String id);

  /// `POST /organizations/:orgId/tournaments`. Creates a draft; with
  /// [publish] it also opens registration, so players can find it.
  Future<OrgTournament> createTournament(String orgId, TournamentDraft draft, {bool publish = false});

  /// `POST /tournaments/:id/transitions {action}`: open or close
  /// registration, start, complete, cancel, archive.
  Future<OrgTournament> transition(String id, TmsAction action);

  /// `POST /tournaments/:id/duplicate`: same setup as a new draft.
  Future<OrgTournament> duplicate(String id);

  /// `PATCH /tournaments/:id {checkInOpen}`
  Future<OrgTournament> setCheckInOpen(String id, bool open);

  /// `GET /tournaments/:id/entries`
  Future<List<Entry>> entries(String tournamentId);

  /// `PATCH /entries/:id`
  Future<Entry> updateEntry(String entryId, EntryChange change);

  /// `POST /tournaments/:id/check-in {code}`: the code on the player's ticket.
  Future<Entry> checkInByCode(String tournamentId, String code);

  /// `POST /tournaments/:id/check-in/bulk`: every approved entry. Returns how many changed.
  Future<int> checkInAll(String tournamentId);

  /// `GET /tournaments/:id/categories/:cid/draw`, or null before one is made.
  Future<DrawLayout?> draw(String tournamentId, String categoryId);

  /// `POST /tournaments/:id/categories/:cid/draw {method}`
  Future<DrawLayout> generateDraw(String tournamentId, String categoryId, DrawMethod method);

  /// `PATCH /tournaments/:id/categories/:cid/draw {swap: [a, b]}`
  Future<DrawLayout> swapInDraw(String tournamentId, String categoryId, String entryA, String entryB);

  /// `POST /tournaments/:id/categories/:cid/draw/publish`: players see it.
  Future<void> publishDraw(String tournamentId, String categoryId);

  /// `GET /tournaments/:id/matches`
  Future<List<TmsMatch>> matches(String tournamentId);

  /// `GET /matches/:id`
  Future<TmsMatch> match(String matchId);

  /// `POST /tournaments/:id/schedule`
  Future<List<TmsMatch>> generateSchedule(String tournamentId, ScheduleSettings settings);

  /// `GET /tournaments/:id/courts`
  Future<List<TmsCourt>> courts(String tournamentId);

  /// `PATCH /courts/:id`
  Future<TmsCourt> updateCourt(String courtId, {String? name, CourtMode? mode, String? note});

  /// `PATCH /matches/:id {courtId}`: move a match, keeping its time.
  Future<TmsMatch> moveMatch(String matchId, String courtId);

  /// `POST /matches/:id/{call|start|pause|resume}`
  Future<TmsMatch> command(String matchId, MatchCommand command);

  /// `GET /matches/:id/score-events`
  Future<ScoreLog> scoreLog(String matchId);

  /// `POST /matches/:id/score`. Idempotent on [ScoreWrite.clientEventId].
  /// Throws `SCORE_CONFLICT` when [ScoreWrite.baseVersion] is stale.
  Future<TmsMatch> score(String matchId, ScoreWrite write);

  /// `POST /matches/:id/complete {version}`: the official confirms the
  /// result. Stats, standings and the next round update from this.
  Future<TmsMatch> confirmResult(String matchId, int version);

  /// `POST /matches/:id/result {games, reason}`: typed-in or corrected
  /// result, validated against the category rules and audited.
  Future<TmsMatch> enterResult(String matchId, List<GameScore> games, {required String reason});

  /// `GET /tournaments/:id/announcements`
  Future<List<Announcement>> announcements(String tournamentId);

  /// `POST /tournaments/:id/announcements`. Returns it with the recipient count.
  Future<Announcement> announce(
    String tournamentId, {
    required AnnouncementKind kind,
    required Audience audience,
    required String message,
    String? target,
    bool push = true,
  });

  /// `GET /organizations/:orgId/audit`
  Future<List<AuditEntry>> audit(String orgId);

  /// `GET /organizations/:orgId/finance`
  Future<OrgFinance> finance(String orgId);

  /// `GET /organizations/:orgId/profile`
  Future<OrgProfile> profile(String orgId);

  /// `GET /realtime/stream?scope=org:<orgId>` (Server-Sent Events).
  Stream<TmsEvent> events(String orgId);
}

final organizerRepositoryProvider = Provider<OrganizerRepository>(
  (ref) => kDebugMode ? ref.watch(sampleOrganizerRepositoryProvider) : const EmptyOrganizerRepository(),
);

final orgOverviewProvider =
    FutureProvider.family<OrgOverview, String>((ref, orgId) => ref.watch(organizerRepositoryProvider).overview(orgId));

final orgTournamentsProvider = FutureProvider.family<List<OrgTournament>, String>(
  (ref, orgId) => ref.watch(organizerRepositoryProvider).tournaments(orgId),
);

final orgTournamentProvider =
    FutureProvider.family<OrgTournament, String>((ref, id) => ref.watch(organizerRepositoryProvider).tournament(id));

final entriesProvider =
    FutureProvider.family<List<Entry>, String>((ref, tid) => ref.watch(organizerRepositoryProvider).entries(tid));

final tmsMatchesProvider =
    FutureProvider.family<List<TmsMatch>, String>((ref, tid) => ref.watch(organizerRepositoryProvider).matches(tid));

final tmsMatchProvider =
    FutureProvider.family<TmsMatch, String>((ref, id) => ref.watch(organizerRepositoryProvider).match(id));

final courtsProvider =
    FutureProvider.family<List<TmsCourt>, String>((ref, tid) => ref.watch(organizerRepositoryProvider).courts(tid));

final drawProvider = FutureProvider.family<DrawLayout?, (String, String)>(
  (ref, key) => ref.watch(organizerRepositoryProvider).draw(key.$1, key.$2),
);

final announcementsProvider = FutureProvider.family<List<Announcement>, String>(
  (ref, tid) => ref.watch(organizerRepositoryProvider).announcements(tid),
);

final auditProvider =
    FutureProvider.family<List<AuditEntry>, String>((ref, orgId) => ref.watch(organizerRepositoryProvider).audit(orgId));

final financeProvider =
    FutureProvider.family<OrgFinance, String>((ref, orgId) => ref.watch(organizerRepositoryProvider).finance(orgId));

final orgProfileProvider =
    FutureProvider.family<OrgProfile, String>((ref, orgId) => ref.watch(organizerRepositoryProvider).profile(orgId));

/// The tournament the Live and Players tabs work on: the live one, else the
/// next one coming up, else the most recent.
final focusTournamentProvider = Provider.family<AsyncValue<OrgTournament?>, String>((ref, orgId) {
  return ref.watch(orgTournamentsProvider(orgId)).whenData((all) {
    final byStart = [...all]..sort((a, b) => a.start.compareTo(b.start));
    return byStart.where((t) => t.status == TournamentStatus.live).firstOrNull ??
        byStart.where((t) => t.status.isActive).firstOrNull ??
        byStart.where((t) => t.status == TournamentStatus.completed).lastOrNull;
  });
});

/// Keeps the organiser's screens current: each realtime event refreshes
/// only the data it touches. Watched by the organiser shell.
final tmsRealtimeProvider = Provider.family<void, String>((ref, orgId) {
  final sub = ref.watch(organizerRepositoryProvider).events(orgId).listen((event) {
    final tid = event.tournamentId;
    switch (event.type) {
      case TmsEventType.tournament:
        ref.invalidate(orgTournamentsProvider(orgId));
        if (tid != null) ref.invalidate(orgTournamentProvider(tid));
      case TmsEventType.entries:
        if (tid != null) ref.invalidate(entriesProvider(tid));
      case TmsEventType.draw:
        ref.invalidate(drawProvider);
        if (tid != null) ref.invalidate(tmsMatchesProvider(tid));
      case TmsEventType.matches:
      case TmsEventType.score:
        if (tid != null) ref.invalidate(tmsMatchesProvider(tid));
        if (event.matchId != null) ref.invalidate(tmsMatchProvider(event.matchId!));
      case TmsEventType.courts:
        if (tid != null) ref.invalidate(courtsProvider(tid));
      case TmsEventType.announcement:
        if (tid != null) ref.invalidate(announcementsProvider(tid));
    }
    // Counts on the dashboard move with almost everything.
    if (event.type != TmsEventType.score) ref.invalidate(orgOverviewProvider(orgId));
    ref.invalidate(auditProvider(orgId));
  });
  ref.onDispose(sub.cancel);
});

/// Release builds until the endpoints ship: honest empty screens, and
/// writes that say so instead of pretending to succeed.
class EmptyOrganizerRepository implements OrganizerRepository {
  const EmptyOrganizerRepository();

  static const _notYet = ApiException('NOT_AVAILABLE', 'Tournament management opens in the next update.');

  @override
  Future<OrgOverview> overview(String orgId) async => const OrgOverview(
        activeTournaments: 0,
        upcomingTournaments: 0,
        players: 0,
        pendingApprovals: 0,
        unpaid: 0,
        todaysMatches: 0,
        collected: 0,
        outstanding: 0,
      );

  @override
  Future<List<OrgTournament>> tournaments(String orgId) async => const [];

  @override
  Future<OrgTournament> tournament(String id) async =>
      throw const ApiException('NOT_FOUND', 'This tournament is no longer available.');

  @override
  Future<List<Entry>> entries(String tournamentId) async => const [];

  @override
  Future<List<TmsMatch>> matches(String tournamentId) async => const [];

  @override
  Future<TmsMatch> match(String matchId) async => throw const ApiException('NOT_FOUND', 'This match is no longer available.');

  @override
  Future<List<TmsCourt>> courts(String tournamentId) async => const [];

  @override
  Future<DrawLayout?> draw(String tournamentId, String categoryId) async => null;

  @override
  Future<List<Announcement>> announcements(String tournamentId) async => const [];

  @override
  Future<List<AuditEntry>> audit(String orgId) async => const [];

  @override
  Future<OrgFinance> finance(String orgId) async =>
      const OrgFinance(collected: 0, outstanding: 0, refunded: 0, sponsorship: 0, expenses: [], sponsors: []);

  @override
  Future<OrgProfile> profile(String orgId) async => throw _notYet;

  @override
  Stream<TmsEvent> events(String orgId) => const Stream.empty();

  @override
  Future<OrgTournament> createTournament(String orgId, TournamentDraft draft, {bool publish = false}) async =>
      throw _notYet;
  @override
  Future<OrgTournament> transition(String id, TmsAction action) async => throw _notYet;
  @override
  Future<OrgTournament> duplicate(String id) async => throw _notYet;
  @override
  Future<OrgTournament> setCheckInOpen(String id, bool open) async => throw _notYet;
  @override
  Future<Entry> updateEntry(String entryId, EntryChange change) async => throw _notYet;
  @override
  Future<Entry> checkInByCode(String tournamentId, String code) async => throw _notYet;
  @override
  Future<int> checkInAll(String tournamentId) async => throw _notYet;
  @override
  Future<DrawLayout> generateDraw(String tournamentId, String categoryId, DrawMethod method) async => throw _notYet;
  @override
  Future<DrawLayout> swapInDraw(String tournamentId, String categoryId, String entryA, String entryB) async =>
      throw _notYet;
  @override
  Future<void> publishDraw(String tournamentId, String categoryId) async => throw _notYet;
  @override
  Future<List<TmsMatch>> generateSchedule(String tournamentId, ScheduleSettings settings) async => throw _notYet;
  @override
  Future<TmsCourt> updateCourt(String courtId, {String? name, CourtMode? mode, String? note}) async => throw _notYet;
  @override
  Future<TmsMatch> moveMatch(String matchId, String courtId) async => throw _notYet;
  @override
  Future<TmsMatch> command(String matchId, MatchCommand command) async => throw _notYet;
  @override
  Future<ScoreLog> scoreLog(String matchId) async => throw _notYet;
  @override
  Future<TmsMatch> score(String matchId, ScoreWrite write) async => throw _notYet;
  @override
  Future<TmsMatch> confirmResult(String matchId, int version) async => throw _notYet;
  @override
  Future<TmsMatch> enterResult(String matchId, List<GameScore> games, {required String reason}) async => throw _notYet;
  @override
  Future<Announcement> announce(
    String tournamentId, {
    required AnnouncementKind kind,
    required Audience audience,
    required String message,
    String? target,
    bool push = true,
  }) async =>
      throw _notYet;
}
