import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tuneflow/core/constants/api_endpoints.dart';
import 'package:tuneflow/core/error/app_exception.dart';
import 'package:tuneflow/core/network/paged_response.dart';
import 'package:tuneflow/core/providers/core_providers.dart';
import 'package:tuneflow/features/catalog/domain/entities/search_results.dart';
import 'package:tuneflow/features/library/presentation/providers/library_providers.dart';

/// Playlists: reads, plus the mutations the library screen drives.
///
/// Mutations return the updated playlist from the API and then invalidate the affected providers, so
/// the UI reflects the server's ordering rather than a guess about where a track landed.

final FutureProvider<PagedResponse<PlaylistSummary>> playlistsProvider =
    FutureProvider<PagedResponse<PlaylistSummary>>(
  (Ref ref) => ref.watch(apiClientProvider).getPaged<PlaylistSummary>(
        ApiEndpoints.playlists,
        size: 50,
        itemMapper: PlaylistSummary.fromJson,
      ),
  name: 'playlists',
);

final FutureProvider<PagedResponse<PlaylistSummary>> publicPlaylistsProvider =
    FutureProvider<PagedResponse<PlaylistSummary>>(
  (Ref ref) => ref.watch(apiClientProvider).getPaged<PlaylistSummary>(
        ApiEndpoints.publicPlaylists,
        size: 30,
        itemMapper: PlaylistSummary.fromJson,
      ),
  name: 'publicPlaylists',
);

final FutureProviderFamily<PlaylistDetail, String> playlistDetailProvider =
    FutureProvider.family<PlaylistDetail, String>(
  (Ref ref, String id) async {
    final Map<String, dynamic> data = await ref.watch(apiClientProvider).getJson(ApiEndpoints.playlist(id));
    return PlaylistDetail.fromJson(data);
  },
  name: 'playlistDetail',
);

/// Write operations on playlists.
class PlaylistActions {
  const PlaylistActions(this._ref);

  final Ref _ref;

  Future<PlaylistSummary> create({
    required String name,
    String? description,
    bool isPublic = false,
  }) async {
    final Map<String, dynamic> data = await _ref.read(apiClientProvider).post(
      ApiEndpoints.playlists,
      body: <String, dynamic>{
        'name': name,
        if (description != null && description.isNotEmpty) 'description': description,
        'publicPlaylist': isPublic,
      },
    );
    _invalidateLists();
    return PlaylistSummary.fromJson(data);
  }

  Future<void> update(
    String id, {
    String? name,
    String? description,
    bool? isPublic,
  }) async {
    await _ref.read(apiClientProvider).put(
      ApiEndpoints.playlist(id),
      body: <String, dynamic>{
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        if (isPublic != null) 'publicPlaylist': isPublic,
      },
    );
    _invalidate(id);
  }

  Future<void> delete(String id) async {
    await _ref.read(apiClientProvider).delete(ApiEndpoints.playlist(id));
    _invalidateLists();
  }

  /// Appends a song (or inserts at [position]) and returns the refreshed detail.
  Future<PlaylistDetail> addSong(String playlistId, String songId, {int? position}) async {
    await _ref.read(apiClientProvider).post(
      ApiEndpoints.playlistSongs(playlistId),
      body: <String, dynamic>{
        'songId': songId,
        if (position != null) 'position': position,
      },
    );
    _invalidate(playlistId);
    return _ref.read(playlistDetailProvider(playlistId).future);
  }

  /// Adds several songs in one user action, skipping the ones the API refuses.
  ///
  /// `POST /playlists/{id}/songs` takes a single song and answers `409 SONG_ALREADY_IN_PLAYLIST`
  /// for a duplicate. Adding a selection therefore has to be a loop, and the loop must not abort
  /// half-way: adding 10 songs where the 3rd is already present should end with 9 new rows and a
  /// message that says so, not with 2 rows and a red snackbar.
  Future<PlaylistAddResult> addSongs(String playlistId, Iterable<String> songIds) async {
    int added = 0;
    int skipped = 0;
    String? firstError;

    for (final String songId in songIds) {
      try {
        await _ref.read(apiClientProvider).post(
          ApiEndpoints.playlistSongs(playlistId),
          body: <String, dynamic>{'songId': songId},
        );
        added++;
      } on AppException catch (exception) {
        // "Already in this playlist" is information, not a failure - the row is simply already there.
        if (exception.errorCode == 'SONG_ALREADY_IN_PLAYLIST') {
          skipped++;
        } else {
          firstError ??= exception.message;
        }
      }
    }

    _invalidate(playlistId);
    return PlaylistAddResult(added: added, skipped: skipped, firstError: firstError);
  }

  Future<void> removeSong(String playlistId, String songId) async {
    await _ref.read(apiClientProvider).delete(
      ApiEndpoints.playlistSong(playlistId, songId),
    );
    _invalidate(playlistId);
  }

  /// Rewrites the whole order in one request - the API models ordering as a full replacement
  /// (`PUT /playlists/{id}/songs`), which avoids ambiguous partial reorder semantics.
  Future<void> reorder(String playlistId, List<String> songIds) async {
    await _ref.read(apiClientProvider).put(
      ApiEndpoints.playlistSongs(playlistId),
      body: <String, dynamic>{'songIds': songIds},
    );
    _invalidate(playlistId);
  }

  Future<void> clear(String playlistId) async {
    await _ref.read(apiClientProvider).delete(ApiEndpoints.playlistSongs(playlistId));
    _invalidate(playlistId);
  }

  /// Moves a track one slot up or down and persists the new order.
  Future<void> move(String playlistId, List<String> songIds, int from, int to) async {
    if (to < 0 || to >= songIds.length) {
      return;
    }
    final List<String> reordered = List<String>.of(songIds);
    final String moved = reordered.removeAt(from);
    reordered.insert(to, moved);
    await reorder(playlistId, reordered);
  }

  void _invalidate(String playlistId) {
    _ref.invalidate(playlistDetailProvider(playlistId));
    _invalidateLists();
  }

  void _invalidateLists() {
    _ref.invalidate(playlistsProvider);
    _ref.invalidate(publicPlaylistsProvider);
    // The library shows playlist counts next to liked songs.
    _ref.invalidate(likedSongsProvider);
  }
}

/// Outcome of a multi-song add, so the UI can report exactly what happened.
class PlaylistAddResult {
  const PlaylistAddResult({required this.added, this.skipped = 0, this.firstError});

  final int added;

  /// Songs the API reported as already present.
  final int skipped;

  /// The first genuine failure, if any (a network drop, a playlist deleted in another tab).
  final String? firstError;

  bool get isComplete => added > 0 && skipped == 0 && firstError == null;

  String describe(String playlistName) {
    if (added == 0 && skipped > 0) {
      return skipped == 1
          ? 'That song is already in $playlistName'
          : 'Those songs are already in $playlistName';
    }
    final String base = added == 1 ? 'Added 1 song to $playlistName' : 'Added $added songs to $playlistName';
    final List<String> notes = <String>[
      if (skipped > 0) '$skipped already there',
      if (firstError != null) firstError!,
    ];
    return notes.isEmpty ? base : '$base (${notes.join('; ')})';
  }
}

final Provider<PlaylistActions> playlistActionsProvider = Provider<PlaylistActions>(
  (Ref ref) => PlaylistActions(ref),
  name: 'playlistActions',
);
