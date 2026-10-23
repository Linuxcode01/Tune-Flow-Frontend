import 'package:tuneflow/features/upload/domain/entities/media_file.dart';

/// Opens the platform's file browser.
///
/// An interface rather than a direct `file_picker` call so the upload form can be driven in a widget
/// test without a native picker: the test overrides this provider, which is the same seam the rest of
/// the app uses for anything platform-shaped.
abstract class MediaPicker {
  /// Returns `null` when the user cancels - cancelling is a normal outcome, not an error.
  Future<MediaFile?> pickAudio();

  Future<MediaFile?> pickImage();
}
