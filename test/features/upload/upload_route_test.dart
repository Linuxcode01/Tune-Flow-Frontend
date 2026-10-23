import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuneflow/core/network/api_client.dart';
import 'package:tuneflow/features/upload/data/datasources/upload_remote_datasource.dart';
import 'package:tuneflow/features/upload/domain/entities/media_file.dart';
import 'package:tuneflow/features/upload/domain/entities/upload_result.dart';

/// Which route a file takes: one request, or chunks. This is what makes a large upload survive a
/// flaky connection, and it is a threshold rule - exactly the kind of thing that silently rots.
///
/// The API client is faked, so the test asserts the *decisions* (which endpoints, which parts, what
/// progress) rather than HTTP.
void main() {
  test('a small file goes up in a single request - no session traffic for a short track', () async {
    final _RecordingApiClient client = _RecordingApiClient();
    final UploadRemoteDataSource source = UploadRemoteDataSource(client, chunkThresholdBytes: 1024);

    await source.uploadAudio(_file(600));

    expect(client.multipartPaths, <String>['/uploads/audio']);
    expect(client.initiatePaths, isEmpty,
        reason: 'an initiate/complete pair would cost more requests than the upload itself');
  });

  test('a file at or above the threshold is chunked, in order, and completed once', () async {
    final _RecordingApiClient client = _RecordingApiClient();
    // 8-byte threshold and a 8-byte server chunk: 20 bytes is three parts (8, 8, 4).
    final UploadRemoteDataSource source = UploadRemoteDataSource(client, chunkThresholdBytes: 8);
    client.chunkSizeBytes = 8;

    final UploadResult result = await source.uploadAudio(_file(20));

    expect(client.initiatePaths, <String>['/uploads/audio/initiate']);
    expect(client.multipartPaths, isEmpty);
    expect(client.partPaths, <String>[
      '/uploads/audio/session-1/parts/1',
      '/uploads/audio/session-1/parts/2',
      '/uploads/audio/session-1/parts/3',
    ]);
    expect(client.partSizes, <int>[8, 8, 4]);
    expect(client.completePaths, <String>['/uploads/audio/session-1/complete']);
    expect(result.objectKey, 'audio/2026/10/stored.mp3');
  });

  test('fraction progress is monotonic and ends at 1 when the object is actually stored', () async {
    final _RecordingApiClient client = _RecordingApiClient()..chunkSizeBytes = 4;
    final UploadRemoteDataSource source = UploadRemoteDataSource(client, chunkThresholdBytes: 4);
    final List<double> progress = <double>[];

    await source.uploadAudio(_file(10), onProgress: progress.add);

    expect(progress.first, 0);
    expect(progress.last, 1);
    for (int i = 1; i < progress.length; i++) {
      expect(progress[i], greaterThanOrEqualTo(progress[i - 1]),
          reason: 'a progress bar that jumps backwards reads as a failed upload: $progress');
    }
  });
}

MediaFile _file(int size) => MediaFile(
      name: 'neon.mp3',
      sizeBytes: size,
      bytes: Uint8List.fromList(List<int>.filled(size, 7)),
    );

/// Records every endpoint the upload flow would have called, and answers with the wire shapes the
/// real API returns.
class _RecordingApiClient implements ApiClient {
  final List<String> multipartPaths = <String>[];
  final List<String> initiatePaths = <String>[];
  final List<String> partPaths = <String>[];
  final List<int> partSizes = <int>[];
  final List<String> completePaths = <String>[];

  int chunkSizeBytes = 1024 * 1024;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');

  @override
  Future<Map<String, dynamic>> postMultipart(
    String path, {
    required List<int> bytes,
    required String filename,
    String fieldName = 'file',
    String? contentType,
    Map<String, dynamic>? fields,
    ProgressCallback? onSendProgress,
    dynamic cancelToken,
  }) async {
    multipartPaths.add(path);
    onSendProgress?.call(bytes.length, bytes.length);
    return <String, dynamic>{'objectKey': 'audio/2026/10/small.mp3', 'sizeBytes': bytes.length};
  }

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Object? body,
    Map<String, dynamic>? queryParameters,
    dynamic cancelToken,
  }) async {
    if (path.endsWith('/initiate')) {
      initiatePaths.add(path);
      final Map<String, dynamic> request = body! as Map<String, dynamic>;
      final int size = (request['sizeBytes'] as num).toInt();
      return <String, dynamic>{
        'uploadId': 'session-1',
        'chunkSizeBytes': chunkSizeBytes,
        'partCount': (size + chunkSizeBytes - 1) ~/ chunkSizeBytes,
        'sizeBytes': size,
        'receivedParts': <int>[],
      };
    }
    completePaths.add(path);
    return <String, dynamic>{'objectKey': 'audio/2026/10/stored.mp3', 'durationSeconds': 214};
  }

  @override
  Future<void> putBytes(
    String path, {
    required List<int> bytes,
    String contentType = 'application/octet-stream',
    dynamic onSendProgress,
    dynamic cancelToken,
  }) async {
    partPaths.add(path);
    partSizes.add(bytes.length);
    onSendProgress?.call(bytes.length, bytes.length);
  }
}
