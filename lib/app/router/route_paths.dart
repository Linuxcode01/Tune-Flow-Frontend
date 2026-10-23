/// Every route in the app, as constants plus builders.
///
/// Using builders (`RoutePaths.album('id')`) instead of string interpolation at call sites means a
/// renamed segment is a compile error, and deep links stay consistent with in-app navigation.
class RoutePaths {
  const RoutePaths._();

  static const String splash = '/';
  static const String login = '/login';
  static const String register = '/register';
  static const String forgotPassword = '/forgot-password';

  // Bottom navigation destinations (the shell).
  static const String home = '/home';
  static const String search = '/search';
  static const String library = '/library';
  static const String profile = '/profile';

  // Detail routes.
  static const String player = '/player';
  static const String settings = '/settings';
  static const String notifications = '/notifications';
  static const String downloads = '/downloads';
  static const String likedSongs = '/library/liked';
  static const String recentlyPlayed = '/library/recent';
  static const String queue = '/queue';

  /// Artist publishing flow (ARTIST accounts only; the screen explains itself otherwise).
  static const String upload = '/upload';

  static String album(String id) => '/album/$id';
  static String artist(String id) => '/artist/$id';
  static String playlist(String id) => '/playlist/$id';
  static String genre(String id) => '/genre/$id';

  /// The four primary destinations, in navigation-bar order (docs section 19).
  static const List<String> shellDestinations = <String>[home, search, library, profile];

  /// Routes reachable without a session. Everything else redirects to [login] when signed out.
  static bool isPublic(String location) {
    return location == splash ||
        location == login ||
        location == register ||
        location == forgotPassword;
  }
}
