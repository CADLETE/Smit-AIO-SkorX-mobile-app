import 'tms_models.dart';

/// What the organiser chose on the schedule screen.
class ScheduleSettings {
  const ScheduleSettings({
    required this.start,
    required this.courtIds,
    this.matchMinutes = 25,
    this.bufferMinutes = 5,
    this.breakStart,
    this.breakMinutes = 0,
    this.categoryOrder = const [],
  });

  final DateTime start;

  /// Courts to use, in the order to fill them.
  final List<String> courtIds;
  final int matchMinutes;

  /// Changeover on a court, and the least rest a player gets between matches.
  final int bufferMinutes;

  /// A lunch or ceremony break when no match starts.
  final DateTime? breakStart;
  final int breakMinutes;

  /// Categories to play first when rounds tie; others follow in draw order.
  final List<String> categoryOrder;

  Duration get slot => Duration(minutes: matchMinutes);
  Duration get buffer => Duration(minutes: bufferMinutes);
}

class ScheduledSlot {
  const ScheduledSlot(this.matchId, this.courtId, this.start, this.end);

  final String matchId;
  final String courtId;
  final DateTime start;
  final DateTime end;
}

/// Gives every unplayed match a court and a start time.
///
/// Guarantees, in this order of precedence:
/// 1. A court holds one match at a time, with [ScheduleSettings.buffer]
///    between matches.
/// 2. No player is on two courts at once, and each gets the buffer as rest.
/// 3. A knockout match starts only after the matches that feed it.
/// 4. No match starts inside the break.
///
/// Earlier rounds go first; within a round, [ScheduleSettings.categoryOrder].
/// [playersOf] maps an entry to its player ids, so a player entered in two
/// categories is never double-booked.
List<ScheduledSlot> buildSchedule({
  required List<TmsMatch> matches,
  required ScheduleSettings settings,
  required List<String> Function(String entryId) playersOf,
}) {
  if (settings.courtIds.isEmpty) return const [];
  final todo = matches.where((m) => m.state == MatchState.pending || m.state == MatchState.scheduled).toList();
  int priority(String categoryId) {
    final i = settings.categoryOrder.indexOf(categoryId);
    return i < 0 ? settings.categoryOrder.length : i;
  }

  todo.sort((a, b) {
    if (a.round != b.round) return a.round.compareTo(b.round);
    final byCategory = priority(a.categoryId).compareTo(priority(b.categoryId));
    return byCategory != 0 ? byCategory : a.number.compareTo(b.number);
  });

  final courtFree = {for (final c in settings.courtIds) c: settings.start};
  final playerFree = <String, DateTime>{};
  final matchEnd = <String, DateTime>{
    // Matches already on court or done are not moved; they only constrain.
    for (final m in matches)
      if (m.state != MatchState.pending && m.state != MatchState.scheduled && !m.isBye)
        m.id: m.completedAt ?? (m.startedAt ?? settings.start).add(settings.slot),
  };
  final slots = <ScheduledSlot>[];

  DateTime later(DateTime a, DateTime b) => a.isAfter(b) ? a : b;

  DateTime outsideBreak(DateTime t) {
    final breakStart = settings.breakStart;
    if (breakStart == null || settings.breakMinutes <= 0) return t;
    final breakEnd = breakStart.add(Duration(minutes: settings.breakMinutes));
    // A match may not start in the break, nor run into it.
    final end = t.add(settings.slot);
    return end.isAfter(breakStart) && t.isBefore(breakEnd) ? breakEnd : t;
  }

  for (final match in todo) {
    var earliest = settings.start;
    for (final source in [match.sourceA, match.sourceB]) {
      final end = source == null ? null : matchEnd[source];
      if (end != null) earliest = later(earliest, end.add(settings.buffer));
    }
    final players = [
      for (final entry in [match.entryA, match.entryB])
        if (entry != null) ...playersOf(entry),
    ];
    for (final p in players) {
      final free = playerFree[p];
      if (free != null) earliest = later(earliest, free.add(settings.buffer));
    }

    // The court that lets this match start soonest; ties go to the first court.
    String? bestCourt;
    DateTime? bestStart;
    for (final court in settings.courtIds) {
      final start = outsideBreak(later(courtFree[court]!, earliest));
      if (bestStart == null || start.isBefore(bestStart)) {
        bestCourt = court;
        bestStart = start;
      }
    }
    final end = bestStart!.add(settings.slot);
    slots.add(ScheduledSlot(match.id, bestCourt!, bestStart, end));
    courtFree[bestCourt] = end.add(settings.buffer);
    matchEnd[match.id] = end;
    for (final p in players) {
      playerFree[p] = end;
    }
  }
  return slots;
}
