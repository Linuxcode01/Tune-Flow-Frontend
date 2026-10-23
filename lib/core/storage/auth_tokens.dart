/// The credential pair held in secure storage.
///
/// This is the persistence-level view of a session; the auth feature owns the richer domain
/// `AuthSession` (tokens + user profile) and maps to/from this type at the data-source boundary.
class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.accessTokenExpiresAt,
  });

  factory AuthTokens.fromJson(Map<String, dynamic> json) {
    return AuthTokens(
      accessToken: json['accessToken'] as String? ?? '',
      refreshToken: json['refreshToken'] as String? ?? '',
      accessTokenExpiresAt: DateTime.tryParse(json['accessTokenExpiresAt'] as String? ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
    );
  }

  final String accessToken;
  final String refreshToken;

  /// Access tokens live 15 minutes; the client refreshes before this moment rather than after a
  /// failed request, so playback never stutters on an expired token.
  final DateTime accessTokenExpiresAt;

  /// Treats a token as stale shortly before its real expiry.
  bool isExpired({Duration leeway = const Duration(seconds: 30)}) {
    return DateTime.now().toUtc().isAfter(accessTokenExpiresAt.subtract(leeway));
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'accessTokenExpiresAt': accessTokenExpiresAt.toIso8601String(),
      };

  AuthTokens copyWith({String? accessToken, String? refreshToken, DateTime? accessTokenExpiresAt}) {
    return AuthTokens(
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      accessTokenExpiresAt: accessTokenExpiresAt ?? this.accessTokenExpiresAt,
    );
  }

  @override
  String toString() => 'AuthTokens(expiresAt: $accessTokenExpiresAt)';
}
