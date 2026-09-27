import '../../../core/api/api_client.dart';
import 'looking_for.dart';

/// Looking For data. Method names mirror the API (backend
/// `src/looking-for/looking-for.controller.ts`, docs/LOOKING-FOR.md §6).
abstract class LookingForRepository {
  /// `GET /looking-for/categories`
  Future<List<LfCategory>> categories();

  /// `GET /looking-for?tab&category&city&radiusKm&skill&paid&gender&sort&q&cursor`
  Future<LfPage<LfPost>> feed(LfQuery query, {String? cursor});

  /// `GET /looking-for/summary`
  Future<LfSummary> summary();

  /// `GET /looking-for/:id`
  Future<LfPost> post(String id);

  /// `POST /looking-for/parse`: a sentence → suggested fields.
  Future<LfParsed> parse(String text);

  /// `POST /looking-for`. Returns the post and how many people SkorX found for it.
  Future<(LfPost, LfMatching)> create(Map<String, dynamic> body);

  /// `PATCH /looking-for/:id`
  Future<LfPost> update(String id, Map<String, dynamic> body);

  /// `POST /looking-for/:id/cancel` · `/fill` · `/reopen`
  Future<LfPost> setState(String id, String action);

  /// `GET /looking-for/:id/responses` (poster only)
  Future<List<LfResponse>> responses(String postId);

  /// `POST /looking-for/:id/responses`: I'm Interested.
  Future<LfResponse> respond(String postId, {String? message, bool availabilityConfirmed = false});

  /// `POST /looking-for/responses/:id/accept` · `/decline` · `/withdraw` · `/share-contact`
  Future<LfResponse> act(String responseId, String action);

  /// `PUT` / `DELETE /looking-for/:id/save`
  Future<void> save(String postId, {required bool on});

  /// `POST /looking-for/:id/share`: records the share, returns the link.
  Future<String> shareLink(String postId, {String? channel});

  /// `POST /looking-for/:id/report`
  Future<void> report(String postId, String reason, {String? note});

  /// `GET /me/looking-for?tab=posted|completed|saved`
  Future<LfPage<LfPost>> myPosts(LfMineTab tab, {String? cursor});

  /// `GET /me/looking-for?tab=interested`
  Future<LfPage<LfInterest>> myInterests({String? cursor});

  /// `GET /me/looking-for?tab=responses`
  Future<LfPage<LfIncoming>> incoming({String? cursor});

  /// `GET /me/looking-for/counts`
  Future<LfCounts> counts();

  /// `GET` / `PUT /me/looking-for/alerts`
  Future<LfAlerts> alerts();
  Future<LfAlerts> saveAlerts(LfAlerts alerts);
}

class ApiLookingForRepository implements LookingForRepository {
  const ApiLookingForRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<LfCategory>> categories() async {
    final data = await _api.get<List<dynamic>>('/looking-for/categories');
    return [for (final c in data) LfCategory.fromJson(c as Map<String, dynamic>)];
  }

  @override
  Future<LfPage<LfPost>> feed(LfQuery query, {String? cursor}) async {
    final (data, meta) = await _api.getPage<List<dynamic>>('/looking-for', query: query.toQuery(cursor: cursor));
    return LfPage(
      [for (final p in data) LfPost.fromJson(p as Map<String, dynamic>)],
      meta['nextCursor'] as String?,
      needsLocation: meta['needsLocation'] == true,
    );
  }

  @override
  Future<LfSummary> summary() async => LfSummary.fromJson(await _api.get<Map<String, dynamic>>('/looking-for/summary'));

  @override
  Future<LfPost> post(String id) async => LfPost.fromJson(await _api.get<Map<String, dynamic>>('/looking-for/$id'));

  @override
  Future<LfParsed> parse(String text) async => LfParsed.fromJson(await _api.post<Map<String, dynamic>>(
        '/looking-for/parse',
        body: {'text': text, 'tzOffsetMinutes': DateTime.now().timeZoneOffset.inMinutes},
      ));

  @override
  Future<(LfPost, LfMatching)> create(Map<String, dynamic> body) async {
    final data = await _api.post<Map<String, dynamic>>('/looking-for', body: body);
    return (LfPost.fromJson(data['post'] as Map<String, dynamic>), LfMatching.fromJson(data['matching'] as Map<String, dynamic>?));
  }

  @override
  Future<LfPost> update(String id, Map<String, dynamic> body) async =>
      LfPost.fromJson(await _api.patch<Map<String, dynamic>>('/looking-for/$id', body: body));

  @override
  Future<LfPost> setState(String id, String action) async =>
      LfPost.fromJson(await _api.post<Map<String, dynamic>>('/looking-for/$id/$action'));

  @override
  Future<List<LfResponse>> responses(String postId) async {
    final data = await _api.get<List<dynamic>>('/looking-for/$postId/responses');
    return [for (final r in data) LfResponse.fromJson(r as Map<String, dynamic>)];
  }

  @override
  Future<LfResponse> respond(String postId, {String? message, bool availabilityConfirmed = false}) async =>
      LfResponse.fromJson(await _api.post<Map<String, dynamic>>(
        '/looking-for/$postId/responses',
        body: {if (message != null && message.trim().isNotEmpty) 'message': message.trim(), 'availabilityConfirmed': availabilityConfirmed},
      ));

  @override
  Future<LfResponse> act(String responseId, String action) async =>
      LfResponse.fromJson(await _api.post<Map<String, dynamic>>('/looking-for/responses/$responseId/$action'));

  @override
  Future<void> save(String postId, {required bool on}) =>
      on ? _api.put<Object?>('/looking-for/$postId/save') : _api.delete<Object?>('/looking-for/$postId/save');

  @override
  Future<String> shareLink(String postId, {String? channel}) async {
    final data = await _api.post<Map<String, dynamic>>('/looking-for/$postId/share', body: {'channel': ?channel});
    return data['url'] as String;
  }

  @override
  Future<void> report(String postId, String reason, {String? note}) => _api.post<Object?>(
        '/looking-for/$postId/report',
        body: {'reason': reason, if (note != null && note.trim().isNotEmpty) 'description': note.trim()},
      );

  Future<(List<dynamic>, String?)> _mine(String tab, String? cursor) async {
    final (data, meta) = await _api.getPage<List<dynamic>>('/me/looking-for', query: {'tab': tab, 'cursor': ?cursor});
    return (data, meta['nextCursor'] as String?);
  }

  @override
  Future<LfPage<LfPost>> myPosts(LfMineTab tab, {String? cursor}) async {
    final (data, next) = await _mine(tab.name, cursor);
    return LfPage([for (final p in data) LfPost.fromJson(p as Map<String, dynamic>)], next);
  }

  @override
  Future<LfPage<LfInterest>> myInterests({String? cursor}) async {
    final (data, next) = await _mine('interested', cursor);
    return LfPage([
      for (final p in data.cast<Map<String, dynamic>>())
        LfInterest(LfPost.fromJson(p), LfResponse.fromJson(p['myResponse'] as Map<String, dynamic>)),
    ], next);
  }

  @override
  Future<LfPage<LfIncoming>> incoming({String? cursor}) async {
    final (data, next) = await _mine('responses', cursor);
    return LfPage([
      for (final r in data.cast<Map<String, dynamic>>())
        LfIncoming(
          postId: (r['post'] as Map)['id'] as String,
          postTitle: (r['post'] as Map)['title'] as String,
          response: LfResponse.fromJson(r['response'] as Map<String, dynamic>),
        ),
    ], next);
  }

  @override
  Future<LfCounts> counts() async => LfCounts.fromJson(await _api.get<Map<String, dynamic>>('/me/looking-for/counts'));

  @override
  Future<LfAlerts> alerts() async => LfAlerts.fromJson(await _api.get<Map<String, dynamic>>('/me/looking-for/alerts'));

  @override
  Future<LfAlerts> saveAlerts(LfAlerts alerts) async =>
      LfAlerts.fromJson(await _api.put<Map<String, dynamic>>('/me/looking-for/alerts', body: alerts.toJson()));
}
