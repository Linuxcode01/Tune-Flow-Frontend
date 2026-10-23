import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tuneflow/core/network/api_client.dart';
import 'package:tuneflow/core/providers/core_providers.dart';
import 'package:tuneflow/core/theme/app_theme.dart';
import 'package:tuneflow/features/auth/domain/repositories/auth_repository.dart';
import 'package:tuneflow/features/auth/presentation/providers/auth_providers.dart';
import 'package:tuneflow/features/catalog/domain/entities/search_results.dart';
import 'package:tuneflow/features/playlist/presentation/widgets/playlist_dialogs.dart';
import 'package:tuneflow/features/profile/presentation/screens/settings_screen.dart';

/// Regression suite for the "TextEditingController used after being disposed" red screen: dialogs
/// and sheets that own text fields must not dispose their controllers when the route *pops* - the
/// widgets stay in the tree for the exit animation and still receive focus/IME callbacks. The
/// controllers may only die in `State.dispose`.

class _NeverApiClient implements ApiClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => Completer<Never>().future;
}

class _FakePlaylistApiClient implements ApiClient {
  final List<Map<String, Object?>> posts = <Map<String, Object?>>[];

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Object? body,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
  }) async {
    posts.add(<String, Object?>{'path': path, 'body': body});
    final Map<String, dynamic> sent = (body as Map<String, dynamic>?) ?? <String, dynamic>{};
    return <String, dynamic>{
      'id': 'pl-1',
      'name': sent['name'] ?? 'Untitled',
      'description': sent['description'],
      'publicPlaylist': sent['publicPlaylist'] ?? false,
      'songCount': 0,
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => Completer<Never>().future;
}

class _FakeAuthRepository implements AuthRepository {
  int changePasswordCalls = 0;

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    changePasswordCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => Completer<Never>().future;
}

/// Hosts the dialog call so it gets a real [WidgetRef] and [BuildContext].
class _DialogHost extends ConsumerStatefulWidget {
  const _DialogHost();

  @override
  ConsumerState<_DialogHost> createState() => _DialogHostState();
}

class _DialogHostState extends ConsumerState<_DialogHost> {
  PlaylistSummary? result;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            result = await showCreatePlaylistDialog(context, ref);
          },
          child: const Text('open dialog'),
        ),
      ),
    );
  }
}

Future<void> _pumpApp(
  WidgetTester tester, {
  required Widget child,
  ApiClient? apiClient,
  AuthRepository? authRepository,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final List<Override> overrides = <Override>[
    sharedPreferencesProvider.overrideWithValue(prefs),
    apiClientProvider.overrideWithValue(apiClient ?? _NeverApiClient()),
    if (authRepository != null) authRepositoryProvider.overrideWithValue(authRepository),
  ];
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(theme: AppTheme.dark, home: child),
    ),
  );
}

void main() {
  testWidgets('closing the focused playlist dialog never touches a disposed controller',
      (WidgetTester tester) async {
    await _pumpApp(tester, child: const _DialogHost());

    await tester.tap(find.text('open dialog'));
    await tester.pumpAndSettle();
    expect(find.text('New playlist'), findsOneWidget);

    // Focus the autofocused name field the way a typing user would, then bail out.
    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'My Mix');
    await tester.tap(find.text('Cancel'));
    // The exit animation is where the old dispose-at-pop crashed: focus and IME callbacks land on
    // the dialog while it animates out.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    expect(find.text('New playlist'), findsNothing);
  });

  testWidgets('creating a playlist pops with the result and no use-after-dispose',
      (WidgetTester tester) async {
    final _FakePlaylistApiClient api = _FakePlaylistApiClient();
    await _pumpApp(tester, child: const _DialogHost(), apiClient: api);

    await tester.tap(find.text('open dialog'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Road Trip');
    await tester.tap(find.text('Public'));
    await tester.pump();
    await tester.tap(find.text('Create'));
    // The fake POST resolves in a microtask; a couple of frames carry the pop through.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    expect(api.posts.single['path'], '/playlists');
    final Map<String, dynamic> body = api.posts.single['body']! as Map<String, dynamic>;
    expect(body['name'], 'Road Trip');
    expect(body['publicPlaylist'], true);

    final _DialogHostState host = tester.state<_DialogHostState>(find.byType(_DialogHost));
    expect(host.result?.id, 'pl-1');
    expect(find.text('New playlist'), findsNothing);
  });

  testWidgets('the change-password sheet closes after submitting without a disposed controller',
      (WidgetTester tester) async {
    // The settings list is taller than the default 800x600 test surface; a tall viewport keeps
    // the "Change password" row on screen so the test is about behaviour, not scrolling.
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final _FakeAuthRepository auth = _FakeAuthRepository();
    await _pumpApp(tester, child: const SettingsScreen(), authRepository: auth);

    await tester.tap(find.text('Change password'));
    await tester.pumpAndSettle();
    expect(find.text('Update password'), findsOneWidget);

    // Type into the fields (the last one holds focus) and submit.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Current password'),
      'Password123',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'New password'),
      'Password124',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirm new password'),
      'Password124',
    );
    await tester.tap(find.text('Update password'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(auth.changePasswordCalls, 1);
    expect(tester.takeException(), isNull);
    expect(find.text('Password updated'), findsOneWidget);
    expect(find.text('Update password'), findsNothing);
  });
}
