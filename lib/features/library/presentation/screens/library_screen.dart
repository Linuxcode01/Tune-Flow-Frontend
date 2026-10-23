import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tuneflow/app/router/route_paths.dart';
import 'package:tuneflow/core/network/paged_response.dart';
import 'package:tuneflow/core/theme/app_colors.dart';
import 'package:tuneflow/core/utils/formatters.dart';
import 'package:tuneflow/core/widgets/artwork.dart';
import 'package:tuneflow/core/widgets/state_views.dart';
import 'package:tuneflow/features/catalog/domain/entities/search_results.dart';
import 'package:tuneflow/features/library/domain/entities/history_stats.dart';
import 'package:tuneflow/features/library/presentation/providers/library_providers.dart';
import 'package:tuneflow/features/playlist/presentation/providers/playlist_providers.dart';
import 'package:tuneflow/features/playlist/presentation/widgets/playlist_dialogs.dart';
import 'package:tuneflow/features/playlist/presentation/widgets/song_picker_sheet.dart';

/// Library tab: the listener's own collection (docs section 22).
///
/// Ordered by how often it is used: liked songs, recently played, then playlists. The listening-stats
/// card is the one place the app reflects the user's own behaviour back at them.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<int> likedCount = ref
        .watch(likedSongsProvider)
        .whenData((paged) => paged.totalElements);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your library'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Downloads',
            onPressed: () => context.push(RoutePaths.downloads),
            icon: const Icon(Icons.download_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createPlaylist(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('New playlist'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(likedSongsProvider);
          ref.invalidate(playlistsProvider);
          ref.invalidate(historyStatsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: <Widget>[
            _QuickAccessTile(
              icon: Icons.favorite,
              iconColor: AppColors.like,
              title: 'Liked songs',
              subtitle: likedCount.when(
                data: (int count) => count == 1 ? '1 song' : '$count songs',
                loading: () => 'Loading…',
                error: (_, __) => '',
              ),
              onTap: () => context.push(RoutePaths.likedSongs),
            ),
            _QuickAccessTile(
              icon: Icons.history,
              iconColor: AppColors.secondary,
              title: 'Recently played',
              subtitle: 'Pick up where you left off',
              onTap: () => context.push(RoutePaths.recentlyPlayed),
            ),
            _QuickAccessTile(
              icon: Icons.download_done,
              iconColor: AppColors.success,
              title: 'Downloads',
              subtitle: 'Available without a connection',
              onTap: () => context.push(RoutePaths.downloads),
            ),
            const _ListeningStatsCard(),
            const _PlaylistsSection(),
          ],
        ),
      ),
    );
  }
}

class _QuickAccessTile extends StatelessWidget {
  const _QuickAccessTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor),
      ),
      title: Text(title, style: Theme.of(context).textTheme.titleSmall),
      subtitle: Text(
        subtitle,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondaryDark,
            ),
      ),
      trailing: const Icon(Icons.chevron_right, size: 20),
    );
  }
}

/// Weekly listening summary with a seven-bar chart.
class _ListeningStatsCard extends ConsumerWidget {
  const _ListeningStatsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<HistoryStats> stats = ref.watch(historyStatsProvider);

    return stats.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: LinearProgressIndicator(minHeight: 2),
      ),
      // A failed stats call is not worth an error card in the middle of the library: hide the card.
      error: (Object error, StackTrace stackTrace) => const SizedBox.shrink(),
      data: (HistoryStats data) {
        if (data.isEmpty) {
          return const SizedBox.shrink();
        }

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: <Color>[
                AppColors.accent.withValues(alpha: 0.18),
                AppColors.secondary.withValues(alpha: 0.12),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(Icons.insights, size: 18, color: AppColors.accent),
                  const SizedBox(width: 8),
                  Text('Your listening', style: Theme.of(context).textTheme.titleSmall),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  _Stat(label: 'Plays', value: '${data.totalPlays}'),
                  _Stat(
                    label: 'Time',
                    value: data.listeningHours >= 1
                        ? '${data.listeningHours.toStringAsFixed(1)}h'
                        : '${(data.totalListeningSeconds / 60).round()}m',
                  ),
                  _Stat(label: 'Artists', value: '${data.uniqueArtists}'),
                  _Stat(label: 'Tracks', value: '${data.uniqueSongs}'),
                ],
              ),
              const SizedBox(height: 16),
              _WeeklyChart(days: data.lastSevenDays, peak: data.peakDailyPlays),
              if (data.topGenres.isNotEmpty) ...<Widget>[
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: data.topGenres
                      .take(4)
                      .map((TopGenre genre) => StatusPill(label: genre.name))
                      .toList(growable: false),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(value, style: Theme.of(context).textTheme.titleMedium),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.textSecondaryDark,
                ),
          ),
        ],
      ),
    );
  }
}

/// Seven bars, scaled to the busiest day. Rendered with plain containers - a charting package would
/// be overkill for seven rectangles.
class _WeeklyChart extends StatelessWidget {
  const _WeeklyChart({required this.days, required this.peak});

  final List<DailyPlays> days;
  final int peak;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) {
      return const SizedBox.shrink();
    }
    final int safePeak = peak <= 0 ? 1 : peak;

    return SizedBox(
      height: 44,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: days.map((DailyPlays day) {
          final double ratio = day.plays / safePeak;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  Container(
                    height: (ratio * 32).clamp(2, 32),
                    decoration: BoxDecoration(
                      color: day.plays > 0 ? AppColors.accent : AppColors.darkDivider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(growable: false),
      ),
    );
  }
}

class _PlaylistsSection extends ConsumerWidget {
  const _PlaylistsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Typed, not `AsyncValue<dynamic>`: the dynamic version compiled fine and then needed a
    // `.cast<>()` to get back to real types, which is exactly how a provider swap turns into a
    // runtime type error on a device instead of a compile error.
    final AsyncValue<PagedResponse<PlaylistSummary>> playlists = ref.watch(playlistsProvider);

    return playlists.when(
      loading: () => const SizedBox.shrink(),
      error: (Object error, StackTrace stackTrace) => const SizedBox.shrink(),
      data: (PagedResponse<PlaylistSummary> paged) {
        final List<PlaylistSummary> items = paged.items;
        if (items.isEmpty) {
          return const Padding(
            padding: EdgeInsets.only(top: 24),
            child: EmptyView(
              title: 'No playlists yet',
              message: 'Create one to collect the tracks you love.',
              icon: Icons.queue_music,
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: Text('Playlists', style: Theme.of(context).textTheme.titleLarge),
            ),
            ...items.map(
              (PlaylistSummary playlist) => ListTile(
                onTap: () => context.push(RoutePaths.playlist(playlist.id)),
                leading: Artwork(
                  imageUrl: playlist.coverImageUrl,
                  seed: playlist.id,
                  size: 48,
                ),
                title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  Formatters.collectionSummary(
                    playlist.songCount,
                    playlist.totalDurationSeconds,
                  ),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondaryDark,
                      ),
                ),
                trailing: playlist.publicPlaylist
                    ? const StatusPill(label: 'PUBLIC')
                    : null,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Creates a playlist, then offers the obvious next step.
///
/// The dialog used to end at "playlist created", leaving an empty playlist and no visible way to
/// fill it - the dead end this feature exists to remove. The snackbar action opens the same picker
/// the playlist screen uses, so both routes into "add songs" are identical.
Future<void> _createPlaylist(BuildContext context, WidgetRef ref) async {
  final PlaylistSummary? created = await showCreatePlaylistDialog(context, ref);
  if (created == null || !context.mounted) {
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('Created ${created.name}'),
      // Longer than the 4 s default: the action is the point of this snackbar.
      duration: const Duration(seconds: 6),
      action: SnackBarAction(
        label: 'Add songs',
        onPressed: () => showSongPickerSheet(
          context,
          ref,
          playlistId: created.id,
          playlistName: created.name,
        ),
      ),
    ),
  );
}
