/// Client-side form validation.
///
/// These mirror the backend's Bean Validation rules exactly (docs section 30), so a user never
/// waits for a round trip to learn that a password is too short - and the server remains the
/// authority, since it re-validates everything.
class Validators {
  const Validators._();

  static final RegExp _email = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');
  static final RegExp _hasLetter = RegExp('[A-Za-z]');
  static final RegExp _hasDigit = RegExp(r'\d');

  static String? email(String? value) {
    final String input = (value ?? '').trim();
    if (input.isEmpty) {
      return 'Email is required';
    }
    if (!_email.hasMatch(input)) {
      return 'Enter a valid email address';
    }
    return null;
  }

  static String? name(String? value) {
    final String input = (value ?? '').trim();
    if (input.isEmpty) {
      return 'Name is required';
    }
    if (input.length < 2) {
      return 'Name must be at least 2 characters';
    }
    if (input.length > 120) {
      return 'Name must be 120 characters or fewer';
    }
    return null;
  }

  /// Matches the backend rule: at least 8 characters, with a letter and a digit.
  static String? password(String? value) {
    final String input = value ?? '';
    if (input.isEmpty) {
      return 'Password is required';
    }
    if (input.length < 8) {
      return 'Password must be at least 8 characters';
    }
    if (!_hasLetter.hasMatch(input) || !_hasDigit.hasMatch(input)) {
      return 'Password must contain at least one letter and one digit';
    }
    return null;
  }

  static String? confirmPassword(String? value, String original) {
    if ((value ?? '').isEmpty) {
      return 'Confirm your password';
    }
    if (value != original) {
      return 'Passwords do not match';
    }
    return null;
  }

  static String? required(String? value, {String field = 'This field'}) {
    if ((value ?? '').trim().isEmpty) {
      return '$field is required';
    }
    return null;
  }

  static String? playlistName(String? value) {
    final String input = (value ?? '').trim();
    if (input.isEmpty) {
      return 'Playlist name is required';
    }
    if (input.length > 120) {
      return 'Playlist name must be 120 characters or fewer';
    }
    return null;
  }
}
