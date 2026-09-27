import 'dart:math';

import '../../../sports/core/score_state.dart';
import 'tms_models.dart';

/// Where every entry sits in a category's draw. Matches are always rebuilt
/// from this, so a swap or a regenerate can never leave a stale match.
class DrawLayout {
  const DrawLayout({required this.categoryId, required this.format, required this.groups, this.method = DrawMethod.seeded});

  final String categoryId;
  final DrawFormat format;
  final DrawMethod method;

  /// Knockout: one group, the bracket's slots top to bottom (null = bye).
  /// Round robin: one group. Pool play: one group per pool.
  final List<List<String?>> groups;

  Iterable<String> get entries => groups.expand((g) => g).whereType<String>();

  DrawLayout withGroups(List<List<String?>> groups) =>
      DrawLayout(categoryId: categoryId, format: format, groups: groups, method: method);
}

/// Seeds first (1, 2, 3…), then the rest by SkorX rating, highest first.
List<Entry> seedOrder(Iterable<Entry> entries) => entries.toList()
  ..sort((a, b) {
    final bySeed = (a.seed ?? 1 << 20).compareTo(b.seed ?? 1 << 20);
    if (bySeed != 0) return bySeed;
    final byRating = (b.rating ?? 0).compareTo(a.rating ?? 0);
    return byRating != 0 ? byRating : a.registeredAt.compareTo(b.registeredAt);
  });

/// Bracket positions of seeds 1…[size], top to bottom, so 1 and 2 can only
/// meet in the final: 8 → [1, 8, 4, 5, 2, 7, 3, 6].
List<int> bracketOrder(int size) {
  var order = [1];
  while (order.length < size) {
    final n = order.length * 2;
    order = [for (final s in order) ...[s, n + 1 - s]];
  }
  return order;
}

/// Places [entries] (approved, any order) into a new draw.
DrawLayout generateDraw({
  required String categoryId,
  required DrawFormat format,
  required DrawMethod method,
  required List<Entry> entries,
  Random? random,
}) {
  final ordered = seedOrder(entries);
  if (method == DrawMethod.random) {
    // Seeds stay protected: only the unseeded entries are shuffled.
    final seeded = ordered.where((e) => e.seed != null).toList();
    final rest = ordered.where((e) => e.seed == null).toList()..shuffle(random ?? Random());
    ordered
      ..clear()
      ..addAll([...seeded, ...rest]);
  }
  final ids = ordered.map((e) => e.id).toList();

  final groups = switch (format) {
    DrawFormat.knockout => [_knockoutSlots(ids)],
    DrawFormat.roundRobin => [ids],
    DrawFormat.pools => _snakePools(ids),
  };
  return DrawLayout(categoryId: categoryId, format: format, groups: groups, method: method);
}

List<String?> _knockoutSlots(List<String> ids) {
  var size = 2;
  while (size < ids.length) {
    size *= 2;
  }
  // Seed k takes position k; missing seeds are byes, so the top seeds get them.
  return [for (final seed in bracketOrder(size)) seed <= ids.length ? ids[seed - 1] : null];
}

/// Pools of about four, filled in a snake (A B C C B A…) so pools are even.
List<List<String?>> _snakePools(List<String> ids) {
  final count = max(1, (ids.length / 4).ceil());
  final pools = List.generate(count, (_) => <String?>[]);
  for (final (i, id) in ids.indexed) {
    final lap = i ~/ count;
    final pos = i % count;
    pools[lap.isEven ? pos : count - 1 - pos].add(id);
  }
  return pools;
}

/// Swaps two entries wherever they sit, including across pools.
DrawLayout swapInDraw(DrawLayout layout, String a, String b) => layout.withGroups([
      for (final group in layout.groups)
        [
          for (final id in group) id == a ? b : (id == b ? a : id),
        ],
    ]);

/// The category's matches, numbered from [firstNumber]. Byes are completed
/// at once and their winner is already in the next round.
List<TmsMatch> buildMatches({
  required DrawLayout layout,
  required String tournamentId,
  required String Function(String entryId) labelOf,
  int firstNumber = 1,
}) {
  var number = firstNumber;
  String id(int round, int index, [String pool = '']) => '${layout.categoryId}-r$round$pool-$index';

  switch (layout.format) {
    case DrawFormat.knockout:
      final slots = layout.groups.single;
      final rounds = (log(slots.length) / ln2).round();
      final matches = <TmsMatch>[];
      // Who is already known to be in each match of the previous round.
      var previous = <TmsMatch>[];
      for (var r = 1; r <= rounds; r++) {
        final count = slots.length >> r;
        final current = <TmsMatch>[];
        for (var i = 0; i < count; i++) {
          String? a;
          String? b;
          String? sourceA;
          String? sourceB;
          if (r == 1) {
            a = slots[2 * i];
            b = slots[2 * i + 1];
          } else {
            final left = previous[2 * i];
            final right = previous[2 * i + 1];
            sourceA = left.id;
            sourceB = right.id;
            a = left.isBye ? left.entry(left.winner!) : null;
            b = right.isBye ? right.entry(right.winner!) : null;
          }
          final bye = r == 1 && (a == null) != (b == null);
          current.add(TmsMatch(
            id: id(r, i),
            tournamentId: tournamentId,
            categoryId: layout.categoryId,
            round: r,
            roundLabel: knockoutRoundLabel(r, rounds),
            number: bye ? 0 : number++,
            entryA: a,
            entryB: b,
            labelA: a == null ? (bye ? 'Bye' : 'Winner of ${_winnerOf(sourceA, previous)}') : labelOf(a),
            labelB: b == null ? (bye ? 'Bye' : 'Winner of ${_winnerOf(sourceB, previous)}') : labelOf(b),
            sourceA: sourceA,
            sourceB: sourceB,
            state: bye ? MatchState.completed : MatchState.pending,
            winner: bye ? (a != null ? Side.a : Side.b) : null,
          ));
        }
        matches.addAll(current);
        previous = current;
      }
      return matches;

    case DrawFormat.roundRobin:
    case DrawFormat.pools:
      final pooled = layout.format == DrawFormat.pools;
      final matches = <TmsMatch>[];
      for (final (p, group) in layout.groups.indexed) {
        final pool = pooled ? String.fromCharCode(65 + p) : null;
        for (final (r, pairs) in roundRobinRounds(group.whereType<String>().toList()).indexed) {
          for (final (i, (a, b)) in pairs.indexed) {
            matches.add(TmsMatch(
              id: id(r + 1, i, pool ?? ''),
              tournamentId: tournamentId,
              categoryId: layout.categoryId,
              round: r + 1,
              roundLabel: pool == null ? 'Round ${r + 1}' : 'Pool $pool · Round ${r + 1}',
              number: 0,
              pool: pool,
              entryA: a,
              entryB: b,
              labelA: labelOf(a),
              labelB: labelOf(b),
            ));
          }
        }
      }
      // Number round by round across pools, the order they are played in.
      matches.sort((x, y) => x.round != y.round ? x.round.compareTo(y.round) : (x.pool ?? '').compareTo(y.pool ?? ''));
      return [
        for (final m in matches)
          TmsMatch(
            id: m.id,
            tournamentId: m.tournamentId,
            categoryId: m.categoryId,
            round: m.round,
            roundLabel: m.roundLabel,
            number: number++,
            pool: m.pool,
            entryA: m.entryA,
            entryB: m.entryB,
            labelA: m.labelA,
            labelB: m.labelB,
          ),
      ];
  }
}

String _winnerOf(String? matchId, List<TmsMatch> previous) {
  final m = previous.where((p) => p.id == matchId).firstOrNull;
  return m == null ? 'previous match' : 'M${m.number}';
}

String knockoutRoundLabel(int round, int rounds) => switch (rounds - round) {
      0 => 'Final',
      1 => 'Semi-final',
      2 => 'Quarter-final',
      _ => 'Round of ${1 << (rounds - round + 1)}',
    };

/// Every pairing once, grouped into rounds where nobody plays twice (the
/// circle method). An odd entry count gives each entry one round off.
List<List<(String, String)>> roundRobinRounds(List<String> ids) {
  if (ids.length < 2) return const [];
  final ring = <String?>[...ids, if (ids.length.isOdd) null];
  final n = ring.length;
  final rounds = <List<(String, String)>>[];
  for (var r = 0; r < n - 1; r++) {
    final pairs = <(String, String)>[];
    for (var i = 0; i < n ~/ 2; i++) {
      final a = ring[i];
      final b = ring[n - 1 - i];
      if (a != null && b != null) pairs.add(r.isEven ? (a, b) : (b, a));
    }
    rounds.add(pairs);
    // Keep the first fixed, rotate the rest one step.
    ring.insert(1, ring.removeLast());
  }
  return rounds;
}

/// Puts the winner of [finished] into the match it feeds, if any.
/// Returns the updated next match, or null when there is none.
TmsMatch? advanceWinner(TmsMatch finished, List<TmsMatch> matches, String Function(String entryId) labelOf) {
  final winner = finished.winner;
  if (winner == null) return null;
  final entry = finished.entry(winner);
  if (entry == null) return null;
  for (final next in matches) {
    if (next.sourceA == finished.id) return next.copyWith(entryA: () => entry, labelA: labelOf(entry));
    if (next.sourceB == finished.id) return next.copyWith(entryB: () => entry, labelB: labelOf(entry));
  }
  return null;
}
