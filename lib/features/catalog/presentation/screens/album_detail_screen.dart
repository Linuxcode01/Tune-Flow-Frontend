import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tuneflow/app/router/route_paths.dart';
import 'package:tuneflow/core/theme/app_colors.dart';
import 'package:tuneflow/core/utils/formatters.dart';
import 'package:tuneflow/core/widgets/artwork.dart';
import 'package:tuneflow/core/widgets/state_views.dart';
import 'package:tuneflow/features/catalog/domain/entities/album.dart';
import 'package:tuneflow/features/catalog/domain/entities/song.dart';
import 'package:tuneflow/features/catalog/presentation/providers/catalog_providers.dart';
import 'package:tuneflow/features/catalog/presentation/widgets/song_tile.dart';
import 'package:tuneflow/features/player/presentation/providers/player_providers.dart';
import 'package:tuneflow/features/playlist/presentation/widgets/playlist_dialogs.dart';

/// Album detail: header, follow-artist action, tracklist, and "more from this artist".
class AlbumDetailScreen extends ConsumerWidget {
  const AlbumDetailScreen({super.key, required this.albumId});

  final String albumId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Album> album = ref.watch(albumProvider(albumId));
    final AsyncValue<List<Song>> songs = ref.watch(albumSongsProvider(albumId));

    return Scaffold(
      body: album.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stackTrace) => Scaffold(
          appBar: AppBar(),
          body: ErrorView(error: error, onRetry: () => ref.invalidate(albumProvider(albumId))),
        ),
        data: (Album data) => CustomScrollView(
          slivers: <Widget>[
            SliverAppBar(
              pinned: true,
              expandedHeight: 280,
              flexibleSpace: FlexibleSpaceBar(
                background: _AlbumHeader(album: data),
              ),
            ),
            SliverToBoxAdapter(
              child: _AlbumActions(
                album: data,
                songs: songs.valueOrNull ?? const <Song>[],
              ),
            ),
            songs.when(
              loading: () => const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              error: (Object error, StackTrace stackTrace) => SliverToBoxAdapter(
                child: ErrorView(
                  error: error,
                  onRetry: () => ref.invalidate(albumSongsProvider(albumId)),
                ),
              ),
              data: (List<Song> tracks) => SliverList.builder(
                itemCount: tracks.length,
                itemBuilder: (BuildContext context, int index) => SongTile(
                  song: tracks[index],
                  queue: tracks,
                  index: tracks[index].trackNumber ?? index + 1,
                  showArtwork: false,
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 90)),
          ],
        ),
      ),
    );
  }
}

class _AlbumHeader extends StatelessWidget {
  const _AlbumHeader({required this.album});

  final Album album;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 72, 20, 20),
      decoration: const BoxDecoration(gradient: AppColors.heroGradient),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Artwork(imageUrl: album.coverImageUrl, seed: album.id, size: 132, borderRadius: 12),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                const Text(
                  'ALBUM',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  album.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 8),
                if (album.artist != null)
                  GestureDetector(
                    onTap: () => context.push(RoutePaths.artist(album.artist!.id)),
                    child: Row(
                      children: <Widget>[
                        Artwork(
                          imageUrl: album.artist!.profileImageUrl,
                          seed: album.artist!.id,
                          size: 22,
                          isCircle: true,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          album.artist!.name,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                        ),
                        if (album.artist!.verified) ...<Widget>[
                          const SizedBox(width: 6),
                          const Icon(Icons.verified, size: 14, color: AppColors.accent),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: 6),
                Text(
                  [
                    if (album.releaseDate != null) Formatters.releaseDate(album.releaseDate),
                    Formatters.collectionSummary(album.songCount, album.totalDurationSeconds),
                  ].join(' · '),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AlbumActions extends ConsumerWidget {
  const _AlbumActions({required this.album, required this.songs});

  final Album album;
  final List<Song> songs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (album.description != null && album.description!.isNotEmpty) ...<Widget>[
            Text(
              album.description!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondaryDark,
                  ),
            ),
            const SizedBox(height: 14),
          ],
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  onPressed: songs.isEmpty
                      ? null
                      : () => ref.read(playerControllerProvider.notifier).playQueue(songs),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Play'),
                ),
              ),
              const SizedBox(width: 10),
              if (songs.isNotEmpty)
                IconButton.filledTonal(
                  tooltip: 'Shuffle',
                  onPressed: () {
                    final PlayerController controller = ref.read(playerControllerProvider.notifier);
                    controller.playQueue(List<Song>.of(songs)..shuffle());
                    controller.toggleShuffle();
                  },
                  icon: const Icon(Icons.shuffle),
                ),
              if (songs.isNotEmpty)
                IconButton.filledTonal(
                  tooltip: 'Add album to playlist',
                  // The whole album: the previous version silently added only the first track, which
                  // looks like a successful "add this album" until the playlist is opened.
                  onPressed: () => showAddToPlaylistSheet(
                    context,
                    ref,
                    songIds: songs.map((Song song) => song.id).toList(growable: false),
                  ),
                  icon: const Icon(Icons.playlist_add),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
