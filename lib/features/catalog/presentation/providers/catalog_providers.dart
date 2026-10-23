import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tuneflow/core/network/paged_response.dart';
import 'package:tuneflow/core/providers/core_providers.dart';
import 'package:tuneflow/features/catalog/data/datasources/catalog_remote_datasource.dart';
import 'package:tuneflow/features/catalog/data/repositories/catalog_repository_impl.dart';
import 'package:tuneflow/features/catalog/domain/entities/album.dart';
import 'package:tuneflow/features/catalog/domain/entities/artist.dart';
import 'package:tuneflow/features/catalog/domain/entities/genre.dart';
import 'package:tuneflow/features/catalog/domain/entities/home_feed.dart';
import 'package:tuneflow/features/catalog/domain/entities/song.dart';
import 'package:tuneflow/features/catalog/domain/repositories/catalog_repository.dart';

/// Catalogue wiring plus the read providers the home, search and detail screens consume.
///
/// Riverpod's auto-dispose is used for parameterised providers (a specific album, a search query) so
/// navigating away releases the data, while the shared list providers stay alive to avoid refetching
/// on every tab switch.

final Provider<CatalogRemoteDataSource> catalogRemoteDataSourceProvider =
    Provider<CatalogRemoteDataSource>(
  (Ref ref) => CatalogRemoteDataSource(ref.watch(apiClientProvider)),
  name: 'catalogRemoteDataSource',
);

final Provider<CatalogRepository> catalogRepositoryProvider = Provider<CatalogRepository>(
  (Ref ref) => CatalogRepositoryImpl(ref.watch(catalogRemoteDataSourceProvider)),
  name: 'catalogRepository',
);

/// The assembled home screen. Kept alive: it is the app's landing tab.
final FutureProvider<HomeFeed> homeFeedProvider = FutureProvider<HomeFeed>(
  (Ref ref) => ref.watch(catalogRepositoryProvider).getHomeFeed(),
  name: 'homeFeed',
);

final FutureProvider<List<Genre>> genresProvider = FutureProvider<List<Genre>>(
  (Ref ref) => ref.watch(catalogRepositoryProvider).getGenres(),
  name: 'genres',
);

final FutureProvider<PagedResponse<Song>> trendingSongsProvider =
    FutureProvider<PagedResponse<Song>>(
  (Ref ref) async {
    final List<Song> songs = await ref.watch(catalogRepositoryProvider).getTrendingSongs(limit: 30);
    return PagedResponse<Song>(
      items: songs,
      page: 0,
      size: songs.length,
      totalElements: songs.length,
      totalPages: 1,
      isFirst: true,
      isLast: true,
    );
  },
  name: 'trendingSongs',
);

final FutureProvider<PagedResponse<Artist>> popularArtistsProvider =
    FutureProvider<PagedResponse<Artist>>(
  (Ref ref) => ref.watch(catalogRepositoryProvider).getPopularArtists(size: 30),
  name: 'popularArtists',
);

/// A single song, refreshed after like/unlike so the heart and counter stay in sync.
final FutureProviderFamily<Song, String> songProvider = FutureProvider.family<Song, String>(
  (Ref ref, String id) => ref.watch(catalogRepositoryProvider).getSong(id),
  name: 'song',
);

final FutureProviderFamily<Album, String> albumProvider = FutureProvider.family<Album, String>(
  (Ref ref, String id) => ref.watch(catalogRepositoryProvider).getAlbum(id),
  name: 'album',
);

final FutureProviderFamily<List<Song>, String> albumSongsProvider =
    FutureProvider.family<List<Song>, String>(
  (Ref ref, String albumId) => ref.watch(catalogRepositoryProvider).getAlbumSongs(albumId),
  name: 'albumSongs',
);

final FutureProviderFamily<Artist, String> artistProvider = FutureProvider.family<Artist, String>(
  (Ref ref, String id) => ref.watch(catalogRepositoryProvider).getArtist(id),
  name: 'artist',
);

/// Songs for an artist or genre, reusing the `/songs` filter parameters.
final FutureProviderFamily<PagedResponse<Song>, String> artistSongsProvider =
    FutureProvider.family<PagedResponse<Song>, String>(
  (Ref ref, String artistId) =>
      ref.watch(catalogRepositoryProvider).getSongs(artistId: artistId, size: 50),
  name: 'artistSongs',
);

final FutureProviderFamily<PagedResponse<Album>, String> artistAlbumsProvider =
    FutureProvider.family<PagedResponse<Album>, String>(
  (Ref ref, String artistId) =>
      ref.watch(catalogRepositoryProvider).getAlbums(artistId: artistId, size: 50),
  name: 'artistAlbums',
);

final FutureProviderFamily<PagedResponse<Song>, String> genreSongsProvider =
    FutureProvider.family<PagedResponse<Song>, String>(
  (Ref ref, String genreSlug) =>
      ref.watch(catalogRepositoryProvider).getSongs(genreSlug: genreSlug, size: 50),
  name: 'genreSongs',
);

final FutureProviderFamily<List<Song>, String> similarSongsProvider =
    FutureProvider.family<List<Song>, String>(
  (Ref ref, String songId) => ref.watch(catalogRepositoryProvider).getSimilarSongs(songId),
  name: 'similarSongs',
);

/// Catalogue writes (follow/unfollow). Kept as a small action object so screens do not reach into
/// the repository directly and so the provider invalidations live next to the call that needs them.
class CatalogActions {
  const CatalogActions(this._ref);

  final Ref _ref;

  Future<void> followArtist(String artistId) async {
    await _ref.read(catalogRepositoryProvider).followArtist(artistId);
    _invalidate(artistId);
  }

  Future<void> unfollowArtist(String artistId) async {
    await _ref.read(catalogRepositoryProvider).unfollowArtist(artistId);
    _invalidate(artistId);
  }

  void _invalidate(String artistId) {
    _ref.invalidate(artistProvider(artistId));
    _ref.invalidate(homeFeedProvider);
    _ref.invalidate(followingArtistsProvider);
  }
}

final Provider<CatalogActions> catalogActionsProvider = Provider<CatalogActions>(
  (Ref ref) => CatalogActions(ref),
  name: 'catalogActions',
);

/// Artists the user follows (`GET /artists/following`), shown in the profile and library.
final FutureProvider<PagedResponse<Artist>> followingArtistsProvider =
    FutureProvider<PagedResponse<Artist>>(
  (Ref ref) => ref.watch(catalogRepositoryProvider).getFollowingArtists(size: 30),
  name: 'followingArtists',
);
