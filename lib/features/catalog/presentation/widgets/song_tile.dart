import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tuneflow/app/router/route_paths.dart';
import 'package:tuneflow/core/error/app_exception.dart';
import 'package:tuneflow/core/theme/app_colors.dart';
import 'package:tuneflow/core/utils/formatters.dart';
import 'package:tuneflow/core/widgets/artwork.dart';
import 'package:tuneflow/core/widgets/state_views.dart';
import 'package:tuneflow/features/catalog/domain/entities/song.dart';
import 'package:tuneflow/features/library/presentation/providers/library_providers.dart';
import 'package:tuneflow/features/player/presentation/providers/player_providers.dart';
import 'package:tuneflow/features/playlist/presentation/widgets/playlist_dialogs.dart';

/// The one row used for every track lists in the app - home rails, search results, album and
/// playlist tracklists, liked songs.
///
/// A single implementation means the play-tap behaviour, the like button, the "now playing" highlight
/// and the overflow menu are consistent everywhere, and there is exactly one place to change them.
class SongTile extends ConsumerWidget {
  const SongTile({
    super.key,
    required this.song,
    this.queue,
    this.index,
    this.showArtwork = true,
    this.showLikeButton = true,
    this.showMenu = true,
    this.trailing,
    this.onTapOverride,
    this.subtitleOverride,
  });

  final Song song;

  /// The list this row belongs to; tapping plays the song *within that list*, which is what makes
  /// "next track" mean the next row the user can see.
  final List<Song>? queue;

  /// One-based position shown instead of artwork in album/playlist tracklists.
  final int? index;

  final bool showArtwork;
  final bool showLikeButton;

  /// The per-row overflow menu. On by default: "add this to a playlist" belongs on the track, not
  /// only on the album header and the playlist screen.
  final bool showMenu;
  final Widget? trailing;

  final VoidCallback? onTapOverride;
  final String? subtitleOverride;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Song? current = ref.watch(currentTrackProvider);
    final bool isCurrent = current?.id == song.id;
    final bool liked = ref.watch(songLikedProvider(song));

    return ListTile(
      key: ValueKey<String>('song-${song.id}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      onTap: onTapOverride ?? () => _play(ref),
      leading: showArtwork
          ? _Leading(song: song, index: index, isCurrent: isCurrent)
          : null,
      title: Text(
        song.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: isCurrent ? AppColors.accent : null,
              fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w600,
            ),
      ),
      subtitle: Row(
        children: <Widget>[
          if (song.explicit) ...<Widget>[
            const StatusPill(label: 'E', color: AppColors.textSecondaryDark),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              subtitleOverride ?? song.artistName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondaryDark,
                  ),
            ),
          ),
        ],
      ),
      trailing: trailing ??
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                Formatters.durationFromSeconds(song.durationSeconds),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondaryDark,
                    ),
              ),
              if (showMenu) _SongMenuButton(song: song),
              if (showLikeButton)
                IconButton(
                  onPressed: () => _toggleLike(context, ref),
                  tooltip: liked ? 'Remove from liked songs' : 'Add to liked songs',
                  icon: Icon(
                    liked ? Icons.favorite : Icons.favorite_border,
                    size: 20,
                    color: liked ? AppColors.like : AppColors.textSecondaryDark,
                  ),
                ),
            ],
          ),
    );
  }

  Future<void> _play(WidgetRef ref) async {
    await ref.read(playerControllerProvider.notifier).playSong(song, queue: queue);
  }

  Future<void> _toggleLike(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(libraryActionsProvider).toggleLike(song);
    } on AppException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }
}

/// Artwork or track number, with a "now playing" equaliser overlay.
class _Leading extends StatelessWidget {
  const _Leading({required this.song, this.index, required this.isCurrent});

  final Song song;
  final int? index;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final Widget artwork = Artwork(
      imageUrl: song.artworkUrl,
      seed: song.artworkSeed,
      size: 48,
    );

    if (isCurrent) {
      return Stack(
        alignment: Alignment.center,
        children: <Widget>[
          artwork,
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.graphic_eq_rounded, color: AppColors.accent, size: 22),
          ),
        ],
      );
    }

    if (index != null) {
      return SizedBox(
        width: 48,
        child: Center(
          child: Text(
            '$index',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondaryDark,
                ),
          ),
        ),
      );
    }

    return artwork;
  }
}

/// Per-track overflow menu.
///
/// Deliberately small: one action that is otherwise hard to reach (adding to a playlist) and two
/// navigations that are otherwise only possible by opening the player. Anything more belongs in the
/// full-screen player, where there is room to explain it.
enum _SongMenuAction { addToPlaylist, goToAlbum, goToArtist }

class _SongMenuButton extends ConsumerWidget {
  const _SongMenuButton({required this.song});

  final Song song;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<_SongMenuAction>(
      tooltip: 'More options',
      icon: const Icon(Icons.more_vert, size: 20, color: AppColors.textSecondaryDark),
      onSelected: (_SongMenuAction action) => _handle(context, ref, action),
      itemBuilder: (BuildContext context) => <PopupMenuEntry<_SongMenuAction>>[
        const PopupMenuItem<_SongMenuAction>(
          value: _SongMenuAction.addToPlaylist,
          child: ListTile(
            leading: Icon(Icons.playlist_add),
            title: Text('Add to playlist'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        if (song.album?.id != null)
          const PopupMenuItem<_SongMenuAction>(
            value: _SongMenuAction.goToAlbum,
            child: ListTile(
              leading: Icon(Icons.album_outlined),
              title: Text('Go to album'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (song.artist?.id != null)
          const PopupMenuItem<_SongMenuAction>(
            value: _SongMenuAction.goToArtist,
            child: ListTile(
              leading: Icon(Icons.person_outline),
              title: Text('Go to artist'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
      ],
    );
  }

  Future<void> _handle(BuildContext context, WidgetRef ref, _SongMenuAction action) async {
    switch (action) {
      case _SongMenuAction.addToPlaylist:
        await showAddToPlaylistSheet(context, ref, songIds: <String>[song.id]);
      case _SongMenuAction.goToAlbum:
        final String? albumId = song.album?.id;
        if (albumId != null) {
          await context.push(RoutePaths.album(albumId));
        }
      case _SongMenuAction.goToArtist:
        final String? artistId = song.artist?.id;
        if (artistId != null) {
          await context.push(RoutePaths.artist(artistId));
        }
    }
  }
}
