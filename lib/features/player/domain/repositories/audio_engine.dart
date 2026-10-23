/// Abstraction over the audio backend.
///
/// `just_audio` sits behind this interface for two reasons: the playback state machine can be unit
/// tested with a fake engine (no platform channels, no audio device), and swapping engines later -
/// for example to add background playback via `audio_service` - does not touch a single line of the
/// player logic.
abstract interface class AudioEngine {
  Stream<Duration> get positionStream;

  Stream<Duration> get durationStream;

  Stream<Duration> get bufferedPositionStream;

  /// Platform-level state changes (loading / ready / completed / error).
  Stream<EngineState> get stateStream;

  /// Loads a single track. Each track needs its own signed URL, so the player loads one URL at a
  /// time and advances explicitly rather than relying on a native playlist.
  Future<Duration?> setUrl(String url);

  Future<void> play();

  Future<void> pause();

  Future<void> seek(Duration position);

  Future<void> stop();

  Future<void> dispose();
}

/// Normalised engine state, independent of the plugin's own enums.
class EngineState {
  const EngineState({
    required this.playing,
    required this.processing,
  });

  final bool playing;
  final EngineProcessing processing;

  bool get isCompleted => processing == EngineProcessing.completed;
  bool get isLoading => processing == EngineProcessing.loading || processing == EngineProcessing.buffering;
  bool get isReady => processing == EngineProcessing.ready;

  @override
  String toString() => 'EngineState(playing: $playing, processing: $processing)';
}

enum EngineProcessing { idle, loading, buffering, ready, completed }
