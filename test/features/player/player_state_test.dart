import 'package:flutter_test/flutter_test.dart';
import 'package:tuneflow/features/catalog/domain/entities/song.dart';
import 'package:tuneflow/features/player/domain/entities/player_state.dart';

/// The player state is the object every playback surface reads, so its derivations (progress,
/// remaining time, emptiness) are tested rather than eyeballed in the UI.
void main() {
  Song song(String id, {int seconds = 200}) => Song(
        id: id,
        title: 'Track $id',
        durationSeconds: seconds,
      );

  group('PlayerState', () {
    test('starts idle with nothing loaded', () {
      const PlayerState state = PlayerState();

      expect(state.status, PlaybackStatus.idle);
      expect(state.isIdle, isTrue);
      expect(state.hasTrack, isFalse);
      expect(state.progress, 0);
      expect(state.hasNext, isFalse);
    });

    test('computes progress and remaining time', () {
      final PlayerState state = PlayerState(
        status: PlaybackStatus.playing,
        track: song('1', seconds: 200),
        position: const Duration(seconds: 50),
        duration: const Duration(seconds: 200),
      );

      expect(state.progress, closeTo(0.25, 0.0001));
      expect(state.remaining, const Duration(seconds: 150));
      expect(state.isPlaying, isTrue);
    });

    test('clamps progress instead of exceeding the track length', () {
      final PlayerState state = PlayerState(
        track: song('1'),
        position: const Duration(seconds: 500),
        duration: const Duration(seconds: 200),
      );

      // A position beyond the duration happens for a moment when a stream reports the next track.
      expect(state.progress, 1.0);
      expect(state.remaining, Duration.zero);
    });

    test('guards against a zero duration rather than dividing by zero', () {
      final PlayerState state = PlayerState(track: song('1', seconds: 0), duration: Duration.zero);
      expect(state.progress, 0);
    });

    test('copyWith can clear the track and the error independently', () {
      final PlayerState state = PlayerState(
        status: PlaybackStatus.error,
        track: song('1'),
        errorMessage: 'Could not play this track.',
      );

      final PlayerState cleared = state.copyWith(
        status: PlaybackStatus.idle,
        clearTrack: true,
        clearError: true,
      );

      expect(cleared.track, isNull);
      expect(cleared.errorMessage, isNull);
      expect(cleared.isIdle, isTrue);
      // Untouched fields survive the copy.
      expect(cleared.repeatMode, RepeatMode.off);
    });
  });

  group('RepeatMode', () {
    test('cycles off -> all -> one -> off', () {
      expect(RepeatMode.off.next, RepeatMode.all);
      expect(RepeatMode.all.next, RepeatMode.one);
      expect(RepeatMode.one.next, RepeatMode.off);
    });
  });
}
