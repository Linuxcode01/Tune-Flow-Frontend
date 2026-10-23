import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuneflow/core/error/app_exception.dart';
import 'package:tuneflow/core/network/api_client.dart';
import 'package:tuneflow/core/providers/core_providers.dart';
import 'package:tuneflow/features/playlist/presentation/providers/playlist_providers.dart';

/// Adding several songs to a playlist is a loop over a single-song endpoint, and the loop has to
/// survive the two things that actually happen in practice: a song that is already in the playlist
/// (the API answers `409 SONG_ALREADY_IN_PLAYLIST`) and one genuine failure in the middle. Aborting
/// the whole batch on either would leave the user with a half-filled playlist and no explanation.

/// Records writes and answers with whatever the test configured.
class _RecordingApiClient implements ApiClient {
  _RecordingApiClient({this.alreadyPresent = const <String>{}, this.failing = const <String>{}});

  final Set<String> alreadyPresent;
  final Set<String> failing;

  final List<({String path, Map<String, dynamic> body})> posts = <({String path, Map<String, dynamic> body})>[];

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Object? body,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
  }) async {
    final Map<String, dynamic> map = (body as Map<String, dynamic>?) ?? const <String, dynamic>{};
    posts.add((path: path, body: map));

    final String songId = map['songId'] as String? ?? '';
    if (alreadyPresent.contains(songId)) {
      throw const ApiException(
        message: 'That song is already in this playlist.',
        errorCode: 'SONG_ALREADY_IN_PLAYLIST',
        statusCode: 409,
      );
    }
    if (failing.contains(songId)) {
      throw const ApiException(
        message: 'Playlist not found.',
        errorCode: 'PLAYLIST_NOT_FOUND',
        statusCode: 404,
      );
    }
    return <String, dynamic>{};
  }

  @override
  Future<void> delete(
    String path, {
    Object? body,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

ProviderContainer _containerWith(_RecordingApiClient client) {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[apiClientProvider.overrideWithValue(client)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('PlaylistActions.addSongs', () {
    test('sends one request per song, in the order the user selected them', () async {
      final _RecordingApiClient client = _RecordingApiClient();
      final ProviderContainer container = _containerWith(client);

      final PlaylistAddResult result = await container
          .read(playlistActionsProvider)
          .addSongs('p1', <String>['s1', 's2', 's3']);

      expect(result.added, 3);
      expect(result.skipped, 0);
      expect(result.firstError, isNull);
      expect(client.posts.length, 3);
      expect(
        client.posts.map((({String path, Map<String, dynamic> body}) call) => call.path),
        everyElement('/playlists/p1/songs'),
      );
      expect(
        client.posts.map((({String path, Map<String, dynamic> body}) call) => call.body['songId']),
        <String>['s1', 's2', 's3'],
      );
    });

    test('counts songs that were already there without stopping the batch', () async {
      final _RecordingApiClient client = _RecordingApiClient(alreadyPresent: <String>{'s2'});
      final ProviderContainer container = _containerWith(client);

      final PlaylistAddResult result = await container
          .read(playlistActionsProvider)
          .addSongs('p1', <String>['s1', 's2', 's3']);

      expect(result.added, 2, reason: 'the songs after the duplicate must still be attempted');
      expect(result.skipped, 1);
      expect(result.firstError, isNull, reason: 'a duplicate is information, not a failure');
      expect(client.posts.length, 3);
    });

    test('keeps going after a genuine failure and reports the first one', () async {
      final _RecordingApiClient client = _RecordingApiClient(failing: <String>{'s2'});
      final ProviderContainer container = _containerWith(client);

      final PlaylistAddResult result = await container
          .read(playlistActionsProvider)
          .addSongs('p1', <String>['s1', 's2', 's3']);

      expect(result.added, 2);
      expect(result.skipped, 0);
      expect(result.firstError, 'Playlist not found.');
    });

    test('is a no-op for an empty selection', () async {
      final _RecordingApiClient client = _RecordingApiClient();
      final ProviderContainer container = _containerWith(client);

      final PlaylistAddResult result =
          await container.read(playlistActionsProvider).addSongs('p1', const <String>[]);

      expect(result.added, 0);
      expect(client.posts, isEmpty);
    });
  });

  group('PlaylistAddResult.describe', () {
    test('reports a clean add with the playlist name', () {
      const PlaylistAddResult result = PlaylistAddResult(added: 4);
      expect(result.describe('Road trip'), 'Added 4 songs to Road trip');
      expect(result.isComplete, isTrue);
    });

    test('uses the singular for one song', () {
      const PlaylistAddResult result = PlaylistAddResult(added: 1);
      expect(result.describe('Road trip'), 'Added 1 song to Road trip');
    });

    test('explains that everything was already present', () {
      const PlaylistAddResult result = PlaylistAddResult(added: 0, skipped: 2);
      expect(result.describe('Road trip'), 'Those songs are already in Road trip');
    });

    test('mentions both the skips and the failure when both happened', () {
      const PlaylistAddResult result =
          PlaylistAddResult(added: 2, skipped: 1, firstError: 'Playlist not found.');
      expect(
        result.describe('Road trip'),
        'Added 2 songs to Road trip (1 already there; Playlist not found.)',
      );
      expect(result.isComplete, isFalse);
    });
  });
}
