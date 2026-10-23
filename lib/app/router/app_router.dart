import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tuneflow/app/root_shell.dart';
import 'package:tuneflow/app/router/route_paths.dart';
import 'package:tuneflow/features/auth/domain/entities/auth_session.dart';
import 'package:tuneflow/features/auth/presentation/providers/auth_providers.dart';
import 'package:tuneflow/features/auth/presentation/screens/forgot_password_screen.dart';
import 'package:tuneflow/features/auth/presentation/screens/login_screen.dart';
import 'package:tuneflow/features/auth/presentation/screens/register_screen.dart';
import 'package:tuneflow/features/auth/presentation/screens/splash_screen.dart';
import 'package:tuneflow/features/catalog/presentation/screens/album_detail_screen.dart';
import 'package:tuneflow/features/catalog/presentation/screens/artist_detail_screen.dart';
import 'package:tuneflow/features/catalog/presentation/screens/genre_detail_screen.dart';
import 'package:tuneflow/features/downloads/presentation/screens/downloads_screen.dart';
import 'package:tuneflow/features/home/presentation/screens/home_screen.dart';
import 'package:tuneflow/features/library/presentation/screens/library_screen.dart';
import 'package:tuneflow/features/library/presentation/screens/liked_songs_screen.dart';
import 'package:tuneflow/features/library/presentation/screens/recently_played_screen.dart';
import 'package:tuneflow/features/player/presentation/screens/player_screen.dart';
import 'package:tuneflow/features/playlist/presentation/screens/playlist_detail_screen.dart';
import 'package:tuneflow/features/profile/presentation/screens/notifications_screen.dart';
import 'package:tuneflow/features/profile/presentation/screens/profile_screen.dart';
import 'package:tuneflow/features/profile/presentation/screens/settings_screen.dart';
import 'package:tuneflow/features/search/presentation/screens/search_screen.dart';
import 'package:tuneflow/features/upload/presentation/screens/upload_song_screen.dart';

/// The application router (docs section 11).
///
/// * A [`StatefulShellRoute`] keeps each of the four tabs alive, so a search query or a scrolled
///   library survives tab switches - the single most noticeable difference between a good and a
///   bad music app.
/// * The redirect below is the auth guard. It reads a [ValueNotifier] rather than the provider
///   directly because `GoRouter` needs a `Listenable` to re-evaluate when the session changes.
final Provider<GoRouter> routerProvider = Provider<GoRouter>(
  (Ref ref) {
    final ValueNotifier<AuthState> authState = ValueNotifier<AuthState>(
      ref.read(authControllerProvider),
    );
    ref.listen<AuthState>(authControllerProvider, (AuthState? previous, AuthState next) {
      authState.value = next;
    });

    // The navigator that owns full-screen routes. It has to be created here - inside the provider -
    // and handed to GoRouter as its own `navigatorKey`, because go_router asserts that every
    // `parentNavigatorKey` in the route table either belongs to an ancestor `ShellRoute` or is the
    // router's own navigator key. Creating it inside the provider also means each router instance
    // gets a fresh key: a file-level `GlobalKey` would be reused across provider rebuilds (and, in
    // tests, across containers), which Flutter rejects with "Multiple widgets used the same
    // GlobalKey" - a second, sneakier failure of the same mistake.
    final GlobalKey<NavigatorState> rootNavigatorKey =
        GlobalKey<NavigatorState>(debugLabel: 'root');

    final GoRouter router = GoRouter(
      navigatorKey: rootNavigatorKey,
      initialLocation: RoutePaths.splash,
      refreshListenable: authState,
      debugLogDiagnostics: false,
      redirect: (BuildContext context, GoRouterState state) => _redirect(authState.value, state),
      routes: <RouteBase>[
        GoRoute(
          path: RoutePaths.splash,
          builder: (BuildContext context, GoRouterState state) => const SplashScreen(),
        ),
        GoRoute(
          path: RoutePaths.login,
          builder: (BuildContext context, GoRouterState state) => const LoginScreen(),
        ),
        GoRoute(
          path: RoutePaths.register,
          builder: (BuildContext context, GoRouterState state) => const RegisterScreen(),
        ),
        GoRoute(
          path: RoutePaths.forgotPassword,
          builder: (BuildContext context, GoRouterState state) => const ForgotPasswordScreen(),
        ),

        // Tabs ---------------------------------------------------------------------------------
        StatefulShellRoute.indexedStack(
          builder: (
            BuildContext context,
            GoRouterState state,
            StatefulNavigationShell navigationShell,
          ) =>
              RootShell(navigationShell: navigationShell),
          branches: <StatefulShellBranch>[
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: RoutePaths.home,
                  builder: (BuildContext context, GoRouterState state) => const HomeScreen(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: RoutePaths.search,
                  builder: (BuildContext context, GoRouterState state) => const SearchScreen(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: RoutePaths.library,
                  builder: (BuildContext context, GoRouterState state) => const LibraryScreen(),
                  routes: <RouteBase>[
                    GoRoute(
                      path: 'liked',
                      builder: (BuildContext context, GoRouterState state) =>
                          const LikedSongsScreen(),
                    ),
                    GoRoute(
                      path: 'recent',
                      builder: (BuildContext context, GoRouterState state) =>
                          const RecentlyPlayedScreen(),
                    ),
                  ],
                ),
              ],
            ),
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: RoutePaths.profile,
                  builder: (BuildContext context, GoRouterState state) => const ProfileScreen(),
                ),
              ],
            ),
          ],
        ),

        // Full-screen routes pushed above the shell ---------------------------------------------
        GoRoute(
          path: RoutePaths.player,
          parentNavigatorKey: rootNavigatorKey,
          builder: (BuildContext context, GoRouterState state) => const PlayerScreen(),
        ),
        GoRoute(
          path: RoutePaths.settings,
          parentNavigatorKey: rootNavigatorKey,
          builder: (BuildContext context, GoRouterState state) => const SettingsScreen(),
        ),
        GoRoute(
          path: RoutePaths.notifications,
          parentNavigatorKey: rootNavigatorKey,
          builder: (BuildContext context, GoRouterState state) => const NotificationsScreen(),
        ),
        GoRoute(
          path: RoutePaths.downloads,
          parentNavigatorKey: rootNavigatorKey,
          builder: (BuildContext context, GoRouterState state) => const DownloadsScreen(),
        ),

        GoRoute(
          path: RoutePaths.upload,
          parentNavigatorKey: rootNavigatorKey,
          builder: (BuildContext context, GoRouterState state) => const UploadSongScreen(),
        ),

        // Catalogue detail screens. Their paths are built from the same `RoutePaths` helpers every
        // call site uses, so a link can never point at a location the table does not have - the
        // failure mode being a silent "Not found" page, which no analyzer check would catch. They
        // are root-level (like the player) so an album or playlist opened from *any* tab covers the
        // shell instead of appearing inside the tab that happened to push it.
        GoRoute(
          path: RoutePaths.album(':id'),
          parentNavigatorKey: rootNavigatorKey,
          builder: (BuildContext context, GoRouterState state) =>
              AlbumDetailScreen(albumId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: RoutePaths.artist(':id'),
          parentNavigatorKey: rootNavigatorKey,
          builder: (BuildContext context, GoRouterState state) =>
              ArtistDetailScreen(artistId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: RoutePaths.playlist(':id'),
          parentNavigatorKey: rootNavigatorKey,
          builder: (BuildContext context, GoRouterState state) =>
              PlaylistDetailScreen(playlistId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: RoutePaths.genre(':id'),
          parentNavigatorKey: rootNavigatorKey,
          builder: (BuildContext context, GoRouterState state) =>
              GenreDetailScreen(genreSlug: state.pathParameters['id']!),
        ),
      ],
      errorBuilder: (BuildContext context, GoRouterState state) => Scaffold(
        appBar: AppBar(title: const Text('Not found')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('No page at ${state.uri}'),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: () => context.go(RoutePaths.home),
                child: const Text('Go home'),
              ),
            ],
          ),
        ),
      ),
    );

    ref.onDispose(() {
      authState.dispose();
      router.dispose();
    });

    return router;
  },
  name: 'router',
);

/// Guard rules, in order:
/// 1. While the session is being restored, hold the user on the splash - never flash the login form.
/// 2. Unauthenticated users may only see the public routes; anything else remembers where they were
///    headed so they land there after signing in.
/// 3. Authenticated users are moved off the auth screens (deep links to `/login` after signing in).
String? _redirect(AuthState auth, GoRouterState state) {
  final String location = state.matchedLocation;

  if (auth.status == AuthStatus.unknown) {
    return location == RoutePaths.splash ? null : RoutePaths.splash;
  }

  if (!auth.isAuthenticated) {
    return RoutePaths.isPublic(location) ? null : RoutePaths.login;
  }

  if (RoutePaths.isPublic(location)) {
    return RoutePaths.home;
  }

  return null;
}
