import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sample_persona.dart';
import '../../../sports/core/match_rules.dart';
import '../../auth/auth_controller.dart';
import '../../player/data/x_code.dart';

/// How many play on each side, and whether a side is one man and one woman.
enum MatchFormat {
  singles('Singles', 1),
  doubles('Doubles', 2),
  mixed('Mixed Doubles', 2);

  const MatchFormat(this.label, this.playersPerSide);
  final String label;
  final int playersPerSide;
}

/// Who may play, which decides the player pool the search offers.
enum Division {
  men("Men's"),
  women("Women's"),
  kids('Kids'),

  /// Grown-ups of both genders; only for mixed doubles, where Men's and
  /// Women's make no sense.
  open('Adults');

  const Division(this.label);
  final String label;

  /// Divisions offered for [format].
  static List<Division> forFormat(MatchFormat format) =>
      format == MatchFormat.mixed ? const [open, kids] : const [men, women, kids];
}

enum Gender { male, female }

/// The casual match category id (`racketCategories`), e.g. "mens_doubles".
String categoryIdFor(MatchFormat format, Division division) {
  final base = switch (format) {
    MatchFormat.singles => 'singles',
    MatchFormat.doubles => 'doubles',
    MatchFormat.mixed => 'mixed_doubles',
  };
  return switch (division) {
    Division.men => 'mens_$base',
    Division.women => 'womens_$base',
    Division.kids => 'kids_$base',
    Division.open => base,
  };
}

/// Reads a category id back into format and division. Plain "singles" and
/// "doubles" (old Home shortcuts) come back with no division.
(MatchFormat, Division?)? parseCategoryId(String id) {
  for (final format in MatchFormat.values) {
    for (final division in Division.forFormat(format)) {
      if (categoryIdFor(format, division) == id) return (format, division);
    }
  }
  return switch (id) {
    'singles' => (MatchFormat.singles, null),
    'doubles' => (MatchFormat.doubles, null),
    _ => null,
  };
}

/// Someone who can be put on court: a SkorX player, the signed-in player,
/// or a guest typed in by name.
@immutable
class MatchPlayer {
  const MatchPlayer({required this.id, required this.name, this.gender, this.kid = false, this.city, this.level, this.xCode});

  /// A player who is not on SkorX. Their id is made from the name, so
  /// starring "Raj" twice keeps one star.
  factory MatchPlayer.guest(String name, {Gender? gender, bool kid = false}) =>
      MatchPlayer(id: 'guest:${name.trim().toLowerCase()}', name: name.trim(), gender: gender, kid: kid);

  static const meId = 'me';

  /// Public id ("SKX-10482"), [meId], or `guest:<name>`.
  final String id;
  final String name;

  /// Null when unknown (the signed-in player, a guest): allowed anywhere.
  final Gender? gender;
  final bool kid;
  final String? city;
  final String? level;

  /// Their X code ("7K2Q"); null for guests.
  final String? xCode;

  bool get isMe => id == meId;
  bool get isGuest => id.startsWith('guest:');

  /// Whether this player belongs in [division]'s pool. Unknown genders are
  /// let in; the person setting up the match knows who is playing.
  bool fits(Division division, {Gender? requiredGender}) {
    if (requiredGender != null && gender != null && gender != requiredGender) return false;
    return switch (division) {
      Division.men => !kid && gender != Gender.female,
      Division.women => !kid && gender != Gender.male,
      Division.kids => kid || isMe || gender == null,
      Division.open => !kid,
    };
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (gender != null) 'gender': gender!.name,
        if (kid) 'kid': true,
        if (city != null) 'city': city,
        if (level != null) 'level': level,
        if (xCode != null) 'xCode': xCode,
      };

  factory MatchPlayer.fromJson(Map<String, dynamic> json) => MatchPlayer(
        id: json['id'] as String,
        name: json['name'] as String,
        gender: Gender.values.asNameMap()[json['gender']],
        kid: json['kid'] as bool? ?? false,
        city: json['city'] as String?,
        level: json['level'] as String?,
        xCode: json['xCode'] as String?,
      );

  @override
  bool operator ==(Object other) => other is MatchPlayer && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

enum StreamPrivacy {
  public('Public'),
  unlisted('Unlisted'),
  private('Private');

  const StreamPrivacy(this.label);
  final String label;
}

/// A YouTube Live broadcast of the match, set up before it starts.
@immutable
class YouTubeStream {
  const YouTubeStream({
    required this.title,
    this.privacy = StreamPrivacy.unlisted,
    this.streamKey = '',
    this.serverUrl = defaultServer,
    this.showScoreOverlay = true,
  });

  static const defaultServer = 'rtmp://a.rtmp.youtube.com/live2';

  final String title;
  final StreamPrivacy privacy;

  /// From YouTube Studio › Go live › Stream key.
  final String streamKey;
  final String serverUrl;

  /// Burn the live score into the video.
  final bool showScoreOverlay;

  bool get ready => title.trim().isNotEmpty && streamKey.trim().isNotEmpty;

  YouTubeStream copyWith({String? title, StreamPrivacy? privacy, String? streamKey, String? serverUrl, bool? showScoreOverlay}) =>
      YouTubeStream(
        title: title ?? this.title,
        privacy: privacy ?? this.privacy,
        streamKey: streamKey ?? this.streamKey,
        serverUrl: serverUrl ?? this.serverUrl,
        showScoreOverlay: showScoreOverlay ?? this.showScoreOverlay,
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'privacy': privacy.name,
        'streamKey': streamKey,
        'serverUrl': serverUrl,
        'showScoreOverlay': showScoreOverlay,
      };

  factory YouTubeStream.fromJson(Map<String, dynamic> json) => YouTubeStream(
        title: json['title'] as String? ?? '',
        privacy: StreamPrivacy.values.asNameMap()[json['privacy']] ?? StreamPrivacy.unlisted,
        streamKey: json['streamKey'] as String? ?? '',
        serverUrl: json['serverUrl'] as String? ?? defaultServer,
        showScoreOverlay: json['showScoreOverlay'] as bool? ?? true,
      );
}

// ─── Player pool ─────────────────────────────────────────────────────────

/// The last ten digits of a typed mobile number ("+91 98250 10412",
/// "098250-10412"), or null when fewer than ten digits were typed. Search
/// by number only matches a whole number, never part of one, so nobody can
/// browse other players' numbers.
String? mobileKey(String input) {
  final digits = input.replaceAll(RegExp(r'\D'), '');
  return digits.length < 10 ? null : digits.substring(digits.length - 10);
}

/// Players the match search can find. Becomes `GET /players?q&gender&age`.
abstract class MatchPlayerDirectory {
  Future<List<MatchPlayer>> search(String query);
}

final matchPlayerDirectoryProvider = Provider<MatchPlayerDirectory>((ref) {
  if (!kDebugMode || ref.watch(samplePersonaProvider) == SamplePersona.newcomer) return const _EmptyDirectory();
  return const SampleMatchPlayerDirectory();
});

final matchPlayerSearchProvider = FutureProvider.autoDispose.family<List<MatchPlayer>, String>(
  (ref, query) => ref.watch(matchPlayerDirectoryProvider).search(query),
);

/// Release builds until the endpoint exists: starred players, "me" and guests only.
class _EmptyDirectory implements MatchPlayerDirectory {
  const _EmptyDirectory();

  @override
  Future<List<MatchPlayer>> search(String query) async => const [];
}

/// Debug builds: a local club's worth of players, men, women and kids.
class SampleMatchPlayerDirectory implements MatchPlayerDirectory {
  const SampleMatchPlayerDirectory();

  static const _m = Gender.male;
  static const _f = Gender.female;

  static const players = [
    MatchPlayer(id: 'SKX-10412', name: 'Kamal Parmar', gender: _m, city: 'Ahmedabad', level: 'Advanced', xCode: 'D4JX'),
    MatchPlayer(id: 'SKX-10427', name: 'Anand Varsada', gender: _m, city: 'Ahmedabad', level: 'Advanced', xCode: '8AVN'),
    MatchPlayer(id: 'SKX-10544', name: 'Hardik Suthar', gender: _m, city: 'Ahmedabad', level: 'Intermediate', xCode: 'H9ST'),
    MatchPlayer(id: 'SKX-10503', name: 'Vivaan Gupta', gender: _m, city: 'Ahmedabad', level: 'Intermediate', xCode: 'G5VP'),
    MatchPlayer(id: 'SKX-10560', name: 'Anand Verma', gender: _m, city: 'Ahmedabad', level: 'Intermediate', xCode: '7AVE'),
    MatchPlayer(id: 'SKX-10233', name: 'Ishaan Patel', gender: _m, city: 'Surat', level: 'Advanced', xCode: '3PQE'),
    MatchPlayer(id: 'SKX-10291', name: 'Rohan Desai', gender: _m, city: 'Vadodara', level: 'Advanced', xCode: 'R8DZ'),
    MatchPlayer(id: 'SKX-10302', name: 'Arjun Trivedi', gender: _m, city: 'Rajkot', level: 'Intermediate', xCode: '5TJW'),
    MatchPlayer(id: 'SKX-10355', name: 'Kabir Rao', gender: _m, city: 'Gandhinagar', level: 'Intermediate', xCode: 'K2BR'),
    MatchPlayer(id: 'SKX-10611', name: 'Dev Patel', gender: _m, city: 'Ahmedabad', level: 'Intermediate', xCode: 'D8PT'),
    MatchPlayer(id: 'SKX-10718', name: 'Parth Bhatt', gender: _m, city: 'Gandhinagar', level: 'Beginner', xCode: 'P5BT'),
    MatchPlayer(id: 'SKX-10519', name: 'Riya Shah', gender: _f, city: 'Ahmedabad', level: 'Intermediate', xCode: 'R2SH'),
    MatchPlayer(id: 'SKX-10366', name: 'Anaya Nair', gender: _f, city: 'Surat', level: 'Intermediate', xCode: 'N6AY'),
    MatchPlayer(id: 'SKX-10590', name: 'Sara Khan', gender: _f, city: 'Vadodara', level: 'Intermediate', xCode: 'S3KZ'),
    MatchPlayer(id: 'SKX-10702', name: 'Nisha Kapoor', gender: _f, city: 'Ahmedabad', level: 'Beginner', xCode: 'N4KP'),
    MatchPlayer(id: 'SKX-10014', name: 'Tara Menon', gender: _f, city: 'Mumbai', level: 'Pro', xCode: 'T4MN'),
    MatchPlayer(id: 'SKX-10731', name: 'Zoya Qureshi', gender: _f, city: 'Surat', level: 'Beginner', xCode: 'Z7QU'),
    MatchPlayer(id: 'SKX-10648', name: 'Meera Joshi', gender: _f, city: 'Ahmedabad', level: 'Advanced', xCode: 'J6MA'),
    MatchPlayer(id: 'SKX-10801', name: 'Aarav Shah', gender: _m, kid: true, city: 'Ahmedabad', level: 'Beginner', xCode: 'A2SK'),
    MatchPlayer(id: 'SKX-10802', name: 'Vihaan Mehta', gender: _m, kid: true, city: 'Ahmedabad', level: 'Intermediate', xCode: 'V3HM'),
    MatchPlayer(id: 'SKX-10803', name: 'Kiaan Desai', gender: _m, kid: true, city: 'Surat', level: 'Beginner', xCode: 'K9DS'),
    MatchPlayer(id: 'SKX-10811', name: 'Diya Patel', gender: _f, kid: true, city: 'Ahmedabad', level: 'Intermediate', xCode: 'D6PY'),
    MatchPlayer(id: 'SKX-10812', name: 'Anika Rao', gender: _f, kid: true, city: 'Vadodara', level: 'Beginner', xCode: 'A8RN'),
    MatchPlayer(id: 'SKX-10813', name: 'Myra Iyer', gender: _f, kid: true, city: 'Ahmedabad', level: 'Beginner', xCode: 'M5YR'),
  ];

  /// Sample mobile numbers, looked up only by a whole number (see [mobileKey]).
  static final phones = {for (final p in players) p.id: '+91 98250 ${p.id.substring(4)}'};

  @override
  Future<List<MatchPlayer>> search(String query) async {
    final code = XCode.parse(query);
    if (code != null) return [for (final p in players) if (p.xCode == code) p];
    final mobile = mobileKey(query);
    if (mobile != null) return [for (final p in players) if (mobileKey(phones[p.id] ?? '') == mobile) p];
    final q = query.trim().toLowerCase();
    return [
      for (final p in players)
        if (q.isEmpty || '${p.name} ${p.id} ${p.city}'.toLowerCase().contains(q)) p,
    ];
  }
}

// ─── Starred players ─────────────────────────────────────────────────────

final starredPlayersProvider = NotifierProvider<StarredPlayersController, List<MatchPlayer>>(StarredPlayersController.new);

/// The people this player plays with most, kept on the phone so a casual
/// match is a tap per player. Guests can be starred too.
class StarredPlayersController extends Notifier<List<MatchPlayer>> {
  static const _key = 'skorx.starredPlayers';

  @override
  List<MatchPlayer> build() {
    _restore();
    return const [];
  }

  Future<void> _restore() async {
    final raw = await ref.read(preferencesProvider).getString(_key);
    if (raw == null) return;
    try {
      state = (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>().map(MatchPlayer.fromJson).toList();
    } catch (_) {
      // Unreadable stars are dropped rather than blocking match setup.
    }
  }

  bool isStarred(MatchPlayer p) => state.contains(p);

  Future<void> toggle(MatchPlayer p) async {
    state = isStarred(p) ? [...state.where((s) => s != p)] : [...state, p];
    await ref.read(preferencesProvider).setString(_key, jsonEncode(state.map((p) => p.toJson()).toList()));
  }
}

// ─── Last setup ──────────────────────────────────────────────────────────

/// What the last match was set up with, so the next one starts one tap
/// from ready: same type, rules, court and stream settings.
@immutable
class MatchSetupMemory {
  const MatchSetupMemory({this.format, this.division, this.rules, this.court, this.venue, this.stream});

  final MatchFormat? format;
  final Division? division;
  final MatchRules? rules;
  final String? court;
  final String? venue;
  final YouTubeStream? stream;

  Map<String, dynamic> toJson() => {
        'format': format?.name,
        'division': division?.name,
        'rules': rules?.toJson(),
        'court': court,
        'venue': venue,
        'stream': stream?.toJson(),
      };

  factory MatchSetupMemory.fromJson(Map<String, dynamic> json) => MatchSetupMemory(
        format: MatchFormat.values.asNameMap()[json['format']],
        division: Division.values.asNameMap()[json['division']],
        rules: json['rules'] == null ? null : MatchRules.parse(json['rules']).rules,
        court: json['court'] as String?,
        venue: json['venue'] as String?,
        stream: json['stream'] == null ? null : YouTubeStream.fromJson(json['stream'] as Map<String, dynamic>),
      );
}

final matchSetupMemoryProvider =
    NotifierProvider<MatchSetupMemoryController, MatchSetupMemory>(MatchSetupMemoryController.new);

class MatchSetupMemoryController extends Notifier<MatchSetupMemory> {
  static const _key = 'skorx.lastMatchSetup';

  /// Resolves once the saved setup (if any) has been read.
  late final Future<void> ready;

  @override
  MatchSetupMemory build() {
    ready = _restore();
    return const MatchSetupMemory();
  }

  Future<void> _restore() async {
    final raw = await ref.read(preferencesProvider).getString(_key);
    if (raw == null) return;
    try {
      state = MatchSetupMemory.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {}
  }

  Future<void> remember(MatchSetupMemory memory) async {
    state = memory;
    await ref.read(preferencesProvider).setString(_key, jsonEncode(memory.toJson()));
  }
}

// ─── Saved with the match ────────────────────────────────────────────────

/// Everything about a casual match beyond players and rules: where it is,
/// who stands where at the first serve, and the stream.
@immutable
class MatchDetails {
  const MatchDetails({
    this.division,
    this.court,
    this.venue,
    this.teamA,
    this.teamB,
    this.aStartsLeft = true,
    this.sideAIds = const [],
    this.sideBIds = const [],
    this.stream,
  });

  final Division? division;
  final String? court;
  final String? venue;

  /// Optional team names for doubles.
  final String? teamA;
  final String? teamB;

  /// Whether side A starts at the left end of the court as the scorer sees it.
  final bool aStartsLeft;

  /// Player ids in the same court order as the names (see [LocalMatch.sideA]).
  final List<String> sideAIds;
  final List<String> sideBIds;
  final YouTubeStream? stream;

  String? get courtLabel {
    final parts = [court, venue].whereType<String>().where((s) => s.trim().isNotEmpty).toList();
    return parts.isEmpty ? null : parts.join(' · ');
  }

  Map<String, dynamic> toJson() => {
        if (division != null) 'division': division!.name,
        if (court != null) 'court': court,
        if (venue != null) 'venue': venue,
        if (teamA != null) 'teamA': teamA,
        if (teamB != null) 'teamB': teamB,
        'aStartsLeft': aStartsLeft,
        'sideAIds': sideAIds,
        'sideBIds': sideBIds,
        if (stream != null) 'stream': stream!.toJson(),
      };

  factory MatchDetails.fromJson(Map<String, dynamic> json) => MatchDetails(
        division: Division.values.asNameMap()[json['division']],
        court: json['court'] as String?,
        venue: json['venue'] as String?,
        teamA: json['teamA'] as String?,
        teamB: json['teamB'] as String?,
        aStartsLeft: json['aStartsLeft'] as bool? ?? true,
        sideAIds: ((json['sideAIds'] as List<dynamic>?) ?? const []).cast<String>(),
        sideBIds: ((json['sideBIds'] as List<dynamic>?) ?? const []).cast<String>(),
        stream: json['stream'] == null ? null : YouTubeStream.fromJson(json['stream'] as Map<String, dynamic>),
      );
}
