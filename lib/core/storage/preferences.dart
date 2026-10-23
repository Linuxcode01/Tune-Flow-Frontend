import 'package:shared_preferences/shared_preferences.dart';
import 'package:tuneflow/core/constants/app_constants.dart';

/// Typed access to non-sensitive local settings.
///
/// Wraps [SharedPreferences] so features never deal with stringly-typed keys, and so the whole
/// surface is trivially fakeable in tests.
class Preferences {
  const Preferences(this._prefs);

  final SharedPreferences _prefs;

  String? get themeMode => _prefs.getString(StorageKeys.themeMode);

  Future<void> setThemeMode(String mode) => _prefs.setString(StorageKeys.themeMode, mode);

  bool get downloadWifiOnly => _prefs.getBool(StorageKeys.downloadWifiOnly) ?? true;

  Future<void> setDownloadWifiOnly(bool value) =>
      _prefs.setBool(StorageKeys.downloadWifiOnly, value);

  String get lastSearchQuery => _prefs.getString(StorageKeys.lastSearchQuery) ?? '';

  Future<void> setLastSearchQuery(String query) =>
      _prefs.setString(StorageKeys.lastSearchQuery, query);

  /// Recently played song ids, newest first - used for instant offline rendering of the home rail
  /// before the network responds.
  List<String> get recentSongIds => _prefs.getStringList(StorageKeys.playedSongIds) ?? <String>[];

  Future<void> pushRecentSongId(String songId, {int maxEntries = 20}) async {
    final List<String> updated = <String>[
      songId,
      ...recentSongIds.where((String id) => id != songId),
    ].take(maxEntries).toList(growable: false);
    await _prefs.setStringList(StorageKeys.playedSongIds, updated);
  }
}
