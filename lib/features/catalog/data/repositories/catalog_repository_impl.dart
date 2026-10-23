import 'package:tuneflow/core/network/paged_response.dart';
import 'package:tuneflow/features/catalog/data/datasources/catalog_remote_datasource.dart';
import 'package:tuneflow/features/catalog/domain/entities/album.dart';
import 'package:tuneflow/features/catalog/domain/entities/artist.dart';
import 'package:tuneflow/features/catalog/domain/entities/genre.dart';
import 'package:tuneflow/features/catalog/domain/entities/home_feed.dart';
import 'package:tuneflow/features/catalog/domain/entities/search_results.dart';
import 'package:tuneflow/features/catalog/domain/entities/song.dart';
import 'package:tuneflow/features/catalog/domain/repositories/catalog_repository.dart';

/// Thin pass-through over [CatalogRemoteDataSource].
///
/// It is kept deliberately thin: when the backend gains a local cache or an offline store, this is
/// the only class that changes, and no screen has to be touched.
class CatalogRepositoryImpl implements CatalogRepository {
  const CatalogRepositoryImpl(this._remote);

  final CatalogRemoteDataSource _remote;

  @override
  Future<PagedResponse<Song>> getSongs({
    int page = 0,
    int size = 20,
    String? artistId,
    String? albumId,
    String? genreSlug,
    String? query,
  }) {
    return _remote.getSongs(
      page: page,
      size: size,
      artistId: artistId,
      albumId: albumId,
      genreSlug: genreSlug,
      query: query,
    );
  }

  @override
  Future<List<Song>> getTrendingSongs({int limit = 20}) => _remote.getTrendingSongs(limit: limit);

  @override
  Future<List<Song>> getNewReleaseSongs({int limit = 20}) => _remote.getNewReleaseSongs(limit: limit);

  @override
  Future<Song> getSong(String id) => _remote.getSong(id);

  @override
  Future<PagedResponse<Album>> getAlbums({
    int page = 0,
    int size = 20,
    String? artistId,
    String? query,
  }) {
    return _remote.getAlbums(page: page, size: size, artistId: artistId, query: query);
  }

  @override
  Future<List<Album>> getNewReleaseAlbums({int limit = 20}) =>
      _remote.getNewReleaseAlbums(limit: limit);

  @override
  Future<Album> getAlbum(String id) => _remote.getAlbum(id);

  @override
  Future<List<Song>> getAlbumSongs(String albumId) => _remote.getAlbumSongs(albumId);

  @override
  Future<PagedResponse<Artist>> getArtists({int page = 0, int size = 20, String? query}) =>
      _remote.getArtists(page: page, size: size, query: query);

  @override
  Future<PagedResponse<Artist>> getPopularArtists({int page = 0, int size = 20}) =>
      _remote.getPopularArtists(page: page, size: size);

  @override
  Future<PagedResponse<Artist>> getFollowingArtists({int page = 0, int size = 20}) =>
      _remote.getFollowingArtists(page: page, size: size);

  @override
  Future<Artist> getArtist(String id) => _remote.getArtist(id);

  @override
  Future<void> followArtist(String id) => _remote.follow(id);

  @override
  Future<void> unfollowArtist(String id) => _remote.unfollow(id);

  @override
  Future<List<Genre>> getGenres() => _remote.getGenres();

  @override
  Future<HomeFeed> getHomeFeed() => _remote.getHomeFeed();

  @override
  Future<List<Song>> getRecommendations({int limit = 20}) =>
      _remote.getRecommendations(limit: limit);

  @override
  Future<List<Song>> getSimilarSongs(String songId, {int limit = 10}) =>
      _remote.getSimilarSongs(songId, limit: limit);

  @override
  Future<SearchResults> search(String query, {String type = 'all', int limit = 20}) =>
      _remote.search(query, type: type, limit: limit);

  @override
  Future<SearchSuggestions> suggest(String query, {int limit = 8}) =>
      _remote.suggest(query, limit: limit);
}
