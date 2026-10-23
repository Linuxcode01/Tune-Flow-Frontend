import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:tuneflow/core/constants/app_constants.dart';
import 'package:tuneflow/core/storage/auth_tokens.dart';
import 'package:tuneflow/core/utils/app_logger.dart';

/// Persists credentials in the platform keystore (Keychain / EncryptedSharedPreferences).
///
/// A small in-memory mirror keeps the Dio interceptor synchronous on the hot path: the token is
/// read once per app launch and served from memory afterwards, while every write is mirrored to
/// secure storage so a restart restores the session (docs section 10).
class TokenStorage {
  TokenStorage({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              // `AndroidOptions(encryptedSharedPreferences: true)` was removed in
              // flutter_secure_storage 11: the Jetpack Security backend is gone and the default is
              // now AES-GCM under an RSA-OAEP-wrapped key. The platform default is what we want.
              aOptions: AndroidOptions(),
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
            );

  final FlutterSecureStorage _secureStorage;
  AuthTokens? _cached;

  /// The token pair currently held in memory, if the session has been restored.
  AuthTokens? get cached => _cached;

  /// Reads the persisted session, hydrating the memory cache.
  Future<AuthTokens?> read() async {
    if (_cached != null) {
      return _cached;
    }
    try {
      // Every keystore call is bounded. On some platforms (a Linux desktop without a keyring, a
      // Windows credential store that prompts) the plugin can block indefinitely, and a hung read
      // here is indistinguishable from a hung splash screen to the user.
      final String? accessToken = await _secureStorage
          .read(key: StorageKeys.accessToken)
          .timeout(AppConstants.secureStorageTimeout);
      final String? refreshToken = await _secureStorage
          .read(key: StorageKeys.refreshToken)
          .timeout(AppConstants.secureStorageTimeout);
      if (accessToken == null || refreshToken == null || accessToken.isEmpty) {
        return null;
      }
      final String? expiry = await _secureStorage
          .read(key: StorageKeys.accessTokenExpiry)
          .timeout(AppConstants.secureStorageTimeout);
      _cached = AuthTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
        accessTokenExpiresAt: DateTime.tryParse(expiry ?? '')?.toUtc() ?? DateTime.now().toUtc(),
      );
      return _cached;
    } catch (error, stackTrace) {
      // A corrupt keystore entry must not brick the app: treat it as "signed out".
      AppLogger.error('Failed to read stored credentials', error: error, stackTrace: stackTrace);
      await clear();
      return null;
    }
  }

  /// Persists a fresh token pair and refreshes the memory cache.
  ///
  /// The memory cache is updated first: even if the keystore write times out, the session works for
  /// the rest of this app run - it just will not survive a restart.
  Future<void> write(AuthTokens tokens) async {
    _cached = tokens;
    try {
      await _secureStorage
          .write(key: StorageKeys.accessToken, value: tokens.accessToken)
          .timeout(AppConstants.secureStorageTimeout);
      await _secureStorage
          .write(key: StorageKeys.refreshToken, value: tokens.refreshToken)
          .timeout(AppConstants.secureStorageTimeout);
      await _secureStorage
          .write(
            key: StorageKeys.accessTokenExpiry,
            value: tokens.accessTokenExpiresAt.toIso8601String(),
          )
          .timeout(AppConstants.secureStorageTimeout);
    } catch (error) {
      AppLogger.warn('Could not persist credentials - session is memory-only', error: error);
    }
  }

  /// Removes every credential. Called on logout and whenever a refresh is rejected.
  Future<void> clear() async {
    _cached = null;
    try {
      await _secureStorage
          .delete(key: StorageKeys.accessToken)
          .timeout(AppConstants.secureStorageTimeout);
      await _secureStorage
          .delete(key: StorageKeys.refreshToken)
          .timeout(AppConstants.secureStorageTimeout);
      await _secureStorage
          .delete(key: StorageKeys.accessTokenExpiry)
          .timeout(AppConstants.secureStorageTimeout);
    } catch (error, stackTrace) {
      AppLogger.warn('Failed to clear credentials', error: error);
      AppLogger.debug('clear() stack trace: $stackTrace');
    }
  }

  /// Caches the signed-in user so the app can render immediately on cold start, before the profile
  /// request completes. Not a security boundary - it only avoids a blank screen.
  Future<void> cacheUser(Map<String, dynamic> user) async {
    try {
      await _secureStorage
          .write(key: StorageKeys.cachedUser, value: jsonEncode(user))
          .timeout(AppConstants.secureStorageTimeout);
    } catch (error) {
      // The profile cache is only a cold-start nicety; losing it must never surface to the user.
      AppLogger.debug('Could not cache the user profile: $error');
    }
  }

  Future<Map<String, dynamic>?> readCachedUser() async {
    final String? raw = await _secureStorage
        .read(key: StorageKeys.cachedUser)
        .timeout(AppConstants.secureStorageTimeout);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final dynamic decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }
}
