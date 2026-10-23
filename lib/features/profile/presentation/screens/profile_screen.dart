import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tuneflow/app/router/route_paths.dart';
import 'package:tuneflow/core/network/paged_response.dart';
import 'package:tuneflow/core/theme/app_colors.dart';
import 'package:tuneflow/core/utils/formatters.dart';
import 'package:tuneflow/core/widgets/artwork.dart';
import 'package:tuneflow/core/widgets/state_views.dart';
import 'package:tuneflow/features/auth/domain/entities/user.dart';
import 'package:tuneflow/features/auth/presentation/providers/auth_providers.dart';
import 'package:tuneflow/features/catalog/domain/entities/artist.dart';
import 'package:tuneflow/features/catalog/presentation/providers/catalog_providers.dart';
import 'package:tuneflow/features/library/domain/entities/history_stats.dart';
import 'package:tuneflow/features/library/presentation/providers/library_providers.dart';
import 'package:tuneflow/features/profile/presentation/providers/profile_providers.dart';

/// Profile tab: identity, listening summary, followed artists and the settings entry points.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final User? user = ref.watch(currentUserProvider);
    final AsyncValue<int> unread = ref.watch(unreadNotificationCountProvider);
    final AsyncValue<HistoryStats> stats = ref.watch(historyStatsProvider);
    final AsyncValue<PagedResponse<Artist>> following = ref.watch(followingArtistsProvider);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(authControllerProvider.notifier).refreshUser();
          ref.invalidate(unreadNotificationCountProvider);
          ref.invalidate(historyStatsProvider);
          ref.invalidate(followingArtistsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: <Widget>[
            _ProfileHeader(user: user),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: Row(
                children: <Widget>[
                  _MiniStat(
                    label: 'Plays',
                    value: stats.maybeWhen(
                      data: (HistoryStats value) => '${value.totalPlays}',
                      orElse: () => '—',
                    ),
                  ),
                  _MiniStat(
                    label: 'Hours',
                    value: stats.maybeWhen(
                      data: (HistoryStats value) => value.listeningHours.toStringAsFixed(1),
                      orElse: () => '—',
                    ),
                  ),
                  _MiniStat(
                    label: 'Following',
                    value: following.maybeWhen(
                      data: (PagedResponse<Artist> page) => '${page.totalElements}',
                      orElse: () => '—',
                    ),
                  ),
                ],
              ),
            ),
            if (following.valueOrNull?.items.isNotEmpty ?? false) ...<Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 28, 16, 10),
                child: Text(
                  'Artists you follow',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              SizedBox(
                height: 108,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: following.valueOrNull!.items.length,
                  separatorBuilder: (BuildContext context, int index) =>
                      const SizedBox(width: 14),
                  itemBuilder: (BuildContext context, int index) {
                    final Artist artist = following.valueOrNull!.items[index];
                    return InkWell(
                      onTap: () => context.push(RoutePaths.artist(artist.id)),
                      child: SizedBox(
                        width: 72,
                        child: Column(
                          children: <Widget>[
                            Artwork(
                              imageUrl: artist.profileImageUrl,
                              seed: artist.id,
                              size: 64,
                              isCircle: true,
                            ),
                            const SizedBox(height: 6),
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
                  },
                ),
              ),
            ],
            if (user?.isArtist ?? false) ...<Widget>[
              const Divider(height: 32),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Artist tools',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: AppColors.textSecondaryDark,
                      ),
                ),
              ),
              _MenuTile(
                icon: Icons.cloud_upload_outlined,
                title: 'Upload a song',
                onTap: () => context.push(RoutePaths.upload),
              ),
            ],
            const Divider(height: 32),
            _MenuTile(
              icon: Icons.notifications_none,
              title: 'Notifications',
              badge: unread.valueOrNull,
              onTap: () => context.push(RoutePaths.notifications),
            ),
            _MenuTile(
              icon: Icons.download_outlined,
              title: 'Downloads',
              onTap: () => context.push(RoutePaths.downloads),
            ),
            _MenuTile(
              icon: Icons.favorite_border,
              title: 'Liked songs',
              onTap: () => context.push(RoutePaths.likedSongs),
            ),
            _MenuTile(
              icon: Icons.history,
              title: 'Recently played',
              onTap: () => context.push(RoutePaths.recentlyPlayed),
            ),
            _MenuTile(
              icon: Icons.settings_outlined,
              title: 'Settings',
              onTap: () => context.push(RoutePaths.settings),
            ),
            const Divider(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OutlinedButton.icon(
                onPressed: () => _confirmSignOut(context, ref),
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('Downloads on this device stay available until you remove them.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      await ref.read(authControllerProvider.notifier).logout();
      // The router redirects to the login screen as soon as the auth state changes.
    }
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.user});

  final User? user;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 64, 20, 24),
      decoration: const BoxDecoration(gradient: AppColors.heroGradient),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            radius: 36,
            backgroundColor: Colors.white24,
            foregroundImage:
                (user?.profileImageUrl?.isNotEmpty ?? false) ? NetworkImage(user!.profileImageUrl!) : null,
            child: Text(
              user?.initials ?? '?',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  user?.name ?? 'Listener',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 2),
                Text(
                  user?.email ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    StatusPill(
                      label: (user?.role ?? UserRole.user).wire,
                      color: Colors.white,
                      icon: user?.isArtist ?? false ? Icons.mic_none : null,
                    ),
                    if (user?.createdAt != null) ...<Widget>[
                      const SizedBox(width: 8),
                      Text(
                        'Joined ${Formatters.releaseDate(user!.createdAt)}',
                        style: const TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: <Widget>[
          Text(value, style: Theme.of(context).textTheme.titleLarge),
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

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: AppColors.textSecondaryDark),
      title: Text(title),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (badge != null && badge! > 0) StatusPill(label: '$badge', color: AppColors.accent),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right, size: 20),
        ],
      ),
    );
  }
}
