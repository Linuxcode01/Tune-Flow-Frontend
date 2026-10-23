import 'package:tuneflow/features/catalog/domain/entities/album.dart';
import 'package:tuneflow/features/catalog/domain/entities/artist.dart';
import 'package:tuneflow/features/catalog/domain/entities/genre.dart';

/// A track, as returned by `/songs`, `/home`, search and playlist endpoints.
///
/// This is the most widely used entity in the app (home, search, playlist, library and the player
/// all consume it), which is why the catalogue lives in its own module rather than inside one
/// screen's feature - the same reason the backend keeps a `music` module.
///
/// Parsing is tolerant: the API omits null fields entirely, and a field being absent is normal
/// rather than an error.
class Song {
  const Song({
    required this.id,
    required this.title,
    required this.durationSeconds,
    this.trackNumber,
    this.playCount = 0,
    this.likeCount = 0,
    this.releaseDate,
    this.explicit = false,
    this.coverImageUrl,
    this.streamAvailable = true,
    this.artist,
    this.album,
    this.genres = const <Genre>[],
    this.liked,
  });

  factory Song.fromJson(Map<String, dynamic> json) {
    return Song(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'Unknown track',
      durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
      trackNumber: (json['trackNumber'] as num?)?.toInt(),
      playCount: (json['playCount'] as num?)?.toInt() ?? 0,
      likeCount: (json['likeCount'] as num?)?.toInt() ?? 0,
      releaseDate: DateTime.tryParse(json['releaseDate'] as String? ?? ''),
      explicit: json['explicit'] as bool? ?? false,
      coverImageUrl: json['coverImageUrl'] as String?,
      streamAvailable: json['streamAvailable'] as bool? ?? true,
      artist: json['artist'] == null
          ? null
          : ArtistSummary.fromJson(json['artist'] as Map<String, dynamic>),
      album: json['album'] == null
          ? null
          : AlbumSummary.fromJson(json['album'] as Map<String, dynamic>),
      genres: ((json['genres'] as List<dynamic>?) ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(Genre.fromJson)
          .toList(growable: false),
      liked: json['liked'] as bool?,
    );
  }

  final String id;
  final String title;
  final int durationSeconds;
  final int? trackNumber;
  final int playCount;
  final int likeCount;
  final DateTime? releaseDate;
  final bool explicit;

  /// Present only when the track has its own artwork; otherwise the album's is used.
  final String? coverImageUrl;
  final bool streamAvailable;
  final ArtistSummary? artist;
  final AlbumSummary? album;
  final List<Genre> genres;

  /// `null` for anonymous callers (the API does not know who is asking).
  final bool? liked;

  Duration get duration => Duration(seconds: durationSeconds);

  String get artistName => artist?.name ?? 'Unknown artist';

  /// Artwork to display: the track's own image, falling back to the album's.
  String? get artworkUrl => coverImageUrl ?? album?.coverImageUrl;

  /// Stable key for artwork placeholders and image caching.
  String get artworkSeed => id;

  bool get isLiked => liked ?? false;

  /// Combines the two like flags the API can return (`liked` on the song, or a local override).
  Song copyWith({bool? liked, int? likeCount, String? title, String? coverImageUrl}) {
    return Song(
      id: id,
      title: title ?? this.title,
      durationSeconds: durationSeconds,
      trackNumber: trackNumber,
      playCount: playCount,
      likeCount: likeCount ?? this.likeCount,
      releaseDate: releaseDate,
      explicit: explicit,
      coverImageUrl: coverImageUrl ?? this.coverImageUrl,
      streamAvailable: streamAvailable,
      artist: artist,
      album: album,
      genres: genres,
      liked: liked ?? this.liked,
    );
  }

  @override
  bool operator ==(Object other) => other is Song && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Song($title - $artistName)';
}
