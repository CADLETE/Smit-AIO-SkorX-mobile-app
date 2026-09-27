import 'package:flutter/material.dart';

/// The pickleball ecosystem, as Community groups it (docs/COMMUNITY.md §2).
/// Each sector holds person roles and/or kinds of place; the hub shows the
/// sectors, and a sector's page narrows by role with chips.
enum CommunitySector {
  players('Players', 'Partners, rivals, teammates', Icons.sports_tennis_rounded),
  officials('Officials', 'Referees and scorekeepers', Icons.sports_rounded),
  organizers('Organizers', 'Tournaments, leagues, events', Icons.event_available_rounded),
  training('Coaching', 'Coaches and academies', Icons.school_rounded),
  places('Clubs & courts', 'Clubs, grounds, facilities', Icons.stadium_rounded),
  media('Media', 'Commentators, streamers, creators', Icons.videocam_rounded),
  business('Business', 'Brands, sponsors, services', Icons.storefront_rounded);

  const CommunitySector(this.title, this.tagline, this.icon);
  final String title;
  final String tagline;
  final IconData icon;

  List<CommunityRole> get roles => [for (final r in CommunityRole.values) if (r.sector == this) r];
  List<PlaceKind> get placeKinds => [for (final k in PlaceKind.values) if (k.sector == this) k];

  static CommunitySector? byName(String? name) => values.where((s) => s.name == name).firstOrNull;
}

/// What a person does in pickleball. A person can hold several.
enum CommunityRole {
  player('Player', 'Players', Icons.sports_tennis_rounded, CommunitySector.players),
  referee('Referee', 'Referees', Icons.sports_rounded, CommunitySector.officials),
  scorekeeper('Scorekeeper', 'Scorekeepers', Icons.scoreboard_rounded, CommunitySector.officials),
  official('Tournament official', 'Tournament officials', Icons.badge_rounded, CommunitySector.officials),
  organizer('Tournament organizer', 'Organizers', Icons.emoji_events_rounded, CommunitySector.organizers),
  eventManager('Event manager', 'Event managers', Icons.event_note_rounded, CommunitySector.organizers),
  coach('Coach', 'Coaches', Icons.school_rounded, CommunitySector.training),
  trainer('Fitness trainer', 'Trainers', Icons.fitness_center_rounded, CommunitySector.training),
  commentator('Commentator', 'Commentators', Icons.mic_rounded, CommunitySector.media),
  streamer('Streamer', 'Streamers', Icons.live_tv_rounded, CommunitySector.media),
  photographer('Photographer', 'Photographers', Icons.photo_camera_rounded, CommunitySector.media),
  creator('Content creator', 'Creators', Icons.movie_creation_rounded, CommunitySector.media);

  const CommunityRole(this.label, this.plural, this.icon, this.sector);
  final String label;
  final String plural;
  final IconData icon;
  final CommunitySector sector;

  static CommunityRole? byName(String? name) => values.where((r) => r.name == name).firstOrNull;
}

/// Organisations and places, which have a page of their own.
enum PlaceKind {
  club('Club', 'Clubs', Icons.groups_rounded, CommunitySector.places),
  venue('Courts', 'Courts & grounds', Icons.stadium_rounded, CommunitySector.places),
  academy('Academy', 'Academies', Icons.school_rounded, CommunitySector.training),
  business('Business', 'Brands & services', Icons.storefront_rounded, CommunitySector.business);

  const PlaceKind(this.label, this.plural, this.icon, this.sector);
  final String label;
  final String plural;
  final IconData icon;
  final CommunitySector sector;

  static PlaceKind? byName(String? name) => values.where((k) => k.name == name).firstOrNull;
}

enum Availability {
  open('Available', 'Taking new work'),
  limited('Limited', 'Some dates open'),
  busy('Not available', 'Fully booked for now');

  const Availability(this.label, this.detail);
  final String label;
  final String detail;
}

/// One role on a person's profile, with the evidence for it. Reputation is
/// role-specific numbers from SkorX (matches officiated, events streamed),
/// never a generic star rating.
class RoleRecord {
  const RoleRecord(
    this.role, {
    this.verified = false,
    this.since,
    this.metrics = const [],
    this.highlights = const [],
  });

  final CommunityRole role;

  /// SkorX checked the evidence for this role (docs/COMMUNITY.md §6). Never
  /// set by the member themselves.
  final bool verified;

  /// Year they started in this role.
  final int? since;

  /// (label, value): "Matches officiated" · "312". Worked out on the server
  /// from SkorX records where it can be.
  final List<(String, String)> metrics;

  /// Portfolio lines: events worked, certificates, notable work.
  final List<String> highlights;

  int? yearsIn(DateTime now) => since == null ? null : (now.year - since!).clamp(0, 80);
}

/// A person on SkorX Community. Linked to their player profile when they
/// play, so stats are read from there, never copied.
class CommunityMember {
  const CommunityMember({
    required this.id,
    required this.name,
    required this.city,
    required this.roles,
    this.state,
    this.headline,
    this.bio,
    this.playerId,
    this.level,
    this.tags = const [],
    this.languages = const [],
    this.serviceArea = const [],
    this.availability,
    this.placeIds = const [],
    this.groupIds = const [],
    this.mutualConnections = 0,
    this.acceptsMessagesFrom = MessagePermission.everyone,
  });

  final String id;
  final String name;
  final String city;
  final String? state;
  final String? headline;
  final String? bio;

  /// In order of importance to them; the first is their primary role.
  final List<RoleRecord> roles;

  /// Their SkorX player id ("SKX-10021") when they play.
  final String? playerId;

  /// Playing level, when they play.
  final String? level;

  /// Player tags: Doubles, Singles, Competitive, Recreational, Junior, Senior.
  final List<String> tags;
  final List<String> languages;

  /// Cities they will travel to for work.
  final List<String> serviceArea;

  /// For professional roles; null for players only.
  final Availability? availability;

  /// Clubs, academies and venues they belong to or work at.
  final List<String> placeIds;
  final List<String> groupIds;
  final int mutualConnections;
  final MessagePermission acceptsMessagesFrom;

  CommunityRole get primaryRole => roles.first.role;
  bool hasRole(CommunityRole r) => roles.any((x) => x.role == r);
  bool verifiedAs(CommunityRole r) => roles.any((x) => x.role == r && x.verified);
  bool get verified => roles.any((r) => r.verified);
  RoleRecord? record(CommunityRole r) => roles.where((x) => x.role == r).firstOrNull;

  /// "Referee · Scorekeeper".
  String get rolesLabel => roles.map((r) => r.role.label).join(' · ');

  /// "Ahmedabad, Gujarat".
  String get placeLabel => [city, if (state != null && state != city) state!].join(', ');
}

enum PlaceSetting {
  indoor('Indoor'),
  outdoor('Outdoor'),
  both('Indoor & outdoor');

  const PlaceSetting(this.label);
  final String label;

  bool get hasIndoor => this != outdoor;
  bool get hasOutdoor => this != indoor;
}

/// A coaching or club programme.
class Program {
  const Program({required this.name, required this.level, required this.schedule, this.fee, this.juniors = false});

  final String name;

  /// Beginner, Intermediate, Advanced, All levels.
  final String level;
  final String schedule;

  /// Rupees per month, when published.
  final int? fee;
  final bool juniors;
}

/// A club, academy, venue or business. Courts and bookings live in the
/// courts module: [venueId] links to it, so nothing is entered twice.
class CommunityPlace {
  const CommunityPlace({
    required this.id,
    required this.kind,
    required this.name,
    required this.city,
    required this.about,
    this.state,
    this.area,
    this.verified = false,
    this.venueId,
    this.courts,
    this.setting,
    this.surface,
    this.amenities = const [],
    this.hours,
    this.programs = const [],
    this.staffIds = const [],
    this.tournamentIds = const [],
    this.members = 0,
    this.followers = 0,
    this.organizationId,
    this.founded,
  });

  final String id;
  final PlaceKind kind;
  final String name;
  final String city;
  final String? state;
  final String? area;
  final String about;
  final bool verified;

  /// The venue in the courts module, for booking, prices and reviews.
  final String? venueId;

  /// The organisation in the TMS, when it runs tournaments on SkorX.
  final String? organizationId;
  final int? courts;
  final PlaceSetting? setting;
  final String? surface;
  final List<String> amenities;
  final String? hours;
  final List<Program> programs;

  /// Coaches and staff, as community member ids.
  final List<String> staffIds;

  /// Tournaments held here or by them, as SkorX tournament ids.
  final List<String> tournamentIds;
  final int members;
  final int followers;
  final int? founded;

  bool get bookable => venueId != null;
  String get placeLabel => [?area, city].join(', ');
}

enum GroupAccess {
  public('Public', 'Anyone can join'),
  private('Private', 'Admins approve new members'),
  verified('Verified', 'Run by a verified organisation');

  const GroupAccess(this.label, this.detail);
  final String label;
  final String detail;
}

/// A focused community: a city's players, a state's referees.
class CommunityGroup {
  const CommunityGroup({
    required this.id,
    required this.name,
    required this.about,
    required this.access,
    required this.members,
    required this.activeThisWeek,
    this.city,
    this.state,
    this.focus,
    this.managedBy,
    this.rules = const [],
  });

  final String id;
  final String name;
  final String about;
  final GroupAccess access;
  final int members;

  /// Members who posted, chatted or played this week. Trending is ordered
  /// by this, not by size.
  final int activeThisWeek;

  /// Null for national or online groups.
  final String? city;
  final String? state;

  /// The role it is for, when it is for one.
  final CommunityRole? focus;

  /// Place id of the verified organisation that runs it.
  final String? managedBy;
  final List<String> rules;

  String get placeLabel => city ?? state ?? 'India';

  /// Share of members active this week, 0–1.
  double get activity => members == 0 ? 0 : (activeThisWeek / members).clamp(0, 1).toDouble();
}

enum ConnectionStatus { none, pendingOut, pendingIn, connected }

enum GroupStatus { none, requested, member }

enum MessagePermission {
  everyone('Everyone on SkorX'),
  connections('Connections only');

  const MessagePermission(this.label);
  final String label;
}

/// What a follow, save or report points at. The server needs the type as
/// well as the id (`PUT /me/saved/:type/:id`).
enum CommunityTarget { member, place, group, event, post }

/// The signed-in member's ties: who they are connected to and follow,
/// what they joined, run, blocked and saved. `GET /me/community`.
class CommunityGraph {
  const CommunityGraph({
    this.connections = const {},
    this.following = const {},
    this.groups = const {},
    this.adminOf = const {},
    this.blocked = const {},
    this.saved = const {},
  });

  /// Member id → status. Missing means none.
  final Map<String, ConnectionStatus> connections;

  /// Member and place ids.
  final Set<String> following;
  final Map<String, GroupStatus> groups;

  /// Communities I run: I see and decide their join requests.
  final Set<String> adminOf;
  final Set<String> blocked;

  /// Saved people, places, communities, events and posts, with their type.
  final Map<String, CommunityTarget> saved;

  ConnectionStatus connectionWith(String id) => connections[id] ?? ConnectionStatus.none;
  GroupStatus groupStatus(String id) => groups[id] ?? GroupStatus.none;
  bool follows(String id) => following.contains(id);
  bool hasBlocked(String id) => blocked.contains(id);
  bool hasSaved(String id) => saved.containsKey(id);
  bool admins(String groupId) => adminOf.contains(groupId);
  Iterable<String> savedOf(CommunityTarget type) => saved.entries.where((e) => e.value == type).map((e) => e.key);

  Iterable<String> idsWith(ConnectionStatus s) => connections.entries.where((e) => e.value == s).map((e) => e.key);
  int get connectedCount => idsWith(ConnectionStatus.connected).length;
  int get incomingCount => idsWith(ConnectionStatus.pendingIn).length;
  Iterable<String> get joinedGroups => groups.entries.where((e) => e.value == GroupStatus.member).map((e) => e.key);

  CommunityGraph copyWith({
    Map<String, ConnectionStatus>? connections,
    Set<String>? following,
    Map<String, GroupStatus>? groups,
    Set<String>? adminOf,
    Set<String>? blocked,
    Map<String, CommunityTarget>? saved,
  }) =>
      CommunityGraph(
        connections: connections ?? this.connections,
        following: following ?? this.following,
        groups: groups ?? this.groups,
        adminOf: adminOf ?? this.adminOf,
        blocked: blocked ?? this.blocked,
        saved: saved ?? this.saved,
      );

  CommunityGraph withConnection(String id, ConnectionStatus s) => copyWith(
        connections: {...connections, id: s}..removeWhere((_, v) => v == ConnectionStatus.none),
      );

  CommunityGraph withGroup(String id, GroupStatus s) =>
      copyWith(groups: {...groups, id: s}..removeWhere((_, v) => v == GroupStatus.none));

  CommunityGraph withSaved(String id, CommunityTarget type, bool on) =>
      copyWith(saved: on ? {...saved, id: type} : ({...saved}..remove(id)));
}

/// [set] with [id] added or removed.
Set<String> toggledIn(Set<String> set, String id, bool on) => on ? {...set, id} : ({...set}..remove(id));

/// How the signed-in member appears in Community. `GET /me/community-profile`.
class MyCommunityProfile {
  const MyCommunityProfile({
    this.roles = const {CommunityRole.player},
    this.headline,
    this.availability,
    this.languages = const [],
    this.serviceArea = const [],
    this.messagesFrom = MessagePermission.everyone,
    this.listed = true,
    this.rolesChosen = false,
  });

  final Set<CommunityRole> roles;
  final String? headline;
  final Availability? availability;
  final List<String> languages;
  final List<String> serviceArea;
  final MessagePermission messagesFrom;

  /// Shown in the directory and search. Off: only people they are connected
  /// to can find them.
  final bool listed;

  /// They have told SkorX what they do (the first-visit card goes away).
  final bool rolesChosen;

  bool get professional => roles.any((r) => r != CommunityRole.player);

  MyCommunityProfile copyWith({
    Set<CommunityRole>? roles,
    String? Function()? headline,
    Availability? Function()? availability,
    List<String>? languages,
    List<String>? serviceArea,
    MessagePermission? messagesFrom,
    bool? listed,
    bool? rolesChosen,
  }) =>
      MyCommunityProfile(
        roles: roles ?? this.roles,
        headline: headline == null ? this.headline : headline(),
        availability: availability == null ? this.availability : availability(),
        languages: languages ?? this.languages,
        serviceArea: serviceArea ?? this.serviceArea,
        messagesFrom: messagesFrom ?? this.messagesFrom,
        listed: listed ?? this.listed,
        rolesChosen: rolesChosen ?? this.rolesChosen,
      );
}

/// A person suggested on the hub, and why, so the list never feels random.
class Suggestion {
  const Suggestion(this.member, this.reason);

  final CommunityMember member;

  /// "4 mutual connections", "Plays at CADLETE Club", "Referee in Ahmedabad".
  final String reason;
}

enum ReportReason {
  spam('Spam or scam'),
  fake('Fake profile or impersonation'),
  abuse('Harassment or abuse'),
  inappropriate('Inappropriate content'),
  other('Something else');

  const ReportReason(this.label);
  final String label;
}

enum ReportTarget { member, place, group, message, post, comment, event }
