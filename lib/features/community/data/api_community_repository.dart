import '../../../core/api/api_client.dart';
import 'community.dart';
import 'community_json.dart';
import 'community_query.dart';
import 'community_repository.dart';
import 'content.dart';
import 'messages.dart';

/// Community on the SkorX API (backend src/community). Errors arrive as
/// `ApiException` with the server's code (BLOCKED, MESSAGES_RESTRICTED,
/// AWAITING_REPLY, RATE_LIMITED…) and a message written for players.
class ApiCommunityRepository implements CommunityRepository {
  const ApiCommunityRepository(this._api);

  final ApiClient _api;

  List<T> _list<T>(Object? data, T Function(Json) read) => [for (final x in (data as List<dynamic>)) read(x as Json)];

  // ─── Directory ──────────────────────────────────────────────────────────

  @override
  Future<List<CommunityMember>> members(CommunityQuery query) async {
    final (data, _) = await _api.getPage<List<dynamic>>('/community/members', query: query.toParams());
    return _list(data, memberFromJson);
  }

  @override
  Future<CommunityMember> member(String id) async => memberFromJson(await _api.get<Json>('/community/members/$id'));

  @override
  Future<List<CommunityPlace>> places(CommunityQuery query) async {
    final (data, _) = await _api.getPage<List<dynamic>>('/community/places', query: query.toParams());
    return _list(data, placeFromJson);
  }

  @override
  Future<CommunityPlace> place(String id) async => placeFromJson(await _api.get<Json>('/community/places/$id'));

  @override
  Future<List<CommunityGroup>> groups({String? city, String query = ''}) async => _list(
        await _api.get<List<dynamic>>('/community/groups', query: {'city': ?city, if (query.isNotEmpty) 'q': query}),
        groupFromJson,
      );

  @override
  Future<CommunityGroup> group(String id) async => groupFromJson(await _api.get<Json>('/community/groups/$id'));

  /// The server knows my roles; only the place is sent.
  @override
  Future<List<Suggestion>> suggestions({String? city, Set<CommunityRole> forRoles = const {}}) async =>
      _list(await _api.get<List<dynamic>>('/community/suggestions', query: {'city': ?city}), suggestionFromJson);

  // ─── Me ─────────────────────────────────────────────────────────────────

  @override
  Future<CommunityGraph> graph() async => graphFromJson(await _api.get<Json>('/me/community'));

  @override
  Future<MyCommunityProfile> myProfile() async => profileFromJson(await _api.get<Json>('/me/community-profile'));

  @override
  Future<MyCommunityProfile> saveProfile(MyCommunityProfile profile) async =>
      profileFromJson(await _api.put<Json>('/me/community-profile', body: profileToJson(profile)));

  // ─── Ties ───────────────────────────────────────────────────────────────

  @override
  Future<ConnectionStatus> connect(String memberId) async {
    final data = await _api.post<Json>('/community/connections', body: {'memberId': memberId});
    return ConnectionStatus.values.where((s) => s.name == data['status']).firstOrNull ?? ConnectionStatus.pendingOut;
  }

  @override
  Future<void> disconnect(String memberId) => _api.delete<Object?>('/community/connections/$memberId');

  @override
  Future<void> follow(String targetId, {required bool on, CommunityTarget type = CommunityTarget.member}) {
    final path = '/community/follows/${type.name}/$targetId';
    return on ? _api.put<Object?>(path) : _api.delete<Object?>(path);
  }

  @override
  Future<GroupStatus> joinGroup(String groupId) async {
    final data = await _api.post<Json>('/community/groups/$groupId/join');
    return data['status'] == 'member' ? GroupStatus.member : GroupStatus.requested;
  }

  @override
  Future<void> leaveGroup(String groupId) => _api.delete<Object?>('/community/groups/$groupId/membership');

  @override
  Future<CommunityGroup> createGroup({required String name, required String about, required GroupAccess access, String? city}) async =>
      groupFromJson(await _api.post<Json>('/community/groups', body: {'name': name, 'about': about, 'access': access.name, 'city': ?city}));

  @override
  Future<List<CommunityMember>> groupRequests(String groupId) async =>
      _list(await _api.get<List<dynamic>>('/community/groups/$groupId/requests'), memberFromJson);

  @override
  Future<void> decideGroupRequest(String groupId, String memberId, {required bool approve}) =>
      _api.post<Object?>('/community/groups/$groupId/requests/$memberId/${approve ? 'approve' : 'decline'}');

  @override
  Future<void> save(String targetId, {required bool on, required CommunityTarget type}) {
    final path = '/me/saved/${type.name}/$targetId';
    return on ? _api.put<Object?>(path) : _api.delete<Object?>(path);
  }

  @override
  Future<void> block(String memberId, {required bool on}) =>
      on ? _api.post<Object?>('/community/blocks/$memberId') : _api.delete<Object?>('/community/blocks/$memberId');

  @override
  Future<void> report(ReportTarget target, String targetId, ReportReason reason, {String? note}) => _api.post<Object?>(
        '/community/reports',
        body: {'target': target.name, 'targetId': targetId, 'reason': reason.name, 'note': ?note},
      );

  // ─── Reputation and verification ────────────────────────────────────────

  @override
  Future<void> feedback({required String memberId, required CommunityRole role, required bool recommend, bool? onTime, String? note}) =>
      _api.post<Object?>('/community/feedback', body: {
        'memberId': memberId,
        'role': role.name,
        'recommend': recommend,
        'onTime': ?onTime,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      });

  @override
  Future<List<VerificationRequest>> myVerifications() async =>
      _list(await _api.get<List<dynamic>>('/me/community/verifications'), verificationFromJson);

  @override
  Future<VerificationRequest> requestVerification({required CommunityRole role, required String evidence, List<String> links = const []}) async =>
      verificationFromJson(await _api.post<Json>('/me/community/verifications', body: {'role': role.name, 'evidence': evidence, 'links': links}));

  // ─── Events ─────────────────────────────────────────────────────────────

  @override
  Future<List<CommunityEvent>> events({String? city, String? groupId, String? placeId}) async => _list(
        await _api.get<List<dynamic>>('/community/events', query: {'city': ?city, 'groupId': ?groupId, 'placeId': ?placeId}),
        eventFromJson,
      );

  @override
  Future<CommunityEvent> event(String id) async => eventFromJson(await _api.get<Json>('/community/events/$id'));

  @override
  Future<CommunityEvent> createEvent(EventDraft draft) async => eventFromJson(await _api.post<Json>('/community/events', body: draft.toJson()));

  @override
  Future<CommunityEvent> rsvp(String eventId, RsvpStatus? status) async =>
      eventFromJson(await _api.post<Json>('/community/events/$eventId/rsvp', body: {'status': status?.name ?? 'none'}));

  @override
  Future<void> cancelEvent(String eventId) => _api.post<Object?>('/community/events/$eventId/cancel');

  // ─── Posts ──────────────────────────────────────────────────────────────

  @override
  Future<PostPage> feed(FeedScope scope, {String? cursor}) async {
    final (data, meta) = await _api.getPage<List<dynamic>>('/community/posts', query: {...scope.toParams(), 'before': ?cursor});
    return PostPage(_list(data, postFromJson), meta['nextCursor'] as String?);
  }

  @override
  Future<CommunityPost> createPost({required PostKind kind, required String body, String? link, String? groupId, String? eventId}) async =>
      postFromJson(await _api.post<Json>('/community/posts', body: {
        'kind': kind.name,
        'body': body,
        'link': ?link,
        'groupId': ?groupId,
        'eventId': ?eventId,
      }));

  @override
  Future<void> deletePost(String postId) => _api.delete<Object?>('/community/posts/$postId');

  @override
  Future<int> like(String postId, {required bool on}) async {
    final path = '/community/posts/$postId/like';
    final data = on ? await _api.put<Json>(path) : await _api.delete<Json>(path);
    return data['likes'] as int? ?? 0;
  }

  @override
  Future<List<PostComment>> comments(String postId) async =>
      _list(await _api.get<List<dynamic>>('/community/posts/$postId/comments'), commentFromJson);

  @override
  Future<PostComment> comment(String postId, String body) async =>
      commentFromJson(await _api.post<Json>('/community/posts/$postId/comments', body: {'body': body}));

  @override
  Future<void> deleteComment(String commentId) => _api.delete<Object?>('/community/comments/$commentId');

  // ─── Messages ───────────────────────────────────────────────────────────

  @override
  Future<List<Conversation>> conversations() async => _list(await _api.get<List<dynamic>>('/me/conversations'), conversationFromJson);

  @override
  Future<Conversation> openConversation(ConversationKind kind, String targetId) async =>
      conversationFromJson(await _api.post<Json>('/conversations', body: {'kind': kind.name, 'targetId': targetId}));

  @override
  Future<List<ChatMessage>> messages(String conversationId) async =>
      _list(await _api.get<List<dynamic>>('/conversations/$conversationId/messages'), messageFromJson);

  @override
  Future<ChatMessage> send(String conversationId, String text) async =>
      messageFromJson(await _api.post<Json>('/conversations/$conversationId/messages', body: {'text': text}));

  @override
  Future<void> markRead(String conversationId) => _api.post<Object?>('/conversations/$conversationId/read');

  @override
  Future<void> acceptRequest(String conversationId) => _api.post<Object?>('/conversations/$conversationId/accept');

  @override
  Future<void> deleteConversation(String conversationId) => _api.delete<Object?>('/conversations/$conversationId');
}
