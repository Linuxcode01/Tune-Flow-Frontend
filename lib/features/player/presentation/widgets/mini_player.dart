import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tuneflow/app/router/route_paths.dart';
import 'package:tuneflow/core/constants/app_constants.dart';
import 'package:tuneflow/core/theme/app_colors.dart';
import 'package:tuneflow/core/widgets/artwork.dart';
import 'package:tuneflow/features/player/domain/entities/player_state.dart';
import 'package:tuneflow/features/player/presentation/providers/player_providers.dart';

/// The persistent mini-player that sits above the bottom navigation on every tab
/// (docs section 19).
///
/// It renders nothing when no track is loaded, so screens do not need to know whether it is visible -
/// the shell simply reserves the space when [PlayerState.hasTrack] is true.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PlayerState player = ref.watch(playerControllerProvider);
    if (!player.hasTrack) {
      return const SizedBox.shrink();
    }

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: InkWell(
        onTap: () => context.push(RoutePaths.player),
        child: SizedBox(
          height: AppConstants.miniPlayerHeight,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _ProgressBar(progress: player.progress),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: <Widget>[
                      Artwork(
                        imageUrl: player.track!.artworkUrl,
                        seed: player.track!.artworkSeed,
                        size: 42,
                        borderRadius: 6,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              player.track!.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            Text(
                              player.status == PlaybackStatus.error
                                  ? (player.errorMessage ?? 'Playback error')
                                  : player.track!.artistName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: player.status == PlaybackStatus.error
                                        ? AppColors.error
                                        : AppColors.textSecondaryDark,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: player.isPlaying ? 'Pause' : 'Play',
                        onPressed: () =>
                            ref.read(playerControllerProvider.notifier).togglePlayPause(),
                        icon: player.isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(player.isPlaying ? Icons.pause : Icons.play_arrow, size: 28),
                      ),
                      IconButton(
                        tooltip: 'Next',
                        onPressed:
                            player.hasNext ? ref.read(playerControllerProvider.notifier).next : null,
                        icon: const Icon(Icons.skip_next, size: 26),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 2,
      child: LinearProgressIndicator(
        value: progress,
        minHeight: 2,
        backgroundColor: AppColors.darkDivider,
      ),
    );
  }
}
