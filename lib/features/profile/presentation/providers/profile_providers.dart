import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tuneflow/core/constants/api_endpoints.dart';
import 'package:tuneflow/core/network/paged_response.dart';
import 'package:tuneflow/core/providers/core_providers.dart';
import 'package:tuneflow/features/auth/domain/entities/user.dart';
import 'package:tuneflow/features/auth/presentation/providers/auth_providers.dart';

/// Profile-adjacent read models: the notification feed and the unread badge.
///
/// Notifications are modelled here rather than in their own module because this is the only surface
/// that consumes them; if a second consumer appears, the providers move without touching the screens.

/// A notification row (`GET /notifications`).
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    this.body,
    this.data,
    this.read = false,
    this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? 'SYSTEM',
      title: json['title'] as String? ?? '',
      body: json['body'] as String?,
      data: json['data'] as String?,
      read: json['read'] as bool? ?? false,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '')?.toUtc(),
    );
  }

  final String id;
  final String type;
  final String title;
  final String? body;

  /// Opaque JSON payload; typically the id of the entity the notification refers to.
  final String? data;
  final bool read;
  final DateTime? createdAt;
}

final FutureProvider<PagedResponse<AppNotification>> notificationsProvider =
    FutureProvider<PagedResponse<AppNotification>>(
  (Ref ref) => ref
      .watch(apiClientProvider)
      .getPaged<AppNotification>(
        ApiEndpoints.notifications,
        size: 30,
        itemMapper: AppNotification.fromJson,
      ),
  name: 'notifications',
);

final FutureProvider<int> unreadNotificationCountProvider = FutureProvider<int>(
  (Ref ref) async {
    final Map<String, dynamic> data = await ref.watch(apiClientProvider).getJson(ApiEndpoints.unreadCount);
    // The API returns an object ({"count": n}) rather than a bare number; accept both shapes so a
    // future simplification on the server does not break the badge.
    if (data.containsKey('count')) {
      return (data['count'] as num?)?.toInt() ?? 0;
    }
    return (data['unreadCount'] as num?)?.toInt() ?? 0;
  },
  name: 'unreadNotificationCount',
);

/// The display name shown in the home greeting and the profile header.
final Provider<String?> currentUserNameProvider = Provider<String?>(
  (Ref ref) {
    final User? user = ref.watch(currentUserProvider);
    if (user == null) {
      return null;
    }
    final List<String> parts = user.name.split(' ');
    return parts.isEmpty ? user.name : parts.first;
  },
  name: 'currentUserName',
);
