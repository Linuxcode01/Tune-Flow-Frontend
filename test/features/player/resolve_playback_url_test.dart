import 'package:flutter_test/flutter_test.dart';
import 'package:tuneflow/features/player/data/engines/just_audio_engine.dart';

/// `resolvePlaybackUrl` is the engine's safety net: even if a caller forgets to resolve a signed
/// URL (or an older backend answers with a relative/loopback one), nothing unresolved may ever
/// reach ExoPlayer - that is exactly the shape of the "song uploads but never plays" bug.
void main() {
  group('resolvePlaybackUrl', () {
    test('passes the URL through when no API base is wired', () {
      const String relative = '/api/v1/media/a.mp3?expires=1&signature=s';
      expect(resolvePlaybackUrl(relative, null), relative);
      expect(resolvePlaybackUrl(relative, ''), relative);
    });

    test('absolutizes a relative signed URL right before the native player sees it', () {
      expect(
        resolvePlaybackUrl(
          '/api/v1/media/audio/a.mp3?expires=1760000000&signature=abc-_1',
          'http://10.49.5.96:8080/api/v1',
        ),
        'http://10.49.5.96:8080/api/v1/media/audio/a.mp3?expires=1760000000&signature=abc-_1',
      );
    });

    test('retargets a loopback-signed URL onto the LAN base', () {
      expect(
        resolvePlaybackUrl(
          'http://localhost:8080/api/v1/media/a.mp3?expires=1&signature=s',
          'http://10.49.5.96:8080/api/v1',
        ),
        'http://10.49.5.96:8080/api/v1/media/a.mp3?expires=1&signature=s',
      );
    });

    test('leaves an already-reachable absolute URL untouched', () {
      const String url = 'http://10.49.5.96:8080/api/v1/media/a.mp3?expires=1&signature=s';
      expect(resolvePlaybackUrl(url, 'http://10.49.5.96:8080/api/v1'), url);
    });
  });
}
