import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tuneflow/core/error/app_exception.dart';
import 'package:tuneflow/core/network/paged_response.dart';
import 'package:tuneflow/core/providers/core_providers.dart';
import 'package:tuneflow/features/auth/presentation/providers/auth_providers.dart';
import 'package:tuneflow/features/catalog/domain/entities/album.dart';
import 'package:tuneflow/features/catalog/domain/entities/song.dart';
import 'package:tuneflow/features/catalog/presentation/providers/catalog_providers.dart';
import 'package:tuneflow/features/upload/data/datasources/upload_remote_datasource.dart';
import 'package:tuneflow/features/upload/data/repositories/upload_repository_impl.dart';
import 'package:tuneflow/features/upload/data/services/file_picker_media_picker.dart';
import 'package:tuneflow/features/upload/domain/entities/media_file.dart';
import 'package:tuneflow/features/upload/domain/entities/upload_result.dart';
import 'package:tuneflow/features/upload/domain/entities/upload_state.dart';
import 'package:tuneflow/features/upload/domain/repositories/upload_repository.dart';
import 'package:tuneflow/features/upload/domain/services/media_picker.dart';

final Provider<UploadRemoteDataSource> uploadRemoteDataSourceProvider =
    Provider<UploadRemoteDataSource>(
  (Ref ref) => UploadRemoteDataSource(ref.watch(apiClientProvider)),
  name: 'uploadRemoteDataSource',
);

final Provider<UploadRepository> uploadRepositoryProvider = Provider<UploadRepository>(
  (Ref ref) => UploadRepositoryImpl(ref.watch(uploadRemoteDataSourceProvider)),
  name: 'uploadRepository',
);

/// Overridden in widget tests, which is the whole reason the picker sits behind an interface.
final Provider<MediaPicker> mediaPickerProvider = Provider<MediaPicker>(
  (Ref ref) => const FilePickerMediaPicker(),
  name: 'mediaPicker',
);

/// The artist's own albums, for the optional "belongs to album" picker.
///
/// Empty for a listener account, which is also the honest answer for an artist who has not created
/// an album yet - the form then simply offers no album, instead of showing an error about it.
final FutureProvider<List<Album>> myAlbumsProvider = FutureProvider<List<Album>>(
  (Ref ref) async {
    final String? artistId = ref.watch(currentUserProvider)?.artistId;
    if (artistId == null) {
      return const <Album>[];
    }
    final PagedResponse<Album> page = await ref
        .watch(catalogRepositoryProvider)
        .getAlbums(artistId: artistId, size: 50);
    return page.items;
  },
  name: 'myAlbums',
);

/// The server's own media limits (`tuneflow.media.*`), mirrored so a doomed upload can be refused
/// before 40 MB travel over a phone connection and come back as a 413.
class UploadLimits {
  const UploadLimits._();

  static const int maxAudioBytes = 104857600; // 100 MB
  static const int maxImageBytes = 10485760; // 10 MB

  static const Set<String> audioExtensions = <String>{'mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg'};

  static const Set<String> imageExtensions = <String>{'jpg', 'jpeg', 'png', 'webp'};
}

/// Drives the upload form: pick -> upload -> review -> publish.
///
/// Auto-disposed so leaving the screen throws away a half-filled form (and the signed preview URLs
/// that go stale) instead of resurrecting yesterday's draft.
class UploadController extends AutoDisposeNotifier<UploadState> {
  /// Uploads outlive the widget tree by design (a user can navigate away mid-upload), so progress
  /// callbacks must not write to a disposed notifier.
  bool _disposed = false;

  @override
  UploadState build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    return const UploadState();
  }

  void _emit(UploadState next) {
    if (!_disposed) {
      state = next;
    }
  }

  // --- Metadata ---------------------------------------------------------------------------------
  void setTitle(String value) => _emit(state.copyWith(title: value, clearError: true));

  void setAlbum(String? albumId) =>
      _emit(albumId == null ? state.copyWith(clearAlbum: true) : state.copyWith(albumId: albumId));

  void toggleGenre(String slug) {
    final Set<String> next = Set<String>.of(state.genreSlugs);
    if (!next.remove(slug)) {
      next.add(slug);
    }
    _emit(state.copyWith(genreSlugs: next));
  }

  void setDuration(int seconds) => _emit(state.copyWith(durationSeconds: seconds));

  void setExplicit(bool value) => _emit(state.copyWith(explicit: value));

  void setTrackNumber(int? value) {
    if (value == null || value <= 0) {
      return;
    }
    _emit(state.copyWith(trackNumber: value));
  }

  void setReleaseDate(DateTime? date) {
    if (date == null) {
      return;
    }
    _emit(state.copyWith(releaseDate: date));
  }

  void dismissError() => _emit(state.copyWith(clearError: true));

  // --- Media ------------------------------------------------------------------------------------
  Future<void> pickAudio() => _pickAndUpload(audio: true);

  Future<void> pickCover() => _pickAndUpload(audio: false);

  void removeAudio() => _emit(state.copyWith(clearAudio: true, clearDuration: true));

  void removeCover() => _emit(state.copyWith(clearCover: true));

  Future<void> _pickAndUpload({required bool audio}) async {
    if (state.isUploading) {
      return;
    }

    MediaFile? file;
    try {
      final MediaPicker picker = ref.read(mediaPickerProvider);
      file = audio ? await picker.pickAudio() : await picker.pickImage();
    } on AppException catch (exception) {
      _emit(state.copyWith(errorMessage: exception.message));
      return;
    }

    // Cancelling is a normal outcome: leave the form exactly as it was.
    if (file == null) {
      return;
    }

    final String? rejected = _reject(file, audio: audio);
    if (rejected != null) {
      _emit(state.copyWith(errorMessage: rejected));
      return;
    }

    if (audio) {
      _emit(state.copyWith(
        audioFile: file,
        uploadingAudio: true,
        audioProgress: 0,
        // The previous upload's objectKey must go, but the file just picked must stay: clearing the
        // whole slot here is how the chosen filename used to vanish the moment the upload started.
        clearAudioResult: true,
        clearError: true,
      ));
    } else {
      _emit(state.copyWith(
        coverFile: file,
        uploadingCover: true,
        coverProgress: 0,
        clearCoverResult: true,
        clearError: true,
      ));
    }

    try {
      final UploadRepository repository = ref.read(uploadRepositoryProvider);
      final UploadResult result = audio
          ? await repository.uploadAudio(file, onProgress: (double fraction) {
              _emit(state.copyWith(audioProgress: fraction));
            })
          : await repository.uploadImage(file, onProgress: (double fraction) {
              _emit(state.copyWith(coverProgress: fraction));
            });

      if (audio) {
        _emit(state.copyWith(
          audio: result,
          uploadingAudio: false,
          audioProgress: 1,
          // Seed the duration from the server's analysis when it has one; the field stays editable
          // because a deployment without FFprobe returns null.
          durationSeconds: result.durationSeconds ?? state.durationSeconds,
        ));
      } else {
        _emit(state.copyWith(cover: result, uploadingCover: false, coverProgress: 1));
      }
    } on AppException catch (exception) {
      // Drop the failed file: a form still holding a file that never reached storage would publish
      // metadata pointing at nothing.
      if (audio) {
        _emit(state.copyWith(uploadingAudio: false, clearAudio: true, errorMessage: exception.message));
      } else {
        _emit(state.copyWith(uploadingCover: false, clearCover: true, errorMessage: exception.message));
      }
    }
  }

  /// Client-side mirror of the server's validation, so the common mistakes are answered instantly.
  String? _reject(MediaFile file, {required bool audio}) {
    final Set<String> allowed = audio ? UploadLimits.audioExtensions : UploadLimits.imageExtensions;
    final int limit = audio ? UploadLimits.maxAudioBytes : UploadLimits.maxImageBytes;

    if (!allowed.contains(file.extension)) {
      return '${file.extension.toUpperCase()} files are not supported. '
          'Use ${allowed.map((String value) => value.toUpperCase()).join(', ')}.';
    }
    if (file.sizeBytes > limit) {
      return 'That file is ${file.readableSize}; the limit is '
          '${audio ? '100 MB' : '10 MB'}.';
    }
    return null;
  }

  // --- Publish ----------------------------------------------------------------------------------
  Future<Song?> submit() async {
    if (!state.canSubmit) {
      _emit(state.copyWith(
        errorMessage: state.blockingReason ?? 'This song is not ready to publish yet.',
      ));
      return null;
    }

    _emit(state.copyWith(submitting: true, clearError: true));
    try {
      final Song song = await ref.read(uploadRepositoryProvider).createSong(
            title: state.title.trim(),
            audioObjectKey: state.audio!.objectKey,
            durationSeconds: state.effectiveDurationSeconds,
            coverImageObjectKey: state.cover?.objectKey,
            albumId: state.albumId,
            trackNumber: state.trackNumber,
            releaseDate: state.releaseDate,
            explicit: state.explicit,
            genreSlugs: state.genreSlugs,
          );
      _invalidateCatalog(song);
      // A fresh state, not a copy: the form is finished with, and keeping the objectKeys around
      // would let a second submit create a duplicate song.
      _emit(UploadState(createdSong: song));
      return song;
    } on AppException catch (exception) {
      _emit(state.copyWith(submitting: false, errorMessage: exception.message));
      return null;
    }
  }

  /// Publishing changes the catalogue, the recommendations and the artist's own page.
  void _invalidateCatalog(Song song) {
    ref.invalidate(homeFeedProvider);
    ref.invalidate(trendingSongsProvider);
    ref.invalidate(songProvider(song.id));

    final String? artistId = ref.read(currentUserProvider)?.artistId ?? song.artist?.id;
    if (artistId != null) {
      ref.invalidate(artistSongsProvider(artistId));
      ref.invalidate(artistAlbumsProvider(artistId));
      ref.invalidate(artistProvider(artistId));
    }
  }
}

final AutoDisposeNotifierProvider<UploadController, UploadState> uploadControllerProvider =
    AutoDisposeNotifierProvider<UploadController, UploadState>(
  UploadController.new,
  name: 'uploadController',
);
