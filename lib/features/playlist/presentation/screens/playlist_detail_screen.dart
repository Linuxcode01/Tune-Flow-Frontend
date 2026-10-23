import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tuneflow/app/router/route_paths.dart';
import 'package:tuneflow/core/error/app_exception.dart';
import 'package:tuneflow/core/theme/app_colors.dart';
import 'package:tuneflow/core/utils/formatters.dart';
import 'package:tuneflow/core/widgets/artwork.dart';
import 'package:tuneflow/core/widgets/state_views.dart';
import 'package:tuneflow/features/catalog/domain/entities/search_results.dart';
import 'package:tuneflow/features/catalog/domain/entities/song.dart';
import 'package:tuneflow/features/player/presentation/providers/player_providers.dart';
import 'package:tuneflow/features/playlist/presentation/providers/playlist_providers.dart';
import 'package:tuneflow/features/playlist/presentation/widgets/playlist_dialogs.dart';
import 'package:tuneflow/features/playlist/presentation/widgets/song_picker_sheet.dart';

/// Playlist detail with reordering for the owner (docs section 25).
///
/// Owners get a [ReorderableListView]: dragging a row rewrites the whole order through
/// `PUT /playlists/{id}/songs`, matching the API's replace-the-order model. Non-owners see the same
/// tracklist without drag handles, because the server would reject the write.
class PlaylistDetailScreen extends ConsumerWidget {
  const PlaylistDetailScreen({super.key, required this.playlistId});

  final String playlistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<PlaylistDetail> detail = ref.watch(playlistDetailProvider(playlistId));
    final PlaylistDetail? loaded = detail.valueOrNull;

    return Scaffold(
      // Owners get a permanent way in, not only the empty state - a playlist is filled over many
      // sessions, and hunting for an "add" affordance on every visit is the wrong kind of work.
      floatingActionButton: loaded != null && loaded.playlist.canEdit
          ? FloatingActionButton.extended(
              onPressed: () => _addSongs(context, ref, loaded),
              icon: const Icon(Icons.playlist_add),
              label: const Text('Add songs'),
            )
          : null,
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stackTrace) => Scaffold(
          appBar: AppBar(),
          body: ErrorView(
            error: error,
            onRetry: () => ref.invalidate(playlistDetailProvider(playlistId)),
          ),
        ),
        data: (PlaylistDetail data) => CustomScrollView(
          slivers: <Widget>[
            SliverAppBar(
              pinned: true,
              expandedHeight: 300,
              flexibleSpace: FlexibleSpaceBar(
                background: _Header(detail: data),
              ),
              actions: <Widget>[
                if (data.playlist.canEdit)
                  PopupMenuButton<String>(
                    onSelected: (String value) => _onMenuAction(context, ref, value, data),
                    itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                      const PopupMenuItem<String>(
                        value: 'edit',
                        child: ListTile(
                          leading: Icon(Icons.edit_outlined),
                          title: Text('Edit details'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem<String>(
                        value: 'delete',
                        child: ListTile(
                          leading: Icon(Icons.delete_outline),
                          title: Text('Delete playlist'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            if (data.songs.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    const EmptyView(
                      title: 'This playlist is empty',
                      message: 'Search the catalogue and pick the tracks you want in here.',
                      icon: Icons.queue_music,
                    ),
                    if (data.playlist.canEdit)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: FilledButton.icon(
                          onPressed: () => _addSongs(context, ref, data),
                          icon: const Icon(Icons.playlist_add),
                          label: const Text('Add songs'),
                        ),
                      ),
                  ],
                ),
              )
            else if (data.playlist.canEdit)
              SliverReorderableList(
                itemCount: data.songs.length,
                // onReorderItem already accounts for the removed item, unlike the deprecated
                // onReorder callback which required manual index adjustment.
                onReorderItem: (int oldIndex, int newIndex) =>
                    _onReorder(ref, data, oldIndex, newIndex),
                itemBuilder: (BuildContext context, int index) => _TrackRow(
                  key: ValueKey<String>(data.songs[index].id),
                  song: data.songs[index],
                  index: index,
                  queue: data.songs,
                  playlistId: playlistId,
                  draggable: true,
                ),
              )
            else
              SliverList.builder(
                itemCount: data.songs.length,
                itemBuilder: (BuildContext context, int index) => _TrackRow(
                  key: ValueKey<String>(data.songs[index].id),
                  song: data.songs[index],
                  index: index,
                  queue: data.songs,
                  playlistId: playlistId,
                  draggable: false,
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 90)),
          ],
        ),
      ),
    );
  }

  /// Opens the song picker for this playlist, skipping what is already in it.
  Future<void> _addSongs(BuildContext context, WidgetRef ref, PlaylistDetail detail) async {
    await showSongPickerSheet(
      context,
      ref,
      playlistId: playlistId,
      playlistName: detail.playlist.name,
      existingSongIds: detail.songs.map((Song song) => song.id).toSet(),
    );
  }

  Future<void> _onReorder(
    WidgetRef ref,
    PlaylistDetail detail,
    int oldIndex,
    int newIndex,
  ) async {
    if (oldIndex == newIndex) {
      return;
    }
    final List<String> ids = detail.songs.map((Song song) => song.id).toList(growable: true);
    final String moved = ids.removeAt(oldIndex);
    ids.insert(newIndex, moved);

    try {
      await ref.read(playlistActionsProvider).reorder(playlistId, ids);
    } on AppException catch (error) {
      if (ref.context.mounted) {
        ScaffoldMessenger.of(ref.context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _onMenuAction(
    BuildContext context,
    WidgetRef ref,
    String action,
    PlaylistDetail detail,
  ) async {
    if (action == 'edit') {
      await showCreatePlaylistDialog(context, ref, existing: detail.playlist);
      return;
    }

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('Delete "${detail.playlist.name}"?'),
        content: const Text('The playlist is removed. The songs themselves stay in the catalogue.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      await ref.read(playlistActionsProvider).delete(playlistId);
      if (context.mounted) {
        context.pop();
      }
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.detail});

  final PlaylistDetail detail;

  @override
  Widget build(BuildContext context) {
    final PlaylistSummary playlist = detail.playlist;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 72, 20, 20),
      decoration: const BoxDecoration(gradient: AppColors.heroGradient),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Artwork(
                imageUrl: playlist.coverImageUrl,
                seed: playlist.id,
                size: 120,
                borderRadius: 12,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (playlist.publicPlaylist)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 6),
                        child: StatusPill(label: 'PUBLIC', color: Colors.white),
                      ),
                    Text(
                      playlist.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: Colors.white,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (playlist.ownerName != null) playlist.ownerName!,
                        Formatters.collectionSummary(
                          playlist.songCount,
                          playlist.totalDurationSeconds,
                        ),
                      ].join(' · '),
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (detail.songs.isNotEmpty) ...<Widget>[
            const SizedBox(height: 18),
            Row(
              children: <Widget>[
                _PlayAllButton(songs: detail.songs),
                const SizedBox(width: 12),
                _ShuffleButton(songs: detail.songs),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PlayAllButton extends ConsumerWidget {
  const _PlayAllButton({required this.songs});

  final List<Song> songs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Expanded(
      child: FilledButton.icon(
        onPressed: () => ref.read(playerControllerProvider.notifier).playQueue(songs),
        icon: const Icon(Icons.play_arrow_rounded),
        label: const Text('Play'),
      ),
    );
  }
}

class _ShuffleButton extends ConsumerWidget {
  const _ShuffleButton({required this.songs});

  final List<Song> songs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white38),
        minimumSize: const Size(52, 52),
      ),
      onPressed: () {
        final PlayerController controller = ref.read(playerControllerProvider.notifier);
        final List<Song> shuffled = List<Song>.of(songs)..shuffle();
        controller.playQueue(shuffled);
        controller.toggleShuffle();
      },
      child: const Icon(Icons.shuffle),
    );
  }
}

class _TrackRow extends ConsumerWidget {
  const _TrackRow({
    super.key,
    required this.song,
    required this.index,
    required this.queue,
    required this.playlistId,
    required this.draggable,
  });

  final Song song;
  final int index;
  final List<Song> queue;
  final String playlistId;
  final bool draggable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Widget row = ListTile(
      onTap: () => ref
          .read(playerControllerProvider.notifier)
          .playSong(song, queue: queue),
      contentPadding: EdgeInsets.only(left: draggable ? 8 : 16, right: 8),
      leading: drragHandleOrIndex(context),
      title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(song.artistName, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            Formatters.durationFromSeconds(song.durationSeconds),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondaryDark,
                ),
          ),
          IconButton(
            tooltip: 'Remove from playlist',
            icon: const Icon(Icons.more_vert, size: 20),
            onPressed: () => _showRowMenu(context, ref),
          ),
        ],
      ),
    );

    return draggable
        ? ReorderableDragStartListener(index: index, child: row)
        : row;
  }

  /// Track number for readers, drag handle for owners.
  Widget drragHandleOrIndex(BuildContext context) {
    if (draggable) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: Icon(Icons.drag_handle, color: AppColors.textSecondaryDark),
      );
    }
    return SizedBox(
      width: 28,
      child: Center(
        child: Text(
          '${index + 1}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondaryDark,
              ),
        ),
      ),
    );
  }

  Future<void> _showRowMenu(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.album_outlined),
              title: const Text('Go to album'),
              enabled: song.album != null,
              onTap: () {
                Navigator.of(sheetContext).pop();
                if (song.album != null) {
                  context.push(RoutePaths.album(song.album!.id));
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Go to artist'),
              enabled: song.artist != null,
              onTap: () {
                Navigator.of(sheetContext).pop();
                if (song.artist != null) {
                  context.push(RoutePaths.artist(song.artist!.id));
                }
              },
            ),
            if (draggable)
              ListTile(
                leading: const Icon(Icons.playlist_remove),
                title: const Text('Remove from this playlist'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  try {
                    await ref.read(playlistActionsProvider).removeSong(playlistId, song.id);
                  } on AppException catch (error) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text(error.message)));
                    }
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}
