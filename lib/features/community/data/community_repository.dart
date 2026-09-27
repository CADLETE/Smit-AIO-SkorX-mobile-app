import '../../../core/api/api_exception.dart';
import 'community.dart';
import 'community_query.dart';
import 'content.dart';
import 'messages.dart';

/// Community data. Method names mirror the NestJS endpoints (backend
/// src/community, docs/COMMUNITY.md §5). Builds that use the real API get
/// [ApiCommunityRepository] (api_community_repository.dart); debug builds
/// otherwise use [SampleCommunityRepository] (sample_community.dart).
abstract class CommunityRepository {
  // ─── Directory ──────────────────────────────────────────────────────────

  /// `GET /community/members?q&sector&roles&city&state&verified&available&language&level&tag`
  /// Blocked members and members who hid themselves are left out by the server.
  Future<List<CommunityMember>> members(CommunityQuery query);

  /// `GET /community/members/:id`
  Future<CommunityMember> member(String id);

  /// `GET /community/places?q&sector&kinds&city&state&verified&setting&level`
  Future<List<CommunityPlace>> places(CommunityQuery query);

  /// `GET /community/places/:id`
  Future<CommunityPlace> place(String id);

  /// `GET /community/groups?city&q`: the city's groups first, then national ones.
  Future<List<CommunityGroup>> groups({String? city, String query = ''});

  /// `GET /community/groups/:id`
  Future<CommunityGroup> group(String id);

  /// `GET /community/suggestions?city`: people you may know, each with why.
  Future<List<Suggestion>> suggestions({String? city, Set<CommunityRole> forRoles = const {}});

  // ─── Me ─────────────────────────────────────────────────────────────────

  /// `GET /me/community`
  Future<CommunityGraph> graph();

  /// `GET /me/community-profile`
  Future<MyCommunityProfile> myProfile();

  /// `PUT /me/community-profile`
  Future<MyCommunityProfile> saveProfile(MyCommunityProfile profile);

  // ─── Ties ───────────────────────────────────────────────────────────────

  /// `POST /community/connections { memberId }`. Returns the new status:
  /// accepting their pending request connects at once.
  Future<ConnectionStatus> connect(String memberId);

  /// `DELETE /community/connections/:memberId`: withdraw, decline or remove.
  Future<void> disconnect(String memberId);

  /// `PUT` / `DELETE /community/follows/:type/:id` (member or place).
  Future<void> follow(String targetId, {required bool on, CommunityTarget type = CommunityTarget.member});

  /// `POST /community/groups/:id/join`: private groups answer `requested`.
  Future<GroupStatus> joinGroup(String groupId);

  /// `DELETE /community/groups/:id/membership`
  Future<void> leaveGroup(String groupId);

  /// `POST /community/groups`
  Future<CommunityGroup> createGroup({required String name, required String about, required GroupAccess access, String? city});

  /// `GET /community/groups/:id/requests` (admins)
  Future<List<CommunityMember>> groupRequests(String groupId);

  /// `POST /community/groups/:id/requests/:userId/approve|decline` (admins)
  Future<void> decideGroupRequest(String groupId, String memberId, {required bool approve});

  /// `PUT` / `DELETE /me/saved/:type/:id`
  Future<void> save(String targetId, {required bool on, required CommunityTarget type});

  /// `POST` / `DELETE /community/blocks/:memberId`. Blocking also removes
  /// any connection and follow both ways.
  Future<void> block(String memberId, {required bool on});

  /// `POST /community/reports { target, targetId, reason, note }`
  Future<void> report(ReportTarget target, String targetId, ReportReason reason, {String? note});

  // ─── Reputation and verification ────────────────────────────────────────

  /// `POST /community/feedback`: organisers only, about someone who worked their event.
  Future<void> feedback({required String memberId, required CommunityRole role, required bool recommend, bool? onTime, String? note});

  /// `GET /me/community/verifications`
  Future<List<VerificationRequest>> myVerifications();

  /// `POST /me/community/verifications`: one role, with evidence for SkorX staff.
  Future<VerificationRequest> requestVerification({required CommunityRole role, required String evidence, List<String> links = const []});

  // ─── Events ─────────────────────────────────────────────────────────────

  /// `GET /community/events?city&kind&placeId&groupId`: upcoming, soonest first.
  Future<List<CommunityEvent>> events({String? city, String? groupId, String? placeId});

  /// `GET /community/events/:id`
  Future<CommunityEvent> event(String id);

  /// `POST /community/events`
  Future<CommunityEvent> createEvent(EventDraft draft);

  /// `POST /community/events/:id/rsvp { status: going|interested|none }`. Fails
  /// with `RESOURCE_CONFLICT` when the event is full.
  Future<CommunityEvent> rsvp(String eventId, RsvpStatus? status);

  /// `POST /community/events/:id/cancel` (organiser)
  Future<void> cancelEvent(String eventId);

  // ─── Posts ──────────────────────────────────────────────────────────────

  /// `GET /community/posts?groupId&placeId&authorId&before`
  Future<PostPage> feed(FeedScope scope, {String? cursor});

  /// `POST /community/posts`
  Future<CommunityPost> createPost({required PostKind kind, required String body, String? link, String? groupId, String? eventId});

  /// `DELETE /community/posts/:id`
  Future<void> deletePost(String postId);

  /// `PUT` / `DELETE /community/posts/:id/like`. Returns the new count.
  Future<int> like(String postId, {required bool on});

  /// `GET /community/posts/:id/comments`
  Future<List<PostComment>> comments(String postId);

  /// `POST /community/posts/:id/comments`
  Future<PostComment> comment(String postId, String body);

  /// `DELETE /community/comments/:id`
  Future<void> deleteComment(String commentId);

  // ─── Messages ───────────────────────────────────────────────────────────

  /// `GET /me/conversations`
  Future<List<Conversation>> conversations();

  /// `POST /conversations { kind, targetId }`: the existing thread or a new
  /// one. Fails with `MESSAGES_RESTRICTED` when they take messages from
  /// connections only, and `BLOCKED` when either side blocked the other.
  Future<Conversation> openConversation(ConversationKind kind, String targetId);

  /// `GET /conversations/:id/messages?before`
  Future<List<ChatMessage>> messages(String conversationId);

  /// `POST /conversations/:id/messages { text }`. Fails with
  /// `AWAITING_REPLY` for a second message to someone who has not answered.
  Future<ChatMessage> send(String conversationId, String text);

  /// `POST /conversations/:id/read`
  Future<void> markRead(String conversationId);

  /// `POST /conversations/:id/accept` (a message request)
  Future<void> acceptRequest(String conversationId);

  /// `DELETE /conversations/:id`
  Future<void> deleteConversation(String conversationId);
}

/// When no server is configured: an honest empty community.
class EmptyCommunityRepository implements CommunityRepository {
  const EmptyCommunityRepository();

  static const _soon = ApiException('NOT_AVAILABLE', 'Community is not available yet. Please try again soon.');

  @override
  Future<List<CommunityMember>> members(CommunityQuery query) async => const [];
  @override
  Future<CommunityMember> member(String id) async => throw const ApiException('NOT_FOUND', 'This profile is not on SkorX.');
  @override
  Future<List<CommunityPlace>> places(CommunityQuery query) async => const [];
  @override
  Future<CommunityPlace> place(String id) async => throw const ApiException('NOT_FOUND', 'This page is not on SkorX.');
  @override
  Future<List<CommunityGroup>> groups({String? city, String query = ''}) async => const [];
  @override
  Future<CommunityGroup> group(String id) async => throw const ApiException('NOT_FOUND', 'This community is not on SkorX.');
  @override
  Future<List<Suggestion>> suggestions({String? city, Set<CommunityRole> forRoles = const {}}) async => const [];
  @override
  Future<CommunityGraph> graph() async => const CommunityGraph();
  @override
  Future<MyCommunityProfile> myProfile() async => const MyCommunityProfile();
  @override
  Future<MyCommunityProfile> saveProfile(MyCommunityProfile profile) async => throw _soon;
  @override
  Future<ConnectionStatus> connect(String memberId) async => throw _soon;
  @override
  Future<void> disconnect(String memberId) async => throw _soon;
  @override
  Future<void> follow(String targetId, {required bool on, CommunityTarget type = CommunityTarget.member}) async => throw _soon;
  @override
  Future<GroupStatus> joinGroup(String groupId) async => throw _soon;
  @override
  Future<void> leaveGroup(String groupId) async => throw _soon;
  @override
  Future<CommunityGroup> createGroup({required String name, required String about, required GroupAccess access, String? city}) async =>
      throw _soon;
  @override
  Future<List<CommunityMember>> groupRequests(String groupId) async => const [];
  @override
  Future<void> decideGroupRequest(String groupId, String memberId, {required bool approve}) async => throw _soon;
  @override
  Future<void> save(String targetId, {required bool on, required CommunityTarget type}) async => throw _soon;
  @override
  Future<void> block(String memberId, {required bool on}) async => throw _soon;
  @override
  Future<void> report(ReportTarget target, String targetId, ReportReason reason, {String? note}) async => throw _soon;
  @override
  Future<void> feedback({required String memberId, required CommunityRole role, required bool recommend, bool? onTime, String? note}) async =>
      throw _soon;
  @override
  Future<List<VerificationRequest>> myVerifications() async => const [];
  @override
  Future<VerificationRequest> requestVerification({required CommunityRole role, required String evidence, List<String> links = const []}) async =>
      throw _soon;
  @override
  Future<List<CommunityEvent>> events({String? city, String? groupId, String? placeId}) async => const [];
  @override
  Future<CommunityEvent> event(String id) async => throw const ApiException('NOT_FOUND', 'This event is not on SkorX.');
  @override
  Future<CommunityEvent> createEvent(EventDraft draft) async => throw _soon;
  @override
  Future<CommunityEvent> rsvp(String eventId, RsvpStatus? status) async => throw _soon;
  @override
  Future<void> cancelEvent(String eventId) async => throw _soon;
  @override
  Future<PostPage> feed(FeedScope scope, {String? cursor}) async => const PostPage([], null);
  @override
  Future<CommunityPost> createPost({required PostKind kind, required String body, String? link, String? groupId, String? eventId}) async =>
      throw _soon;
  @override
  Future<void> deletePost(String postId) async => throw _soon;
  @override
  Future<int> like(String postId, {required bool on}) async => throw _soon;
  @override
  Future<List<PostComment>> comments(String postId) async => const [];
  @override
  Future<PostComment> comment(String postId, String body) async => throw _soon;
  @override
  Future<void> deleteComment(String commentId) async => throw _soon;
  @override
  Future<List<Conversation>> conversations() async => const [];
  @override
  Future<Conversation> openConversation(ConversationKind kind, String targetId) async => throw _soon;
  @override
  Future<List<ChatMessage>> messages(String conversationId) async => const [];
  @override
  Future<ChatMessage> send(String conversationId, String text) async => throw _soon;
  @override
  Future<void> markRead(String conversationId) async {}
  @override
  Future<void> acceptRequest(String conversationId) async => throw _soon;
  @override
  Future<void> deleteConversation(String conversationId) async => throw _soon;
}
