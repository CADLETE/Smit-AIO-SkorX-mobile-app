import 'community.dart';

/// Who a member with these roles most likely wants to find (spec §20). The
/// hub leads with these sectors, and suggestions favour these roles.
Set<CommunityRole> rolesOfInterest(Set<CommunityRole> mine) => {
      for (final r in mine) ..._interest[r] ?? const <CommunityRole>{},
    };

const _interest = <CommunityRole, Set<CommunityRole>>{
  CommunityRole.player: {CommunityRole.player, CommunityRole.coach},
  CommunityRole.organizer: {
    CommunityRole.referee,
    CommunityRole.scorekeeper,
    CommunityRole.official,
    CommunityRole.streamer,
    CommunityRole.commentator,
    CommunityRole.photographer,
  },
  CommunityRole.eventManager: {CommunityRole.organizer, CommunityRole.streamer, CommunityRole.photographer},
  CommunityRole.referee: {CommunityRole.organizer, CommunityRole.scorekeeper, CommunityRole.referee},
  CommunityRole.scorekeeper: {CommunityRole.organizer, CommunityRole.referee},
  CommunityRole.official: {CommunityRole.organizer, CommunityRole.referee},
  CommunityRole.coach: {CommunityRole.player, CommunityRole.coach},
  CommunityRole.trainer: {CommunityRole.player, CommunityRole.coach},
  CommunityRole.streamer: {CommunityRole.organizer, CommunityRole.commentator},
  CommunityRole.commentator: {CommunityRole.organizer, CommunityRole.streamer},
  CommunityRole.photographer: {CommunityRole.organizer, CommunityRole.creator},
  CommunityRole.creator: {CommunityRole.player, CommunityRole.organizer},
};

/// The hub's sector cards, most useful first for these roles. Every sector
/// stays; only the order changes.
List<CommunitySector> sectorsFor(Set<CommunityRole> mine) {
  // Each of my roles' first interest counts most ("a referee wants
  // organisers"), the rest a little.
  int score(CommunitySector s) {
    var n = 0;
    for (final r in mine) {
      for (final (i, wanted) in (_interest[r] ?? const <CommunityRole>{}).indexed) {
        if (wanted.sector == s) n += i == 0 ? 12 : 5;
      }
    }
    // Players always want somewhere to play; organisers need venues.
    if (s == CommunitySector.places && (mine.contains(CommunityRole.player) || mine.contains(CommunityRole.organizer))) {
      n += 5;
    }
    return n;
  }

  final order = [...CommunitySector.values];
  // Stable: ties keep the enum's order.
  final indexed = order.indexed.toList()..sort((a, b) => score(b.$2) != score(a.$2) ? score(b.$2) - score(a.$2) : a.$1 - b.$1);
  return [for (final (_, s) in indexed) s];
}

/// One line under the hub's title, for what this member came to do.
String hubPrompt(Set<CommunityRole> mine) {
  if (mine.contains(CommunityRole.organizer) || mine.contains(CommunityRole.eventManager)) {
    return 'Officials, streamers and venues for your next event.';
  }
  if (mine.any((r) => r.sector == CommunitySector.officials)) return 'Organisers and events that need officials.';
  if (mine.contains(CommunityRole.coach) || mine.contains(CommunityRole.trainer)) {
    return 'Players to train, academies and clubs to work with.';
  }
  if (mine.any((r) => r.sector == CommunitySector.media)) return 'Events to cover and the people who run them.';
  return 'Connect. Discover. Collaborate. Grow pickleball.';
}
