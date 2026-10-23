import 'package:tuneflow/features/auth/domain/entities/user.dart';

/// A signed-in session: the token pair plus the profile it belongs to.
class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresInSeconds,
    required this.user,
  });

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      accessToken: json['accessToken'] as String? ?? '',
      refreshToken: json['refreshToken'] as String? ?? '',
      expiresInSeconds: (json['expiresIn'] as num?)?.toInt() ?? 900,
      user: User.fromJson((json['user'] as Map<String, dynamic>?) ?? const <String, dynamic>{}),
    );
  }

  final String accessToken;
  final String refreshToken;
  final int expiresInSeconds;
  final User user;

  @override
  String toString() => 'AuthSession(user: ${user.email}, expiresIn: ${expiresInSeconds}s)';
}

/// Coarse session state consumed by the router guard.
///
/// * `unknown` — cold start: the stored session is still being restored. The router holds the user on
///   the splash screen rather than flashing the login form at a returning user.
/// * `authenticating` — a sign-in or sign-up request is in flight. Deliberately *not* the same as
///   `unknown`: treating it as "still restoring" would bounce the user from the form to the splash
///   screen the moment they tap Sign in.
/// * `authenticated` / `unauthenticated` — resolved.
enum AuthStatus { unknown, authenticating, authenticated, unauthenticated }

/// Immutable auth state exposed to the widget tree.
class AuthState {
  const AuthState({
    this.status = AuthStatus.unknown,
    this.user,
    this.errorMessage,
  });

  const AuthState.unauthenticated({this.errorMessage})
      : status = AuthStatus.unauthenticated,
        user = null;

  final AuthStatus status;
  final User? user;
  final String? errorMessage;

  bool get isAuthenticated => status == AuthStatus.authenticated;

  /// True while a sign-in/sign-up request is in flight, so forms can show a busy state.
  bool get isAuthenticating => status == AuthStatus.authenticating;

  /// False only during the cold-start restore window, when the router shows the splash screen.
  bool get isResolved => status != AuthStatus.unknown;

  AuthState copyWith({AuthStatus? status, User? user, String? errorMessage}) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      errorMessage: errorMessage,
    );
  }

  @override
  String toString() => 'AuthState($status, user: ${user?.email})';
}
