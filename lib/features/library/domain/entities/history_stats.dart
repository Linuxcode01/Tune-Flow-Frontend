/// Listening statistics (`GET /history/stats`).
///
/// Mirrors the API payload one-to-one, including the zero-filled seven-day window: the chart's
/// x-axis must stay stable, so days with no listening arrive as zeroes rather than being absent.
class HistoryStats {
  const HistoryStats({
    this.totalPlays = 0,
    this.totalListeningSeconds = 0,
    this.completedPlays = 0,
    this.uniqueSongs = 0,
    this.uniqueArtists = 0,
    this.topArtists = const <TopArtist>[],
    this.topGenres = const <TopGenre>[],
    this.lastSevenDays = const <DailyPlays>[],
  });

  factory HistoryStats.fromJson(Map<String, dynamic> json) {
    return HistoryStats(
      totalPlays: (json['totalPlays'] as num?)?.toInt() ?? 0,
      totalListeningSeconds: (json['totalListeningSeconds'] as num?)?.toInt() ?? 0,
      completedPlays: (json['completedPlays'] as num?)?.toInt() ?? 0,
      uniqueSongs: (json['uniqueSongs'] as num?)?.toInt() ?? 0,
      uniqueArtists: (json['uniqueArtists'] as num?)?.toInt() ?? 0,
      topArtists: _mapList(json['topArtists'], TopArtist.fromJson),
      topGenres: _mapList(json['topGenres'], TopGenre.fromJson),
      lastSevenDays: _mapList(json['lastSevenDays'], DailyPlays.fromJson),
    );
  }

  final int totalPlays;
  final int totalListeningSeconds;
  final int completedPlays;
  final int uniqueSongs;
  final int uniqueArtists;
  final List<TopArtist> topArtists;
  final List<TopGenre> topGenres;
  final List<DailyPlays> lastSevenDays;

  bool get isEmpty => totalPlays == 0;

  /// Total listening time in hours, for the "you listened for X" headline.
  double get listeningHours => totalListeningSeconds / 3600;

  /// Highest daily play count, used to scale the mini bar chart.
  int get peakDailyPlays =>
      lastSevenDays.fold<int>(0, (int max, DailyPlays day) => day.plays > max ? day.plays : max);

  double get completionRate => totalPlays == 0 ? 0 : completedPlays / totalPlays;
}

class TopArtist {
  const TopArtist({required this.id, required this.name, this.imageUrl, this.playCount = 0});

  factory TopArtist.fromJson(Map<String, dynamic> json) => TopArtist(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        imageUrl: json['imageUrl'] as String?,
        playCount: (json['playCount'] as num?)?.toInt() ?? 0,
      );

  final String id;
  final String name;
  final String? imageUrl;
  final int playCount;
}

class TopGenre {
  const TopGenre({required this.id, required this.name, required this.slug, this.playCount = 0});

  factory TopGenre.fromJson(Map<String, dynamic> json) => TopGenre(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        slug: json['slug'] as String? ?? '',
        playCount: (json['playCount'] as num?)?.toInt() ?? 0,
      );

  final String id;
  final String name;
  final String slug;
  final int playCount;
}

class DailyPlays {
  const DailyPlays({required this.date, required this.plays});

  factory DailyPlays.fromJson(Map<String, dynamic> json) => DailyPlays(
        date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
        plays: (json['plays'] as num?)?.toInt() ?? 0,
      );

  final DateTime date;
  final int plays;
}

List<T> _mapList<T>(dynamic raw, T Function(Map<String, dynamic> json) mapper) {
  return ((raw as List<dynamic>?) ?? const <dynamic>[])
      .whereType<Map<String, dynamic>>()
      .map(mapper)
      .toList(growable: false);
}
