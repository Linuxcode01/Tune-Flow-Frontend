/// A short-lived signed streaming URL (`GET /songs/{id}/stream`).
///
/// Signed URLs are deliberate (docs section 17): audio is served by object storage or the CDN, never
/// proxied through the API, and the URL stops working shortly after it is issued. The client must
/// therefore treat it as disposable - re-fetch it rather than cache it for later playback.
class StreamUrl {
  const StreamUrl({
    required this.songId,
    required this.url,
    required this.expiresAt,
    this.title,
    this.hls = false,
    this.bitrateKbps,
    this.contentType,
  });

  factory StreamUrl.fromJson(Map<String, dynamic> json) {
    return StreamUrl(
      songId: json['songId'] as String? ?? '',
      url: json['url'] as String? ?? '',
      expiresAt: DateTime.tryParse(json['expiresAt'] as String? ?? '')?.toUtc() ??
          DateTime.now().toUtc().add(const Duration(minutes: 10)),
      title: json['title'] as String?,
      hls: json['hls'] as bool? ?? false,
      bitrateKbps: (json['bitrateKbps'] as num?)?.toInt(),
      contentType: json['contentType'] as String?,
    );
  }

  /// Same track, but with [url] replaced - used after a relative API URL has been resolved against
  /// the client's base URL (see `resolveMediaUrl`).
  StreamUrl withUrl(String absoluteUrl) => StreamUrl(
        songId: songId,
        url: absoluteUrl,
        expiresAt: expiresAt,
        title: title,
        hls: hls,
        bitrateKbps: bitrateKbps,
        contentType: contentType,
      );

  final String songId;
  final String url;
  final DateTime expiresAt;
  final String? title;
  final bool hls;
  final int? bitrateKbps;
  final String? contentType;

  bool get isUsable => url.isNotEmpty;

  /// True when the URL should be re-requested before playback continues.
  ///
  /// A margin is subtracted so a track that is already playing does not die mid-song - the failure
  /// mode users notice immediately.
  bool isExpiringWithin(Duration margin) =>
      DateTime.now().toUtc().isAfter(expiresAt.subtract(margin));
}
