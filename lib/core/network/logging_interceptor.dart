import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:tuneflow/core/utils/app_logger.dart';

/// Request/response logging for local development.
///
/// Off in release builds (and never logs `Authorization` headers or audio bytes), because tokens in
/// log output are a real leak vector.
class LoggingInterceptor extends Interceptor {
  LoggingInterceptor({required this.enabled});

  final bool enabled;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (enabled && !kReleaseMode) {
      final String auth = options.headers.containsKey('Authorization') ? ' [auth]' : ' [anon]';
      AppLogger.debug('-> ${options.method} ${options.uri}$auth');
    }
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    if (enabled && !kReleaseMode) {
      AppLogger.debug(
        '<- ${response.statusCode} ${response.requestOptions.method} ${response.requestOptions.uri}',
      );
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (enabled && !kReleaseMode) {
      AppLogger.debug(
        'xx ${err.response?.statusCode ?? err.type.name} ${err.requestOptions.uri}',
      );
    }
    handler.next(err);
  }
}
