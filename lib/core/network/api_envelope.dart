import 'package:tuneflow/core/error/app_exception.dart';

/// Parser for the backend's response envelope (docs section 10).
///
/// The API always answers with one of two shapes:
///
/// ```json
/// { "success": true,  "message": "...", "data": {...}, "timestamp": "..." }
/// { "success": false, "message": "...", "errorCode": "...", "fieldErrors": [...] }
/// ```
///
/// Unwrapping happens in exactly one place so every repository receives plain payloads and every
/// error reaches the UI as a typed [AppException] with a code the presentation layer can switch on.
class ApiEnvelope {
  const ApiEnvelope._();

  /// Extracts `data` from a successful envelope.
  ///
  /// Handles the two shapes the backend can return: the standard envelope and (defensively) a raw
  /// payload, so a proxy that strips the wrapper cannot break the app.
  static dynamic unwrap(dynamic body, {int? statusCode, required String path}) {
    if (body == null) {
      return null;
    }
    if (body is! Map<String, dynamic>) {
      return body;
    }
    if (!body.containsKey('success')) {
      return body;
    }

    final bool success = body['success'] == true;
    final String message = (body['message'] as String?)?.trim().isNotEmpty == true
        ? body['message'] as String
        : (success ? 'Request completed' : 'Request failed');

    if (success) {
      return body['data'];
    }

    throw ApiException(
      message: message,
      errorCode: (body['errorCode'] as String?) ?? 'UNKNOWN',
      statusCode: statusCode ?? 400,
      path: (body['path'] as String?) ?? path,
      fieldErrors: _parseFieldErrors(body['fieldErrors']),
    );
  }

  static List<FieldError> _parseFieldErrors(dynamic raw) {
    if (raw is! List) {
      return const <FieldError>[];
    }
    return raw
        .whereType<Map<String, dynamic>>()
        .map(
          (Map<String, dynamic> entry) => FieldError(
            field: (entry['field'] as String?) ?? '',
            message: (entry['message'] as String?) ?? 'Invalid value',
            rejectedValue: entry['rejectedValue']?.toString(),
          ),
        )
        .toList(growable: false);
  }
}
