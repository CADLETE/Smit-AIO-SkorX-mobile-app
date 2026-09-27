import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sample_latency.dart';
import '../../core/sample_persona.dart';
import '../auth/auth_controller.dart';
import '../player/data/player_repository.dart';
import 'data/api_community_repository.dart';
import 'data/community.dart';
import 'data/community_query.dart';
import 'data/community_repository.dart';
import 'data/content.dart';
import 'data/messages.dart';
import 'data/sample_community.dart';

/// The real API when this build signs in against it (release, or
/// `--dart-define=REAL_AUTH=true`); the in-memory sample otherwise.
final communityRepositoryProvider = Provider<CommunityRepository>((ref) {
  if (useRealApi || !kDebugMode) return ApiCommunityRepository(ref.watch(apiClientProvider));
  return SampleCommunityRepository(
    latency: ref.watch(sampleLatencyProvider),
    newcomer: ref.watch(samplePersonaProvider) == SamplePersona.newcomer,
    myName: ref.watch(currentUserProvider.select((u) => u?.name)) ?? 'You',
  );
});

// ─── Location ─────────────────────────────────────────────────────────────

/// Where Community looks. Starts at the player's own city; they can pick
/// any city or "Anywhere". Location permission is never asked for.
class CommunityLocation {
  const CommunityLocation(this.city, {this.mine = false});

  static const anywhere = CommunityLocation(null);

  /// Null: anywhere.
  final String? city;

  /// Following the player's profile city, not a choice they made.
  final bool mine;

  String get label => city ?? 'Anywhere';
  String? get state => city == null ? null : communityCities[city];
}

final communityLocationProvider =
    NotifierProvider<CommunityLocationController, CommunityLocation>(CommunityLocationController.new);

class CommunityLocationController extends Notifier<CommunityLocation> {
  CommunityLocation? _chosen;

  @override
  CommunityLocation build() {
    if (_chosen != null) return _chosen!;
    final mine = ref.watch(playerOverviewProvider.select((o) => o.value?.city));
    return mine == null ? CommunityLocation.anywhere : CommunityLocation(mine, mine: true);
  }

  void choose(String? city) => state = _chosen = CommunityLocation(city);
}

// ─── Me ───────────────────────────────────────────────────────────────────

final myCommunityProfileProvider =
    AsyncNotifierProvider<MyCommunityProfileController, MyCommunityProfile>(MyCommunityProfileController.new);

class MyCommunityProfileController extends AsyncNotifier<MyCommunityProfile> {
  @override
  Future<MyCommunityProfile> build() => ref.watch(communityRepositoryProvider).myProfile();

  Future<void> save(MyCommunityProfile profile) async {
    state = AsyncData(await ref.read(communityRepositoryProvider).saveProfile(profile));
  }
}

/// The roles Community personalises for; a player until they say more.
/// A selector, not a derived provider, so a change lands when it is saved
/// rather than when a paused screen resumes mid-build.
final myCommunityRoles = myCommunityProfileProvider.select((p) => p.value?.roles ?? const {CommunityRole.player});

/// Connections, follows, groups, blocks and saves. Every change shows at
/// once and rolls back if the server refuses it.
final communityGraphProvider = AsyncNotifierProvider<CommunityGraphController, CommunityGraph>(CommunityGraphController.new);

class CommunityGraphController extends AsyncNotifier<CommunityGraph> {
  @override
  Future<CommunityGraph> build() => ref.watch(communityRepositoryProvider).graph();

  CommunityRepository get _repo => ref.read(communityRepositoryProvider);

  Future<T> _optimistic<T>(CommunityGraph Function(CommunityGraph) change, Future<T> Function() call) async {
    final before = state.value ?? const CommunityGraph();
    state = AsyncData(change(before));
    try {
      return await call();
    } catch (_) {
      state = AsyncData(before);
      rethrow;
    }
  }

  /// Sends a request, or accepts theirs. Returns the new status.
  Future<ConnectionStatus> connect(String memberId) async {
    final incoming = state.value?.connectionWith(memberId) == ConnectionStatus.pendingIn;
    final status = await _optimistic(
      (g) => g.withConnection(memberId, incoming ? ConnectionStatus.connected : ConnectionStatus.pendingOut),
      () => _repo.connect(memberId),
    );
    state = AsyncData(state.value!.withConnection(memberId, status));
    // An accepted request can turn a message request into a normal thread.
    await ref.read(conversationsProvider.notifier).reload();
    return status;
  }

  /// Withdraws a request, declines theirs, or removes a connection.
  Future<void> disconnect(String memberId) =>
      _optimistic((g) => g.withConnection(memberId, ConnectionStatus.none), () => _repo.disconnect(memberId));

  Future<void> follow(String targetId, {required bool on, CommunityTarget type = CommunityTarget.member}) => _optimistic(
        (g) => g.copyWith(following: toggledIn(g.following, targetId, on)),
        () => _repo.follow(targetId, on: on, type: type),
      );

  Future<void> save(String targetId, {required bool on, required CommunityTarget type}) => _optimistic(
        (g) => g.withSaved(targetId, type, on),
        () => _repo.save(targetId, on: on, type: type),
      );

  Future<GroupStatus> join(CommunityGroup group) async {
    final status = await _optimistic(
      (g) => g.withGroup(group.id, group.access == GroupAccess.public ? GroupStatus.member : GroupStatus.requested),
      () => _repo.joinGroup(group.id),
    );
    state = AsyncData(state.value!.withGroup(group.id, status));
    return status;
  }

  Future<void> leave(String groupId) =>
      _optimistic((g) => g.withGroup(groupId, GroupStatus.none), () => _repo.leaveGroup(groupId));

  Future<void> block(String memberId, {required bool on}) async {
    await _optimistic(
      (g) => on
          ? g
              .withConnection(memberId, ConnectionStatus.none)
              .copyWith(blocked: {...g.blocked, memberId}, following: toggledIn(g.following, memberId, false))
          : g.copyWith(blocked: toggledIn(g.blocked, memberId, false)),
      () => _repo.block(memberId, on: on),
    );
    await ref.read(conversationsProvider.notifier).reload();
  }

  /// A group the member just created, already joined.
  void addCreatedGroup(String groupId) => state = AsyncData((state.value ?? const CommunityGraph()).withGroup(groupId, GroupStatus.member));
}

/// Pending requests to me, for the tab badge and the hub.
final incomingRequestsProvider = communityGraphProvider.select((g) => g.value?.incomingCount ?? 0);

// ─── Directory ────────────────────────────────────────────────────────────

/// Re-read directory lists after a block or unblock (the server hides
/// blocked members).
int _blocks(Ref ref) => ref.watch(communityGraphProvider.select((g) => g.value?.blocked.length ?? 0));

final communityMembersProvider = FutureProvider.autoDispose.family<List<CommunityMember>, CommunityQuery>((ref, query) {
  _blocks(ref);
  return ref.watch(communityRepositoryProvider).members(query);
});

final communityPlacesProvider = FutureProvider.autoDispose.family<List<CommunityPlace>, CommunityQuery>(
  (ref, query) => ref.watch(communityRepositoryProvider).places(query),
);

final communityMemberProvider = FutureProvider.autoDispose.family<CommunityMember, String>(
  (ref, id) => ref.watch(communityRepositoryProvider).member(id),
);

final communityPlaceProvider = FutureProvider.autoDispose.family<CommunityPlace, String>(
  (ref, id) => ref.watch(communityRepositoryProvider).place(id),
);

final communityGroupProvider = FutureProvider.autoDispose.family<CommunityGroup, String>(
  (ref, id) => ref.watch(communityRepositoryProvider).group(id),
);

/// Groups for a city (null: all), local ones first.
final communityGroupsProvider = FutureProvider.autoDispose.family<List<CommunityGroup>, String?>(
  (ref, city) => ref.watch(communityRepositoryProvider).groups(city: city),
);

/// People you may know, for where Community is looking and what I do.
final communitySuggestionsProvider = FutureProvider.autoDispose<List<Suggestion>>((ref) {
  _blocks(ref);
  return ref.watch(communityRepositoryProvider).suggestions(
        city: ref.watch(communityLocationProvider).city,
        forRoles: ref.watch(myCommunityRoles),
      );
});

/// Several members by id, in that order, skipping any that are gone.
final communityMembersByIdProvider = FutureProvider.autoDispose.family<List<CommunityMember>, String>((ref, ids) async {
  _blocks(ref);
  final repo = ref.watch(communityRepositoryProvider);
  final out = <CommunityMember>[];
  for (final id in ids.split(',').where((s) => s.isNotEmpty)) {
    try {
      out.add(await repo.member(id));
    } catch (_) {}
  }
  final blocked = ref.read(communityGraphProvider).value?.blocked ?? const {};
  return [for (final m in out) if (!blocked.contains(m.id)) m];
});

/// Several places by id, in that order, skipping any that are gone.
final communityPlacesByIdProvider = FutureProvider.autoDispose.family<List<CommunityPlace>, String>((ref, ids) async {
  final repo = ref.watch(communityRepositoryProvider);
  final out = <CommunityPlace>[];
  for (final id in ids.split(',').where((s) => s.isNotEmpty)) {
    try {
      out.add(await repo.place(id));
    } catch (_) {}
  }
  return out;
});

// ─── Messages ─────────────────────────────────────────────────────────────

final conversationsProvider = AsyncNotifierProvider<ConversationsController, List<Conversation>>(ConversationsController.new);

class ConversationsController extends AsyncNotifier<List<Conversation>> {
  @override
  Future<List<Conversation>> build() => ref.watch(communityRepositoryProvider).conversations();

  CommunityRepository get _repo => ref.read(communityRepositoryProvider);

  /// Re-reads the inbox in place (after a connection or block changes who
  /// can talk), keeping the old list on screen meanwhile.
  Future<void> reload() async {
    try {
      state = AsyncData(await _repo.conversations());
    } catch (_) {
      // Keep what is shown; the next open retries.
    }
  }

  /// The thread with a member, place or group, started if there is none.
  Future<Conversation> open(ConversationKind kind, String targetId) async {
    final c = await _repo.openConversation(kind, targetId);
    final list = state.value ?? const [];
    if (!list.any((x) => x.id == c.id)) state = AsyncData([c, ...list]);
    return c;
  }

  void _patch(String id, Conversation Function(Conversation) change) {
    final list = state.value;
    if (list == null) return;
    state = AsyncData([for (final c in list) c.id == id ? change(c) : c]..sort((a, b) => b.lastAt.compareTo(a.lastAt)));
  }

  Future<void> markRead(String id) async {
    _patch(id, (c) => c.copyWith(unread: 0));
    await _repo.markRead(id);
  }

  Future<void> accept(String id) async {
    await _repo.acceptRequest(id);
    _patch(id, (c) => c.copyWith(request: false));
  }

  Future<void> delete(String id) async {
    await _repo.deleteConversation(id);
    state = AsyncData([for (final c in state.value ?? const <Conversation>[]) if (c.id != id) c]);
  }

  void _sent(ChatMessage m) => _patch(m.conversationId, (c) => c.copyWith(lastText: m.text, lastAt: m.at, request: false));
}

/// Conversations waiting in the inbox (not requests) with unread messages,
/// plus message requests.
final unreadConversationsProvider = conversationsProvider.select(
  (v) => (v.value ?? const <Conversation>[]).where((c) => c.unread > 0 || c.request).length,
);

/// The Community tab's badge: requests to connect and unread conversations.
final communityBadgeProvider = Provider<int>((ref) => ref.watch(incomingRequestsProvider) + ref.watch(unreadConversationsProvider));

final threadProvider = AsyncNotifierProvider.autoDispose.family<ThreadController, List<ChatMessage>, String>(ThreadController.new);

class ThreadController extends AsyncNotifier<List<ChatMessage>> {
  ThreadController(this.conversationId);

  final String conversationId;

  @override
  Future<List<ChatMessage>> build() => ref.watch(communityRepositoryProvider).messages(conversationId);

  Future<void> send(String text) async {
    final m = await ref.read(communityRepositoryProvider).send(conversationId, text);
    state = AsyncData([...?state.value, m]);
    ref.read(conversationsProvider.notifier)._sent(m);
  }
}

// ─── Events ───────────────────────────────────────────────────────────────

/// Clinics, open play and meetups: in a city, a community or at a place.
typedef EventScope = ({String? city, String? groupId, String? placeId});

final communityEventsProvider = FutureProvider.autoDispose.family<List<CommunityEvent>, EventScope>(
  (ref, s) => ref.watch(communityRepositoryProvider).events(city: s.city, groupId: s.groupId, placeId: s.placeId),
);

final communityEventProvider = AsyncNotifierProvider.autoDispose.family<EventController, CommunityEvent, String>(EventController.new);

class EventController extends AsyncNotifier<CommunityEvent> {
  EventController(this.eventId);

  final String eventId;

  @override
  Future<CommunityEvent> build() => ref.watch(communityRepositoryProvider).event(eventId);

  /// Going, interested, or null to drop out.
  Future<void> rsvp(RsvpStatus? status) async {
    state = AsyncData(await ref.read(communityRepositoryProvider).rsvp(eventId, status));
    ref.invalidate(communityEventsProvider);
  }

  Future<void> cancel() async {
    await ref.read(communityRepositoryProvider).cancelEvent(eventId);
    state = AsyncData(state.value!.copyWith(cancelled: true));
    ref.invalidate(communityEventsProvider);
  }
}

// ─── Posts ────────────────────────────────────────────────────────────────

final communityFeedProvider = AsyncNotifierProvider.autoDispose.family<FeedController, PostPage, FeedScope>(FeedController.new);

class FeedController extends AsyncNotifier<PostPage> {
  FeedController(this.scope);

  final FeedScope scope;
  bool _loading = false;

  CommunityRepository get _repo => ref.read(communityRepositoryProvider);

  @override
  Future<PostPage> build() {
    ref.watch(communityGraphProvider.select((g) => g.value?.blocked.length ?? 0));
    return ref.watch(communityRepositoryProvider).feed(scope);
  }

  Future<void> loadMore() async {
    final page = state.value;
    if (page == null || page.nextCursor == null || _loading) return;
    _loading = true;
    try {
      final next = await _repo.feed(scope, cursor: page.nextCursor);
      state = AsyncData(PostPage([...page.posts, ...next.posts], next.nextCursor));
    } finally {
      _loading = false;
    }
  }

  void _patch(String id, CommunityPost Function(CommunityPost) change) {
    final page = state.value;
    if (page == null) return;
    state = AsyncData(PostPage([for (final p in page.posts) p.id == id ? change(p) : p], page.nextCursor));
  }

  /// Likes show at once and roll back if the server refuses.
  Future<void> like(CommunityPost post) async {
    final on = !post.likedByMe;
    _patch(post.id, (p) => p.copyWith(likedByMe: on, likes: p.likes + (on ? 1 : -1)));
    try {
      final likes = await _repo.like(post.id, on: on);
      _patch(post.id, (p) => p.copyWith(likes: likes));
    } catch (_) {
      _patch(post.id, (p) => p.copyWith(likedByMe: !on, likes: p.likes + (on ? -1 : 1)));
      rethrow;
    }
  }

  void added(CommunityPost post) {
    final page = state.value ?? const PostPage([], null);
    state = AsyncData(PostPage([post, ...page.posts], page.nextCursor));
  }

  Future<void> delete(String postId) async {
    await _repo.deletePost(postId);
    final page = state.value;
    if (page != null) state = AsyncData(PostPage([for (final p in page.posts) if (p.id != postId) p], page.nextCursor));
  }

  void commented(String postId, int delta) => _patch(postId, (p) => p.copyWith(comments: p.comments + delta));
}

final postCommentsProvider = FutureProvider.autoDispose.family<List<PostComment>, String>(
  (ref, postId) => ref.watch(communityRepositoryProvider).comments(postId),
);

// ─── Verification and admin ───────────────────────────────────────────────

final myVerificationsProvider = FutureProvider.autoDispose<List<VerificationRequest>>(
  (ref) => ref.watch(communityRepositoryProvider).myVerifications(),
);

final groupRequestsProvider = FutureProvider.autoDispose.family<List<CommunityMember>, String>(
  (ref, groupId) => ref.watch(communityRepositoryProvider).groupRequests(groupId),
);

/// Whether I can leave organiser feedback: I run tournaments for an
/// organisation (owner or tournament admin). The server checks it again.
final isOrganiserProvider = Provider<bool>((ref) {
  final user = ref.watch(currentUserProvider);
  return user?.memberships.any((m) => m.role == 'owner' || m.role == 'tournament_admin') ?? false;
});
