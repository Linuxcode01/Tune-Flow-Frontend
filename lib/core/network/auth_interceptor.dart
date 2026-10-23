import 'package:dio/dio.dart';
import 'package:tuneflow/core/constants/api_endpoints.dart';
import 'package:tuneflow/core/network/api_envelope.dart';
import 'package:tuneflow/core/network/session_events.dart';
import 'package:tuneflow/core/storage/auth_tokens.dart';
import 'package:tuneflow/core/storage/token_storage.dart';
import 'package:tuneflow/core/utils/app_logger.dart';

/// Attaches the bearer token and transparently refreshes it on `401` (docs section 10).
///
/// Key behaviours:
/// * **Single-flight refresh.** When ten requests fail with 401 at once - which is exactly what
///   happens when a token expires mid-scroll - only the first triggers a refresh; the rest wait on
///   the same future. Without this, refresh-token rotation would invalidate the session because
///   the server rejects a reused refresh token.
/// * **Request replay.** The original request is retried once with the new token, so the UI never
///   sees the 401 that caused it.
/// * **Hard stop on failure.** If the refresh is rejected, credentials are wiped and a
///   [SessionEvent.expired] is emitted; the router then sends the user to the login screen.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required TokenStorage tokenStorage,
    required Dio refreshDio,
    required SessionEvents sessionEvents,
  })  : _tokenStorage = tokenStorage,
        _refreshDio = refreshDio,
        _sessionEvents = sessionEvents;

  final TokenStorage _tokenStorage;

  /// A bare Dio instance (no interceptors) used only for the refresh call, so a failed refresh can
  /// never recurse back into this interceptor.
  final Dio _refreshDio;

  final SessionEvents _sessionEvents;

  Future<AuthTokens?>? _inFlightRefresh;

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (_requiresAuth(options)) {
      final AuthTokens? tokens = _tokenStorage.cached ?? await _tokenStorage.read();
      if (tokens != null) {
        if (tokens.isExpired()) {
          final AuthTokens? refreshed = await _refreshTokens();
          if (refreshed != null) {
            options.headers['Authorization'] = 'Bearer ${refreshed.accessToken}';
          }
        } else {
          options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
        }
      }
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final RequestOptions request = err.requestOptions;
    final bool isUnauthorized = err.response?.statusCode == 401;

    if (!isUnauthorized || !_requiresAuth(request) || request.extra['retried'] == true) {
      handler.next(err);
      return;
    }

    final AuthTokens? refreshed = await _refreshTokens();
    if (refreshed == null) {
      handler.next(err);
      return;
    }

    try {
      final Response<dynamic> response = await _replay(request, refreshed.accessToken);
      handler.resolve(response);
    } on DioException catch (replayError) {
      handler.next(replayError);
    }
  }

  Future<Response<dynamic>> _replay(RequestOptions request, String accessToken) {
    final Map<String, dynamic> headers = Map<String, dynamic>.from(request.headers)
      ..['Authorization'] = 'Bearer $accessToken'
      ..remove(Headers.contentLengthHeader);

    return _refreshDio.request<dynamic>(
      request.path,
      data: request.data,
      queryParameters: request.queryParameters,
      cancelToken: request.cancelToken,
      options: Options(
        method: request.method,
        headers: headers,
        contentType: request.contentType,
        responseType: request.responseType,
        sendTimeout: request.sendTimeout,
        receiveTimeout: request.receiveTimeout,
        extra: <String, dynamic>{...request.extra, 'retried': true},
      ),
    );
  }

  /// Refreshes once, no matter how many callers ask concurrently.
  Future<AuthTokens?> _refreshTokens() {
    return _inFlightRefresh ??= _performRefresh().whenComplete(() {
      _inFlightRefresh = null;
    });
  }

  Future<AuthTokens?> _performRefresh() async {
    final AuthTokens? current = _tokenStorage.cached ?? await _tokenStorage.read();
    if (current == null || current.refreshToken.isEmpty) {
      await _handleExpiry();
      return null;
    }

    try {
      final Response<dynamic> response = await _refreshDio.post<dynamic>(
        ApiEndpoints.refresh,
        data: <String, dynamic>{'refreshToken': current.refreshToken},
      );
      final dynamic payload = ApiEnvelope.unwrap(response.data, path: ApiEndpoints.refresh);
      if (payload is! Map<String, dynamic>) {
        await _handleExpiry();
        return null;
      }

      final String accessToken = payload['accessToken'] as String? ?? '';
      final String refreshToken = payload['refreshToken'] as String? ?? '';
      final int expiresIn = (payload['expiresIn'] as num?)?.toInt() ?? 900;
      if (accessToken.isEmpty || refreshToken.isEmpty) {
        await _handleExpiry();
        return null;
      }

      final AuthTokens rotated = AuthTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
        accessTokenExpiresAt: DateTime.now().toUtc().add(Duration(seconds: expiresIn)),
      );
      await _tokenStorage.write(rotated);
      AppLogger.debug('Access token refreshed');
      return rotated;
    } on DioException catch (error) {
      // 401/403 means the refresh token itself is dead - that is a real sign-out. A network blip is
      // not, so keep the stored session and let the caller surface a retryable error.
      final int? status = error.response?.statusCode;
      if (status == 401 || status == 403) {
        await _handleExpiry();
      } else {
        AppLogger.warn('Token refresh failed (network) -> keeping session', error: error);
      }
      return null;
    }
  }

  Future<void> _handleExpiry() async {
    await _tokenStorage.clear();
    _sessionEvents.emit(SessionEvent.expired);
    AppLogger.info('Session expired - credentials cleared');
  }

  /// Public endpoints skip token handling entirely (catalogue reads, auth, signed media URLs).
  static bool _requiresAuth(RequestOptions options) {
    final String path = options.path;
    if (path.startsWith(ApiEndpoints.login) ||
        path.startsWith(ApiEndpoints.register) ||
        path.startsWith(ApiEndpoints.refresh) ||
        path.startsWith(ApiEndpoints.forgotPassword) ||
        path.startsWith(ApiEndpoints.resetPassword)) {
      return false;
    }
    return !options.extra.containsKey('skipAuth');
  }
}
