import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tuneflow/core/theme/app_colors.dart';
import 'package:tuneflow/core/utils/formatters.dart';
import 'package:tuneflow/core/widgets/artwork.dart';
import 'package:tuneflow/core/widgets/state_views.dart';
import 'package:tuneflow/features/catalog/domain/entities/song.dart';
import 'package:tuneflow/features/catalog/presentation/providers/catalog_providers.dart';
import 'package:tuneflow/features/playlist/presentation/providers/playlist_providers.dart';

/// Search-and-multi-select sheet for filling a playlist (docs section 25).
///
/// This is the missing half of playlist editing: the API has always supported
/// `POST /playlists/{id}/songs`, but the only client that called it was the album screen, for one
/// track at a time. Picking several songs at once is the flow a user actually has in mind when they
/// build a playlist, so the sheet takes a selection rather than a single id.
///
/// The results list is the catalogue search endpoint, which also covers the empty-query case with
/// trending songs - so the sheet is useful before the user types anything.
Future<void> showSongPickerSheet(
  BuildContext context,
  WidgetRef ref, {
  required String playlistId,
  required String playlistName,
  Set<String> existingSongIds = const <String>{},
}) async {
  final PlaylistAddResult? result = await showModalBottomSheet<PlaylistAddResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    // A fixed, tall sheet with a pinned header/footer (rather than a draggable one): the search field
    // has to stay put while the results scroll under it, and the "Add" button must not drift off the
    // bottom with the list. The height leaves the keyboard room when the field is focused.
    builder: (BuildContext sheetContext) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * 0.85,
        child: _SongPickerSheet(
          playlistId: playlistId,
          playlistName: playlistName,
          existingSongIds: existingSongIds,
        ),
      ),
    ),
  );

  if (result != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.describe(playlistName))),
    );
  }
}

/// Songs already in the playlist are shown but not selectable, which is friendlier than hiding them
/// (the user can see that the track is accounted for) and cheaper than a pre-flight check per tap.
class _SongPickerSheet extends ConsumerStatefulWidget {
  const _SongPickerSheet({
    required this.playlistId,
    required this.playlistName,
    required this.existingSongIds,
  });

  final String playlistId;
  final String playlistName;
  final Set<String> existingSongIds;

  @override
  ConsumerState<_SongPickerSheet> createState() => _SongPickerSheetState();
}

class _SongPickerSheetState extends ConsumerState<_SongPickerSheet> {
  final TextEditingController _query = TextEditingController();

  /// The query actually sent to the API, updated only after the user pauses typing.
  String _effectiveQuery = '';
  Timer? _debounce;
  final Map<String, Song> _selected = <String, Song>{};
  bool _submitting = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    // 300 ms: long enough to skip intermediate keystrokes, short enough to feel immediate.
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted && value != _effectiveQuery) {
        setState(() => _effectiveQuery = value);
      }
    });
  }

  Future<void> _submit() async {
    if (_selected.isEmpty) {
      return;
    }
    setState(() => _submitting = true);
    try {
      final PlaylistAddResult result = await ref.read(playlistActionsProvider).addSongs(
            widget.playlistId,
            _selected.keys.toList(growable: false),
          );
      if (mounted) {
        Navigator.of(context).pop(result);
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Song>> songs = ref.watch(_songPickerResultsProvider(_effectiveQuery));

    return Column(
      children: <Widget>[
        _Header(query: _query, onChanged: _onQueryChanged),
        const Divider(height: 1),
        Expanded(
          child: songs.when(
            loading: () => const SkeletonList(),
            error: (Object error, StackTrace stackTrace) => ErrorView(
              error: error,
              onRetry: () => ref.invalidate(_songPickerResultsProvider(_effectiveQuery)),
            ),
            data: (List<Song> items) => items.isEmpty
                ? const EmptyView(
                    title: 'Nothing found',
                    message: 'Try a different artist, album or track name.',
                    icon: Icons.search_off,
                  )
                : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (BuildContext context, int index) {
                      final Song song = items[index];
                      return _PickerRow(
                        song: song,
                        alreadyInPlaylist: widget.existingSongIds.contains(song.id),
                        selected: _selected.containsKey(song.id),
                        onToggle: () => setState(() {
                          if (_selected.remove(song.id) == null) {
                            _selected[song.id] = song;
                          }
                        }),
                      );
                    },
                  ),
          ),
        ),
        _Footer(
          playlistName: widget.playlistName,
          selectedCount: _selected.length,
          submitting: _submitting,
          onSubmit: _submitting ? null : _submit,
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.query, required this.onChanged});

  final TextEditingController query;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Add songs', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(
            controller: query,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            autofocus: false,
            decoration: const InputDecoration(
              hintText: 'Search songs, artists or albums',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ],
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.song,
    required this.selected,
    required this.alreadyInPlaylist,
    required this.onToggle,
  });

  final Song song;
  final bool selected;
  final bool alreadyInPlaylist;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      enabled: !alreadyInPlaylist,
      onTap: alreadyInPlaylist ? null : onToggle,
      leading: Artwork(imageUrl: song.artworkUrl, seed: song.id, size: 44),
      title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        alreadyInPlaylist ? 'Already in this playlist' : song.artistName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondaryDark,
            ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            Formatters.durationFromSeconds(song.durationSeconds),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondaryDark,
                ),
          ),
          const SizedBox(width: 8),
          if (alreadyInPlaylist)
            const Icon(Icons.check_circle, color: AppColors.textSecondaryDark)
          else
            Icon(
              selected ? Icons.check_circle : Icons.radio_button_unchecked,
              color: selected ? AppColors.accent : AppColors.textSecondaryDark,
            ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.playlistName,
    required this.selectedCount,
    required this.submitting,
    required this.onSubmit,
  });

  final String playlistName;
  final int selectedCount;
  final bool submitting;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    // Stacked rather than a Row: the app theme makes filled buttons full width
    // (`minimumSize: Size.fromHeight(52)`), so one placed in a Row with unbounded width has an
    // infinite minimum width and fails layout. A full-width call to action also matches the rest of
    // the app.
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              selectedCount == 0
                  ? 'Select songs to add'
                  : selectedCount == 1
                      ? '1 song selected'
                      : '$selectedCount songs selected',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondaryDark,
                  ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: selectedCount == 0 ? null : onSubmit,
              icon: submitting
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.playlist_add_check),
              label: Text(selectedCount == 1 ? 'Add song' : 'Add songs'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Candidate songs for the picker.
///
/// An empty query is not an empty screen: it falls back to trending tracks, because a picker that
/// shows nothing until the user types is a dead end for the common case ("add something from what's
/// popular right now").
final AutoDisposeFutureProviderFamily<List<Song>, String> _songPickerResultsProvider =
    FutureProvider.autoDispose.family<List<Song>, String>(
  (Ref ref, String query) async {
    final String trimmed = query.trim();
    if (trimmed.isEmpty) {
      return ref.watch(catalogRepositoryProvider).getTrendingSongs(limit: 40);
    }
    return ref
        .watch(catalogRepositoryProvider)
        .getSongs(query: trimmed, size: 40)
        .then((paged) => paged.items);
  },
  name: 'songPickerResults',
);
