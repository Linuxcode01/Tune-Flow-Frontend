import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tuneflow/app/router/route_paths.dart';
import 'package:tuneflow/core/constants/app_constants.dart';
import 'package:tuneflow/core/theme/app_colors.dart';
import 'package:tuneflow/core/widgets/artwork.dart';
import 'package:tuneflow/core/widgets/state_views.dart';
import 'package:tuneflow/features/catalog/domain/entities/genre.dart';
import 'package:tuneflow/features/catalog/domain/entities/search_results.dart';
import 'package:tuneflow/features/catalog/presentation/providers/catalog_providers.dart';
import 'package:tuneflow/features/catalog/presentation/widgets/song_tile.dart';

/// Search tab: browse-by-genre, typeahead suggestions and full results (docs section 23).
///
/// Three modes in one screen, which is how a search tab should behave: an empty query shows genres to
/// explore, typing shows cheap suggestions, submitting shows grouped results.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Debounced so typing "skyline" fires one request, not seven (docs section 23).
  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(AppConstants.searchDebounce, () {
      if (mounted) {
        setState(() => _query = value.trim());
      }
    });
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    setState(() => _query = '');
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                textInputAction: TextInputAction.search,
                onChanged: _onChanged,
                onSubmitted: (String value) => setState(() => _query = value.trim()),
                decoration: InputDecoration(
                  hintText: 'Songs, artists, albums',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          onPressed: _clear,
                          icon: const Icon(Icons.close),
                          tooltip: 'Clear',
                        ),
                ),
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_query.isEmpty) {
      return const _GenreBrowser();
    }
    if (_query.length < 2) {
      return const EmptyView(
        title: 'Keep typing',
        message: 'Search needs at least two characters.',
        icon: Icons.keyboard_outlined,
      );
    }
    return _SearchResultsView(query: _query);
  }
}

/// Genre grid shown before the user types.
class _GenreBrowser extends ConsumerWidget {
  const _GenreBrowser();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Genre>> genres = ref.watch(genresProvider);

    return genres.when(
      loading: () => const SkeletonList(itemCount: 6, itemHeight: 48),
      error: (Object error, StackTrace stackTrace) => ErrorView(
        error: error,
        onRetry: () => ref.invalidate(genresProvider),
      ),
      data: (List<Genre> data) {
        if (data.isEmpty) {
          return const EmptyView(title: 'No genres yet');
        }
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 2.1,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: data.length,
          itemBuilder: (BuildContext context, int index) {
            final Genre genre = data[index];
            final Color tint = AppColors.placeholderFor(genre.slug, dark: true);
            return InkWell(
              onTap: () => context.push(RoutePaths.genre(genre.slug)),
              borderRadius: BorderRadius.circular(AppConstants.cardRadius),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: BorderRadius.circular(AppConstants.cardRadius),
                ),
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Text(
                    genre.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Suggestions while typing, then grouped results once submitted (or after the debounce).
class _SearchResultsView extends ConsumerWidget {
  const _SearchResultsView({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<SearchResults> results =
        ref.watch(_searchResultsProvider(query));

    return results.when(
      loading: () => const SkeletonList(itemCount: 6),
      error: (Object error, StackTrace stackTrace) => ErrorView(
        error: error,
        onRetry: () => ref.invalidate(_searchResultsProvider(query)),
      ),
      data: (SearchResults data) {
        if (data.isEmpty) {
          return EmptyView(
            title: 'No results for "$query"',
            message: 'Check the spelling, or try a different word.',
            icon: Icons.search_off,
            actionLabel: 'Clear search',
            onAction: () => ref.invalidate(_searchResultsProvider(query)),
          );
        }

        return ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: <Widget>[
            if (data.fuzzyMatched)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  'Showing close matches for "$query"',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondaryDark,
                      ),
                ),
              ),
            if (data.artists.isNotEmpty) ...<Widget>[
              const _SectionLabel(label: 'Artists'),
              ...data.artists.map(
                (artist) => ListTile(
                  onTap: () => context.push(RoutePaths.artist(artist.id)),
                  leading: Artwork(
                    imageUrl: artist.profileImageUrl,
                    seed: artist.id,
                    size: 48,
                    isCircle: true,
                  ),
                  title: Text(artist.name),
                  subtitle: Text('${artist.songCount} songs'),
                  trailing: const Icon(Icons.chevron_right),
                ),
              ),
            ],
            if (data.albums.isNotEmpty) ...<Widget>[
              const _SectionLabel(label: 'Albums'),
              ...data.albums.map(
                (album) => ListTile(
                  onTap: () => context.push(RoutePaths.album(album.id)),
                  leading: Artwork(
                    imageUrl: album.coverImageUrl,
                    seed: album.id,
                    size: 48,
                  ),
                  title: Text(album.title),
                  subtitle: Text(album.artist?.name ?? ''),
                  trailing: const Icon(Icons.chevron_right),
                ),
              ),
            ],
            if (data.playlists.isNotEmpty) ...<Widget>[
              const _SectionLabel(label: 'Playlists'),
              ...data.playlists.map(
                (playlist) => ListTile(
                  onTap: () => context.push(RoutePaths.playlist(playlist.id)),
                  leading: Artwork(
                    imageUrl: playlist.coverImageUrl,
                    seed: playlist.id,
                    size: 48,
                  ),
                  title: Text(playlist.name),
                  subtitle: Text('${playlist.songCount} songs'),
                  trailing: const Icon(Icons.chevron_right),
                ),
              ),
            ],
            if (data.songs.isNotEmpty) ...<Widget>[
              const _SectionLabel(label: 'Songs'),
              ...data.songs.map(
                (song) => SongTile(song: song, queue: data.songs),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.textSecondaryDark,
              letterSpacing: 1,
            ),
      ),
    );
  }
}

/// Per-query search provider: auto-dispose keeps result sets from accumulating as the user types.
final AutoDisposeFutureProviderFamily<SearchResults, String> _searchResultsProvider =
    FutureProvider.autoDispose.family<SearchResults, String>(
  (Ref ref, String query) => ref.watch(catalogRepositoryProvider).search(query),
  name: 'searchResults',
);
