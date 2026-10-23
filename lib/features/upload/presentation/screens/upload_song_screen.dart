import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tuneflow/app/router/route_paths.dart';
import 'package:tuneflow/core/error/app_exception.dart';
import 'package:tuneflow/core/theme/app_colors.dart';
import 'package:tuneflow/core/utils/validators.dart';
import 'package:tuneflow/core/widgets/artwork.dart';
import 'package:tuneflow/core/widgets/state_views.dart';
import 'package:tuneflow/features/auth/domain/entities/user.dart';
import 'package:tuneflow/features/auth/presentation/providers/auth_providers.dart';
import 'package:tuneflow/features/catalog/domain/entities/album.dart';
import 'package:tuneflow/features/catalog/domain/entities/genre.dart';
import 'package:tuneflow/features/catalog/domain/entities/song.dart';
import 'package:tuneflow/features/catalog/presentation/providers/catalog_providers.dart';
import 'package:tuneflow/features/upload/domain/entities/upload_state.dart';
import 'package:tuneflow/features/upload/presentation/providers/upload_providers.dart';

/// Artist publishing screen (docs section 13).
///
/// The flow is deliberately three visible steps - audio, artwork, details - because each one can be
/// retried independently: the audio lands in storage first and its `objectKey` is only spent when the
/// metadata call succeeds. A failure at any point therefore costs a retry, never a re-upload.
///
/// Reachable only from the profile menu of an artist account; a listener who deep-links here gets an
/// explanation instead of a form that the API would reject with 403.
class UploadSongScreen extends ConsumerStatefulWidget {
  const UploadSongScreen({super.key});

  @override
  ConsumerState<UploadSongScreen> createState() => _UploadSongScreenState();
}

class _UploadSongScreenState extends ConsumerState<UploadSongScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _duration = TextEditingController();
  final TextEditingController _trackNumber = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _duration.dispose();
    _trackNumber.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    await ref.read(uploadControllerProvider.notifier).submit();
  }

  @override
  Widget build(BuildContext context) {
    final User? user = ref.watch(currentUserProvider);

    // The publish call would fail with 403 for a listener; saying so up front is the difference
    // between a dead button and an explanation.
    if (user != null && !user.isArtist) {
      return Scaffold(
        appBar: AppBar(title: const Text('Upload a song')),
        body: const EmptyView(
          title: 'Artist account needed',
          message: 'Only artist accounts can publish music. Create an artist account from the sign-up '
              'screen - or sign in with the demo artist (artist@tuneflow.dev).',
          icon: Icons.mic_none_outlined,
        ),
      );
    }

    final UploadState state = ref.watch(uploadControllerProvider);
    final UploadController controller = ref.read(uploadControllerProvider.notifier);

    // One-shot reaction to a successful publish: announce it and leave the screen, so the artist
    // lands back where they started instead of on a form that no longer has anything in it.
    ref.listen<UploadState>(uploadControllerProvider, (UploadState? previous, UploadState next) {
      final int? detected = next.audio?.durationSeconds;
      // `probe` reports 0 when FFmpeg/FFprobe is not installed, which is the norm on a dev machine.
      // Writing that 0 into the field would look like a measured value and fail validation with a
      // message the artist cannot act on; leaving it empty keeps the "enter the length" hint honest.
      if (detected != null && detected > 0 && detected != previous?.audio?.durationSeconds) {
        _duration.text = detected.toString();
      }
      final Song? created = next.createdSong;
      if (created != null && previous?.createdSong == null) {
        final String? artistId = created.artist?.id;
        // Capture the messenger and router *before* popping: this screen is disposed by the pop,
        // and the snackbar's action fires later. Touching `context` at that point hits a
        // deactivated element and crashes the whole app (GoRouter.of throws there too, while
        // maybeOf is the defensive form for harnesses without a router in the tree).
        final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
        final GoRouter? router = GoRouter.maybeOf(context);
        messenger.showSnackBar(
          SnackBar(
            content: Text('“${created.title}” is now live'),
            action: artistId == null || router == null
                ? null
                : SnackBarAction(
                    label: 'View artist',
                    onPressed: () => router.push(RoutePaths.artist(artistId)),
                  ),
          ),
        );
        Navigator.of(context).pop();
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Upload a song')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: <Widget>[
            _MediaStep(
              title: 'Audio file',
              subtitle: 'MP3, M4A, AAC, WAV, FLAC or OGG - up to 100 MB',
              icon: Icons.audiotrack,
              fileName: state.audioFile?.name,
              detail: state.audioFile == null
                  ? null
                  : state.audio != null
                      ? '${state.audioFile!.readableSize} · uploaded'
                      : state.audioFile!.readableSize,
              progress: state.audioProgress,
              uploading: state.uploadingAudio,
              uploaded: state.audio != null,
              onPick: controller.pickAudio,
              onClear: controller.removeAudio,
            ),
            const SizedBox(height: 12),
            _MediaStep(
              title: 'Cover art',
              subtitle: 'JPG, PNG or WEBP - up to 10 MB. Optional; the album art is used otherwise.',
              icon: Icons.image_outlined,
              fileName: state.coverFile?.name,
              detail: state.coverFile?.readableSize,
              progress: state.coverProgress,
              uploading: state.uploadingCover,
              uploaded: state.cover != null,
              previewUrl: state.cover?.previewUrl,
              previewSeed: state.cover?.objectKey,
              onPick: controller.pickCover,
              onClear: controller.removeCover,
            ),
            const SizedBox(height: 24),
            const _SectionLabel('Details'),
            TextFormField(
              controller: _title,
              textInputAction: TextInputAction.next,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'e.g. Neon Skyline',
              ),
              validator: (String? value) => Validators.required(value, field: 'Title'),
              onChanged: controller.setTitle,
            ),
            const SizedBox(height: 8),
            _AlbumField(
              selectedAlbumId: state.albumId,
              onChanged: controller.setAlbum,
            ),
            const SizedBox(height: 20),
            const _SectionLabel('Genres'),
            _GenreChips(
              selected: state.genreSlugs,
              onToggle: controller.toggleGenre,
            ),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: TextFormField(
                    controller: _duration,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Duration (seconds)',
                      helperText: 'Filled in from your file',
                    ),
                    validator: (String? value) {
                      final int seconds = int.tryParse((value ?? '').trim()) ?? 0;
                      return seconds <= 0 ? 'Duration is required' : null;
                    },
                    onChanged: (String value) {
                      final int? seconds = int.tryParse(value.trim());
                      if (seconds != null) {
                        controller.setDuration(seconds);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _trackNumber,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Track number',
                      helperText: 'Optional',
                    ),
                    onChanged: (String value) {
                      final int? number = int.tryParse(value.trim());
                      if (number != null) {
                        controller.setTrackNumber(number);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined, color: AppColors.textSecondaryDark),
              title: const Text('Release date'),
              subtitle: Text(
                state.releaseDate == null
                    ? 'Today'
                    : '${state.releaseDate!.day}/${state.releaseDate!.month}/${state.releaseDate!.year}',
              ),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () => _pickReleaseDate(state, controller),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: state.explicit,
              onChanged: controller.setExplicit,
              title: const Text('Explicit content'),
              subtitle: const Text('Marks the track with an E badge'),
            ),
            if (state.errorMessage != null) ...<Widget>[
              const SizedBox(height: 8),
              ErrorBanner(
                message: state.errorMessage!,
                onDismiss: controller.dismissError,
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: state.canSubmit ? _submit : null,
              icon: state.submitting
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_upload_outlined),
              label: Text(state.submitting ? 'Publishing…' : 'Publish song'),
            ),
            const SizedBox(height: 8),
            Text(
              // The button explains its own disabled state instead of staying a mystery.
              state.blockingReason ?? 'Ready to publish.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondaryDark,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickReleaseDate(UploadState state, UploadController controller) async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: state.releaseDate ?? now,
      firstDate: DateTime(1900),
      // The API rejects a future release date (`@PastOrPresent`), so it is not offered.
      lastDate: now,
    );
    if (picked != null) {
      controller.setReleaseDate(picked);
    }
  }
}

/// One file slot: choose, watch it upload, or replace/remove it.
class _MediaStep extends StatelessWidget {
  const _MediaStep({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.fileName,
    required this.detail,
    required this.progress,
    required this.uploading,
    required this.uploaded,
    required this.onPick,
    required this.onClear,
    this.previewUrl,
    this.previewSeed,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String? fileName;
  final String? detail;
  final double? progress;
  final bool uploading;
  final bool uploaded;
  final VoidCallback onPick;
  final VoidCallback onClear;
  final String? previewUrl;
  final String? previewSeed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (previewUrl != null && previewSeed != null)
                Artwork(imageUrl: previewUrl, seed: previewSeed!, size: 44)
              else
                Icon(icon, color: AppColors.textSecondaryDark),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      fileName ?? subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondaryDark,
                          ),
                    ),
                    if (fileName != null && detail != null) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        detail!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: uploaded ? AppColors.accent : AppColors.textSecondaryDark,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
              if (fileName != null && !uploading)
                IconButton(
                  tooltip: 'Remove',
                  onPressed: onClear,
                  icon: const Icon(Icons.close, size: 20),
                ),
            ],
          ),
          if (uploading) ...<Widget>[
            const SizedBox(height: 10),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 4),
            Text(
              'Uploading${progress == null ? '' : ' - ${(progress! * 100).round()}%'}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondaryDark,
                  ),
            ),
          ] else ...<Widget>[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onPick,
                icon: Icon(fileName == null ? Icons.folder_open : Icons.swap_horiz, size: 18),
                label: Text(fileName == null ? 'Choose file' : 'Replace file'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AlbumField extends ConsumerWidget {
  const _AlbumField({required this.selectedAlbumId, required this.onChanged});

  final String? selectedAlbumId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Album>> albums = ref.watch(myAlbumsProvider);

    return albums.maybeWhen(
      data: (List<Album> items) => DropdownButtonFormField<String?>(
        initialValue: selectedAlbumId,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Album',
          helperText: 'Optional - singles stay unattached',
        ),
        items: <DropdownMenuItem<String?>>[
          const DropdownMenuItem<String?>(child: Text('None (single)')),
          ...items.map(
            (Album album) => DropdownMenuItem<String?>(
              value: album.id,
              child: Text(album.title, overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
        onChanged: onChanged,
      ),
      // While loading, or when the artist has no albums, the form shows the field without options
      // rather than blocking the whole screen on a secondary choice.
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _GenreChips extends ConsumerWidget {
  const _GenreChips({required this.selected, required this.onToggle});

  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Genre>> genres = ref.watch(genresProvider);

    return genres.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(),
      ),
      error: (Object error, StackTrace stackTrace) => Text(
        error is AppException ? error.message : 'Could not load genres.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      data: (List<Genre> items) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: items
            .map(
              (Genre genre) => FilterChip(
                label: Text(genre.name),
                selected: selected.contains(genre.slug),
                onSelected: (_) => onToggle(genre.slug),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}
