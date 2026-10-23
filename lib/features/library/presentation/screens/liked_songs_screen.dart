import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tuneflow/core/network/paged_response.dart';
import 'package:tuneflow/core/widgets/state_views.dart';
import 'package:tuneflow/features/catalog/domain/entities/song.dart';
import 'package:tuneflow/features/catalog/presentation/widgets/song_tile.dart';
import 'package:tuneflow/features/library/presentation/providers/library_providers.dart';
import 'package:tuneflow/features/player/presentation/providers/player_providers.dart';

/// The liked-songs collection, rendered from the same [SongTile] as every other tracklist.
class LikedSongsScreen extends ConsumerWidget {
  const LikedSongsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<PagedResponse<Song>> liked = ref.watch(likedSongsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Liked songs'),
        actions: <Widget>[
          liked.maybeWhen(
            data: (PagedResponse<Song> paged) => paged.items.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: 'Shuffle play',
                    icon: const Icon(Icons.shuffle),
                    onPressed: () {
                      final List<Song> shuffled = List<Song>.of(paged.items)..shuffle();
                      ref.read(playerControllerProvider.notifier).playQueue(shuffled);
                    },
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: liked.when(
        loading: () => const SkeletonList(),
        error: (Object error, StackTrace stackTrace) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(likedSongsProvider),
        ),
        data: (PagedResponse<Song> paged) {
          if (paged.items.isEmpty) {
            return const EmptyView(
              title: 'No liked songs yet',
              message: 'Tap the heart on any track and it will appear here.',
              icon: Icons.favorite_border,
            );
          }
          return ListView.builder(
            itemCount: paged.items.length,
            itemBuilder: (BuildContext context, int index) => SongTile(
              song: paged.items[index],
              queue: paged.items,
            ),
          );
        },
      ),
    );
  }
}
