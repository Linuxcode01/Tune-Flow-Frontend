import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tuneflow/app/router/route_paths.dart';
import 'package:tuneflow/core/constants/api_endpoints.dart';
import 'package:tuneflow/core/network/paged_response.dart';
import 'package:tuneflow/core/providers/core_providers.dart';
import 'package:tuneflow/core/theme/app_colors.dart';
import 'package:tuneflow/core/utils/formatters.dart';
import 'package:tuneflow/core/widgets/state_views.dart';
import 'package:tuneflow/features/profile/presentation/providers/profile_providers.dart';

/// Notification feed (new releases from followed artists, playlist activity, system messages).
///
/// Tapping a row marks it read and, when the payload carries an entity id, navigates to it - which is
/// what "new release" notifications are actually for.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<PagedResponse<AppNotification>> notifications =
        ref.watch(notificationsProvider);
    final bool hasUnread =
        notifications.valueOrNull?.items.any((AppNotification item) => !item.read) ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: <Widget>[
          if (hasUnread)
            TextButton(
              onPressed: () async {
                await ref.read(apiClientProvider).post(ApiEndpoints.markAllRead);
                ref.invalidate(notificationsProvider);
                ref.invalidate(unreadNotificationCountProvider);
              },
              child: const Text('Mark all read'),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(notificationsProvider);
          ref.invalidate(unreadNotificationCountProvider);
        },
        child: notifications.when(
          loading: () => const SkeletonList(itemCount: 7),
          error: (Object error, StackTrace stackTrace) => ErrorView(
            error: error,
            onRetry: () => ref.invalidate(notificationsProvider),
          ),
          data: (PagedResponse<AppNotification> page) {
            if (page.items.isEmpty) {
              return const EmptyView(
                title: 'No notifications',
                message: 'Follow an artist and you will hear about their new releases.',
                icon: Icons.notifications_none,
              );
            }
            return ListView.separated(
              itemCount: page.items.length,
              separatorBuilder: (BuildContext context, int index) => const Divider(height: 1),
              itemBuilder: (BuildContext context, int index) {
                final AppNotification notification = page.items[index];
                return ListTile(
                  onTap: () => _onTap(context, ref, notification),
                  leading: CircleAvatar(
                    backgroundColor: _tint(notification.type).withValues(alpha: 0.18),
                    child: Icon(_icon(notification.type), size: 18, color: _tint(notification.type)),
                  ),
                  title: Text(
                    notification.title,
                    style: TextStyle(
                      fontWeight: notification.read ? FontWeight.w400 : FontWeight.w700,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (notification.body != null) Text(notification.body!),
                      const SizedBox(height: 2),
                      Text(
                        Formatters.relativeTime(notification.createdAt),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: AppColors.textSecondaryDark,
                            ),
                      ),
                    ],
                  ),
                  trailing: notification.read
                      ? null
                      : const SizedBox(
                          width: 8,
                          height: 8,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: AppColors.accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _onTap(
    BuildContext context,
    WidgetRef ref,
    AppNotification notification,
  ) async {
    if (!notification.read) {
      await ref.read(apiClientProvider).post(ApiEndpoints.notificationRead(notification.id));
      ref.invalidate(notificationsProvider);
      ref.invalidate(unreadNotificationCountProvider);
    }

    final String? target = _targetOf(notification);
    if (target != null && context.mounted) {
      await context.push(target);
    }
  }

  /// Builds a route from the notification payload. Only paths the app actually owns are used, so a
  /// malformed payload cannot navigate somewhere unexpected.
  String? _targetOf(AppNotification notification) {
    final String raw = (notification.data ?? '').trim();
    if (raw.isEmpty) {
      return null;
    }
    // The payload is a JSON object such as {"songId":"..."} or a bare id, depending on the producer.
    final RegExp idPattern = RegExp(r'[0-9a-fA-F-]{36}');
    final RegExpMatch? match = idPattern.firstMatch(raw);
    if (match == null) {
      return null;
    }
    final String id = match.group(0)!;
    if (raw.toLowerCase().contains('artist')) {
      return RoutePaths.artist(id);
    }
    if (raw.toLowerCase().contains('album')) {
      return RoutePaths.album(id);
    }
    if (raw.toLowerCase().contains('playlist')) {
      return RoutePaths.playlist(id);
    }
    return null;
  }

  IconData _icon(String type) {
    switch (type.toUpperCase()) {
      case 'NEW_RELEASE':
        return Icons.new_releases_outlined;
      case 'PLAYLIST_UPDATE':
        return Icons.queue_music;
      case 'FOLLOWER':
        return Icons.person_add_alt;
      default:
        return Icons.campaign_outlined;
    }
  }

  Color _tint(String type) {
    switch (type.toUpperCase()) {
      case 'NEW_RELEASE':
        return AppColors.accent;
      case 'PLAYLIST_UPDATE':
        return AppColors.secondary;
      default:
        return AppColors.textSecondaryDark;
    }
  }
}
