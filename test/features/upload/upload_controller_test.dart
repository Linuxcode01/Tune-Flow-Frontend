import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuneflow/core/error/app_exception.dart';
import 'package:tuneflow/features/auth/domain/entities/user.dart';
import 'package:tuneflow/features/auth/presentation/providers/auth_providers.dart';
import 'package:tuneflow/features/catalog/domain/entities/song.dart';
import 'package:tuneflow/features/upload/domain/entities/media_file.dart';
import 'package:tuneflow/features/upload/domain/entities/upload_result.dart';
import 'package:tuneflow/features/upload/domain/entities/upload_state.dart';
import 'package:tuneflow/features/upload/domain/repositories/upload_repository.dart';
import 'package:tuneflow/features/upload/domain/services/media_picker.dart';
import 'package:tuneflow/features/upload/presentation/providers/upload_providers.dart';

/// The publishing flow is two API calls with a form in between, and the failure modes that matter are
/// all about *state*: a file that is too big must never be uploaded, a cancelled pick must change
/// nothing, a failed upload must not leave a phantom `objectKey` behind, and the publish button must
/// stay shut until there is something real to publish.

MediaFile _file({
  String name = 'neon.mp3',
  int sizeBytes = 4 * 1024 * 1024,
}) =>
    MediaFile(name: name, sizeBytes: sizeBytes, bytes: Uint8List(sizeBytes.clamp(0, 16)));

class _FakeMediaPicker implements MediaPicker {
  _FakeMediaPicker({this.audio, this.image});

  MediaFile? audio;
  MediaFile? image;

  @override
  Future<MediaFile?> pickAudio() async => audio;

  @override
  Future<MediaFile?> pickImage() async => image;
}

class _FakeUploadRepository implements UploadRepository {
  _FakeUploadRepository({
    this.audioResult,
    this.imageResult,
    this.uploadError,
    this.createError,
  });

  UploadResult? audioResult;
  UploadResult? imageResult;
  AppException? uploadError;
  AppException? createError;

  final List<MediaFile> uploaded = <MediaFile>[];
  final List<Map<String, Object?>> createCalls = <Map<String, Object?>>[];

  @override
  Future<UploadResult> uploadAudio(MediaFile file, {UploadProgressCallback? onProgress}) async {
    uploaded.add(file);
    onProgress?.call(0.5);
    onProgress?.call(1);
    if (uploadError != null) {
      throw uploadError!;
    }
    return audioResult ?? const UploadResult(objectKey: 'audio/2026/10/neon.mp3');
  }

  @override
  Future<UploadResult> uploadImage(MediaFile file, {UploadProgressCallback? onProgress}) async {
    uploaded.add(file);
    if (uploadError != null) {
      throw uploadError!;
    }
    return imageResult ?? const UploadResult(objectKey: 'images/2026/10/cover.jpg');
  }

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
      'durationSeconds': durationSeconds,
      'coverImageObjectKey': coverImageObjectKey,
      'albumId': albumId,
      'trackNumber': trackNumber,
      'releaseDate': releaseDate,
      'explicit': explicit,
      'genreSlugs': genreSlugs,
    });
    if (createError != null) {
      throw createError!;
    }
    return Song(id: 'song-new', title: title, durationSeconds: durationSeconds);
  }
}

const User _artist = User(
  id: 'user-1',
  name: 'Aria',
  email: 'artist@tuneflow.dev',
  role: UserRole.artist,
  artistId: 'artist-1',
);

({ProviderContainer container, UploadController controller, _FakeMediaPicker picker, _FakeUploadRepository repo})
    _harness({
  MediaFile? audio,
  MediaFile? image,
  _FakeUploadRepository? repository,
}) {
  final _FakeMediaPicker picker = _FakeMediaPicker(audio: audio, image: image);
  final _FakeUploadRepository repo = repository ?? _FakeUploadRepository();

  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      mediaPickerProvider.overrideWithValue(picker),
      uploadRepositoryProvider.overrideWithValue(repo),
      // Read by the post-publish invalidation; a value keeps the real auth stack (and the platform
      // keystore behind it) out of the test entirely.
      currentUserProvider.overrideWithValue(_artist),
    ],
  );
  addTearDown(container.dispose);

  // An auto-disposed provider needs a listener to stay alive between reads.
  final ProviderSubscription<UploadState> subscription =
      container.listen(uploadControllerProvider, (UploadState? previous, UploadState next) {});
  addTearDown(subscription.close);

  return (
    container: container,
    controller: container.read(uploadControllerProvider.notifier),
    picker: picker,
    repo: repo,
  );
}

void main() {
  group('UploadController.pickAudio', () {
    test('uploads an allowed file and seeds the duration from the response', () async {
      final _FakeUploadRepository repo = _FakeUploadRepository(
        audioResult: const UploadResult(
          objectKey: 'audio/2026/10/neon.mp3',
          durationSeconds: 214,
          bitrateKbps: 320,
        ),
      );
      final harness = _harness(audio: _file(), repository: repo);

      await harness.controller.pickAudio();

      final UploadState state = harness.container.read(uploadControllerProvider);
      expect(repo.uploaded.single.name, 'neon.mp3');
      expect(state.audio?.objectKey, 'audio/2026/10/neon.mp3');
      expect(state.uploadingAudio, isFalse);
      expect(state.audioProgress, 1);
      expect(
        state.durationSeconds,
        214,
        reason: 'the server analysed the file - the artist should not have to type that in',
      );
    });

    test('refuses an oversized file before spending bandwidth on it', () async {
      final harness = _harness(audio: _file(sizeBytes: 120 * 1024 * 1024));

      await harness.controller.pickAudio();

      final UploadState state = harness.container.read(uploadControllerProvider);
      expect(harness.repo.uploaded, isEmpty, reason: 'a rejected file must never be uploaded');
      expect(state.errorMessage, contains('100 MB'));
      expect(state.audio, isNull);
    });

    test('refuses an unsupported extension', () async {
      final harness = _harness(audio: _file(name: 'document.pdf'));

      await harness.controller.pickAudio();

      expect(harness.repo.uploaded, isEmpty);
      expect(harness.container.read(uploadControllerProvider).errorMessage, contains('PDF'));
    });

    test('treats a cancelled pick as a no-op', () async {
      final harness = _harness();

      await harness.controller.pickAudio();

      final UploadState state = harness.container.read(uploadControllerProvider);
      expect(state.audio, isNull);
      expect(state.errorMessage, isNull, reason: 'backing out of the picker is not an error');
      expect(state.uploadingAudio, isFalse);
    });

    test('a failed upload leaves no file and no objectKey behind', () async {
      final _FakeUploadRepository repo = _FakeUploadRepository(
        uploadError: const ApiException(
          message: 'Storage is unavailable.',
          errorCode: 'STORAGE_ERROR',
          statusCode: 500,
        ),
      );
      final harness = _harness(audio: _file(), repository: repo);

      await harness.controller.pickAudio();

      final UploadState state = harness.container.read(uploadControllerProvider);
      expect(state.audio, isNull);
      expect(state.uploadingAudio, isFalse);
      expect(state.errorMessage, 'Storage is unavailable.');
    });
  });

  group('UploadController.submit', () {
    test('refuses to publish without audio and says why', () async {
      final harness = _harness();
      harness.controller.setTitle('Neon Skyline');

      final Song? song = await harness.controller.submit();

      expect(song, isNull);
      expect(harness.repo.createCalls, isEmpty);
      expect(
        harness.container.read(uploadControllerProvider).errorMessage,
        'Choose an audio file first.',
      );
    });

    test('publishes the metadata the upload produced', () async {
      final _FakeUploadRepository repo = _FakeUploadRepository(
        audioResult: const UploadResult(objectKey: 'audio/2026/10/neon.mp3', durationSeconds: 214),
        imageResult: const UploadResult(objectKey: 'images/2026/10/neon.jpg'),
      );
      final harness = _harness(audio: _file(), image: _file(name: 'neon.jpg'), repository: repo);

      await harness.controller.pickAudio();
      harness.controller.setTitle('  Neon Skyline  ');
      harness.controller.toggleGenre('electronic');
      harness.controller.toggleGenre('synthwave');
      harness.controller.setExplicit(true);
      await harness.controller.pickCover();

      final Song? song = await harness.controller.submit();

      expect(song, isNotNull);
      final Map<String, Object?> call = repo.createCalls.single;
      expect(call['title'], 'Neon Skyline', reason: 'trimmed before it reaches the API');
      expect(call['audioObjectKey'], 'audio/2026/10/neon.mp3');
      expect(call['coverImageObjectKey'], 'images/2026/10/neon.jpg');
      expect(call['durationSeconds'], 214);
      expect(call['explicit'], isTrue);
      expect(call['genreSlugs'], <String>{'electronic', 'synthwave'});
      expect(
        harness.container.read(uploadControllerProvider).createdSong?.title,
        'Neon Skyline',
      );
    });

    test('a rejected publish keeps the form usable and the file in place', () async {
      final _FakeUploadRepository repo = _FakeUploadRepository(
        audioResult: const UploadResult(objectKey: 'audio/2026/10/neon.mp3', durationSeconds: 214),
        createError: const ApiException(
          message: 'You can only publish under your own artist profile.',
          errorCode: 'FORBIDDEN',
          statusCode: 403,
        ),
      );
      final harness = _harness(audio: _file(), repository: repo);

      await harness.controller.pickAudio();
      harness.controller.setTitle('Neon Skyline');
      final Song? song = await harness.controller.submit();

      final UploadState state = harness.container.read(uploadControllerProvider);
      expect(song, isNull);
      expect(state.errorMessage, contains('own artist profile'));
      expect(state.submitting, isFalse);
      expect(
        state.audio,
        isNotNull,
        reason: 'the retry should cost a metadata call, not another 40 MB upload',
      );
      expect(state.canSubmit, isTrue, reason: 'the artist can fix the problem and submit again');
    });
  });

  group('UploadState.blockingReason', () {
    test('walks the artist through what is still missing', () {
      const UploadState empty = UploadState();
      expect(empty.blockingReason, 'Choose an audio file first.');
      expect(empty.canSubmit, isFalse);

      const UploadState uploaded = UploadState(
        audio: UploadResult(objectKey: 'audio/x.mp3', durationSeconds: 200),
      );
      expect(uploaded.blockingReason, 'Give the track a title.');

      final UploadState titled = uploaded.copyWith(title: 'Neon Skyline');
      expect(titled.canSubmit, isTrue);
      expect(titled.blockingReason, isNull);
      expect(
        titled.effectiveDurationSeconds,
        200,
        reason: 'the duration the server measured is used until the artist overrides it',
      );
    });

    test('an edited duration wins over the measured one', () {
      const UploadState state = UploadState(
        audio: UploadResult(objectKey: 'audio/x.mp3', durationSeconds: 200),
        title: 'Neon Skyline',
        durationSeconds: 187,
      );
      expect(state.effectiveDurationSeconds, 187);
    });

    test('a zero duration blocks publishing, because the API requires a real length', () {
      const UploadState state = UploadState(
        audio: UploadResult(objectKey: 'audio/x.mp3'),
        title: 'Neon Skyline',
      );
      expect(state.canSubmit, isFalse);
      expect(state.blockingReason, 'Duration must be at least one second.');
    });
  });
}
