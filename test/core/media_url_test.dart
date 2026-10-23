import 'package:flutter_test/flutter_test.dart';
import 'package:tuneflow/core/utils/media_url.dart';

/// `resolveMediaUrl` is what stops "the song uploads but never plays": the API signs media URLs
/// against its own public base URL, which is empty by default, so playback and artwork URLs arrive
/// **relative** - fine for Dio, impossible for `just_audio` and the image loader.
void main() {
  const String apiBase = 'http://localhost:8080/api/v1';

  group('resolveMediaUrl', () {
    test('joins a signed relative media path onto the API base', () {
      const String signed = '/api/v1/media/audio/2026/10/9f2c.mp3?expires=1760000000&signature=abc-_';
      expect(resolveMediaUrl(signed, apiBase), 'http://localhost:8080/api/v1/media/audio/2026/10/9f2c.mp3'
          '?expires=1760000000&signature=abc-_');
    });

    test('keeps an absolute URL untouched - a CDN or external artwork must stay where it points', () {
      const String cdn = 'https://cdn.tuneflow.dev/audio/track.mp3?token=xyz';
      expect(resolveMediaUrl(cdn, apiBase), cdn);
    });

    test('is indifferent to a trailing slash on the base URL', () {
      expect(resolveMediaUrl('/api/v1/media/a.mp3', 'http://10.0.2.2:8080/api/v1/'),
          'http://10.0.2.2:8080/api/v1/media/a.mp3');
    });

    test('resolves against a host:port base once the /api/v1 prefix is gone', () {
      expect(resolveMediaUrl('/api/v1/media/a.mp3', 'http://localhost:8080'),
          'http://localhost:8080/api/v1/media/a.mp3');
    });

    test('a bare relative path is appended to the base directory, not treated as a root path', () {
      // Covers the S3 provider shape, where the signed URL can come back as a plain object path.
      expect(resolveMediaUrl('images/2026/10/art.jpg', 'http://localhost:8080/api/v1'),
          'http://localhost:8080/api/v1/images/2026/10/art.jpg');
    });

    test('passes null and empty straight through so callers keep their own empty-state handling', () {
      expect(resolveMediaUrl(null, apiBase), isNull);
      expect(resolveMediaUrl('', apiBase), '');
    });

    test('returns the original string when there is nothing usable to resolve against', () {
      expect(resolveMediaUrl('/api/v1/media/a.mp3', 'not a url'), '/api/v1/media/a.mp3');
    });

    test('retargets a loopback-signed URL onto the LAN base a phone can actually reach', () {
      // The dev backend signs against http://localhost:8080 by default; a phone on Wi-Fi only
      // knows the PC as 10.49.5.96, so the host must move while the signature stays intact.
      expect(
        resolveMediaUrl(
          'http://localhost:8080/api/v1/media/audio/a.mp3?expires=1760000000&signature=abc-_1',
          'http://10.49.5.96:8080/api/v1',
        ),
        'http://10.49.5.96:8080/api/v1/media/audio/a.mp3?expires=1760000000&signature=abc-_1',
      );
    });

    test('leaves a loopback URL alone when the client also targets loopback', () {
      const String url = 'http://127.0.0.1:8080/api/v1/media/a.mp3?expires=1&signature=s';
      expect(resolveMediaUrl(url, 'http://localhost:8080/api/v1'), url);
    });

    test('never touches a non-loopback absolute URL, whatever the base is', () {
      const String cdn = 'https://cdn.tuneflow.dev/audio/track.mp3?token=xyz';
      expect(resolveMediaUrl(cdn, 'http://10.49.5.96:8080/api/v1'), cdn);
    });
  });
}
