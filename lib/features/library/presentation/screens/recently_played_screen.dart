import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tuneflow/core/widgets/state_views.dart';
import 'package:tuneflow/features/catalog/domain/entities/song.dart';
import 'package:tuneflow/features/catalog/presentation/widgets/song_tile.dart';
import 'package:tuneflow/features/library/presentation/providers/library_providers.dart';

/// Recently played, plus the destructive "clear history" action.
///
/// Clearing is guarded by a confirmation dialog because it is irreversible from the client - the API
/// only exposes a delete.
class RecentlyPlayedScreen extends ConsumerWidget {
  const RecentlyPlayedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Song>> recent = ref.watch(recentlyPlayedProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recently played'),
        actions: <Widget>[
          recent.maybeWhen(
            data: (List<Song> songs) => songs.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: 'Clear history',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _confirmClear(context, ref),
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: recent.when(
        loading: () => const SkeletonList(),
        error: (Object error, StackTrace stackTrace) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(recentlyPlayedProvider),
        ),
        data: (List<Song> songs) {
          if (songs.isEmpty) {
            return const EmptyView(
              title: 'Nothing played yet',
              message: 'Tracks you listen to will show up here.',
              icon: Icons.history,
            );
          }
          return ListView.builder(
            itemCount: songs.length,
            // `GET /history/recently-played` returns distinct songs, most recent first - it carries
            // no per-row timestamp, so there is nothing honest to print here. It used to render
            // `Formatters.relativeTime(DateTime.now())`, which stamped every row "now" and looked
            // like real data. The paginated `GET /history` endpoint is the one with `playedAt`;
            // wiring an entry-level model is the follow-up if per-row times are wanted.
            itemBuilder: (BuildContext context, int index) => SongTile(
              song: songs[index],
              queue: songs,
              showLikeButton: false,
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Clear listening history?'),
        content: const Text(
          'This removes every recorded play. Your likes and playlists are not affected.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      await ref.read(libraryActionsProvider).clearHistory();
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('History cleared')));
      }
    }
  }
}
