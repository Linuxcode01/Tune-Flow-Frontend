import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tuneflow/core/constants/app_constants.dart';
import 'package:tuneflow/core/theme/app_colors.dart';
import 'package:tuneflow/core/widgets/artwork.dart';
import 'package:tuneflow/features/catalog/domain/entities/song.dart';
import 'package:tuneflow/features/player/presentation/providers/player_providers.dart';

/// Horizontal rail of album-art cards, used for the home sections and "more like this".
///
/// Tapping a card plays it *within the rail*, so the queue matches what the user can see; that rule is
/// applied consistently by always passing the rail's list as the queue.
class SongRail extends StatelessWidget {
  const SongRail({
    super.key,
    required this.songs,
    required this.title,
    this.subtitle,
    this.trailing,
    this.cardSize = 148,
  });

  final List<Song> songs;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final double cardSize;

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondaryDark,
                            ),
                      ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
        SizedBox(
          height: cardSize + 62,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: songs.length,
            separatorBuilder: (BuildContext context, int index) => const SizedBox(width: 14),
            itemBuilder: (BuildContext context, int index) => SongCard(
              song: songs[index],
              queue: songs,
              size: cardSize,
            ),
          ),
        ),
      ],
    );
  }
}

/// A single album-art card.
class SongCard extends ConsumerWidget {
  const SongCard({
    super.key,
    required this.song,
    this.queue,
    this.size = 148,
  });

  final Song song;
  final List<Song>? queue;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Song? current = ref.watch(currentTrackProvider);
    final bool isCurrent = current?.id == song.id;

    return SizedBox(
      width: size,
      child: InkWell(
        onTap: () => ref
            .read(playerControllerProvider.notifier)
            .playSong(song, queue: queue),
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Stack(
              children: <Widget>[
                Artwork(
                  imageUrl: song.artworkUrl,
                  seed: song.artworkSeed,
                  size: size,
                  borderRadius: AppConstants.cardRadius,
                ),
                if (isCurrent)
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: AppColors.accent,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.graphic_eq_rounded, size: 16, color: Colors.black),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: isCurrent ? AppColors.accent : null,
                  ),
            ),
            Text(
              song.artistName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondaryDark,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
