import 'community.dart';

/// Cities Community knows, with their state, so "scorekeepers in Gujarat"
/// and "referee near Surat" both resolve. The server keeps the real list
/// (`GET /community/places/cities`); this seeds the picker and the parser.
const communityCities = {
  'Ahmedabad': 'Gujarat',
  'Gandhinagar': 'Gujarat',
  'Surat': 'Gujarat',
  'Vadodara': 'Gujarat',
  'Rajkot': 'Gujarat',
  'Mumbai': 'Maharashtra',
  'Pune': 'Maharashtra',
  'Bengaluru': 'Karnataka',
  'Delhi': 'Delhi',
  'Jaipur': 'Rajasthan',
};

Set<String> get communityStates => {...communityCities.values};

const communityLanguages = ['English', 'Hindi', 'Gujarati', 'Marathi', 'Kannada'];
const communityLevels = ['Beginner', 'Intermediate', 'Advanced', 'Pro'];
const playerTags = ['Doubles', 'Singles', 'Mixed', 'Competitive', 'Recreational', 'Junior', 'Senior'];

/// A directory search: typed filters plus leftover free text. Built from
/// the filter sheet, a category page, or a sentence ([CommunityQuery.parse]).
class CommunityQuery {
  const CommunityQuery({
    this.text = '',
    this.sector,
    this.roles = const {},
    this.kinds = const {},
    this.city,
    this.state,
    this.nearMe = false,
    this.verifiedOnly = false,
    this.availableOnly = false,
    this.language,
    this.setting,
    this.level,
    this.tag,
  });

  /// Words not understood as a filter; matched against names and headlines.
  final String text;
  final CommunitySector? sector;
  final Set<CommunityRole> roles;
  final Set<PlaceKind> kinds;
  final String? city;
  final String? state;

  /// "near me": the caller swaps in the chosen location ([resolveNearMe]).
  final bool nearMe;
  final bool verifiedOnly;
  final bool availableOnly;
  final String? language;
  final PlaceSetting? setting;
  final String? level;
  final String? tag;

  bool get isEmpty =>
      text.isEmpty &&
      sector == null &&
      roles.isEmpty &&
      kinds.isEmpty &&
      city == null &&
      state == null &&
      !nearMe &&
      !verifiedOnly &&
      !availableOnly &&
      language == null &&
      setting == null &&
      level == null &&
      tag == null;

  /// Filters beyond text, sector and location, for the filter button badge.
  int get filterCount =>
      roles.length +
      kinds.length +
      (verifiedOnly ? 1 : 0) +
      (availableOnly ? 1 : 0) +
      (language != null ? 1 : 0) +
      (setting != null ? 1 : 0) +
      (level != null ? 1 : 0) +
      (tag != null ? 1 : 0);

  /// Asking for people only, places only, or both.
  bool get wantsPeople => kinds.isEmpty && setting == null && (sector == null || sector!.roles.isNotEmpty);
  bool get wantsPlaces => roles.isEmpty && tag == null && !availableOnly && (sector == null || sector!.placeKinds.isNotEmpty);

  CommunityQuery copyWith({
    String? text,
    CommunitySector? Function()? sector,
    Set<CommunityRole>? roles,
    Set<PlaceKind>? kinds,
    String? Function()? city,
    String? Function()? state,
    bool? nearMe,
    bool? verifiedOnly,
    bool? availableOnly,
    String? Function()? language,
    PlaceSetting? Function()? setting,
    String? Function()? level,
    String? Function()? tag,
  }) =>
      CommunityQuery(
        text: text ?? this.text,
        sector: sector == null ? this.sector : sector(),
        roles: roles ?? this.roles,
        kinds: kinds ?? this.kinds,
        city: city == null ? this.city : city(),
        state: state == null ? this.state : state(),
        nearMe: nearMe ?? this.nearMe,
        verifiedOnly: verifiedOnly ?? this.verifiedOnly,
        availableOnly: availableOnly ?? this.availableOnly,
        language: language == null ? this.language : language(),
        setting: setting == null ? this.setting : setting(),
        level: level == null ? this.level : level(),
        tag: tag == null ? this.tag : tag(),
      );

  /// "Near me" becomes the chosen city. Without one, it is dropped rather
  /// than guessed: location permission is never required.
  CommunityQuery resolveNearMe(String? here) =>
      !nearMe ? this : copyWith(nearMe: false, city: () => city ?? here);

  /// Only the filters, with [text] cleared.
  CommunityQuery get filtersOnly => copyWith(text: '');

  /// Query parameters for `GET /community/members` and `/community/places`.
  Map<String, String> toParams() => {
        if (text.isNotEmpty) 'q': text,
        if (sector != null) 'sector': sector!.name,
        if (roles.isNotEmpty) 'roles': roles.map((r) => r.name).join(','),
        if (kinds.isNotEmpty) 'kinds': kinds.map((k) => k.name).join(','),
        'city': ?city,
        'state': ?state,
        if (verifiedOnly) 'verified': 'true',
        if (availableOnly) 'available': 'true',
        'language': ?language,
        if (setting != null) 'setting': setting!.name,
        'level': ?level,
        'tag': ?tag,
      };

  // ─── Matching (the sample repository; the server applies the same rules) ──

  bool _inPlace(String city, String? state, [List<String> serves = const []]) {
    if (this.city != null && city != this.city && !serves.contains(this.city)) return false;
    if (this.state != null && state != this.state && !serves.any((c) => communityCities[c] == this.state)) {
      return false;
    }
    return true;
  }

  bool _textIn(List<String?> fields) {
    if (text.isEmpty) return true;
    final hay = fields.whereType<String>().join(' ').toLowerCase();
    return text.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).every(hay.contains);
  }

  bool matchesMember(CommunityMember m) {
    if (!wantsPeople) return false;
    if (roles.isNotEmpty && !roles.any(m.hasRole)) return false;
    if (sector != null && !m.roles.any((r) => r.role.sector == sector)) return false;
    if (!_inPlace(m.city, m.state, m.serviceArea)) return false;
    if (verifiedOnly && !(roles.isEmpty ? m.verified : roles.any(m.verifiedAs))) return false;
    if (availableOnly && (m.availability == null || m.availability == Availability.busy)) return false;
    if (language != null && !m.languages.contains(language)) return false;
    if (tag != null && !m.tags.contains(tag)) return false;
    if (level != null) {
      final l = level!.toLowerCase();
      if (m.level?.toLowerCase() != l && !m.tags.any((t) => t.toLowerCase().startsWith(l))) return false;
    }
    return _textIn([m.name, m.headline, m.city, m.state, m.rolesLabel, ...m.tags]);
  }

  bool matchesPlace(CommunityPlace p) {
    if (!wantsPlaces) return false;
    if (kinds.isNotEmpty && !kinds.contains(p.kind)) return false;
    if (sector != null && p.kind.sector != sector) return false;
    if (!_inPlace(p.city, p.state)) return false;
    if (verifiedOnly && !p.verified) return false;
    if (setting != null) {
      final s = p.setting;
      if (s == null) return false;
      if (setting == PlaceSetting.indoor && !s.hasIndoor) return false;
      if (setting == PlaceSetting.outdoor && !s.hasOutdoor) return false;
    }
    if (level != null &&
        !p.programs.any((x) => x.level == level || x.level == 'All levels') &&
        p.kind == PlaceKind.academy) {
      return false;
    }
    if (language != null || tag != null) return false;
    return _textIn([p.name, p.area, p.city, p.state, p.about, p.kind.label]);
  }

  // ─── Parsing ────────────────────────────────────────────────────────────

  static const _roleWords = {
    'referee': CommunityRole.referee,
    'referees': CommunityRole.referee,
    'ref': CommunityRole.referee,
    'refs': CommunityRole.referee,
    'scorekeeper': CommunityRole.scorekeeper,
    'scorekeepers': CommunityRole.scorekeeper,
    'scorer': CommunityRole.scorekeeper,
    'scorers': CommunityRole.scorekeeper,
    'umpire': CommunityRole.official,
    'umpires': CommunityRole.official,
    'official': CommunityRole.official,
    'officials': CommunityRole.official,
    'organizer': CommunityRole.organizer,
    'organizers': CommunityRole.organizer,
    'organiser': CommunityRole.organizer,
    'organisers': CommunityRole.organizer,
    'coach': CommunityRole.coach,
    'coaches': CommunityRole.coach,
    'coaching': CommunityRole.coach,
    'trainer': CommunityRole.trainer,
    'trainers': CommunityRole.trainer,
    'commentator': CommunityRole.commentator,
    'commentators': CommunityRole.commentator,
    'caster': CommunityRole.commentator,
    'streamer': CommunityRole.streamer,
    'streamers': CommunityRole.streamer,
    'streaming': CommunityRole.streamer,
    'photographer': CommunityRole.photographer,
    'photographers': CommunityRole.photographer,
    'creator': CommunityRole.creator,
    'creators': CommunityRole.creator,
    'player': CommunityRole.player,
    'players': CommunityRole.player,
    'partner': CommunityRole.player,
    'partners': CommunityRole.player,
  };

  static const _kindWords = {
    'club': PlaceKind.club,
    'clubs': PlaceKind.club,
    'academy': PlaceKind.academy,
    'academies': PlaceKind.academy,
    'court': PlaceKind.venue,
    'courts': PlaceKind.venue,
    'ground': PlaceKind.venue,
    'grounds': PlaceKind.venue,
    'venue': PlaceKind.venue,
    'venues': PlaceKind.venue,
    'facility': PlaceKind.venue,
    'facilities': PlaceKind.venue,
    'brand': PlaceKind.business,
    'brands': PlaceKind.business,
    'sponsor': PlaceKind.business,
    'sponsors': PlaceKind.business,
    'shop': PlaceKind.business,
  };

  static const _stopWords = {
    'find', 'a', 'an', 'the', 'near', 'in', 'at', 'for', 'around', 'me', 'my', 'pickleball', 'looking', 'need',
    'needed', 'required', 'want', 'i', 'who', 'is', 'are', 'of', 'to', 'and', 'with', 'tournament', 'tournaments',
    'training', 'india', 'some', 'good', 'best', 'show', 'nearby', 'local', 'event', 'events', 'match', 'matches',
  };

  /// Reads a sentence like "Find a referee near Ahmedabad" or "indoor courts
  /// Surat" into filters. Words it does not know stay as [text].
  static CommunityQuery parse(String input) {
    var s = ' ${input.toLowerCase().replaceAll(RegExp(r"[^a-z0-9\s]"), ' ')} ';
    final nearMe = s.contains(' near me ') || s.contains(' nearby ') || s.contains(' around me ');
    s = s.replaceAll(' score keeper', ' scorekeeper').replaceAll(' line judge', ' official');

    final roles = <CommunityRole>{};
    final kinds = <PlaceKind>{};
    String? city, state, language, level, tag;
    PlaceSetting? setting;
    var verified = false, available = false;
    final rest = <String>[];

    for (final w in s.split(RegExp(r'\s+')).where((w) => w.isNotEmpty)) {
      final cityHit = communityCities.keys.where((c) => c.toLowerCase() == w).firstOrNull;
      final stateHit = communityStates.where((x) => x.toLowerCase() == w).firstOrNull;
      final langHit = communityLanguages.where((x) => x.toLowerCase() == w).firstOrNull;
      final levelHit = communityLevels.where((x) => x.toLowerCase() == w || '${x.toLowerCase()}s' == w).firstOrNull;
      final tagHit = playerTags.where((x) => x.toLowerCase() == w || '${x.toLowerCase()}s' == w).firstOrNull;
      if (_roleWords[w] case final r?) {
        roles.add(r);
      } else if (_kindWords[w] case final k?) {
        kinds.add(k);
      } else if (cityHit != null) {
        city = cityHit;
      } else if (stateHit != null && stateHit != 'Delhi') {
        state = stateHit;
      } else if (langHit != null) {
        language = langHit;
      } else if (levelHit != null) {
        level = levelHit;
      } else if (tagHit != null) {
        tag = tagHit;
      } else if (w == 'indoor') {
        setting = PlaceSetting.indoor;
      } else if (w == 'outdoor') {
        setting = PlaceSetting.outdoor;
      } else if (w == 'verified') {
        verified = true;
      } else if (w == 'available') {
        available = true;
      } else if (!_stopWords.contains(w)) {
        rest.add(w);
      }
    }
    // "doubles partner": a tag on players, not a filter that hides places.
    if (tag != null && kinds.isEmpty) roles.add(CommunityRole.player);
    // A level with no role or place kind means coaching: "beginner training".
    if (level != null && roles.isEmpty && kinds.isEmpty && input.toLowerCase().contains('train')) {
      roles.add(CommunityRole.coach);
    }
    return CommunityQuery(
      text: rest.join(' '),
      roles: roles,
      kinds: kinds,
      city: city,
      state: city == null ? state : null,
      nearMe: nearMe && city == null && state == null,
      verifiedOnly: verified,
      availableOnly: available,
      language: language,
      setting: setting,
      level: level,
      tag: tag,
    );
  }

  /// Human summary of the filters, for "Showing referees in Ahmedabad".
  String describe() {
    final what = [
      ...roles.map((r) => r.plural.toLowerCase()),
      ...kinds.map((k) => k.plural.toLowerCase()),
    ];
    final where = city ?? state;
    return [
      if (verifiedOnly) 'verified',
      if (setting != null) setting!.label.toLowerCase(),
      if (level != null) level!.toLowerCase(),
      if (tag != null) tag!.toLowerCase(),
      what.isEmpty ? (sector?.title.toLowerCase() ?? 'everyone') : what.join(' and '),
      if (where != null) 'in $where',
      if (language != null) 'speaking $language',
      if (availableOnly) 'available now',
    ].join(' ');
  }

  @override
  bool operator ==(Object other) =>
      other is CommunityQuery &&
      other.text == text &&
      other.sector == sector &&
      _setEq(other.roles, roles) &&
      _setEq(other.kinds, kinds) &&
      other.city == city &&
      other.state == state &&
      other.nearMe == nearMe &&
      other.verifiedOnly == verifiedOnly &&
      other.availableOnly == availableOnly &&
      other.language == language &&
      other.setting == setting &&
      other.level == level &&
      other.tag == tag;

  @override
  int get hashCode => Object.hash(text, sector, Object.hashAllUnordered(roles), Object.hashAllUnordered(kinds), city,
      state, nearMe, verifiedOnly, availableOnly, language, setting, level, tag);
}

bool _setEq<T>(Set<T> a, Set<T> b) => a.length == b.length && a.containsAll(b);
