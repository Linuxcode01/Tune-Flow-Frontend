/// Turns a media URL from the API into one that anything other than Dio can actually fetch.
///
/// The API signs audio and artwork URLs against `tuneflow.storage.public-base-url`. In dev that is
/// either empty or left at its `http://localhost:8080` default, which produces two shapes of URL
/// that a phone cannot play:
///
/// ```
/// /api/v1/media/audio/2026/10/9f2c….mp3?expires=1760…&signature=…   (relative)
/// http://localhost:8080/api/v1/media/audio/…?expires=…&signature=…  (absolute, but loopback)
/// ```
///
/// Dio resolves the relative form against `API_BASE_URL` on its own, which is why every JSON call
/// works and the bug stayed hidden - but the consumers that take a URL *string* and leave
/// HTTP-land cannot: `just_audio`/ExoPlayer fails on a relative URL (the track simply never
/// plays), and `CachedNetworkImage` renders its placeholder. Both go through this function.
///
/// Absolute non-loopback URLs are returned untouched, because a deployment that configures a real
/// CDN base URL (or stores external artwork) must keep pointing at that host.
String? resolveMediaUrl(String? url, String apiBaseUrl) {
  if (url == null || url.isEmpty) {
    return url;
  }

  final Uri? base = Uri.tryParse(apiBaseUrl);

  if (_isAbsolute(url)) {
    // One absolute shape still needs help: a URL the server signed against its own loopback
    // address. Only the API host this client actually talks to can reach that - a phone on the
    // same Wi-Fi has no `localhost` of the PC's. Retarget scheme/host/port onto the API base and
    // keep the path plus the signature query (the signature covers key + expiry, not host).
    if (base != null && base.hasScheme && !_isLoopbackHost(base.host)) {
      final Uri absolute = Uri.parse(url);
      if (_isLoopbackHost(absolute.host)) {
        return base
            .replace(
              path: absolute.path,
              query: absolute.query.isEmpty ? null : absolute.query,
            )
            .toString();
      }
    }
    return url;
  }

  if (base == null || !base.hasScheme) {
    // Nothing sensible to resolve against; hand back what we were given so the failure is at least
    // the same one the caller would have had without us.
    return url;
  }

  if (url.startsWith('/')) {
    // Rooted path (`/api/v1/media/…`): keep the scheme and host, replace the base path. The query
    // string travels with it, which is what carries `expires` and `signature`.
    final Uri? relative = Uri.tryParse(url);
    return relative == null ? url : base.resolveUri(relative).toString();
  }

  // Bare path (`images/2026/10/art.jpg`): join it onto the base *directory*. `Uri.resolve` would
  // drop the last segment of the base path here (RFC 3986 treats it as a file name), turning
  // `/api/v1` + `images/x` into `/api/images/x` - not what a storage object key means.
  return '${_trimTrailingSlash(apiBaseUrl)}/$url';
}

String _trimTrailingSlash(String value) =>
    value.endsWith('/') ? value.substring(0, value.length - 1) : value;

bool _isAbsolute(String url) =>
    url.startsWith('http://') || url.startsWith('https://') || url.startsWith('data:');

bool _isLoopbackHost(String host) {
  switch (host.toLowerCase()) {
    case 'localhost':
    case '127.0.0.1':
    case '0.0.0.0':
    case '::1':
      return true;
    default:
      return false;
  }
}
