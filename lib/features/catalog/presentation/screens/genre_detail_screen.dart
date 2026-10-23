import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tuneflow/core/network/paged_response.dart';
import 'package:tuneflow/core/theme/app_colors.dart';
import 'package:tuneflow/core/widgets/state_views.dart';
import 'package:tuneflow/features/catalog/domain/entities/genre.dart';
import 'package:tuneflow/features/catalog/domain/entities/song.dart';
import 'package:tuneflow/features/catalog/presentation/providers/catalog_providers.dart';
import 'package:tuneflow/features/catalog/presentation/widgets/song_tile.dart';
import 'package:tuneflow/features/player/presentation/providers/player_providers.dart';

/// Everything in one genre.
///
/// The route carries the genre *slug* rather than an id, because the catalogue filters by slug
/// (`GET /songs?genre=synthwave`) - the screen only needs the name for its title, which it resolves
/// from the genres list.
class GenreDetailScreen extends ConsumerWidget {
  const GenreDetailScreen({super.key, required this.genreSlug});

  final String genreSlug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<PagedResponse<Song>> songs = ref.watch(genreSongsProvider(genreSlug));
    final String title = ref.watch(genresProvider).maybeWhen(
          data: (List<Genre> genres) => genres
              .where((Genre genre) => genre.slug == genreSlug)
              .map((Genre genre) => genre.name)
              .firstOrNull ??
              _humanise(genreSlug),
          orElse: () => _humanise(genreSlug),
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: <Widget>[
          songs.maybeWhen(
            data: (PagedResponse<Song> page) => page.items.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: 'Shuffle play',
                    icon: const Icon(Icons.shuffle),
                    onPressed: () {
                      final PlayerController controller =
                          ref.read(playerControllerProvider.notifier);
                      controller.playQueue(List<Song>.of(page.items)..shuffle());
                      controller.toggleShuffle();
                    },
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: songs.when(
        loading: () => const SkeletonList(),
        error: (Object error, StackTrace stackTrace) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(genreSongsProvider(genreSlug)),
        ),
        data: (PagedResponse<Song> page) {
          if (page.items.isEmpty) {
            return const EmptyView(
              title: 'Nothing in this genre yet',
              icon: Icons.library_music_outlined,
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 90),
            itemCount: page.items.length,
            itemBuilder: (BuildContext context, int index) => SongTile(
              song: page.items[index],
              queue: page.items,
            ),
          );
        },
      ),
      floatingActionButton: songs.maybeWhen(
        data: (PagedResponse<Song> page) => page.items.isEmpty
            ? null
            : FloatingActionButton.extended(
                onPressed: () =>
                    ref.read(playerControllerProvider.notifier).playQueue(page.items),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Play all'),
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.black,
              ),
        orElse: () => null,
      ),
    );
  }

  /// `drum-and-bass` -> `Drum And Bass`, used until the genres list resolves.
  String _humanise(String slug) => slug
      .split(RegExp('[-_]'))
      .where((String part) => part.isNotEmpty)
      .map((String part) => part[0].toUpperCase() + part.substring(1))
      .join(' ');
}
