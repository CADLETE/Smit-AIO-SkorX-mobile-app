import 'package:flutter/material.dart';

import '../../design/design.dart';

/// Whether a module can be opened yet.
enum ExploreModuleStatus { active, comingSoon }

/// A module's accent, resolved against the current theme so light and dark
/// both hold.
enum ExploreTone {
  volt,
  blue,
  deep,
  cyan;

  List<Color> colors(SxColors c) => switch (this) {
        ExploreTone.volt => [c.voltFill, c.olive],
        ExploreTone.blue => [c.blue, c.cyan],
        ExploreTone.deep => [c.deep, c.blue],
        ExploreTone.cyan => [c.cyan, c.blue],
      };
}

/// One thing to discover on SkorX, as the Explore hub lists it.
///
/// To switch a coming-soon module on: build its screen, give it a
/// [location], and set [status] to active. Locations under
/// `/player/explore/` open inside the Explore tab (see `ExploreModulePage`);
/// any other location is a tab or screen of its own.
class ExploreModule {
  const ExploreModule({
    required this.id,
    required this.title,
    required this.tagline,
    required this.icon,
    this.tone = ExploreTone.blue,
    this.status = ExploreModuleStatus.active,
    this.location,
  }) : assert(status == ExploreModuleStatus.comingSoon || location != null, 'an active module needs a location');

  /// Stable id: the path segment under `/player/explore/`, and test keys.
  final String id;
  final String title;
  final String tagline;
  final IconData icon;
  final ExploreTone tone;
  final ExploreModuleStatus status;
  final String? location;

  bool get available => status == ExploreModuleStatus.active;

  /// Opens inside the Explore tab rather than switching tabs.
  bool get nested => location?.startsWith('/player/explore/') ?? false;
}

/// Open now: the modules the hub leads with.
const exploreModules = [
  ExploreModule(
    id: 'tournaments',
    title: 'Tournaments',
    tagline: 'Find, enter and follow events',
    icon: Icons.emoji_events_rounded,
    tone: ExploreTone.volt,
    location: '/player/explore/tournaments',
  ),
  ExploreModule(
    id: 'scores',
    title: 'Scores',
    tagline: 'Live and recent matches',
    icon: Icons.scoreboard_rounded,
    tone: ExploreTone.blue,
    location: '/player/matches',
  ),
  ExploreModule(
    id: 'players',
    title: 'Players',
    tagline: 'Find partners, scout rivals',
    icon: Icons.person_search_rounded,
    tone: ExploreTone.deep,
    location: '/player/explore/players',
  ),
  ExploreModule(
    id: 'courts',
    title: 'Courts',
    tagline: 'Book a court near you',
    icon: Icons.stadium_rounded,
    tone: ExploreTone.cyan,
    location: '/player/explore/courts',
  ),
  ExploreModule(
    id: 'community',
    title: 'Community',
    tagline: 'Players, referees, coaches, clubs',
    icon: Icons.diversity_3_rounded,
    tone: ExploreTone.deep,
    location: '/player/community',
  ),
  ExploreModule(
    id: 'looking-for',
    title: 'Looking For',
    tagline: 'Find or post: players, officials, courts',
    icon: Icons.radar_rounded,
    tone: ExploreTone.volt,
    location: '/player/looking-for',
  ),
];

/// Being built: shown so players know what is coming, never faked. Empty
/// for now, so the hub hides its "Coming to SkorX" list.
const upcomingExploreModules = <ExploreModule>[];

ExploreModule? exploreModuleById(String id) =>
    [...exploreModules, ...upcomingExploreModules].where((m) => m.id == id).firstOrNull;
