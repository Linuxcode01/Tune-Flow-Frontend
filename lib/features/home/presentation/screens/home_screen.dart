import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tuneflow/app/router/route_paths.dart';
import 'package:tuneflow/core/theme/app_colors.dart';
import 'package:tuneflow/core/widgets/artwork.dart';
import 'package:tuneflow/core/widgets/state_views.dart';
import 'package:tuneflow/features/catalog/domain/entities/artist.dart';
import 'package:tuneflow/features/catalog/domain/entities/home_feed.dart';
import 'package:tuneflow/features/catalog/presentation/providers/catalog_providers.dart';
import 'package:tuneflow/features/catalog/presentation/widgets/song_rail.dart';
import 'package:tuneflow/features/profile/presentation/providers/profile_providers.dart';

/// Home tab: the assembled, personalised feed (docs section 18).
///
/// The screen renders whatever sections the API returns rather than hard-coding rails, so a new
/// server-side section (say "because you listened to ...") shows up without a client release. Only
/// the greeting is client-side, because it needs the user's name.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<HomeFeed> feed = ref.watch(homeFeedProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(homeFeedProvider);
            await ref.read(homeFeedProvider.future);
          },
          child: feed.when(
            loading: () => const SkeletonList(itemCount: 5),
            error: (Object error, StackTrace stackTrace) => ListView(
              // A ListView (not a bare widget) so pull-to-refresh works even when the feed failed.
              children: <Widget>[
                SizedBox(height: MediaQuery.of(context).size.height * 0.25),
                ErrorView(
                  error: error,
                  onRetry: () => ref.invalidate(homeFeedProvider),
                ),
              ],
            ),
            data: (HomeFeed data) {
              if (data.isEmpty) {
                return ListView(
                  children: <Widget>[
                    SizedBox(height: MediaQuery.of(context).size.height * 0.25),
                    const EmptyView(
                      title: 'Nothing here yet',
                      message: 'Once music is published, your feed will fill up.',
                      icon: Icons.library_music_outlined,
                    ),
                  ],
                );
              }

              return CustomScrollView(
                slivers: <Widget>[
                  const SliverToBoxAdapter(child: _GreetingHeader()),
                  if (!data.personalised)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
                        child: _AnonymousNotice(),
                      ),
                    ),
                  SliverList.builder(
                    itemCount: data.sections.length,
                    itemBuilder: (BuildContext context, int index) {
                      final HomeSection section = data.sections[index];
                      if (section.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return section.isArtistSection
                          ? ArtistRail(section: section)
                          : SongRail(
                              songs: section.songs,
                              title: section.title,
                              subtitle: section.subtitle,
                              trailing: section.key == 'recently-played'
                                  ? TextButton(
                                      onPressed: () => context.push(RoutePaths.recentlyPlayed),
                                      child: const Text('See all'),
                                    )
                                  : null,
                            );
                    },
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 32)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _GreetingHeader extends ConsumerWidget {
  const _GreetingHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? name = ref.watch(currentUserNameProvider);
    final int hour = DateTime.now().hour;
    final String greeting = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            name == null ? greeting : '$greeting, $name',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 2),
          Text(
            'Here is what suits your mood today',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondaryDark,
                ),
          ),
        ],
      ),
    );
  }
}

/// Shown when the API served the anonymous fallback, so the user understands why the feed looks
/// generic instead of assuming the app is broken.
class _AnonymousNotice extends StatelessWidget {
  const _AnonymousNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.auto_awesome_outlined, size: 18, color: AppColors.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Like a few songs and this feed becomes personal.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// Circular artist cards for the `popular-artists` and `followed-artists` sections.
class ArtistRail extends StatelessWidget {
  const ArtistRail({super.key, required this.section});

  final HomeSection section;

  @override
  Widget build(BuildContext context) {
    final List<Artist> artists = section.artists;
    if (artists.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(section.title, style: Theme.of(context).textTheme.titleLarge),
              if (section.subtitle != null)
                Text(
                  section.subtitle!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondaryDark,
                      ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: artists.length,
            separatorBuilder: (BuildContext context, int index) => const SizedBox(width: 16),
            itemBuilder: (BuildContext context, int index) => ArtistAvatar(
              artist: artists[index],
              size: 104,
            ),
          ),
        ),
      ],
    );
  }
}

/// Circular artist avatar with an optional verified badge.
class ArtistAvatar extends StatelessWidget {
  const ArtistAvatar({super.key, required this.artist, this.size = 96, this.onTap});

  final Artist artist;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size + 12,
      child: InkWell(
        onTap: onTap ?? () => context.push(RoutePaths.artist(artist.id)),
        borderRadius: BorderRadius.circular(size),
        child: Column(
          children: <Widget>[
            Stack(
              children: <Widget>[
                Artwork(
                  imageUrl: artist.profileImageUrl,
                  seed: artist.id,
                  size: size,
                  isCircle: true,
                ),
                if (artist.verified)
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: AppColors.accent,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check, size: 12, color: Colors.black),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              artist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
