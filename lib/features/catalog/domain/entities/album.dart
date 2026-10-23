import 'package:tuneflow/features/catalog/domain/entities/artist.dart';

/// Compact album reference embedded in song payloads.
class AlbumSummary {
  const AlbumSummary({
    required this.id,
    required this.title,
    this.coverImageUrl,
    this.releaseDate,
  });

  factory AlbumSummary.fromJson(Map<String, dynamic> json) {
    return AlbumSummary(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'Unknown album',
      coverImageUrl: json['coverImageUrl'] as String?,
      releaseDate: DateTime.tryParse(json['releaseDate'] as String? ?? ''),
    );
  }

  final String id;
  final String title;
  final String? coverImageUrl;
  final DateTime? releaseDate;

  @override
  bool operator ==(Object other) => other is AlbumSummary && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Full album (`GET /albums/{id}`, `GET /albums/new-releases`).
class Album {
  const Album({
    required this.id,
    required this.title,
    this.description,
    this.coverImageUrl,
    this.releaseDate,
    this.songCount = 0,
    this.totalDurationSeconds = 0,
    this.artist,
    this.followingArtist,
  });

  factory Album.fromJson(Map<String, dynamic> json) {
    return Album(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'Unknown album',
      description: json['description'] as String?,
      coverImageUrl: json['coverImageUrl'] as String?,
      releaseDate: DateTime.tryParse(json['releaseDate'] as String? ?? ''),
      songCount: (json['songCount'] as num?)?.toInt() ?? 0,
      totalDurationSeconds: (json['totalDurationSeconds'] as num?)?.toInt() ?? 0,
      artist: json['artist'] == null
          ? null
          : ArtistSummary.fromJson(json['artist'] as Map<String, dynamic>),
      followingArtist: json['followingArtist'] as bool?,
    );
  }

  final String id;
  final String title;
  final String? description;
  final String? coverImageUrl;
  final DateTime? releaseDate;
  final int songCount;
  final int totalDurationSeconds;
  final ArtistSummary? artist;
  final bool? followingArtist;

  AlbumSummary toSummary() => AlbumSummary(
        id: id,
        title: title,
        coverImageUrl: coverImageUrl,
        releaseDate: releaseDate,
      );

  @override
  bool operator ==(Object other) => other is Album && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
