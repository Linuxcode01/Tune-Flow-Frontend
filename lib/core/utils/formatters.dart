import 'package:intl/intl.dart';

/// Presentation helpers shared by every feature, so "3:07", "1.2K plays" and "2 days ago" are
/// formatted identically everywhere in the app.
class Formatters {
  const Formatters._();

  static final DateFormat _shortDate = DateFormat('d MMM yyyy');
  static final DateFormat _monthYear = DateFormat('MMM yyyy');

  /// `mm:ss`, or `h:mm:ss` for anything an hour or longer. Null-safe: unknown durations render as
  /// `--:--` rather than `0:00`, which would look like a corrupt track.
  static String duration(Duration? value) {
    if (value == null) {
      return '--:--';
    }
    final int totalSeconds = value.inSeconds.abs();
    final int hours = totalSeconds ~/ 3600;
    final int minutes = (totalSeconds % 3600) ~/ 60;
    final int seconds = totalSeconds % 60;
    final String mm = minutes.toString().padLeft(hours > 0 ? 2 : 1, '0');
    final String ss = seconds.toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
  }

  static String durationFromSeconds(int? seconds) =>
      duration(seconds == null ? null : Duration(seconds: seconds));

  /// Compact listener counts: `842`, `1.2K`, `3.4M`.
  static String compactCount(num? value) {
    if (value == null) {
      return '0';
    }
    if (value < 1000) {
      return value.toStringAsFixed(0);
    }
    if (value < 1000000) {
      return '${(value / 1000).toStringAsFixed(value < 10000 ? 1 : 0)}K';
    }
    return '${(value / 1000000).toStringAsFixed(1)}M';
  }

  /// "5 songs · 24 min" - the standard playlist/album subtitle.
  static String collectionSummary(int songCount, int totalSeconds) {
    final String songs = songCount == 1 ? '1 song' : '$songCount songs';
    if (totalSeconds <= 0) {
      return songs;
    }
    final int minutes = (totalSeconds / 60).round();
    if (minutes < 60) {
      return '$songs · $minutes min';
    }
    final int hours = minutes ~/ 60;
    final int remainder = minutes % 60;
    return remainder == 0 ? '$songs · ${hours}h' : '$songs · ${hours}h ${remainder}m';
  }

  /// Relative time for history and notifications.
  static String relativeTime(DateTime? timestamp) {
    if (timestamp == null) {
      return '';
    }
    final Duration difference = DateTime.now().toUtc().difference(timestamp.toUtc());
    if (difference.inSeconds < 60) {
      return 'Just now';
    }
    if (difference.inMinutes < 60) {
      final int minutes = difference.inMinutes;
      return minutes == 1 ? '1 minute ago' : '$minutes minutes ago';
    }
    if (difference.inHours < 24) {
      final int hours = difference.inHours;
      return hours == 1 ? '1 hour ago' : '$hours hours ago';
    }
    if (difference.inDays < 7) {
      final int days = difference.inDays;
      return days == 1 ? 'Yesterday' : '$days days ago';
    }
    if (difference.inDays < 30) {
      final int weeks = difference.inDays ~/ 7;
      return weeks == 1 ? '1 week ago' : '$weeks weeks ago';
    }
    return _shortDate.format(timestamp.toLocal());
  }

  /// Release dates: exact within the current year, `MMM yyyy` beyond it.
  static String releaseDate(DateTime? date) {
    if (date == null) {
      return '';
    }
    final DateTime local = date.toLocal();
    if (local.year == DateTime.now().year) {
      return DateFormat('d MMM').format(local);
    }
    return _monthYear.format(local);
  }

  /// Byte sizes for downloads.
  static String bytes(int? value) {
    if (value == null || value <= 0) {
      return '';
    }
    const List<String> units = <String>['B', 'KB', 'MB', 'GB'];
    double size = value.toDouble();
    int unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(size >= 10 || unit == 0 ? 0 : 1)} ${units[unit]}';
  }
}
