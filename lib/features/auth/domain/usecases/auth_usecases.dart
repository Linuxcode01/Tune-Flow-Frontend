import 'package:tuneflow/features/auth/domain/entities/auth_session.dart';
import 'package:tuneflow/features/auth/domain/repositories/auth_repository.dart';

/// Use cases for the auth flow.
///
/// Each one is a named, testable unit of intent. They are thin by design - the value is that the
/// presentation layer states *what* it wants ("sign this user in") rather than *how* (call the
/// repository, then the token store, then...), which keeps the controller's intent readable.

/// Signs a user in and returns the resulting session.
class LoginUseCase {
  const LoginUseCase(this._repository);

  final AuthRepository _repository;

  Future<AuthSession> call({required String email, required String password}) {
    return _repository.login(email: email.trim().toLowerCase(), password: password);
  }
}

/// Creates an account, optionally as an artist.
class RegisterUseCase {
  const RegisterUseCase(this._repository);

  final AuthRepository _repository;

  Future<AuthSession> call({
    required String name,
    required String email,
    required String password,
    bool asArtist = false,
  }) {
    return _repository.register(
      name: name.trim(),
      email: email.trim().toLowerCase(),
      password: password,
      asArtist: asArtist,
    );
  }
}

/// Restores a persisted session on cold start, without a network call when the token is still good.
class RestoreSessionUseCase {
  const RestoreSessionUseCase(this._repository);

  final AuthRepository _repository;

  Future<AuthSession?> call() => _repository.restoreSession();
}

/// Signs out: revokes the refresh token server-side, then clears local credentials.
///
/// Local credentials are cleared even when the revoke call fails - otherwise a user on a plane
/// could not sign out of their own device.
class LogoutUseCase {
  const LogoutUseCase(this._repository);

  final AuthRepository _repository;

  Future<void> call() => _repository.logout();
}
