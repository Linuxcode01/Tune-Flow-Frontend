import 'package:dio/dio.dart';

/// A single field-level validation error returned by the backend.
class FieldError {
  const FieldError({required this.field, required this.message, this.rejectedValue});

  final String field;
  final String message;
  final String? rejectedValue;

  @override
  String toString() => '$field: $message';
}

/// Base type for every failure the client can surface.
///
/// Features catch [AppException] (or let it bubble into an `AsyncValue.error`) and render
/// [message]; they never inspect `DioException` directly, which keeps HTTP details out of the UI
/// layer and makes the error paths unit-testable.
///
/// `message` is a *named* parameter on every subclass so that each one can forward it with a super
/// parameter and still supply its own default plus an error code.
sealed class AppException implements Exception {
  const AppException({required this.message, this.errorCode});

  /// Human-readable, already-safe to display.
  final String message;

  /// Stable machine-readable code (`UNAUTHENTICATED`, `RATE_LIMIT_EXCEEDED`, ...).
  final String? errorCode;

  /// True when retrying the same request could plausibly succeed.
  bool get isRetryable => false;

  @override
  String toString() => '$runtimeType($errorCode): $message';
}

/// The server answered, but with an error envelope.
class ApiException extends AppException {
  const ApiException({
    required super.message,
    required super.errorCode,
    required this.statusCode,
    this.path,
    this.fieldErrors = const <FieldError>[],
  });

  final int statusCode;
  final String? path;
  final List<FieldError> fieldErrors;

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isConflict => statusCode == 409;
  bool get isRateLimited => statusCode == 429;

  @override
  bool get isRetryable => statusCode == 429 || statusCode >= 500;

  /// Convenience for forms: the message for a given field, when the server flagged one.
  String? messageFor(String field) {
    for (final FieldError error in fieldErrors) {
      if (error.field == field) {
        return error.message;
      }
    }
    return null;
  }

  /// Builds the rich exception from a Dio error that carried the error envelope.
  static ApiException fromResponse(Response<dynamic> response, {required String path}) {
    final dynamic body = response.data;
    if (body is Map<String, dynamic>) {
      return ApiException(
        message: (body['message'] as String?) ?? _fallbackMessage(response.statusCode),
        errorCode: (body['errorCode'] as String?) ?? 'HTTP_${response.statusCode}',
        statusCode: response.statusCode ?? 0,
        path: (body['path'] as String?) ?? path,
        fieldErrors: (body['fieldErrors'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(
              (Map<String, dynamic> e) => FieldError(
                field: (e['field'] as String?) ?? '',
                message: (e['message'] as String?) ?? 'Invalid value',
              ),
            )
            .toList(growable: false),
      );
    }
    return ApiException(
      message: _fallbackMessage(response.statusCode),
      errorCode: 'HTTP_${response.statusCode}',
      statusCode: response.statusCode ?? 0,
      path: path,
    );
  }

  static String _fallbackMessage(int? statusCode) {
    switch (statusCode) {
      case 400:
        return 'That request could not be processed.';
      case 401:
        return 'Your session has expired. Please sign in again.';
      case 403:
        return 'You do not have access to that.';
      case 404:
        return 'We could not find what you were looking for.';
      case 409:
        return 'That already exists.';
      case 413:
        return 'That file is too large.';
      case 429:
        return 'You are doing that too quickly. Please wait a moment.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }
}

/// The request never reached the server, or the connection dropped.
class NetworkException extends AppException {
  const NetworkException({
    super.message = 'No connection. Check your network and try again.',
    this.timeout = false,
  }) : super(errorCode: 'NETWORK_ERROR');

  final bool timeout;

  @override
  bool get isRetryable => true;
}

/// The server answered 200 but the payload did not match the expected contract.
class SerializationException extends AppException {
  const SerializationException({
    super.message = 'We received an unexpected response.',
  }) : super(errorCode: 'SERIALIZATION_ERROR');
}

/// The stored session is no longer valid; the app must return to the login screen.
class SessionExpiredException extends AppException {
  const SessionExpiredException({super.message = 'Please sign in again.'})
      : super(errorCode: 'SESSION_EXPIRED');
}

/// An upload of bytes (chunked or single-shot) did not complete.
///
/// Retryable by definition: the file is still on the device, so the artist can simply try again -
/// which is exactly what the upload screen offers.
class UploadException extends AppException {
  const UploadException({super.message = 'The upload did not finish. Please try again.'})
      : super(errorCode: 'UPLOAD_FAILED');

  @override
  bool get isRetryable => true;
}

/// The local device refused the operation (storage full, permission denied, audio init failure).
class DeviceException extends AppException {
  const DeviceException(String message)
      : super(message: message, errorCode: 'DEVICE_ERROR');
}

/// Maps any thrown object onto an [AppException] so the UI layer always has a message to show.
AppException toAppException(Object error, [StackTrace? stackTrace]) {
  if (error is AppException) {
    return error;
  }
  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const NetworkException(
          message: 'The server took too long to respond.',
          timeout: true,
        );
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        return const NetworkException();
      case DioExceptionType.cancel:
        return const NetworkException(
          message: 'Request cancelled.',
        );
      case DioExceptionType.badCertificate:
        return const NetworkException(
          message: 'The secure connection could not be verified.',
        );
      case DioExceptionType.badResponse:
        final Response<dynamic>? response = error.response;
        if (response != null) {
          return ApiException.fromResponse(response, path: response.requestOptions.path);
        }
        return const NetworkException();
    }
  }
  return const ApiException(
    message: 'Something went wrong. Please try again.',
    errorCode: 'UNEXPECTED',
    statusCode: 0,
  );
}
