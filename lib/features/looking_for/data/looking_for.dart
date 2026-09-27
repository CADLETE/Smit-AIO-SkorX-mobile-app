/// Looking For: the community's requirement network (docs/LOOKING-FOR.md).
/// These types mirror the API's responses (backend `src/looking-for/`)
/// field for field, so the API repository only parses JSON.
library;

import '../../../shared/format.dart';

enum LfStatus {
  open('Open'),
  responsesReceived('Responses in'),
  partiallyFilled('Partly filled'),
  filled('Filled'),
  expired('Expired'),
  cancelled('Cancelled');

  const LfStatus(this.label);
  final String label;

  bool get active => this == open || this == responsesReceived || this == partiallyFilled;

  static LfStatus parse(String? s) => switch (s) {
        'responses_received' => responsesReceived,
        'partially_filled' => partiallyFilled,
        'filled' => filled,
        'expired' => expired,
        'cancelled' => cancelled,
        _ => open,
      };
}

enum LfResponseStatus {
  pending,
  accepted,
  declined,
  withdrawn;

  static LfResponseStatus parse(String? s) => values.firstWhere((v) => v.name == s, orElse: () => pending);
}

enum LfPaymentType {
  none,

  /// The poster pays whoever responds.
  paid,

  /// The responder pays a share.
  fee;

  static LfPaymentType parse(String? s) => values.firstWhere((v) => v.name == s, orElse: () => none);
}

enum LfTab {
  forYou('for_you', 'For You'),
  nearby('nearby', 'Nearby'),
  latest('latest', 'Latest');

  const LfTab(this.api, this.label);
  final String api;
  final String label;

  static LfTab? parse(String? s) => values.where((t) => t.api == s || t.name == s).firstOrNull;
}

enum LfMineTab {
  posted('Posted'),
  interested('Interested'),
  responses('Responses'),
  saved('Saved'),
  completed('Completed');

  const LfMineTab(this.label);
  final String label;
}

const lfSkillBands = ['beginner', 'intermediate', 'advanced', 'pro'];
const lfSkillLabels = {'beginner': 'Beginner', 'intermediate': 'Intermediate', 'advanced': 'Advanced', 'pro': 'Pro'};
const lfAgeGroups = ['any', 'junior', 'open', '35+', '50+', '60+'];
const lfPaymentUnits = {
  'per_person': 'per person',
  'per_hour': 'per hour',
  'per_day': 'per day',
  'per_match': 'per match',
  'total': 'total',
};
const lfReportReasons = {
  'spam': 'Spam',
  'fake': 'Fake requirement',
  'wrong_info': 'Wrong information',
  'harassment': 'Harassment',
  'fraud': 'Fraud',
  'inappropriate': 'Inappropriate content',
  'duplicate': 'Duplicate',
  'other': 'Something else',
};

/// Roles a person can be found for; ids match Community's `CommunityRole`.
const lfRoles = {
  'referee': 'Referee',
  'scorekeeper': 'Scorekeeper',
  'official': 'Tournament official',
  'organizer': 'Organizer',
  'eventManager': 'Event manager',
  'coach': 'Coach',
  'trainer': 'Trainer',
  'commentator': 'Commentator',
  'streamer': 'Streamer',
  'photographer': 'Photographer',
  'creator': 'Content creator',
};

class LfDetailField {
  const LfDetailField({required this.key, required this.label, required this.type, this.options = const [], this.min, this.max});

  factory LfDetailField.fromJson(Map<String, dynamic> j) => LfDetailField(
        key: j['key'] as String,
        label: j['label'] as String,
        type: j['type'] as String,
        options: [...?(j['options'] as List?)?.cast<String>()],
        min: j['min'] as int?,
        max: j['max'] as int?,
      );

  final String key;
  final String label;

  /// number | choice | text
  final String type;
  final List<String> options;
  final int? min;
  final int? max;
}

/// Which fields a category's form shows; the server validates the same.
class LfForm {
  const LfForm({
    required this.fields,
    required this.required,
    this.quantityLabel,
    this.details = const [],
    this.roles = const [],
    this.payment = 'none',
  });

  factory LfForm.fromJson(Map<String, dynamic> j) => LfForm(
        fields: {...(j['fields'] as List).cast<String>()},
        required: {...(j['required'] as List).cast<String>()},
        quantityLabel: j['quantityLabel'] as String?,
        details: [for (final d in (j['details'] as List? ?? const [])) LfDetailField.fromJson(d as Map<String, dynamic>)],
        roles: [...?(j['roles'] as List?)?.cast<String>()],
        payment: j['payment'] as String? ?? 'none',
      );

  final Set<String> fields;
  final Set<String> required;
  final String? quantityLabel;
  final List<LfDetailField> details;
  final List<String> roles;
  final String payment;

  bool has(String f) => fields.contains(f);
  bool needs(String f) => required.contains(f);
}

class LfOption {
  const LfOption(this.id, this.label);
  final String id;
  final String label;
}

class LfCategory {
  const LfCategory({
    required this.id,
    required this.label,
    required this.group,
    required this.icon,
    required this.tagline,
    required this.form,
    this.subcategories = const [],
  });

  factory LfCategory.fromJson(Map<String, dynamic> j) => LfCategory(
        id: j['id'] as String,
        label: j['label'] as String,
        group: j['group'] as String,
        icon: j['icon'] as String,
        tagline: j['tagline'] as String? ?? '',
        form: LfForm.fromJson(j['form'] as Map<String, dynamic>),
        subcategories: [
          for (final s in (j['subcategories'] as List? ?? const []))
            LfOption((s as Map)['id'] as String, s['label'] as String),
        ],
      );

  final String id;
  final String label;
  final String group;
  final String icon;
  final String tagline;
  final LfForm form;
  final List<LfOption> subcategories;
}

class LfPostedBy {
  const LfPostedBy({required this.kind, required this.name, required this.userId, this.imageUrl, this.playerProfileId});

  factory LfPostedBy.fromJson(Map<String, dynamic> j) => LfPostedBy(
        kind: j['kind'] as String? ?? 'self',
        name: j['name'] as String? ?? 'SkorX player',
        userId: j['userId'] as String? ?? '',
        imageUrl: j['imageUrl'] as String?,
        playerProfileId: j['playerProfileId'] as String?,
      );

  /// self | organization | tournament
  final String kind;
  final String name;
  final String userId;
  final String? imageUrl;
  final String? playerProfileId;
}

class LfMyResponseRef {
  const LfMyResponseRef(this.id, this.status);
  final String id;
  final LfResponseStatus status;
}

/// What the owner sees about the people SkorX found: a count and shared facts.
class LfMatching {
  const LfMatching({this.count = 0, this.alerted = 0, this.waitingForDigest = 0, this.summary = const []});

  factory LfMatching.fromJson(Map<String, dynamic>? j) => j == null
      ? const LfMatching()
      : LfMatching(
          count: j['count'] as int? ?? 0,
          alerted: j['alerted'] as int? ?? 0,
          waitingForDigest: j['waitingForDigest'] as int? ?? 0,
          summary: [
            for (final s in (j['summary'] as List? ?? const []))
              ((s as Map)['label'] as String, s['count'] as int),
          ],
        );

  final int count;
  final int alerted;
  final int waitingForDigest;
  final List<(String, int)> summary;
}

class LfPost {
  const LfPost({
    required this.id,
    required this.categoryId,
    required this.categoryLabel,
    required this.categoryIcon,
    required this.title,
    required this.postedBy,
    required this.city,
    required this.status,
    required this.expiresAt,
    required this.createdAt,
    this.subcategoryId,
    this.subcategoryLabel,
    this.description,
    this.placeName,
    this.approximate = true,
    this.distanceKm,
    this.startsAt,
    this.endsAt,
    this.durationMins,
    this.whenLabel,
    this.quantityRequired = 1,
    this.quantityFilled = 0,
    this.quantityLabel,
    this.skillLevels = const [],
    this.gender = 'any',
    this.ageGroup = 'any',
    this.paymentType = LfPaymentType.none,
    this.paymentAmount,
    this.paymentUnit,
    this.details = const {},
    this.detailLabels = const {},
    this.tournamentId,
    this.tournamentName,
    this.visibility = 'public',
    this.hidden = false,
    this.responseCount = 0,
    this.viewCount,
    this.matchCount,
    this.isOwner = false,
    this.saved = false,
    this.myResponse,
    this.reasons = const [],
    this.matching,
    this.shareUrl,
  });

  factory LfPost.fromJson(Map<String, dynamic> j) {
    final category = j['category'] as Map<String, dynamic>;
    final sub = j['subcategory'] as Map<String, dynamic>?;
    final place = j['place'] as Map<String, dynamic>;
    final payment = j['payment'] as Map<String, dynamic>? ?? const {};
    final tournament = j['tournament'] as Map<String, dynamic>?;
    final viewer = j['viewer'] as Map<String, dynamic>? ?? const {};
    final response = viewer['response'] as Map<String, dynamic>?;
    DateTime? date(String k) => j[k] == null ? null : DateTime.parse(j[k] as String).toLocal();
    return LfPost(
      id: j['id'] as String,
      categoryId: category['id'] as String,
      categoryLabel: category['label'] as String,
      categoryIcon: category['icon'] as String? ?? category['id'] as String,
      subcategoryId: sub?['id'] as String?,
      subcategoryLabel: sub?['label'] as String?,
      title: j['title'] as String,
      description: j['description'] as String?,
      postedBy: LfPostedBy.fromJson(j['postedBy'] as Map<String, dynamic>),
      placeName: place['name'] as String?,
      city: place['city'] as String,
      approximate: place['approximate'] as bool? ?? true,
      distanceKm: (j['distanceKm'] as num?)?.toDouble(),
      startsAt: date('startsAt'),
      endsAt: date('endsAt'),
      durationMins: j['durationMins'] as int?,
      whenLabel: j['whenLabel'] as String?,
      quantityRequired: j['quantityRequired'] as int? ?? 1,
      quantityFilled: j['quantityFilled'] as int? ?? 0,
      quantityLabel: j['quantityLabel'] as String?,
      skillLevels: [...?(j['skillLevels'] as List?)?.cast<String>()],
      gender: j['gender'] as String? ?? 'any',
      ageGroup: j['ageGroup'] as String? ?? 'any',
      paymentType: LfPaymentType.parse(payment['type'] as String?),
      paymentAmount: payment['amount'] as int?,
      paymentUnit: payment['unit'] as String?,
      details: {...?(j['details'] as Map?)?.cast<String, Object?>()},
      detailLabels: {...?(j['detailLabels'] as Map?)?.cast<String, String>()},
      tournamentId: tournament?['id'] as String?,
      tournamentName: tournament?['name'] as String?,
      visibility: j['visibility'] as String? ?? 'public',
      status: LfStatus.parse(j['status'] as String?),
      hidden: j['hidden'] as bool? ?? false,
      expiresAt: DateTime.parse(j['expiresAt'] as String).toLocal(),
      createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
      responseCount: j['responseCount'] as int? ?? 0,
      viewCount: j['viewCount'] as int?,
      matchCount: j['matchCount'] as int?,
      isOwner: viewer['isOwner'] as bool? ?? false,
      saved: viewer['saved'] as bool? ?? false,
      myResponse: response == null
          ? null
          : LfMyResponseRef(response['id'] as String, LfResponseStatus.parse(response['status'] as String?)),
      reasons: [...?(j['reasons'] as List?)?.cast<String>()],
      matching: j['matching'] == null ? null : LfMatching.fromJson(j['matching'] as Map<String, dynamic>),
      shareUrl: j['shareUrl'] as String?,
    );
  }

  final String id;
  final String categoryId;
  final String categoryLabel;
  final String categoryIcon;
  final String? subcategoryId;
  final String? subcategoryLabel;
  final String title;
  final String? description;
  final LfPostedBy postedBy;
  final String? placeName;
  final String city;

  /// Distance is between city centres, not the place itself.
  final bool approximate;
  final double? distanceKm;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final int? durationMins;

  /// The server's "Today 8:00 PM" (IST).
  final String? whenLabel;
  final int quantityRequired;
  final int quantityFilled;
  final String? quantityLabel;
  final List<String> skillLevels;
  final String gender;
  final String ageGroup;
  final LfPaymentType paymentType;
  final int? paymentAmount;
  final String? paymentUnit;
  final Map<String, Object?> details;
  final Map<String, String> detailLabels;
  final String? tournamentId;
  final String? tournamentName;
  final String visibility;
  final LfStatus status;
  final bool hidden;
  final DateTime expiresAt;
  final DateTime createdAt;
  final int responseCount;

  /// Owner only.
  final int? viewCount;
  final int? matchCount;
  final bool isOwner;
  final bool saved;
  final LfMyResponseRef? myResponse;

  /// For You: why this is relevant to me ("In Ahmedabad", "Intermediate").
  final List<String> reasons;

  /// Owner only, on the detail.
  final LfMatching? matching;
  final String? shareUrl;

  int get openPlaces => (quantityRequired - quantityFilled).clamp(0, quantityRequired);

  /// "1 of 2 filled", or null when nothing is filled yet.
  String? get fillLabel =>
      quantityRequired > 1 && quantityFilled > 0 && status != LfStatus.filled ? '$quantityFilled of $quantityRequired filled' : null;

  String get placeLabel => placeName == null ? city : '$placeName · $city';

  String? get skillLabel => skillLevels.isEmpty ? null : skillLevels.map((s) => lfSkillLabels[s] ?? s).join(' / ');

  /// "₹300 per person", "Paid · ₹1,500 per day", "Paid".
  String? get paymentLabel {
    if (paymentType == LfPaymentType.none) return null;
    final unit = paymentUnit == null ? '' : ' ${lfPaymentUnits[paymentUnit] ?? paymentUnit}';
    final amount = paymentAmount == null ? null : '${formatInr(paymentAmount!, freeWhenZero: false)}$unit';
    return switch (paymentType) {
      LfPaymentType.paid => amount == null ? 'Paid' : 'Paid · $amount',
      LfPaymentType.fee => amount == null ? 'Shared cost' : 'Fee $amount',
      LfPaymentType.none => null,
    };
  }

  LfPost copyWith({bool? saved, LfMyResponseRef? myResponse, bool clearResponse = false}) => LfPost(
        id: id,
        categoryId: categoryId,
        categoryLabel: categoryLabel,
        categoryIcon: categoryIcon,
        subcategoryId: subcategoryId,
        subcategoryLabel: subcategoryLabel,
        title: title,
        description: description,
        postedBy: postedBy,
        placeName: placeName,
        city: city,
        approximate: approximate,
        distanceKm: distanceKm,
        startsAt: startsAt,
        endsAt: endsAt,
        durationMins: durationMins,
        whenLabel: whenLabel,
        quantityRequired: quantityRequired,
        quantityFilled: quantityFilled,
        quantityLabel: quantityLabel,
        skillLevels: skillLevels,
        gender: gender,
        ageGroup: ageGroup,
        paymentType: paymentType,
        paymentAmount: paymentAmount,
        paymentUnit: paymentUnit,
        details: details,
        detailLabels: detailLabels,
        tournamentId: tournamentId,
        tournamentName: tournamentName,
        visibility: visibility,
        status: status,
        hidden: hidden,
        expiresAt: expiresAt,
        createdAt: createdAt,
        responseCount: responseCount,
        viewCount: viewCount,
        matchCount: matchCount,
        isOwner: isOwner,
        saved: saved ?? this.saved,
        myResponse: clearResponse ? null : (myResponse ?? this.myResponse),
        reasons: reasons,
        matching: matching,
        shareUrl: shareUrl,
      );
}

/// Phone numbers appear only after that person shared theirs.
class LfContact {
  const LfContact({this.iShared = false, this.theyShared = false, this.phone});

  factory LfContact.fromJson(Map<String, dynamic>? j) => LfContact(
        iShared: j?['iShared'] as bool? ?? false,
        theyShared: j?['theyShared'] as bool? ?? false,
        phone: j?['phone'] as String?,
      );

  final bool iShared;
  final bool theyShared;
  final String? phone;
}

class LfPerson {
  const LfPerson({
    required this.userId,
    required this.name,
    this.playerProfileId,
    this.photoUrl,
    this.city,
    this.skillLevel,
    this.roles = const [],
    this.matchesPlayed = 0,
    this.recentMatches = 0,
  });

  factory LfPerson.fromJson(Map<String, dynamic> j) => LfPerson(
        userId: j['userId'] as String,
        name: j['name'] as String,
        playerProfileId: j['playerProfileId'] as String?,
        photoUrl: j['photoUrl'] as String?,
        city: j['city'] as String?,
        skillLevel: j['skillLevel'] as String?,
        roles: [...?(j['roles'] as List?)?.cast<String>()],
        matchesPlayed: j['matchesPlayed'] as int? ?? 0,
        recentMatches: j['recentMatches'] as int? ?? 0,
      );

  final String userId;
  final String name;
  final String? playerProfileId;
  final String? photoUrl;
  final String? city;
  final String? skillLevel;
  final List<String> roles;
  final int matchesPlayed;
  final int recentMatches;
}

/// A response, as the poster sees it (with the person) or as the responder
/// sees their own (without).
class LfResponse {
  const LfResponse({
    required this.id,
    required this.status,
    required this.respondedAt,
    this.postId,
    this.message,
    this.availabilityConfirmed = false,
    this.decidedAt,
    this.person,
    this.contact = const LfContact(),
  });

  factory LfResponse.fromJson(Map<String, dynamic> j) => LfResponse(
        id: j['id'] as String,
        postId: j['postId'] as String?,
        status: LfResponseStatus.parse(j['status'] as String?),
        message: j['message'] as String?,
        availabilityConfirmed: j['availabilityConfirmed'] as bool? ?? false,
        respondedAt: DateTime.parse(j['respondedAt'] as String).toLocal(),
        decidedAt: j['decidedAt'] == null ? null : DateTime.parse(j['decidedAt'] as String).toLocal(),
        person: j['person'] == null ? null : LfPerson.fromJson(j['person'] as Map<String, dynamic>),
        contact: LfContact.fromJson(j['contact'] as Map<String, dynamic>?),
      );

  final String id;
  final String? postId;
  final LfResponseStatus status;
  final String? message;
  final bool availabilityConfirmed;
  final DateTime respondedAt;
  final DateTime? decidedAt;
  final LfPerson? person;
  final LfContact contact;
}

/// One row of My Looking For › Interested: the post and my response to it.
class LfInterest {
  const LfInterest(this.post, this.response);
  final LfPost post;
  final LfResponse response;
}

/// One row of My Looking For › Responses: someone who answered my post.
class LfIncoming {
  const LfIncoming({required this.postId, required this.postTitle, required this.response});
  final String postId;
  final String postTitle;
  final LfResponse response;
}

class LfPage<T> {
  const LfPage(this.items, this.nextCursor, {this.needsLocation = false});
  final List<T> items;
  final String? nextCursor;

  /// Nearby had nowhere to measure from.
  final bool needsLocation;
}

/// Open requests per category, for the browse tiles.
class LfSummary {
  const LfSummary({this.total = 0, this.byCategory = const {}});

  factory LfSummary.fromJson(Map<String, dynamic> j) => LfSummary(
        total: j['total'] as int? ?? 0,
        byCategory: {...?(j['byCategory'] as Map?)?.cast<String, int>()},
      );

  final int total;
  final Map<String, int> byCategory;

  int count(Iterable<String> categories) => categories.fold(0, (n, c) => n + (byCategory[c] ?? 0));
}

class LfCounts {
  const LfCounts({this.posted = 0, this.pendingResponses = 0, this.interested = 0, this.saved = 0});

  factory LfCounts.fromJson(Map<String, dynamic> j) => LfCounts(
        posted: j['posted'] as int? ?? 0,
        pendingResponses: j['pendingResponses'] as int? ?? 0,
        interested: j['interested'] as int? ?? 0,
        saved: j['saved'] as int? ?? 0,
      );

  final int posted;
  final int pendingResponses;
  final int interested;
  final int saved;
}

enum LfAlertMode {
  instant('instant', 'Instant', 'As soon as something fits you'),
  dailyDigest('daily_digest', 'Daily digest', 'One summary each evening'),
  off('off', 'Off', 'No Looking For alerts');

  const LfAlertMode(this.api, this.label, this.detail);
  final String api;
  final String label;
  final String detail;

  static LfAlertMode parse(String? s) => values.firstWhere((v) => v.api == s, orElse: () => instant);
}

class LfAlerts {
  const LfAlerts({
    required this.mode,
    required this.categories,
    required this.radiusKm,
    this.city,
    this.roles = const {},
    this.digestHour = 19,
    this.dailyCap = 5,
    this.isDefault = false,
    this.knownCities = const [],
  });

  factory LfAlerts.fromJson(Map<String, dynamic> j) => LfAlerts(
        mode: LfAlertMode.parse(j['mode'] as String?),
        categories: {...(j['categories'] as List? ?? const []).cast<String>()},
        radiusKm: j['radiusKm'] as int?,
        city: j['city'] as String?,
        roles: {...(j['roles'] as List? ?? const []).cast<String>()},
        digestHour: j['digestHour'] as int? ?? 19,
        dailyCap: j['dailyCap'] as int? ?? 5,
        isDefault: j['isDefault'] as bool? ?? false,
        knownCities: [...?(j['knownCities'] as List?)?.cast<String>()],
      );

  final LfAlertMode mode;
  final Set<String> categories;

  /// Null = anywhere.
  final int? radiusKm;
  final String? city;
  final Set<String> roles;
  final int digestHour;
  final int dailyCap;

  /// Never saved: these are SkorX's defaults for this person.
  final bool isDefault;
  final List<String> knownCities;

  Map<String, dynamic> toJson() => {
        'mode': mode.api,
        'categories': categories.toList(),
        'radiusKm': radiusKm,
        'city': city,
        'digestHour': digestHour,
        'dailyCap': dailyCap,
        'roles': roles.toList(),
      };

  LfAlerts copyWith({LfAlertMode? mode, Set<String>? categories, int? radiusKm, bool anywhere = false, String? city, Set<String>? roles}) =>
      LfAlerts(
        mode: mode ?? this.mode,
        categories: categories ?? this.categories,
        radiusKm: anywhere ? null : (radiusKm ?? this.radiusKm),
        city: city ?? this.city,
        roles: roles ?? this.roles,
        digestHour: digestHour,
        dailyCap: dailyCap,
        isDefault: isDefault,
        knownCities: knownCities,
      );
}

/// Feed filters. Equal queries share one cached feed.
class LfQuery {
  const LfQuery({
    this.tab = LfTab.forYou,
    this.categories = const {},
    this.city,
    this.radiusKm,
    this.skill = const {},
    this.paid,
    this.gender,
    this.sort = 'new',
    this.text = '',
    this.tournamentId,
  });

  final LfTab tab;
  final Set<String> categories;
  final String? city;
  final int? radiusKm;
  final Set<String> skill;
  final bool? paid;
  final String? gender;

  /// new | expiring | soonest
  final String sort;
  final String text;
  final String? tournamentId;

  int get activeFilters =>
      (categories.isEmpty ? 0 : 1) +
      (city == null ? 0 : 1) +
      (radiusKm == null ? 0 : 1) +
      (skill.isEmpty ? 0 : 1) +
      (paid == null ? 0 : 1) +
      (gender == null ? 0 : 1) +
      (sort == 'new' ? 0 : 1);

  Map<String, dynamic> toQuery({String? cursor, int limit = 20}) => {
        'tab': tab.api,
        if (categories.isNotEmpty) 'category': categories.join(','),
        if (city != null) 'city': city,
        if (radiusKm != null) 'radiusKm': radiusKm,
        if (skill.isNotEmpty) 'skill': skill.join(','),
        if (paid != null) 'paid': paid.toString(),
        if (gender != null) 'gender': gender,
        if (sort != 'new') 'sort': sort,
        if (text.trim().isNotEmpty) 'q': text.trim(),
        if (tournamentId != null) 'tournamentId': tournamentId,
        'cursor': ?cursor,
        'limit': limit,
        'tz': DateTime.now().timeZoneOffset.inMinutes,
      };

  LfQuery copyWith({
    LfTab? tab,
    Set<String>? categories,
    String? city,
    bool clearCity = false,
    int? radiusKm,
    bool clearRadius = false,
    Set<String>? skill,
    bool? paid,
    bool clearPaid = false,
    String? gender,
    bool clearGender = false,
    String? sort,
    String? text,
  }) =>
      LfQuery(
        tab: tab ?? this.tab,
        categories: categories ?? this.categories,
        city: clearCity ? null : (city ?? this.city),
        radiusKm: clearRadius ? null : (radiusKm ?? this.radiusKm),
        skill: skill ?? this.skill,
        paid: clearPaid ? null : (paid ?? this.paid),
        gender: clearGender ? null : (gender ?? this.gender),
        sort: sort ?? this.sort,
        text: text ?? this.text,
        tournamentId: tournamentId,
      );

  @override
  bool operator ==(Object other) =>
      other is LfQuery &&
      other.tab == tab &&
      _setEq(other.categories, categories) &&
      other.city == city &&
      other.radiusKm == radiusKm &&
      _setEq(other.skill, skill) &&
      other.paid == paid &&
      other.gender == gender &&
      other.sort == sort &&
      other.text == text &&
      other.tournamentId == tournamentId;

  @override
  int get hashCode => Object.hash(tab, Object.hashAllUnordered(categories), city, radiusKm, Object.hashAllUnordered(skill), paid, gender,
      sort, text, tournamentId);
}

bool _setEq(Set<String> a, Set<String> b) => a.length == b.length && a.containsAll(b);

/// What the create form sends. Only the fields the category's form shows
/// are filled in.
class LfDraft {
  LfDraft({
    required this.categoryId,
    this.subcategoryId,
    this.title = '',
    this.description = '',
    this.postAs = 'self',
    this.organizationId,
    this.tournamentId,
    this.placeName = '',
    this.city = '',
    this.startsAt,
    this.endsAt,
    this.durationMins,
    this.quantity = 1,
    Set<String>? skillLevels,
    this.gender = 'any',
    this.ageGroup = 'any',
    this.paymentType = LfPaymentType.none,
    this.paymentAmount,
    this.paymentUnit = 'per_person',
    Map<String, Object?>? details,
    this.expiryPreset,
  })  : skillLevels = skillLevels ?? {},
        details = details ?? {};

  String categoryId;
  String? subcategoryId;
  String title;
  String description;
  String postAs;
  String? organizationId;
  String? tournamentId;
  String placeName;
  String city;
  DateTime? startsAt;
  DateTime? endsAt;
  int? durationMins;
  int quantity;
  Set<String> skillLevels;
  String gender;
  String ageGroup;
  LfPaymentType paymentType;
  int? paymentAmount;
  String paymentUnit;
  Map<String, Object?> details;

  /// 1h | today | tomorrow | week; null = when the session ends.
  String? expiryPreset;

  Map<String, dynamic> toJson(LfForm form) => {
        'categoryId': categoryId,
        if (subcategoryId != null) 'subcategoryId': subcategoryId,
        'title': title.trim(),
        if (description.trim().isNotEmpty) 'description': description.trim(),
        if (postAs != 'self') 'postAs': postAs,
        if (organizationId != null) 'organizationId': organizationId,
        if (tournamentId != null) 'tournamentId': tournamentId,
        if (form.has('place') && placeName.trim().isNotEmpty) 'placeName': placeName.trim(),
        'city': city.trim(),
        if (form.has('when') && startsAt != null) 'startsAt': startsAt!.toUtc().toIso8601String(),
        if (form.has('when') && endsAt != null) 'endsAt': endsAt!.toUtc().toIso8601String(),
        if (durationMins != null) 'durationMins': durationMins,
        if (form.has('quantity')) 'quantityRequired': quantity,
        if (form.has('skill')) 'skillLevels': skillLevels.toList(),
        if (form.has('gender')) 'gender': gender,
        if (form.has('age')) 'ageGroup': ageGroup,
        if (form.has('payment')) 'paymentType': paymentType.name,
        if (form.has('payment') && paymentType != LfPaymentType.none && paymentAmount != null) 'paymentAmount': paymentAmount,
        if (form.has('payment') && paymentType != LfPaymentType.none) 'paymentUnit': paymentUnit,
        'details': {
          for (final e in details.entries)
            if (e.value != null && e.value != '') e.key: e.value,
        },
        if (expiryPreset != null) 'expiryPreset': expiryPreset,
        'tzOffsetMinutes': DateTime.now().timeZoneOffset.inMinutes,
      };
}

/// What SkorX read from a typed sentence; every field is a suggestion.
class LfParsed {
  const LfParsed({
    this.categoryId,
    this.subcategoryId,
    this.title,
    this.quantity,
    this.skillLevels = const [],
    this.startsAt,
    this.endsAt,
    this.date,
    this.city,
    this.placeName,
    this.gender,
    this.matchType,
    this.paymentType,
    this.paymentAmount,
    this.description = '',
  });

  factory LfParsed.fromJson(Map<String, dynamic> j) {
    DateTime? d(String k) => j[k] == null ? null : DateTime.parse(j[k] as String).toLocal();
    return LfParsed(
      categoryId: j['categoryId'] as String?,
      subcategoryId: j['subcategoryId'] as String?,
      title: j['title'] as String?,
      quantity: j['quantity'] as int?,
      skillLevels: [...?(j['skillLevels'] as List?)?.cast<String>()],
      startsAt: d('startsAt'),
      endsAt: d('endsAt'),
      date: d('date'),
      city: j['city'] as String?,
      placeName: j['placeName'] as String?,
      gender: j['gender'] as String?,
      matchType: j['matchType'] as String?,
      paymentType: j['paymentType'] as String?,
      paymentAmount: j['paymentAmount'] as int?,
      description: j['description'] as String? ?? '',
    );
  }

  final String? categoryId;
  final String? subcategoryId;
  final String? title;
  final int? quantity;
  final List<String> skillLevels;
  final DateTime? startsAt;
  final DateTime? endsAt;

  /// A day with no time ("on 12 October").
  final DateTime? date;
  final String? city;
  final String? placeName;
  final String? gender;
  final String? matchType;
  final String? paymentType;
  final int? paymentAmount;
  final String description;
}
