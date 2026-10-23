import 'package:tuneflow/core/constants/api_endpoints.dart';
import 'package:tuneflow/core/network/api_client.dart';
import 'package:tuneflow/core/network/paged_response.dart';
import 'package:tuneflow/features/catalog/domain/entities/album.dart';
import 'package:tuneflow/features/catalog/domain/entities/artist.dart';
import 'package:tuneflow/features/catalog/domain/entities/genre.dart';
import 'package:tuneflow/features/catalog/domain/entities/home_feed.dart';
import 'package:tuneflow/features/catalog/domain/entities/search_results.dart';
import 'package:tuneflow/features/catalog/domain/entities/song.dart';

/// HTTP access to the catalogue endpoints.
///
/// Filtering is expressed with the API's own query parameters (`artistId`, `albumId`, `genre`, `q`)
/// rather than client-side filtering, so pagination totals stay correct.
class CatalogRemoteDataSource {
  const CatalogRemoteDataSource(this._client);

  final ApiClient _client;

  // --- Songs ---------------------------------------------------------------------------------

  Future<PagedResponse<Song>> getSongs({
    int page = 0,
    int size = 20,
    String? artistId,
    String? albumId,
    String? genreSlug,
    String? query,
  }) {
    return _client.getPaged<Song>(
      ApiEndpoints.songs,
      page: page,
      size: size,
      itemMapper: Song.fromJson,
      queryParameters: <String, dynamic>{
        if (artistId != null) 'artistId': artistId,
        if (albumId != null) 'albumId': albumId,
        if (genreSlug != null) 'genre': genreSlug,
        if (query != null && query.isNotEmpty) 'q': query,
      },
    );
  }

  Future<List<Song>> getTrendingSongs({int limit = 20}) async {
    // The trending endpoint accepts a pageable; a single page of `limit` is what the rails need.
    final PagedResponse<Song> page = await _client.getPaged<Song>(
      ApiEndpoints.trendingSongs,
      page: 0,
      size: limit,
      itemMapper: Song.fromJson,
    );
    return page.items;
  }

  Future<List<Song>> getNewReleaseSongs({int limit = 20}) async {
    final PagedResponse<Song> page = await _client.getPaged<Song>(
      ApiEndpoints.newReleaseSongs,
      page: 0,
      size: limit,
      itemMapper: Song.fromJson,
    );
    return page.items;
  }

  Future<Song> getSong(String id) async {
    final Map<String, dynamic> data = await _client.getJson(ApiEndpoints.song(id));
    return Song.fromJson(data);
  }

  // --- Albums --------------------------------------------------------------------------------

  Future<PagedResponse<Album>> getAlbums({
    int page = 0,
    int size = 20,
    String? artistId,
    String? query,
  }) {
    return _client.getPaged<Album>(
      ApiEndpoints.albums,
      page: page,
      size: size,
      itemMapper: Album.fromJson,
      queryParameters: <String, dynamic>{
        if (artistId != null) 'artistId': artistId,
        if (query != null && query.isNotEmpty) 'q': query,
      },
    );
  }

  Future<List<Album>> getNewReleaseAlbums({int limit = 20}) async {
    final PagedResponse<Album> page = await _client.getPaged<Album>(
      ApiEndpoints.newReleaseAlbums,
      page: 0,
      size: limit,
      itemMapper: Album.fromJson,
    );
    return page.items;
  }

  Future<Album> getAlbum(String id) async {
    final Map<String, dynamic> data = await _client.getJson(ApiEndpoints.album(id));
    return Album.fromJson(data);
  }

  Future<List<Song>> getAlbumSongs(String albumId) {
    return _client.getList(ApiEndpoints.albumSongs(albumId)).then(
          (List<Map<String, dynamic>> rows) => rows.map(Song.fromJson).toList(growable: false),
        );
  }

  // --- Artists -------------------------------------------------------------------------------

  Future<PagedResponse<Artist>> getArtists({int page = 0, int size = 20, String? query}) {
    return _client.getPaged<Artist>(
      ApiEndpoints.artists,
      page: page,
      size: size,
      itemMapper: Artist.fromJson,
      queryParameters: <String, dynamic>{
        if (query != null && query.isNotEmpty) 'q': query,
      },
    );
  }

  Future<PagedResponse<Artist>> getPopularArtists({int page = 0, int size = 20}) {
    return _client.getPaged<Artist>(
      ApiEndpoints.popularArtists,
      page: page,
      size: size,
      itemMapper: Artist.fromJson,
    );
  }

  Future<PagedResponse<Artist>> getFollowingArtists({int page = 0, int size = 20}) {
    return _client.getPaged<Artist>(
      ApiEndpoints.followingArtists,
      page: page,
      size: size,
      itemMapper: Artist.fromJson,
    );
  }

  Future<Artist> getArtist(String id) async {
    final Map<String, dynamic> data = await _client.getJson(ApiEndpoints.artist(id));
    return Artist.fromJson(data);
  }

  Future<void> follow(String artistId) => _client.post(ApiEndpoints.artistFollow(artistId));

  Future<void> unfollow(String artistId) => _client.delete(ApiEndpoints.artistFollow(artistId));

  // --- Genres --------------------------------------------------------------------------------

  Future<List<Genre>> getGenres() async {
    final List<Map<String, dynamic>> rows = await _client.getList(ApiEndpoints.genres);
    return rows.map(Genre.fromJson).toList(growable: false);
  }

  // --- Discovery -----------------------------------------------------------------------------

  Future<HomeFeed> getHomeFeed() async {
    final Map<String, dynamic> data = await _client.getJson(ApiEndpoints.home);
    return HomeFeed.fromJson(data);
  }

  Future<List<Song>> getRecommendations({int limit = 20}) {
    return _client.getList(ApiEndpoints.recommendations, queryParameters: <String, dynamic>{'limit': limit}).then(
          (List<Map<String, dynamic>> rows) => rows.map(Song.fromJson).toList(growable: false),
        );
  }

  Future<List<Song>> getSimilarSongs(String songId, {int limit = 10}) {
    return _client
        .getList(ApiEndpoints.similarSongs(songId), queryParameters: <String, dynamic>{'limit': limit})
        .then((List<Map<String, dynamic>> rows) => rows.map(Song.fromJson).toList(growable: false));
  }

  Future<SearchResults> search(String query, {String type = 'all', int limit = 20}) async {
    final Map<String, dynamic> data = await _client.getJson(
      ApiEndpoints.search,
      queryParameters: <String, dynamic>{'q': query, 'type': type, 'limit': limit},
    );
    return SearchResults.fromJson(data);
  }

  Future<SearchSuggestions> suggest(String query, {int limit = 8}) async {
    final Map<String, dynamic> data = await _client.getJson(
      ApiEndpoints.searchSuggest,
      queryParameters: <String, dynamic>{'q': query, 'limit': limit},
    );
    return SearchSuggestions.fromJson(data);
  }
}
