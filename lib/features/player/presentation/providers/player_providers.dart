import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tuneflow/core/config/app_config.dart';
import 'package:tuneflow/core/constants/app_constants.dart';
import 'package:tuneflow/core/error/app_exception.dart';
import 'package:tuneflow/core/providers/core_providers.dart';
import 'package:tuneflow/core/utils/app_logger.dart';
import 'package:tuneflow/core/utils/id_generator.dart';
import 'package:tuneflow/features/catalog/domain/entities/song.dart';
import 'package:tuneflow/features/player/data/datasources/playback_remote_datasource.dart';
import 'package:tuneflow/features/player/data/engines/just_audio_engine.dart';
import 'package:tuneflow/features/player/data/repositories/playback_repository_impl.dart';
import 'package:tuneflow/features/player/domain/entities/player_state.dart';
import 'package:tuneflow/features/player/domain/entities/stream_url.dart';
import 'package:tuneflow/features/player/domain/repositories/audio_engine.dart';
import 'package:tuneflow/features/player/domain/repositories/playback_repository.dart';

// ---------------------------------------------------------------------------------------------
// Wiring
// ---------------------------------------------------------------------------------------------

final Provider<AudioEngine> audioEngineProvider = Provider<AudioEngine>(
  (Ref ref) {
    // The engine gets the API base URL so it can absolutize any URL itself - the final safety net
    // before a string reaches ExoPlayer (see resolvePlaybackUrl).
    final AudioEngine engine = JustAudioEngine(
      apiBaseUrl: ref.watch(appConfigProvider).apiBaseUrl,
    );
    ref.onDispose(engine.dispose);
    return engine;
  },
  name: 'audioEngine',
);

final Provider<PlaybackRemoteDataSource> playbackRemoteDataSourceProvider =
    Provider<PlaybackRemoteDataSource>(
  (Ref ref) => PlaybackRemoteDataSource(ref.watch(apiClientProvider)),
  name: 'playbackRemoteDataSource',
);

final Provider<PlaybackRepository> playbackRepositoryProvider = Provider<PlaybackRepository>(
  (Ref ref) => PlaybackRepositoryImpl(
        ref.watch(playbackRemoteDataSourceProvider),
        ref.watch(appConfigProvider),
      ),
  name: 'playbackRepository',
);

// ---------------------------------------------------------------------------------------------
// The player service
// ---------------------------------------------------------------------------------------------

/// The cross-feature player (docs sections 20-21).
///
/// Responsibilities, in one place rather than spread across screens:
/// * own the single audio engine instance,
/// * turn a song into a fresh signed URL and load it,
/// * expose the six documented states,
/// * advance the queue (including shuffle and repeat),
/// * report listening progress to `POST /history`, including the final update.
///
/// Screens only read [playerControllerProvider] and call its methods; none of them touch the engine.
class PlayerController extends Notifier<PlayerState> {
  late final AudioEngine _engine;
  late final PlaybackRepository _repository;

  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<Duration>? _bufferedSubscription;
  StreamSubscription<EngineState>? _engineStateSubscription;

  /// Signed URLs are cached per track and re-fetched once close to expiry.
  final Map<String, StreamUrl> _urlCache = <String, StreamUrl>{};

  /// The URL the native player most recently tried; surfaced in the playback error message so a
  /// failure is self-diagnosing (relative, loopback or unreachable host).
  String? _attemptedUrl;

  /// Playback seconds already reported for the current session.
  Duration _reported = Duration.zero;
  Duration _lastKnownPosition = Duration.zero;
  bool _finalReportSent = true;

  @override
  PlayerState build() {
    _engine = ref.watch(audioEngineProvider);
    _repository = ref.watch(playbackRepositoryProvider);

    _positionSubscription = _engine.positionStream.listen(_onPosition);
    _durationSubscription = _engine.durationStream.listen(_onDuration);
    _bufferedSubscription = _engine.bufferedPositionStream.listen((Duration buffered) {
      state = state.copyWith(bufferedPosition: buffered);
    });
    _engineStateSubscription = _engine.stateStream.listen(_onEngineState);

    ref.onDispose(() {
      _positionSubscription?.cancel();
      _durationSubscription?.cancel();
      _bufferedSubscription?.cancel();
      _engineStateSubscription?.cancel();
    });

    return const PlayerState();
  }

  // --- Public controls -----------------------------------------------------------------------

  /// Plays a single song, optionally as part of a queue (the list the user tapped from).
  Future<void> playSong(Song song, {List<Song>? queue}) async {
    final List<Song> context = (queue == null || queue.isEmpty) ? <Song>[song] : queue;
    final int index = context.indexWhere((Song candidate) => candidate.id == song.id);
    await playQueue(context, startIndex: index < 0 ? 0 : index);
  }

  /// Replaces the queue and starts at [startIndex].
  Future<void> playQueue(List<Song> songs, {int startIndex = 0}) async {
    final List<Song> playable = songs.where((Song song) => song.streamAvailable).toList(growable: false);
    if (playable.isEmpty) {
      state = state.copyWith(
        status: PlaybackStatus.error,
        errorMessage: 'Nothing to play here yet.',
      );
      return;
    }

    final int safeIndex = startIndex.clamp(0, playable.length - 1);
    state = state.copyWith(
      queue: playable,
      index: safeIndex,
      hasPrevious: safeIndex > 0,
      hasNext: safeIndex < playable.length - 1,
      position: Duration.zero,
      duration: playable[safeIndex].duration,
      clearError: true,
    );
    await _load(playable[safeIndex]);
  }

  /// Adds a track to the end of the queue without disturbing playback.
  void enqueue(Song song) {
    if (state.queue.any((Song queued) => queued.id == song.id && queued == state.track)) {
      return;
    }
    final List<Song> updated = <Song>[...state.queue, song];
    state = state.copyWith(queue: updated, hasNext: state.index < updated.length - 1);
  }

  /// Plays (or resumes) the loaded track.
  Future<void> resume() async {
    if (state.track == null) {
      return;
    }
    if (state.status == PlaybackStatus.completed) {
      await _engine.seek(Duration.zero);
      state = state.copyWith(position: Duration.zero);
    }
    await _engine.play();
  }

  Future<void> pause() async {
    await _engine.pause();
  }

  Future<void> togglePlayPause() async {
    if (state.isPlaying) {
      await pause();
    } else {
      await resume();
    }
  }

  Future<void> next() async {
    if (!state.hasNext) {
      return;
    }
    await _sendFinalReport();
    final int target = _nextIndex();
    state = state.copyWith(
      index: target,
      hasPrevious: target > 0,
      hasNext: target < state.queue.length - 1,
      position: Duration.zero,
      duration: state.queue[target].duration,
    );
    await _load(state.queue[target]);
  }

  Future<void> previous() async {
    // Standard player behaviour: restart the track unless the user is near its start.
    if (state.position.inSeconds > 3) {
      await seek(Duration.zero);
      return;
    }
    if (!state.hasPrevious) {
      return;
    }
    await _sendFinalReport();
    final int target = state.index - 1;
    state = state.copyWith(
      index: target,
      hasPrevious: target > 0,
      hasNext: true,
      position: Duration.zero,
      duration: state.queue[target].duration,
    );
    await _load(state.queue[target]);
  }

  Future<void> seek(Duration position) async {
    await _engine.seek(position);
    state = state.copyWith(position: position);
  }

  void toggleShuffle() {
    final bool shuffle = !state.shuffle;
    state = state.copyWith(shuffle: shuffle);
    if (shuffle && state.track != null) {
      _shuffleUpcoming();
    }
  }

  void cycleRepeatMode() {
    state = state.copyWith(repeatMode: state.repeatMode.next);
  }

  /// Stops playback and clears the queue (used when the user signs out).
  Future<void> stopAndClear() async {
    await _engine.stop();
    _urlCache.clear();
    state = const PlayerState();
  }

  // --- Internals -----------------------------------------------------------------------------

  Future<void> _load(Song song) async {
    state = state.copyWith(
      status: PlaybackStatus.loading,
      track: song,
      analyticsSessionId: IdGenerator.uuidV4(),
      clearError: true,
    );
    _reported = Duration.zero;
    _lastKnownPosition = Duration.zero;
    _finalReportSent = false;
    _attemptedUrl = null;

    try {
      final StreamUrl stream = await _resolveUrl(song.id);
      if (!stream.isUsable) {
        state = state.copyWith(
          status: PlaybackStatus.error,
          errorMessage: 'This track is not available right now.',
        );
        return;
      }

      _attemptedUrl = stream.url;
      final Duration? actualDuration = await _engine.setUrl(stream.url);
      await _engine.play();
      state = state.copyWith(
        // `setUrl` is the authority on duration - the catalogue value can be stale.
        duration: actualDuration ?? song.duration,
        position: Duration.zero,
      );
      await ref.read(preferencesProvider).pushRecentSongId(song.id);
    } on AppException catch (error) {
      state = state.copyWith(status: PlaybackStatus.error, errorMessage: error.message);
    } catch (error, stackTrace) {
      AppLogger.error('Playback failed for ${song.id} via $_attemptedUrl',
          error: error, stackTrace: stackTrace);
      // The URL is surfaced on purpose: when a track will not play, the address the native player
      // actually tried is the whole diagnosis (relative / loopback / unreachable host).
      state = state.copyWith(
        status: PlaybackStatus.error,
        errorMessage: _attemptedUrl == null
            ? 'Could not play this track.'
            : 'Could not play this track.\n$_attemptedUrl',
      );
    }
  }

  /// Returns a cached signed URL, refreshing it when it is close to expiring.
  Future<StreamUrl> _resolveUrl(String songId) async {
    final AppConfig config = ref.read(appConfigProvider);
    final StreamUrl? cached = _urlCache[songId];
    if (cached != null && !cached.isExpiringWithin(config.streamUrlSafetyMargin)) {
      return cached;
    }
    final StreamUrl fresh = await _repository.getStreamUrl(songId);
    _urlCache[songId] = fresh;
    return fresh;
  }

  void _onPosition(Duration position) {
    _lastKnownPosition = position;
    state = state.copyWith(position: position);

    // Report every 30 s of playback so "Recently played" and listening stats stay current without
    // hammering the API on every position tick (which fires ~4x/second).
    if (position - _reported >= AppConstants.progressReportInterval) {
      _reported = position;
      unawaited(_report(completed: false, finalUpdate: false));
    }
  }

  void _onDuration(Duration duration) {
    if (duration > Duration.zero) {
      state = state.copyWith(duration: duration);
    }
  }

  void _onEngineState(EngineState engineState) {
    if (engineState.isCompleted) {
      unawaited(_handleCompletion());
      return;
    }

    final PlaybackStatus status;
    if (engineState.playing) {
      status = PlaybackStatus.playing;
    } else if (engineState.isLoading) {
      status = PlaybackStatus.loading;
    } else if (state.status == PlaybackStatus.error) {
      status = PlaybackStatus.error;
    } else if (state.track == null) {
      status = PlaybackStatus.idle;
    } else {
      status = PlaybackStatus.paused;
    }
    state = state.copyWith(status: status);
  }

  Future<void> _handleCompletion() async {
    final Song? finished = state.track;
    if (finished != null) {
      await ref.read(preferencesProvider).pushRecentSongId(finished.id);
    }
    await _sendFinalReport(completed: true);

    if (state.repeatMode == RepeatMode.one) {
      await _engine.seek(Duration.zero);
      await _engine.play();
      _reported = Duration.zero;
      _finalReportSent = false;
      return;
    }

    final bool canAdvance = state.repeatMode == RepeatMode.all || state.hasNext;
    if (canAdvance && state.queue.isNotEmpty) {
      final int target = state.hasNext ? _nextIndex() : 0;
      state = state.copyWith(
        index: target,
        hasPrevious: target > 0,
        hasNext: target < state.queue.length - 1,
        position: Duration.zero,
        duration: state.queue[target].duration,
      );
      await _load(state.queue[target]);
      return;
    }

    state = state.copyWith(
      status: PlaybackStatus.completed,
      position: state.duration,
    );
  }

  /// Next index honouring shuffle: a random index is picked lazily at advance time so the queue view
  /// still shows the real order.
  int _nextIndex() {
    if (state.shuffle && state.queue.length > 1) {
      int candidate = state.index;
      while (candidate == state.index) {
        candidate = DateTime.now().microsecondsSinceEpoch % state.queue.length;
      }
      return candidate;
    }
    return (state.index + 1).clamp(0, state.queue.length - 1);
  }

  void _shuffleUpcoming() {
    final List<Song> remaining = state.queue.sublist(state.index + 1);
    if (remaining.length < 2) {
      return;
    }
    remaining.shuffle();
    state = state.copyWith(
      queue: <Song>[...state.queue.sublist(0, state.index + 1), ...remaining],
    );
  }

  Future<void> _report({required bool completed, required bool finalUpdate}) {
    final Song? track = state.track;
    final String? sessionId = state.analyticsSessionId;
    if (track == null || sessionId == null) {
      return Future<void>.value();
    }
    return _repository.recordPlayback(
      songId: track.id,
      sessionId: sessionId,
      playedSeconds: _lastKnownPosition.inSeconds,
      completed: completed,
      finalUpdate: finalUpdate,
    );
  }

  /// Sends the closing report for the current session, exactly once.
  Future<void> _sendFinalReport({bool completed = false}) async {
    if (_finalReportSent || state.track == null) {
      return;
    }
    _finalReportSent = true;
    await _report(completed: completed, finalUpdate: true);
  }
}

final NotifierProvider<PlayerController, PlayerState> playerControllerProvider =
    NotifierProvider<PlayerController, PlayerState>(PlayerController.new, name: 'playerController');

/// Selectors used by the mini-player and the shell, so widgets rebuild only for what they show.
final Provider<Song?> currentTrackProvider = Provider<Song?>(
  (Ref ref) => ref.watch(playerControllerProvider).track,
  name: 'currentTrack',
);

final Provider<bool> isPlayingProvider = Provider<bool>(
  (Ref ref) => ref.watch(playerControllerProvider).isPlaying,
  name: 'isPlaying',
);
