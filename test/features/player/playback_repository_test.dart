import 'package:flutter_test/flutter_test.dart';
import 'package:tuneflow/core/config/app_config.dart';
import 'package:tuneflow/features/player/data/datasources/playback_remote_datasource.dart';
import 'package:tuneflow/features/player/data/repositories/playback_repository_impl.dart';
import 'package:tuneflow/features/player/domain/entities/stream_url.dart';

/// The bug this pins down: the API signs media URLs against its own public base URL, which is empty
/// by default, so `GET /songs/{id}/stream` answers with a **relative** path. Dio resolves that for
/// JSON calls, but the audio engine gets the URL string and cannot - the track silently never plays.
/// The repository is the seam where that is fixed, so it is asserted here rather than on a device.
void main() {
  const AppConfig config = AppConfig(
    apiBaseUrl: 'http://localhost:8080/api/v1',
    apiTimeout: Duration(seconds: 20),
    streamUrlSafetyMargin: Duration(seconds: 30),
    pageSize: 20,
    enableNetworkLogs: false,
  );

  test('a relative signed URL is resolved against the API base before the player sees it', () async {
    final _StubDataSource dataSource = _StubDataSource(
      url: '/api/v1/media/audio/2026/10/9f2c.mp3?expires=1760000000&signature=abc',
    );

    final StreamUrl stream = await PlaybackRepositoryImpl(dataSource, config).getStreamUrl('song-1');

    expect(
      stream.url,
      'http://localhost:8080/api/v1/media/audio/2026/10/9f2c.mp3?expires=1760000000&signature=abc',
    );
    // Everything else about the response is left alone.
    expect(stream.songId, 'song-1');
    expect(stream.contentType, 'audio/mpeg');
    expect(stream.expiresAt.isAfter(DateTime.now().toUtc()), isTrue);
  });

  test('an absolute URL (a CDN deployment) is passed through untouched', () async {
    const String cdn = 'https://cdn.tuneflow.dev/audio/9f2c.mp3?token=xyz';
    final _StubDataSource dataSource = _StubDataSource(url: cdn);

    final StreamUrl stream = await PlaybackRepositoryImpl(dataSource, config).getStreamUrl('song-1');

    expect(stream.url, cdn);
  });
}

class _StubDataSource implements PlaybackRemoteDataSource {
  _StubDataSource({required this.url});

  final String url;

  @override
  Future<StreamUrl> getStreamUrl(String songId) async => StreamUrl(
        songId: songId,
        url: url,
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 10)),
        title: 'Neon Skyline',
        contentType: 'audio/mpeg',
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
