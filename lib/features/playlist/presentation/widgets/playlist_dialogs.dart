import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tuneflow/core/error/app_exception.dart';
import 'package:tuneflow/core/utils/validators.dart';
import 'package:tuneflow/features/catalog/domain/entities/search_results.dart';
import 'package:tuneflow/features/playlist/presentation/providers/playlist_providers.dart';

/// Create/rename dialog shared by the library and the playlist detail screen.
///
/// Both flows need the same validation and the same error handling, so they share one implementation
/// instead of two dialogs that drift apart.
Future<PlaylistSummary?> showCreatePlaylistDialog(
  BuildContext context,
  WidgetRef ref, {
  PlaylistSummary? existing,
}) {
  return showDialog<PlaylistSummary>(
    context: context,
    builder: (BuildContext dialogContext) => _PlaylistFormDialog(existing: existing),
  );
}

/// The dialog owns its text controllers and disposes them in [State.dispose].
///
/// Disposing when the *route* pops (i.e. when `showDialog`'s future completes) is not safe: the
/// dialog's widgets - including the autofocused `TextFormField` - stay in the tree for the whole
/// exit animation, and the framework keeps delivering focus/IME events to them. Disposing the
/// controllers at pop time therefore threw "A TextEditingController was used after being disposed"
/// and cascaded into `_dependents.isEmpty` assertions that red-screened the app right after a
/// playlist was created. `State.dispose` runs only once the element is fully deactivated, which is
/// exactly the guarantee the controllers need.
class _PlaylistFormDialog extends ConsumerStatefulWidget {
  const _PlaylistFormDialog({this.existing});

  final PlaylistSummary? existing;

  @override
  ConsumerState<_PlaylistFormDialog> createState() => _PlaylistFormDialogState();
}

class _PlaylistFormDialogState extends ConsumerState<_PlaylistFormDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _description =
      TextEditingController(text: widget.existing?.description ?? '');
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late bool _isPublic = widget.existing?.publicPlaylist ?? false;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final PlaylistActions actions = ref.read(playlistActionsProvider);
      final PlaylistSummary playlist = widget.existing == null
          ? await actions.create(
              name: _name.text.trim(),
              description: _description.text.trim(),
              isPublic: _isPublic,
            )
          : await actions
              .update(
                widget.existing!.id,
                name: _name.text.trim(),
                description: _description.text.trim(),
                isPublic: _isPublic,
              )
              .then((_) => widget.existing!);
      if (mounted) {
        Navigator.of(context).pop(playlist);
      }
    } on AppException catch (exception) {
      if (mounted) {
        setState(() {
          _error = exception.message;
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'New playlist' : 'Edit playlist'),
      // The keyboard can take half the screen on a phone; scrolling the content keeps every field
      // reachable instead of overflowing the dialog's Column.
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (_error != null) ...<Widget>[
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
                ),
                const SizedBox(height: 8),
              ],
              TextFormField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: Validators.playlistName,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _description,
                decoration: const InputDecoration(labelText: 'Description (optional)'),
                maxLines: 2,
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _isPublic,
                onChanged: (bool value) => setState(() => _isPublic = value),
                title: const Text('Public'),
                subtitle: const Text('Anyone can find and play this playlist'),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(widget.existing == null ? 'Create' : 'Save'),
        ),
      ],
    );
  }
}

/// Bottom sheet that sends one or more songs to a playlist the user picks.
///
/// Shared by every "add to playlist" entry point: the song row overflow menu (one track), the album
/// header (a whole album) and the playlist picker sheet. Resolving the destination first and adding
/// second is the order the user thinks in, and it means the create-and-add path - "New playlist" -
/// needs no second screen.
Future<void> showAddToPlaylistSheet(
  BuildContext context,
  WidgetRef ref, {
  required List<String> songIds,
}) async {
  if (songIds.isEmpty) {
    return;
  }

  final List<PlaylistSummary> playlists = await ref
      .read(playlistsProvider.future)
      .then((paged) => paged.items)
      .catchError((Object _) => <PlaylistSummary>[]);

  if (!context.mounted) {
    return;
  }

  final String label = songIds.length == 1 ? 'song' : '${songIds.length} songs';

  /// Adds to [playlist] and closes the sheet, reporting the outcome in the parent context.
  Future<void> addTo(BuildContext sheetContext, PlaylistSummary playlist) async {
    final PlaylistAddResult result =
        await ref.read(playlistActionsProvider).addSongs(playlist.id, songIds);
    if (!sheetContext.mounted) {
      return;
    }
    Navigator.of(sheetContext).pop();
    ScaffoldMessenger.of(sheetContext)
        .showSnackBar(SnackBar(content: Text(result.describe(playlist.name))));
  }

  await showModalBottomSheet<void>(
    context: context,
    builder: (BuildContext sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Add $label to',
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('New playlist'),
            onTap: () async {
              final PlaylistSummary? created = await showCreatePlaylistDialog(sheetContext, ref);
              if (created != null && sheetContext.mounted) {
                await addTo(sheetContext, created);
              }
            },
          ),
          const Divider(height: 1),
          if (playlists.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('You have no playlists yet.'),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: playlists.length,
                itemBuilder: (BuildContext context, int index) {
                  final PlaylistSummary playlist = playlists[index];
                  return ListTile(
                    title: Text(playlist.name),
                    subtitle: Text(
                      playlist.songCount == 1 ? '1 song' : '${playlist.songCount} songs',
                    ),
                    onTap: () => addTo(sheetContext, playlist),
                  );
                },
              ),
            ),
        ],
      ),
    ),
  );
}
