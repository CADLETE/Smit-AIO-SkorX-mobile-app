import 'dart:async';

import 'package:dio/dio.dart';

import '../auth/token_store.dart';
import 'api_exception.dart';

/// The API the app talks to. Override per build:
/// `flutter run --dart-define=API_BASE_URL=https://api.skorx.in/api/v1`.
/// The default reaches a backend on the host machine from the Android emulator.
const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:4000/api/v1');

/// Thin wrapper over Dio for the SkorX API: unwraps the `{ success, data }`
/// envelope, turns failures into [ApiException], sends the access token and
/// refreshes it once when it has expired.
class ApiClient {
  ApiClient({
    required TokenStore tokens,
    String baseUrl = apiBaseUrl,
    HttpClientAdapter? adapter,
    this.onSessionEnded,
  })  : _tokens = tokens,
        _dio = Dio(_options(baseUrl)),
        _refreshDio = Dio(_options(baseUrl)) {
    if (adapter != null) {
      _dio.httpClientAdapter = adapter;
      _refreshDio.httpClientAdapter = adapter;
    }
    _dio.interceptors.add(InterceptorsWrapper(onRequest: _attachToken));
  }

  final TokenStore _tokens;
  final Dio _dio;

  /// Used only for refresh, so a failing refresh cannot recurse.
  final Dio _refreshDio;

  /// Called when the session can no longer be refreshed (revoked, expired).
  void Function()? onSessionEnded;

  Future<SessionTokens?>? _refreshing;

  static BaseOptions _options(String baseUrl) => BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
        contentType: Headers.jsonContentType,
        // Status handling is ours: every body is read and unwrapped.
        validateStatus: (_) => true,
      );

  Future<T> get<T>(String path, {Map<String, dynamic>? query}) =>
      _send<T>(() => _dio.get<Object?>(path, queryParameters: query));

  Future<T> post<T>(String path, {Object? body}) => _send<T>(() => _dio.post<Object?>(path, data: body));

  Future<T> patch<T>(String path, {Object? body}) => _send<T>(() => _dio.patch<Object?>(path, data: body));

  Future<T> put<T>(String path, {Object? body}) => _send<T>(() => _dio.put<Object?>(path, data: body));

  Future<T> delete<T>(String path, {Object? body}) => _send<T>(() => _dio.delete<Object?>(path, data: body));

  /// A paged list: the data plus the envelope's `meta` (cursors, totals).
  Future<(T, Map<String, dynamic>)> getPage<T>(String path, {Map<String, dynamic>? query}) async {
    final meta = <String, dynamic>{};
    final data = await _send<T>(() async {
      final response = await _dio.get<Object?>(path, queryParameters: query);
      final body = response.data;
      if (body is Map<String, dynamic> && body['meta'] is Map<String, dynamic>) {
        meta
          ..clear()
          ..addAll(body['meta'] as Map<String, dynamic>);
      }
      return response;
    });
    return (data, meta);
  }

  /// Unauthenticated call that must not trigger a refresh (sign-in itself).
  Future<T> postPublic<T>(String path, {Object? body}) =>
      _send<T>(() => _refreshDio.post<Object?>(path, data: body), retryOnExpiry: false);

  Future<T> _send<T>(Future<Response<Object?>> Function() request, {bool retryOnExpiry = true}) async {
    var response = await _guard(request);
    if (response.statusCode == 401 && retryOnExpiry) {
      final refreshed = await _refreshOnce();
      if (refreshed != null) response = await _guard(request);
    }
    return _unwrap<T>(response);
  }

  Future<void> _attachToken(RequestOptions options, RequestInterceptorHandler handler) async {
    final tokens = await _tokens.read();
    if (tokens != null) options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
    handler.next(options);
  }

  /// Parallel requests that all hit an expired token share one refresh: the
  /// server rotates refresh tokens, so a second refresh with the same token
  /// would be rejected.
  Future<SessionTokens?> _refreshOnce() {
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  Future<SessionTokens?> _refresh() async {
    final current = await _tokens.read();
    if (current == null) return null;
    try {
      final response = await _guard(
        () => _refreshDio.post<Object?>('/auth/refresh', data: {'refreshToken': current.refreshToken}),
      );
      final data = _unwrap<Map<String, dynamic>>(response);
      final next = SessionTokens.fromJson(data['session'] as Map<String, dynamic>);
      await _tokens.write(next);
      return next;
    } on ApiException catch (e) {
      // Offline is not a reason to sign the player out.
      if (e.isNetwork) return null;
      await _tokens.clear();
      onSessionEnded?.call();
      return null;
    }
  }

  static Future<Response<Object?>> _guard(Future<Response<Object?>> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      if (e.response != null) return e.response!;
      throw const ApiException(ApiException.network, 'No internet connection. Check your network and try again.');
    }
  }

  static T _unwrap<T>(Response<Object?> response) {
    final body = response.data;
    if (body is Map<String, dynamic> && body['success'] == true) return body['data'] as T;
    if (body is Map<String, dynamic> && body['error'] is Map<String, dynamic>) {
      final error = body['error'] as Map<String, dynamic>;
      throw ApiException(
        error['code'] as String? ?? ApiException.badResponse,
        error['message'] as String? ?? 'Something went wrong. Please try again.',
        status: response.statusCode,
      );
    }
    throw ApiException(
      ApiException.badResponse,
      'Something went wrong. Please try again.',
      status: response.statusCode,
    );
  }
}
