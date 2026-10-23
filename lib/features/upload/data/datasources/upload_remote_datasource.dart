import 'package:dio/dio.dart';
import 'package:tuneflow/core/constants/api_endpoints.dart';
import 'package:tuneflow/core/network/api_client.dart';
import 'package:tuneflow/features/catalog/domain/entities/song.dart';
import 'package:tuneflow/features/upload/data/services/chunked_audio_upload.dart';
import 'package:tuneflow/features/upload/domain/entities/media_file.dart';
import 'package:tuneflow/features/upload/domain/entities/upload_result.dart';
import 'package:tuneflow/features/upload/domain/entities/upload_session.dart';
import 'package:tuneflow/features/upload/domain/repositories/upload_repository.dart';

/// Talks to the endpoints the publishing flow needs.
///
/// Everything here is a thin translation between the API's wire shapes and the upload feature's
/// models; the interesting decisions (validation, provider invalidation) live in the controller,
/// and the chunking policy lives in [ChunkedAudioUpload].
class UploadRemoteDataSource implements ChunkedUploadTransport {
  const UploadRemoteDataSource(this._client, {this.chunkThresholdBytes = _chunkThresholdDefault});

  /// Below this, one request is simply better: the round trips an initiate/complete pair costs are
  /// not worth saving a single small POST.
  static const int _chunkThresholdDefault = 2 * 1024 * 1024;

  /// Chunked uploads are demonstrated and tested by lowering this, which is also how the widget and
  /// repository tests drive the chunked path with a tiny fixture.
  final int chunkThresholdBytes;

  final ApiClient _client;

  /// The audio upload route for this file: chunked when it is big enough to be worth protecting
  /// against a mid-transfer failure, single-shot when it is not.
  Future<UploadResult> uploadAudio(
    MediaFile file, {
    ProgressCallback? onRequestProgress,
    UploadProgressCallback? onProgress,
  }) async {
    if (file.bytes.length < chunkThresholdBytes) {
      final Map<String, dynamic> data = await _client.postMultipart(
        ApiEndpoints.uploadAudio,
        bytes: file.bytes,
        filename: file.name,
        onSendProgress: onRequestProgress,
      );
      return UploadResult.fromJson(data);
    }
    return ChunkedAudioUpload(this).upload(file, onProgress: onProgress);
  }

  Future<UploadResult> uploadImage(MediaFile file, {ProgressCallback? onProgress}) async {
    final Map<String, dynamic> data = await _client.postMultipart(
      ApiEndpoints.uploadImage,
      bytes: file.bytes,
      filename: file.name,
      onSendProgress: onProgress,
    );
    return UploadResult.fromJson(data);
  }

  // -----------------------------------------------------------------------------------------------
  // ChunkedUploadTransport
  // -----------------------------------------------------------------------------------------------

  @override
  Future<UploadSession> initiateUpload({
    required String fileName,
    required int sizeBytes,
    String? contentType,
  }) async {
    final Map<String, dynamic> data = await _client.post(
      ApiEndpoints.uploadAudioInitiate,
      body: <String, dynamic>{
        'fileName': fileName,
        'sizeBytes': sizeBytes,
        if (contentType != null) 'contentType': contentType,
      },
    );
    return UploadSession.fromJson(data);
  }

  @override
  Future<void> sendPart({
    required String uploadId,
    required int partNumber,
    required List<int> bytes,
    void Function(int sent, int total)? onSendProgress,
  }) async {
    await _client.putBytes(
      ApiEndpoints.uploadAudioPart(uploadId, partNumber),
      bytes: bytes,
      onSendProgress: onSendProgress,
    );
  }

  @override
  Future<UploadResult> completeUpload(String uploadId) async {
    final Map<String, dynamic> data =
        await _client.post(ApiEndpoints.uploadAudioComplete(uploadId));
    return UploadResult.fromJson(data);
  }

  @override
  Future<void> abortUpload(String uploadId) =>
      _client.delete(ApiEndpoints.uploadAudioSession(uploadId));

  /// Which parts the server already holds (the resume path).
  Future<UploadSession> uploadSessionStatus(String uploadId) async {
    final Map<String, dynamic> data = await _client.getJson(ApiEndpoints.uploadAudioSession(uploadId));
    return UploadSession.fromJson(data);
  }

  // -----------------------------------------------------------------------------------------------

  /// `POST /songs`.
  ///
  /// `artistId` is deliberately omitted: the API derives the artist profile from the access token for
  /// an artist account, and sending an id the caller does not own is how a client ends up silently
  /// publishing under the wrong name.
  Future<Song> createSong({
    required String title,
    required String audioObjectKey,
    required int durationSeconds,
    String? coverImageObjectKey,
    String? albumId,
    int? trackNumber,
    DateTime? releaseDate,
    bool explicit = false,
    Set<String> genreSlugs = const <String>{},
  }) async {
    final Map<String, dynamic> data = await _client.post(
      ApiEndpoints.songs,
      body: <String, dynamic>{
        'title': title,
        'durationSeconds': durationSeconds,
        'audioObjectKey': audioObjectKey,
        if (coverImageObjectKey != null) 'coverImageObjectKey': coverImageObjectKey,
        if (albumId != null) 'albumId': albumId,
        if (trackNumber != null) 'trackNumber': trackNumber,
        if (releaseDate != null) 'releaseDate': _isoDate(releaseDate),
        'explicit': explicit,
        if (genreSlugs.isNotEmpty) 'genres': genreSlugs.toList(growable: false),
      },
    );
    return Song.fromJson(data);
  }

  /// `yyyy-MM-dd`: the API models release dates as `LocalDate`, and a full ISO timestamp is rejected.
  String _isoDate(DateTime date) {
    final String month = date.month.toString().padLeft(2, '0');
    final String day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
