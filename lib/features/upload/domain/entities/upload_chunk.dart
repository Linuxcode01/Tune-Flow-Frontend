/// One slice of the file, expressed as an inclusive-exclusive byte range.
class UploadChunk {
  const UploadChunk({
    required this.partNumber,
    required this.start,
    required this.end,
  });

  /// 1-based, matching the API's `PUT /uploads/audio/{uploadId}/parts/{partNumber}`.
  final int partNumber;
  final int start;

  /// Exclusive.
  final int end;

  int get length => end - start;

  @override
  String toString() => 'UploadChunk(part $partNumber, bytes $start..${end - 1})';
}

/// Splits [totalBytes] into the parts the server asked for.
///
/// Pure arithmetic on purpose: the slicing rule ("every part is `chunkSize`, the last one is the
/// remainder") is the kind of thing that is easy to get subtly wrong off-by-one, so it is tested on
/// its own rather than only through an HTTP round trip.
List<UploadChunk> planUploadChunks({required int totalBytes, required int chunkSizeBytes}) {
  if (totalBytes <= 0 || chunkSizeBytes <= 0) {
    return const <UploadChunk>[];
  }
  final List<UploadChunk> chunks = <UploadChunk>[];
  int start = 0;
  int partNumber = 1;
  while (start < totalBytes) {
    final int end = start + chunkSizeBytes > totalBytes ? totalBytes : start + chunkSizeBytes;
    chunks.add(UploadChunk(partNumber: partNumber, start: start, end: end));
    start = end;
    partNumber++;
  }
  return chunks;
}
