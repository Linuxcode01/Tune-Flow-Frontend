import 'package:tuneflow/core/config/app_config.dart';
import 'package:tuneflow/core/error/app_exception.dart';
import 'package:tuneflow/core/utils/app_logger.dart';
import 'package:tuneflow/core/utils/media_url.dart';
import 'package:tuneflow/features/player/data/datasources/playback_remote_datasource.dart';
import 'package:tuneflow/features/player/domain/entities/stream_url.dart';
import 'package:tuneflow/features/player/domain/repositories/playback_repository.dart';

class PlaybackRepositoryImpl implements PlaybackRepository {
  const PlaybackRepositoryImpl(this._remote, this._config);

  final PlaybackRemoteDataSource _remote;
  final AppConfig _config;

  /// The signed URL is resolved to absolute here, at the boundary, because the audio engine is the
  /// one consumer that cannot do it itself: a relative `/api/v1/media/…` handed to `just_audio` is a
  /// track that never plays (see [resolveMediaUrl]).
  @override
  Future<StreamUrl> getStreamUrl(String songId) async {
    final StreamUrl stream = await _remote.getStreamUrl(songId);
    final String? resolved = resolveMediaUrl(stream.url, _config.apiBaseUrl);
    final String effective = resolved ?? stream.url;
    if (effective != stream.url) {
      AppLogger.info('Stream URL resolved for $songId: $effective');
    }
    return resolved == null ? stream : stream.withUrl(resolved);
  }

  @override
  Future<void> recordPlayback({
    required String songId,
    required String sessionId,
    required int playedSeconds,
    required bool completed,
    required bool finalUpdate,
  }) async {
    try {
      await _remote.recordPlayback(
        songId: songId,
        sessionId: sessionId,
        playedSeconds: playedSeconds,
        completed: completed,
        finalUpdate: finalUpdate,
      );
    } on AppException catch (error) {
      /*
       * Analytics must never break playback: a history ping that fails (offline, server hiccup,
       * rate limit) is logged and dropped. The next ping carries the cumulative `playedSeconds`,
       * so the timeline self-heals rather than losing the listen entirely.
       */
      AppLogger.warn('Playback report dropped ($songId)', error: error);
    }
  }
}
