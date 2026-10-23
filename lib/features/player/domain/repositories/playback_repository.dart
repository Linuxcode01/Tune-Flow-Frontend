import 'package:tuneflow/features/player/domain/entities/stream_url.dart';

/// Playback-specific backend operations: obtaining a signed URL and reporting listens.
///
/// Separated from the catalogue because these are writes against the *streaming* and *history*
/// modules, with different failure semantics: a failed play-count report must never interrupt
/// playback.
abstract interface class PlaybackRepository {
  /// Fetches a fresh signed URL for a track.
  Future<StreamUrl> getStreamUrl(String songId);

  /// Reports a playback event (`POST /history`).
  ///
  /// [finalUpdate] is how the API distinguishes progress pings from the last write of a session;
  /// only the final update is used for statistics, which is what makes the play counter accurate
  /// rather than optimistic.
  Future<void> recordPlayback({
    required String songId,
    required String sessionId,
    required int playedSeconds,
    required bool completed,
    required bool finalUpdate,
  });
}
