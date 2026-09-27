import '../../../core/api/api_exception.dart';
import '../../../core/sample_latency.dart';
import 'community.dart';
import 'community_query.dart';
import 'community_repository.dart';
import 'content.dart';
import 'messages.dart';
import 'personalize.dart';

/// Debug builds: a small, consistent pickleball community around Ahmedabad.
/// Players link to the sample players (`SKX-…`), places to the sample venues
/// (`v-…`) and tournaments (`t-…`), so every tap lands on real sample data.
/// Applies the rules the server will: blocks hide people both ways, a member
/// who takes messages from connections only cannot be messaged cold, and a
/// cold message waits for a reply before the next.
class SampleCommunityRepository implements CommunityRepository {
  SampleCommunityRepository({this.latency = Duration.zero, bool newcomer = false, this.myName = 'You'}) : _newcomer = newcomer {
    final now = DateTime.now();
    if (newcomer) {
      _profile = const MyCommunityProfile();
      return;
    }
    _profile = const MyCommunityProfile(
      roles: {CommunityRole.player},
      languages: ['English', 'Gujarati'],
      rolesChosen: true,
    );
    _graph = const CommunityGraph(
      connections: {
        'cm-kavya': ConnectionStatus.connected,
        'cm-aarav': ConnectionStatus.connected,
        'cm-nikhil': ConnectionStatus.connected,
        'cm-meera': ConnectionStatus.pendingIn,
        'cm-sunil': ConnectionStatus.pendingOut,
      },
      following: {'pl-cadlete', 'cm-aditya'},
      groups: {'g-amd': GroupStatus.member, 'g-guj-players': GroupStatus.member, 'g-bodakdev': GroupStatus.member},
      adminOf: {'g-bodakdev'},
      saved: {'pl-smashacad': CommunityTarget.place},
    );
    _conversations.addAll([
      Conversation(
        id: 'cv-kavya',
        kind: ConversationKind.direct,
        targetId: 'cm-kavya',
        title: 'Kavya Mehta',
        lastText: 'Court 2 at 7 then. I will bring balls.',
        lastAt: now.subtract(const Duration(minutes: 18)),
        unread: 1,
      ),
      Conversation(
        id: 'cv-rohan',
        kind: ConversationKind.direct,
        targetId: 'cm-rohan',
        title: 'Rohan Desai',
        lastText: 'Hi! I referee in Vadodara and Ahmedabad. Happy to help at your next club event.',
        lastAt: now.subtract(const Duration(hours: 3)),
        unread: 1,
        request: true,
      ),
      Conversation(
        id: 'cv-g-amd',
        kind: ConversationKind.group,
        targetId: 'g-amd',
        title: 'Ahmedabad Pickleball',
        lastText: 'Nikhil: Open play at Riverside this Sunday, 6 AM.',
        lastAt: now.subtract(const Duration(hours: 5)),
        unread: 2,
      ),
      Conversation(
        id: 'cv-cadlete',
        kind: ConversationKind.place,
        targetId: 'pl-cadlete',
        title: 'CADLETE Club',
        lastText: 'Thanks! Club nights are every Thursday from 7 PM.',
        lastAt: now.subtract(const Duration(days: 2)),
      ),
    ]);
    _messages
      ..['cv-kavya'] = [
        _msg('cv-kavya', 'cm-kavya', 'Kavya Mehta', 'Up for doubles on Saturday?', now.subtract(const Duration(hours: 2))),
        _msg('cv-kavya', meId, myName, 'Yes! Blitz Arena, 7 AM?', now.subtract(const Duration(hours: 1))),
        _msg('cv-kavya', 'cm-kavya', 'Kavya Mehta', 'Court 2 at 7 then. I will bring balls.', now.subtract(const Duration(minutes: 18))),
      ]
      ..['cv-rohan'] = [
        _msg('cv-rohan', 'cm-rohan', 'Rohan Desai',
            'Hi! I referee in Vadodara and Ahmedabad. Happy to help at your next club event.', now.subtract(const Duration(hours: 3))),
      ]
      ..['cv-g-amd'] = [
        _msg('cv-g-amd', 'cm-aarav', 'Aarav Shah', 'Anyone for a 4.0 game tomorrow evening?', now.subtract(const Duration(hours: 9))),
        _msg('cv-g-amd', 'cm-nikhil', 'Nikhil Agarwal', 'Open play at Riverside this Sunday, 6 AM.', now.subtract(const Duration(hours: 5))),
      ]
      ..['cv-cadlete'] = [
        _msg('cv-cadlete', meId, myName, 'Hi, do you run social nights for club members?', now.subtract(const Duration(days: 2, hours: 1))),
        _msg('cv-cadlete', 'pl-cadlete', 'CADLETE Club', 'Thanks! Club nights are every Thursday from 7 PM.',
            now.subtract(const Duration(days: 2))),
      ];
  }

  final Duration latency;
  final String myName;
  final bool _newcomer;
  late MyCommunityProfile _profile;
  CommunityGraph _graph = const CommunityGraph();
  final List<Conversation> _conversations = [];
  final Map<String, List<ChatMessage>> _messages = {};
  final List<CommunityGroup> _createdGroups = [];
  late final List<CommunityEvent> _events = sampleEvents(DateTime.now());
  late final List<CommunityPost> _posts = samplePosts(DateTime.now());
  final Map<String, List<PostComment>> _comments = {};
  final Set<String> _liked = {};
  final List<VerificationRequest> _verifications = [];

  /// Organiser feedback given here: (member, role, recommend, onTime).
  final List<(String, CommunityRole, bool, bool?)> _feedback = [];

  /// Join requests waiting in communities I run.
  final Map<String, List<String>> _groupRequests = {
    'g-bodakdev': ['cm-nisha', 'cm-parth'],
  };
  int _seq = 0;

  /// Reports filed, for tests: (target, id, reason).
  final List<(ReportTarget, String, ReportReason)> reports = [];

  static ChatMessage _msg(String conversation, String sender, String name, String text, DateTime at) =>
      ChatMessage(id: '$conversation-${at.microsecondsSinceEpoch}', conversationId: conversation, senderId: sender, senderName: name, text: text, at: at);

  Future<void> _wait() => simulateLatency(latency);

  List<CommunityGroup> get _allGroups => [..._createdGroups, if (!_newcomer) sampleAdminGroup, ...sampleGroups];

  // ─── Directory ──────────────────────────────────────────────────────────

  @override
  Future<List<CommunityMember>> members(CommunityQuery query) async {
    await _wait();
    return [for (final m in sampleMembers) if (!_graph.hasBlocked(m.id) && query.matchesMember(m)) m];
  }

  @override
  Future<CommunityMember> member(String id) async {
    await _wait();
    final m = sampleMembers.where((m) => m.id == id).firstOrNull ??
        (throw const ApiException('NOT_FOUND', 'This profile is not on SkorX.'));
    final given = _feedback.where((f) => f.$1 == id).toList();
    if (given.isEmpty) return m;
    // Feedback left here shows on the profile, as the server works it out.
    return CommunityMember(
      id: m.id,
      name: m.name,
      city: m.city,
      state: m.state,
      headline: m.headline,
      bio: m.bio,
      playerId: m.playerId,
      level: m.level,
      tags: m.tags,
      languages: m.languages,
      serviceArea: m.serviceArea,
      availability: m.availability,
      placeIds: m.placeIds,
      groupIds: m.groupIds,
      mutualConnections: m.mutualConnections,
      acceptsMessagesFrom: m.acceptsMessagesFrom,
      roles: [
        for (final r in m.roles)
          if (given.where((f) => f.$2 == r.role).toList() case final mine when mine.isNotEmpty)
            RoleRecord(r.role, verified: r.verified, since: r.since, highlights: r.highlights, metrics: [
              ...r.metrics.where((x) => x.$1 != 'Organiser feedback'),
              ('Organiser feedback', '${(mine.where((f) => f.$3).length * 100 / mine.length).round()}% positive (${mine.length})'),
            ])
          else
            r,
      ],
    );
  }

  @override
  Future<List<CommunityPlace>> places(CommunityQuery query) async {
    await _wait();
    return [for (final p in samplePlaces) if (query.matchesPlace(p)) p];
  }

  @override
  Future<CommunityPlace> place(String id) async {
    await _wait();
    return samplePlaces.where((p) => p.id == id).firstOrNull ??
        (throw const ApiException('NOT_FOUND', 'This page is not on SkorX.'));
  }

  @override
  Future<List<CommunityGroup>> groups({String? city, String query = ''}) async {
    await _wait();
    final q = query.trim().toLowerCase();
    final state = city == null ? null : communityCities[city];
    int rank(CommunityGroup g) => g.city == city && city != null ? 0 : (g.state == state && state != null && g.city == null ? 1 : 2);
    final list = [
      for (final g in _allGroups)
        if (q.isEmpty || '${g.name} ${g.about} ${g.placeLabel}'.toLowerCase().contains(q))
          if (city == null || g.city == null || g.city == city) g,
    ]..sort((a, b) => rank(a) != rank(b) ? rank(a) - rank(b) : b.activeThisWeek - a.activeThisWeek);
    return list;
  }

  @override
  Future<CommunityGroup> group(String id) async {
    await _wait();
    return _allGroups.where((g) => g.id == id).firstOrNull ??
        (throw const ApiException('NOT_FOUND', 'This community is not on SkorX.'));
  }

  @override
  Future<List<Suggestion>> suggestions({String? city, Set<CommunityRole> forRoles = const {}}) async {
    await _wait();
    final wanted = rolesOfInterest(forRoles);
    final myGroups = _graph.joinedGroups.toSet();
    final scored = <(Suggestion, int)>[];
    for (final m in sampleMembers) {
      if (_graph.hasBlocked(m.id) || _graph.connectionWith(m.id) != ConnectionStatus.none) continue;
      final sharedGroup = m.groupIds.where(myGroups.contains).firstOrNull;
      final relevant = m.roles.map((r) => r.role).where(wanted.contains).firstOrNull;
      final local = city != null && (m.city == city || m.serviceArea.contains(city));
      final score = m.mutualConnections * 2 + (local ? 4 : 0) + (sharedGroup != null ? 3 : 0) + (relevant != null ? 5 : 0);
      if (score < 4) continue;
      final reason = m.mutualConnections >= 2
          ? '${m.mutualConnections} mutual connections'
          : sharedGroup != null
              ? 'Also in ${_allGroups.firstWhere((g) => g.id == sharedGroup).name}'
              : relevant != null && relevant != CommunityRole.player
                  ? '${relevant.label} · ${local ? city : m.city}'
                  : local
                      ? 'Plays in $city'
                      : m.placeLabel;
      scored.add((Suggestion(m, reason), score));
    }
    scored.sort((a, b) => b.$2 - a.$2);
    return [for (final (s, _) in scored.take(10)) s];
  }

  // ─── Me ─────────────────────────────────────────────────────────────────

  @override
  Future<CommunityGraph> graph() async {
    await _wait();
    return _graph;
  }

  @override
  Future<MyCommunityProfile> myProfile() async {
    await _wait();
    return _profile;
  }

  @override
  Future<MyCommunityProfile> saveProfile(MyCommunityProfile profile) async {
    await _wait();
    if (profile.roles.isEmpty) throw const ApiException('VALIDATION', 'Choose at least one role.');
    return _profile = profile.copyWith(rolesChosen: true);
  }

  // ─── Ties ───────────────────────────────────────────────────────────────

  void _checkMember(String id) {
    if (!sampleMembers.any((m) => m.id == id)) throw const ApiException('NOT_FOUND', 'This profile is not on SkorX.');
    if (_graph.hasBlocked(id)) throw const ApiException('BLOCKED', 'Unblock them first.');
  }

  @override
  Future<ConnectionStatus> connect(String memberId) async {
    await _wait();
    _checkMember(memberId);
    final next = switch (_graph.connectionWith(memberId)) {
      ConnectionStatus.pendingIn || ConnectionStatus.connected => ConnectionStatus.connected,
      _ => ConnectionStatus.pendingOut,
    };
    _graph = _graph.withConnection(memberId, next);
    // A conversation that was a request becomes a normal thread.
    _updateConversations((c) => c.targetId == memberId ? c.copyWith(request: false, awaitingReply: false) : c);
    return next;
  }

  @override
  Future<void> disconnect(String memberId) async {
    await _wait();
    _graph = _graph.withConnection(memberId, ConnectionStatus.none);
  }

  @override
  Future<void> follow(String targetId, {required bool on, CommunityTarget type = CommunityTarget.member}) async {
    await _wait();
    if (_graph.hasBlocked(targetId)) throw const ApiException('BLOCKED', 'Unblock them first.');
    _graph = _graph.copyWith(following: toggledIn(_graph.following, targetId, on));
  }

  @override
  Future<GroupStatus> joinGroup(String groupId) async {
    await _wait();
    final g = await group(groupId);
    final status = g.access == GroupAccess.public ? GroupStatus.member : GroupStatus.requested;
    _graph = _graph.withGroup(groupId, status);
    return status;
  }

  @override
  Future<void> leaveGroup(String groupId) async {
    await _wait();
    _graph = _graph.withGroup(groupId, GroupStatus.none);
  }

  @override
  Future<CommunityGroup> createGroup({required String name, required String about, required GroupAccess access, String? city}) async {
    await _wait();
    final clean = name.trim();
    if (clean.length < 3) throw const ApiException('VALIDATION', 'Give the community a name of at least 3 letters.');
    if (access == GroupAccess.verified) {
      throw const ApiException('FORBIDDEN', 'Verified communities are run by verified organisations.');
    }
    if (_allGroups.any((g) => g.name.toLowerCase() == clean.toLowerCase())) {
      throw const ApiException('DUPLICATE', 'A community with this name already exists. Join it instead?');
    }
    final g = CommunityGroup(
      id: 'g-new-${++_seq}',
      name: clean,
      about: about.trim(),
      access: access,
      members: 1,
      activeThisWeek: 1,
      city: city,
      state: city == null ? null : communityCities[city],
    );
    _createdGroups.add(g);
    _graph = _graph.withGroup(g.id, GroupStatus.member).copyWith(adminOf: {..._graph.adminOf, g.id});
    return g;
  }

  @override
  Future<void> save(String targetId, {required bool on, required CommunityTarget type}) async {
    await _wait();
    _graph = _graph.withSaved(targetId, type, on);
  }

  @override
  Future<void> block(String memberId, {required bool on}) async {
    await _wait();
    if (on) {
      _graph = _graph
          .withConnection(memberId, ConnectionStatus.none)
          .copyWith(blocked: {..._graph.blocked, memberId}, following: toggledIn(_graph.following, memberId, false));
      _conversations.removeWhere((c) => c.kind == ConversationKind.direct && c.targetId == memberId);
    } else {
      _graph = _graph.copyWith(blocked: toggledIn(_graph.blocked, memberId, false));
    }
  }

  @override
  Future<void> report(ReportTarget target, String targetId, ReportReason reason, {String? note}) async {
    await _wait();
    reports.add((target, targetId, reason));
  }

  @override
  Future<List<CommunityMember>> groupRequests(String groupId) async {
    await _wait();
    if (!_graph.admins(groupId)) throw const ApiException('FORBIDDEN', 'Only the community admins can do that.');
    return [for (final id in _groupRequests[groupId] ?? const <String>[]) ?sampleMembers.where((m) => m.id == id).firstOrNull];
  }

  @override
  Future<void> decideGroupRequest(String groupId, String memberId, {required bool approve}) async {
    await _wait();
    if (!_graph.admins(groupId)) throw const ApiException('FORBIDDEN', 'Only the community admins can do that.');
    _groupRequests[groupId]?.remove(memberId);
  }

  // ─── Reputation and verification ────────────────────────────────────────

  @override
  Future<void> feedback({required String memberId, required CommunityRole role, required bool recommend, bool? onTime, String? note}) async {
    await _wait();
    if (!feedbackRoles.contains(role)) throw ApiException('VALIDATION', 'Feedback is not collected for ${role.plural.toLowerCase()}.');
    final m = await member(memberId);
    if (!m.hasRole(role)) throw ApiException('VALIDATION', 'They are not listed as a ${role.label.toLowerCase()}.');
    _feedback
      ..removeWhere((f) => f.$1 == memberId && f.$2 == role)
      ..add((memberId, role, recommend, onTime));
  }

  @override
  Future<List<VerificationRequest>> myVerifications() async {
    await _wait();
    return [..._verifications];
  }

  @override
  Future<VerificationRequest> requestVerification({required CommunityRole role, required String evidence, List<String> links = const []}) async {
    await _wait();
    if (!_profile.roles.contains(role)) throw const ApiException('VALIDATION', 'Add this role to your profile first.');
    if (evidence.trim().length < 20) throw const ApiException('VALIDATION', 'Tell us a little more: at least 20 characters.');
    if (_verifications.any((v) => v.role == role && v.status == VerificationStatus.pending)) {
      throw const ApiException('RESOURCE_CONFLICT', 'Your request is already with the SkorX team.');
    }
    final v = VerificationRequest(id: 'vr-${++_seq}', role: role, status: VerificationStatus.pending, createdAt: DateTime.now());
    _verifications.insert(0, v);
    return v;
  }

  // ─── Events ─────────────────────────────────────────────────────────────

  @override
  Future<List<CommunityEvent>> events({String? city, String? groupId, String? placeId}) async {
    await _wait();
    final now = DateTime.now();
    return [
      for (final e in _events)
        if (!e.cancelled && e.endsAt.isAfter(now))
          if (city == null || e.city == city)
            if (groupId == null || e.groupId == groupId)
              if (placeId == null || e.placeId == placeId) e,
    ]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  }

  @override
  Future<CommunityEvent> event(String id) async {
    await _wait();
    return _events.where((e) => e.id == id).firstOrNull ?? (throw const ApiException('NOT_FOUND', 'This event is not on SkorX.'));
  }

  @override
  Future<CommunityEvent> createEvent(EventDraft d) async {
    await _wait();
    if (d.title.trim().length < 3) throw const ApiException('VALIDATION', 'Give the event a title.');
    if (!d.endsAt.isAfter(d.startsAt)) throw const ApiException('VALIDATION', 'The event must end after it starts.');
    if (d.startsAt.isBefore(DateTime.now().subtract(const Duration(hours: 1)))) {
      throw const ApiException('VALIDATION', 'Pick a time in the future.');
    }
    final place = d.placeId == null ? null : samplePlaces.where((p) => p.id == d.placeId).firstOrNull;
    final e = CommunityEvent(
      id: 'ev-new-${++_seq}',
      kind: d.kind,
      title: d.title.trim(),
      about: d.about.trim(),
      startsAt: d.startsAt,
      endsAt: d.endsAt,
      city: d.city,
      address: d.address,
      placeId: d.placeId,
      placeName: place?.name,
      groupId: d.groupId,
      organizerId: meId,
      organizerName: myName,
      capacity: d.capacity,
      feeInr: d.feeInr,
      level: d.level,
      going: 1,
      myRsvp: RsvpStatus.going,
      mine: true,
    );
    _events.add(e);
    return e;
  }

  @override
  Future<CommunityEvent> rsvp(String eventId, RsvpStatus? status) async {
    await _wait();
    final i = _events.indexWhere((e) => e.id == eventId);
    if (i < 0 || _events[i].cancelled) throw const ApiException('NOT_FOUND', 'This event was cancelled.');
    final e = _events[i];
    if (status == null && e.mine) throw const ApiException('VALIDATION', 'You are hosting this event.');
    if (status == RsvpStatus.going && e.full) {
      throw const ApiException('RESOURCE_CONFLICT', 'This event is full. Mark yourself interested to hear if a spot opens.');
    }
    var going = e.going - (e.myRsvp == RsvpStatus.going ? 1 : 0);
    var interested = e.interested - (e.myRsvp == RsvpStatus.interested ? 1 : 0);
    if (status == RsvpStatus.going) going++;
    if (status == RsvpStatus.interested) interested++;
    return _events[i] = e.copyWith(going: going, interested: interested, myRsvp: () => status);
  }

  @override
  Future<void> cancelEvent(String eventId) async {
    await _wait();
    final i = _events.indexWhere((e) => e.id == eventId);
    if (i < 0) return;
    if (!_events[i].mine) throw const ApiException('FORBIDDEN', 'Only the organiser can cancel this event.');
    _events[i] = _events[i].copyWith(cancelled: true);
  }

  // ─── Posts ──────────────────────────────────────────────────────────────

  bool _inScope(CommunityPost p, FeedScope s) {
    if (s.groupId != null) return p.groupId == s.groupId;
    if (s.placeId != null) return p.placeId == s.placeId;
    if (s.authorId != null) return p.authorId == s.authorId && p.groupId == null;
    // My network: people I am connected to or follow, places I follow, my groups, me.
    return p.mine ||
        _graph.connectionWith(p.authorId) == ConnectionStatus.connected ||
        _graph.follows(p.authorId) ||
        (p.placeId != null && _graph.follows(p.placeId!)) ||
        (p.groupId != null && _graph.groupStatus(p.groupId!) == GroupStatus.member);
  }

  @override
  Future<PostPage> feed(FeedScope scope, {String? cursor}) async {
    await _wait();
    final list = [for (final p in _posts) if (!_graph.hasBlocked(p.authorId) && (!p.hidden || p.mine) && _inScope(p, scope)) p]
      ..sort((a, b) => b.at.compareTo(a.at));
    return PostPage([for (final p in list) p.copyWith(likedByMe: _liked.contains(p.id))], null);
  }

  @override
  Future<CommunityPost> createPost({required PostKind kind, required String body, String? link, String? groupId, String? eventId}) async {
    await _wait();
    final text = body.trim();
    if (text.isEmpty) throw const ApiException('VALIDATION', 'Write something first.');
    if (text.length > 1000) throw const ApiException('VALIDATION', 'Keep posts under 1,000 characters.');
    if (link != null && !RegExp(r'^/player/').hasMatch(link)) throw const ApiException('VALIDATION', 'Links can only point inside SkorX.');
    if (groupId != null && _graph.groupStatus(groupId) != GroupStatus.member) {
      throw const ApiException('FORBIDDEN', 'Join the community to post in it.');
    }
    final group = groupId == null ? null : _allGroups.where((g) => g.id == groupId).firstOrNull;
    final p = CommunityPost(
      id: 'ps-new-${++_seq}',
      kind: kind,
      body: text,
      link: link,
      authorId: meId,
      authorName: myName,
      groupId: groupId,
      groupName: group?.name,
      eventId: eventId,
      mine: true,
      at: DateTime.now(),
    );
    _posts.add(p);
    return p;
  }

  @override
  Future<void> deletePost(String postId) async {
    await _wait();
    final p = _posts.where((p) => p.id == postId).firstOrNull;
    if (p != null && !p.mine && !(p.groupId != null && _graph.admins(p.groupId!))) {
      throw const ApiException('FORBIDDEN', 'You can only delete your own posts.');
    }
    _posts.removeWhere((p) => p.id == postId);
  }

  @override
  Future<int> like(String postId, {required bool on}) async {
    await _wait();
    final i = _posts.indexWhere((p) => p.id == postId);
    if (i < 0) throw const ApiException('NOT_FOUND', 'This post is no longer available.');
    final had = _liked.contains(postId);
    if (on != had) {
      on ? _liked.add(postId) : _liked.remove(postId);
      _posts[i] = _posts[i].copyWith(likes: _posts[i].likes + (on ? 1 : -1));
    }
    return _posts[i].likes;
  }

  @override
  Future<List<PostComment>> comments(String postId) async {
    await _wait();
    return [...?_comments[postId]];
  }

  @override
  Future<PostComment> comment(String postId, String body) async {
    await _wait();
    final text = body.trim();
    if (text.isEmpty || text.length > 500) throw const ApiException('VALIDATION', 'Comments are 1–500 characters.');
    final i = _posts.indexWhere((p) => p.id == postId);
    if (i < 0) throw const ApiException('NOT_FOUND', 'This post is no longer available.');
    final c = PostComment(id: 'cmt-${++_seq}', postId: postId, authorId: meId, authorName: myName, body: text, at: DateTime.now(), mine: true);
    _comments.putIfAbsent(postId, () => []).add(c);
    _posts[i] = _posts[i].copyWith(comments: _posts[i].comments + 1);
    return c;
  }

  @override
  Future<void> deleteComment(String commentId) async {
    await _wait();
    for (final e in _comments.entries) {
      final c = e.value.where((c) => c.id == commentId).firstOrNull;
      if (c == null) continue;
      e.value.remove(c);
      final i = _posts.indexWhere((p) => p.id == e.key);
      if (i >= 0) _posts[i] = _posts[i].copyWith(comments: _posts[i].comments - 1);
    }
  }

  // ─── Messages ───────────────────────────────────────────────────────────

  void _updateConversations(Conversation Function(Conversation) change) {
    for (var i = 0; i < _conversations.length; i++) {
      _conversations[i] = change(_conversations[i]);
    }
  }

  @override
  Future<List<Conversation>> conversations() async {
    await _wait();
    return [..._conversations]..sort((a, b) => b.lastAt.compareTo(a.lastAt));
  }

  @override
  Future<Conversation> openConversation(ConversationKind kind, String targetId) async {
    await _wait();
    final existing = _conversations.where((c) => c.kind == kind && c.targetId == targetId).firstOrNull;
    if (existing != null) return existing;
    late final String title;
    var awaiting = false;
    switch (kind) {
      case ConversationKind.direct:
        final m = await member(targetId);
        if (_graph.hasBlocked(targetId)) throw const ApiException('BLOCKED', 'You blocked this member. Unblock them to message.');
        final connected = _graph.connectionWith(targetId) == ConnectionStatus.connected;
        if (!connected && m.acceptsMessagesFrom == MessagePermission.connections) {
          throw ApiException('MESSAGES_RESTRICTED',
              '${m.name.split(' ').first} takes messages from connections only. Send a connection request first.');
        }
        title = m.name;
        awaiting = !connected;
      case ConversationKind.place:
        title = (await place(targetId)).name;
      case ConversationKind.group:
        final g = await group(targetId);
        if (_graph.groupStatus(targetId) != GroupStatus.member) {
          throw const ApiException('FORBIDDEN', 'Join the community to see its chat.');
        }
        title = g.name;
      case ConversationKind.event:
        final e = await event(targetId);
        if (!e.mine && e.myRsvp == null) throw const ApiException('FORBIDDEN', 'RSVP to the event to join its chat.');
        title = e.title;
    }
    final c = Conversation(
      id: 'cv-new-${++_seq}',
      kind: kind,
      targetId: targetId,
      title: title,
      lastAt: DateTime.now(),
      awaitingReply: awaiting,
    );
    _conversations.add(c);
    _messages[c.id] = [];
    return c;
  }

  Conversation _conversation(String id) =>
      _conversations.where((c) => c.id == id).firstOrNull ?? (throw const ApiException('NOT_FOUND', 'This conversation was deleted.'));

  @override
  Future<List<ChatMessage>> messages(String conversationId) async {
    await _wait();
    _conversation(conversationId);
    return [...?_messages[conversationId]];
  }

  @override
  Future<ChatMessage> send(String conversationId, String text) async {
    await _wait();
    final c = _conversation(conversationId);
    final body = text.trim();
    if (body.isEmpty) throw const ApiException('VALIDATION', 'Write a message first.');
    if (body.length > maxMessageLength) throw const ApiException('VALIDATION', 'Keep messages under 2,000 characters.');
    if (c.kind == ConversationKind.direct && _graph.hasBlocked(c.targetId)) {
      throw const ApiException('BLOCKED', 'You blocked this member. Unblock them to message.');
    }
    final list = _messages.putIfAbsent(conversationId, () => []);
    if (c.awaitingReply && list.any((m) => m.mine)) {
      throw ApiException('AWAITING_REPLY', 'You can send more once ${c.title.split(' ').first} replies or connects with you.');
    }
    final m = _msg(conversationId, meId, myName, body, DateTime.now());
    list.add(m);
    _updateConversations((x) => x.id == conversationId ? x.copyWith(lastText: body, lastAt: m.at, request: false) : x);
    return m;
  }

  @override
  Future<void> markRead(String conversationId) async {
    _updateConversations((c) => c.id == conversationId ? c.copyWith(unread: 0) : c);
  }

  @override
  Future<void> acceptRequest(String conversationId) async {
    await _wait();
    _updateConversations((c) => c.id == conversationId ? c.copyWith(request: false) : c);
  }

  @override
  Future<void> deleteConversation(String conversationId) async {
    await _wait();
    _conversations.removeWhere((c) => c.id == conversationId);
    _messages.remove(conversationId);
  }
}

// ─── Sample data ───────────────────────────────────────────────────────────

const _gj = 'Gujarat';
const _mh = 'Maharashtra';

const sampleMembers = <CommunityMember>[
  // Players (linked to the sample player directory).
  CommunityMember(
    id: 'cm-aarav',
    name: 'Aarav Shah',
    city: 'Ahmedabad',
    state: _gj,
    headline: 'Competitive doubles, 4.0+. Always up for a morning game.',
    playerId: 'SKX-10021',
    level: 'Advanced',
    tags: ['Doubles', 'Competitive'],
    languages: ['English', 'Gujarati', 'Hindi'],
    roles: [
      RoleRecord(CommunityRole.player, since: 2022, metrics: [('SkorX Points', '1420'), ('Matches', '142'), ('Win rate', '78%')]),
    ],
    placeIds: ['pl-cadlete'],
    groupIds: ['g-amd', 'g-guj-players'],
    mutualConnections: 6,
  ),
  CommunityMember(
    id: 'cm-kavya',
    name: 'Kavya Mehta',
    city: 'Ahmedabad',
    state: _gj,
    headline: 'Mixed doubles player. Coaching beginners at Smash Academy.',
    playerId: 'SKX-10388',
    level: 'Advanced',
    tags: ['Mixed', 'Competitive', 'Beginners'],
    languages: ['English', 'Gujarati'],
    availability: Availability.limited,
    roles: [
      RoleRecord(CommunityRole.player, since: 2021, metrics: [('SkorX Points', '1394'), ('Matches', '118'), ('Win rate', '76%')]),
      RoleRecord(CommunityRole.coach, since: 2024, metrics: [('Students coached', '24'), ('Programs', '1')]),
    ],
    placeIds: ['pl-smashacad'],
    groupIds: ['g-amd', 'g-women'],
    mutualConnections: 4,
  ),
  CommunityMember(
    id: 'cm-diya',
    name: 'Diya Joshi',
    city: 'Ahmedabad',
    state: _gj,
    headline: 'Singles specialist. Looking for hitting partners.',
    playerId: 'SKX-10412',
    level: 'Advanced',
    tags: ['Singles', 'Competitive'],
    languages: ['English', 'Hindi'],
    roles: [
      RoleRecord(CommunityRole.player, since: 2023, metrics: [('SkorX Points', '1368'), ('Matches', '96'), ('Win rate', '74%')]),
    ],
    groupIds: ['g-amd', 'g-women'],
    mutualConnections: 2,
  ),
  CommunityMember(
    id: 'cm-meera',
    name: 'Meera Iyer',
    city: 'Ahmedabad',
    state: _gj,
    headline: 'Weekend doubles and courtside photos.',
    playerId: 'SKX-10477',
    level: 'Intermediate',
    tags: ['Doubles', 'Recreational'],
    languages: ['English', 'Hindi'],
    availability: Availability.open,
    roles: [
      RoleRecord(CommunityRole.player, since: 2023, metrics: [('SkorX Points', '1342'), ('Matches', '88'), ('Win rate', '72%')]),
      RoleRecord(CommunityRole.photographer, since: 2024, metrics: [('Events shot', '7')], highlights: ['Ahmedabad Pickle League 2025 gallery']),
    ],
    groupIds: ['g-amd'],
    mutualConnections: 3,
  ),
  CommunityMember(
    id: 'cm-nisha',
    name: 'Nisha Kapoor',
    city: 'Ahmedabad',
    state: _gj,
    headline: 'New to pickleball. Looking for friendly doubles.',
    playerId: 'SKX-10702',
    level: 'Beginner',
    tags: ['Doubles', 'Recreational'],
    languages: ['English', 'Hindi'],
    roles: [RoleRecord(CommunityRole.player, since: 2026, metrics: [('Matches', '3')])],
    groupIds: ['g-amd'],
    mutualConnections: 1,
  ),
  CommunityMember(
    id: 'cm-parth',
    name: 'Parth Bhatt',
    city: 'Gandhinagar',
    state: _gj,
    headline: 'Under-16. Training for the Gujarat Juniors Cup.',
    playerId: 'SKX-10718',
    level: 'Beginner',
    tags: ['Junior', 'Doubles'],
    languages: ['Gujarati', 'English'],
    roles: [RoleRecord(CommunityRole.player, since: 2025, metrics: [('Matches', '14'), ('Win rate', '43%')])],
    groupIds: ['g-juniors'],
  ),
  CommunityMember(
    id: 'cm-ishaan',
    name: 'Ishaan Patel',
    city: 'Surat',
    state: _gj,
    headline: 'Surat singles champion 2025.',
    playerId: 'SKX-10233',
    level: 'Advanced',
    tags: ['Singles', 'Competitive'],
    languages: ['Gujarati', 'English'],
    roles: [
      RoleRecord(CommunityRole.player, since: 2021, metrics: [('SkorX Points', '1407'), ('Matches', '130'), ('Win rate', '77%')]),
    ],
    groupIds: ['g-guj-players'],
    mutualConnections: 1,
  ),
  CommunityMember(
    id: 'cm-zoya',
    name: 'Zoya Qureshi',
    city: 'Surat',
    state: _gj,
    playerId: 'SKX-10731',
    level: 'Beginner',
    tags: ['Mixed', 'Recreational'],
    languages: ['Hindi', 'English'],
    roles: [RoleRecord(CommunityRole.player, since: 2025, metrics: [('Matches', '19')])],
    groupIds: ['g-women'],
  ),
  CommunityMember(
    id: 'cm-vikram',
    name: 'Vikram Singh',
    city: 'Mumbai',
    state: _mh,
    headline: 'Pro singles. Coaching advanced players in Mumbai.',
    playerId: 'SKX-10009',
    level: 'Pro',
    tags: ['Singles', 'Competitive', 'Advanced'],
    languages: ['English', 'Hindi'],
    availability: Availability.limited,
    roles: [
      RoleRecord(CommunityRole.player, verified: true, since: 2019, metrics: [('SkorX Points', '1612'), ('Matches', '310'), ('Win rate', '84%')]),
      RoleRecord(CommunityRole.coach, verified: true, since: 2022, metrics: [('Students coached', '65'), ('Programs', '2')],
          highlights: ['Level 2 certified coach']),
    ],
    placeIds: ['pl-bandra'],
  ),
  CommunityMember(
    id: 'cm-tara',
    name: 'Tara Menon',
    city: 'Mumbai',
    state: _mh,
    headline: 'Pro mixed doubles and the voice of Mumbai Masters.',
    playerId: 'SKX-10014',
    level: 'Pro',
    tags: ['Mixed', 'Competitive'],
    languages: ['English', 'Hindi', 'Marathi'],
    availability: Availability.open,
    roles: [
      RoleRecord(CommunityRole.player, verified: true, since: 2019, metrics: [('SkorX Points', '1588'), ('Matches', '276'), ('Win rate', '82%')]),
      RoleRecord(CommunityRole.commentator, since: 2024, metrics: [('Events covered', '6')], highlights: ['Mumbai Pickleball Masters 2025, finals']),
    ],
    groupIds: ['g-women'],
  ),

  // Officials.
  CommunityMember(
    id: 'cm-rohan',
    name: 'Rohan Desai',
    city: 'Vadodara',
    state: _gj,
    headline: 'Level 2 referee. Travels across Gujarat for events.',
    playerId: 'SKX-10291',
    level: 'Advanced',
    languages: ['English', 'Hindi', 'Gujarati'],
    serviceArea: ['Vadodara', 'Ahmedabad', 'Surat'],
    availability: Availability.open,
    roles: [
      RoleRecord(
        CommunityRole.referee,
        verified: true,
        since: 2021,
        metrics: [('Matches officiated', '312'), ('Tournaments', '18'), ('Organiser feedback', '96% positive'), ('No-shows', '0')],
        highlights: ['Head referee, Surat Smash Championship 2025', 'Referee, SkorX Open 2025'],
      ),
      RoleRecord(CommunityRole.player, since: 2020, metrics: [('SkorX Points', '1381'), ('Matches', '104')]),
    ],
    groupIds: ['g-guj-refs', 'g-refs-india'],
    mutualConnections: 1,
  ),
  CommunityMember(
    id: 'cm-hetal',
    name: 'Hetal Parikh',
    city: 'Ahmedabad',
    state: _gj,
    headline: 'Referee-in-chief for Gujarat events since 2019.',
    languages: ['Gujarati', 'Hindi', 'English'],
    serviceArea: ['Ahmedabad', 'Gandhinagar'],
    availability: Availability.limited,
    acceptsMessagesFrom: MessagePermission.connections,
    roles: [
      RoleRecord(
        CommunityRole.referee,
        verified: true,
        since: 2019,
        metrics: [('Matches officiated', '468'), ('Tournaments', '27'), ('Organiser feedback', '98% positive'), ('No-shows', '0')],
        highlights: ['Referee-in-chief, Ahmedabad Pickle League', 'Trains new referees for SkorX'],
      ),
      RoleRecord(CommunityRole.official, verified: true, since: 2021, metrics: [('Events as tournament director', '6')]),
    ],
    groupIds: ['g-guj-refs', 'g-refs-india', 'g-women'],
    mutualConnections: 2,
  ),
  CommunityMember(
    id: 'cm-sameer',
    name: 'Sameer Qureshi',
    city: 'Ahmedabad',
    state: _gj,
    headline: 'Scorekeeper on SkorX courts. Fast, accurate, on time.',
    languages: ['Hindi', 'English', 'Gujarati'],
    serviceArea: ['Ahmedabad', 'Gandhinagar', 'Vadodara'],
    availability: Availability.open,
    roles: [
      RoleRecord(
        CommunityRole.scorekeeper,
        verified: true,
        since: 2022,
        metrics: [('Matches scored', '540'), ('Tournaments', '22'), ('Score corrections', '0.4%'), ('On time', '100%')],
        highlights: ['Centre court scorer, SkorX Open 2025'],
      ),
    ],
    groupIds: ['g-guj-refs', 'g-scorers'],
    mutualConnections: 2,
  ),
  CommunityMember(
    id: 'cm-pooja',
    name: 'Pooja Rana',
    city: 'Gandhinagar',
    state: _gj,
    headline: 'New scorekeeper, available weekends.',
    languages: ['Gujarati', 'English'],
    serviceArea: ['Gandhinagar', 'Ahmedabad'],
    availability: Availability.open,
    roles: [
      RoleRecord(CommunityRole.scorekeeper, since: 2025, metrics: [('Matches scored', '64'), ('Tournaments', '3')]),
      RoleRecord(CommunityRole.player, since: 2024),
    ],
    groupIds: ['g-scorers'],
  ),
  CommunityMember(
    id: 'cm-imran',
    name: 'Imran Sheikh',
    city: 'Surat',
    state: _gj,
    headline: 'Referee in Surat.',
    languages: ['Hindi', 'Gujarati'],
    serviceArea: ['Surat'],
    availability: Availability.busy,
    roles: [RoleRecord(CommunityRole.referee, since: 2023, metrics: [('Matches officiated', '96'), ('Tournaments', '6')])],
    groupIds: ['g-guj-refs'],
  ),
  CommunityMember(
    id: 'cm-anjali',
    name: 'Anjali Deshmukh',
    city: 'Pune',
    state: _mh,
    headline: 'Tournament official and referee trainer.',
    languages: ['Marathi', 'Hindi', 'English'],
    serviceArea: ['Pune', 'Mumbai'],
    availability: Availability.open,
    roles: [
      RoleRecord(CommunityRole.official, verified: true, since: 2020, metrics: [('Events as tournament director', '11')]),
      RoleRecord(CommunityRole.referee, verified: true, since: 2020, metrics: [('Matches officiated', '380'), ('Tournaments', '21')]),
    ],
    groupIds: ['g-refs-india'],
  ),

  // Organisers.
  CommunityMember(
    id: 'cm-nikhil',
    name: 'Nikhil Agarwal',
    city: 'Ahmedabad',
    state: _gj,
    headline: 'Runs the Ahmedabad Pickle League and CADLETE Monsoon Cup.',
    languages: ['English', 'Hindi', 'Gujarati'],
    availability: Availability.open,
    roles: [
      RoleRecord(
        CommunityRole.organizer,
        verified: true,
        since: 2022,
        metrics: [('Events completed', '9'), ('Players hosted', '1,240'), ('Players who came back', '61%')],
        highlights: ['Ahmedabad Pickle League', 'CADLETE Monsoon Cup'],
      ),
      RoleRecord(CommunityRole.player, since: 2021),
    ],
    placeIds: ['pl-cadlete'],
    groupIds: ['g-amd', 'g-organisers'],
    mutualConnections: 5,
  ),
  CommunityMember(
    id: 'cm-rhea',
    name: 'Rhea Kothari',
    city: 'Surat',
    state: _gj,
    headline: 'Surat Smash Championship. Corporate leagues on request.',
    languages: ['English', 'Gujarati'],
    availability: Availability.limited,
    roles: [
      RoleRecord(CommunityRole.organizer, verified: true, since: 2023, metrics: [('Events completed', '5'), ('Players hosted', '610')],
          highlights: ['Surat Smash Championship']),
      RoleRecord(CommunityRole.eventManager, since: 2023, metrics: [('Corporate events', '4')]),
    ],
    placeIds: ['pl-surat-club'],
    groupIds: ['g-organisers'],
  ),
  CommunityMember(
    id: 'cm-farhan',
    name: 'Farhan Ali',
    city: 'Mumbai',
    state: _mh,
    headline: 'Corporate pickleball days and leagues.',
    languages: ['English', 'Hindi'],
    serviceArea: ['Mumbai', 'Pune'],
    availability: Availability.open,
    roles: [RoleRecord(CommunityRole.eventManager, since: 2024, metrics: [('Corporate events', '7'), ('Players hosted', '420')])],
    groupIds: ['g-organisers'],
  ),

  // Coaches.
  CommunityMember(
    id: 'cm-sunil',
    name: 'Sunil Nair',
    city: 'Ahmedabad',
    state: _gj,
    headline: 'Head coach, Smash Pickleball Academy. Beginners to tournament play.',
    languages: ['English', 'Hindi'],
    tags: ['Beginners', 'Intermediate', 'Juniors'],
    availability: Availability.limited,
    roles: [
      RoleRecord(
        CommunityRole.coach,
        verified: true,
        since: 2020,
        metrics: [('Students coached', '180'), ('Programs', '4'), ('Juniors to tournaments', '14')],
        highlights: ['Level 2 certified coach', 'Coach, Gujarat juniors squad 2025'],
      ),
    ],
    placeIds: ['pl-smashacad'],
    groupIds: ['g-coaches', 'g-amd'],
    mutualConnections: 3,
  ),
  CommunityMember(
    id: 'cm-kiran',
    name: 'Kiran Bhatt',
    city: 'Vadodara',
    state: _gj,
    headline: 'Beginner clinics every weekend.',
    languages: ['Gujarati', 'Hindi'],
    tags: ['Beginners'],
    availability: Availability.open,
    roles: [RoleRecord(CommunityRole.coach, since: 2024, metrics: [('Students coached', '35'), ('Programs', '1')])],
    placeIds: ['pl-baroda-acad'],
    groupIds: ['g-coaches'],
  ),
  CommunityMember(
    id: 'cm-deepa',
    name: 'Deepa Pillai',
    city: 'Bengaluru',
    state: 'Karnataka',
    headline: 'Strength and movement for racket sports.',
    languages: ['English', 'Kannada'],
    tags: ['Advanced'],
    availability: Availability.open,
    roles: [
      RoleRecord(CommunityRole.trainer, since: 2021, metrics: [('Athletes trained', '90')]),
      RoleRecord(CommunityRole.coach, since: 2023, metrics: [('Students coached', '40')]),
    ],
    groupIds: ['g-coaches'],
  ),

  // Media.
  CommunityMember(
    id: 'cm-aditya',
    name: 'Aditya Rao',
    city: 'Ahmedabad',
    state: _gj,
    headline: 'Live streams with SkorX scores on screen.',
    languages: ['English', 'Hindi'],
    serviceArea: ['Ahmedabad', 'Vadodara', 'Surat', 'Mumbai'],
    availability: Availability.open,
    roles: [
      RoleRecord(
        CommunityRole.streamer,
        verified: true,
        since: 2023,
        metrics: [('Events streamed', '14'), ('Hours live', '160'), ('Setup', '3 cameras · score overlay')],
        highlights: ['SkorX Open 2025 on YouTube', 'Ahmedabad Pickle League finals'],
      ),
    ],
    groupIds: ['g-streamers'],
    mutualConnections: 2,
  ),
  CommunityMember(
    id: 'cm-mihir',
    name: 'Mihir Shah',
    city: 'Ahmedabad',
    state: _gj,
    headline: 'Commentary in Gujarati, Hindi and English.',
    languages: ['Gujarati', 'Hindi', 'English'],
    availability: Availability.open,
    roles: [RoleRecord(CommunityRole.commentator, since: 2024, metrics: [('Events covered', '8')])],
    groupIds: ['g-streamers'],
    mutualConnections: 1,
  ),
  CommunityMember(
    id: 'cm-sneha',
    name: 'Sneha Jain',
    city: 'Mumbai',
    state: _mh,
    headline: 'Pickleball tips and tournament vlogs.',
    languages: ['English', 'Hindi'],
    roles: [RoleRecord(CommunityRole.creator, since: 2024, metrics: [('Videos', '120'), ('Tournaments covered', '6')])],
    groupIds: ['g-streamers', 'g-women'],
  ),
];

const samplePlaces = <CommunityPlace>[
  CommunityPlace(
    id: 'pl-cadlete',
    kind: PlaceKind.club,
    name: 'CADLETE Club',
    city: 'Ahmedabad',
    state: _gj,
    area: 'Bodakdev',
    about: 'A members club with five indoor courts, club nights every Thursday and two tournaments a year.',
    verified: true,
    venueId: 'v-cadlete',
    organizationId: 'org-cadlete',
    courts: 5,
    setting: PlaceSetting.indoor,
    surface: 'Acrylic hard court',
    amenities: ['Parking', 'Changing rooms', 'Showers', 'Coaching', 'Café', 'AC'],
    hours: '6 AM – 10 PM, every day',
    programs: [
      Program(name: 'Club nights', level: 'All levels', schedule: 'Thursdays, 7–10 PM'),
      Program(name: 'Ladder league', level: 'Intermediate', schedule: 'Monthly, Saturdays'),
    ],
    staffIds: ['cm-nikhil', 'cm-sunil'],
    tournamentIds: ['t-monsoon', 't-league'],
    members: 240,
    followers: 1840,
    founded: 2022,
  ),
  CommunityPlace(
    id: 'pl-surat-club',
    kind: PlaceKind.club,
    name: 'Surat Pickleball Club',
    city: 'Surat',
    state: _gj,
    area: 'Vesu',
    about: 'Surat\'s first pickleball club. We play at Diamond Sports Hub and host the Surat Smash Championship.',
    verified: true,
    venueId: 'v-diamond',
    courts: 6,
    setting: PlaceSetting.indoor,
    hours: '6 AM – 11 PM',
    programs: [Program(name: 'Social doubles', level: 'All levels', schedule: 'Tue & Fri, 7 PM')],
    staffIds: ['cm-rhea'],
    tournamentIds: ['t-surat', 't-spt-surat'],
    members: 120,
    followers: 640,
    founded: 2023,
  ),
  CommunityPlace(
    id: 'pl-bandra',
    kind: PlaceKind.club,
    name: 'Bandra Pickleball Club',
    city: 'Mumbai',
    state: _mh,
    area: 'Bandra West',
    about: 'Sea-facing outdoor courts and a friendly Sunday social.',
    courts: 3,
    setting: PlaceSetting.outdoor,
    hours: '6 – 10 AM, 5 – 10 PM',
    amenities: ['Floodlights', 'Drinking water'],
    programs: [Program(name: 'Sunday social', level: 'All levels', schedule: 'Sundays, 7 AM')],
    staffIds: ['cm-vikram'],
    tournamentIds: ['t-mumbai'],
    members: 95,
    followers: 410,
  ),
  CommunityPlace(
    id: 'pl-smashacad',
    kind: PlaceKind.academy,
    name: 'Smash Pickleball Academy',
    city: 'Ahmedabad',
    state: _gj,
    area: 'SG Highway',
    about: 'Structured coaching from your first rally to tournament play. Trains at Smash Arena.',
    verified: true,
    venueId: 'v-smash',
    courts: 8,
    setting: PlaceSetting.indoor,
    hours: 'Classes 6–9 AM and 5–9 PM',
    programs: [
      Program(name: 'Start pickleball', level: 'Beginner', schedule: 'Mon, Wed, Fri · 7 AM', fee: 2500),
      Program(name: 'Build your game', level: 'Intermediate', schedule: 'Tue, Thu · 6 PM', fee: 3200),
      Program(name: 'Tournament prep', level: 'Advanced', schedule: 'Sat · 7 AM', fee: 3800),
      Program(name: 'Junior squad', level: 'Beginner', schedule: 'Sat, Sun · 5 PM', fee: 2800, juniors: true),
    ],
    staffIds: ['cm-sunil', 'cm-kavya'],
    tournamentIds: ['t-juniors'],
    members: 160,
    followers: 920,
    founded: 2023,
  ),
  CommunityPlace(
    id: 'pl-baroda-acad',
    kind: PlaceKind.academy,
    name: 'Baroda Pickleball Academy',
    city: 'Vadodara',
    state: _gj,
    area: 'Alkapuri',
    about: 'Weekend beginner clinics and a junior programme.',
    courts: 3,
    setting: PlaceSetting.outdoor,
    hours: 'Weekends, 6–10 AM',
    programs: [
      Program(name: 'Weekend clinic', level: 'Beginner', schedule: 'Sat, Sun · 7 AM', fee: 1800),
      Program(name: 'Juniors', level: 'Beginner', schedule: 'Sun · 9 AM', fee: 1500, juniors: true),
    ],
    staffIds: ['cm-kiran'],
    members: 48,
    followers: 150,
  ),
  CommunityPlace(
    id: 'pl-blitz',
    kind: PlaceKind.venue,
    name: 'Pickle Blitz Arena',
    city: 'Ahmedabad',
    state: _gj,
    area: 'Prahlad Nagar',
    about: 'Six air-conditioned courts, open late, home of the Night Series.',
    verified: true,
    venueId: 'v-blitz',
    courts: 6,
    setting: PlaceSetting.indoor,
    tournamentIds: ['t-blitz', 't-open'],
    followers: 1320,
  ),
  CommunityPlace(
    id: 'pl-smash',
    kind: PlaceKind.venue,
    name: 'Smash Arena',
    city: 'Ahmedabad',
    state: _gj,
    area: 'SG Highway',
    about: 'Eight indoor courts with a pro shop and coaching.',
    venueId: 'v-smash',
    courts: 8,
    setting: PlaceSetting.indoor,
    tournamentIds: ['t-spt-amd'],
    followers: 860,
  ),
  CommunityPlace(
    id: 'pl-riverside',
    kind: PlaceKind.venue,
    name: 'Riverside Courts',
    city: 'Ahmedabad',
    state: _gj,
    area: 'Riverfront',
    about: 'Outdoor courts on the Sabarmati riverfront. Open play on Sunday mornings.',
    venueId: 'v-riverside',
    courts: 4,
    setting: PlaceSetting.outdoor,
    followers: 530,
  ),
  CommunityPlace(
    id: 'pl-diamond',
    kind: PlaceKind.venue,
    name: 'Diamond Sports Hub',
    city: 'Surat',
    state: _gj,
    area: 'Vesu',
    about: 'Multi-sport complex with six indoor pickleball courts.',
    venueId: 'v-diamond',
    courts: 6,
    setting: PlaceSetting.indoor,
    tournamentIds: ['t-surat'],
    followers: 480,
  ),
  CommunityPlace(
    id: 'pl-kitchenline',
    kind: PlaceKind.business,
    name: 'Kitchen Line Gear',
    city: 'Mumbai',
    state: _mh,
    about: 'Paddles, balls and nets, shipped across India. Sponsors local tournaments.',
    followers: 2100,
    founded: 2024,
  ),
];

const sampleGroups = <CommunityGroup>[
  CommunityGroup(
    id: 'g-amd',
    name: 'Ahmedabad Pickleball',
    about: 'Everyone who plays in Ahmedabad: open play, partners, courts and news.',
    access: GroupAccess.public,
    members: 1240,
    activeThisWeek: 310,
    city: 'Ahmedabad',
    state: _gj,
    rules: ['Be kind on and off court.', 'No selling outside the Friday thread.'],
  ),
  CommunityGroup(
    id: 'g-organisers',
    name: 'Tournament Organizers India',
    about: 'Dates, venues, officials and lessons learned from running events.',
    access: GroupAccess.private,
    members: 180,
    activeThisWeek: 64,
    focus: CommunityRole.organizer,
  ),
  CommunityGroup(
    id: 'g-guj-refs',
    name: 'Gujarat Referees',
    about: 'Referees and scorekeepers working events in Gujarat. Run by CADLETE Club.',
    access: GroupAccess.verified,
    members: 86,
    activeThisWeek: 41,
    state: _gj,
    focus: CommunityRole.referee,
    managedBy: 'pl-cadlete',
  ),
  CommunityGroup(
    id: 'g-guj-players',
    name: 'Gujarat Pickleball Players',
    about: 'Players across Gujarat: tournaments, travel partners and results.',
    access: GroupAccess.public,
    members: 2150,
    activeThisWeek: 290,
    state: _gj,
  ),
  CommunityGroup(
    id: 'g-coaches',
    name: 'Pickleball Coaches India',
    about: 'Drills, programmes and coaching jobs.',
    access: GroupAccess.private,
    members: 140,
    activeThisWeek: 52,
    focus: CommunityRole.coach,
  ),
  CommunityGroup(
    id: 'g-women',
    name: 'Women in Pickleball',
    about: 'A welcoming space to find partners, clinics and events.',
    access: GroupAccess.public,
    members: 860,
    activeThisWeek: 190,
  ),
  CommunityGroup(
    id: 'g-juniors',
    name: 'Junior Pickleball Gujarat',
    about: 'For junior players and their parents: camps, squads and junior events.',
    access: GroupAccess.private,
    members: 210,
    activeThisWeek: 38,
    state: _gj,
  ),
  CommunityGroup(
    id: 'g-streamers',
    name: 'Pickleball Streamers',
    about: 'Cameras, overlays and commentary for pickleball events.',
    access: GroupAccess.public,
    members: 74,
    activeThisWeek: 29,
    focus: CommunityRole.streamer,
  ),
  CommunityGroup(
    id: 'g-scorers',
    name: 'Pickleball Scorekeepers',
    about: 'Scoring on SkorX, event rosters and shift swaps.',
    access: GroupAccess.public,
    members: 120,
    activeThisWeek: 22,
    focus: CommunityRole.scorekeeper,
  ),
  CommunityGroup(
    id: 'g-refs-india',
    name: 'Pickleball Referees India',
    about: 'Rules questions, certification and event calls for referees.',
    access: GroupAccess.verified,
    members: 320,
    activeThisWeek: 71,
    focus: CommunityRole.referee,
    managedBy: 'pl-cadlete',
  ),
];

/// A private crew the sample player runs, with join requests waiting.
const sampleAdminGroup = CommunityGroup(
  id: 'g-bodakdev',
  name: 'Bodakdev Morning Crew',
  about: 'Doubles at 6 AM, four days a week. Ask to join and say your level.',
  access: GroupAccess.private,
  members: 14,
  activeThisWeek: 9,
  city: 'Ahmedabad',
  state: _gj,
  rules: ['Be on court by 6.', 'Rotate partners every game.'],
);

DateTime _at(DateTime now, int days, int hour, [int minute = 0]) => DateTime(now.year, now.month, now.day + days, hour, minute);

/// Clinics, open play and meetups around the sample player, at sample places.
List<CommunityEvent> sampleEvents(DateTime now) => [
      CommunityEvent(
        id: 'ev-clinic',
        kind: EventKind.clinic,
        title: 'Beginner clinic: dinks and resets',
        about: 'Two hours on the soft game with Coach Sunil. Paddles provided.',
        startsAt: _at(now, 2, 7),
        endsAt: _at(now, 2, 9),
        city: 'Ahmedabad',
        placeId: 'pl-smashacad',
        placeName: 'Smash Pickleball Academy',
        organizerId: 'cm-sunil',
        organizerName: 'Sunil Nair',
        capacity: 12,
        feeInr: 500,
        level: 'Beginner',
        going: 9,
        interested: 4,
      ),
      CommunityEvent(
        id: 'ev-openplay',
        kind: EventKind.openPlay,
        title: 'Sunday open play at the riverfront',
        about: 'All levels. Paddles up, rotate every game. Bring water.',
        startsAt: _at(now, (DateTime.sunday - now.weekday) % 7 == 0 ? 7 : (DateTime.sunday - now.weekday) % 7, 6),
        endsAt: _at(now, (DateTime.sunday - now.weekday) % 7 == 0 ? 7 : (DateTime.sunday - now.weekday) % 7, 9),
        city: 'Ahmedabad',
        placeId: 'pl-riverside',
        placeName: 'Riverside Courts',
        groupId: 'g-amd',
        organizerId: 'cm-nikhil',
        organizerName: 'Nikhil Agarwal',
        going: 22,
        interested: 11,
      ),
      CommunityEvent(
        id: 'ev-women',
        kind: EventKind.meetup,
        title: "Women's doubles meetup",
        about: 'Friendly games and new partners. Every level welcome.',
        startsAt: _at(now, 4, 18),
        endsAt: _at(now, 4, 20),
        city: 'Ahmedabad',
        placeId: 'pl-blitz',
        placeName: 'Pickle Blitz Arena',
        groupId: 'g-women',
        organizerId: 'cm-kavya',
        organizerName: 'Kavya Mehta',
        capacity: 16,
        going: 16,
        interested: 5,
      ),
      CommunityEvent(
        id: 'ev-refs',
        kind: EventKind.workshop,
        title: 'Referee workshop: faults and line calls',
        about: 'For new and working referees before the monsoon season. Certificates for attendees.',
        startsAt: _at(now, 6, 10),
        endsAt: _at(now, 6, 13),
        city: 'Ahmedabad',
        placeId: 'pl-cadlete',
        placeName: 'CADLETE Club',
        groupId: 'g-guj-refs',
        tournamentId: 't-monsoon',
        organizerId: 'cm-hetal',
        organizerName: 'Hetal Parikh',
        capacity: 30,
        going: 18,
        interested: 7,
      ),
      CommunityEvent(
        id: 'ev-surat',
        kind: EventKind.social,
        title: 'Surat social doubles night',
        about: 'Games, music and chai after work.',
        startsAt: _at(now, 5, 19),
        endsAt: _at(now, 5, 22),
        city: 'Surat',
        placeId: 'pl-diamond',
        placeName: 'Diamond Sports Hub',
        organizerId: 'cm-rhea',
        organizerName: 'Rhea Kothari',
        going: 28,
      ),
    ];

/// What the sample player's network posted: pickleball, and useful.
List<CommunityPost> samplePosts(DateTime now) => [
      CommunityPost(
        id: 'ps-monsoon',
        kind: PostKind.announcement,
        body: 'Entries for the CADLETE Monsoon Cup close Friday. Doubles and mixed, all levels. See you on court!',
        link: '/player/tournament/t-monsoon',
        authorId: 'cm-nikhil',
        authorName: 'Nikhil Agarwal',
        likes: 42,
        comments: 6,
        at: now.subtract(const Duration(hours: 3)),
      ),
      CommunityPost(
        id: 'ps-tip',
        kind: PostKind.tip,
        body: 'Drill of the week: 10 minutes of cross-court dinks, then 10 of resets from the transition zone. Your third shot will thank you.',
        authorId: 'cm-kavya',
        authorName: 'Kavya Mehta',
        likes: 31,
        comments: 4,
        at: now.subtract(const Duration(hours: 9)),
      ),
      CommunityPost(
        id: 'ps-club',
        kind: PostKind.announcement,
        body: 'Club night this Thursday moves to 7:30 PM. Courts 3 to 5 are for beginners.',
        authorId: 'cm-nikhil',
        authorName: 'Nikhil Agarwal',
        placeId: 'pl-cadlete',
        placeName: 'CADLETE Club',
        likes: 18,
        at: now.subtract(const Duration(days: 1)),
      ),
      CommunityPost(
        id: 'ps-win',
        kind: PostKind.achievement,
        body: 'Finally won the Ahmedabad Pickle League pool with @Kavya. 3–0 in games. Semis next week!',
        link: '/player/tournament/t-league',
        authorId: 'cm-aarav',
        authorName: 'Aarav Shah',
        likes: 57,
        comments: 12,
        at: now.subtract(const Duration(days: 1, hours: 6)),
      ),
      CommunityPost(
        id: 'ps-amd',
        kind: PostKind.event,
        body: 'Open play at Riverside this Sunday, 6 AM. We had 20 people last week. Beginners very welcome.',
        authorId: 'cm-nikhil',
        authorName: 'Nikhil Agarwal',
        groupId: 'g-amd',
        groupName: 'Ahmedabad Pickleball',
        eventId: 'ev-openplay',
        eventTitle: 'Sunday open play at the riverfront',
        likes: 24,
        comments: 3,
        at: now.subtract(const Duration(days: 2)),
      ),
      CommunityPost(
        id: 'ps-refs',
        kind: PostKind.news,
        body: 'New SkorX referee course for Gujarat starts next month. Workshop details in the events tab.',
        authorId: 'cm-hetal',
        authorName: 'Hetal Parikh',
        groupId: 'g-guj-refs',
        groupName: 'Gujarat Referees',
        likes: 15,
        at: now.subtract(const Duration(days: 3)),
      ),
    ];
