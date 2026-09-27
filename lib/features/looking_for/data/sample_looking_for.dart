import '../../../core/api/api_exception.dart';
import '../../../core/sample_latency.dart';
import 'looking_for.dart';
import 'looking_for_repository.dart';

/// Debug builds without a server, and widget tests. Keeps the server's rules
/// (docs/LOOKING-FOR.md): statuses, one response per person, accepting fills
/// places, phones only after consent. The catalogue is the server's
/// (`backend/src/looking-for/looking-for.categories.ts`).
class SampleLookingForRepository implements LookingForRepository {
  SampleLookingForRepository({this.latency = Duration.zero, this.newcomer = false, DateTime Function()? clock})
      : _now = clock ?? DateTime.now {
    if (!newcomer) _seed();
  }

  final Duration latency;
  final bool newcomer;
  final DateTime Function() _now;

  static const meId = 'me';
  static const _myCity = 'Ahmedabad';

  final _posts = <String, _Post>{};
  final _responses = <String, _Response>{};
  final _saved = <String>{};
  final _reported = <String>{};
  var _seq = 0;
  LfAlerts? _alerts;

  Future<void> _wait() => simulateLatency(latency);

  // ---------------------------------------------------------------------------

  @override
  Future<List<LfCategory>> categories() async {
    await _wait();
    return [for (final c in _catalogue) LfCategory.fromJson(c)];
  }

  @override
  Future<LfPage<LfPost>> feed(LfQuery query, {String? cursor}) async {
    await _wait();
    final now = _now();
    final words = query.text.toLowerCase().split(RegExp(r'\s+')).where((w) => w.length > 2 && !_filler.contains(w)).toList();
    final guessed = _guessCategory(query.text.toLowerCase());
    var list = _posts.values.where((p) {
      if (!_status(p, now).active || p.hidden || p.visibility != 'public') return false;
      if (query.tab == LfTab.forYou && p.creatorId == meId) return false;
      if (query.categories.isNotEmpty && !query.categories.contains(p.categoryId)) return false;
      if (query.categories.isEmpty && guessed != null && p.categoryId != guessed) return false;
      final city = query.city ?? (query.tab == LfTab.latest ? null : _myCity);
      if (city != null && query.radiusKm == null && p.city.toLowerCase() != city.toLowerCase() && query.tab != LfTab.forYou) return false;
      if (query.skill.isNotEmpty && p.skillLevels.isNotEmpty && !p.skillLevels.any(query.skill.contains)) return false;
      if (query.paid != null && (p.paymentType == LfPaymentType.paid) != query.paid) return false;
      if (query.gender != null && p.gender != 'any' && p.gender != query.gender) return false;
      final hay = '${p.title} ${p.description ?? ''} ${p.placeName ?? ''} ${p.city} ${_label(p.categoryId)}'.toLowerCase();
      for (final w in words) {
        if (_guessCategory(w) == null && !hay.contains(w) && !_isTimeWord(w)) return false;
      }
      return true;
    }).toList();
    list.sort((a, b) => switch (query.sort) {
          'expiring' => a.expiresAt.compareTo(b.expiresAt),
          'soonest' => (a.startsAt ?? DateTime(9999)).compareTo(b.startsAt ?? DateTime(9999)),
          _ => b.createdAt.compareTo(a.createdAt),
        });
    final offset = int.tryParse(cursor ?? '') ?? 0;
    const limit = 20;
    final page = list.skip(offset).take(limit).map((p) => _view(p, now, forYou: query.tab == LfTab.forYou)).toList();
    return LfPage(page, offset + limit < list.length ? '${offset + limit}' : null);
  }

  @override
  Future<LfSummary> summary() async {
    await _wait();
    final now = _now();
    final counts = <String, int>{};
    for (final p in _posts.values.where((p) => _status(p, now).active && !p.hidden)) {
      counts[p.categoryId] = (counts[p.categoryId] ?? 0) + 1;
    }
    return LfSummary(total: counts.values.fold(0, (a, b) => a + b), byCategory: counts);
  }

  @override
  Future<LfPost> post(String id) async {
    await _wait();
    final p = _posts[id];
    if (p == null || (p.hidden && p.creatorId != meId)) {
      throw const ApiException('RESOURCE_NOT_FOUND', 'This request is no longer available.', status: 404);
    }
    if (p.creatorId != meId) p.views++;
    return _view(p, _now(), detail: true);
  }

  @override
  Future<LfParsed> parse(String text) async {
    await _wait();
    final t = text.toLowerCase();
    final category = _guessCategory(t);
    final qty = RegExp(r'\b(\d{1,2})\s+[a-z]').firstMatch(t)?.group(1);
    final time = RegExp(r'\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b').firstMatch(t);
    final now = _now();
    DateTime? startsAt;
    if (time != null) {
      var h = int.parse(time.group(1)!) % 12;
      if (time.group(3) == 'pm') h += 12;
      final day = t.contains('tomorrow') ? now.add(const Duration(days: 1)) : now;
      startsAt = DateTime(day.year, day.month, day.day, h, int.tryParse(time.group(2) ?? '') ?? 0);
    }
    final place = RegExp(r"\bat ([a-z0-9&' ]+?)(?= tonight| today| tomorrow| at | on |[.,]|$)").firstMatch(t)?.group(1);
    return LfParsed(
      categoryId: category,
      quantity: qty == null ? null : int.parse(qty),
      skillLevels: [for (final s in lfSkillBands) if (t.contains(s)) s],
      startsAt: startsAt,
      placeName: place == null || RegExp(r'^\d').hasMatch(place) ? null : place.split(' ').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' '),
      city: _cities.where((c) => t.contains(c.toLowerCase())).firstOrNull,
      title: category == null ? null : '${qty == null ? '' : '$qty '}${_label(category)} needed'.trim(),
      description: text.trim(),
    );
  }

  @override
  Future<(LfPost, LfMatching)> create(Map<String, dynamic> body) async {
    await _wait();
    final now = _now();
    final category = _catalogue.firstWhere((c) => c['id'] == body['categoryId']);
    final form = LfForm.fromJson(category['form'] as Map<String, dynamic>);
    if ((body['title'] as String? ?? '').trim().length < 3) {
      throw const ApiException('VALIDATION_ERROR', 'Give it a short title.', status: 422);
    }
    if (form.needs('when') && body['startsAt'] == null) {
      throw const ApiException('VALIDATION_ERROR', 'Add date and time.', status: 422);
    }
    final active = _posts.values.where((p) => p.creatorId == meId && _status(p, now).active).length;
    if (active >= 10) {
      throw const ApiException('RESOURCE_CONFLICT', 'You have 10 open requests. Close or fill one before posting another.', status: 409);
    }
    final id = 'lf-new-${++_seq}';
    final p = _Post.fromBody(id, meId, 'You', body, now, _label(body['categoryId'] as String), category['icon'] as String, form);
    _posts[id] = p;
    // Everyone in the city who plays, capped as the server caps alerts.
    final found = p.city.toLowerCase() == 'ahmedabad' ? 12 : 3;
    p.matchCount = found;
    return (_view(p, now, detail: true), LfMatching(count: found, alerted: found, summary: [('In ${p.city}', found)]));
  }

  @override
  Future<LfPost> update(String id, Map<String, dynamic> body) async {
    await _wait();
    final p = _own(id);
    if (body['title'] is String) p.title = (body['title'] as String).trim();
    if (body.containsKey('description')) p.description = body['description'] as String?;
    if (body['quantityRequired'] is int) p.quantityRequired = body['quantityRequired'] as int;
    return _view(p, _now(), detail: true);
  }

  @override
  Future<LfPost> setState(String id, String action) async {
    await _wait();
    final p = _own(id);
    final now = _now();
    switch (action) {
      case 'cancel':
        p.cancelledAt = now;
      case 'fill':
        if (p.cancelledAt != null) throw const ApiException('RESOURCE_CONFLICT', 'This request was cancelled.', status: 409);
        p.closedAt = now;
      case 'reopen':
        if (!p.expiresAt.isAfter(now)) {
          throw const ApiException('RESOURCE_CONFLICT', 'This request has expired. Post it again with a new date.', status: 409);
        }
        if (p.filled >= p.quantityRequired) {
          throw const ApiException('RESOURCE_CONFLICT', 'Every place is taken. Raise how many you need to reopen it.', status: 409);
        }
        p.cancelledAt = null;
        p.closedAt = null;
    }
    return _view(p, now, detail: true);
  }

  @override
  Future<List<LfResponse>> responses(String postId) async {
    await _wait();
    _own(postId);
    final list = _responses.values.where((r) => r.postId == postId && r.status != LfResponseStatus.withdrawn).toList()
      ..sort((a, b) => a.at.compareTo(b.at));
    return [for (final r in list) _responseView(r, forPoster: true)];
  }

  @override
  Future<LfResponse> respond(String postId, {String? message, bool availabilityConfirmed = false}) async {
    await _wait();
    final p = _posts[postId];
    final now = _now();
    if (p == null) throw const ApiException('RESOURCE_NOT_FOUND', 'This request is no longer available.', status: 404);
    if (p.creatorId == meId) throw const ApiException('FORBIDDEN', 'This is your own request.', status: 403);
    final status = _status(p, now);
    if (!status.active) {
      throw ApiException('RESOURCE_CONFLICT', status == LfStatus.filled ? 'This request has been filled.' : 'This request is closed.',
          status: 409);
    }
    final existing = _responses.values.where((r) => r.postId == postId && r.userId == meId).firstOrNull;
    if (existing != null && existing.status == LfResponseStatus.declined) {
      throw const ApiException('RESOURCE_CONFLICT', 'The poster has already answered your interest.', status: 409);
    }
    if (existing != null && existing.status != LfResponseStatus.withdrawn) return _responseView(existing, forPoster: false);
    final r = existing ?? _Response('r-${++_seq}', postId, meId, 'You', now);
    r
      ..status = LfResponseStatus.pending
      ..message = message
      ..available = availabilityConfirmed;
    _responses[r.id] = r;
    return _responseView(r, forPoster: false);
  }

  @override
  Future<LfResponse> act(String responseId, String action) async {
    await _wait();
    final r = _responses[responseId];
    if (r == null) throw const ApiException('RESOURCE_NOT_FOUND', 'Response not found.', status: 404);
    final p = _posts[r.postId]!;
    final now = _now();
    switch (action) {
      case 'accept':
        if (p.creatorId != meId) throw const ApiException('RESOURCE_NOT_FOUND', 'Response not found.', status: 404);
        if (r.status == LfResponseStatus.accepted) break;
        if (p.filled >= p.quantityRequired) {
          throw const ApiException('RESOURCE_CONFLICT', 'Every place is already filled. Raise how many you need first.', status: 409);
        }
        r
          ..status = LfResponseStatus.accepted
          ..decidedAt = now;
      case 'decline':
        if (p.creatorId != meId) throw const ApiException('RESOURCE_NOT_FOUND', 'Response not found.', status: 404);
        r
          ..status = LfResponseStatus.declined
          ..decidedAt = now;
        p.closedAt = null;
      case 'withdraw':
        if (r.userId != meId) throw const ApiException('RESOURCE_NOT_FOUND', 'Response not found.', status: 404);
        r.status = LfResponseStatus.withdrawn;
        p.closedAt = null;
      case 'share-contact':
        if (r.status != LfResponseStatus.accepted) {
          throw const ApiException('FORBIDDEN', 'Contact can be shared once the response is accepted.', status: 403);
        }
        if (p.creatorId == meId) {
          r.posterShared = true;
        } else {
          r.responderShared = true;
        }
    }
    return _responseView(r, forPoster: p.creatorId == meId);
  }

  @override
  Future<void> save(String postId, {required bool on}) async {
    await _wait();
    on ? _saved.add(postId) : _saved.remove(postId);
  }

  @override
  Future<String> shareLink(String postId, {String? channel}) async => 'https://skorx.in/looking-for/$postId';

  @override
  Future<void> report(String postId, String reason, {String? note}) async {
    await _wait();
    if (_posts[postId]?.creatorId == meId) throw const ApiException('FORBIDDEN', 'You cannot report your own request.', status: 403);
    _reported.add(postId);
  }

  @override
  Future<LfPage<LfPost>> myPosts(LfMineTab tab, {String? cursor}) async {
    await _wait();
    final now = _now();
    final list = switch (tab) {
      LfMineTab.saved => [for (final id in _saved) ?_posts[id]],
      LfMineTab.completed => _posts.values.where((p) => p.creatorId == meId && !_status(p, now).active).toList(),
      _ => _posts.values.where((p) => p.creatorId == meId && _status(p, now).active).toList(),
    }
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return LfPage([for (final p in list) _view(p, now)], null);
  }

  @override
  Future<LfPage<LfInterest>> myInterests({String? cursor}) async {
    await _wait();
    final now = _now();
    final mine = _responses.values.where((r) => r.userId == meId).toList()..sort((a, b) => b.at.compareTo(a.at));
    return LfPage([for (final r in mine) LfInterest(_view(_posts[r.postId]!, now), _responseView(r, forPoster: false))], null);
  }

  @override
  Future<LfPage<LfIncoming>> incoming({String? cursor}) async {
    await _wait();
    final list = _responses.values
        .where((r) => _posts[r.postId]?.creatorId == meId && r.status != LfResponseStatus.withdrawn)
        .toList()
      ..sort((a, b) => b.at.compareTo(a.at));
    return LfPage([
      for (final r in list) LfIncoming(postId: r.postId, postTitle: _posts[r.postId]!.title, response: _responseView(r, forPoster: true)),
    ], null);
  }

  @override
  Future<LfCounts> counts() async {
    await _wait();
    final now = _now();
    final mine = _posts.values.where((p) => p.creatorId == meId && _status(p, now).active).map((p) => p.id).toSet();
    return LfCounts(
      posted: mine.length,
      pendingResponses: _responses.values.where((r) => mine.contains(r.postId) && r.status == LfResponseStatus.pending).length,
      interested: _responses.values
          .where((r) => r.userId == meId && (r.status == LfResponseStatus.pending || r.status == LfResponseStatus.accepted))
          .length,
      saved: _saved.length,
    );
  }

  @override
  Future<LfAlerts> alerts() async {
    await _wait();
    return _alerts ??
        const LfAlerts(
          mode: LfAlertMode.instant,
          categories: {'player', 'match', 'team', 'tournament'},
          radiusKm: 25,
          city: _myCity,
          isDefault: true,
          knownCities: _cities,
        );
  }

  @override
  Future<LfAlerts> saveAlerts(LfAlerts alerts) async {
    await _wait();
    return _alerts = LfAlerts(
      mode: alerts.mode,
      categories: alerts.categories,
      radiusKm: alerts.radiusKm,
      city: alerts.city,
      roles: alerts.roles,
      digestHour: alerts.digestHour,
      dailyCap: alerts.dailyCap,
      knownCities: _cities,
    );
  }

  // ---------------------------------------------------------------------------

  _Post _own(String id) {
    final p = _posts[id];
    if (p == null || p.creatorId != meId) throw const ApiException('RESOURCE_NOT_FOUND', 'Request not found.', status: 404);
    return p;
  }

  int _filledOf(_Post p) => _responses.values.where((r) => r.postId == p.id && r.status == LfResponseStatus.accepted).length;

  LfStatus _status(_Post p, DateTime now) {
    p.filled = _filledOf(p);
    if (p.cancelledAt != null) return LfStatus.cancelled;
    if (p.closedAt != null || p.filled >= p.quantityRequired) return LfStatus.filled;
    if (!p.expiresAt.isAfter(now)) return LfStatus.expired;
    if (p.filled > 0) return LfStatus.partiallyFilled;
    final live = _responses.values
        .where((r) => r.postId == p.id && (r.status == LfResponseStatus.pending || r.status == LfResponseStatus.accepted))
        .length;
    return live > 0 ? LfStatus.responsesReceived : LfStatus.open;
  }

  LfPost _view(_Post p, DateTime now, {bool detail = false, bool forYou = false}) {
    final status = _status(p, now);
    final mine = _responses.values.where((r) => r.postId == p.id && r.userId == meId).firstOrNull;
    final live = _responses.values
        .where((r) => r.postId == p.id && (r.status == LfResponseStatus.pending || r.status == LfResponseStatus.accepted))
        .length;
    final isOwner = p.creatorId == meId;
    return LfPost.fromJson({
      'id': p.id,
      'category': {'id': p.categoryId, 'label': _label(p.categoryId), 'icon': p.icon},
      'subcategory': p.subcategoryId == null ? null : {'id': p.subcategoryId, 'label': _subLabel(p.subcategoryId!)},
      'title': p.title,
      'description': p.description,
      'postedBy': {'kind': p.postAs, 'name': p.postedByName, 'userId': p.creatorId},
      'place': {'name': p.placeName, 'city': p.city, 'approximate': true},
      'distanceKm': p.city == _myCity ? 3.5 : null,
      'startsAt': p.startsAt?.toUtc().toIso8601String(),
      'endsAt': p.endsAt?.toUtc().toIso8601String(),
      'durationMins': p.durationMins,
      'whenLabel': p.startsAt == null ? null : _whenLabel(p.startsAt!, now),
      'quantityRequired': p.quantityRequired,
      'quantityFilled': p.filled,
      'quantityLabel': p.quantityLabel,
      'skillLevels': p.skillLevels,
      'gender': p.gender,
      'ageGroup': 'any',
      'payment': {'type': p.paymentType.name, 'amount': p.paymentAmount, 'unit': p.paymentUnit},
      'details': p.details,
      'detailLabels': p.detailLabels,
      'tournament': p.tournamentName == null ? null : {'id': 't-open', 'name': p.tournamentName},
      'visibility': p.visibility,
      'status': switch (status) {
        LfStatus.responsesReceived => 'responses_received',
        LfStatus.partiallyFilled => 'partially_filled',
        _ => status.name,
      },
      'hidden': p.hidden,
      'expiresAt': p.expiresAt.toUtc().toIso8601String(),
      'createdAt': p.createdAt.toUtc().toIso8601String(),
      'responseCount': live,
      if (isOwner) 'viewCount': p.views,
      if (isOwner) 'matchCount': p.matchCount,
      'viewer': {
        'isOwner': isOwner,
        'saved': _saved.contains(p.id),
        'response': mine == null ? null : {'id': mine.id, 'status': mine.status.name},
      },
      if (forYou) 'reasons': ['In ${p.city}', if (p.skillLevels.contains('intermediate')) 'Intermediate'],
      if (detail && isOwner)
        'matching': {
          'count': p.matchCount,
          'alerted': p.matchCount,
          'waitingForDigest': 0,
          'summary': [
            {'label': 'In ${p.city}', 'count': p.matchCount},
          ],
        },
      'shareUrl': 'https://skorx.in/looking-for/${p.id}',
    });
  }

  LfResponse _responseView(_Response r, {required bool forPoster}) {
    final p = _posts[r.postId]!;
    return LfResponse.fromJson({
      'id': r.id,
      'postId': r.postId,
      'status': r.status.name,
      'message': r.message,
      'availabilityConfirmed': r.available,
      'respondedAt': r.at.toUtc().toIso8601String(),
      'decidedAt': r.decidedAt?.toUtc().toIso8601String(),
      if (forPoster)
        'person': {
          'userId': r.userId,
          'name': r.name,
          'city': r.city,
          'skillLevel': r.skill,
          'roles': r.roles,
          'matchesPlayed': r.matches,
          'recentMatches': (r.matches / 6).floor(),
        },
      'contact': {
        'iShared': forPoster ? r.posterShared : r.responderShared,
        'theyShared': forPoster ? r.responderShared : r.posterShared,
        'phone': r.status != LfResponseStatus.accepted
            ? null
            : forPoster
                ? (r.responderShared ? '+91 98250 ${r.id.hashCode.abs() % 90000 + 10000}' : null)
                : (r.posterShared ? '+91 99090 12345' : null),
      },
      if (!forPoster) 'postTitle': p.title,
    });
  }

  void _seed() {
    final now = _now();
    DateTime at(int days, int hour, [int minute = 0]) {
      final d = now.add(Duration(days: days));
      return DateTime(d.year, d.month, d.day, hour, minute);
    }

    DateTime soon(int hour) {
      final today = at(0, hour);
      return today.isAfter(now.add(const Duration(minutes: 45))) ? today : at(1, hour);
    }

    void add(_Post p) => _posts[p.id] = p;

    add(_Post(
      id: 'lf-1',
      creatorId: 'u-rahul',
      postedByName: 'Rahul Mehta',
      categoryId: 'player',
      icon: 'player',
      subcategoryId: 'player.players',
      title: '2 Players needed tonight',
      description: 'Doubles, friendly but competitive. Court is booked, balls provided.',
      placeName: 'Pickle Blitz Arena',
      city: 'Ahmedabad',
      startsAt: soon(20),
      durationMins: 90,
      quantityRequired: 2,
      quantityLabel: 'Players needed',
      skillLevels: const ['intermediate'],
      paymentType: LfPaymentType.fee,
      paymentAmount: 300,
      paymentUnit: 'per_person',
      details: const {'matchType': 'Doubles'},
      detailLabels: const {'matchType': 'Match type'},
      createdAt: now.subtract(const Duration(minutes: 25)),
    ));
    add(_Post(
      id: 'lf-2',
      creatorId: 'u-cadlete',
      postAs: 'organization',
      postedByName: 'CADLETE Pickleball',
      categoryId: 'referee',
      icon: 'referee',
      subcategoryId: 'referee.referee',
      title: 'Referees needed · SkorX Open',
      description: 'Main draw, four courts. Lunch and travel covered.',
      placeName: 'CADLETE Club',
      city: 'Ahmedabad',
      startsAt: at(6, 9),
      endsAt: at(6, 18),
      quantityRequired: 3,
      quantityLabel: 'Referees needed',
      paymentType: LfPaymentType.paid,
      paymentAmount: 1500,
      paymentUnit: 'per_day',
      details: const {'courts': 4, 'matches': 48, 'experience': 'Some events'},
      detailLabels: const {'courts': 'Courts', 'matches': 'Matches', 'experience': 'Experience'},
      tournamentName: 'SkorX Open 2026',
      createdAt: now.subtract(const Duration(hours: 5)),
    ));
    add(_Post(
      id: 'lf-3',
      creatorId: 'u-neha',
      postedByName: 'Neha Shah',
      categoryId: 'scorer',
      icon: 'scorer',
      title: 'Scorer for 6 hours',
      description: 'Live scoring on the SkorX app for a club league.',
      placeName: 'Smash Point',
      city: 'Ahmedabad',
      startsAt: at(2, 16),
      durationMins: 360,
      quantityRequired: 1,
      quantityLabel: 'Scorers needed',
      paymentType: LfPaymentType.paid,
      paymentAmount: 800,
      paymentUnit: 'total',
      details: const {'courts': 2},
      detailLabels: const {'courts': 'Courts'},
      createdAt: now.subtract(const Duration(hours: 9)),
    ));
    add(_Post(
      id: 'lf-4',
      creatorId: 'u-arjun',
      postedByName: 'Arjun Patel',
      categoryId: 'team',
      icon: 'team',
      subcategoryId: 'team.members',
      title: "1 male player for Men's Doubles",
      description: 'Our partner is injured. Looking for a 3.5+ player for SkorX Open.',
      city: 'Ahmedabad',
      quantityRequired: 1,
      quantityLabel: 'Players needed',
      skillLevels: const ['intermediate', 'advanced'],
      gender: 'male',
      details: const {'teamName': 'Kitchen Kings', 'division': "Men's"},
      detailLabels: const {'teamName': 'Team name', 'division': 'Division'},
      tournamentName: 'SkorX Open 2026',
      createdAt: now.subtract(const Duration(days: 1)),
    ));
    add(_Post(
      id: 'lf-5',
      creatorId: 'u-vihaan',
      postedByName: 'Vihaan Desai',
      categoryId: 'ground',
      icon: 'ground',
      subcategoryId: 'ground.court',
      title: '2 courts on Saturday evening',
      description: 'For a small club session. Indoor preferred.',
      city: 'Surat',
      startsAt: at((DateTime.saturday - now.weekday) % 7 == 0 ? 7 : (DateTime.saturday - now.weekday) % 7, 18),
      endsAt: at((DateTime.saturday - now.weekday) % 7 == 0 ? 7 : (DateTime.saturday - now.weekday) % 7, 21),
      paymentType: LfPaymentType.paid,
      paymentAmount: 2000,
      paymentUnit: 'total',
      details: const {'courts': 2, 'setting': 'Indoor'},
      detailLabels: const {'courts': 'Courts', 'setting': 'Indoor or outdoor'},
      createdAt: now.subtract(const Duration(days: 2)),
    ));
    add(_Post(
      id: 'lf-6',
      creatorId: 'u-media',
      postedByName: 'Pickle Pulse Media',
      categoryId: 'commentator',
      icon: 'commentator',
      title: 'Commentator for a live stream',
      description: 'Hindi and English. Finals day of the city league.',
      city: 'Ahmedabad',
      startsAt: at(9, 15),
      durationMins: 240,
      quantityLabel: 'Commentators needed',
      paymentType: LfPaymentType.paid,
      paymentAmount: 2500,
      paymentUnit: 'per_day',
      details: const {'language': 'Hindi, English'},
      detailLabels: const {'language': 'Language'},
      createdAt: now.subtract(const Duration(days: 3)),
    ));

    // Mine, with people who answered, so the poster's side can be tried.
    add(_Post(
      id: 'lf-mine',
      creatorId: meId,
      postedByName: 'You',
      categoryId: 'match',
      icon: 'match',
      subcategoryId: 'match.opponents',
      title: 'Opponents for Sunday doubles',
      description: 'We are a 3.0 pair looking for a friendly match.',
      placeName: 'Pickle Blitz Arena',
      city: 'Ahmedabad',
      startsAt: at(((DateTime.sunday - now.weekday) % 7) == 0 ? 7 : (DateTime.sunday - now.weekday) % 7, 7),
      durationMins: 90,
      quantityRequired: 2,
      quantityLabel: 'Players needed',
      skillLevels: const ['beginner', 'intermediate'],
      details: const {'matchType': 'Doubles'},
      detailLabels: const {'matchType': 'Match type'},
      createdAt: now.subtract(const Duration(hours: 20)),
      matchCount: 9,
      views: 41,
    ));
    for (final (i, name, city, skill, matches, msg) in [
      (1, 'Kavya Iyer', 'Ahmedabad', '3.0', 18, "We're a pair and free Sunday morning."),
      (2, 'Dev Trivedi', 'Gandhinagar', '3.5', 42, null),
      (3, 'Isha Rao', 'Ahmedabad', null, 3, 'New to pickleball but keen!'),
    ]) {
      final r = _Response('r-seed-$i', 'lf-mine', 'u-seed-$i', name, now.subtract(Duration(hours: 18 - i * 3)))
        ..city = city
        ..skill = skill
        ..matches = matches
        ..message = msg
        ..available = i != 3;
      _responses[r.id] = r;
    }
  }

  static bool _isTimeWord(String w) => const {'tonight', 'today', 'tomorrow', 'weekend', 'this', 'evening', 'morning'}.contains(w);

  static String? _guessCategory(String t) {
    for (final (re, id) in _guesses) {
      if (RegExp(re).hasMatch(t)) return id;
    }
    return null;
  }

  static String _label(String id) => (_catalogue.firstWhere((c) => c['id'] == id, orElse: () => _catalogue.last)['label']) as String;

  static String _subLabel(String id) {
    for (final c in _catalogue) {
      for (final s in (c['subcategories'] as List).cast<Map<String, dynamic>>()) {
        if (s['id'] == id) return s['label'] as String;
      }
    }
    return id;
  }
}

String _whenLabel(DateTime at, DateTime now) {
  final h = at.hour % 12 == 0 ? 12 : at.hour % 12;
  final time = '$h:${at.minute.toString().padLeft(2, '0')} ${at.hour < 12 ? 'AM' : 'PM'}';
  final days = DateTime(at.year, at.month, at.day).difference(DateTime(now.year, now.month, now.day)).inDays;
  if (days == 0) return 'Today $time';
  if (days == 1) return 'Tomorrow $time';
  const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${wd[at.weekday - 1]} ${at.day} ${mon[at.month - 1]} $time';
}

class _Post {
  _Post({
    required this.id,
    required this.creatorId,
    required this.postedByName,
    required this.categoryId,
    required this.icon,
    required this.title,
    required this.city,
    required this.createdAt,
    this.postAs = 'self',
    this.subcategoryId,
    this.description,
    this.placeName,
    this.startsAt,
    this.endsAt,
    this.durationMins,
    this.quantityRequired = 1,
    this.quantityLabel,
    this.skillLevels = const [],
    this.gender = 'any',
    this.paymentType = LfPaymentType.none,
    this.paymentAmount,
    this.paymentUnit,
    this.details = const {},
    this.detailLabels = const {},
    this.tournamentName,

    this.matchCount = 0,
    this.views = 0,
    DateTime? expiresAt,
  }) : expiresAt = expiresAt ??
            (endsAt ?? startsAt?.add(Duration(minutes: durationMins ?? 60)) ?? createdAt.add(const Duration(days: 7)));

  factory _Post.fromBody(String id, String creatorId, String name, Map<String, dynamic> b, DateTime now, String label, String icon,
      LfForm form) {
    DateTime? d(String k) => b[k] == null ? null : DateTime.parse(b[k] as String).toLocal();
    final startsAt = d('startsAt');
    final endsAt = d('endsAt');
    final preset = b['expiryPreset'] as String?;
    final expires = switch (preset) {
      '1h' => now.add(const Duration(hours: 1)),
      'today' => DateTime(now.year, now.month, now.day, 23, 59),
      'tomorrow' => DateTime(now.year, now.month, now.day + 1, 23, 59),
      'week' => now.add(const Duration(days: 7)),
      _ => null,
    };
    final payment = b['payment'] as Map<String, dynamic>?;
    return _Post(
      id: id,
      creatorId: creatorId,
      postedByName: name,
      categoryId: b['categoryId'] as String,
      icon: icon,
      subcategoryId: b['subcategoryId'] as String?,
      title: (b['title'] as String).trim(),
      description: b['description'] as String?,
      placeName: b['placeName'] as String?,
      city: (b['city'] as String).trim(),
      startsAt: startsAt,
      endsAt: endsAt,
      durationMins: b['durationMins'] as int?,
      quantityRequired: b['quantityRequired'] as int? ?? 1,
      quantityLabel: form.quantityLabel,
      skillLevels: [...?(b['skillLevels'] as List?)?.cast<String>()],
      gender: b['gender'] as String? ?? 'any',
      paymentType: LfPaymentType.parse((b['paymentType'] ?? payment?['type']) as String?),
      paymentAmount: b['paymentAmount'] as int?,
      paymentUnit: b['paymentUnit'] as String?,
      details: {...?(b['details'] as Map?)?.cast<String, Object?>()},
      detailLabels: {for (final f in form.details) f.key: f.label},
      createdAt: now,
      expiresAt: expires,
    );
  }

  final String id;
  final String creatorId;
  final String postAs;
  final String postedByName;
  final String categoryId;
  final String icon;
  final String? subcategoryId;
  String title;
  String? description;
  final String? placeName;
  final String city;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final int? durationMins;
  int quantityRequired;
  final String? quantityLabel;
  final List<String> skillLevels;
  final String gender;
  final LfPaymentType paymentType;
  final int? paymentAmount;
  final String? paymentUnit;
  final Map<String, Object?> details;
  final Map<String, String> detailLabels;
  final String? tournamentName;
  final String visibility = 'public';
  final DateTime createdAt;
  final DateTime expiresAt;
  DateTime? cancelledAt;
  DateTime? closedAt;
  bool hidden = false;
  int filled = 0;
  int matchCount;
  int views;
}

class _Response {
  _Response(this.id, this.postId, this.userId, this.name, this.at);

  final String id;
  final String postId;
  final String userId;
  final String name;
  final DateTime at;
  LfResponseStatus status = LfResponseStatus.pending;
  String? message;
  bool available = false;
  DateTime? decidedAt;
  bool posterShared = false;
  bool responderShared = false;
  String? city = 'Ahmedabad';
  String? skill;
  int matches = 0;
  List<String> roles = const [];
}

const _cities = ['Ahmedabad', 'Gandhinagar', 'Vadodara', 'Surat', 'Rajkot', 'Mumbai', 'Pune', 'Bengaluru', 'Delhi', 'Singapore'];

const _filler = {
  'need', 'needed', 'looking', 'for', 'want', 'wanted', 'required', 'the', 'and', 'near', 'with', 'this', 'that', 'some', 'any',
  'pickleball', 'players', 'player', 'people',
};

const _guesses = [
  (r'\b(referees?|umpires?)\b', 'referee'),
  (r'\b(scorers?|scorekeepers?)\b', 'scorer'),
  (r'\bcommentat', 'commentator'),
  (r'\b(streamers?|stream|camera)\b', 'streamer'),
  (r'\b(sponsors?)\b', 'sponsor'),
  (r'\b(coach|coaches|academy)\b', 'academy'),
  (r'\b(courts?|grounds?|venue)\b', 'ground'),
  (r'\bclubs?\b', 'club'),
  (r'\b(teams?|teammates?)\b', 'team'),
  (r'\b(opponents?|match|game)\b', 'match'),
  (r'\b(players?|partners?|people)\b', 'player'),
];

Map<String, dynamic> _cat(String id, String label, String group, String tagline, Map<String, dynamic> form, List<(String, String)> subs) =>
    {
      'id': id,
      'label': label,
      'group': group,
      'icon': id,
      'tagline': tagline,
      'form': form,
      'subcategories': [for (final (sid, l) in subs) {'id': sid, 'label': l}],
    };

const _matchType = {'key': 'matchType', 'label': 'Match type', 'type': 'choice', 'options': ['Singles', 'Doubles', 'Mixed doubles']};
const _division = {'key': 'division', 'label': 'Division', 'type': 'choice', 'options': ["Men's", "Women's", 'Mixed', 'Open']};
const _courts = {'key': 'courts', 'label': 'Courts', 'type': 'number', 'min': 1, 'max': 60};
const _playerFields = ['when', 'place', 'quantity', 'skill', 'gender', 'age', 'payment', 'tournament'];
const _officialFields = ['when', 'endTime', 'duration', 'place', 'quantity', 'payment', 'tournament'];

final _catalogue = <Map<String, dynamic>>[
  _cat('player', 'Players', 'PLAYER', 'Fill a game, find a partner', {
    'fields': _playerFields, 'required': ['when', 'quantity'], 'quantityLabel': 'Players needed', 'details': [_matchType],
    'roles': ['player'], 'payment': 'fee',
  }, [('player.players', 'Players'), ('player.partner', 'Partner'), ('player.opponent', 'Opponent'), ('player.substitute', 'Substitute'),
    ('player.practice', 'Practice partner')]),
  _cat('team', 'Team', 'TEAM', 'Build or join a team', {
    'fields': ['when', 'place', 'quantity', 'skill', 'gender', 'age', 'tournament'], 'required': ['quantity'],
    'quantityLabel': 'Players needed',
    'details': [{'key': 'teamName', 'label': 'Team name', 'type': 'text'}, _division], 'roles': ['player'], 'payment': 'none',
  }, [('team.members', 'Team members'), ('team.join', 'A team to join'), ('team.opponent', 'Opponent team'), ('team.substitute', 'Substitute')]),
  _cat('match', 'Match', 'MATCH', 'Get a game on', {
    'fields': _playerFields, 'required': ['when'], 'quantityLabel': 'Players needed', 'details': [_matchType], 'roles': ['player'],
    'payment': 'fee',
  }, [('match.match', 'A match'), ('match.opponents', 'Opponents'), ('match.players', 'Players for a match'), ('match.partner', 'Partner for a match')]),
  _cat('tournament', 'Tournament', 'TOURNAMENT', 'Entries, teams, volunteers', {
    'fields': ['when', 'place', 'quantity', 'skill', 'gender', 'age', 'payment', 'tournament'], 'required': <String>[],
    'quantityLabel': 'People needed', 'details': [_division], 'roles': ['player', 'organizer'], 'payment': 'none',
  }, [('tournament.to_play', 'A tournament to play'), ('tournament.players', 'Players'), ('tournament.teams', 'Teams'),
    ('tournament.volunteers', 'Volunteers')]),
  _cat('ground', 'Ground / Court', 'VENUE', 'Courts for your session', {
    'fields': ['when', 'endTime', 'place', 'payment'], 'required': ['when'],
    'details': [
      _courts,
      {'key': 'setting', 'label': 'Indoor or outdoor', 'type': 'choice', 'options': ['Any', 'Indoor', 'Outdoor']},
      {'key': 'facilities', 'label': 'Facilities needed', 'type': 'text'},
    ],
    'roles': ['organizer'], 'payment': 'paid',
  }, [('ground.ground', 'Ground'), ('ground.court', 'Court'), ('ground.booking', 'Court booking')]),
  _cat('club', 'Club', 'COMMUNITY', 'A club to play at', {
    'fields': ['place', 'skill', 'payment'], 'required': <String>[], 'details': <Object>[], 'roles': ['organizer'], 'payment': 'none',
  }, [('club.join', 'A club to join')]),
  _cat('referee', 'Referee', 'OFFICIALS', 'Officials for your event', {
    'fields': _officialFields, 'required': ['when', 'quantity'], 'quantityLabel': 'Referees needed',
    'details': [
      _courts,
      {'key': 'matches', 'label': 'Matches', 'type': 'number', 'min': 1, 'max': 500},
      {'key': 'experience', 'label': 'Experience', 'type': 'choice', 'options': ['Any', 'Some events', 'Certified']},
    ],
    'roles': ['referee', 'official'], 'payment': 'paid',
  }, [('referee.referee', 'Referee'), ('referee.official', 'Tournament official')]),
  _cat('scorer', 'Scorer', 'OFFICIALS', 'Keep the score live', {
    'fields': _officialFields, 'required': ['when', 'quantity'], 'quantityLabel': 'Scorers needed', 'details': [_courts],
    'roles': ['scorekeeper'], 'payment': 'paid',
  }, [('scorer.scorer', 'Scorer'), ('scorer.live_operator', 'Live scoring operator')]),
  _cat('commentator', 'Commentator', 'MEDIA', 'A voice for the stream', {
    'fields': _officialFields, 'required': ['when'], 'quantityLabel': 'Commentators needed',
    'details': [{'key': 'language', 'label': 'Language', 'type': 'text'}], 'roles': ['commentator'], 'payment': 'paid',
  }, [('commentator.commentator', 'Commentator')]),
  _cat('streamer', 'Streamer', 'MEDIA', 'Stream, film, create', {
    'fields': _officialFields, 'required': ['when'], 'quantityLabel': 'People needed', 'details': [_courts],
    'roles': ['streamer', 'photographer', 'creator'], 'payment': 'paid',
  }, [('streamer.streamer', 'Streamer'), ('streamer.camera', 'Camera operator'), ('streamer.creator', 'Content creator')]),
  _cat('academy', 'Academy / Coach', 'COMMUNITY', 'Coaching and training', {
    'fields': ['when', 'place', 'skill', 'age', 'payment'], 'required': <String>[], 'details': <Object>[], 'roles': ['coach', 'trainer'],
    'payment': 'fee',
  }, [('academy.academy', 'Academy'), ('academy.coach', 'Coach')]),
  _cat('sponsor', 'Sponsor / Partner', 'COMMUNITY', 'Sponsors and collaborations', {
    'fields': ['when', 'place', 'tournament'], 'required': <String>[], 'details': <Object>[], 'roles': ['organizer'], 'payment': 'none',
  }, [('sponsor.sponsor', 'Sponsor'), ('sponsor.event_partner', 'Event partner'), ('sponsor.brand', 'Brand collaboration')]),
  _cat('other', 'Other', 'COMMUNITY', 'Anything pickleball', {
    'fields': ['when', 'place', 'quantity', 'payment', 'tournament'], 'required': <String>[], 'quantityLabel': 'People needed',
    'details': <Object>[], 'roles': <String>[], 'payment': 'none',
  }, []),
];
