import 'package:tuneflow/core/constants/api_endpoints.dart';
import 'package:tuneflow/core/network/api_client.dart';
import 'package:tuneflow/features/auth/domain/entities/auth_session.dart';
import 'package:tuneflow/features/auth/domain/entities/user.dart';

/// Talks to the `/auth/**` and `/users/me` endpoints.
///
/// Returns domain entities directly: the envelope has already been unwrapped by [ApiClient], so
/// there is nothing left for a separate DTO to do.
class AuthRemoteDataSource {
  const AuthRemoteDataSource(this._client);

  final ApiClient _client;

  Future<AuthSession> register({
    required String name,
    required String email,
    required String password,
    required bool asArtist,
  }) async {
    final Map<String, dynamic> data = await _client.post(
      ApiEndpoints.register,
      body: <String, dynamic>{
        'name': name,
        'email': email,
        'password': password,
        // The API creates the artist profile as part of registration, so an artist account is
        // immediately usable for uploads.
        if (asArtist) 'role': 'ARTIST',
      },
    );
    return AuthSession.fromJson(data);
  }

  Future<AuthSession> login({required String email, required String password}) async {
    final Map<String, dynamic> data = await _client.post(
      ApiEndpoints.login,
      body: <String, dynamic>{'email': email, 'password': password},
    );
    return AuthSession.fromJson(data);
  }

  Future<void> logout(String refreshToken) async {
    await _client.post(
      ApiEndpoints.logout,
      body: <String, dynamic>{'refreshToken': refreshToken},
    );
  }

  Future<User> currentUser() async {
    final Map<String, dynamic> data = await _client.getJson(ApiEndpoints.me);
    return User.fromJson(data);
  }

  Future<User> updateProfile({String? name, String? profileImageUrl}) async {
    final Map<String, dynamic> data = await _client.patch(
      ApiEndpoints.me,
      body: <String, dynamic>{
        if (name != null) 'name': name,
        if (profileImageUrl != null) 'profileImageUrl': profileImageUrl,
      },
    );
    return User.fromJson(data);
  }

  /// `PUT /users/me/password` - the odd verb is the API's, and changing a password is idempotent in
  /// the sense that it replaces the credential, so `PUT` is a defensible choice server-side.
  Future<void> changePassword({required String currentPassword, required String newPassword}) async {
    await _client.put(
      ApiEndpoints.changePassword,
      body: <String, dynamic>{
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      },
    );
  }

  /// Returns the reset token when the server exposes it (dev profile), otherwise null.
  Future<String?> requestPasswordReset(String email) async {
    final Map<String, dynamic> data = await _client.post(
      ApiEndpoints.forgotPassword,
      body: <String, dynamic>{'email': email},
    );
    return data['resetToken'] as String?;
  }

  Future<void> resetPassword({required String token, required String newPassword}) async {
    await _client.post(
      ApiEndpoints.resetPassword,
      body: <String, dynamic>{'token': token, 'newPassword': newPassword},
    );
  }
}
