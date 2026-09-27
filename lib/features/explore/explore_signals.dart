import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../community/community_controller.dart' show communityBadgeProvider;
import '../matches/data/match.dart';
import '../matches/data/match_feed.dart';
import '../tournaments/data/tournaments.dart';

/// A short, true fact on a module's card: "2 live", "Live now".
class ExploreSignal {
  const ExploreSignal(this.text, {this.live = false});

  final String text;

  /// Something is being played right now.
  final bool live;
}

/// The live match feed's first page: enough to know whether anything is on.
const _liveNow = MatchQuery(status: MatchStatus.live);

/// What a module's card can say about it right now, from the same data its
/// screen shows. Null while loading, on error, or when there is nothing to
/// say; a card never shows a number it made up.
final exploreSignalProvider = Provider.autoDispose.family<ExploreSignal?, String>((ref, id) {
  switch (id) {
    case 'tournaments':
      final all = ref.watch(discoverTournamentsProvider).value;
      if (all == null) return null;
      final now = DateTime.now();
      final live = all.where((t) => t.phase(now) == TournamentPhase.live).length;
      if (live > 0) return ExploreSignal('$live live', live: true);
      final upcoming = all.where((t) => t.phase(now) == TournamentPhase.upcoming).length;
      return upcoming > 0 ? ExploreSignal('$upcoming upcoming') : null;
    case 'scores':
      final page = ref.watch(matchFeedProvider(_liveNow)).value;
      return page != null && page.matches.isNotEmpty ? const ExploreSignal('Live now', live: true) : null;
    case 'community':
      final waiting = ref.watch(communityBadgeProvider);
      return waiting > 0 ? ExploreSignal('$waiting new') : null;
    default:
      return null;
  }
});

/// Everything the signals read, for pull-to-refresh.
void refreshExploreSignals(WidgetRef ref) {
  ref.invalidate(discoverTournamentsProvider);
  ref.invalidate(matchFeedProvider(_liveNow));
}
