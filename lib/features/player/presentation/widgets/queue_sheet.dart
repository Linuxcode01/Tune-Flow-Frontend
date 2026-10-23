import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tuneflow/core/theme/app_colors.dart';
import 'package:tuneflow/core/utils/formatters.dart';
import 'package:tuneflow/core/widgets/artwork.dart';
import 'package:tuneflow/features/player/domain/entities/player_state.dart';
import 'package:tuneflow/features/player/presentation/providers/player_providers.dart';

/// Upcoming tracks, with the current one highlighted.
///
/// Read-only by design: reordering the queue is a playlist-level concept in this app, and the API
/// only models ordering for playlists. Keeping the sheet honest about that avoids a drag interaction
/// that would silently do nothing.
class QueueSheet extends ConsumerWidget {
  const QueueSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PlayerState player = ref.watch(playerControllerProvider);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      builder: (BuildContext context, ScrollController controller) {
        return Column(
          children: <Widget>[
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.darkDivider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: <Widget>[
                  Text('Playing next', style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  Text(
                    '${player.queue.length} tracks',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondaryDark,
                        ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: controller,
                itemCount: player.queue.length,
                itemBuilder: (BuildContext context, int index) {
                  final bool isCurrent = index == player.index;
                  final track = player.queue[index];
                  return ListTile(
                    onTap: () => ref
                        .read(playerControllerProvider.notifier)
                        .playQueue(player.queue, startIndex: index),
                    leading: Artwork(
                      imageUrl: track.artworkUrl,
                      seed: track.artworkSeed,
                      size: 44,
                    ),
                    title: Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isCurrent ? AppColors.accent : null,
                        fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      track.artistName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: isCurrent
                        ? const Icon(Icons.graphic_eq_rounded, color: AppColors.accent, size: 18)
                        : Text(
                            Formatters.durationFromSeconds(track.durationSeconds),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: AppColors.textSecondaryDark,
                                ),
                          ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
