import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sample_latency.dart';
import '../../core/sample_persona.dart';
import '../auth/auth_controller.dart';
import '../notifications/notifications.dart';
import 'data/looking_for.dart';
import 'data/looking_for_repository.dart';
import 'data/sample_looking_for.dart';

/// The real API when this build signs in against it (release, or
/// `--dart-define=REAL_AUTH=true`); the in-memory stand-in otherwise.
final lookingForRepositoryProvider = Provider<LookingForRepository>((ref) {
  if (useRealApi || !kDebugMode) return ApiLookingForRepository(ref.watch(apiClientProvider));
  return SampleLookingForRepository(
    latency: ref.watch(sampleLatencyProvider),
    newcomer: ref.watch(samplePersonaProvider) == SamplePersona.newcomer,
  );
});

final lfCategoriesProvider = FutureProvider<List<LfCategory>>((ref) => ref.watch(lookingForRepositoryProvider).categories());

LfCategory? lfCategoryOf(List<LfCategory>? categories, String id) => categories?.where((c) => c.id == id).firstOrNull;

/// The Looking For home's tab, search and filters, kept while the app is open.
final lfQueryProvider = NotifierProvider<LfQueryController, LfQuery>(LfQueryController.new);

class LfQueryController extends Notifier<LfQuery> {
  @override
  LfQuery build() => const LfQuery();

  void update(LfQuery Function(LfQuery) change) => state = change(state);
}

class LfFeedState {
  const LfFeedState(this.posts, {this.nextCursor, this.needsLocation = false});

  final List<LfPost> posts;
  final String? nextCursor;
  final bool needsLocation;
  bool get hasMore => nextCursor != null;
}

/// One query's feed, a page at a time as the list scrolls.
final lfFeedProvider = AsyncNotifierProvider.autoDispose.family<LfFeed, LfFeedState, LfQuery>(LfFeed.new);

class LfFeed extends AsyncNotifier<LfFeedState> {
  LfFeed(this.query);

  final LfQuery query;
  bool _loading = false;

  @override
  Future<LfFeedState> build() async {
    final page = await ref.watch(lookingForRepositoryProvider).feed(query);
    return LfFeedState(page.items, nextCursor: page.nextCursor, needsLocation: page.needsLocation);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || _loading) return;
    _loading = true;
    try {
      final next = await ref.read(lookingForRepositoryProvider).feed(query, cursor: current.nextCursor);
      state = AsyncData(LfFeedState([...current.posts, ...next.items], nextCursor: next.nextCursor));
    } finally {
      _loading = false;
    }
  }

  /// Applies a change to one post in place (saved, my response) without a reload.
  void patch(String id, LfPost Function(LfPost) change) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(LfFeedState([for (final p in current.posts) p.id == id ? change(p) : p],
        nextCursor: current.nextCursor, needsLocation: current.needsLocation));
  }
}

final lfSummaryProvider = FutureProvider.autoDispose<LfSummary>((ref) => ref.watch(lookingForRepositoryProvider).summary());

final lfPostProvider = FutureProvider.autoDispose.family<LfPost, String>((ref, id) => ref.watch(lookingForRepositoryProvider).post(id));

final lfResponsesProvider =
    FutureProvider.autoDispose.family<List<LfResponse>, String>((ref, postId) => ref.watch(lookingForRepositoryProvider).responses(postId));

final lfMyPostsProvider =
    FutureProvider.autoDispose.family<LfPage<LfPost>, LfMineTab>((ref, tab) => ref.watch(lookingForRepositoryProvider).myPosts(tab));

final lfInterestsProvider = FutureProvider.autoDispose<LfPage<LfInterest>>((ref) => ref.watch(lookingForRepositoryProvider).myInterests());

final lfIncomingProvider = FutureProvider.autoDispose<LfPage<LfIncoming>>((ref) => ref.watch(lookingForRepositoryProvider).incoming());

final lfCountsProvider = FutureProvider.autoDispose<LfCounts>((ref) => ref.watch(lookingForRepositoryProvider).counts());

final lfAlertsProvider = FutureProvider.autoDispose<LfAlerts>((ref) => ref.watch(lookingForRepositoryProvider).alerts());

/// Every write goes through here, so each one refreshes exactly the lists it changes.
final lfActionsProvider = Provider<LfActions>(LfActions.new);

class LfActions {
  LfActions(this._ref);

  final Ref _ref;

  LookingForRepository get _repo => _ref.read(lookingForRepositoryProvider);

  void _mine() {
    _ref
      ..invalidate(lfMyPostsProvider)
      ..invalidate(lfInterestsProvider)
      ..invalidate(lfIncomingProvider)
      ..invalidate(lfCountsProvider);
  }

  void _post(String id) {
    _ref
      ..invalidate(lfPostProvider(id))
      ..invalidate(lfResponsesProvider(id));
    _mine();
  }

  Future<(LfPost, LfMatching)> create(Map<String, dynamic> body) async {
    final result = await _repo.create(body);
    _ref
      ..invalidate(lfFeedProvider)
      ..invalidate(lfSummaryProvider);
    _mine();
    return result;
  }

  Future<LfPost> update(String id, Map<String, dynamic> body) async {
    final post = await _repo.update(id, body);
    _ref.invalidate(lfFeedProvider);
    _post(id);
    return post;
  }

  /// cancel | fill | reopen
  Future<LfPost> setState(String id, String action) async {
    final post = await _repo.setState(id, action);
    _ref.invalidate(lfFeedProvider);
    _post(id);
    return post;
  }

  Future<LfResponse> respond(String postId, {String? message, bool availabilityConfirmed = false}) async {
    final r = await _repo.respond(postId, message: message, availabilityConfirmed: availabilityConfirmed);
    _ref.invalidate(lfFeedProvider);
    _post(postId);
    return r;
  }

  /// accept | decline | withdraw | share-contact
  Future<LfResponse> act(String postId, String responseId, String action) async {
    final r = await _repo.act(responseId, action);
    if (action != 'share-contact') _ref.invalidate(lfFeedProvider);
    _post(postId);
    return r;
  }

  Future<void> save(LfPost post, {required bool on}) async {
    await _repo.save(post.id, on: on);
    _ref
      ..invalidate(lfPostProvider(post.id))
      ..invalidate(lfMyPostsProvider(LfMineTab.saved))
      ..invalidate(lfCountsProvider);
  }

  Future<String> shareLink(String postId, {String? channel}) => _repo.shareLink(postId, channel: channel);

  Future<void> report(String postId, String reason, {String? note}) => _repo.report(postId, reason, note: note);

  Future<LfAlerts> saveAlerts(LfAlerts alerts) async {
    final saved = await _repo.saveAlerts(alerts);
    _ref
      ..invalidate(lfAlertsProvider)
      ..invalidate(lfFeedProvider);
    return saved;
  }

  Future<LfParsed> parse(String text) => _repo.parse(text);

  /// Notifications about Looking For may have arrived with this change.
  void refreshNotifications() => _ref.invalidate(notificationsProvider);
}
