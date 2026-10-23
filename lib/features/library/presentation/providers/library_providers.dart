import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tuneflow/core/error/app_exception.dart';
import 'package:tuneflow/core/network/paged_response.dart';
import 'package:tuneflow/core/providers/core_providers.dart';
import 'package:tuneflow/core/utils/app_logger.dart';
import 'package:tuneflow/features/catalog/domain/entities/song.dart';
import 'package:tuneflow/features/catalog/presentation/providers/catalog_providers.dart';
import 'package:tuneflow/features/library/data/datasources/library_remote_datasource.dart';
import 'package:tuneflow/features/library/data/repositories/library_repository_impl.dart';
import 'package:tuneflow/features/library/domain/entities/history_stats.dart';
import 'package:tuneflow/features/library/domain/repositories/library_repository.dart';

// ---------------------------------------------------------------------------------------------
// Wiring
// ---------------------------------------------------------------------------------------------

final Provider<LibraryRemoteDataSource> libraryRemoteDataSourceProvider =
    Provider<LibraryRemoteDataSource>(
  (Ref ref) => LibraryRemoteDataSource(ref.watch(apiClientProvider)),
  name: 'libraryRemoteDataSource',
);

final Provider<LibraryRepository> libraryRepositoryProvider = Provider<LibraryRepository>(
  (Ref ref) => LibraryRepositoryImpl(ref.watch(libraryRemoteDataSourceProvider)),
  name: 'libraryRepository',
);

// ---------------------------------------------------------------------------------------------
// Read providers
// ---------------------------------------------------------------------------------------------

final FutureProvider<PagedResponse<Song>> likedSongsProvider =
    FutureProvider<PagedResponse<Song>>(
  (Ref ref) => ref.watch(libraryRepositoryProvider).getLikedSongs(size: 50),
  name: 'likedSongs',
);

final FutureProvider<List<Song>> recentlyPlayedProvider = FutureProvider<List<Song>>(
  (Ref ref) => ref.watch(libraryRepositoryProvider).getRecentlyPlayed(limit: 20),
  name: 'recentlyPlayed',
);

final FutureProvider<PagedResponse<Song>> playHistoryProvider =
    FutureProvider<PagedResponse<Song>>(
  (Ref ref) => ref.watch(libraryRepositoryProvider).getHistory(size: 50),
  name: 'playHistory',
);

final FutureProvider<HistoryStats> historyStatsProvider = FutureProvider<HistoryStats>(
  (Ref ref) => ref.watch(libraryRepositoryProvider).getStats(),
  name: 'historyStats',
);

// ---------------------------------------------------------------------------------------------
// Like state
// ---------------------------------------------------------------------------------------------

/// Local, uncommitted like state keyed by song id.
///
/// The like flag arrives embedded in every song payload, so patching each cached list would mean
/// finding and rewriting the row in a dozen places. An override map is the smaller, more honest
/// solution: the UI reads one value, the network call confirms it, and a failure simply drops the
/// override.
final StateProvider<Map<String, bool>> likedOverridesProvider =
    StateProvider<Map<String, bool>>((Ref ref) => const <String, bool>{}, name: 'likedOverrides');

/// The liked state a widget should render for [song].
final ProviderFamily<bool, Song> songLikedProvider = Provider.family<bool, Song>(
  (Ref ref, Song song) => ref.watch(likedOverridesProvider)[song.id] ?? song.isLiked,
  name: 'songLiked',
);

/// Like/unlike with optimistic feedback and rollback on failure.
class LibraryActions {
  const LibraryActions(this._ref);

  final Ref _ref;

  bool isLiked(Song song) =>
      _ref.read(likedOverridesProvider)[song.id] ?? song.isLiked;

  Future<void> toggleLike(Song song) async {
    final bool wasLiked = isLiked(song);
    _setOverride(song.id, !wasLiked);

    try {
      final LibraryRepository repository = _ref.read(libraryRepositoryProvider);
      if (wasLiked) {
        await repository.unlikeSong(song.id);
      } else {
        await repository.likeSong(song.id);
      }
      // The server has accepted the change, so the collection can be refetched. The response is now
      // the source of truth: keeping the override would freeze it forever.
      _ref.invalidate(likedSongsProvider);
      _ref.invalidate(songProvider(song.id));
      _clearOverride(song.id);
    } on AppException catch (error) {
      _setOverride(song.id, wasLiked);
      AppLogger.warn('Like toggle failed for ${song.id}', error: error);
      rethrow;
    }
  }

  Future<void> clearHistory() async {
    await _ref.read(libraryRepositoryProvider).clearHistory();
    _ref.invalidate(playHistoryProvider);
    _ref.invalidate(recentlyPlayedProvider);
    _ref.invalidate(historyStatsProvider);
  }

  void _setOverride(String songId, bool liked) {
    _ref.read(likedOverridesProvider.notifier).update(
          (Map<String, bool> current) => <String, bool>{...current, songId: liked},
        );
  }

  void _clearOverride(String songId) {
    _ref.read(likedOverridesProvider.notifier).update((Map<String, bool> current) {
      final Map<String, bool> updated = Map<String, bool>.of(current);
      updated.remove(songId);
      return updated;
    });
  }
}

final Provider<LibraryActions> libraryActionsProvider = Provider<LibraryActions>(
  (Ref ref) => LibraryActions(ref),
  name: 'libraryActions',
);
