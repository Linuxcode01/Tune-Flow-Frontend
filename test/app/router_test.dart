import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tuneflow/app/root_shell.dart';
import 'package:tuneflow/app/router/app_router.dart';
import 'package:tuneflow/app/router/route_paths.dart';
import 'package:tuneflow/core/network/api_client.dart';
import 'package:tuneflow/core/providers/core_providers.dart';
import 'package:tuneflow/features/auth/domain/entities/auth_session.dart';
import 'package:tuneflow/features/auth/domain/entities/user.dart';
import 'package:tuneflow/features/auth/domain/repositories/auth_repository.dart';
import 'package:tuneflow/features/auth/presentation/providers/auth_providers.dart';
import 'package:tuneflow/features/auth/presentation/screens/login_screen.dart';
import 'package:tuneflow/features/catalog/presentation/screens/album_detail_screen.dart';
import 'package:tuneflow/features/catalog/presentation/screens/artist_detail_screen.dart';
import 'package:tuneflow/features/catalog/presentation/screens/genre_detail_screen.dart';
import 'package:tuneflow/features/downloads/presentation/screens/downloads_screen.dart';
import 'package:tuneflow/features/home/presentation/screens/home_screen.dart';
import 'package:tuneflow/features/library/presentation/screens/library_screen.dart';
import 'package:tuneflow/features/library/presentation/screens/liked_songs_screen.dart';
import 'package:tuneflow/features/library/presentation/screens/recently_played_screen.dart';
import 'package:tuneflow/features/player/domain/entities/player_state.dart';
import 'package:tuneflow/features/player/presentation/providers/player_providers.dart';
import 'package:tuneflow/features/player/presentation/screens/player_screen.dart';
import 'package:tuneflow/features/playlist/presentation/screens/playlist_detail_screen.dart';
import 'package:tuneflow/features/profile/presentation/screens/notifications_screen.dart';
import 'package:tuneflow/features/profile/presentation/screens/profile_screen.dart';
import 'package:tuneflow/features/profile/presentation/screens/settings_screen.dart';
import 'package:tuneflow/features/search/presentation/screens/search_screen.dart';
import 'package:tuneflow/features/upload/presentation/screens/upload_song_screen.dart';

/// Tests for the router *configuration* - the layer where `flutter analyze` sees nothing wrong and
/// unit tests that never build the router see nothing at all.
///
/// Two classes of bug live here, and both reached a physical device before these tests existed:
///
/// 1. **A dangling `parentNavigatorKey`.** The player, settings, notifications and downloads screens
///    are declared with `parentNavigatorKey` so they cover the tab shell. go_router asserts that
///    every such key is either an ancestor `ShellRoute`'s key or the key handed to
///    `GoRouter(navigatorKey: ...)`; when it is neither, the app dies on the first route parse with
///    `'allowedKeys.contains(parentKey)'` - a red screen, not a warning.
///
/// 2. **A route that no call site can reach.** The catalogue detail screens were nested under
///    `/home`, giving them the paths `/home/album/:id`, while every call site pushed
///    `/album/:id`. Nothing failed to compile; tapping an album simply landed on the "Not found"
///    page.
///
/// These tests therefore navigate the real router to every location the app can build and assert
/// that the expected screen is on top. They use a never-resolving [ApiClient] so screens settle in
/// their loading state: deterministic, and no network or timers in the test process.

class _NeverApiClient implements ApiClient {
  /// Every call parks forever. `Future<Never>` is a subtype of every `Future<T>`, so this satisfies
  /// any return type without guessing the shape of the response.
  @override
  dynamic noSuchMethod(Invocation invocation) => Completer<Never>().future;
}

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({this.session});

  final AuthSession? session;

  @override
  Future<AuthSession?> restoreSession() async => session;

  @override
  Future<AuthSession> login({required String email, required String password}) =>
      throw UnimplementedError();

  @override
  Future<AuthSession> register({
    required String name,
    required String email,
    required String password,
    required bool asArtist,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> logout() async {}

  @override
  Future<User> fetchCurrentUser() => throw UnimplementedError();

  @override
  Future<User> updateProfile({String? name, String? profileImageUrl}) =>
      throw UnimplementedError();

  @override
  Future<void> changePassword({required String currentPassword, required String newPassword}) =>
      throw UnimplementedError();

  @override
  Future<String?> requestPasswordReset(String email) => throw UnimplementedError();

  @override
  Future<void> resetPassword({required String token, required String newPassword}) =>
      throw UnimplementedError();
}

/// Keeps the player independent of platform audio.
class _IdlePlayerController extends PlayerController {
  @override
  PlayerState build() => const PlayerState();
}

const AuthSession _session = AuthSession(
  accessToken: 'access',
  refreshToken: 'refresh',
  expiresInSeconds: 900,
  user: User(id: 'user-1', name: 'Aria', email: 'aria@tuneflow.dev'),
);

void main() {
  /// Pumps the production router inside a scope backed by [container] so both the router and the
  /// widgets read from the same overrides.
  Future<void> pumpApp(WidgetTester tester, ProviderContainer container, GoRouter router) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  /// Lets the async session restore settle before the guard is consulted.
  Future<void> settleSession(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  Future<(ProviderContainer, GoRouter)> boot(
    WidgetTester tester, {
    bool signedIn = true,
  }) async {
    // The settings screen reads preferences in `initState`, and `sharedPreferencesProvider`
    // deliberately throws until `main()` overrides it - so the test has to supply the same seam.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences preferences = await SharedPreferences.getInstance();

    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        authRepositoryProvider.overrideWithValue(
          _FakeAuthRepository(session: signedIn ? _session : null),
        ),
        playerControllerProvider.overrideWith(_IdlePlayerController.new),
        apiClientProvider.overrideWithValue(_NeverApiClient()),
        sharedPreferencesProvider.overrideWithValue(preferences),
      ],
    );
    addTearDown(container.dispose);

    // Constructing the router validates the navigator keys.
    final GoRouter router = container.read(routerProvider);
    await pumpApp(tester, container, router);
    await settleSession(tester);
    return (container, router);
  }

  /// Navigates and pumps enough frames for the destination to build without waiting for any
  /// animation to finish (skeletons and shimmers never do).
  Future<void> go(WidgetTester tester, GoRouter router, String location) async {
    router.go(location);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  group('route configuration', () {
    testWidgets('no route declares a dangling parentNavigatorKey', (WidgetTester tester) async {
      final (_, GoRouter router) = await boot(tester);

      // Reaching a full-screen route is what forces go_router to resolve the parent navigator; a
      // dangling key throws the `allowedKeys.contains(parentKey)` assertion here.
      await go(tester, router, RoutePaths.player);

      expect(
        tester.takeException(),
        isNull,
        reason: 'a dangling parentNavigatorKey surfaces as a go_router assertion failure',
      );
    });

    testWidgets('every location the app can build lands on a real screen',
        (WidgetTester tester) async {
      final (_, GoRouter router) = await boot(tester);

      // The full route table, including every path produced by a `RoutePaths` builder.
      final Map<String, Type> expected = <String, Type>{
        RoutePaths.home: HomeScreen,
        RoutePaths.search: SearchScreen,
        RoutePaths.library: LibraryScreen,
        RoutePaths.profile: ProfileScreen,
        RoutePaths.likedSongs: LikedSongsScreen,
        RoutePaths.recentlyPlayed: RecentlyPlayedScreen,
        RoutePaths.player: PlayerScreen,
        RoutePaths.settings: SettingsScreen,
        RoutePaths.notifications: NotificationsScreen,
        RoutePaths.downloads: DownloadsScreen,
        RoutePaths.album('album-1'): AlbumDetailScreen,
        RoutePaths.artist('artist-1'): ArtistDetailScreen,
        RoutePaths.playlist('playlist-1'): PlaylistDetailScreen,
        RoutePaths.genre('pop'): GenreDetailScreen,
        RoutePaths.upload: UploadSongScreen,
      };

      for (final MapEntry<String, Type> entry in expected.entries) {
        await go(tester, router, entry.key);

        // The errorBuilder renders this exact title, so its presence means the location did not
        // match any route - the failure mode of the nested-vs-flat path mismatch.
        expect(
          find.text('Not found'),
          findsNothing,
          reason: '${entry.key} is not handled by any route in the table',
        );
        expect(
          find.byWidgetPredicate((Widget widget) => widget.runtimeType == entry.value),
          findsOneWidget,
          reason: '${entry.key} did not resolve to ${entry.value}',
        );
        expect(tester.takeException(), isNull, reason: '${entry.key} threw while building');
      }
    });

    testWidgets('the auth guard still keeps signed-out users off every private route',
        (WidgetTester tester) async {
      final (_, GoRouter router) = await boot(tester, signedIn: false);

      for (final String location in <String>[
        RoutePaths.home,
        RoutePaths.library,
        RoutePaths.player,
        RoutePaths.downloads,
        RoutePaths.album('album-1'),
        RoutePaths.playlist('playlist-1'),
      ]) {
        await go(tester, router, location);

        expect(
          find.byType(LoginScreen),
          findsOneWidget,
          reason: '$location should have redirected to the login screen',
        );
        expect(tester.takeException(), isNull, reason: '$location threw while redirecting');
      }
    });

    testWidgets('the public routes stay reachable while signed out', (WidgetTester tester) async {
      final (_, GoRouter router) = await boot(tester, signedIn: false);

      await go(tester, router, RoutePaths.forgotPassword);
      expect(find.text('Not found'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('full-screen routes', () {
    testWidgets('the player opens above the shell', (WidgetTester tester) async {
      final (_, GoRouter router) = await boot(tester);

      // Start on the home tab, then push the player: it must replace the whole shell rather than
      // being nested inside the tab.
      await go(tester, router, RoutePaths.home);
      expect(find.byType(HomeScreen), findsOneWidget);

      await go(tester, router, RoutePaths.player);

      // The player must not be nested inside the shell's navigator: that is what "declared with
      // parentNavigatorKey" buys, and what stops the mini-player and tab bar from showing through.
      expect(find.byType(PlayerScreen), findsOneWidget);
      expect(
        find.ancestor(of: find.byType(PlayerScreen), matching: find.byType(RootShell)),
        findsNothing,
      );
      // The home tab is still mounted underneath (that is what makes back work), but inside the
      // shell - the opposite of the player.
      expect(
        find.ancestor(of: find.byType(HomeScreen), matching: find.byType(RootShell)),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
