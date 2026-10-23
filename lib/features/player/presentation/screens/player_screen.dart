// Flutter's animation library exports its own RepeatMode; the player's enum is the one that
// describes playback, so the framework's is hidden here rather than renamed.
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tuneflow/core/error/app_exception.dart';
import 'package:tuneflow/core/theme/app_colors.dart';
import 'package:tuneflow/core/utils/formatters.dart';
import 'package:tuneflow/core/widgets/artwork.dart';
import 'package:tuneflow/core/widgets/state_views.dart';
import 'package:tuneflow/features/catalog/domain/entities/song.dart';
import 'package:tuneflow/features/library/presentation/providers/library_providers.dart';
import 'package:tuneflow/features/player/domain/entities/player_state.dart';
import 'package:tuneflow/features/player/presentation/providers/player_providers.dart';
import 'package:tuneflow/features/player/presentation/widgets/queue_sheet.dart';

/// The expanded player (docs section 20).
///
/// Route-pushed rather than a bottom sheet so that the system back gesture and the mini-player's tap
/// both behave the same way, and so the player can be deep-linked.
class PlayerScreen extends ConsumerWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PlayerState player = ref.watch(playerControllerProvider);
    final Song? track = player.track;

    if (track == null) {
      return Scaffold(
        appBar: AppBar(leading: const _CloseButton()),
        body: const EmptyView(
          title: 'Nothing playing',
          message: 'Pick a track and it will show up here.',
          icon: Icons.play_circle_outline,
        ),
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: const _CloseButton(),
        actions: <Widget>[
          IconButton(
            tooltip: 'Queue',
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (BuildContext context) => const QueueSheet(),
            ),
            icon: const Icon(Icons.queue_music),
          ),
        ],
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.heroGradient),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double artworkSize = _artworkSize(constraints);
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: <Widget>[
                    const SizedBox(height: 16),
                    Hero(
                      tag: 'player-artwork',
                      child: Artwork(
                        imageUrl: track.artworkUrl,
                        seed: track.artworkSeed,
                        size: artworkSize,
                        borderRadius: 18,
                      ),
                    ),
                    const SizedBox(height: 28),
                    _TrackHeader(player: player, track: track),
                    const SizedBox(height: 12),
                    _ProgressSection(player: player),
                    const SizedBox(height: 8),
                    _Controls(player: player),
                    const SizedBox(height: 16),
                    _SecondaryActions(track: track),
                    const SizedBox(height: 24),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Keeps the artwork comfortably inside the viewport on short screens.
  double _artworkSize(BoxConstraints constraints) {
    final double available = constraints.maxWidth - 48;
    final double verticalBudget = constraints.maxHeight * 0.42;
    return <double>[available, verticalBudget, 320].reduce((double a, double b) => a < b ? a : b);
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Close',
      icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
      onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
    );
  }
}

class _TrackHeader extends ConsumerWidget {
  const _TrackHeader({required this.player, required this.track});

  final PlayerState player;
  final Song track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool liked = ref.watch(songLikedProvider(track));

    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                track.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Row(
                children: <Widget>[
                  Flexible(
                    child: Text(
                      track.artistName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.white70,
                          ),
                    ),
                  ),
                  if (track.album != null) ...<Widget>[
                    const Text(' · ', style: TextStyle(color: Colors.white38)),
                    Flexible(
                      child: Text(
                        track.album!.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.white54,
                            ),
                      ),
                    ),
                  ],
                ],
              ),
              if (player.status == PlaybackStatus.error && player.errorMessage != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  player.errorMessage!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.error),
                ),
              ],
            ],
          ),
        ),
        IconButton(
          tooltip: liked ? 'Remove from liked songs' : 'Add to liked songs',
          onPressed: () async {
            try {
              await ref.read(libraryActionsProvider).toggleLike(track);
            } on AppException catch (error) {
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(error.message)));
              }
            }
          },
          icon: Icon(
            liked ? Icons.favorite : Icons.favorite_border,
            color: liked ? AppColors.like : Colors.white70,
          ),
        ),
      ],
    );
  }
}

class _ProgressSection extends ConsumerWidget {
  const _ProgressSection({required this.player});

  final PlayerState player;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final double maxMs = player.duration.inMilliseconds.toDouble();
    final double valueMs = player.position.inMilliseconds.clamp(0, maxMs.toInt()).toDouble();

    return Column(
      children: <Widget>[
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            inactiveTrackColor: Colors.white24,
          ),
          child: Slider(
            value: maxMs <= 0 ? 0 : valueMs,
            max: maxMs <= 0 ? 1 : maxMs,
            onChanged: maxMs <= 0
                ? null
                : (double value) => ref
                    .read(playerControllerProvider.notifier)
                    .seek(Duration(milliseconds: value.round())),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                Formatters.duration(player.position),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70),
              ),
              Text(
                '-${Formatters.duration(player.remaining)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Controls extends ConsumerWidget {
  const _Controls({required this.player});

  final PlayerState player;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PlayerController controller = ref.read(playerControllerProvider.notifier);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: <Widget>[
        IconButton(
          tooltip: 'Shuffle',
          onPressed: controller.toggleShuffle,
          icon: Icon(
            Icons.shuffle,
            color: player.shuffle ? AppColors.accent : Colors.white70,
          ),
        ),
        IconButton(
          tooltip: 'Previous',
          iconSize: 38,
          onPressed: controller.previous,
          icon: const Icon(Icons.skip_previous, color: Colors.white),
        ),
        _PlayButton(player: player),
        IconButton(
          tooltip: 'Next',
          iconSize: 38,
          onPressed: player.hasNext ? controller.next : null,
          icon: const Icon(Icons.skip_next, color: Colors.white),
        ),
        IconButton(
          tooltip: _repeatTooltip(player.repeatMode),
          onPressed: controller.cycleRepeatMode,
          icon: Icon(
            player.repeatMode == RepeatMode.one ? Icons.repeat_one : Icons.repeat,
            color: player.repeatMode == RepeatMode.off ? Colors.white70 : AppColors.accent,
          ),
        ),
      ],
    );
  }

  String _repeatTooltip(RepeatMode mode) {
    switch (mode) {
      case RepeatMode.off:
        return 'Repeat off';
      case RepeatMode.all:
        return 'Repeat queue';
      case RepeatMode.one:
        return 'Repeat track';
    }
  }
}

class _PlayButton extends ConsumerWidget {
  const _PlayButton({required this.player});

  final PlayerState player;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PlayerController controller = ref.read(playerControllerProvider.notifier);

    return Container(
      width: 74,
      height: 74,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: IconButton(
        iconSize: 38,
        tooltip: player.isPlaying ? 'Pause' : 'Play',
        onPressed: controller.togglePlayPause,
        icon: player.isLoading
            ? const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 3, color: Colors.black),
              )
            : Icon(
                player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.black,
              ),
      ),
    );
  }
}

class _SecondaryActions extends ConsumerWidget {
  const _SecondaryActions({required this.track});

  final Song track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: <Widget>[
        _ActionChip(
          icon: Icons.add_circle_outline,
          label: 'Queue',
          onTap: () => ref.read(playerControllerProvider.notifier).enqueue(track),
        ),
        _ActionChip(
          icon: Icons.download_outlined,
          label: 'Download',
          onTap: () => context.push('/downloads'),
        ),
        _ActionChip(
          icon: Icons.album_outlined,
          label: 'Album',
          onTap: track.album == null
              ? null
              : () {
                  context.pop();
                  context.push('/album/${track.album!.id}');
                },
        ),
      ],
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onTap != null;
    final Color color = enabled ? Colors.white70 : Colors.white30;

    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: color),
      label: Text(label, style: TextStyle(color: color, fontSize: 12)),
    );
  }
}
