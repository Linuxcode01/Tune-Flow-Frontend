import 'package:tuneflow/core/constants/api_endpoints.dart';
import 'package:tuneflow/core/network/api_client.dart';
import 'package:tuneflow/core/network/paged_response.dart';
import 'package:tuneflow/features/catalog/domain/entities/song.dart';
import 'package:tuneflow/features/library/domain/entities/history_stats.dart';

/// HTTP access to likes, history and statistics.
class LibraryRemoteDataSource {
  const LibraryRemoteDataSource(this._client);

  final ApiClient _client;

  Future<PagedResponse<Song>> getLikedSongs({int page = 0, int size = 20}) {
    return _client.getPaged<Song>(
      ApiEndpoints.likedSongs,
      page: page,
      size: size,
      itemMapper: Song.fromJson,
    );
  }

  Future<void> like(String songId) => _client.post(ApiEndpoints.songLike(songId));

  /// The API models "unlike" as a DELETE on the same resource, which is why the client has two
  /// separate calls instead of a single toggle with a flag.
  Future<void> unlike(String songId) => _client.delete(ApiEndpoints.songLike(songId));

  Future<List<Song>> getRecentlyPlayed({int limit = 20}) {
    return _client
        .getList(ApiEndpoints.recentlyPlayed, queryParameters: <String, dynamic>{'limit': limit})
        .then((List<Map<String, dynamic>> rows) => rows.map(Song.fromJson).toList(growable: false));
  }

  Future<PagedResponse<Song>> getHistory({int page = 0, int size = 20}) async {
    // History entries wrap the song plus timing metadata; the library only needs the songs, and
    // duplicates are collapsed client-side into the "recently played" view.
    final PagedResponse<Map<String, dynamic>> entries = await _client.getPaged<Map<String, dynamic>>(
      ApiEndpoints.history,
      page: page,
      size: size,
      itemMapper: (Map<String, dynamic> json) => json,
    );
    return PagedResponse<Song>(
      items: entries.items
          .map((Map<String, dynamic> entry) => entry['song'])
          .whereType<Map<String, dynamic>>()
          .map(Song.fromJson)
          .toList(growable: false),
      page: entries.page,
      size: entries.size,
      totalElements: entries.totalElements,
      totalPages: entries.totalPages,
      isFirst: entries.isFirst,
      isLast: entries.isLast,
    );
  }

  Future<void> clearHistory() => _client.delete(ApiEndpoints.history);

  Future<HistoryStats> getStats() async {
    final Map<String, dynamic> data = await _client.getJson(ApiEndpoints.historyStats);
    return HistoryStats.fromJson(data);
  }
}
