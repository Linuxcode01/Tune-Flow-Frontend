import 'package:tuneflow/features/auth/domain/entities/auth_session.dart';
import 'package:tuneflow/features/auth/domain/entities/user.dart';

/// The auth feature's contract with the outside world.
///
/// The presentation layer depends on this interface only, which is what lets the tests swap in a
/// fake repository without touching Dio or the keystore (docs section 9).
abstract interface class AuthRepository {
  /// Creates an account and returns a ready-to-use session (the API logs the user in on register).
  Future<AuthSession> register({
    required String name,
    required String email,
    required String password,
    required bool asArtist,
  });

  Future<AuthSession> login({required String email, required String password});

  /// Revokes the current refresh token server-side, then clears local credentials.
  Future<void> logout();

  /// Restores a session from secure storage at startup.
  ///
  /// Returns null when there is nothing stored; throws [SessionExpiredException] when the stored
  /// refresh token is no longer valid.
  Future<AuthSession?> restoreSession();

  /// Fetches the current profile (`GET /users/me`), used to refresh the cached user.
  Future<User> fetchCurrentUser();

  Future<User> updateProfile({String? name, String? profileImageUrl});

  Future<void> changePassword({required String currentPassword, required String newPassword});

  /// Requests a reset link; the API returns the token in dev so the flow is testable.
  Future<String?> requestPasswordReset(String email);

  Future<void> resetPassword({required String token, required String newPassword});
}
