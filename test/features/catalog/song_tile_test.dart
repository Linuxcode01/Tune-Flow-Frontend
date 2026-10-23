import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuneflow/core/theme/app_theme.dart';
import 'package:tuneflow/features/catalog/domain/entities/artist.dart';
import 'package:tuneflow/features/catalog/domain/entities/song.dart';
import 'package:tuneflow/features/catalog/presentation/widgets/song_tile.dart';
import 'package:tuneflow/features/library/presentation/providers/library_providers.dart';
import 'package:tuneflow/features/player/domain/entities/player_state.dart';
import 'package:tuneflow/features/player/presentation/providers/player_providers.dart';

/// A fake player so the tile can be rendered without an audio engine or a network stack.
class _FakePlayerController extends PlayerController {
  _FakePlayerController(this._state);

  final PlayerState _state;

  @override
  PlayerState build() => _state;
}

/// Widget tests for the row that every tracklist in the app uses.
void main() {
  const Song song = Song(
    id: 'song-1',
    title: 'Neon Skyline',
    durationSeconds: 214,
    explicit: true,
    artist: ArtistSummary(id: 'artist-1', name: 'Aria Vance', verified: true),
    liked: false,
  );

  Widget wrap(Widget child, {PlayerState playerState = const PlayerState()}) {
    return ProviderScope(
      overrides: <Override>[
        playerControllerProvider.overrideWith(() => _FakePlayerController(playerState)),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(body: child),
      ),
    );
  }

  testWidgets('renders title, artist, duration and the explicit flag', (WidgetTester tester) async {
    await tester.pumpWidget(wrap(const SongTile(song: song)));

    expect(find.text('Neon Skyline'), findsOneWidget);
    expect(find.text('Aria Vance'), findsOneWidget);
    expect(find.text('3:34'), findsOneWidget);
    expect(find.text('E'), findsOneWidget);
  });

  testWidgets('shows an outline heart when the track is not liked', (WidgetTester tester) async {
    await tester.pumpWidget(wrap(const SongTile(song: song)));

    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    expect(find.byIcon(Icons.favorite), findsNothing);
  });

  testWidgets('honours a local like override without a round trip', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          playerControllerProvider.overrideWith(() => _FakePlayerController(const PlayerState())),
          likedOverridesProvider.overrideWith((Ref ref) => <String, bool>{'song-1': true}),
        ],
        child: MaterialApp(theme: AppTheme.dark, home: const Scaffold(body: SongTile(song: song))),
      ),
    );

    expect(find.byIcon(Icons.favorite), findsOneWidget);
  });

  testWidgets('highlights the row that is currently playing', (WidgetTester tester) async {
    await tester.pumpWidget(
      wrap(
        const SongTile(song: song),
        playerState: const PlayerState(
          status: PlaybackStatus.playing,
          track: song,
          duration: Duration(seconds: 214),
        ),
      ),
    );

    // The now-playing indicator replaces the artwork while the same track plays.
    expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget);
  });

  testWidgets('hides the like button when asked to', (WidgetTester tester) async {
    await tester.pumpWidget(wrap(const SongTile(song: song, showLikeButton: false)));

    expect(find.byIcon(Icons.favorite_border), findsNothing);
  });
}
