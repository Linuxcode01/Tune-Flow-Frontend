import 'package:flutter/material.dart';

/// Key names for [SharedPreferences] and secure storage. Declared as constants so a typo becomes a
/// compile error instead of a silently lost setting.
class StorageKeys {
  const StorageKeys._();

  static const String accessToken = 'tuneflow.access_token';
  static const String refreshToken = 'tuneflow.refresh_token';
  static const String accessTokenExpiry = 'tuneflow.access_token_expiry';
  static const String cachedUser = 'tuneflow.cached_user';

  static const String themeMode = 'tuneflow.theme_mode';
  static const String lastSearchQuery = 'tuneflow.last_search_query';
  static const String downloadWifiOnly = 'tuneflow.download_wifi_only';
  static const String playedSongIds = 'tuneflow.recent_song_ids';
}

/// Sizes, durations and thresholds used across features.
class AppConstants {
  const AppConstants._();

  /// Height of the persistent mini-player that sits above the bottom navigation (docs section 19).
  static const double miniPlayerHeight = 64;

  /// Height of the expanded player's hero artwork.
  static const double playerArtworkSize = 320;

  /// The backend buckets `playCount` once a track passes this many seconds.
  static const int playCountThresholdSeconds = 30;

  /// How often the player flushes progress to `POST /history` while a track is playing.
  static const Duration progressReportInterval = Duration(seconds: 30);

  /// Debounce for the search-as-you-type field (docs section 23).
  static const Duration searchDebounce = Duration(milliseconds: 350);

  /// Hard ceiling on restoring a stored session at startup.
  ///
  /// The splash screen is only left when the auth status resolves, so this is what guarantees the app
  /// can never be trapped on it - whether the cause is a slow network, a hung platform channel, or an
  /// unexpected error from secure storage.
  static const Duration sessionRestoreTimeout = Duration(seconds: 8);

  /// Ceiling on a single keystore read/write. A hung keyring must not stall startup.
  static const Duration secureStorageTimeout = Duration(seconds: 5);

  /// Animation budget: long enough to feel smooth, short enough not to slow the UI down.
  static const Duration shortAnimation = Duration(milliseconds: 180);
  static const Duration mediumAnimation = Duration(milliseconds: 280);

  static const double cardRadius = 12;
  static const double sheetRadius = 24;

  static const EdgeInsets screenPadding = EdgeInsets.symmetric(horizontal: 16);

  /// Optional artwork fallbacks, keyed by entity kind.
  static const List<Color> artworkPalette = <Color>[
    Color(0xFF1DB954),
    Color(0xFF6C63FF),
    Color(0xFFE91E63),
    Color(0xFFFF9800),
    Color(0xFF00BCD4),
    Color(0xFF9C27B0),
  ];
}
