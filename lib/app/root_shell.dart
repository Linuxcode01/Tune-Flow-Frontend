import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tuneflow/core/constants/app_constants.dart';
import 'package:tuneflow/features/player/presentation/providers/player_providers.dart';
import 'package:tuneflow/features/player/presentation/widgets/mini_player.dart';

/// The persistent chrome around the four primary tabs (docs section 19).
///
/// Structure: the active tab's content, the mini-player sitting directly above the navigation bar,
/// and the navigation bar itself. Because the mini-player is part of the shell - not of a screen -
/// playback controls remain reachable from every tab, which is the whole point of a mini-player.
class RootShell extends ConsumerWidget {
  const RootShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const List<NavigationDestination> _destinations = <NavigationDestination>[
    NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home_rounded),
      label: 'Home',
    ),
    NavigationDestination(
      icon: Icon(Icons.search_outlined),
      selectedIcon: Icon(Icons.search_rounded),
      label: 'Search',
    ),
    NavigationDestination(
      icon: Icon(Icons.library_music_outlined),
      selectedIcon: Icon(Icons.library_music_rounded),
      label: 'Library',
    ),
    NavigationDestination(
      icon: Icon(Icons.person_outline_rounded),
      selectedIcon: Icon(Icons.person_rounded),
      label: 'Profile',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool hasTrack = ref.watch(currentTrackProvider) != null;

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (hasTrack) ...<Widget>[
            const MiniPlayer(),
            // A hairline separates the player from the tabs so the two never read as one control.
            const SizedBox(height: 1, child: ColoredBox(color: Colors.black26)),
          ],
          NavigationBar(
            height: AppConstants.miniPlayerHeight,
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: _onDestinationSelected,
            destinations: _destinations,
          ),
        ],
      ),
    );
  }

  /// Tapping the active tab pops that branch back to its root, which is the behaviour users expect
  /// from a bottom navigation bar (and the only way back out of a deep stack without a back gesture).
  void _onDestinationSelected(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }
}
