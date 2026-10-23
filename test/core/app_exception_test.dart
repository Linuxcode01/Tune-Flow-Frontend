import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuneflow/core/error/app_exception.dart';
import 'package:tuneflow/core/network/api_envelope.dart';

/// Envelope parsing and error translation are the seams where a backend change becomes a user-visible
/// bug, so they are tested directly rather than through a screen.
void main() {
  group('ApiEnvelope.unwrap', () {
    test('returns the payload of a successful envelope', () {
      final dynamic data = ApiEnvelope.unwrap(
        <String, dynamic>{
          'success': true,
          'message': 'Songs fetched successfully',
          'data': <String, dynamic>{'id': 'song-1'},
          'timestamp': '2026-10-06T09:15:04.221Z',
        },
        path: '/songs/song-1',
      );

      expect((data as Map<String, dynamic>)['id'], 'song-1');
    });

    test('throws a typed exception for an error envelope', () {
      expect(
        () => ApiEnvelope.unwrap(
          <String, dynamic>{
            'success': false,
            'message': 'Authentication required',
            'errorCode': 'UNAUTHENTICATED',
            'path': '/api/v1/users/me',
            'timestamp': '2026-10-06T09:15:04.221Z',
          },
          statusCode: 401,
          path: '/users/me',
        ),
        throwsA(
          isA<ApiException>()
              .having((ApiException e) => e.errorCode, 'errorCode', 'UNAUTHENTICATED')
              .having((ApiException e) => e.statusCode, 'statusCode', 401)
              .having((ApiException e) => e.isUnauthorized, 'isUnauthorized', isTrue)
              .having((ApiException e) => e.message, 'message', 'Authentication required'),
        ),
      );
    });

    test('carries field-level validation details', () {
      try {
        ApiEnvelope.unwrap(
          <String, dynamic>{
            'success': false,
            'message': 'Validation failed',
            'errorCode': 'VALIDATION_FAILED',
            'fieldErrors': <dynamic>[
              <String, dynamic>{
                'field': 'email',
                'message': 'Email must be valid',
                'rejectedValue': 'not-an-email',
              },
            ],
          },
          statusCode: 400,
          path: '/auth/register',
        );
        fail('expected an ApiException');
      } on ApiException catch (error) {
        expect(error.fieldErrors, hasLength(1));
        expect(error.messageFor('email'), 'Email must be valid');
        expect(error.messageFor('password'), isNull);
      }
    });

    test('tolerates a bare payload from a proxy that stripped the envelope', () {
      final dynamic data = ApiEnvelope.unwrap(<String, dynamic>{'id': 'song-9'}, path: '/songs/9');
      expect((data as Map<String, dynamic>)['id'], 'song-9');
    });
  });

  group('toAppException', () {
    test('passes through an existing AppException', () {
      const NetworkException original = NetworkException();
      expect(toAppException(original), same(original));
    });

    test('maps a connection error to a retryable network failure', () {
      final AppException mapped = toAppException(
        DioException(
          requestOptions: RequestOptions(path: '/home'),
          type: DioExceptionType.connectionError,
        ),
      );

      expect(mapped, isA<NetworkException>());
      expect(mapped.isRetryable, isTrue);
      expect(mapped.errorCode, 'NETWORK_ERROR');
    });

    test('maps a timeout to a retryable, time-specific failure', () {
      final AppException mapped = toAppException(
        DioException(
          requestOptions: RequestOptions(path: '/home'),
          type: DioExceptionType.receiveTimeout,
        ),
      );

      expect(mapped, isA<NetworkException>());
      expect((mapped as NetworkException).timeout, isTrue);
    });

    test('maps a 429 response to a rate-limit error that the UI can retry', () {
      final AppException mapped = toAppException(
        DioException(
          requestOptions: RequestOptions(path: '/auth/login'),
          type: DioExceptionType.badResponse,
          response: Response<dynamic>(
            requestOptions: RequestOptions(path: '/auth/login'),
            statusCode: 429,
            data: <String, dynamic>{
              'success': false,
              'message': 'Too many requests',
              'errorCode': 'RATE_LIMIT_EXCEEDED',
            },
          ),
        ),
      );

      expect(mapped, isA<ApiException>());
      expect((mapped as ApiException).isRateLimited, isTrue);
      expect(mapped.isRetryable, isTrue);
      // A 4xx from the rate limiter must not be mistaken for a dead session.
      expect(mapped.isUnauthorized, isFalse);
    });

    test('never leaks an unknown object as a bare exception', () {
      final AppException mapped = toAppException(StateError('boom'));
      expect(mapped.errorCode, 'UNEXPECTED');
      expect(mapped.message, isNotEmpty);
    });
  });
}
