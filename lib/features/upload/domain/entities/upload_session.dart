/// A chunked upload session (`POST /uploads/audio/initiate`).
///
/// The server decides the chunk size and the part count; the client's job is to slice the file
/// accordingly. [receivedParts] is what makes the flow resumable - it lists the parts the server
/// already holds, so a session reopened after a dropped connection only sends the gaps.
class UploadSession {
  const UploadSession({
    required this.uploadId,
    required this.chunkSizeBytes,
    required this.partCount,
    required this.sizeBytes,
    this.receivedParts = const <int>[],
    this.expiresAt,
  });

  factory UploadSession.fromJson(Map<String, dynamic> json) {
    return UploadSession(
      uploadId: json['uploadId'] as String? ?? '',
      chunkSizeBytes: (json['chunkSizeBytes'] as num?)?.toInt() ?? 0,
      partCount: (json['partCount'] as num?)?.toInt() ?? 0,
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      receivedParts: (json['receivedParts'] as List<dynamic>? ?? const <dynamic>[])
          .map((dynamic part) => (part as num).toInt())
          .toList(growable: false),
      expiresAt: DateTime.tryParse(json['expiresAt'] as String? ?? '')?.toUtc(),
    );
  }

  final String uploadId;
  final int chunkSizeBytes;
  final int partCount;
  final int sizeBytes;
  final List<int> receivedParts;
  final DateTime? expiresAt;

  bool get isUsable => uploadId.isNotEmpty && chunkSizeBytes > 0 && partCount > 0;

  Set<int> get receivedPartSet => receivedParts.toSet();

  @override
  String toString() =>
      'UploadSession($uploadId, $partCount x $chunkSizeBytes bytes, received: ${receivedParts.length})';
}
