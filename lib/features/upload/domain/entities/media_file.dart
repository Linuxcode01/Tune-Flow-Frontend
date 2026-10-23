import 'dart:typed_data';

/// A file the user picked, carried as bytes rather than a path.
///
/// Two reasons for bytes: the backend caps audio at 100 MB and images at 10 MB, so a picked file is
/// small enough to hold; and paths are a platform detail that does not exist on the web, where the
/// picker hands over bytes. Keeping the path out of the model means the upload path has no `dart:io`
/// in it at all, which is what lets this code compile for every target the client scaffolds.
class MediaFile {
  const MediaFile({
    required this.name,
    required this.sizeBytes,
    required this.bytes,
  });

  /// Original filename, including the extension - the backend validates uploads by extension.
  final String name;

  final int sizeBytes;

  final Uint8List bytes;

  String get extension {
    final int dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  /// Human-readable size, used in the review step so the user can see what they are about to send.
  String get readableSize {
    if (sizeBytes >= 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
  }

  @override
  String toString() => 'MediaFile($name, $readableSize)';
}
