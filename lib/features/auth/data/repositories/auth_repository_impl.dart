import 'package:tuneflow/core/error/app_exception.dart';
import 'package:tuneflow/core/storage/auth_tokens.dart';
import 'package:tuneflow/core/storage/token_storage.dart';
import 'package:tuneflow/core/utils/app_logger.dart';
import 'package:tuneflow/features/auth/data/datasources/auth_remote_datasource.dart';
import 'package:tuneflow/features/auth/domain/entities/auth_session.dart';
import 'package:tuneflow/features/auth/domain/entities/user.dart';
import 'package:tuneflow/features/auth/domain/repositories/auth_repository.dart';

/// Default [AuthRepository]: coordinates the API and the secure token store.
class AuthRepositoryImpl implements AuthRepository {
  const AuthRepositoryImpl({
    required AuthRemoteDataSource remote,
    required TokenStorage tokenStorage,
  })  : _remote = remote,
        _tokenStorage = tokenStorage;

  final AuthRemoteDataSource _remote;
  final TokenStorage _tokenStorage;

  @override
  Future<AuthSession> register({
    required String name,
    required String email,
    required String password,
    required bool asArtist,
  }) async {
    final AuthSession session = await _remote.register(
      name: name,
      email: email,
      password: password,
      asArtist: asArtist,
    );
    await _persist(session);
    return session;
  }

  @override
  Future<AuthSession> login({required String email, required String password}) async {
    final AuthSession session = await _remote.login(email: email, password: password);
    await _persist(session);
    return session;
  }

  @override
  Future<void> logout() async {
    final AuthTokens? tokens = _tokenStorage.cached ?? await _tokenStorage.read();
    if (tokens != null && tokens.refreshToken.isNotEmpty) {
      try {
        await _remote.logout(tokens.refreshToken);
      } on AppException catch (error) {
        // Best effort: the local session must be cleared regardless of what the server says.
        AppLogger.warn('Server-side logout failed, clearing local session', error: error);
      }
    }
    await _tokenStorage.clear();
  }

  @override
  Future<AuthSession?> restoreSession() async {
    final AuthTokens? tokens = await _tokenStorage.read();
    if (tokens == null) {
      return null;
    }

    try {
      // The Dio interceptor silently rotates an expired access token, so this call doubles as the
      // session validation for a returning user.
      final User user = await _remote.currentUser();
      await _tokenStorage.cacheUser(user.toJson());
      return AuthSession(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
        expiresInSeconds: tokens.accessTokenExpiresAt.difference(DateTime.now().toUtc()).inSeconds,
        user: user,
      );
    } on SessionExpiredException {
      await _tokenStorage.clear();
      return null;
    } on ApiException catch (error) {
      if (error.isUnauthorized || error.isForbidden) {
        await _tokenStorage.clear();
        return null;
      }
      rethrow;
    } on NetworkException {
      // Offline cold start: trust the cached profile so the app opens straight into the library
      // instead of blocking on a network round trip. Fresh data arrives when connectivity returns.
      final Map<String, dynamic>? cached = await _tokenStorage.readCachedUser();
      if (cached == null) {
        rethrow;
      }
      AppLogger.info('Restored session from cache (offline)');
      return AuthSession(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
        expiresInSeconds: tokens.accessTokenExpiresAt.difference(DateTime.now().toUtc()).inSeconds,
        user: User.fromJson(cached),
      );
    } catch (error, stackTrace) {
      // Last line of defence, deliberately last: an `on` clause after a bare catch would be dead
      // code. Anything unexpected here (a platform-channel failure, a malformed cached payload) is
      // treated as "no stored session" rather than being allowed to escape - the caller cannot leave
      // the splash screen if this throws.
      AppLogger.error('Unexpected failure while restoring the session',
          error: error, stackTrace: stackTrace);
      await _tokenStorage.clear();
      return null;
    }
  }

  @override
  Future<User> fetchCurrentUser() async {
    final User user = await _remote.currentUser();
    await _tokenStorage.cacheUser(user.toJson());
    return user;
  }

  @override
  Future<User> updateProfile({String? name, String? profileImageUrl}) async {
    final User user = await _remote.updateProfile(name: name, profileImageUrl: profileImageUrl);
    await _tokenStorage.cacheUser(user.toJson());
    return user;
  }

  @override
  Future<void> changePassword({required String currentPassword, required String newPassword}) {
    return _remote.changePassword(currentPassword: currentPassword, newPassword: newPassword);
  }

  @override
  Future<String?> requestPasswordReset(String email) => _remote.requestPasswordReset(email);

  @override
  Future<void> resetPassword({required String token, required String newPassword}) {
    return _remote.resetPassword(token: token, newPassword: newPassword);
  }

  /// Persists the token pair (secure storage) and the profile cache (for instant cold start).
  Future<void> _persist(AuthSession session) async {
    await _tokenStorage.write(
      AuthTokens(
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
        accessTokenExpiresAt:
            DateTime.now().toUtc().add(Duration(seconds: session.expiresInSeconds)),
      ),
    );
    await _tokenStorage.cacheUser(session.user.toJson());
  }
}
