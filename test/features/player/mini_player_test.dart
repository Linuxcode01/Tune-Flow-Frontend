import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuneflow/core/theme/app_theme.dart';
import 'package:tuneflow/features/catalog/domain/entities/artist.dart';
import 'package:tuneflow/features/catalog/domain/entities/song.dart';
import 'package:tuneflow/features/player/domain/entities/player_state.dart';
import 'package:tuneflow/features/player/presentation/providers/player_providers.dart';
import 'package:tuneflow/features/player/presentation/widgets/mini_player.dart';

class _FakePlayerController extends PlayerController {
  _FakePlayerController(this._state);

  final PlayerState _state;

  @override
  PlayerState build() => _state;
}

/// The mini-player is part of the shell, so it must render nothing when idle and show correct
/// controls when a track is loaded - otherwise every tab carries a broken strip.
void main() {
  const Song song = Song(
    id: 'song-1',
    title: 'Neon Skyline',
    durationSeconds: 214,
    artist: ArtistSummary(id: 'artist-1', name: 'Aria Vance'),
  );

  Widget wrap(PlayerState state) {
    return ProviderScope(
      overrides: <Override>[
        playerControllerProvider.overrideWith(() => _FakePlayerController(state)),
      ],
      child: MaterialApp(theme: AppTheme.dark, home: const Scaffold(body: MiniPlayer())),
    );
  }

  testWidgets('renders nothing when no track is loaded', (WidgetTester tester) async {
    await tester.pumpWidget(wrap(const PlayerState()));

    expect(find.text('Neon Skyline'), findsNothing);
    expect(find.byType(IconButton), findsNothing);
  });

  testWidgets('shows the track, a pause button and the next action while playing',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      wrap(
        const PlayerState(
          status: PlaybackStatus.playing,
          track: song,
          duration: Duration(seconds: 214),
          position: Duration(seconds: 30),
          hasNext: true,
        ),
      ),
    );

    expect(find.text('Neon Skyline'), findsOneWidget);
    expect(find.text('Aria Vance'), findsOneWidget);
    expect(find.byIcon(Icons.pause), findsOneWidget);
    expect(find.byIcon(Icons.skip_next), findsOneWidget);
  });

  testWidgets('shows play (not pause) once the queue has finished', (WidgetTester tester) async {
    await tester.pumpWidget(
      wrap(
        const PlayerState(
          status: PlaybackStatus.completed,
          track: song,
          duration: Duration(seconds: 214),
          position: Duration(seconds: 214),
        ),
      ),
    );

    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.byIcon(Icons.pause), findsNothing);
  });

  testWidgets('surfaces a playback failure instead of pretending to play',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      wrap(
        const PlayerState(
          status: PlaybackStatus.error,
          track: song,
          errorMessage: 'Could not play this track.',
        ),
      ),
    );

    expect(find.text('Could not play this track.'), findsOneWidget);
  });
}
