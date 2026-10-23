/// Every backend route the client talks to, in one place.
///
/// Verified against the running service's OpenAPI document (`/v3/api-docs`), so the paths, verbs and
/// query parameters here are the API's, not an approximation. Keeping them in one file means a
/// backend version bump is a single-file change.
///
/// Query parameters are passed as maps at the call site; only the repeated shape is encoded here
/// (pagination uses `page`/`size`, matching Spring's `Pageable` binding).
library;

class ApiEndpoints {
  const ApiEndpoints._();

  // --- Auth -----------------------------------------------------------------------------------
  static const String register = '/auth/register';
  static const String login = '/auth/login';
  static const String refresh = '/auth/refresh';
  static const String logout = '/auth/logout';
  static const String logoutAll = '/auth/logout-all';
  static const String forgotPassword = '/auth/forgot-password';
  static const String resetPassword = '/auth/reset-password';

  // --- Users ----------------------------------------------------------------------------------
  static const String me = '/users/me';
  static const String changePassword = '/users/me/password'; // PUT
  static const String deleteAccount = '/users/me';
  static const String likedSongs = '/users/me/liked-songs';

  // --- Catalogue ------------------------------------------------------------------------------
  static const String songs = '/songs';
  static const String trendingSongs = '/songs/trending';
  static const String newReleaseSongs = '/songs/new-releases';
  static const String albums = '/albums';
  static const String newReleaseAlbums = '/albums/new-releases';
  static const String artists = '/artists';
  static const String popularArtists = '/artists/popular';
  static const String followingArtists = '/artists/following';
  static const String myArtistProfile = '/artists/me';
  static const String genres = '/genres';

  static String song(String id) => '/songs/$id';
  static String songStream(String id) => '/songs/$id/stream';
  static String songLyrics(String songId) => '/songs/$songId/lyrics';
  static String songLyricsLanguages(String songId) => '/songs/$songId/lyrics/languages';
  static String songLyricsByLanguage(String songId, String language) =>
      '/songs/$songId/lyrics/$language';
  static String songLike(String id) => '/songs/$id/like';
  static String similarSongs(String songId) => '/recommendations/similar/$songId';

  static String album(String id) => '/albums/$id';
  static String albumSongs(String id) => '/albums/$id/songs';

  static String artist(String id) => '/artists/$id';
  static String artistFollow(String id) => '/artists/$id/follow';

  // --- Discovery ------------------------------------------------------------------------------
  static const String home = '/home';
  static const String recommendations = '/recommendations';
  static const String search = '/search';
  static const String searchSuggest = '/search/suggest';

  // --- Playlists ------------------------------------------------------------------------------
  static const String playlists = '/playlists';
  static const String publicPlaylists = '/playlists/public';

  static String playlist(String id) => '/playlists/$id';

  /// `POST` adds a song, `PUT` rewrites the order, `DELETE` clears the playlist.
  static String playlistSongs(String id) => '/playlists/$id/songs';

  static String playlistSong(String playlistId, String songId) => '/playlists/$playlistId/songs/$songId';

  // --- History --------------------------------------------------------------------------------
  static const String history = '/history';
  static const String recentlyPlayed = '/history/recently-played';
  static const String historyStats = '/history/stats';

  // --- Downloads ------------------------------------------------------------------------------
  static const String downloads = '/downloads';

  static String download(String id) => '/downloads/$id';
  static String downloadComplete(String id) => '/downloads/$id/complete';

  // --- Notifications --------------------------------------------------------------------------
  static const String notifications = '/notifications';
  static const String unreadCount = '/notifications/unread-count';
  static const String markAllRead = '/notifications/read-all';

  static String notificationRead(String id) => '/notifications/$id/read';

  // --- Uploads (artist flow) ------------------------------------------------------------------
  static const String uploadAudio = '/uploads/audio';

  // Chunked audio upload (large files): open a session, PUT raw parts, then complete. The session
  // reports the chunk size the server wants and which parts already landed, which is what makes an
  // interrupted upload resumable.
  static const String uploadAudioInitiate = '/uploads/audio/initiate';

  static String uploadAudioSession(String uploadId) => '/uploads/audio/$uploadId';

  static String uploadAudioPart(String uploadId, int partNumber) =>
      '/uploads/audio/$uploadId/parts/$partNumber';

  static String uploadAudioComplete(String uploadId) => '/uploads/audio/$uploadId/complete';
  static const String uploadImage = '/uploads/image';
}
