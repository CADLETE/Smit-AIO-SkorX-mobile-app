import 'dart:convert';

import '../../../sports/core/score_state.dart';
import '../../../sports/core/scoring_engine.dart';
import '../local_match.dart';
import '../verification/verification_repository.dart';

/// What the server last acknowledged for a match, as one comparable string:
/// rules, how many events and the last one's id (ids are UUIDs and an undo
/// removes the last one, so this identifies the log), the ending, and the
/// timeline. Any change on the phone changes it, so "synced" is simply
/// "the signature the server acknowledged is the current one".
String syncSignature(LocalMatch m) => [
      jsonEncode(m.rules.toJson()),
      m.events.length,
      m.events.isEmpty ? '-' : m.events.last.id,
      m.outcome == null ? '-' : '${m.outcome!.kind.name}:${m.outcome!.winner.name}',
      m.finishedAt?.toUtc().toIso8601String() ?? '-',
      m.adjustments.length,
      m.endChanges.length,
      m.scorers.length,
      m.pausedAt == null ? 0 : 1,
    ].join('|');

/// The lineup as SkorX needs it. Picked SkorX players go by account id; "me"
/// is the signed-in player; anyone typed in by name is a guest.
List<LineupPlayer> lineupOf(List<String> names, List<String> ids) => [
      for (final (i, name) in names.indexed)
        switch (i < ids.length ? ids[i] : null) {
          'me' => const LineupPlayer.me(),
          final String id when !id.startsWith('guest:') => LineupPlayer.registered(id),
          _ when name == 'You' => const LineupPlayer.me(),
          _ => LineupPlayer.guest(name),
        },
    ];

Map<String, dynamic> _serve(ServeState s) => {'side': s.side.name, 'serverNumber': s.serverNumber};

/// Every event with the score and server before and after it, as the phone's
/// engine computed them. The server recomputes all of it by replay; these
/// are kept only to audit a disagreement.
List<Map<String, dynamic>> eventsForUpload(LocalMatch m) {
  final engine = m.sport.engine;
  final setup = m.setup;
  var state = engine.start(setup);
  final out = <Map<String, dynamic>>[];
  for (final (i, e) in m.events.indexed) {
    final before = state;
    try {
      state = engine.apply(setup, state, e.event);
    } on StateError {
      // An event the engine refuses (after the match was decided) is still
      // sent as recorded: the server rejects the log and says why.
    }
    final finishedGame = state.games.length > before.games.length ? state.games[before.games.length - 1] : state.currentGame;
    out.add({
      'id': e.id,
      'seq': i + 1,
      'kind': e.event is RallyWon ? 'rally' : 'serve',
      'side': switch (e.event) {
        RallyWon(:final side) => side.name,
        ServeCorrected(:final serve) => serve.side.name,
      },
      if (e.event case ServeCorrected(:final serve)) 'serverNumber': serve.serverNumber,
      'recordedAt': e.recordedAt.toUtc().toIso8601String(),
      'gameNumber': before.gameNumber,
      'scoreBefore': [before.currentGame.a, before.currentGame.b],
      'scoreAfter': [finishedGame.a, finishedGame.b],
      'serverBefore': _serve(before.serve),
      'serverAfter': _serve(state.serve),
    });
  }
  return out;
}

/// The result to send once the match is over, or null while it is not.
Map<String, dynamic>? resultForUpload(LocalMatch m) {
  if (!m.isOver) return null;
  final games = [
    for (final g in m.score.games)
      if (g.a + g.b > 0) g,
  ];
  final early = m.outcome;
  return {
    'outcome': switch (early?.kind) {
      EarlyEnd.walkover => 'walkover',
      EarlyEnd.retired => 'retirement',
      null => 'completed',
    },
    'winnerSide': ?(early?.winner.name),
    'sideAScores': games.isEmpty ? [0] : [for (final g in games) g.a],
    'sideBScores': games.isEmpty ? [0] : [for (final g in games) g.b],
    'completedAt': (m.finishedAt ?? DateTime.now()).toUtc().toIso8601String(),
  };
}

/// One match of `POST /casual-matches/sync` (docs/OFFLINE-SCORING.md §5).
Map<String, dynamic> uploadOf(LocalMatch m, {int? baseVersion, bool force = false}) => {
      'clientRef': m.id,
      'code': ?m.code,
      'baseVersion': ?baseVersion,
      if (force) 'force': true,
      'match': {
        'sportId': m.sportId,
        'category': m.categoryId,
        'sideA': [for (final p in lineupOf(m.sideA, m.details.sideAIds)) p.toJson()],
        'sideB': [for (final p in lineupOf(m.sideB, m.details.sideBIds)) p.toJson()],
        'rules': m.rules.toJson(),
        'firstServer': m.firstServer.name,
        'locationName': ?m.locationName,
        'startedAt': m.startedAt.toUtc().toIso8601String(),
      },
      'events': eventsForUpload(m),
      'timeline': {
        if (m.endChanges.isNotEmpty) 'endChanges': {for (final e in m.endChanges.entries) '${e.key}': e.value},
        if (m.adjustments.isNotEmpty) 'adjustments': [for (final a in m.adjustments) a.toJson()],
        if (m.scorers.isNotEmpty) 'scorers': [for (final s in m.scorers) s.toJson()],
        if (m.pausedAt != null) 'pausedAt': m.pausedAt!.toUtc().toIso8601String(),
        'pauseReason': ?m.pauseReason,
      },
      'result': ?resultForUpload(m),
    };

/// Rough size of a match on the wire, to keep one request under the
/// server's 1 MB limit.
int uploadWeight(LocalMatch m) => 1500 + m.events.length * 330;
