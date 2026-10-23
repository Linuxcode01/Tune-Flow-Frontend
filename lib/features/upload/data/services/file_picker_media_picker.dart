import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:tuneflow/core/error/app_exception.dart';
import 'package:tuneflow/features/upload/domain/entities/media_file.dart';
import 'package:tuneflow/features/upload/domain/services/media_picker.dart';

/// [MediaPicker] backed by `file_picker` (Storage Access Framework on Android, the document picker on
/// iOS, a native dialog on desktop, an `<input type="file">` on the web).
///
/// The allowed extensions are the *server's* allow-list (`tuneflow.media.allowed-audio-formats`), so
/// the picker cannot offer a file the API would reject with `UNSUPPORTED_MEDIA_TYPE`. That is a UX
/// decision rather than a security one - the server still validates.
class FilePickerMediaPicker implements MediaPicker {
  const FilePickerMediaPicker();

  static const List<String> audioExtensions = <String>['mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg'];
  static const List<String> imageExtensions = <String>['jpg', 'jpeg', 'png', 'webp'];

  @override
  Future<MediaFile?> pickAudio() => _pick(audioExtensions);

  @override
  Future<MediaFile?> pickImage() => _pick(imageExtensions);

  /// `file_picker` 13 returns the picked file and reads its bytes on demand, rather than returning a
  /// path (which does not exist on the web) or eagerly carrying the bytes through the result object.
  /// Reading them here means the upload path never touches `dart:io`.
  Future<MediaFile?> _pick(List<String> extensions) async {
    final PlatformFile? file;
    try {
      file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: extensions,
      );
    } on Exception catch (error) {
      // A picker failure is a device/service problem, not a server error - DeviceException keeps it
      // out of the "check your connection" copy that ApiException drives.
      throw DeviceException('Could not open the file picker: $error');
    }

    // A null result is the user cancelling, which is a normal outcome rather than an error.
    if (file == null) {
      return null;
    }

    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } on Exception catch (error) {
      throw DeviceException('That file could not be read: $error');
    }

    if (bytes.isEmpty) {
      throw const DeviceException('That file could not be read. Try picking it again.');
    }

    // `lengthSync()` is the size the native picker already reported and costs no I/O; the byte count
    // is the fallback for platforms that do not report one.
    return MediaFile(name: file.name, sizeBytes: file.lengthSync() ?? bytes.length, bytes: bytes);
  }
}
