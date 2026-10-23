import 'package:tuneflow/features/catalog/domain/entities/artist.dart';
import 'package:tuneflow/features/catalog/domain/entities/song.dart';

/// What kind of content a home section carries. The client renders a horizontal rail of song cards
/// or artist avatars depending on this.
enum SectionType {
  songs,
  artists;

  static SectionType fromWire(String? value) =>
      value == 'artists' ? SectionType.artists : SectionType.songs;
}

/// One rail on the home screen (`recently-played`, `made-for-you`, `trending`, ...).
class HomeSection {
  const HomeSection({
    required this.key,
    required this.title,
    this.subtitle,
    this.type = SectionType.songs,
    this.songs = const <Song>[],
    this.artists = const <Artist>[],
  });

  factory HomeSection.fromJson(Map<String, dynamic> json) {
    return HomeSection(
      key: json['key'] as String? ?? '',
      title: json['title'] as String? ?? '',
      subtitle: json['subtitle'] as String?,
      type: SectionType.fromWire(json['type'] as String?),
      songs: ((json['songs'] as List<dynamic>?) ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(Song.fromJson)
          .toList(growable: false),
      artists: ((json['artists'] as List<dynamic>?) ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(Artist.fromJson)
          .toList(growable: false),
    );
  }

  final String key;
  final String title;
  final String? subtitle;
  final SectionType type;
  final List<Song> songs;
  final List<Artist> artists;

  bool get isEmpty => songs.isEmpty && artists.isEmpty;
  bool get isArtistSection => type == SectionType.artists && artists.isNotEmpty;
}

/// The assembled home screen: ordered sections plus whether they were personalised.
///
/// `personalised == false` means the API served the anonymous fallback (trending + new releases),
/// which the UI should acknowledge instead of pretending it knows the listener.
class HomeFeed {
  const HomeFeed({required this.sections, required this.personalised});

  factory HomeFeed.fromJson(Map<String, dynamic> json) {
    return HomeFeed(
      sections: ((json['sections'] as List<dynamic>?) ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(HomeSection.fromJson)
          .toList(growable: false),
      personalised: json['personalised'] as bool? ?? false,
    );
  }

  final List<HomeSection> sections;
  final bool personalised;

  bool get isEmpty => sections.every((HomeSection section) => section.isEmpty);
}
