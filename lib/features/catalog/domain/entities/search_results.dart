import 'package:tuneflow/features/catalog/domain/entities/album.dart';
import 'package:tuneflow/features/catalog/domain/entities/artist.dart';
import 'package:tuneflow/features/catalog/domain/entities/song.dart';

/// A playlist as returned by search and the playlist endpoints.
///
/// Lives in the catalogue module because search results embed it; the playlist feature owns the
/// mutating operations.
class PlaylistSummary {
  const PlaylistSummary({
    required this.id,
    required this.name,
    this.description,
    this.coverImageUrl,
    this.publicPlaylist = false,
    this.systemPlaylist = false,
    this.songCount = 0,
    this.totalDurationSeconds = 0,
    this.ownerId,
    this.ownerName,
    this.ownedByCurrentUser = false,
    this.createdAt,
    this.updatedAt,
  });

  factory PlaylistSummary.fromJson(Map<String, dynamic> json) {
    return PlaylistSummary(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Untitled playlist',
      description: json['description'] as String?,
      coverImageUrl: json['coverImageUrl'] as String?,
      publicPlaylist: json['publicPlaylist'] as bool? ?? false,
      systemPlaylist: json['systemPlaylist'] as bool? ?? false,
      songCount: (json['songCount'] as num?)?.toInt() ?? 0,
      totalDurationSeconds: (json['totalDurationSeconds'] as num?)?.toInt() ?? 0,
      ownerId: json['ownerId'] as String?,
      ownerName: json['ownerName'] as String?,
      ownedByCurrentUser: json['ownedByCurrentUser'] as bool? ?? false,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '')?.toUtc(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toUtc(),
    );
  }

  final String id;
  final String name;
  final String? description;
  final String? coverImageUrl;
  final bool publicPlaylist;
  final bool systemPlaylist;
  final int songCount;
  final int totalDurationSeconds;
  final String? ownerId;
  final String? ownerName;
  final bool ownedByCurrentUser;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Only the owner can edit or delete.
  bool get canEdit => ownedByCurrentUser && !systemPlaylist;

  @override
  bool operator ==(Object other) => other is PlaylistSummary && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// A playlist with its tracks (`GET /playlists/{id}`).
class PlaylistDetail {
  const PlaylistDetail({required this.playlist, required this.songs});

  factory PlaylistDetail.fromJson(Map<String, dynamic> json) {
    return PlaylistDetail(
      playlist: PlaylistSummary.fromJson(
        (json['playlist'] as Map<String, dynamic>?) ?? const <String, dynamic>{},
      ),
      songs: ((json['songs'] as List<dynamic>?) ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(Song.fromJson)
          .toList(growable: false),
    );
  }

  final PlaylistSummary playlist;
  final List<Song> songs;
}

/// Combined search response (`GET /search`).
///
/// [fuzzyMatched] is only true when the backend's fallback pass actually produced rows, so the UI can
/// honestly say "showing results for ..." instead of apologising for an empty list.
class SearchResults {
  const SearchResults({
    required this.query,
    this.songs = const <Song>[],
    this.artists = const <Artist>[],
    this.albums = const <Album>[],
    this.playlists = const <PlaylistSummary>[],
    this.totalResults = 0,
    this.tookMs = 0,
    this.fuzzyMatched = false,
  });

  const SearchResults.empty()
      : query = '',
        songs = const <Song>[],
        artists = const <Artist>[],
        albums = const <Album>[],
        playlists = const <PlaylistSummary>[],
        totalResults = 0,
        tookMs = 0,
        fuzzyMatched = false;

  factory SearchResults.fromJson(Map<String, dynamic> json) {
    return SearchResults(
      query: json['query'] as String? ?? '',
      songs: _mapList(json['songs'], Song.fromJson),
      artists: _mapList(json['artists'], Artist.fromJson),
      albums: _mapList(json['albums'], Album.fromJson),
      playlists: _mapList(json['playlists'], PlaylistSummary.fromJson),
      totalResults: (json['totalResults'] as num?)?.toInt() ?? 0,
      tookMs: (json['tookMs'] as num?)?.toInt() ?? 0,
      fuzzyMatched: json['fuzzyMatched'] as bool? ?? false,
    );
  }

  final String query;
  final List<Song> songs;
  final List<Artist> artists;
  final List<Album> albums;
  final List<PlaylistSummary> playlists;
  final int totalResults;
  final int tookMs;
  final bool fuzzyMatched;

  bool get isEmpty => songs.isEmpty && artists.isEmpty && albums.isEmpty && playlists.isEmpty;

  int get sectionCount => <bool>[
        songs.isNotEmpty,
        artists.isNotEmpty,
        albums.isNotEmpty,
        playlists.isNotEmpty,
      ].where((bool present) => present).length;
}

/// One typeahead row (`GET /search/suggest`).
class SearchSuggestionItem {
  const SearchSuggestionItem({
    required this.type,
    required this.id,
    required this.title,
    this.subtitle,
    this.imageUrl,
  });

  factory SearchSuggestionItem.fromJson(Map<String, dynamic> json) {
    return SearchSuggestionItem(
      type: json['type'] as String? ?? 'song',
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      subtitle: json['subtitle'] as String?,
      imageUrl: json['imageUrl'] as String?,
    );
  }

  final String type;
  final String id;
  final String title;
  final String? subtitle;
  final String? imageUrl;
}

/// Typeahead payload: recent terms plus concrete entities to jump straight to.
class SearchSuggestions {
  const SearchSuggestions({this.query = '', this.terms = const <String>[], this.items = const <SearchSuggestionItem>[]});

  const SearchSuggestions.empty()
      : query = '',
        terms = const <String>[],
        items = const <SearchSuggestionItem>[];

  factory SearchSuggestions.fromJson(Map<String, dynamic> json) {
    return SearchSuggestions(
      query: json['query'] as String? ?? '',
      terms: ((json['terms'] as List<dynamic>?) ?? const <dynamic>[])
          .whereType<String>()
          .toList(growable: false),
      items: _mapList(json['items'], SearchSuggestionItem.fromJson),
    );
  }

  final String query;
  final List<String> terms;
  final List<SearchSuggestionItem> items;

  bool get isEmpty => terms.isEmpty && items.isEmpty;
}

List<T> _mapList<T>(dynamic raw, T Function(Map<String, dynamic> json) mapper) {
  return ((raw as List<dynamic>?) ?? const <dynamic>[])
      .whereType<Map<String, dynamic>>()
      .map(mapper)
      .toList(growable: false);
}
