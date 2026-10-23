import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tuneflow/core/error/app_exception.dart';
import 'package:tuneflow/core/network/paged_response.dart';
import 'package:tuneflow/core/theme/app_colors.dart';
import 'package:tuneflow/core/utils/formatters.dart';
import 'package:tuneflow/core/widgets/artwork.dart';
import 'package:tuneflow/core/widgets/state_views.dart';
import 'package:tuneflow/features/catalog/domain/entities/album.dart';
import 'package:tuneflow/features/catalog/domain/entities/artist.dart';
import 'package:tuneflow/features/catalog/domain/entities/song.dart';
import 'package:tuneflow/features/catalog/presentation/providers/catalog_providers.dart';
import 'package:tuneflow/features/catalog/presentation/widgets/song_tile.dart';

/// Artist detail: header with follow, popular tracks and albums.
class ArtistDetailScreen extends ConsumerWidget {
  const ArtistDetailScreen({super.key, required this.artistId});

  final String artistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Artist> artist = ref.watch(artistProvider(artistId));
    final AsyncValue<PagedResponse<Song>> songs = ref.watch(artistSongsProvider(artistId));
    final AsyncValue<PagedResponse<Album>> albums = ref.watch(artistAlbumsProvider(artistId));

    return Scaffold(
      body: artist.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stackTrace) => Scaffold(
          appBar: AppBar(),
          body: ErrorView(error: error, onRetry: () => ref.invalidate(artistProvider(artistId))),
        ),
        data: (Artist data) => CustomScrollView(
          slivers: <Widget>[
            SliverAppBar(
              pinned: true,
              expandedHeight: 300,
              flexibleSpace: FlexibleSpaceBar(
                background: _ArtistHeader(artist: data),
              ),
            ),
            SliverToBoxAdapter(
              child: _ArtistStatsRow(artist: data),
            ),
            SliverToBoxAdapter(
              child: _FollowButton(artist: data),
            ),
            if (albums.valueOrNull?.items.isNotEmpty ?? false) ...<Widget>[
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
                  child: _SectionTitle('Albums'),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 176,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: albums.valueOrNull!.items.length,
                    separatorBuilder: (BuildContext context, int index) =>
                        const SizedBox(width: 14),
                    itemBuilder: (BuildContext context, int index) {
                      final Album album = albums.valueOrNull!.items[index];
                      return _AlbumCard(album: album);
                    },
                  ),
                ),
              ),
            ],
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 24, 16, 4),
                child: _SectionTitle('Songs'),
              ),
            ),
            songs.when(
              loading: () => const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              error: (Object error, StackTrace stackTrace) => SliverToBoxAdapter(
                child: ErrorView(
                  error: error,
                  onRetry: () => ref.invalidate(artistSongsProvider(artistId)),
                ),
              ),
              data: (PagedResponse<Song> page) {
                if (page.items.isEmpty) {
                  return const SliverToBoxAdapter(
                    child: EmptyView(title: 'No songs published yet'),
                  );
                }
                return SliverList.builder(
                  itemCount: page.items.length,
                  itemBuilder: (BuildContext context, int index) => SongTile(
                    song: page.items[index],
                    queue: page.items,
                  ),
                );
              },
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 90)),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(text, style: Theme.of(context).textTheme.titleLarge);
}

class _ArtistHeader extends StatelessWidget {
  const _ArtistHeader({required this.artist});

  final Artist artist;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.heroGradient),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const SizedBox(height: 32),
            Artwork(
              imageUrl: artist.profileImageUrl,
              seed: artist.id,
              size: 140,
              isCircle: true,
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Flexible(
                  child: Text(
                    artist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white),
                  ),
                ),
                if (artist.verified) ...<Widget>[
                  const SizedBox(width: 8),
                  const Icon(Icons.verified, size: 18, color: AppColors.accent),
                ],
              ],
            ),
            if (artist.country != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(artist.country!, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }
}

class _ArtistStatsRow extends StatelessWidget {
  const _ArtistStatsRow({required this.artist});

  final Artist artist;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: <Widget>[
          _Stat(label: 'Followers', value: Formatters.compactCount(artist.followerCount)),
          _Stat(label: 'Songs', value: '${artist.songCount}'),
          _Stat(label: 'Albums', value: '${artist.albumCount}'),
        ],
      ),
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

/// Follow/unfollow with an optimistic flip and rollback, matching the like pattern.
class _FollowButton extends ConsumerStatefulWidget {
  const _FollowButton({required this.artist});

  final Artist artist;

  @override
  ConsumerState<_FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends ConsumerState<_FollowButton> {
  bool? _override;
  bool _busy = false;

  bool get _following => _override ?? widget.artist.isFollowed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: SizedBox(
        width: double.infinity,
        child: _following
            ? OutlinedButton.icon(
                onPressed: _busy ? null : _toggle,
                icon: const Icon(Icons.check),
                label: const Text('Following'),
              )
            : FilledButton.icon(
                onPressed: _busy ? null : _toggle,
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Follow'),
              ),
      ),
    );
  }

  Future<void> _toggle() async {
    final bool target = !_following;
    setState(() {
      _override = target;
      _busy = true;
    });

    try {
      final CatalogActions actions = ref.read(catalogActionsProvider);
      if (target) {
        await actions.followArtist(widget.artist.id);
      } else {
        await actions.unfollowArtist(widget.artist.id);
      }
      ref.invalidate(artistProvider(widget.artist.id));
      // The home feed has a "followed artists" rail, so it must be refreshed too.
      ref.invalidate(homeFeedProvider);
    } on AppException catch (error) {
      setState(() => _override = !target);
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

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({required this.album});

  final Album album;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Artwork(
            imageUrl: album.coverImageUrl,
            seed: album.id,
            size: 140,
            borderRadius: 10,
          ),
          const SizedBox(height: 8),
          Text(
            album.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text(
            Formatters.releaseDate(album.releaseDate),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondaryDark,
                ),
          ),
        ],
      ),
    );
  }
}
