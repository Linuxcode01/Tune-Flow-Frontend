import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuneflow/features/catalog/domain/entities/song.dart';
import 'package:tuneflow/features/player/domain/entities/player_state.dart';
import 'package:tuneflow/features/player/domain/entities/stream_url.dart';
import 'package:tuneflow/features/player/domain/repositories/audio_engine.dart';
import 'package:tuneflow/features/player/domain/repositories/playback_repository.dart';
import 'package:tuneflow/features/player/presentation/providers/player_providers.dart';

/// When the native player cannot fetch a track, the error shown to the user must carry the URL it
/// tried - "could not play" plus the address is the whole diagnosis (relative path, loopback host,
/// or a host the phone cannot reach).

class _FailingEngine implements AudioEngine {
  String? lastUrl;

  @override
  Stream<Duration> get positionStream => const Stream<Duration>.empty();

  @override
  Stream<Duration> get durationStream => const Stream<Duration>.empty();

  @override
  Stream<Duration> get bufferedPositionStream => const Stream<Duration>.empty();

  @override
  Stream<EngineState> get stateStream => const Stream<EngineState>.empty();

  @override
  Future<Duration?> setUrl(String url) async {
    lastUrl = url;
    // What ExoPlayer throws when the address is unreachable from the phone.
    throw Exception('Source error: connection refused');
  }

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

class _FixedUrlRepository implements PlaybackRepository {
  _FixedUrlRepository(this.url);

  final String url;

  @override
  Future<StreamUrl> getStreamUrl(String songId) async => StreamUrl(
        songId: songId,
        url: url,
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 10)),
      );

  @override
  Future<void> recordPlayback({
    required String songId,
    required String sessionId,
    required int playedSeconds,
    required bool completed,
    required bool finalUpdate,
  }) async {}
}

void main() {
  test('a failed load surfaces the URL the player tried, not a bare "could not play"', () async {
    const String url = 'http://10.49.5.96:8080/api/v1/media/audio/a.mp3?expires=1&signature=s';
    final _FailingEngine engine = _FailingEngine();
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        audioEngineProvider.overrideWithValue(engine),
        playbackRepositoryProvider.overrideWithValue(_FixedUrlRepository(url)),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(playerControllerProvider.notifier)
        .playSong(const Song(id: 's1', title: 'Probe', durationSeconds: 10));

    expect(engine.lastUrl, url);
    final PlayerState state = container.read(playerControllerProvider);
    expect(state.status, PlaybackStatus.error);
    expect(state.errorMessage, startsWith('Could not play this track.'));
    expect(state.errorMessage, contains(url));
  });
}
