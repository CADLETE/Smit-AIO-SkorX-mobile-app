import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/sample_latency.dart';
import '../../../sports/core/match_rules.dart';
import '../../../sports/core/score_state.dart';
import '../../../sports/core/scoring_engine.dart';
import '../../../sports/sport_registry.dart';
import '../../player/data/player_repository.dart' show PlayCategory;
import '../../tournaments/data/tournaments.dart' as player;
import 'draw_engine.dart';
import 'draw_engine.dart' as engine;
import 'organizer_repository.dart';
import 'schedule_engine.dart';
import 'tms_models.dart';

/// The debug builds' stand-in for the API: one in-memory store that both
/// the organiser screens and the player's tournament screens read, so a
/// tournament published here shows up in Player › Tournaments and a player's
/// registration shows up in the organiser's queue. It applies the same rules
/// the server will: life cycle, versioned idempotent scoring, result
/// validation, audit log. Everything resets when the app restarts.
final sampleOrganizerRepositoryProvider = Provider<SampleOrganizerRepository>((ref) {
  final repo = SampleOrganizerRepository(latency: ref.watch(sampleLatencyProvider));
  ref.onDispose(repo.dispose);
  return repo;
});

class SampleOrganizerRepository implements OrganizerRepository {
  SampleOrganizerRepository({this.latency = const Duration(milliseconds: 350), DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final Duration latency;
  final DateTime Function() _clock;
  final _events = StreamController<TmsEvent>.broadcast();

  final _seeded = <String>{};
  final _tournaments = <String, OrgTournament>{};
  final _entries = <String, Entry>{};
  final _matches = <String, TmsMatch>{};
  final _courts = <String, TmsCourt>{};
  final _draws = <(String, String), DrawLayout>{};
  final _rallies = <String, List<ScoringEvent>>{};
  final _acks = <String, Set<String>>{};
  final _announcements = <Announcement>[];
  final _audit = <String, List<AuditEntry>>{};
  final _expenses = <String, List<Expense>>{};
  var _ids = 0;

  /// Who the sample server thinks is making changes, for the audit log.
  String actor = 'You';

  /// While true every call fails as if the venue Wi-Fi dropped. For trying
  /// the offline score queue in debug builds and tests.
  bool offline = false;

  void dispose() => _events.close();

  String _id(String prefix) => '$prefix-${++_ids}';

  Future<void> _wait([int times = 1]) async {
    await simulateLatency(latency * times);
    if (offline) {
      throw const ApiException(ApiException.network, 'No internet connection. Check your network and try again.');
    }
  }

  void _emit(TmsEventType type, String orgId, {String? tournamentId, String? matchId}) {
    if (!_events.isClosed) {
      _events.add(TmsEvent(type, organizationId: orgId, tournamentId: tournamentId, matchId: matchId));
    }
  }

  void _log(String orgId, String action, String subject, {String? before, String? after}) {
    (_audit[orgId] ??= []).insert(
      0,
      AuditEntry(id: _id('a'), at: _clock(), actor: actor, action: action, subject: subject, before: before, after: after),
    );
  }

  OrgTournament _t(String id) {
    final t = _tournaments[id];
    if (t == null) throw const ApiException('NOT_FOUND', 'This tournament is no longer available.');
    return t;
  }

  TmsMatch _m(String id) {
    final m = _matches[id];
    if (m == null) throw const ApiException('NOT_FOUND', 'This match is no longer available.');
    return m;
  }

  void _require(OrgTournament t, TmsAction action) {
    if (!t.can(action)) {
      throw ApiException(
        'TOURNAMENT_STATE',
        "That can't be done while the tournament is ${t.status.label.toLowerCase()}.",
      );
    }
  }

  Iterable<Entry> _entriesOf(String tid) => _entries.values.where((e) => e.tournamentId == tid);
  Iterable<TmsMatch> _matchesOf(String tid) => _matches.values.where((m) => m.tournamentId == tid);

  String _labelOf(String entryId) => _entries[entryId]?.shortName ?? 'TBD';

  MatchSetup _setup(TmsMatch m) {
    final c = _t(m.tournamentId).category(m.categoryId)!;
    return MatchSetup(rules: c.rules, playersPerSide: c.playersPerSide, firstServer: Side.a);
  }

  // ---------------------------------------------------------------- reads

  @override
  Stream<TmsEvent> events(String orgId) => _events.stream.where((e) => e.organizationId == orgId);

  /// Every organisation's changes: the player side refreshes on these.
  Stream<TmsEvent> get allEvents => _events.stream;

  @override
  Future<OrgOverview> overview(String orgId) async {
    _ensureSeeded(orgId);
    await _wait();
    final now = _clock();
    final ts = _tournaments.values.where((t) => t.organizationId == orgId).toList();
    final open = ts.where((t) => t.status.isActive).map((t) => t.id).toSet();
    final entries = _entries.values.where((e) => open.contains(e.tournamentId)).toList();
    final all = _entries.values.where((e) => ts.any((t) => t.id == e.tournamentId));
    return OrgOverview(
      activeTournaments: ts.where((t) => t.status == TournamentStatus.live).length,
      upcomingTournaments: ts.where((t) => t.status.isActive && t.status != TournamentStatus.live).length,
      players: {
        for (final e in entries.where((e) => e.approval == Approval.approved))
          for (final p in e.players) p.id,
      }.length,
      pendingApprovals: entries.where((e) => e.approval == Approval.pending).length,
      unpaid: entries.where((e) => e.approval != Approval.rejected && e.payment == PaymentState.pending).length,
      todaysMatches: _matches.values
          .where((m) => open.contains(m.tournamentId) && m.scheduledAt != null && _sameDay(m.scheduledAt!, now))
          .length,
      collected: all.where((e) => e.payment == PaymentState.paid).fold(0, (s, e) => s + e.amount),
      outstanding: entries
          .where((e) => e.approval != Approval.rejected && e.payment == PaymentState.pending)
          .fold(0, (s, e) => s + e.amount),
    );
  }

  @override
  Future<List<OrgTournament>> tournaments(String orgId) async {
    _ensureSeeded(orgId);
    await _wait();
    return _tournaments.values.where((t) => t.organizationId == orgId).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
  }

  @override
  Future<OrgTournament> tournament(String id) async {
    await _wait();
    return _t(id);
  }

  @override
  Future<List<Entry>> entries(String tournamentId) async {
    await _wait();
    return _entriesOf(tournamentId).toList()..sort((a, b) => b.registeredAt.compareTo(a.registeredAt));
  }

  @override
  Future<List<TmsMatch>> matches(String tournamentId) async {
    await _wait();
    return _matchesOf(tournamentId).where((m) => !m.isBye).toList()..sort((a, b) => a.number.compareTo(b.number));
  }

  @override
  Future<TmsMatch> match(String matchId) async {
    await _wait();
    return _m(matchId);
  }

  @override
  Future<List<TmsCourt>> courts(String tournamentId) async {
    await _wait();
    return _courts.values.where((c) => c.tournamentId == tournamentId).toList();
  }

  @override
  Future<DrawLayout?> draw(String tournamentId, String categoryId) async {
    await _wait();
    return _draws[(tournamentId, categoryId)];
  }

  @override
  Future<List<Announcement>> announcements(String tournamentId) async {
    await _wait();
    return _announcements.where((a) => a.tournamentId == tournamentId).toList();
  }

  @override
  Future<List<AuditEntry>> audit(String orgId) async {
    _ensureSeeded(orgId);
    await _wait();
    return List.of(_audit[orgId] ?? const []);
  }

  @override
  Future<OrgFinance> finance(String orgId) async {
    _ensureSeeded(orgId);
    await _wait();
    final tids = _tournaments.values.where((t) => t.organizationId == orgId).map((t) => t.id).toSet();
    final entries = _entries.values.where((e) => tids.contains(e.tournamentId) && e.approval != Approval.rejected);
    int sum(PaymentState s) => entries.where((e) => e.payment == s).fold(0, (a, e) => a + e.amount);
    final sponsors = _sponsors;
    return OrgFinance(
      collected: sum(PaymentState.paid),
      outstanding: sum(PaymentState.pending),
      refunded: sum(PaymentState.refunded),
      sponsorship: sponsors.where((s) => s.paid).fold(0, (a, s) => a + s.amount),
      expenses: [for (final t in tids) ...?_expenses[t]],
      sponsors: sponsors,
    );
  }

  @override
  Future<OrgProfile> profile(String orgId) async {
    _ensureSeeded(orgId);
    await _wait();
    final ts = _tournaments.values.where((t) => t.organizationId == orgId).toList();
    final tids = ts.map((t) => t.id).toSet();
    final now = _clock();
    return OrgProfile(
      name: '',
      city: 'Ahmedabad, Gujarat',
      verified: true,
      since: DateTime(now.year - 2, 3),
      tournaments: ts.length + 21,
      completed: ts.where((t) => t.status == TournamentStatus.completed).length + 21,
      playersHosted: {
            for (final e in _entries.values.where((e) => tids.contains(e.tournamentId)))
              for (final p in e.players) p.id,
          }.length +
          1240,
      matchesManaged: _matches.values.where((m) => tids.contains(m.tournamentId) && !m.isBye).length + 2870,
      repeatPlayerPercent: 64,
      averageRating: 4.6,
      contact: '+91 98250 12345',
      website: 'skorx.in',
      venues: _venues,
      staff: const [
        StaffMember(name: 'Smit Ramani', role: 'owner', phone: '+91 95865 45430'),
        StaffMember(name: 'Kamal Parmar', role: 'tournament_admin'),
        StaffMember(name: 'Riya Shah', role: 'scorer'),
        StaffMember(name: 'Aarav Mehta', role: 'scorer'),
        StaffMember(name: 'Neha Joshi', role: 'check_in_staff'),
        StaffMember(name: 'Harsh Desai', role: 'finance'),
      ],
      reviews: [
        Review(
          author: 'Priya Nair',
          tournament: 'CADLETE Spring Cup',
          rating: 5,
          text: 'Matches ran on time and live scores were on my phone before I walked off court.',
          at: now.subtract(const Duration(days: 52)),
          reply: 'Thank you Priya! See you at the Summer Open.',
        ),
        Review(
          author: 'Dev Patel',
          tournament: 'CADLETE Spring Cup',
          rating: 4,
          text: 'Great courts and draws. Parking was tight in the evening.',
          at: now.subtract(const Duration(days: 55)),
        ),
        Review(
          author: 'Ishita Rao',
          tournament: 'Monsoon Doubles 2025',
          rating: 5,
          text: 'Best organised event in Gujarat. Check-in took 30 seconds.',
          at: now.subtract(const Duration(days: 300)),
        ),
      ],
    );
  }

  // --------------------------------------------------------------- writes

  @override
  Future<OrgTournament> createTournament(String orgId, TournamentDraft draft, {bool publish = false}) async {
    await _wait(2);
    final problem = draft.problem;
    if (problem != null) throw ApiException('VALIDATION', problem);
    final id = _id('t-new');
    final t = OrgTournament(
      id: id,
      organizationId: orgId,
      name: draft.name.trim(),
      description: draft.description.trim(),
      status: publish ? TournamentStatus.registrationOpen : TournamentStatus.draft,
      venue: draft.venue.trim(),
      city: draft.city.trim(),
      indoor: draft.indoor,
      start: draft.start,
      end: draft.end,
      registrationOpens: draft.registrationOpens,
      registrationCloses: draft.registrationCloses,
      categories: [for (final (i, c) in draft.categories.indexed) c.copyWith(id: '$id-c$i')],
      waitlist: draft.waitlist,
      earlyBirdDiscount: draft.earlyBirdDiscount,
    );
    _tournaments[id] = t;
    for (var i = 1; i <= draft.courts; i++) {
      _courts['$id-court$i'] = TmsCourt(id: '$id-court$i', tournamentId: id, name: 'Court $i');
    }
    _log(orgId, publish ? 'Published tournament' : 'Created draft', t.name);
    _emit(TmsEventType.tournament, orgId, tournamentId: id);
    return t;
  }

  @override
  Future<OrgTournament> transition(String id, TmsAction action) async {
    await _wait();
    final t = _t(id);
    _require(t, action);
    final next = TournamentLifecycle.after(t.status, action) ?? t.status;
    if (action == TmsAction.startTournament && _matchesOf(id).every((m) => m.scheduledAt == null)) {
      throw const ApiException('NOT_SCHEDULED', 'Make the schedule before starting.');
    }
    if (action == TmsAction.completeTournament && _matchesOf(id).any((m) => m.state.onCourt)) {
      throw const ApiException('MATCHES_ON_COURT', 'Finish or pause the matches on court first.');
    }
    final updated = t.copyWith(
      status: next,
      checkInOpen: action == TmsAction.completeTournament || action == TmsAction.cancel ? false : null,
    );
    _tournaments[id] = updated;
    _log(t.organizationId, _actionLog(action), t.name, before: t.status.label, after: next.label);
    _emit(TmsEventType.tournament, t.organizationId, tournamentId: id);
    return updated;
  }

  static String _actionLog(TmsAction action) => switch (action) {
        TmsAction.openRegistration => 'Opened registration',
        TmsAction.closeRegistration => 'Closed registration',
        TmsAction.startTournament => 'Started tournament',
        TmsAction.completeTournament => 'Completed tournament',
        TmsAction.cancel => 'Cancelled tournament',
        TmsAction.archive => 'Archived tournament',
        _ => 'Changed tournament',
      };

  @override
  Future<OrgTournament> duplicate(String id) async {
    await _wait();
    final t = _t(id);
    final now = _clock();
    final shift = DateTime(now.year, now.month, now.day + 30).difference(DateTime(t.start.year, t.start.month, t.start.day));
    final newId = _id('t-new');
    final copy = t.copyWith(
      id: newId,
      name: '${t.name} (copy)',
      status: TournamentStatus.draft,
      start: t.start.add(shift),
      end: t.end.add(shift),
      registrationOpens: now,
      registrationCloses: t.registrationCloses.add(shift),
      categories: [for (final (i, c) in t.categories.indexed) c.copyWith(id: '$newId-c$i')],
      checkInOpen: false,
      publishedDraws: const {},
    );
    _tournaments[newId] = copy;
    for (final c in _courts.values.where((c) => c.tournamentId == id).toList()) {
      final cid = '$newId-${c.id.split('-').last}';
      _courts[cid] = TmsCourt(id: cid, tournamentId: newId, name: c.name);
    }
    _log(t.organizationId, 'Duplicated tournament', t.name, after: copy.name);
    _emit(TmsEventType.tournament, t.organizationId, tournamentId: newId);
    return copy;
  }

  @override
  Future<OrgTournament> setCheckInOpen(String id, bool open) async {
    await _wait();
    final t = _t(id);
    _require(t, TmsAction.checkIn);
    final updated = t.copyWith(checkInOpen: open);
    _tournaments[id] = updated;
    _log(t.organizationId, open ? 'Opened check-in' : 'Closed check-in', t.name);
    _emit(TmsEventType.tournament, t.organizationId, tournamentId: id);
    return updated;
  }

  @override
  Future<Entry> updateEntry(String entryId, EntryChange change) async {
    await _wait();
    final e = _entries[entryId];
    if (e == null) throw const ApiException('NOT_FOUND', 'This registration is no longer available.');
    final t = _t(e.tournamentId);
    final structural = change.approval != null || change.categoryId != null;
    if (structural) _require(t, TmsAction.manageEntries);
    if (change.attendance != null) _require(t, TmsAction.checkIn);

    if (change.approval == Approval.approved && e.approval != Approval.approved) {
      final cid = change.categoryId ?? e.categoryId;
      final taken = _entriesOf(t.id).where((x) => x.categoryId == cid && x.approval == Approval.approved).length;
      if (taken >= t.category(cid)!.capacity) {
        throw const ApiException('CATEGORY_FULL', 'This category is full. Move them to the waitlist instead.');
      }
    }
    if (change.payment == PaymentState.refunded && e.payment != PaymentState.paid) {
      throw const ApiException('NOT_PAID', 'Only a paid entry can be refunded.');
    }
    final updated = e.copyWith(
      approval: change.approval,
      payment: change.payment,
      attendance: change.attendance,
      categoryId: change.categoryId,
    );
    _entries[entryId] = updated;
    if (change.approval != null) {
      _log(t.organizationId, 'Changed registration', e.name, before: e.approval.label, after: updated.approval.label);
    }
    if (change.payment != null) {
      _log(t.organizationId, change.payment == PaymentState.refunded ? 'Refunded payment' : 'Changed payment', e.name,
          before: e.payment.label, after: updated.payment.label);
    }
    if (change.categoryId != null) {
      _log(t.organizationId, 'Moved category', e.name,
          before: t.category(e.categoryId)?.title, after: t.category(change.categoryId!)?.title);
    }
    _emit(TmsEventType.entries, t.organizationId, tournamentId: t.id);
    return updated;
  }

  @override
  Future<Entry> checkInByCode(String tournamentId, String code) async {
    await _wait();
    final t = _t(tournamentId);
    if (!t.checkInOpen) throw const ApiException('CHECK_IN_CLOSED', 'Check-in is closed. Open it first.');
    final wanted = code.trim().toUpperCase();
    final e = _entriesOf(tournamentId).where((e) => e.checkInCode == wanted).firstOrNull;
    if (e == null) throw const ApiException('CODE_NOT_FOUND', 'No player with that code in this tournament.');
    if (e.approval != Approval.approved) {
      throw ApiException('NOT_APPROVED', '${e.name} is ${e.approval.label.toLowerCase()}, not in the draw.');
    }
    if (e.attendance == Attendance.checkedIn) return e;
    final updated = e.copyWith(attendance: Attendance.checkedIn);
    _entries[e.id] = updated;
    _emit(TmsEventType.entries, t.organizationId, tournamentId: tournamentId);
    return updated;
  }

  @override
  Future<int> checkInAll(String tournamentId) async {
    await _wait();
    final t = _t(tournamentId);
    _require(t, TmsAction.checkIn);
    var n = 0;
    for (final e in _entriesOf(tournamentId).toList()) {
      if (e.approval == Approval.approved && e.attendance != Attendance.checkedIn) {
        _entries[e.id] = e.copyWith(attendance: Attendance.checkedIn);
        n++;
      }
    }
    _log(t.organizationId, 'Checked in everyone', t.name, after: '$n entries');
    _emit(TmsEventType.entries, t.organizationId, tournamentId: tournamentId);
    return n;
  }

  @override
  Future<DrawLayout> generateDraw(String tournamentId, String categoryId, DrawMethod method) async {
    await _wait(2);
    final t = _t(tournamentId);
    _require(t, TmsAction.generateDraw);
    final c = t.category(categoryId)!;
    final approved = _entriesOf(tournamentId).where((e) => e.categoryId == categoryId && e.inDraw).toList();
    if (approved.length < 2) {
      throw const ApiException('TOO_FEW_ENTRIES', 'A draw needs at least 2 approved entries.');
    }
    final layout = _storeDraw(t, c, method, approved);
    _log(t.organizationId, 'Generated draw', c.title, after: '${method.label}, ${approved.length} entries');
    _tournaments[tournamentId] = t.copyWith(
      status: TournamentLifecycle.after(t.status, TmsAction.generateDraw),
      publishedDraws: {...t.publishedDraws}..remove(categoryId),
    );
    _emit(TmsEventType.draw, t.organizationId, tournamentId: tournamentId);
    _emit(TmsEventType.tournament, t.organizationId, tournamentId: tournamentId);
    return layout;
  }

  /// Makes and stores the draw and its matches, replacing any before it.
  DrawLayout _storeDraw(OrgTournament t, OrgCategory c, DrawMethod method, List<Entry> entries, [Random? random]) {
    final layout = engine.generateDraw(
      categoryId: c.id,
      format: c.drawFormat,
      method: method,
      entries: entries,
      random: random,
    );
    _draws[(t.id, c.id)] = layout;
    _rebuildMatches(t, layout);
    return layout;
  }

  void _rebuildMatches(OrgTournament t, DrawLayout layout, {bool keepTimes = false}) {
    final old = {for (final m in _matchesOf(t.id).where((m) => m.categoryId == layout.categoryId)) m.id: m};
    _matches.removeWhere((_, m) => m.tournamentId == t.id && m.categoryId == layout.categoryId);
    final first = keepTimes && old.isNotEmpty
        ? old.values.where((m) => m.number > 0).map((m) => m.number).fold(1 << 30, min)
        : _matchesOf(t.id).map((m) => m.number).fold(0, max) + 1;
    for (final m in buildMatches(layout: layout, tournamentId: t.id, labelOf: _labelOf, firstNumber: first)) {
      final before = old[m.id];
      _matches[m.id] = keepTimes && before != null && !m.isBye
          ? m.copyWith(
              courtId: () => before.courtId,
              scheduledAt: () => before.scheduledAt,
              state: before.state == MatchState.scheduled ? MatchState.scheduled : null,
            )
          : m;
    }
  }

  @override
  Future<DrawLayout> swapInDraw(String tournamentId, String categoryId, String entryA, String entryB) async {
    await _wait();
    final t = _t(tournamentId);
    final layout = _draws[(tournamentId, categoryId)];
    if (layout == null) throw const ApiException('NO_DRAW', 'Generate the draw first.');
    final started = _matchesOf(tournamentId)
        .any((m) => m.categoryId == categoryId && !m.isBye && m.state.index >= MatchState.called.index);
    if (started) throw const ApiException('DRAW_LOCKED', 'Matches in this draw have started. It is locked.');
    final swapped = engine.swapInDraw(layout, entryA, entryB);
    _draws[(tournamentId, categoryId)] = swapped;
    _rebuildMatches(t, swapped, keepTimes: true);
    _log(t.organizationId, 'Swapped in draw', t.category(categoryId)!.title,
        before: _labelOf(entryA), after: _labelOf(entryB));
    _emit(TmsEventType.draw, t.organizationId, tournamentId: tournamentId);
    return swapped;
  }

  @override
  Future<void> publishDraw(String tournamentId, String categoryId) async {
    await _wait();
    final t = _t(tournamentId);
    _require(t, TmsAction.publishDraw);
    if (_draws[(tournamentId, categoryId)] == null) throw const ApiException('NO_DRAW', 'Generate the draw first.');
    _tournaments[tournamentId] = t.copyWith(publishedDraws: {...t.publishedDraws, categoryId});
    _log(t.organizationId, 'Published draw', t.category(categoryId)!.title);
    _emit(TmsEventType.tournament, t.organizationId, tournamentId: tournamentId);
  }

  @override
  Future<List<TmsMatch>> generateSchedule(String tournamentId, ScheduleSettings settings) async {
    await _wait(2);
    final t = _t(tournamentId);
    _require(t, TmsAction.generateSchedule);
    if (_matchesOf(tournamentId).isEmpty) throw const ApiException('NO_DRAW', 'Generate at least one draw first.');
    _applySchedule(t, settings);
    _tournaments[tournamentId] = t.copyWith(status: TournamentLifecycle.after(t.status, TmsAction.generateSchedule));
    _log(t.organizationId, 'Generated schedule', t.name,
        after: '${settings.courtIds.length} courts, ${settings.matchMinutes} min matches');
    _emit(TmsEventType.matches, t.organizationId, tournamentId: tournamentId);
    _emit(TmsEventType.tournament, t.organizationId, tournamentId: tournamentId);
    return matches(tournamentId);
  }

  void _applySchedule(OrgTournament t, ScheduleSettings settings) {
    final slots = buildSchedule(
      matches: _matchesOf(t.id).toList(),
      settings: settings,
      playersOf: (id) => [for (final p in _entries[id]?.players ?? const <PlayerRef>[]) p.id],
    );
    for (final s in slots) {
      _matches[s.matchId] = _matches[s.matchId]!
          .copyWith(courtId: () => s.courtId, scheduledAt: () => s.start, state: MatchState.scheduled);
    }
  }

  @override
  Future<TmsCourt> updateCourt(String courtId, {String? name, CourtMode? mode, String? note}) async {
    await _wait();
    final c = _courts[courtId];
    if (c == null) throw const ApiException('NOT_FOUND', 'This court is no longer available.');
    final t = _t(c.tournamentId);
    _require(t, TmsAction.manageCourts);
    final updated = c.copyWith(name: name, mode: mode, note: mode == null ? null : () => note);
    _courts[courtId] = updated;
    _log(t.organizationId, 'Changed court', c.name,
        before: name != null ? c.name : c.mode.label, after: name ?? updated.mode.label);
    _emit(TmsEventType.courts, t.organizationId, tournamentId: t.id);
    return updated;
  }

  @override
  Future<TmsMatch> moveMatch(String matchId, String courtId) async {
    await _wait();
    final m = _m(matchId);
    final t = _t(m.tournamentId);
    _require(t, TmsAction.manageCourts);
    if (m.state == MatchState.completed || m.state == MatchState.live) {
      throw const ApiException('MATCH_STATE', 'A match can move courts only before it starts.');
    }
    final updated = m.copyWith(courtId: () => courtId);
    _matches[matchId] = updated;
    _log(t.organizationId, 'Moved match', 'Match ${m.number}',
        before: _courts[m.courtId]?.name, after: _courts[courtId]?.name);
    _emit(TmsEventType.matches, t.organizationId, tournamentId: t.id, matchId: matchId);
    return updated;
  }

  @override
  Future<TmsMatch> command(String matchId, MatchCommand command) async {
    await _wait();
    final m = _m(matchId);
    final t = _t(m.tournamentId);
    if (t.status != TournamentStatus.live) {
      throw const ApiException('TOURNAMENT_STATE', 'Start the tournament before running matches.');
    }
    final now = _clock();
    final TmsMatch updated = switch (command) {
      MatchCommand.call when m.ready && (m.state == MatchState.scheduled || m.state == MatchState.pending) =>
        m.copyWith(state: MatchState.called),
      MatchCommand.start
          when m.ready &&
              (m.state == MatchState.pending || m.state == MatchState.scheduled || m.state == MatchState.called) =>
        m.copyWith(
          state: MatchState.live,
          startedAt: () => now,
          games: m.games.isEmpty ? const [GameScore.zero] : null,
          serve: () => m.serve ?? _engineFor(m).start(_setup(m)).serve,
        ),
      MatchCommand.pause when m.state == MatchState.live => m.copyWith(state: MatchState.paused),
      MatchCommand.resume when m.state == MatchState.paused => m.copyWith(state: MatchState.live),
      _ => throw ApiException('MATCH_STATE', _commandRefusal(m, command)),
    };
    if (m.courtId == null && command != MatchCommand.pause && command != MatchCommand.resume) {
      throw const ApiException('NO_COURT', 'Put the match on a court first.');
    }
    _matches[matchId] = updated;
    _emit(TmsEventType.matches, t.organizationId, tournamentId: t.id, matchId: matchId);
    return updated;
  }

  static String _commandRefusal(TmsMatch m, MatchCommand c) {
    if (!m.ready) return 'Both sides must be known before the match can be ${c == MatchCommand.call ? 'called' : 'started'}.';
    return 'Match ${m.number} is ${m.state.label.toLowerCase()}.';
  }

  ScoringEngine _engineFor(TmsMatch m) => SportRegistry.standard.of('pickleball')!.engine;

  @override
  Future<ScoreLog> scoreLog(String matchId) async {
    await _wait();
    final m = _m(matchId);
    return ScoreLog(m.scoreVersion, List.of(_rallies[matchId] ?? const []));
  }

  @override
  Future<TmsMatch> score(String matchId, ScoreWrite write) async {
    await _wait();
    final m = _m(matchId);
    final seen = _acks[matchId] ??= {};
    // A resend of a write already applied: answer with the current state.
    if (seen.contains(write.clientEventId)) return m;
    if (m.state != MatchState.live) {
      throw ApiException('MATCH_STATE', 'Match ${m.number} is ${m.state.label.toLowerCase()}, not live.');
    }
    if (write.baseVersion != m.scoreVersion) {
      throw const ApiException(scoreConflict, 'The score changed on another device.');
    }
    final setup = _setup(m);
    final engine = _engineFor(m);
    final rallies = _rallies[matchId] ??= [];
    switch (write.kind) {
      case ScoreWriteKind.rally:
        if (m.winner != null) throw const ApiException('MATCH_DECIDED', 'The match is decided. Confirm the result.');
        rallies.add(RallyWon(write.side!));
      case ScoreWriteKind.serve:
        rallies.add(ServeCorrected(write.serve!));
      case ScoreWriteKind.undo:
        if (rallies.isEmpty) throw const ApiException('NOTHING_TO_UNDO', 'There is nothing to undo.');
        rallies.removeLast();
    }
    final state = engine.replay(setup, rallies);
    seen.add(write.clientEventId);
    final updated = m.copyWith(
      games: state.games,
      serve: () => state.serve,
      winner: () => state.winner,
      scoreVersion: m.scoreVersion + 1,
    );
    _matches[matchId] = updated;
    _emit(TmsEventType.score, _t(m.tournamentId).organizationId, tournamentId: m.tournamentId, matchId: matchId);
    return updated;
  }

  @override
  Future<TmsMatch> confirmResult(String matchId, int version) async {
    await _wait();
    final m = _m(matchId);
    if (m.scoreVersion != version) throw const ApiException(scoreConflict, 'The score changed on another device.');
    if (m.winner == null) throw const ApiException('MATCH_NOT_DECIDED', 'Nobody has won yet.');
    return _finish(m, m.games, m.winner!, 'Confirmed result');
  }

  @override
  Future<TmsMatch> enterResult(String matchId, List<GameScore> games, {required String reason}) async {
    await _wait();
    final m = _m(matchId);
    final t = _t(m.tournamentId);
    if (m.state == MatchState.completed && !t.can(TmsAction.correctResults) && t.status != TournamentStatus.live) {
      throw const ApiException('RESULT_LOCKED', 'Results are locked for this tournament.');
    }
    if (!m.ready) throw const ApiException('MATCH_STATE', 'Both sides must be known before a result.');
    final problem = validateResult(t.category(m.categoryId)!.rules, games);
    if (problem != null) throw ApiException('INVALID_RESULT', problem);
    final wonA = games.where((g) => g.a > g.b).length;
    final wonB = games.length - wonA;
    final winner = wonA > wonB ? Side.a : Side.b;
    if (m.state == MatchState.completed && m.winner != winner) {
      final next = _matchesOf(t.id).where((n) => n.sourceA == m.id || n.sourceB == m.id).firstOrNull;
      if (next != null && next.state != MatchState.pending && next.state != MatchState.scheduled) {
        throw const ApiException('RESULT_LOCKED', 'The next round has started, so the winner cannot change.');
      }
    }
    _rallies.remove(matchId);
    return _finish(m, games, winner, m.state == MatchState.completed ? 'Corrected result' : 'Entered result',
        reason: reason);
  }

  TmsMatch _finish(TmsMatch m, List<GameScore> games, Side winner, String action, {String? reason, bool log = true}) {
    final t = _t(m.tournamentId);
    final updated = m.copyWith(
      state: MatchState.completed,
      games: games,
      winner: () => winner,
      completedAt: () => m.completedAt ?? _clock(),
      startedAt: () => m.startedAt ?? _clock(),
      scoreVersion: m.scoreVersion + 1,
    );
    _matches[m.id] = updated;
    final next = advanceWinner(updated, _matchesOf(t.id).toList(), _labelOf);
    if (next != null) _matches[next.id] = next;
    if (log) {
      _log(t.organizationId, action, 'Match ${m.number} · ${m.labelA} v ${m.labelB}',
          before: m.games.isEmpty || action == 'Confirmed result' ? null : m.scoreLine,
          after: '${updated.scoreLine}${reason == null ? '' : ' ($reason)'}');
    }
    _emit(TmsEventType.matches, t.organizationId, tournamentId: t.id, matchId: m.id);
    return updated;
  }

  @override
  Future<Announcement> announce(
    String tournamentId, {
    required AnnouncementKind kind,
    required Audience audience,
    required String message,
    String? target,
    bool push = true,
  }) async {
    await _wait();
    final t = _t(tournamentId);
    _require(t, TmsAction.announce);
    if (message.trim().isEmpty) throw const ApiException('VALIDATION', 'Write the message first.');
    final approved = _entriesOf(tournamentId).where((e) => e.approval == Approval.approved);
    final recipients = switch (audience) {
      Audience.everyone => approved.fold(0, (n, e) => n + e.players.length),
      Audience.category => approved.where((e) => e.categoryId == target).fold(0, (n, e) => n + e.players.length),
      Audience.court => 4,
      Audience.player => 1,
    };
    final a = Announcement(
      id: _id('an'),
      tournamentId: tournamentId,
      kind: kind,
      audience: audience,
      targetLabel: switch (audience) {
        Audience.category => t.category(target ?? '')?.title,
        Audience.court => _courts[target]?.name,
        _ => target,
      },
      message: message.trim(),
      sentAt: _clock(),
      sentBy: actor,
      recipients: recipients,
      push: push,
    );
    _announcements.insert(0, a);
    _log(t.organizationId, 'Sent announcement', a.kind.label, after: '$recipients players');
    _emit(TmsEventType.announcement, t.organizationId, tournamentId: tournamentId);
    return a;
  }

  // ------------------------------------------------ the player's side

  /// Published tournaments as players see them in discovery.
  List<player.Tournament> playerTournaments() => [
        for (final t in _tournaments.values)
          if (t.status.isActive || t.status == TournamentStatus.completed) _asPlayerTournament(t),
      ];

  bool owns(String tournamentId) => _tournaments.containsKey(tournamentId);

  player.Tournament? playerTournament(String id) {
    final t = _tournaments[id];
    return t == null ? null : _asPlayerTournament(t);
  }

  player.Tournament _asPlayerTournament(OrgTournament t) => player.Tournament(
        id: t.id,
        name: t.name,
        organizer: 'SkorX Organiser',
        organizerVerified: true,
        city: t.city,
        venue: t.venue,
        start: t.start,
        end: t.end,
        registrationDeadline:
            t.status == TournamentStatus.registrationOpen ? t.registrationCloses : t.registrationOpens.subtract(const Duration(days: 1)),
        format: t.categories.map((c) => c.drawFormat.label).toSet().join(', '),
        categories: [
          for (final c in t.categories)
            player.TournamentCategory(
              id: c.id,
              name: c.name,
              format: c.format,
              level: c.level,
              fee: c.fee,
              capacity: c.capacity,
              registered: _entriesOf(t.id).where((e) => e.categoryId == c.id && e.approval != Approval.rejected).length,
            ),
        ],
      );

  /// `POST /tournaments/:id/registrations` from the Player app: the entry
  /// lands in the organiser's queue as pending and unpaid.
  Entry registerPlayer(String tournamentId, String categoryId, {required String playerName, String? partner}) {
    final t = _t(tournamentId);
    if (t.status != TournamentStatus.registrationOpen) {
      throw const ApiException('REGISTRATION_CLOSED', 'Registration for this tournament is closed.');
    }
    final c = t.category(categoryId)!;
    final e = Entry(
      id: _id('e'),
      tournamentId: tournamentId,
      categoryId: categoryId,
      players: [
        PlayerRef(id: 'me', name: playerName.isEmpty ? 'SkorX player' : playerName, rating: 48.0, city: t.city),
        if (partner != null && partner.trim().isNotEmpty) PlayerRef(id: _id('p'), name: partner.trim()),
      ],
      registeredAt: _clock(),
      amount: c.fee,
      // The player paid at checkout; the organiser still approves.
      payment: c.fee == 0 ? PaymentState.waived : PaymentState.paid,
      checkInCode: _code(),
    );
    _entries[e.id] = e;
    _log(t.organizationId, 'New registration', e.name, after: c.title);
    _emit(TmsEventType.entries, t.organizationId, tournamentId: tournamentId);
    return e;
  }

  final _codes = <String>{};
  final _codeRandom = Random(7919);

  /// A short ticket code, unique across the store.
  String _code() {
    const letters = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    while (true) {
      final code = List.generate(5, (_) => letters[_codeRandom.nextInt(letters.length)]).join();
      if (_codes.add(code)) return code;
    }
  }

  // ------------------------------------------------------------- seeding

  /// [t], or an hour before [now] if [t] has not happened yet.
  static DateTime _earlier(DateTime t, DateTime now) {
    final latest = now.subtract(const Duration(hours: 1));
    return t.isAfter(latest) ? latest.subtract(Duration(minutes: t.minute)) : t;
  }

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  static const _venues = [
    Venue(id: 'v1', name: 'Smash Arena', address: 'SG Highway, Ahmedabad', courts: 8, indoor: true,
        amenities: ['Parking', 'Cafe', 'Changing rooms', 'Live stream rig']),
    Venue(id: 'v2', name: 'CADLETE Club', address: 'Bodakdev, Ahmedabad', courts: 6, indoor: true,
        amenities: ['Parking', 'Pro shop']),
    Venue(id: 'v3', name: 'Pickle Blitz Arena', address: 'Prahlad Nagar, Ahmedabad', courts: 4, indoor: false,
        amenities: ['Floodlights', 'Parking']),
    Venue(id: 'v4', name: 'Diamond Sports Hub', address: 'Vesu, Surat', courts: 10, indoor: true,
        amenities: ['Parking', 'Cafe', 'Physio']),
    Venue(id: 'v5', name: 'Sayaji Sports Complex', address: 'Sayajigunj, Vadodara', courts: 6, indoor: false,
        amenities: ['Parking']),
  ];

  static const _sponsors = [
    Sponsor(name: 'Joola India', package: 'Title', amount: 150000, paid: true,
        placements: ['Tournament page', 'Scoreboard', 'Stream overlay']),
    Sponsor(name: 'Gatorade', package: 'Hydration partner', amount: 40000, paid: true,
        placements: ['Scoreboard', 'Player messages']),
    Sponsor(name: 'Decathlon Ahmedabad', package: 'Court partner', amount: 25000, paid: false,
        placements: ['Court banners']),
  ];

  static const _first = [
    'Aarav', 'Vihaan', 'Arjun', 'Kabir', 'Dev', 'Rohan', 'Ishaan', 'Aditya', 'Krish', 'Harsh', 'Yash', 'Karan',
    'Nikhil', 'Rahul', 'Siddharth', 'Varun', 'Aman', 'Parth', 'Jay', 'Meet', 'Dhruv', 'Kunal', 'Manav', 'Om',
    'Ananya', 'Diya', 'Riya', 'Isha', 'Priya', 'Neha', 'Kavya', 'Saanvi', 'Aditi', 'Meera', 'Pooja', 'Sneha',
    'Tanvi', 'Nisha', 'Khushi', 'Janvi', 'Ishita', 'Mansi', 'Zoya', 'Aisha',
  ];
  static const _last = [
    'Shah', 'Patel', 'Mehta', 'Desai', 'Joshi', 'Parmar', 'Rao', 'Nair', 'Iyer', 'Kapoor', 'Trivedi', 'Bhatt',
    'Chauhan', 'Solanki', 'Pandya', 'Vora', 'Gandhi', 'Modi', 'Sheth', 'Jain',
  ];

  List<PlayerRef> _players(Random r, int n, {bool? women}) {
    final firsts = women == null ? _first : (women ? _first.sublist(24) : _first.sublist(0, 24));
    final used = <String>{};
    final out = <PlayerRef>[];
    while (out.length < n) {
      final name = '${firsts[r.nextInt(firsts.length)]} ${_last[r.nextInt(_last.length)]}';
      if (!used.add(name)) continue;
      out.add(PlayerRef(id: 'p-${name.toLowerCase().replaceAll(' ', '-')}', name: name,
          rating: 30 + r.nextInt(500) / 10, city: 'Ahmedabad'));
    }
    return out;
  }

  void _ensureSeeded(String orgId) {
    if (!_seeded.add(orgId)) return;
    final now = _clock();
    final today = DateTime(now.year, now.month, now.day);
    DateTime day(int d, [int hour = 8, int minute = 0]) => DateTime(today.year, today.month, today.day + d, hour, minute);
    final r = Random(orgId.hashCode);
    const standard = MatchRules(pointsToWin: 11, winByTwo: true, bestOf: 1, scoring: ScoringSystem.sideOut);
    const finals = MatchRules(pointsToWin: 11, winByTwo: true, bestOf: 3, scoring: ScoringSystem.sideOut);

    OrgCategory cat(String tid, String key, String name, PlayCategory f, String level, DrawFormat d, int fee, int cap,
            [MatchRules rules = standard]) =>
        OrgCategory(id: '$tid-$key', name: name, format: f, level: level, drawFormat: d, fee: fee, capacity: cap, rules: rules);

    void addEntries(OrgTournament t, OrgCategory c, int n,
        {double approved = 1, double paid = 1, double checkedIn = 0, bool? women, bool seed = true}) {
      final mixed = c.format == PlayCategory.mixed;
      final people = mixed ? _players(r, n, women: false) : _players(r, n * c.playersPerSide, women: women);
      final partners = mixed ? _players(r, n, women: true) : const <PlayerRef>[];
      for (var i = 0; i < n; i++) {
        final players =
            mixed ? [people[i], partners[i]] : people.sublist(i * c.playersPerSide, (i + 1) * c.playersPerSide);
        final isApproved = r.nextDouble() < approved;
        final e = Entry(
          id: _id('e'),
          tournamentId: t.id,
          categoryId: c.id,
          players: players,
          registeredAt: _earlier(t.registrationOpens.add(Duration(hours: 6 + r.nextInt(24 * 10))), now),
          amount: c.fee,
          approval: isApproved ? Approval.approved : (i.isEven ? Approval.pending : Approval.waitlisted),
          payment: r.nextDouble() < paid ? PaymentState.paid : PaymentState.pending,
          attendance: isApproved && r.nextDouble() < checkedIn ? Attendance.checkedIn : Attendance.notArrived,
          checkInCode: _code(),
        );
        _entries[e.id] = e;
      }
      if (seed) {
        final ranked = seedOrder(_entriesOf(t.id).where((e) => e.categoryId == c.id && e.inDraw)).take(4).toList();
        for (final (i, e) in ranked.indexed) {
          _entries[e.id] = e.copyWith(seed: () => i + 1);
        }
      }
    }

    void addCourts(OrgTournament t, int n) {
      for (var i = 1; i <= n; i++) {
        _courts['${t.id}-court$i'] = TmsCourt(id: '${t.id}-court$i', tournamentId: t.id, name: 'Court ${i.toString().padLeft(2, '0')}');
      }
    }

    // 1. Live today: the control room's tournament.
    const liveId = 't-summer';
    final live = OrgTournament(
      id: liveId,
      organizationId: orgId,
      name: 'SkorX Summer Open 2026',
      description: 'Three categories over one day on eight indoor courts, live scored and streamed.',
      status: TournamentStatus.live,
      venue: 'Smash Arena',
      city: 'Ahmedabad',
      start: day(0, 8),
      end: day(0, 21),
      registrationOpens: day(-30),
      registrationCloses: day(-3, 23),
      checkInOpen: true,
      streaming: true,
      categories: [
        cat(liveId, 'md', "Men's Doubles", PlayCategory.doubles, 'Intermediate', DrawFormat.knockout, 800, 16),
        cat(liveId, 'xd', 'Mixed Doubles', PlayCategory.mixed, 'Open', DrawFormat.pools, 900, 8),
        cat(liveId, 'ws', "Women's Singles", PlayCategory.singles, 'Advanced', DrawFormat.knockout, 600, 8, finals),
      ],
    );
    _tournaments[liveId] = live;
    addCourts(live, 8);
    addEntries(live, live.categories[0], 16, checkedIn: 0.95);
    addEntries(live, live.categories[1], 8, checkedIn: 1);
    addEntries(live, live.categories[2], 8, checkedIn: 0.9, women: true);
    for (final c in live.categories) {
      _storeDraw(live, c, DrawMethod.seeded, _entriesOf(liveId).where((e) => e.categoryId == c.id).toList(), r);
    }
    _tournaments[liveId] = live.copyWith(publishedDraws: {for (final c in live.categories) c.id});
    final courtIds = [for (var i = 1; i <= 8; i++) '$liveId-court$i'];
    // Started a couple of hours ago, so some matches are done and some live.
    final start = now.subtract(const Duration(minutes: 115));
    _applySchedule(
      live,
      ScheduleSettings(
        start: DateTime(start.year, start.month, start.day, start.hour, start.minute - start.minute % 5),
        courtIds: courtIds,
        matchMinutes: 20,
        bufferMinutes: 5,
        categoryOrder: [for (final c in live.categories) c.id],
      ),
    );
    _playUntil(live, now, r);
    _courts['$liveId-court8'] = _courts['$liveId-court8']!.copyWith(mode: CourtMode.onBreak, note: () => 'Back at ${_clockLabel(now.add(const Duration(minutes: 20)))}');

    // 2. Registration open: approvals and payments to chase.
    const openId = 't-night';
    final open = OrgTournament(
      id: openId,
      organizationId: orgId,
      name: 'Ahmedabad Night Smash',
      description: 'Floodlit doubles under the stars. Round robin, then knockout.',
      status: TournamentStatus.registrationOpen,
      venue: 'Pickle Blitz Arena',
      city: 'Ahmedabad',
      indoor: false,
      start: day(10, 18),
      end: day(10, 23),
      registrationOpens: day(-8),
      registrationCloses: day(7, 23),
      earlyBirdDiscount: 100,
      categories: [
        cat(openId, 'od', 'Open Doubles', PlayCategory.doubles, 'Beginner', DrawFormat.roundRobin, 500, 24),
        cat(openId, 'xd', 'Mixed Doubles', PlayCategory.mixed, 'Intermediate', DrawFormat.knockout, 600, 16),
      ],
    );
    _tournaments[openId] = open;
    addCourts(open, 4);
    addEntries(open, open.categories[0], 14, approved: 0.6, paid: 0.7, seed: false);
    addEntries(open, open.categories[1], 9, approved: 0.7, paid: 0.8, seed: false);

    // 3. Registration closed: next step is the draw.
    const closedId = 't-league';
    final closed = OrgTournament(
      id: closedId,
      organizationId: orgId,
      name: 'Monsoon Doubles League',
      description: 'Club league for intermediate doubles.',
      status: TournamentStatus.registrationClosed,
      venue: 'CADLETE Club',
      city: 'Ahmedabad',
      start: day(3, 9),
      end: day(4, 19),
      registrationOpens: day(-25),
      registrationCloses: day(-1, 23),
      categories: [
        cat(closedId, 'md', "Men's Doubles", PlayCategory.doubles, 'Intermediate', DrawFormat.knockout, 700, 16),
        cat(closedId, 'wd', "Women's Doubles", PlayCategory.doubles, 'Intermediate', DrawFormat.roundRobin, 700, 6),
      ],
    );
    _tournaments[closedId] = closed;
    addCourts(closed, 6);
    addEntries(closed, closed.categories[0], 12, paid: 0.9);
    addEntries(closed, closed.categories[1], 5, women: true);

    // 4. Draft.
    const draftId = 't-diwali';
    _tournaments[draftId] = OrgTournament(
      id: draftId,
      organizationId: orgId,
      name: 'Diwali Pickle Fest',
      status: TournamentStatus.draft,
      venue: 'Smash Arena',
      city: 'Ahmedabad',
      start: day(34, 9),
      end: day(35, 20),
      registrationOpens: day(5),
      registrationCloses: day(30, 23),
      categories: [
        cat(draftId, 'xd', 'Mixed Doubles', PlayCategory.mixed, 'Open', DrawFormat.pools, 800, 32),
      ],
    );
    addCourts(_tournaments[draftId]!, 8);

    // 5. Completed, with results.
    const doneId = 't-spring';
    final done = OrgTournament(
      id: doneId,
      organizationId: orgId,
      name: 'CADLETE Spring Cup',
      status: TournamentStatus.live,
      venue: 'CADLETE Club',
      city: 'Ahmedabad',
      start: day(-58, 9),
      end: day(-57, 19),
      registrationOpens: day(-90),
      registrationCloses: day(-61),
      categories: [
        cat(doneId, 'ms', "Men's Singles", PlayCategory.singles, 'Open', DrawFormat.knockout, 500, 8),
      ],
    );
    _tournaments[doneId] = done;
    addCourts(done, 4);
    addEntries(done, done.categories.single, 8, checkedIn: 1, women: false);
    _storeDraw(done, done.categories.single, DrawMethod.seeded, _entriesOf(doneId).toList(), r);
    _applySchedule(done, ScheduleSettings(start: day(-58, 9), courtIds: ['$doneId-court1', '$doneId-court2']));
    _playUntil(done, day(-57, 23), r);
    _tournaments[doneId] = done.copyWith(status: TournamentStatus.completed, publishedDraws: {'$doneId-ms'});

    _expenses[liveId] = const [
      Expense(kind: ExpenseKind.venue, label: 'Smash Arena, 8 courts', amount: 48000, tournamentId: liveId),
      Expense(kind: ExpenseKind.officials, label: 'Referees and scorers', amount: 16000, tournamentId: liveId),
      Expense(kind: ExpenseKind.prizes, label: 'Trophies and medals', amount: 22000, tournamentId: liveId),
      Expense(kind: ExpenseKind.food, label: 'Player lunch', amount: 12500, tournamentId: liveId),
      Expense(kind: ExpenseKind.equipment, label: 'Balls and nets', amount: 6800, tournamentId: liveId),
      Expense(kind: ExpenseKind.marketing, label: 'Instagram promotion', amount: 5000, tournamentId: liveId),
    ];
    _expenses[doneId] = const [
      Expense(kind: ExpenseKind.venue, label: 'CADLETE Club, 4 courts', amount: 16000, tournamentId: doneId),
      Expense(kind: ExpenseKind.prizes, label: 'Trophies', amount: 7500, tournamentId: doneId),
    ];

    _announcements.addAll([
      Announcement(
        id: _id('an'),
        tournamentId: liveId,
        kind: AnnouncementKind.delay,
        audience: Audience.category,
        targetLabel: "Men's Doubles · Intermediate",
        message: "Men's Doubles quarter-finals are running 10 minutes late. Stay near your court.",
        sentAt: now.subtract(const Duration(minutes: 18)),
        sentBy: 'Kamal Parmar',
        recipients: 32,
      ),
      Announcement(
        id: _id('an'),
        tournamentId: liveId,
        kind: AnnouncementKind.general,
        audience: Audience.everyone,
        message: 'Welcome to the SkorX Summer Open! Lunch is served at the cafe from 12:30.',
        sentAt: now.subtract(const Duration(minutes: 125)),
        sentBy: 'Smit Ramani',
        recipients: 72,
      ),
    ]);

    actor = 'Kamal Parmar';
    _log(orgId, 'Generated schedule', live.name, after: '8 courts, 20 min matches');
    actor = 'Riya Shah';
    _log(orgId, 'Corrected result', 'Match 3', before: '11-7', after: '11-9 (scorer typo)');
    actor = 'Harsh Desai';
    _log(orgId, 'Refunded payment', 'Tanvi Joshi', before: 'Paid', after: 'Refunded');
    actor = 'You';
  }

  static String _clockLabel(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  /// Plays the schedule forward to [now]: finished slots get a real result
  /// from the scoring engine; the slot in progress is live mid-game; the
  /// first slot after a late one is called but not started (delayed).
  void _playUntil(OrgTournament t, DateTime now, Random r) {
    var delayedLeft = 1;
    for (var pass = 0; pass < 8; pass++) {
      final todo = _matchesOf(t.id).where((m) => m.state == MatchState.scheduled && m.scheduledAt != null).toList()
        ..sort((a, b) => a.scheduledAt!.compareTo(b.scheduledAt!));
      var changed = false;
      for (final m in todo) {
        final current = _matches[m.id]!;
        if (!current.ready) continue;
        final start = current.scheduledAt!;
        final end = start.add(const Duration(minutes: 20));
        if (!end.isAfter(now)) {
          final setup = _setup(current);
          final engine = _engineFor(current);
          var state = engine.start(setup);
          final bias = r.nextDouble() * 0.3 + 0.35;
          while (!state.isOver) {
            state = engine.rally(setup, state, r.nextDouble() < bias ? Side.b : Side.a);
          }
          _matches[m.id] = current.copyWith(state: MatchState.live, startedAt: () => start);
          _finish(_matches[m.id]!.copyWith(games: state.games), state.games, state.winner!, 'Confirmed result', log: false);
          _matches[m.id] = _matches[m.id]!.copyWith(completedAt: () => end.subtract(Duration(minutes: r.nextInt(4))));
          changed = true;
        } else if (!start.isAfter(now)) {
          if (delayedLeft > 0 && now.difference(start) > const Duration(minutes: 11)) {
            delayedLeft--;
            _matches[m.id] = current.copyWith(state: MatchState.called);
            continue;
          }
          final setup = _setup(current);
          final engine = _engineFor(current);
          final rallies = <ScoringEvent>[];
          var state = engine.start(setup);
          final target = 8 + r.nextInt(14);
          while (rallies.length < target && !state.isOver) {
            final e = RallyWon(r.nextBool() ? Side.a : Side.b);
            final next = engine.rally(setup, state, e.side);
            if (next.isOver) break;
            rallies.add(e);
            state = next;
          }
          _rallies[m.id] = rallies;
          _matches[m.id] = current.copyWith(
            state: MatchState.live,
            startedAt: () => start,
            games: state.games,
            serve: () => state.serve,
            scoreVersion: rallies.length,
          );
        }
      }
      if (!changed) break;
    }
    // The next match on each free court is called to court.
    for (final slot in courtBoard(_courts.values.where((c) => c.tournamentId == t.id).toList(), _matchesOf(t.id).toList(), now)) {
      if (slot.current == null && slot.next != null && slot.next!.ready && slot.court.mode == CourtMode.open) {
        _matches[slot.next!.id] = slot.next!.copyWith(state: MatchState.called);
      }
    }
  }
}
