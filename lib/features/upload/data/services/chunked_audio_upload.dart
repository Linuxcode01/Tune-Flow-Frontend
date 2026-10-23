import 'dart:typed_data';

import 'package:tuneflow/core/error/app_exception.dart';
import 'package:tuneflow/core/utils/app_logger.dart';
import 'package:tuneflow/features/upload/domain/entities/media_file.dart';
import 'package:tuneflow/features/upload/domain/entities/upload_chunk.dart';
import 'package:tuneflow/features/upload/domain/entities/upload_result.dart';
import 'package:tuneflow/features/upload/domain/entities/upload_session.dart';
import 'package:tuneflow/features/upload/domain/repositories/upload_repository.dart';

/// The four HTTP calls a chunked upload needs, as an interface.
///
/// Narrow on purpose: the orchestration below (slicing, progress, retries, resume) is the part worth
/// testing, and it can be tested against a fake transport without a server, a Dio instance or a
/// socket.
abstract class ChunkedUploadTransport {
  Future<UploadSession> initiateUpload({
    required String fileName,
    required int sizeBytes,
    String? contentType,
  });

  /// [onSendProgress] reports bytes of *this part* already sent - the caller turns that into overall
  /// progress, because only it knows where the part sits in the file.
  Future<void> sendPart({
    required String uploadId,
    required int partNumber,
    required List<int> bytes,
    void Function(int sent, int total)? onSendProgress,
  });

  Future<UploadResult> completeUpload(String uploadId);

  Future<void> abortUpload(String uploadId);
}

/// Uploads one audio file as a sequence of parts.
///
/// Why not one request: a 40 MB POST over a phone connection is all-or-nothing. Losing the last 10%
/// means starting again, and there is nothing useful to show in the UI in the meantime. Chunking
/// gives three things - real progress, per-part retries that only re-send what failed, and a resume
/// path when the app is killed mid-upload (the session on the server remembers the parts it has).
///
/// Ordering is deliberate: parts go up **sequentially**. Parallel parts would finish sooner on a
/// fast link but saturate a mobile uplink, turn one timeout into several, and make the progress bar
/// lie. Retries are per part, with a short growing delay, and a part that fails every attempt aborts
/// the whole session instead of leaving an orphan behind.
class ChunkedAudioUpload {
  const ChunkedAudioUpload(
    this._transport, {
    this.maxAttempts = 3,
    this.retryDelay = const Duration(milliseconds: 600),
  });

  final ChunkedUploadTransport _transport;
  final int maxAttempts;
  final Duration retryDelay;

  Future<UploadResult> upload(MediaFile file, {UploadProgressCallback? onProgress}) async {
    final int totalBytes = file.bytes.length;
    onProgress?.call(0);

    final UploadSession session = await _transport.initiateUpload(
      fileName: file.name,
      sizeBytes: file.sizeBytes,
      contentType: _contentTypeFor(file),
    );
    if (!session.isUsable) {
      throw const SerializationException(message: 'The server did not return a usable upload session.');
    }

    final List<UploadChunk> chunks = planUploadChunks(
      totalBytes: totalBytes,
      chunkSizeBytes: session.chunkSizeBytes,
    );
    if (chunks.length != session.partCount) {
      // The session was opened for a different file (a stale session id, or the file changed between
      // initiate and upload). Failing loudly beats writing a corrupt object.
      await _abortQuietly(session.uploadId);
      throw SerializationException(
        message: 'Upload session expects ${session.partCount} parts but the file needs ${chunks.length}.',
      );
    }

    final Set<int> alreadyStored = session.receivedPartSet;
    if (alreadyStored.isNotEmpty) {
      AppLogger.debug('Resuming upload ${session.uploadId}: ${alreadyStored.length} part(s) already stored');
    }

    int committedBytes = chunks
        .where((UploadChunk chunk) => alreadyStored.contains(chunk.partNumber))
        .fold(0, (int sum, UploadChunk chunk) => sum + chunk.length);
    onProgress?.call(_fraction(committedBytes, totalBytes));

    for (final UploadChunk chunk in chunks) {
      if (alreadyStored.contains(chunk.partNumber)) {
        continue;
      }
      final Uint8List slice = Uint8List.sublistView(file.bytes, chunk.start, chunk.end);
      await _sendWithRetries(session.uploadId, chunk, slice, (int sent) {
        onProgress?.call(_fraction(committedBytes + sent, totalBytes));
      });
      committedBytes += chunk.length;
      onProgress?.call(_fraction(committedBytes, totalBytes));
    }

    final UploadResult result = await _transport.completeUpload(session.uploadId);
    // The assembled object is only guaranteed to exist after `complete`, so 100% means "stored",
    // not "bytes sent" - which is also what the UI label claims.
    onProgress?.call(1);
    return result;
  }

  Future<void> _sendWithRetries(
    String uploadId,
    UploadChunk chunk,
    Uint8List bytes,
    void Function(int sent) onPartProgress,
  ) async {
    Object? lastError;
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        await _transport.sendPart(
          uploadId: uploadId,
          partNumber: chunk.partNumber,
          bytes: bytes,
          onSendProgress: (int sent, int _) => onPartProgress(sent),
        );
        return;
      } catch (error) {
        lastError = error;
        if (attempt == maxAttempts) {
          break;
        }
        AppLogger.warn(
          'Part ${chunk.partNumber} failed (attempt $attempt/$maxAttempts); retrying',
          error: error,
        );
        // A part that failed mid-flight leaves its progress behind; reset the bar to what is really
        // stored so it never shows more than the server has.
        onPartProgress(0);
        await Future<void>.delayed(retryDelay * attempt);
      }
    }

    // Every attempt failed: drop the session rather than leaving gigabytes of parts on the server
    // for a purge job to find later.
    await _abortQuietly(uploadId);
    throw lastError is AppException
        ? lastError
        : UploadException(message: 'Uploading part ${chunk.partNumber} failed after $maxAttempts attempts.');
  }

  Future<void> _abortQuietly(String uploadId) async {
    try {
      await _transport.abortUpload(uploadId);
    } catch (error) {
      // Best effort: the session TTL sweep on the server is the backstop.
      AppLogger.debug('Could not discard upload session $uploadId: $error');
    }
  }

  double _fraction(int done, int total) =>
      total <= 0 ? 0 : (done / total).clamp(0, 1).toDouble();

  /// Best-effort content type from the extension: the API validates by extension anyway, and this is
  /// only used for the metadata it stores alongside the object.
  String? _contentTypeFor(MediaFile file) {
    switch (file.extension) {
      case 'mp3':
        return 'audio/mpeg';
      case 'm4a':
      case 'aac':
        return 'audio/mp4';
      case 'wav':
        return 'audio/wav';
      case 'flac':
        return 'audio/flac';
      case 'ogg':
        return 'audio/ogg';
      default:
        return null;
    }
  }
}
