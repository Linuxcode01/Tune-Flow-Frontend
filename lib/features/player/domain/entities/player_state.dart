import 'package:tuneflow/features/catalog/domain/entities/song.dart';

/// Playback lifecycle, exactly the set of states the documentation requires
/// (docs section 21: idle, loading, playing, paused, completed, error).
enum PlaybackStatus {
  idle,
  loading,
  playing,
  paused,
  completed,
  error,
}

/// What happens when the current track ends.
enum RepeatMode {
  off,
  all,
  one;

  RepeatMode get next {
    switch (this) {
      case RepeatMode.off:
        return RepeatMode.all;
      case RepeatMode.all:
        return RepeatMode.one;
      case RepeatMode.one:
        return RepeatMode.off;
    }
  }
}

/// Immutable snapshot of the player.
///
/// The player is a cross-feature singleton (the mini-player appears above every tab), so its state is
/// a single object that any screen can watch without owning the playback logic.
class PlayerState {
  const PlayerState({
    this.status = PlaybackStatus.idle,
    this.track,
    this.queue = const <Song>[],
    this.index = 0,
    this.hasPrevious = false,
    this.hasNext = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.bufferedPosition = Duration.zero,
    this.shuffle = false,
    this.repeatMode = RepeatMode.off,
    this.errorMessage,
    this.analyticsSessionId,
  });

  final PlaybackStatus status;

  /// The track currently loaded, if any.
  final Song? track;

  /// Upcoming tracks, in play order (the whole queue, including the current track, for simplicity of
  /// index arithmetic).
  final List<Song> queue;
  final int index;
  final bool hasPrevious;
  final bool hasNext;

  final Duration position;
  final Duration duration;
  final Duration bufferedPosition;

  final bool shuffle;
  final RepeatMode repeatMode;
  final String? errorMessage;

  /// Identifier for the playback session reported to `POST /history`; regenerated per track so a
  /// replay is a new session rather than a continuation of the old one.
  final String? analyticsSessionId;

  bool get isPlaying => status == PlaybackStatus.playing;
  bool get isLoading => status == PlaybackStatus.loading;
  bool get hasTrack => track != null;
  bool get isIdle => status == PlaybackStatus.idle || track == null;

  /// 0.0-1.0 progress, guarded against a zero-length duration.
  double get progress {
    if (duration.inMilliseconds <= 0) {
      return 0;
    }
    return (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
  }

  /// Remaining time, shown next to the total duration in the expanded player.
  Duration get remaining {
    final Duration left = duration - position;
    return left.isNegative ? Duration.zero : left;
  }

  PlayerState copyWith({
    PlaybackStatus? status,
    Song? track,
    bool clearTrack = false,
    List<Song>? queue,
    int? index,
    bool? hasPrevious,
    bool? hasNext,
    Duration? position,
    Duration? duration,
    Duration? bufferedPosition,
    bool? shuffle,
    RepeatMode? repeatMode,
    String? errorMessage,
    bool clearError = false,
    String? analyticsSessionId,
  }) {
    return PlayerState(
      status: status ?? this.status,
      track: clearTrack ? null : (track ?? this.track),
      queue: queue ?? this.queue,
      index: index ?? this.index,
      hasPrevious: hasPrevious ?? this.hasPrevious,
      hasNext: hasNext ?? this.hasNext,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      bufferedPosition: bufferedPosition ?? this.bufferedPosition,
      shuffle: shuffle ?? this.shuffle,
      repeatMode: repeatMode ?? this.repeatMode,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      analyticsSessionId: analyticsSessionId ?? this.analyticsSessionId,
    );
  }

  @override
  String toString() => 'PlayerState($status, ${track?.title}, ${position.inSeconds}s)';
}
