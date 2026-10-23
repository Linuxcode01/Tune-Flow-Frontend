import 'package:dio/dio.dart';
import 'package:tuneflow/features/catalog/domain/entities/song.dart';
import 'package:tuneflow/features/upload/data/datasources/upload_remote_datasource.dart';
import 'package:tuneflow/features/upload/domain/entities/media_file.dart';
import 'package:tuneflow/features/upload/domain/entities/upload_result.dart';
import 'package:tuneflow/features/upload/domain/repositories/upload_repository.dart';

class UploadRepositoryImpl implements UploadRepository {
  const UploadRepositoryImpl(this._remote);

  final UploadRemoteDataSource _remote;

  /// Audio may go up in one request or in chunks, depending on size; both paths report progress as
  /// a fraction, so the caller does not care which one ran.
  @override
  Future<UploadResult> uploadAudio(MediaFile file, {UploadProgressCallback? onProgress}) =>
      _remote.uploadAudio(
        file,
        onRequestProgress: _toDioProgress(onProgress),
        onProgress: onProgress,
      );

  @override
  Future<UploadResult> uploadImage(MediaFile file, {UploadProgressCallback? onProgress}) =>
      _remote.uploadImage(file, onProgress: _toDioProgress(onProgress));

  @override
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
  }) =>
      _remote.createSong(
        title: title,
        audioObjectKey: audioObjectKey,
        durationSeconds: durationSeconds,
        coverImageObjectKey: coverImageObjectKey,
        albumId: albumId,
        trackNumber: trackNumber,
        releaseDate: releaseDate,
        explicit: explicit,
        genreSlugs: genreSlugs,
      );

  /// Dio reports bytes transferred; the form wants a fraction. Guarding the divide keeps a
  /// zero-length total (which the browser transport reports before the request starts) from
  /// producing `NaN` in a progress bar.
  ProgressCallback? _toDioProgress(UploadProgressCallback? onProgress) {
    if (onProgress == null) {
      return null;
    }
    return (int sent, int total) {
      if (total <= 0) {
        onProgress(0);
        return;
      }
      onProgress((sent / total).clamp(0, 1).toDouble());
    };
  }
}
