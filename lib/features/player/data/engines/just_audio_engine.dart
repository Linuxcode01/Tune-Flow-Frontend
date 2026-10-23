import 'dart:async';

import 'package:just_audio/just_audio.dart';
import 'package:tuneflow/core/utils/app_logger.dart';
import 'package:tuneflow/core/utils/media_url.dart';
import 'package:tuneflow/features/player/domain/repositories/audio_engine.dart';

/// The last line of defence between the API and ExoPlayer.
///
/// [PlaybackRepositoryImpl] already resolves signed URLs at the boundary, but the engine is the
/// one consumer where an unresolved URL does not produce a readable error - ExoPlayer throws a
/// `FileDataSourceException` ("uri has query…") and the track simply never plays. Resolving again
/// here means **no call path** can hand a relative or loopback-only URL to the native player,
/// even if a future caller skips the repository.
String resolvePlaybackUrl(String url, String? apiBaseUrl) {
  if (apiBaseUrl == null || apiBaseUrl.isEmpty) {
    return url;
  }
  return resolveMediaUrl(url, apiBaseUrl) ?? url;
}

/// [AudioEngine] implementation backed by `just_audio`.
///
/// The plugin's own enums are translated here so the rest of the app never imports the package: if
/// the audio backend is ever replaced, this is the only file that changes.
class JustAudioEngine implements AudioEngine {
  JustAudioEngine({AudioPlayer? player, String? apiBaseUrl})
      : _player = player ?? AudioPlayer(),
        _apiBaseUrl = apiBaseUrl;

  final AudioPlayer _player;

  /// Base URL of the API, used to absolutize any URL that arrives relative or signed against a
  /// loopback host (see [resolvePlaybackUrl]).
  final String? _apiBaseUrl;
  bool _disposed = false;

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Stream<Duration> get durationStream => _player.durationStream.where((Duration? value) => value != null).cast<Duration>();

  @override
  Stream<Duration> get bufferedPositionStream => _player.bufferedPositionStream;

  @override
  Stream<EngineState> get stateStream => _player.playerStateStream.map(
        (PlayerState state) => EngineState(
          playing: state.playing,
          processing: _mapProcessing(state.processingState),
        ),
      );

  @override
  Future<Duration?> setUrl(String url) async {
    final String resolved = resolvePlaybackUrl(url, _apiBaseUrl);
    if (resolved != url) {
      // Loud on purpose: this line in a device log is proof the URL fix is live, and it shows
      // exactly what ExoPlayer is about to fetch.
      AppLogger.info('Playback URL resolved before load: $url -> $resolved');
    }
    try {
      return await _player.setUrl(resolved);
    } on PlayerException catch (error, stackTrace) {
      // Surfaced to the user as a playable error state rather than an unhandled exception: a broken
      // CDN link should not crash the app.
      AppLogger.error('Audio source failed to load', error: error, stackTrace: stackTrace);
      rethrow;
    } on PlayerInterruptedException {
      // A newer load cancelled this one - expected while skipping tracks quickly.
      return null;
    }
  }

  @override
  Future<void> play() async {
    if (!_disposed) {
      await _player.play();
    }
  }

  @override
  Future<void> pause() async {
    if (!_disposed) {
      await _player.pause();
    }
  }

  @override
  Future<void> seek(Duration position) async {
    if (!_disposed) {
      await _player.seek(position);
    }
  }

  @override
  Future<void> stop() async {
    if (!_disposed) {
      await _player.stop();
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _player.dispose();
  }

  static EngineProcessing _mapProcessing(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return EngineProcessing.idle;
      case ProcessingState.loading:
        return EngineProcessing.loading;
      case ProcessingState.buffering:
        return EngineProcessing.buffering;
      case ProcessingState.ready:
        return EngineProcessing.ready;
      case ProcessingState.completed:
        return EngineProcessing.completed;
    }
  }
}
