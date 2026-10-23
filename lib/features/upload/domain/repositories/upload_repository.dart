import 'package:tuneflow/features/catalog/domain/entities/song.dart';
import 'package:tuneflow/features/upload/domain/entities/media_file.dart';
import 'package:tuneflow/features/upload/domain/entities/upload_result.dart';

/// Progress of a single upload, as a fraction between 0 and 1.
///
/// A plain callback rather than a Dio `ProgressCallback` so the domain layer stays free of transport
/// types - the same rule the rest of the app follows for repositories.
typedef UploadProgressCallback = void Function(double fraction);

/// The artist publishing flow: upload the media, then persist the metadata that points at it.
///
/// Two calls, in that order, mirroring the API: `POST /uploads/audio` stores bytes and returns an
/// `objectKey`, and `POST /songs` creates the catalogue entry with that key. Splitting them is what
/// allows a failed metadata call to be retried without re-uploading a 40 MB file.
abstract class UploadRepository {
  Future<UploadResult> uploadAudio(MediaFile file, {UploadProgressCallback? onProgress});

  Future<UploadResult> uploadImage(MediaFile file, {UploadProgressCallback? onProgress});

  Future<Song> createSong({
    required String title,
    required String audioObjectKey,
    required int durationSeconds,
    String? coverImageObjectKey,
    String? albumId,
    int? trackNumber,
    DateTime? releaseDate,
    bool explicit,
    Set<String> genreSlugs,
  });
}
