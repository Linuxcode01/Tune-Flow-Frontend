import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tuneflow/core/constants/app_constants.dart';
import 'package:tuneflow/core/error/app_exception.dart';
import 'package:tuneflow/core/network/session_events.dart';
import 'package:tuneflow/core/providers/core_providers.dart';
import 'package:tuneflow/core/utils/app_logger.dart';
import 'package:tuneflow/features/auth/data/datasources/auth_remote_datasource.dart';
import 'package:tuneflow/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:tuneflow/features/auth/domain/entities/auth_session.dart';
import 'package:tuneflow/features/auth/domain/entities/user.dart';
import 'package:tuneflow/features/auth/domain/repositories/auth_repository.dart';
import 'package:tuneflow/features/auth/domain/usecases/auth_usecases.dart';

// ---------------------------------------------------------------------------------------------
// Wiring (data + domain)
// ---------------------------------------------------------------------------------------------

final Provider<AuthRemoteDataSource> authRemoteDataSourceProvider =
    Provider<AuthRemoteDataSource>(
  (Ref ref) => AuthRemoteDataSource(ref.watch(apiClientProvider)),
  name: 'authRemoteDataSource',
);

final Provider<AuthRepository> authRepositoryProvider = Provider<AuthRepository>(
  (Ref ref) => AuthRepositoryImpl(
    remote: ref.watch(authRemoteDataSourceProvider),
    tokenStorage: ref.watch(tokenStorageProvider),
  ),
  name: 'authRepository',
);

final Provider<LoginUseCase> loginUseCaseProvider = Provider<LoginUseCase>(
  (Ref ref) => LoginUseCase(ref.watch(authRepositoryProvider)),
);

final Provider<RegisterUseCase> registerUseCaseProvider = Provider<RegisterUseCase>(
  (Ref ref) => RegisterUseCase(ref.watch(authRepositoryProvider)),
);

final Provider<LogoutUseCase> logoutUseCaseProvider = Provider<LogoutUseCase>(
  (Ref ref) => LogoutUseCase(ref.watch(authRepositoryProvider)),
);

final Provider<RestoreSessionUseCase> restoreSessionUseCaseProvider =
    Provider<RestoreSessionUseCase>(
  (Ref ref) => RestoreSessionUseCase(ref.watch(authRepositoryProvider)),
);

// ---------------------------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------------------------

/// Owns the session. A synchronous [Notifier] (not `AsyncNotifier`) because the router guard needs
/// to read the status during a rebuild without awaiting a future.
///
/// The invariant this class must uphold, and which every method below is written to guarantee:
/// **the status never stays [AuthStatus.unknown] once startup has finished.** `unknown` is what pins
/// the router to the splash screen, so any code path that can leave it set is a bug that traps the
/// user on a spinner with no way forward.
class AuthController extends Notifier<AuthState> {
  StreamSubscription<SessionEvent>? _sessionSubscription;

  @override
  AuthState build() {
    // The interceptor signals here when a refresh token is rejected, so the UI can react even if
    // the failure happened on a background request.
    _sessionSubscription = ref.read(sessionEventsProvider).stream.listen(_onSessionEvent);
    ref.onDispose(() => _sessionSubscription?.cancel());

    // Kick off restoration immediately; the router holds the splash screen until this resolves.
    unawaited(restore());
    return const AuthState();
  }

  /// Restores a persisted session (cold start). Safe to call repeatedly.
  ///
  /// Bounded by [AppConstants.sessionRestoreTimeout] and guarded by a catch-all: a stored session is
  /// a convenience, never something worth trapping the user behind.
  Future<void> restore() async {
    try {
      final AuthSession? session = await ref
          .read(restoreSessionUseCaseProvider)
          .call()
          .timeout(AppConstants.sessionRestoreTimeout);

      state = session == null
          ? const AuthState.unauthenticated()
          : AuthState(status: AuthStatus.authenticated, user: session.user);
    } on TimeoutException catch (error) {
      AppLogger.warn('Session restore timed out - continuing signed out', error: error);
      state = const AuthState.unauthenticated(
        errorMessage: 'We could not restore your session. Please sign in.',
      );
    } catch (error, stackTrace) {
      // Catch everything, deliberately. Anything escaping here would leave the status at `unknown`
      // and the app on the splash screen forever - the exact failure this guard exists to prevent.
      AppLogger.error('Session restore failed', error: error, stackTrace: stackTrace);
      state = const AuthState.unauthenticated(
        errorMessage: 'We could not restore your session. Please sign in.',
      );
    }
  }

  Future<void> login({required String email, required String password}) async {
    // `authenticating`, not `unknown`: the splash screen is for cold-start restoration only, and
    // reusing it here would yank the user off the login form mid-request.
    state = const AuthState(status: AuthStatus.authenticating);
    try {
      final AuthSession session = await ref.read(loginUseCaseProvider).call(
            email: email,
            password: password,
          );
      state = AuthState(status: AuthStatus.authenticated, user: session.user);
    } catch (error, stackTrace) {
      final AppException failure = toAppException(error, stackTrace);
      state = AuthState.unauthenticated(errorMessage: failure.message);
      // Re-thrown as an AppException so the form can render it; the state is already resolved either
      // way, so a caller that ignores the error still cannot get stuck.
      Error.throwWithStackTrace(failure, stackTrace);
    }
  }

  Future<void> register({
    required String name,
    required String email,
    required String password,
    bool asArtist = false,
  }) async {
    state = const AuthState(status: AuthStatus.authenticating);
    try {
      final AuthSession session = await ref.read(registerUseCaseProvider).call(
            name: name,
            email: email,
            password: password,
            asArtist: asArtist,
          );
      state = AuthState(status: AuthStatus.authenticated, user: session.user);
    } catch (error, stackTrace) {
      final AppException failure = toAppException(error, stackTrace);
      state = AuthState.unauthenticated(errorMessage: failure.message);
      Error.throwWithStackTrace(failure, stackTrace);
    }
  }

  Future<void> logout() async {
    await ref.read(logoutUseCaseProvider).call();
    ref.read(sessionEventsProvider).emit(SessionEvent.signedOut);
    state = const AuthState.unauthenticated();
  }

  /// Escape hatch for the splash screen: give up on restoring and go to the login form.
  ///
  /// Without this, a user whose stored session cannot be read has no way past the splash screen even
  /// though signing in again would work perfectly.
  void continueAsSignedOut() {
    state = const AuthState.unauthenticated();
  }

  /// Refreshes the cached profile (`GET /users/me`) - used after a profile edit.
  Future<void> refreshUser() async {
    if (!state.isAuthenticated) {
      return;
    }
    try {
      final User user = await ref.read(authRepositoryProvider).fetchCurrentUser();
      state = state.copyWith(user: user);
    } on AppException catch (error) {
      AppLogger.warn('Failed to refresh profile', error: error);
    }
  }

  /// Lets the profile screen apply an edited user without another round trip.
  void updateUser(User user) => state = state.copyWith(user: user);

  void _onSessionEvent(SessionEvent event) {
    if (event == SessionEvent.expired || event == SessionEvent.signedOut) {
      state = AuthState.unauthenticated(
        errorMessage: event == SessionEvent.expired ? 'Your session expired. Please sign in again.' : null,
      );
    }
  }
}

final NotifierProvider<AuthController, AuthState> authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new, name: 'authController');

/// Convenience selector used across the app (profile header, greeting, artist checks).
final Provider<User?> currentUserProvider = Provider<User?>(
  (Ref ref) => ref.watch(authControllerProvider).user,
  name: 'currentUser',
);

final Provider<bool> isAuthenticatedProvider = Provider<bool>(
  (Ref ref) => ref.watch(authControllerProvider).isAuthenticated,
  name: 'isAuthenticated',
);
