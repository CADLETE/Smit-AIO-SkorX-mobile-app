import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/sample_latency.dart';
import '../../../core/sample_persona.dart';
import '../../auth/auth_controller.dart';
import '../../organizer/data/sample_organizer_repository.dart';
import '../../player/data/player_repository.dart';

/// One event within a tournament a player enters, e.g. "Men's Doubles · Intermediate".
class TournamentCategory {
  const TournamentCategory({
    required this.id,
    required this.name,
    required this.format,
    required this.level,
    required this.fee,
    required this.capacity,
    required this.registered,
  });

  final String id;
  final String name;
  final PlayCategory format;
  final String level;

  /// Entry fee per player, in rupees.
  final int fee;
  final int capacity;
  final int registered;

  bool get full => registered >= capacity;
  int get spotsLeft => (capacity - registered).clamp(0, capacity);
  bool get needsPartner => format != PlayCategory.singles;
}

enum RegistrationWindow { open, closingSoon, full, closed }

enum TournamentPhase { upcoming, live, completed }

class Tournament {
  const Tournament({
    required this.id,
    required this.name,
    required this.organizer,
    required this.city,
    required this.venue,
    required this.start,
    required this.end,
    required this.registrationDeadline,
    required this.categories,
    this.organizerVerified = false,
    this.address,
    this.distanceKm,
    this.prizePool,
    this.prizeNote,
    this.format = 'Group stage, then knockout',
    this.rules = const [],
    this.schedule = const [],
    this.liveScoring = true,
    this.liveStreaming = false,
    this.region,
    this.country = 'India',
    this.series,
    this.bannerUrl,
    this.logoUrl,
  });

  final String id;
  final String name;
  final String organizer;
  final bool organizerVerified;
  final String city;
  final String venue;
  final String? address;
  final double? distanceKm;
  final DateTime start;
  final DateTime end;
  final DateTime registrationDeadline;
  final List<TournamentCategory> categories;

  /// Total prize money in rupees, when there is any.
  final int? prizePool;
  final String? prizeNote;
  final String format;
  final List<String> rules;

  /// (when, what), in order.
  final List<(DateTime, String)> schedule;
  final bool liveScoring;
  final bool liveStreaming;

  /// State or province of [city]; null where there is none.
  final String? region;
  final String country;

  /// The tour it belongs to, e.g. "SPT 2026", so a series can be searched.
  final String? series;

  /// The organiser's uploaded banner and logo. Without them the card draws
  /// its own SkorX art (`TournamentBanner`).
  final String? bannerUrl;
  final String? logoUrl;

  /// "Ahmedabad, Gujarat".
  String get placeLabel => [city, if (region != null && region != city) region!].join(', ');

  int get minFee => categories.isEmpty ? 0 : categories.map((c) => c.fee).reduce((a, b) => a < b ? a : b);
  int get playersRegistered => categories.fold(0, (sum, c) => sum + c.registered);
  int get capacity => categories.fold(0, (sum, c) => sum + c.capacity);
  Set<String> get levels => {for (final c in categories) c.level};
  Set<PlayCategory> get formats => {for (final c in categories) c.format};

  TournamentPhase phase(DateTime now) {
    if (now.isBefore(start)) return TournamentPhase.upcoming;
    if (now.isAfter(end.add(const Duration(days: 1)))) return TournamentPhase.completed;
    return TournamentPhase.live;
  }

  RegistrationWindow window(DateTime now) {
    if (now.isAfter(registrationDeadline) || phase(now) != TournamentPhase.upcoming) return RegistrationWindow.closed;
    if (categories.every((c) => c.full)) return RegistrationWindow.full;
    if (registrationDeadline.difference(now).inDays < 3) return RegistrationWindow.closingSoon;
    return RegistrationWindow.open;
  }
}

enum RegistrationStatus { confirmed, pendingPayment, waitlisted }

class Registration {
  const Registration({
    required this.id,
    required this.tournamentId,
    required this.categoryId,
    required this.categoryName,
    required this.amountPaid,
    required this.registeredAt,
    this.partner,
    this.status = RegistrationStatus.confirmed,
  });

  final String id;
  final String tournamentId;
  final String categoryId;
  final String categoryName;
  final String? partner;
  final int amountPaid;
  final DateTime registeredAt;
  final RegistrationStatus status;
}

/// A tournament the player is in, with how they are doing.
class MyTournament {
  const MyTournament({required this.tournament, required this.registration, this.result, this.nextMatch});

  final Tournament tournament;
  final Registration registration;

  /// Where the player finished or is now: "Semi-final", "Winner".
  final String? result;

  /// "Round of 16 · Tomorrow 7:30 PM".
  final String? nextMatch;
}

class TournamentDetail {
  const TournamentDetail(this.tournament, this.myRegistration);

  final Tournament tournament;
  final Registration? myRegistration;
}

enum TournamentSort {
  soonest('Soonest'),
  nearest('Nearest'),
  lowestFee('Lowest fee');

  const TournamentSort(this.label);
  final String label;
}

enum DateWindow {
  any('Any date'),
  today('Today'),
  thisWeek('This week'),
  thisMonth('This month'),
  upcoming('Upcoming'),
  past('Past');

  const DateWindow(this.label);
  final String label;

  /// Whether a tournament running [start]–[end] falls in this window.
  bool includes(DateTime start, DateTime end, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    bool overlaps(int days) => !start.isAfter(today.add(Duration(days: days))) && !end.isBefore(today);
    return switch (this) {
      DateWindow.any => true,
      DateWindow.today => overlaps(1),
      DateWindow.thisWeek => overlaps(7),
      DateWindow.thisMonth => overlaps(31),
      DateWindow.upcoming => start.isAfter(now),
      DateWindow.past => end.add(const Duration(days: 1)).isBefore(now),
    };
  }
}

/// A place to narrow discovery to, from the widest: country, state, city.
class PlaceFilter {
  const PlaceFilter({this.country, this.region, this.city});

  final String? country;
  final String? region;
  final String? city;

  bool get isAny => country == null && region == null && city == null;

  /// The narrowest part: "Ahmedabad", "Gujarat", "India".
  String? get label => city ?? region ?? country;

  bool includes({required String? country, required String? region, required String city}) =>
      (this.country == null || this.country == country) &&
      (this.region == null || this.region == region) &&
      (this.city == null || this.city == city);

  Map<String, dynamic> toJson() => {'country': country, 'region': region, 'city': city};

  factory PlaceFilter.fromJson(Map<String, dynamic>? json) => PlaceFilter(
        country: json?['country'] as String?,
        region: json?['region'] as String?,
        city: json?['city'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      other is PlaceFilter && other.country == country && other.region == region && other.city == city;

  @override
  int get hashCode => Object.hash(country, region, city);
}

/// What the player filtered discovery by. Remembered on the device.
class TournamentFilters {
  const TournamentFilters({
    this.text = '',
    this.nearby = false,
    this.dates = DateWindow.any,
    this.levels = const {},
    this.formats = const {},
    this.maxFee,
    this.sort = TournamentSort.soonest,
    this.place = const PlaceFilter(),
    this.phases = const {},
  });

  final String text;
  final bool nearby;
  final DateWindow dates;
  final Set<String> levels;
  final Set<PlayCategory> formats;
  final int? maxFee;
  final TournamentSort sort;
  final PlaceFilter place;

  /// Live, upcoming, completed. Empty: live and upcoming, or completed for
  /// [DateWindow.past].
  final Set<TournamentPhase> phases;

  /// How many filters beyond search and sort are on, for the filter button badge.
  int get activeCount =>
      (nearby ? 1 : 0) +
      (dates != DateWindow.any ? 1 : 0) +
      levels.length +
      formats.length +
      (maxFee != null ? 1 : 0) +
      (place.isAny ? 0 : 1) +
      phases.length;

  TournamentFilters copyWith({
    String? text,
    bool? nearby,
    DateWindow? dates,
    Set<String>? levels,
    Set<PlayCategory>? formats,
    int? Function()? maxFee,
    TournamentSort? sort,
    PlaceFilter? place,
    Set<TournamentPhase>? phases,
  }) =>
      TournamentFilters(
        text: text ?? this.text,
        nearby: nearby ?? this.nearby,
        dates: dates ?? this.dates,
        levels: levels ?? this.levels,
        formats: formats ?? this.formats,
        maxFee: maxFee == null ? this.maxFee : maxFee(),
        sort: sort ?? this.sort,
        place: place ?? this.place,
        phases: phases ?? this.phases,
      );

  TournamentFilters cleared() => TournamentFilters(text: text, sort: sort);

  bool matches(Tournament t, DateTime now) {
    final q = text.trim().toLowerCase();
    if (q.isNotEmpty &&
        !'${t.name} ${t.series ?? ''} ${t.city} ${t.region ?? ''} ${t.venue} ${t.organizer}'.toLowerCase().contains(q)) {
      return false;
    }
    final phase = t.phase(now);
    if (phases.isEmpty ? (phase == TournamentPhase.completed) != (dates == DateWindow.past) : !phases.contains(phase)) {
      return false;
    }
    if (!place.includes(country: t.country, region: t.region, city: t.city)) return false;
    if (nearby && (t.distanceKm ?? 999) > 25) return false;
    if (!dates.includes(t.start, t.end, now)) return false;
    if (levels.isNotEmpty && t.levels.intersection(levels).isEmpty) return false;
    if (formats.isNotEmpty && t.formats.intersection(formats).isEmpty) return false;
    if (maxFee != null && t.minFee > maxFee!) return false;
    return true;
  }

  Map<String, dynamic> toJson() => {
        'nearby': nearby,
        'dates': dates.name,
        'levels': levels.toList(),
        'formats': formats.map((f) => f.name).toList(),
        'maxFee': maxFee,
        'sort': sort.name,
        'place': place.toJson(),
        'phases': phases.map((p) => p.name).toList(),
      };

  factory TournamentFilters.fromJson(Map<String, dynamic> json) => TournamentFilters(
        nearby: json['nearby'] as bool? ?? false,
        dates: DateWindow.values.asNameMap()[json['dates']] ?? DateWindow.any,
        levels: {...((json['levels'] as List<dynamic>?) ?? const []).cast<String>()},
        formats: {
          for (final f in ((json['formats'] as List<dynamic>?) ?? const []).cast<String>())
            if (PlayCategory.values.asNameMap()[f] != null) PlayCategory.values.asNameMap()[f]!,
        },
        maxFee: json['maxFee'] as int?,
        sort: TournamentSort.values.asNameMap()[json['sort']] ?? TournamentSort.soonest,
        place: PlaceFilter.fromJson(json['place'] as Map<String, dynamic>?),
        phases: {
          for (final p in ((json['phases'] as List<dynamic>?) ?? const []).cast<String>())
            if (TournamentPhase.values.asNameMap()[p] != null) TournamentPhase.values.asNameMap()[p]!,
        },
      );
}

const skillLevels = ['Beginner', 'Intermediate', 'Advanced', 'Open'];

/// Tournament data for players. Method names mirror the endpoints they will
/// call (docs/PLAYER-APP.md §2).
abstract class TournamentRepository {
  /// `GET /tournaments?status=upcoming,live&…`
  Future<List<Tournament>> discover();

  /// `GET /tournaments/:id` plus the caller's registration.
  Future<TournamentDetail> detail(String id);

  /// `GET /me/registrations`
  Future<List<MyTournament>> mine();

  /// `POST /tournaments/:id/registrations`, then payment.
  Future<Registration> register(String tournamentId, String categoryId, {String? partner});
}

final tournamentRepositoryProvider = Provider<TournamentRepository>(
  (ref) => kDebugMode
      ? SampleTournamentRepository(
          latency: ref.watch(sampleLatencyProvider),
          // Debug builds share one store with the organiser screens, like
          // the real API: what an organiser publishes, players can find.
          organizer: ref.watch(sampleOrganizerRepositoryProvider),
          newcomer: ref.watch(samplePersonaProvider) == SamplePersona.newcomer,
          playerName: () => switch (ref.read(authControllerProvider)) {
            SignedIn(:final user) => user.name,
            _ => '',
          },
        )
      : const EmptyTournamentRepository(),
);

/// Refreshes a provider when an organiser changes tournament data. Stands in
/// for the realtime stream (ARCHITECTURE.md §7) in debug builds.
void _refreshOnOrganizerChanges(Ref ref) {
  if (!kDebugMode) return;
  final sub = ref.watch(sampleOrganizerRepositoryProvider).allEvents.listen((_) => ref.invalidateSelf());
  ref.onDispose(sub.cancel);
}

final discoverTournamentsProvider = FutureProvider<List<Tournament>>((ref) {
  _refreshOnOrganizerChanges(ref);
  return ref.watch(tournamentRepositoryProvider).discover();
});

final tournamentDetailProvider = FutureProvider.family<TournamentDetail, String>((ref, id) {
  _refreshOnOrganizerChanges(ref);
  return ref.watch(tournamentRepositoryProvider).detail(id);
});

final myTournamentsProvider = FutureProvider<List<MyTournament>>((ref) {
  _refreshOnOrganizerChanges(ref);
  return ref.watch(tournamentRepositoryProvider).mine();
});

/// Every place a tournament is played, for the location filter: countries,
/// their states, and the states' cities. Worked out from the tournaments, so
/// a new city shows up as soon as a tournament is announced there.
final tournamentPlacesProvider = Provider<List<PlaceOption>>((ref) {
  final all = ref.watch(discoverTournamentsProvider).value ?? const <Tournament>[];
  return placeOptions([for (final t in all) (country: t.country, region: t.region, city: t.city)]);
});

/// One country, with its states and cities, as the location filter lists them.
class PlaceOption {
  const PlaceOption(this.country, this.regions);

  final String country;

  /// State → cities, in order. A country without states has one entry under
  /// its own name.
  final Map<String, List<String>> regions;
}

List<PlaceOption> placeOptions(Iterable<({String country, String? region, String city})> places) {
  final tree = <String, Map<String, Set<String>>>{};
  for (final p in places) {
    tree.putIfAbsent(p.country, () => {}).putIfAbsent(p.region ?? p.city, () => {}).add(p.city);
  }
  final countries = tree.keys.toList()..sort((a, b) => a == 'India' ? -1 : b == 'India' ? 1 : a.compareTo(b));
  return [
    for (final c in countries)
      PlaceOption(c, {
        for (final r in (tree[c]!.keys.toList()..sort())) r: (tree[c]![r]!.toList()..sort()),
      }),
  ];
}

/// Discovery results after the player's filters, sorted.
final filteredTournamentsProvider = Provider<AsyncValue<List<Tournament>>>((ref) {
  final filters = ref.watch(tournamentFiltersProvider);
  final now = DateTime.now();
  return ref.watch(discoverTournamentsProvider).whenData((all) {
    final list = all.where((t) => filters.matches(t, now)).toList();
    switch (filters.sort) {
      case TournamentSort.soonest:
        // Live first, then soonest; past tournaments newest first.
        list.sort((a, b) {
          final pa = a.phase(now), pb = b.phase(now);
          if (pa != pb) return pa == TournamentPhase.live ? -1 : pb == TournamentPhase.live ? 1 : pa.index.compareTo(pb.index);
          return pa == TournamentPhase.completed ? b.start.compareTo(a.start) : a.start.compareTo(b.start);
        });
      case TournamentSort.nearest:
        list.sort((a, b) => (a.distanceKm ?? 999).compareTo(b.distanceKm ?? 999));
      case TournamentSort.lowestFee:
        list.sort((a, b) => a.minFee.compareTo(b.minFee));
    }
    return list;
  });
});

final tournamentFiltersProvider =
    NotifierProvider<TournamentFiltersController, TournamentFilters>(TournamentFiltersController.new);

/// The discovery filters, remembered on this phone (search text is not).
class TournamentFiltersController extends Notifier<TournamentFilters> {
  static const _key = 'skorx.tournamentFilters';

  @override
  TournamentFilters build() {
    Future.microtask(_load);
    return const TournamentFilters();
  }

  Future<void> _load() async {
    try {
      final raw = await ref.read(preferencesProvider).getString(_key);
      if (raw != null) state = TournamentFilters.fromJson(jsonDecode(raw) as Map<String, dynamic>).copyWith(text: state.text);
    } catch (_) {
      // Unreadable saved filters: start clean.
    }
  }

  void update(TournamentFilters Function(TournamentFilters) change) {
    state = change(state);
    ref.read(preferencesProvider).setString(_key, jsonEncode(state.toJson()));
  }

  void search(String text) => state = state.copyWith(text: text);
}

class EmptyTournamentRepository implements TournamentRepository {
  const EmptyTournamentRepository();

  @override
  Future<List<Tournament>> discover() async => const [];

  @override
  Future<TournamentDetail> detail(String id) async =>
      throw const ApiException('NOT_FOUND', 'This tournament is no longer available.');

  @override
  Future<List<MyTournament>> mine() async => const [];

  @override
  Future<Registration> register(String tournamentId, String categoryId, {String? partner}) async =>
      throw const ApiException('NOT_AVAILABLE', 'Registration opens in the next update.');
}

/// Debug builds: realistic tournaments to design and test against.
/// Registrations made here last until the app restarts.
class SampleTournamentRepository implements TournamentRepository {
  SampleTournamentRepository({
    this.latency = const Duration(milliseconds: 400),
    this.organizer,
    this.playerName,
    bool newcomer = false,
  }) {
    final now = DateTime.now();
    // A brand-new player has not entered anything yet.
    if (!newcomer) {
      _registrations.addAll([
      Registration(
        id: 'r-1',
        tournamentId: 't-open',
        categoryId: 't-open-xd-int',
        categoryName: 'Mixed Doubles · Intermediate',
        partner: 'Riya Shah',
        amountPaid: 600,
        registeredAt: now.subtract(const Duration(days: 4)),
      ),
      Registration(
        id: 'r-2',
        tournamentId: 't-monsoon',
        categoryId: 't-monsoon-xd',
        categoryName: 'Mixed Doubles · Open',
        partner: 'Riya Shah',
        amountPaid: 500,
        registeredAt: now.subtract(const Duration(days: 40)),
      ),
      Registration(
        id: 'r-3',
        tournamentId: 't-league',
        categoryId: 't-league-md',
        categoryName: "Men's Doubles · Intermediate",
        partner: 'Kamal Parmar',
        amountPaid: 400,
        registeredAt: now.subtract(const Duration(days: 12)),
      ),
    ]);
    }
  }

  final Duration latency;

  /// Organiser-run tournaments in the same debug store.
  final SampleOrganizerRepository? organizer;

  /// The signed-in player's name, for registrations sent to an organiser.
  final String Function()? playerName;
  final List<Registration> _registrations = [];
  late final List<Tournament> _samples = _sampleTournaments(DateTime.now());

  List<Tournament> get _all => [
        ..._samples,
        ...?organizer?.playerTournaments().where((t) => _samples.every((s) => s.id != t.id)),
      ];

  @override
  Future<List<Tournament>> discover() async {
    await simulateLatency(latency);
    return _all;
  }

  @override
  Future<TournamentDetail> detail(String id) async {
    await simulateLatency(latency);
    final t = _all.where((t) => t.id == id).firstOrNull;
    if (t == null) throw const ApiException('NOT_FOUND', 'This tournament is no longer available.');
    return TournamentDetail(t, _registrations.where((r) => r.tournamentId == id).firstOrNull);
  }

  @override
  Future<List<MyTournament>> mine() async {
    await simulateLatency(latency);
    final now = DateTime.now();
    return [
      for (final r in _registrations)
        if (_all.where((t) => t.id == r.tournamentId).firstOrNull case final t?)
          MyTournament(
            tournament: t,
            registration: r,
            result: switch (t.id) {
              't-monsoon' => 'Runner-up',
              't-league' => 'Playing the quarter-final',
              _ => null,
            },
            nextMatch: t.phase(now) == TournamentPhase.completed
                ? null
                : t.id == 't-league'
                    ? 'Semi-final · Court 01 · 7:30 PM'
                    : 'Round of 16 · Draws out 2 days before',
          ),
    ];
  }

  @override
  Future<Registration> register(String tournamentId, String categoryId, {String? partner}) async {
    await simulateLatency(latency * 2);
    final t = _all.firstWhere((t) => t.id == tournamentId);
    final c = t.categories.firstWhere((c) => c.id == categoryId);
    if (c.full) throw const ApiException('CATEGORY_FULL', 'This category just filled up. Pick another one.');
    if (organizer?.owns(tournamentId) ?? false) {
      // Lands in the organiser's registration queue for approval.
      organizer!.registerPlayer(tournamentId, categoryId, playerName: playerName?.call() ?? '', partner: partner);
    }
    final registration = Registration(
      id: 'r-${_registrations.length + 1}',
      tournamentId: tournamentId,
      categoryId: categoryId,
      categoryName: '${c.name} · ${c.level}',
      partner: partner,
      amountPaid: c.fee,
      registeredAt: DateTime.now(),
    );
    _registrations.add(registration);
    return registration;
  }
}

List<Tournament> _sampleTournaments(DateTime now) {
  DateTime day(int d, [int hour = 8]) => DateTime(now.year, now.month, now.day + d, hour);

  TournamentCategory cat(String id, String name, PlayCategory f, String level, int fee, int cap, int reg) =>
      TournamentCategory(id: id, name: name, format: f, level: level, fee: fee, capacity: cap, registered: reg);

  const rules = [
    'USA Pickleball rules apply.',
    'Games to 11, win by 2. Finals best of 3.',
    'Report 30 minutes before your first match.',
    'Paddles must be on the approved list.',
    'Non-marking court shoes only.',
  ];

  return [
    Tournament(
      id: 't-open',
      name: 'SkorX Open 2026',
      organizer: 'SkorX Events',
      organizerVerified: true,
      city: 'Ahmedabad',
      region: 'Gujarat',
      venue: 'Smash Arena',
      address: 'SG Highway, Ahmedabad',
      distanceKm: 4.2,
      start: day(9),
      end: day(11, 20),
      registrationDeadline: day(6, 23),
      prizePool: 200000,
      prizeNote: 'Trophies and prize money for the top three in every category.',
      liveStreaming: true,
      rules: rules,
      schedule: [
        (day(9, 7), 'Check-in and warm-up'),
        (day(9, 8), 'Group stage: all categories'),
        (day(10, 8), 'Round of 16 and quarter-finals'),
        (day(11, 16), 'Semi-finals and finals'),
      ],
      categories: [
        cat('t-open-md-int', "Men's Doubles", PlayCategory.doubles, 'Intermediate', 500, 64, 58),
        cat('t-open-wd-int', "Women's Doubles", PlayCategory.doubles, 'Intermediate', 500, 32, 18),
        cat('t-open-xd-int', 'Mixed Doubles', PlayCategory.mixed, 'Intermediate', 600, 48, 40),
        cat('t-open-ms-adv', "Men's Singles", PlayCategory.singles, 'Advanced', 700, 32, 12),
      ],
    ),
    Tournament(
      id: 't-league',
      name: 'Ahmedabad Pickle League',
      organizer: 'CADLETE Pickleball',
      organizerVerified: true,
      city: 'Ahmedabad',
      region: 'Gujarat',
      venue: 'CADLETE Club',
      address: 'Bodakdev, Ahmedabad',
      distanceKm: 6.8,
      start: day(-1),
      end: day(1, 20),
      registrationDeadline: day(-5),
      liveStreaming: true,
      rules: rules,
      schedule: [
        (day(-1, 8), 'League matches'),
        (day(0, 8), 'Quarter-finals'),
        (day(1, 17), 'Finals'),
      ],
      categories: [
        cat('t-league-md', "Men's Doubles", PlayCategory.doubles, 'Intermediate', 400, 32, 32),
        cat('t-league-xd', 'Mixed Doubles', PlayCategory.mixed, 'Open', 400, 24, 24),
      ],
    ),
    Tournament(
      id: 't-blitz',
      name: 'Pickle Blitz Night Series',
      organizer: 'Pickle Blitz Arena',
      city: 'Ahmedabad',
      region: 'Gujarat',
      venue: 'Pickle Blitz Arena',
      address: 'Prahlad Nagar, Ahmedabad',
      distanceKm: 2.4,
      start: day(3, 19),
      end: day(3, 23),
      registrationDeadline: day(2, 18),
      format: 'Round robin, 1 game to 15',
      prizeNote: 'Winners get a free month of court time.',
      rules: rules,
      schedule: [(day(3, 19), 'Round robin'), (day(3, 22), 'Final')],
      categories: [
        cat('t-blitz-open', 'Open Doubles', PlayCategory.doubles, 'Beginner', 300, 24, 17),
        cat('t-blitz-xd', 'Mixed Doubles', PlayCategory.mixed, 'Beginner', 300, 16, 9),
      ],
    ),
    Tournament(
      id: 't-surat',
      name: 'Surat Smash Championship',
      organizer: 'Surat Pickleball Association',
      organizerVerified: true,
      city: 'Surat',
      region: 'Gujarat',
      venue: 'Diamond Sports Hub',
      address: 'Vesu, Surat',
      distanceKm: 264,
      start: day(24),
      end: day(26, 20),
      registrationDeadline: day(18),
      prizePool: 150000,
      rules: rules,
      schedule: [(day(24, 8), 'Groups'), (day(26, 15), 'Finals')],
      categories: [
        cat('t-surat-md', "Men's Doubles", PlayCategory.doubles, 'Advanced', 800, 48, 21),
        cat('t-surat-ms', "Men's Singles", PlayCategory.singles, 'Open', 600, 32, 11),
        cat('t-surat-ws', "Women's Singles", PlayCategory.singles, 'Open', 600, 24, 6),
      ],
    ),
    Tournament(
      id: 't-juniors',
      name: 'Gujarat Juniors Cup',
      organizer: 'Gujarat Pickleball',
      city: 'Vadodara',
      region: 'Gujarat',
      venue: 'Sayaji Sports Complex',
      distanceKm: 112,
      start: day(38),
      end: day(39, 18),
      registrationDeadline: day(30),
      liveScoring: true,
      rules: rules,
      schedule: [(day(38, 8), 'All categories')],
      categories: [
        cat('t-jr-u18', 'Under 18 Singles', PlayCategory.singles, 'Beginner', 0, 32, 8),
        cat('t-jr-u18d', 'Under 18 Doubles', PlayCategory.doubles, 'Beginner', 0, 24, 4),
      ],
    ),
    Tournament(
      id: 't-monsoon',
      name: 'CADLETE Monsoon Cup',
      organizer: 'CADLETE Pickleball',
      organizerVerified: true,
      city: 'Ahmedabad',
      region: 'Gujarat',
      venue: 'CADLETE Club',
      distanceKm: 6.8,
      start: day(-27),
      end: day(-25, 20),
      registrationDeadline: day(-32),
      rules: rules,
      categories: [cat('t-monsoon-xd', 'Mixed Doubles', PlayCategory.mixed, 'Open', 500, 32, 32)],
    ),
    // The rest of the SkorX universe: other cities, other countries.
    Tournament(
      id: 't-spt-amd',
      name: 'SPT 2026 Ahmedabad',
      series: 'SPT 2026',
      organizer: 'SkorX Pro Tour',
      organizerVerified: true,
      city: 'Ahmedabad',
      region: 'Gujarat',
      venue: 'Riverside Courts',
      address: 'Sabarmati Riverfront, Ahmedabad',
      distanceKm: 3.1,
      start: day(-1),
      end: day(1, 2),
      registrationDeadline: day(-8),
      prizePool: 300000,
      liveStreaming: true,
      format: 'Knockout, best of 3',
      rules: rules,
      categories: [cat('t-spt-amd-md', "Men's Doubles", PlayCategory.doubles, 'Open', 800, 16, 16)],
    ),
    Tournament(
      id: 't-spt-surat',
      name: 'SPT 2026 Surat',
      series: 'SPT 2026',
      organizer: 'SkorX Pro Tour',
      organizerVerified: true,
      city: 'Surat',
      region: 'Gujarat',
      venue: 'Diamond Sports Hub',
      distanceKm: 264,
      start: day(-20),
      end: day(-19, 20),
      registrationDeadline: day(-27),
      prizePool: 250000,
      format: 'Knockout, best of 3',
      rules: rules,
      categories: [cat('t-spt-surat-xd', 'Mixed Doubles', PlayCategory.mixed, 'Open', 700, 16, 16)],
    ),
    Tournament(
      id: 't-mumbai',
      name: 'Mumbai Pickleball Masters',
      organizer: 'Maharashtra Pickleball Association',
      organizerVerified: true,
      city: 'Mumbai',
      region: 'Maharashtra',
      venue: 'NSCI Dome',
      address: 'Worli, Mumbai',
      distanceKm: 524,
      start: day(-1, 7),
      end: day(1, 21),
      registrationDeadline: day(-6),
      prizePool: 400000,
      liveStreaming: true,
      format: 'Knockout, best of 3',
      rules: rules,
      categories: [cat('t-mumbai-ms', "Men's Singles", PlayCategory.singles, 'Advanced', 900, 16, 16)],
    ),
    Tournament(
      id: 't-blr',
      name: 'Bengaluru Paddle Open',
      organizer: 'Koramangala Paddle Club',
      city: 'Bengaluru',
      region: 'Karnataka',
      venue: 'Koramangala Paddle Club',
      distanceKm: 1490,
      start: day(2, 8),
      end: day(3, 20),
      registrationDeadline: day(-1),
      format: 'Knockout, best of 3',
      rules: rules,
      categories: [cat('t-blr-md', 'Open Doubles', PlayCategory.doubles, 'Intermediate', 600, 16, 16)],
    ),
    Tournament(
      id: 't-sg',
      name: 'Singapore Pickle Cup',
      organizer: 'Pickleball Singapore',
      organizerVerified: true,
      city: 'Singapore',
      country: 'Singapore',
      venue: 'Kallang Pickle Centre',
      start: day(-11),
      end: day(-10, 20),
      registrationDeadline: day(-18),
      format: 'Knockout, best of 3',
      rules: rules,
      categories: [cat('t-sg-xd', 'Mixed Doubles', PlayCategory.mixed, 'Open', 1200, 16, 16)],
    ),
  ];
}
