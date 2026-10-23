import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuneflow/core/network/api_client.dart';
import 'package:tuneflow/core/network/paged_response.dart';
import 'package:tuneflow/core/providers/core_providers.dart';
import 'package:tuneflow/core/theme/app_theme.dart';
import 'package:tuneflow/features/catalog/domain/entities/artist.dart';
import 'package:tuneflow/features/catalog/domain/entities/song.dart';
import 'package:tuneflow/features/catalog/domain/repositories/catalog_repository.dart';
import 'package:tuneflow/features/catalog/presentation/providers/catalog_providers.dart';
import 'package:tuneflow/features/playlist/presentation/widgets/song_picker_sheet.dart';

/// The flow the playlist screen was missing: search the catalogue, tick several tracks, add them.
///
/// This drives the real sheet against a fake catalogue and a recording API client, so it fails if the
/// sheet ever stops reaching the add endpoint - which is exactly what was wrong before: the endpoint
/// existed and nothing in the playlist UI called it.

class _RecordingApiClient implements ApiClient {
  final List<Map<String, dynamic>> added = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Object? body,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
  }) async {
    final Map<String, dynamic> map = (body as Map<String, dynamic>?) ?? const <String, dynamic>{};
    if (path.endsWith('/songs')) {
      added.add(map);
    }
    return <String, dynamic>{};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Only the two calls the sheet makes are implemented; anything else throws, which keeps the fake
/// honest about what the sheet is allowed to touch.
class _FakeCatalogRepository implements CatalogRepository {
  _FakeCatalogRepository(this.songs);

  final List<Song> songs;

  @override
  Future<PagedResponse<Song>> getSongs({
    int page = 0,
    int size = 20,
    String? artistId,
    String? albumId,
    String? genreSlug,
    String? query,
  }) async =>
      PagedResponse<Song>(items: songs, page: 0, size: songs.length, totalElements: songs.length, totalPages: 1, isFirst: true, isLast: true);

  @override
  Future<List<Song>> getTrendingSongs({int limit = 20}) async => songs;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

const Song _neon = Song(
  id: 's1',
  title: 'Neon Skyline',
  durationSeconds: 214,
  artist: ArtistSummary(id: 'a1', name: 'Aria Vance'),
);
const Song _midnight = Song(
  id: 's2',
  title: 'Midnight Drive',
  durationSeconds: 198,
  artist: ArtistSummary(id: 'a1', name: 'Aria Vance'),
);
const Song _harbour = Song(
  id: 's3',
  title: 'Harbour Lights',
  durationSeconds: 240,
  artist: ArtistSummary(id: 'a1', name: 'Aria Vance'),
);

Widget _host({
  required _RecordingApiClient client,
  Set<String> existing = const <String>{},
}) {
  return ProviderScope(
    overrides: <Override>[
      apiClientProvider.overrideWithValue(client),
      catalogRepositoryProvider.overrideWithValue(
        _FakeCatalogRepository(<Song>[_neon, _midnight, _harbour]),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => Center(
            child: Consumer(
              builder: (BuildContext context, WidgetRef ref, Widget? child) => ElevatedButton(
                onPressed: () => showSongPickerSheet(
                  context,
                  ref,
                  playlistId: 'p1',
                  playlistName: 'Road trip',
                  existingSongIds: existing,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Opens the sheet and lets its entrance animation finish. `pumpAndSettle` is avoided on purpose: a
/// snackbar timer or a transient progress indicator makes it hang rather than fail.
Future<void> openSheet(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

void main() {
  testWidgets('lists candidates with trending songs before anything is typed',
      (WidgetTester tester) async {
    await tester.pumpWidget(_host(client: _RecordingApiClient()));
    await openSheet(tester);

    expect(find.text('Add songs'), findsWidgets);
    expect(find.text('Neon Skyline'), findsOneWidget);
    expect(find.text('Midnight Drive'), findsOneWidget);
    expect(find.text('Harbour Lights'), findsOneWidget);
    expect(find.text('Select songs to add'), findsOneWidget);
  });

  testWidgets('adds every selected song and reports the result', (WidgetTester tester) async {
    final _RecordingApiClient client = _RecordingApiClient();
    await tester.pumpWidget(_host(client: client));
    await openSheet(tester);

    await tester.tap(find.text('Neon Skyline'));
    await tester.pump();
    await tester.tap(find.text('Harbour Lights'));
    await tester.pump();

    expect(find.text('2 songs selected'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Add songs'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(
      client.added.map((Map<String, dynamic> body) => body['songId']),
      <String>['s1', 's3'],
      reason: 'the sheet must reach POST /playlists/{id}/songs for each ticked track',
    );
    expect(find.text('Added 2 songs to Road trip'), findsOneWidget);
  });

  testWidgets('a song already in the playlist is shown but not selectable',
      (WidgetTester tester) async {
    await tester.pumpWidget(_host(client: _RecordingApiClient(), existing: <String>{'s2'}));
    await openSheet(tester);

    expect(find.text('Already in this playlist'), findsOneWidget);

    await tester.tap(find.text('Midnight Drive'));
    await tester.pump();
    expect(
      find.text('Select songs to add'),
      findsOneWidget,
      reason: 'tapping a track that is already there must not select it',
    );
  });

  testWidgets('ticking a song and unticking it leaves nothing to add', (WidgetTester tester) async {
    final _RecordingApiClient client = _RecordingApiClient();
    await tester.pumpWidget(_host(client: client));
    await openSheet(tester);

    await tester.tap(find.text('Neon Skyline'));
    await tester.pump();
    await tester.tap(find.text('Neon Skyline'));
    await tester.pump();

    expect(find.text('Select songs to add'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Add songs')).onPressed,
      isNull,
    );
  });
}
