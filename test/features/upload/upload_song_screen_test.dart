import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tuneflow/core/network/api_client.dart';
import 'package:tuneflow/core/providers/core_providers.dart';
import 'package:tuneflow/core/theme/app_theme.dart';
import 'package:tuneflow/features/auth/domain/entities/user.dart';
import 'package:tuneflow/features/auth/presentation/providers/auth_providers.dart';
import 'package:tuneflow/features/catalog/domain/entities/album.dart';
import 'package:tuneflow/features/catalog/domain/entities/artist.dart';
import 'package:tuneflow/features/catalog/domain/entities/genre.dart';
import 'package:tuneflow/features/catalog/domain/entities/song.dart';
import 'package:tuneflow/features/catalog/presentation/providers/catalog_providers.dart';
import 'package:tuneflow/features/upload/domain/entities/media_file.dart';
import 'package:tuneflow/features/upload/domain/entities/upload_result.dart';
import 'package:tuneflow/features/upload/domain/repositories/upload_repository.dart';
import 'package:tuneflow/features/upload/domain/services/media_picker.dart';
import 'package:tuneflow/features/upload/presentation/providers/upload_providers.dart';
import 'package:tuneflow/features/upload/presentation/screens/upload_song_screen.dart';

/// The screen is the gate for the whole publishing flow: a listener must be told why they cannot
/// publish, and an artist must be able to go from "no file" to a submitted song without the form
/// letting them submit garbage.

class _NeverApiClient implements ApiClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => Completer<Never>().future;
}

class _FakeMediaPicker implements MediaPicker {
  _FakeMediaPicker(this.audio);

  final MediaFile? audio;

  @override
  Future<MediaFile?> pickAudio() async => audio;

  @override
  Future<MediaFile?> pickImage() async => null;
}

class _FakeUploadRepository implements UploadRepository {
  final List<Map<String, Object?>> createCalls = <Map<String, Object?>>[];

  @override
  Future<UploadResult> uploadAudio(MediaFile file, {UploadProgressCallback? onProgress}) async {
    onProgress?.call(1);
    return const UploadResult(objectKey: 'audio/2026/10/neon.mp3', durationSeconds: 214);
  }

  @override
  Future<UploadResult> uploadImage(MediaFile file, {UploadProgressCallback? onProgress}) async =>
      const UploadResult(objectKey: 'images/2026/10/neon.jpg');

  @override
  Future<Song> createSong({
    required String title,
    required String audioObjectKey,
    required int durationSeconds,
    String? coverImageObjectKey,
    String? albumId,
    int? trackNumber,
    DateTime? releaseDate,
    bool explicit = false,
    Set<String> genreSlugs = const <String>{},
  }) async {
    createCalls.add(<String, Object?>{
      'title': title,
      'audioObjectKey': audioObjectKey,
      'genres': genreSlugs,
    });
    return Song(
      id: 'song-new',
      title: title,
      durationSeconds: durationSeconds,
      // The artist is what surfaces the snackbar's "View artist" action - the path that used to
      // crash when it fired with a deactivated screen context.
      artist: const ArtistSummary(id: 'artist-1', name: 'Aria'),
    );
  }
}

const User _listener = User(id: 'user-1', name: 'Sam', email: 'listener@tuneflow.dev');
const User _artist = User(
  id: 'user-2',
  name: 'Aria',
  email: 'artist@tuneflow.dev',
  role: UserRole.artist,
  artistId: 'artist-1',
);

MediaFile _audioFile() =>
    MediaFile(name: 'neon.mp3', sizeBytes: 3 * 1024 * 1024, bytes: Uint8List(8));

List<Override> _overrides({
  required User user,
  _FakeUploadRepository? repository,
  _FakeMediaPicker? picker,
}) {
  return <Override>[
    currentUserProvider.overrideWithValue(user),
    apiClientProvider.overrideWithValue(_NeverApiClient()),
    uploadRepositoryProvider.overrideWithValue(repository ?? _FakeUploadRepository()),
    mediaPickerProvider.overrideWithValue(picker ?? _FakeMediaPicker(_audioFile())),
    // Resolved up front: an unresolved provider leaves an indeterminate progress indicator on
    // screen, which never stops animating and would make `pumpAndSettle` meaningless.
    genresProvider.overrideWith((Ref ref) => const <Genre>[
          Genre(id: 'g1', name: 'Electronic', slug: 'electronic'),
          Genre(id: 'g2', name: 'Synthwave', slug: 'synthwave'),
        ]),
    myAlbumsProvider.overrideWith((Ref ref) => const <Album>[]),
  ];
}

Widget _app({
  required User user,
  _FakeUploadRepository? repository,
  _FakeMediaPicker? picker,
}) {
  return ProviderScope(
    overrides: _overrides(user: user, repository: repository, picker: picker),
    child: MaterialApp(theme: AppTheme.dark, home: const UploadSongScreen()),
  );
}

void main() {
  /// The form is a scrolling ListView, and form widgets below the fold are not laid out in the
  /// default 800x600 test surface. A tall viewport keeps every field on screen so the assertions are
  /// about behaviour rather than about scrolling.
  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('a listener account gets an explanation, not a form that would 403',
      (WidgetTester tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(_app(user: _listener));
    await tester.pump();

    expect(find.text('Artist account needed'), findsOneWidget);
    expect(find.text('Publish song'), findsNothing);
    // The copy has to name the way out, otherwise it is just a locked door.
    expect(find.textContaining('artist account'), findsWidgets);
  });

  testWidgets('an artist sees the three steps and cannot publish an empty song',
      (WidgetTester tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(_app(user: _artist));
    await tester.pump();

    expect(find.text('Audio file'), findsOneWidget);
    expect(find.text('Cover art'), findsOneWidget);
    expect(find.text('Title'), findsOneWidget);
    expect(find.text('Duration (seconds)'), findsOneWidget);
    expect(find.text('Publish song'), findsOneWidget);

    // Disabled, and it says why - a grey button with no explanation is the thing this replaces.
    expect(find.text('Choose an audio file first.'), findsOneWidget);
    final FilledButton publish = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Publish song'),
    );
    expect(publish.onPressed, isNull);
  });

  testWidgets('picking a file uploads it, fills in the duration, and then publishing works',
      (WidgetTester tester) async {
    useTallViewport(tester);
    final _FakeUploadRepository repository = _FakeUploadRepository();
    await tester.pumpWidget(_app(user: _artist, repository: repository));
    await tester.pump();

    await tester.tap(find.text('Choose file').first);
    // Explicit pumps rather than pumpAndSettle: the uploading state shows a progress indicator, and
    // settling is the wrong instrument when a spinner is legitimately on screen.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('neon.mp3'), findsOneWidget);
    // The duration the server measured is in the field before the artist types anything.
    expect(find.widgetWithText(TextFormField, '214'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Title'), 'Neon Skyline');
    await tester.tap(find.text('Electronic'));
    await tester.pump();

    final FilledButton publish = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Publish song'),
    );
    expect(publish.onPressed, isNotNull, reason: 'audio + title + duration is everything the API needs');

    await tester.tap(find.text('Publish song'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(repository.createCalls.single['title'], 'Neon Skyline');
    expect(repository.createCalls.single['audioObjectKey'], 'audio/2026/10/neon.mp3');
    expect(repository.createCalls.single['genres'], <String>{'electronic'});
    // The artist is told the song is live. (The screen also pops here; popping is a no-op when the
    // screen is the root route, as it is in this harness, so the confirmation is what we assert.)
    expect(find.text('“Neon Skyline” is now live'), findsOneWidget);
  });

  testWidgets('publishing under the real GoRouter shell pops and the snackbar action still works',
      (WidgetTester tester) async {
    // Regression: the snackbar's "View artist" action used to call `context.push` after this
    // screen had popped, hitting a deactivated element and crashing the app. The screen now
    // captures the router before popping, so the same flow under a real GoRouter must complete -
    // pop back home, and navigate when the action is tapped.
    useTallViewport(tester);
    final _FakeUploadRepository repository = _FakeUploadRepository();
    final GoRouter router = GoRouter(
      routes: <GoRoute>[
        GoRoute(
          path: '/',
          builder: (BuildContext context, GoRouterState state) =>
              const Scaffold(body: Text('home screen')),
        ),
        GoRoute(
          path: '/upload',
          builder: (BuildContext context, GoRouterState state) => const UploadSongScreen(),
        ),
        GoRoute(
          path: '/artist/:id',
          builder: (BuildContext context, GoRouterState state) =>
              Scaffold(body: Text('artist ${state.pathParameters['id']}')),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(user: _artist, repository: repository),
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    unawaited(router.push('/upload'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Choose file').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.enterText(find.widgetWithText(TextFormField, 'Title'), 'Neon Skyline');
    // Flush the rebuild the title change schedules: without it the publish button still holds its
    // disabled pre-typing callback and the tap below would be a silent no-op.
    await tester.pump();
    await tester.tap(find.text('Publish song'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('“Neon Skyline” is now live'), findsOneWidget);
    // Let the pop transition finish before asserting what is and is not on screen.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // The pop happened: the upload form is gone and the route underneath is home again.
    expect(find.text('Publish song'), findsNothing);
    expect(find.text('home screen'), findsOneWidget);

    // The action fires after the screen is disposed - this is the exact line that crashed before.
    await tester.tap(find.text('View artist'));
    await tester.pumpAndSettle();
    expect(find.text('artist artist-1'), findsOneWidget);
  });
}
