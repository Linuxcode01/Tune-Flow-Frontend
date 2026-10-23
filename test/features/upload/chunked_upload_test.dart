import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tuneflow/core/error/app_exception.dart';
import 'package:tuneflow/features/upload/data/services/chunked_audio_upload.dart';
import 'package:tuneflow/features/upload/domain/entities/media_file.dart';
import 'package:tuneflow/features/upload/domain/entities/upload_chunk.dart';
import 'package:tuneflow/features/upload/domain/entities/upload_result.dart';
import 'package:tuneflow/features/upload/domain/entities/upload_session.dart';

/// Chunked uploads: the slicing rule, the progress arithmetic, per-part retries and resume.
///
/// The transport is faked, so these tests exercise the part that can actually be wrong - the
/// orchestration - without a server, a socket or a file system.
void main() {
  group('planUploadChunks', () {
    test('slices into equal parts with the remainder last', () {
      final List<UploadChunk> chunks = planUploadChunks(totalBytes: 10, chunkSizeBytes: 4);

      expect(chunks.map((UploadChunk chunk) => chunk.length), <int>[4, 4, 2]);
      expect(chunks.map((UploadChunk chunk) => chunk.start), <int>[0, 4, 8]);
      expect(chunks.map((UploadChunk chunk) => chunk.end), <int>[4, 8, 10]);
      expect(chunks.map((UploadChunk chunk) => chunk.partNumber), <int>[1, 2, 3]);
    });

    test('an exact multiple does not produce an empty trailing part', () {
      final List<UploadChunk> chunks = planUploadChunks(totalBytes: 8, chunkSizeBytes: 4);
      expect(chunks.length, 2);
      expect(chunks.last.end, 8);
    });

    test('a file smaller than one chunk is a single part', () {
      expect(planUploadChunks(totalBytes: 3, chunkSizeBytes: 4).single.partNumber, 1);
    });

    test('nonsense inputs produce no parts rather than an infinite loop', () {
      expect(planUploadChunks(totalBytes: 0, chunkSizeBytes: 4), isEmpty);
      expect(planUploadChunks(totalBytes: 10, chunkSizeBytes: 0), isEmpty);
    });
  });

  group('ChunkedAudioUpload', () {
    test('sends every part in order and reports progress that only moves forward', () async {
      final _FakeTransport transport = _FakeTransport(chunkSizeBytes: 4);
      final List<double> progress = <double>[];

      final UploadResult result = await ChunkedAudioUpload(transport, retryDelay: Duration.zero)
          .upload(_file(10), onProgress: progress.add);

      expect(result.objectKey, 'audio/2026/10/stored.mp3');
      expect(transport.sentParts, <int>[1, 2, 3]);
      // Part 2 is 4 bytes of a 10-byte file, so the byte ranges are exact.
      expect(transport.sentSizes, <int>[4, 4, 2]);
      expect(transport.completed, isTrue);
      expect(progress.first, 0);
      expect(progress.last, 1);
      expect(_isMonotonic(progress), isTrue, reason: 'progress must never jump backwards: $progress');
      expect(progress.length, greaterThan(4), reason: 'mid-part progress is what makes the bar useful');
    });

    test('retries a failed part instead of giving up, and does not re-send the parts that landed', () async {
      final _FakeTransport transport = _FakeTransport(chunkSizeBytes: 4)
        ..failParts(<int>{2}, times: 2);

      await ChunkedAudioUpload(transport, retryDelay: Duration.zero).upload(_file(10));

      expect(transport.attemptsFor(2), 3, reason: 'two failures, then success');
      expect(transport.attemptsFor(1), 1);
      expect(transport.attemptsFor(3), 1);
      expect(transport.completed, isTrue);
    });

    test('skips parts the server already has - the resume path after a dropped connection', () async {
      final _FakeTransport transport = _FakeTransport(chunkSizeBytes: 4, receivedParts: <int>[1, 2]);

      await ChunkedAudioUpload(transport, retryDelay: Duration.zero).upload(_file(10));

      expect(transport.sentParts, <int>[3]);
      expect(transport.completed, isTrue);
    });

    test('gives up after the retry budget and discards the session rather than leaving parts behind',
        () async {
      final _FakeTransport transport = _FakeTransport(chunkSizeBytes: 4)..alwaysFailPart(2);

      await expectLater(
        ChunkedAudioUpload(transport, maxAttempts: 3, retryDelay: Duration.zero).upload(_file(10)),
        throwsA(isA<ApiException>()),
      );

      expect(transport.attemptsFor(2), 3);
      expect(transport.aborted, isTrue);
      expect(transport.completed, isFalse);
      expect(transport.sentParts, <int>[1], reason: 'part 3 is never reached after part 2 fails');
    });

    test('refuses a session that does not match the file instead of writing a corrupt object', () async {
      // A session opened for a 10-byte file cannot hold a 26-byte one: 3 parts vs 7.
      final _FakeTransport transport = _FakeTransport(chunkSizeBytes: 4, serverSizeBytes: 10);

      await expectLater(
        ChunkedAudioUpload(transport, retryDelay: Duration.zero).upload(_file(26)),
        throwsA(isA<SerializationException>()),
      );

      expect(transport.aborted, isTrue);
      expect(transport.sentParts, isEmpty);
    });

    test('treats an unusable session as a failure before sending anything', () async {
      final _FakeTransport transport = _FakeTransport(chunkSizeBytes: 0);

      await expectLater(
        ChunkedAudioUpload(transport, retryDelay: Duration.zero).upload(_file(10)),
        throwsA(isA<SerializationException>()),
      );
      expect(transport.sentParts, isEmpty);
    });
  });
}

bool _isMonotonic(List<double> values) {
  for (int i = 1; i < values.length; i++) {
    if (values[i] < values[i - 1]) {
      return false;
    }
  }
  return true;
}

MediaFile _file(int size) {
  return MediaFile(name: 'neon.mp3', sizeBytes: size, bytes: Uint8List.fromList(_bytes(size)));
}

List<int> _bytes(int size) => List<int>.generate(size, (int index) => index % 251);

class _FakeTransport implements ChunkedUploadTransport {
  _FakeTransport({
    required this.chunkSizeBytes,
    this.receivedParts = const <int>[],
    this.serverSizeBytes,
  });

  final int chunkSizeBytes;
  final List<int> receivedParts;

  /// Set to simulate a stale session that was opened for a different file size.
  final int? serverSizeBytes;

  final List<int> sentParts = <int>[];
  final List<int> sentSizes = <int>[];
  final Map<int, int> _attempts = <int, int>{};
  final Map<int, int> _failuresAllowed = <int, int>{};
  final Set<int> _alwaysFail = <int>{};
  bool completed = false;
  bool aborted = false;

  void failParts(Set<int> parts, {required int times}) {
    for (final int part in parts) {
      _failuresAllowed[part] = times;
    }
  }

  void alwaysFailPart(int part) => _alwaysFail.add(part);

  int attemptsFor(int part) => _attempts[part] ?? 0;

  @override
  Future<UploadSession> initiateUpload({
    required String fileName,
    required int sizeBytes,
    String? contentType,
  }) async {
    final int declared = serverSizeBytes ?? sizeBytes;
    final int partCount =
        chunkSizeBytes <= 0 ? 0 : (declared + chunkSizeBytes - 1) ~/ chunkSizeBytes;
    return UploadSession(
      uploadId: 'session-1',
      chunkSizeBytes: chunkSizeBytes,
      // The server plans from the size it was told, which is how a mismatch is detected.
      partCount: partCount,
      sizeBytes: sizeBytes,
      receivedParts: receivedParts,
    );
  }

  @override
  Future<void> sendPart({
    required String uploadId,
    required int partNumber,
    required List<int> bytes,
    void Function(int sent, int total)? onSendProgress,
  }) async {
    _attempts[partNumber] = attemptsFor(partNumber) + 1;

    if (_alwaysFail.contains(partNumber)) {
      throw const ApiException(
        message: 'Server exploded',
        errorCode: 'STORAGE_ERROR',
        statusCode: 502,
      );
    }
    final int allowed = _failuresAllowed[partNumber] ?? 0;
    if (attemptsFor(partNumber) <= allowed) {
      // Fail midway through the part: the progress bar must not keep that credit.
      onSendProgress?.call(bytes.length ~/ 2, bytes.length);
      throw const ApiException(
        message: 'Connection reset',
        errorCode: 'STORAGE_ERROR',
        statusCode: 502,
      );
    }

    onSendProgress?.call(bytes.length ~/ 2, bytes.length);
    onSendProgress?.call(bytes.length, bytes.length);
    sentParts.add(partNumber);
    sentSizes.add(bytes.length);
  }

  @override
  Future<UploadResult> completeUpload(String uploadId) async {
    completed = true;
    return const UploadResult(
      objectKey: 'audio/2026/10/stored.mp3',
      previewUrl: '/api/v1/media/stored.mp3',
      durationSeconds: 214,
      sizeBytes: 10,
    );
  }

  @override
  Future<void> abortUpload(String uploadId) async => aborted = true;
}
