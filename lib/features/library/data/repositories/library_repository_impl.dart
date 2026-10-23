import 'package:tuneflow/core/network/paged_response.dart';
import 'package:tuneflow/features/catalog/domain/entities/song.dart';
import 'package:tuneflow/features/library/data/datasources/library_remote_datasource.dart';
import 'package:tuneflow/features/library/domain/entities/history_stats.dart';
import 'package:tuneflow/features/library/domain/repositories/library_repository.dart';

class LibraryRepositoryImpl implements LibraryRepository {
  const LibraryRepositoryImpl(this._remote);

  final LibraryRemoteDataSource _remote;

  @override
  Future<PagedResponse<Song>> getLikedSongs({int page = 0, int size = 20}) =>
      _remote.getLikedSongs(page: page, size: size);

  @override
  Future<void> likeSong(String songId) => _remote.like(songId);

  @override
  Future<void> unlikeSong(String songId) => _remote.unlike(songId);

  @override
  Future<List<Song>> getRecentlyPlayed({int limit = 20}) =>
      _remote.getRecentlyPlayed(limit: limit);

  @override
  Future<PagedResponse<Song>> getHistory({int page = 0, int size = 20}) =>
      _remote.getHistory(page: page, size: size);

  @override
  Future<void> clearHistory() => _remote.clearHistory();

  @override
  Future<HistoryStats> getStats() => _remote.getStats();
}
