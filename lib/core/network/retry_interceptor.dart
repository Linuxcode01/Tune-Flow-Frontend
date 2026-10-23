import 'dart:math';

import 'package:dio/dio.dart';
import 'package:tuneflow/core/utils/app_logger.dart';

/// Retries idempotent requests that failed for transient reasons.
///
/// Mobile networks drop connections constantly; without this, a user scrolling a rail sees an error
/// card for what was a one-second blip. Only GETs are retried (a retried POST could double-charge
/// or double-like), and `429` is respected via `Retry-After` because hammering a rate limiter makes
/// things worse.
class RetryInterceptor extends Interceptor {
  RetryInterceptor({
    required Dio dio,
    this.maxAttempts = 3,
    this.baseDelay = const Duration(milliseconds: 400),
  }) : _dio = dio;

  final Dio _dio;
  final int maxAttempts;
  final Duration baseDelay;

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final RequestOptions request = err.requestOptions;
    final int attempt = (request.extra['attempt'] as int?) ?? 0;

    if (!_shouldRetry(err, attempt)) {
      handler.next(err);
      return;
    }

    final Duration delay = _delayFor(err, attempt);
    AppLogger.debug('Retrying ${request.path} in ${delay.inMilliseconds}ms (attempt ${attempt + 1})');
    await Future<void>.delayed(delay);

    try {
      final Response<dynamic> response = await _dio.fetch<dynamic>(
        request.copyWith(extra: <String, dynamic>{...request.extra, 'attempt': attempt + 1}),
      );
      handler.resolve(response);
    } on DioException catch (error) {
      handler.next(error);
    }
  }

  bool _shouldRetry(DioException err, int attempt) {
    if (attempt >= maxAttempts - 1) {
      return false;
    }
    if (err.requestOptions.method.toUpperCase() != 'GET') {
      return false;
    }
    switch (err.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.connectionError:
      case DioExceptionType.transformTimeout:
        return true;
      case DioExceptionType.badResponse:
        final int? status = err.response?.statusCode;
        return status == 429 || (status != null && status >= 500);
      case DioExceptionType.cancel:
      case DioExceptionType.badCertificate:
      case DioExceptionType.unknown:
        return false;
    }
  }

  /// Exponential backoff with jitter, honouring `Retry-After` when the server sends one.
  Duration _delayFor(DioException err, int attempt) {
    final String? retryAfter = err.response?.headers.value('retry-after');
    if (retryAfter != null) {
      final int? seconds = int.tryParse(retryAfter.trim());
      if (seconds != null && seconds > 0) {
        return Duration(seconds: seconds.clamp(1, 30));
      }
    }
    final int backoffMs = baseDelay.inMilliseconds * (1 << attempt);
    final int jitter = Random().nextInt(baseDelay.inMilliseconds);
    return Duration(milliseconds: backoffMs + jitter);
  }
}
