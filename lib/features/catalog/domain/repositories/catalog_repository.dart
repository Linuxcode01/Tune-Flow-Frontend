import 'package:tuneflow/core/network/paged_response.dart';
import 'package:tuneflow/features/catalog/domain/entities/album.dart';
import 'package:tuneflow/features/catalog/domain/entities/artist.dart';
import 'package:tuneflow/features/catalog/domain/entities/genre.dart';
import 'package:tuneflow/features/catalog/domain/entities/home_feed.dart';
import 'package:tuneflow/features/catalog/domain/entities/search_results.dart';
import 'package:tuneflow/features/catalog/domain/entities/song.dart';

/// Browse, search and discovery - the read side of the catalogue.
///
/// Playback (stream URLs, history) is deliberately *not* here: it belongs to the player feature, and
/// downloads to the downloads feature. One repository per capability keeps the dependency graph
/// acyclic and each interface small enough to fake in tests.
abstract interface class CatalogRepository {
  // Songs ------------------------------------------------------------------------------------
  Future<PagedResponse<Song>> getSongs({
    int page = 0,
    int size = 20,
    String? artistId,
    String? albumId,
    String? genreSlug,
    String? query,
  });

  Future<List<Song>> getTrendingSongs({int limit = 20});

  Future<List<Song>> getNewReleaseSongs({int limit = 20});

  Future<Song> getSong(String id);

  // Albums -----------------------------------------------------------------------------------
  Future<PagedResponse<Album>> getAlbums({int page = 0, int size = 20, String? artistId, String? query});

  Future<List<Album>> getNewReleaseAlbums({int limit = 20});

  Future<Album> getAlbum(String id);

  Future<List<Song>> getAlbumSongs(String albumId);

  // Artists ----------------------------------------------------------------------------------
  Future<PagedResponse<Artist>> getArtists({int page = 0, int size = 20, String? query});

  Future<PagedResponse<Artist>> getPopularArtists({int page = 0, int size = 20});

  Future<PagedResponse<Artist>> getFollowingArtists({int page = 0, int size = 20});

  Future<Artist> getArtist(String id);

  Future<void> followArtist(String id);

  Future<void> unfollowArtist(String id);

  // Genres -----------------------------------------------------------------------------------
  Future<List<Genre>> getGenres();

  // Discovery --------------------------------------------------------------------------------
  Future<HomeFeed> getHomeFeed();

  Future<List<Song>> getRecommendations({int limit = 20});

  Future<List<Song>> getSimilarSongs(String songId, {int limit = 10});

  Future<SearchResults> search(String query, {String type = 'all', int limit = 20});

  Future<SearchSuggestions> suggest(String query, {int limit = 8});
}
