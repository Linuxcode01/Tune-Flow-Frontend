/// What `POST /uploads/audio` and `POST /uploads/image` return.
///
/// [objectKey] is the value the song metadata call persists; [previewUrl] is a short-lived signed URL
/// for showing the artwork (or playing the track) before it is published, which is why it is not the
/// thing that gets saved.
class UploadResult {
  const UploadResult({
    required this.objectKey,
    this.previewUrl,
    this.expiresInSeconds,
    this.durationSeconds,
    this.bitrateKbps,
    this.contentType,
    this.sizeBytes,
    this.checksum,
  });

  factory UploadResult.fromJson(Map<String, dynamic> json) {
    return UploadResult(
      objectKey: json['objectKey'] as String? ?? '',
      previewUrl: json['previewUrl'] as String?,
      expiresInSeconds: (json['expiresInSeconds'] as num?)?.toInt(),
      durationSeconds: (json['durationSeconds'] as num?)?.toInt(),
      bitrateKbps: (json['bitrateKbps'] as num?)?.toInt(),
      contentType: json['contentType'] as String?,
      sizeBytes: (json['sizeBytes'] as num?)?.toInt(),
      checksum: json['checksum'] as String?,
    );
  }

  final String objectKey;
  final String? previewUrl;
  final int? expiresInSeconds;

  /// Filled in by FFprobe/FFmpeg when the deployment has it; `null` otherwise, which is why the
  /// upload form keeps duration editable rather than trusting this blindly.
  final int? durationSeconds;

  final int? bitrateKbps;
  final String? contentType;
  final int? sizeBytes;
  final String? checksum;

  bool get isUsable => objectKey.isNotEmpty;
}
