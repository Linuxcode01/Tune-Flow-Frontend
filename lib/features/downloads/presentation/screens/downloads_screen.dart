import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tuneflow/core/error/app_exception.dart';
import 'package:tuneflow/core/network/paged_response.dart';
import 'package:tuneflow/core/theme/app_colors.dart';
import 'package:tuneflow/core/utils/formatters.dart';
import 'package:tuneflow/core/widgets/artwork.dart';
import 'package:tuneflow/core/widgets/state_views.dart';
import 'package:tuneflow/features/catalog/domain/entities/song.dart';
import 'package:tuneflow/features/downloads/presentation/providers/download_providers.dart';
import 'package:tuneflow/features/player/presentation/providers/player_providers.dart';

/// Downloads list (docs section 28).
///
/// The flow is intentionally explicit about the server contract: "Save" reserves the download
/// (`POST /downloads`), then the completion is reported (`POST /downloads/{id}/complete`) - the step
/// that actually increments the track's download count. A real client would write the bytes to disk
/// between the two; this build keeps the record and the licence so the UI can express the state
/// truthfully without pretending to manage files it does not own.
class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<PagedResponse<DownloadRecord>> downloads = ref.watch(downloadsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Downloads')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(downloadsProvider);
          await ref.read(downloadsProvider.future);
        },
        child: downloads.when(
          loading: () => const SkeletonList(itemCount: 5),
          error: (Object error, StackTrace stackTrace) => ErrorView(
            error: error,
            onRetry: () => ref.invalidate(downloadsProvider),
          ),
          data: (PagedResponse<DownloadRecord> page) {
            if (page.items.isEmpty) {
              return const EmptyView(
                title: 'No downloads yet',
                message: 'Save a track and it will be listed here.',
                icon: Icons.download_outlined,
              );
            }
            return ListView.separated(
              itemCount: page.items.length,
              separatorBuilder: (BuildContext context, int index) => const Divider(height: 1),
              itemBuilder: (BuildContext context, int index) =>
                  _DownloadRow(record: page.items[index]),
            );
          },
        ),
      ),
    );
  }
}

class _DownloadRow extends ConsumerStatefulWidget {
  const _DownloadRow({required this.record});

  final DownloadRecord record;

  @override
  ConsumerState<_DownloadRow> createState() => _DownloadRowState();
}

class _DownloadRowState extends ConsumerState<_DownloadRow> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final DownloadRecord record = widget.record;

    return ListTile(
      onTap: () => ref.read(playerControllerProvider.notifier).playSong(record.song),
      leading: Artwork(
        imageUrl: record.song.artworkUrl,
        seed: record.song.artworkSeed,
        size: 48,
      ),
      title: Text(record.song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(record.song.artistName, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Row(
            children: <Widget>[
              StatusPill(
                label: record.status,
                color: record.isCompleted ? AppColors.success : AppColors.warning,
              ),
              const SizedBox(width: 8),
              if (record.sizeBytes != null)
                Text(
                  Formatters.bytes(record.sizeBytes),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.textSecondaryDark,
                      ),
                ),
              if (record.bitrateKbps != null) ...<Widget>[
                const SizedBox(width: 8),
                Text(
                  '${record.bitrateKbps} kbps',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.textSecondaryDark,
                      ),
                ),
              ],
            ],
          ),
        ],
      ),
      trailing: _busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : PopupMenuButton<String>(
              onSelected: (String action) => _handle(action, record),
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                if (record.isPending)
                  const PopupMenuItem<String>(
                    value: 'complete',
                    child: Text('Mark as downloaded'),
                  ),
                const PopupMenuItem<String>(
                  value: 'remove',
                  child: Text('Remove download'),
                ),
              ],
            ),
    );
  }

  Future<void> _handle(String action, DownloadRecord record) async {
    setState(() => _busy = true);
    try {
      final DownloadActions actions = ref.read(downloadActionsProvider);
      if (action == 'complete') {
        await actions.complete(record.id);
      } else {
        await actions.remove(record.id);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              action == 'complete'
                  ? 'Marked ${record.song.title} as downloaded'
                  : 'Removed ${record.song.title}',
            ),
          ),
        );
      }
    } on AppException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }
}

/// Entry point used from a track's context menu: reserve the download, then report completion.
///
/// Kept here rather than inside a tile so the two-step protocol is implemented exactly once and any
/// future screen can reuse it.
Future<void> downloadSong(
  BuildContext context,
  WidgetRef ref, {
  required Song song,
  int? bitrateKbps,
}) async {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  try {
    final DownloadActions actions = ref.read(downloadActionsProvider);
    final DownloadRecord record = await actions.start(song, bitrateKbps: bitrateKbps);
    await actions.complete(record.id);
    messenger.showSnackBar(SnackBar(content: Text('Saved ${song.title} for offline listening')));
  } on AppException catch (error) {
    messenger.showSnackBar(SnackBar(content: Text(error.message)));
  }
}
