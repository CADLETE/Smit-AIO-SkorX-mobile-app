import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../sports/core/match_rules.dart';
import '../../sports/core/score_state.dart';
import '../../sports/core/scoring_engine.dart';
import '../auth/auth_controller.dart';
import '../auth/data/current_user.dart';
import 'data/match_code.dart';
import 'data/match_setup.dart';
import 'handover/scoring_handover.dart';
import 'local_match.dart';
import 'offline/match_store.dart';
import 'played_matches.dart';
import 'verification/verification_controller.dart';

/// What a player chose on the create-match screen.
class NewMatch {
  const NewMatch({
    required this.sportId,
    required this.categoryId,
    required this.sideA,
    required this.sideB,
    required this.rules,
    required this.firstServer,
    this.locationName,
    this.details = const MatchDetails(),
  });

  final String sportId;
  final String categoryId;
  final List<String> sideA;
  final List<String> sideB;
  final MatchRules rules;
  final Side firstServer;
  final String? locationName;
  final MatchDetails details;
}

/// The signed-in player as a scorer from the start of [match].
ScorerShift? _profileScorer(LocalMatch match, CurrentUser? user) => user == null
    ? null
    : ScorerShift(name: user.name.trim().isEmpty ? 'You' : user.name.trim(), playerId: user.id, fromEvent: 0, at: match.startedAt);

/// Who scored [match]. A match saved before scorers were recorded credits the
/// signed-in player's profile name, so there is always a name to show.
List<ScorerShift> scorersOf(LocalMatch match, CurrentUser? user) {
  if (match.scorers.isNotEmpty) return match.scorers;
  final me = _profileScorer(match, user);
  return me == null ? const [] : [me];
}

final scoringControllerProvider = NotifierProvider<ScoringController, LocalMatch?>(ScoringController.new);

/// The casual match being scored on this phone, if any. Every change is
/// written to the phone before the screen updates, so closing the app, a
/// crash or a flat battery never loses a point.
class ScoringController extends Notifier<LocalMatch?> {
  static const _uuid = Uuid();

  /// Resolves once the saved match (if any) has been read.
  late final Future<void> ready;

  @override
  LocalMatch? build() {
    ready = _restore().then((_) => _creditProfile(ref.read(currentUserProvider)));
    // Sign-in can finish after the match loads: credit the profile then.
    ref.listen(currentUserProvider, (_, user) => _creditProfile(user));
    // The new scorer's answer to a handover this phone sent.
    final answers = ref.read(scoringHandoverServiceProvider).answers.listen((a) => _answered(a.$1, a.$2));
    ref.onDispose(answers.cancel);
    return null;
  }

  /// Asks another SkorX player to take over scoring on their own phone.
  /// Scoring pauses here until they answer.
  Future<void> requestHandover(String name, String playerId) async {
    final match = state;
    if (match == null || match.isOver || match.awaitingHandover) return;
    final from = scorersOf(match, ref.read(currentUserProvider));
    final request = ScoringHandover(
      toName: name.trim(),
      toPlayerId: playerId,
      fromName: from.isEmpty ? 'The scorer' : from.last.name,
      requestedAt: DateTime.now(),
    );
    final pending = match.copyWith(handover: request);
    await _save(pending);
    await ref.read(scoringHandoverServiceProvider).send(pending, request);
  }

  /// Withdraws the request; scoring carries on here.
  Future<void> cancelHandover() async {
    final match = state;
    if (match == null || !match.awaitingHandover) return;
    await ref.read(scoringHandoverServiceProvider).cancel(match.id);
    await _save(match.copyWith(clearHandover: true));
  }

  Future<void> _answered(String matchId, HandoverAnswer answer) async {
    if (!ref.mounted) return;
    final match = state;
    final request = match?.handover;
    if (match == null || match.id != matchId || request == null) return;
    if (answer == HandoverAnswer.declined) {
      lastDeclined = request.toName;
      await _save(match.copyWith(clearHandover: true));
      return;
    }
    final shift = ScorerShift(name: request.toName, playerId: request.toPlayerId, fromEvent: match.events.length, at: DateTime.now());
    await _save(match.copyWith(clearHandover: true, scorers: [...scorersOf(match, ref.read(currentUserProvider)), shift]));
  }

  /// Who last turned down a handover, for the screen to say so.
  String? lastDeclined;

  /// This player accepted scoring a match sent from another phone: it
  /// becomes the match on this phone, carrying on exactly where it was.
  Future<void> adoptHandedOver(LocalMatch match) async {
    final request = match.handover;
    if (request == null) return;
    final shift = ScorerShift(name: request.toName, playerId: request.toPlayerId, fromEvent: match.events.length, at: DateTime.now());
    await _save(match.copyWith(clearHandover: true, scorers: [...match.scorers, shift]));
  }

  /// Gives a match with no recorded scorer the signed-in player's name.
  Future<void> _creditProfile(CurrentUser? user) async {
    if (!ref.mounted) return;
    final match = state;
    if (match == null || match.scorers.isNotEmpty) return;
    final me = _profileScorer(match, user);
    if (me != null) await _save(match.copyWith(scorers: [me]));
  }

  Future<void> _restore() async {
    // A saved match this version cannot read is set aside by the store
    // rather than blocking the app.
    final match = await ref.read(matchStoreProvider).readActive();
    if (match == null || !ref.mounted) return;
    state = match;
    // Finished before results were kept: add it now.
    if (match.isOver) await ref.read(playedMatchesProvider.notifier).record(match);
  }

  /// Conflict resolution ("Use SkorX's score"): the match carries on from
  /// SkorX's events instead of this phone's.
  Future<void> replaceEvents(List<RecordedEvent> events) async {
    final match = state;
    if (match == null) return;
    final next = match.copyWith(events: events, reopen: true);
    await _save(next.score.isOver ? next.copyWith(finishedAt: match.finishedAt ?? DateTime.now()) : next);
  }

  Future<void> start(NewMatch match) async {
    final now = DateTime.now();
    final category = parseCategoryId(match.categoryId);
    final format = category?.$1 ?? (match.sideA.length == 1 ? MatchFormat.singles : MatchFormat.doubles);
    final code = MatchCode.generate(
      sport: match.sportId,
      context: MatchContext.casual,
      format: format,
      division: category?.$2 ?? match.details.division ?? Division.open,
      at: now,
    );
    final user = ref.read(currentUserProvider);
    final first = user == null ? null : ScorerShift(name: user.name.trim().isEmpty ? 'You' : user.name.trim(), playerId: user.id, fromEvent: 0, at: now);
    await _save(LocalMatch(
      id: _uuid.v4(),
      code: code.toString(),
      scorers: [?first],
      sportId: match.sportId,
      categoryId: match.categoryId,
      sideA: match.sideA,
      sideB: match.sideB,
      rules: match.rules,
      firstServer: match.firstServer,
      locationName: match.locationName,
      details: match.details,
      startedAt: now,
    ));
    // SkorX asks the other players to confirm straight away. Scoring never
    // waits for it: offline, it is sent later.
    final started = state;
    if (started != null) unawaited(ref.read(casualSyncProvider.notifier).track(started));
    // Who played is remembered, so the next match can be set up offline.
    unawaited(ref.read(knownPlayersProvider.notifier).remember([
      for (final (names, ids) in [(match.sideA, match.details.sideAIds), (match.sideB, match.details.sideBIds)])
        for (final (i, name) in names.indexed)
          if (i < ids.length) MatchPlayer(id: ids[i], name: name),
    ]));
  }

  /// Someone else takes over scoring on this phone. The match carries on
  /// exactly where it is; the result credits every scorer.
  Future<void> changeScorer(String name, {String? playerId}) async {
    final match = state;
    if (match == null || match.isOver || name.trim().isEmpty) return;
    final shift = ScorerShift(name: name.trim(), playerId: playerId, fromEvent: match.events.length, at: DateTime.now());
    await _save(match.copyWith(scorers: [...scorersOf(match, ref.read(currentUserProvider)), shift]));
  }

  /// Corrects who stands where (see [CourtFix]). Undo takes it back.
  Future<void> adjustCourt(CourtFix fix) async {
    final match = state;
    if (match == null || match.isOver || match.isPaused || match.awaitingHandover) return;
    await _save(match.copyWith(adjustments: [...match.adjustments, CourtAdjustment(fix, match.events.length)]));
  }

  /// Records that [side] won the rally. Ignored once the match is over, so a
  /// late double tap cannot add a point to a finished match.
  Future<void> rallyWonBy(Side side) => _record(RallyWon(side));

  Future<void> correctServe(ServeState serve) => _record(ServeCorrected(serve));

  Future<void> _record(ScoringEvent event) async {
    final match = state;
    if (match == null || match.finishedAt != null || match.isOver || match.isPaused || match.awaitingHandover) return;
    // Between games, nothing is scored until the scorer confirms the ends.
    if (event is RallyWon && match.awaitingEndChange) return;
    final events = [...match.events, RecordedEvent(id: _uuid.v4(), event: event, recordedAt: DateTime.now())];
    final next = match.copyWith(events: events);
    await _save(next.score.isOver ? next.copyWith(finishedAt: DateTime.now()) : next);
  }

  /// Takes back the last recorded action, including the point that ended the
  /// match or a walkover (until the result is closed).
  Future<void> undo() async {
    final match = state;
    if (match == null || match.isPaused || match.awaitingHandover) return;
    // A walkover or retirement is taken back first, leaving the rallies as they were.
    if (match.outcome != null) return _save(match.copyWith(reopen: true));
    // A court correction made since the last rally is the last action.
    final fixes = match.adjustments;
    if (fixes.isNotEmpty && fixes.last.afterEvents >= match.events.length) {
      return _save(match.copyWith(adjustments: fixes.sublist(0, fixes.length - 1)));
    }
    if (match.events.isEmpty) return;
    final events = match.events.sublist(0, match.events.length - 1);
    final undone = match.copyWith(events: events, reopen: true);
    // Undoing a game-winning point also takes back the ends answer for that game.
    final game = undone.score.gameNumber;
    await _save(undone.copyWith(endChanges: {
      for (final e in match.endChanges.entries)
        if (e.key < game) e.key: e.value,
    }));
  }

  /// The scorer's answer at a game break: did the players change ends
  /// before game [finishedGame] + 1?
  Future<void> setEndChange(int finishedGame, {required bool switched}) async {
    final match = state;
    if (match == null) return;
    await _save(match.copyWith(endChanges: {...match.endChanges, finishedGame: switched}));
  }

  /// Stops play; taps do nothing until [resume].
  Future<void> pause(String reason) async {
    final match = state;
    if (match == null || match.isOver || match.isPaused) return;
    await _save(match.copyWith(pausedAt: DateTime.now(), pauseReason: reason));
  }

  Future<void> resume() async {
    final match = state;
    if (match == null || !match.isPaused) return;
    await _save(match.copyWith(resume: true));
  }

  /// Ends the match for [winner] without playing it out: a walkover (the
  /// other side never came) or a retirement (they stopped mid-match).
  Future<void> endEarly(EarlyEnd kind, Side winner) async {
    final match = state;
    if (match == null || match.isOver) return;
    await _save(match.copyWith(outcome: MatchOutcome(kind, winner), finishedAt: DateTime.now(), resume: true));
  }

  /// New rules restart the scoring from 0-0 with the same players and first
  /// server; the screen asks before calling this on a match under way.
  Future<void> changeRules(MatchRules rules) async {
    final match = state;
    if (match == null || match.isOver) return;
    await _save(match.copyWith(rules: rules, events: const [], endChanges: const {}, adjustments: const []));
  }

  /// Closes the finished match so a new one can start.
  Future<void> close() async {
    await ref.read(matchStoreProvider).clearActive();
    state = null;
  }

  Future<void> _save(LocalMatch match) async {
    final wasOver = state?.id == match.id && state!.isOver;
    await ref.read(matchStoreProvider).writeActive(match);
    state = match;
    // A finished match joins the player's results; undoing the winning point takes it out again.
    final played = ref.read(playedMatchesProvider.notifier);
    if (match.isOver) {
      await played.record(match);
    } else if (wasOver) {
      await played.remove(match.id);
    }
    // Every change goes to SkorX: live when there is signal, later when not.
    // A finished result goes to the other players to confirm; it only counts once they do.
    unawaited(ref.read(casualSyncProvider.notifier).changed(match));
  }
}
