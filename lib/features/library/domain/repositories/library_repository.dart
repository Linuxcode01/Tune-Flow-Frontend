import 'package:tuneflow/core/network/paged_response.dart';
import 'package:tuneflow/features/catalog/domain/entities/song.dart';
import 'package:tuneflow/features/library/domain/entities/history_stats.dart';

/// The listener's own library: likes, listening history and statistics.
///
/// Likes live here rather than in the catalogue because they are per-user state, not catalogue data -
/// the same split the backend makes between `music` and `history`/`liked_songs`.
abstract interface class LibraryRepository {
  Future<PagedResponse<Song>> getLikedSongs({int page = 0, int size = 20});

  Future<void> likeSong(String songId);

  Future<void> unlikeSong(String songId);

  Future<List<Song>> getRecentlyPlayed({int limit = 20});

  Future<PagedResponse<Song>> getHistory({int page = 0, int size = 20});

  Future<void> clearHistory();

  Future<HistoryStats> getStats();
}
