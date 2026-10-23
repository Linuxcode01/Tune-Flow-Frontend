import 'package:dio/dio.dart';
import 'package:tuneflow/core/config/app_config.dart';
import 'package:tuneflow/core/error/app_exception.dart';
import 'package:tuneflow/core/network/api_envelope.dart';
import 'package:tuneflow/core/network/paged_response.dart';
import 'package:tuneflow/core/utils/app_logger.dart';

/// Typed wrapper around the shared [Dio] instance.
///
/// Repositories depend on this instead of Dio so that envelope unwrapping, error translation and
/// logging live in one place (docs section 10). Every method returns already-unwrapped payloads.
class ApiClient {
  ApiClient({required Dio dio, required AppConfig config})
      : _dio = dio,
        _config = config;

  final Dio _dio;
  final AppConfig _config;

  /// GET returning a JSON object.
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
  }) async {
    final dynamic data = await _request<dynamic>(
      () => _dio.get<dynamic>(path, queryParameters: queryParameters, cancelToken: cancelToken),
      path: path,
    );
    return _asMap(data, path);
  }

  /// GET returning a list of JSON objects (endpoints that are not paginated).
  Future<List<Map<String, dynamic>>> getList(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
  }) async {
    final dynamic data = await _request<dynamic>(
      () => _dio.get<dynamic>(path, queryParameters: queryParameters, cancelToken: cancelToken),
      path: path,
    );
    return _asListOfMaps(data, path);
  }

  /// GET returning the standard pagination envelope, already mapped to [T].
  Future<PagedResponse<T>> getPaged<T>(
    String path, {
    required T Function(Map<String, dynamic> json) itemMapper,
    int? page,
    int? size,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
  }) async {
    final Map<String, dynamic> query = <String, dynamic>{
      if (page != null) 'page': page,
      // Always send an explicit size: the API's Pageable defaults would otherwise differ from the
      // client's expectations as soon as one side changes.
      'size': size ?? _config.pageSize,
      ...?queryParameters,
    };
    final dynamic data = await _request<dynamic>(
      () => _dio.get<dynamic>(path, queryParameters: query, cancelToken: cancelToken),
      path: path,
    );
    if (data is! Map<String, dynamic>) {
      throw SerializationException(message: 'Expected a paginated payload from $path.');
    }
    return PagedResponse.fromJson(data, itemMapper);
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Object? body,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
  }) async {
    final dynamic data = await _request<dynamic>(
      () => _dio.post<dynamic>(path, data: body, queryParameters: queryParameters, cancelToken: cancelToken),
      path: path,
    );
    return _asMap(data, path);
  }

  /// POST a `multipart/form-data` request - the shape every upload endpoint expects.
  ///
  /// [bytes] is used rather than a file path so the same code works on Android/iOS (where the picker
  /// returns a path) and on the web (where it returns bytes): reading the file is the caller's job,
  /// which also keeps this method testable without touching the filesystem.
  Future<Map<String, dynamic>> postMultipart(
    String path, {
    required List<int> bytes,
    required String filename,
    String fieldName = 'file',
    String? contentType,
    Map<String, dynamic>? fields,
    ProgressCallback? onSendProgress,
    CancelToken? cancelToken,
  }) async {
    final FormData form = FormData.fromMap(<String, dynamic>{
      ...?fields,
      fieldName: MultipartFile.fromBytes(
        bytes,
        filename: filename,
        contentType: _mediaType(contentType, filename),
      ),
    });
    final dynamic data = await _request<dynamic>(
      () => _dio.post<dynamic>(
        path,
        data: form,
        onSendProgress: onSendProgress,
        cancelToken: cancelToken,
        // Let Dio set the multipart boundary itself: a hand-written header here is the classic
        // "file arrives empty" bug.
        options: Options(contentType: 'multipart/form-data'),
      ),
      path: path,
    );
    return _asMap(data, path);
  }

  /// PUT a raw binary body - one chunk of a chunked upload.
  ///
  /// No multipart envelope: the server asks for `application/octet-stream`, and re-encoding a 4 MB
  /// chunk into multipart on every part would add framing bytes and another parser to the hot path.
  Future<void> putBytes(
    String path, {
    required List<int> bytes,
    String contentType = 'application/octet-stream',
    ProgressCallback? onSendProgress,
    CancelToken? cancelToken,
  }) async {
    await _request<dynamic>(
      () => _dio.put<dynamic>(
        path,
        data: bytes,
        onSendProgress: onSendProgress,
        cancelToken: cancelToken,
        options: Options(contentType: contentType),
      ),
      path: path,
    );
  }

  Future<Map<String, dynamic>> put(
    String path, {
    Object? body,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
  }) async {
    final dynamic data = await _request<dynamic>(
      () => _dio.put<dynamic>(path, data: body, queryParameters: queryParameters, cancelToken: cancelToken),
      path: path,
    );
    return _asMap(data, path);
  }

  Future<Map<String, dynamic>> patch(
    String path, {
    Object? body,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
  }) async {
    final dynamic data = await _request<dynamic>(
      () => _dio.patch<dynamic>(path, data: body, queryParameters: queryParameters, cancelToken: cancelToken),
      path: path,
    );
    return _asMap(data, path);
  }

  /// DELETE, tolerating `data: null` responses (the API replies with `data: null` on deletes).
  Future<void> delete(
    String path, {
    Object? body,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
  }) async {
    await _request<dynamic>(
      () => _dio.delete<dynamic>(path, data: body, queryParameters: queryParameters, cancelToken: cancelToken),
      path: path,
    );
  }

  /// Sends a request and translates every failure into an [AppException].
  Future<T> _request<T>(Future<Response<T>> Function() send, {required String path}) async {
    try {
      final Response<T> response = await send();
      final dynamic unwrapped = ApiEnvelope.unwrap(response.data, statusCode: response.statusCode, path: path);
      return unwrapped as T;
    } on DioException catch (error, stackTrace) {
      final AppException mapped = toAppException(error);
      AppLogger.debug('API $path failed -> $mapped');
      Error.throwWithStackTrace(mapped, stackTrace);
    }
  }

  Map<String, dynamic> _asMap(dynamic data, String path) {
    if (data == null) {
      return <String, dynamic>{};
    }
    if (data is Map<String, dynamic>) {
      return data;
    }
    throw SerializationException(message: 'Expected a JSON object from $path.');
  }

  /// `'audio/mpeg'` -> `MediaType('audio', 'mpeg')`, falling back to a guess from the extension.
  ///
  /// The backend validates uploads by extension, but sends the content type on to storage, and a
  /// wrong one makes the file unplayable in a browser.
  DioMediaType _mediaType(String? contentType, String filename) {
    final String? source = contentType ?? _contentTypeForExtension(filename);
    if (source == null || !source.contains('/')) {
      return DioMediaType('application', 'octet-stream');
    }
    final List<String> parts = source.split('/');
    return DioMediaType(parts.first, parts.sublist(1).join('/'));
  }

  String? _contentTypeForExtension(String filename) {
    final int dot = filename.lastIndexOf('.');
    if (dot < 0) {
      return null;
    }
    switch (filename.substring(dot + 1).toLowerCase()) {
      case 'mp3':
        return 'audio/mpeg';
      case 'm4a':
        return 'audio/mp4';
      case 'aac':
        return 'audio/aac';
      case 'wav':
        return 'audio/wav';
      case 'flac':
        return 'audio/flac';
      case 'ogg':
        return 'audio/ogg';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      default:
        return null;
    }
  }

  List<Map<String, dynamic>> _asListOfMaps(dynamic data, String path) {
    if (data is List) {
      return data.whereType<Map<String, dynamic>>().toList(growable: false);
    }
    throw SerializationException(message: 'Expected a JSON array from $path.');
  }
}
