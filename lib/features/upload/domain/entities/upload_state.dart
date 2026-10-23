import 'package:tuneflow/features/catalog/domain/entities/song.dart';
import 'package:tuneflow/features/upload/domain/entities/media_file.dart';
import 'package:tuneflow/features/upload/domain/entities/upload_result.dart';

/// The artist upload form, as one immutable value.
///
/// The two media steps are tracked separately from the metadata: a file can be uploading (or failed)
/// while the text fields are still being filled in, and the form must stay usable in that state
/// rather than locking the whole screen behind one spinner.
class UploadState {
  const UploadState({
    this.audioFile,
    this.audio,
    this.audioProgress,
    this.uploadingAudio = false,
    this.coverFile,
    this.cover,
    this.coverProgress,
    this.uploadingCover = false,
    this.title = '',
    this.albumId,
    this.genreSlugs = const <String>{},
    this.durationSeconds,
    this.trackNumber,
    this.releaseDate,
    this.explicit = false,
    this.submitting = false,
    this.errorMessage,
    this.createdSong,
  });

  // --- Audio ------------------------------------------------------------------------------------
  final MediaFile? audioFile;

  /// Set once the bytes have landed in storage; its `objectKey` is what gets published.
  final UploadResult? audio;

  final double? audioProgress;
  final bool uploadingAudio;

  // --- Cover art --------------------------------------------------------------------------------
  final MediaFile? coverFile;
  final UploadResult? cover;
  final double? coverProgress;
  final bool uploadingCover;

  // --- Metadata ---------------------------------------------------------------------------------
  final String title;
  final String? albumId;
  final Set<String> genreSlugs;

  /// Seconds. Seeded from the upload result when FFprobe is available, editable because it is
  /// required by the API and an un-analysed upload returns nothing.
  final int? durationSeconds;

  final int? trackNumber;
  final DateTime? releaseDate;
  final bool explicit;

  // --- Request ----------------------------------------------------------------------------------
  final bool submitting;
  final String? errorMessage;
  final Song? createdSong;

  bool get hasAudio => audio != null;

  bool get isUploading => uploadingAudio || uploadingCover;

  /// What actually gets published: the value the artist typed, falling back to what the server
  /// measured while accepting the file.
  ///
  /// Keeping the fallback here rather than in the form means a state that has an analysed upload can
  /// never be "blocked on duration" for no reason, and an explicit edit still wins.
  int get effectiveDurationSeconds => durationSeconds ?? audio?.durationSeconds ?? 0;

  /// Deliberately strict: the API rejects a song without a title, and publishing metadata that points
  /// at an audio file that is not there yet would produce an unplayable track.
  bool get canSubmit =>
      hasAudio && title.trim().isNotEmpty && !isUploading && !submitting && effectiveDurationSeconds > 0;

  /// Non-blocking validation, so the button can explain itself instead of just being grey.
  String? get blockingReason {
    if (!hasAudio) {
      return 'Choose an audio file first.';
    }
    if (isUploading) {
      return 'Waiting for the upload to finish.';
    }
    if (title.trim().isEmpty) {
      return 'Give the track a title.';
    }
    if (effectiveDurationSeconds <= 0) {
      return 'Duration must be at least one second.';
    }
    if (submitting) {
      return 'Publishing…';
    }
    return null;
  }

  UploadState copyWith({
    MediaFile? audioFile,
    UploadResult? audio,
    double? audioProgress,
    bool? uploadingAudio,
    MediaFile? coverFile,
    UploadResult? cover,
    double? coverProgress,
    bool? uploadingCover,
    String? title,
    String? albumId,
    Set<String>? genreSlugs,
    int? durationSeconds,
    int? trackNumber,
    DateTime? releaseDate,
    bool? explicit,
    bool? submitting,
    String? errorMessage,
    Song? createdSong,
    // Nullable fields need an explicit signal to be cleared - passing `null` cannot mean both
    // "leave it" and "remove it".
    //
    // `clearAudio` drops the picked file *and* its upload result (the Remove button). `clearAudioResult`
    // drops only the result, which is what starting a replacement upload needs: the new file is set in
    // the same call, and clearing the file as well would erase it before it could be shown.
    bool clearAudio = false,
    bool clearAudioResult = false,
    bool clearCover = false,
    bool clearCoverResult = false,
    bool clearAlbum = false,
    bool clearError = false,
    bool clearDuration = false,
  }) {
    return UploadState(
      audioFile: clearAudio ? null : (audioFile ?? this.audioFile),
      audio: (clearAudio || clearAudioResult) ? null : (audio ?? this.audio),
      audioProgress: clearAudio ? null : (audioProgress ?? this.audioProgress),
      uploadingAudio: uploadingAudio ?? this.uploadingAudio,
      coverFile: clearCover ? null : (coverFile ?? this.coverFile),
      cover: (clearCover || clearCoverResult) ? null : (cover ?? this.cover),
      coverProgress: clearCover ? null : (coverProgress ?? this.coverProgress),
      uploadingCover: uploadingCover ?? this.uploadingCover,
      title: title ?? this.title,
      albumId: clearAlbum ? null : (albumId ?? this.albumId),
      genreSlugs: genreSlugs ?? this.genreSlugs,
      durationSeconds: clearDuration ? null : (durationSeconds ?? this.durationSeconds),
      trackNumber: trackNumber ?? this.trackNumber,
      releaseDate: releaseDate ?? this.releaseDate,
      explicit: explicit ?? this.explicit,
      submitting: submitting ?? this.submitting,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      createdSong: createdSong ?? this.createdSong,
    );
  }
}
