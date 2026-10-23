import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tuneflow/core/config/app_config.dart';
import 'package:tuneflow/core/network/api_client.dart';
import 'package:tuneflow/core/network/auth_interceptor.dart';
import 'package:tuneflow/core/network/logging_interceptor.dart';
import 'package:tuneflow/core/network/retry_interceptor.dart';
import 'package:tuneflow/core/network/session_events.dart';
import 'package:tuneflow/core/storage/preferences.dart';
import 'package:tuneflow/core/storage/token_storage.dart';

/// Infrastructure providers: configuration, storage, networking.
///
/// Everything here is a plain `Provider` (no async), so the DI graph is resolved once and stays
/// inspectable. Feature providers layer on top of [apiClientProvider] and never build their own
/// Dio instance - that is what keeps auth refresh, retries and logging uniformly applied.

/// Resolved at startup from `--dart-define` values.
final Provider<AppConfig> appConfigProvider = Provider<AppConfig>(
  (Ref ref) => AppConfig.fromEnvironment(),
  name: 'appConfig',
);

/// Overridden in `main()` with the awaited instance, so no feature ever awaits plugin init.
final Provider<SharedPreferences> sharedPreferencesProvider = Provider<SharedPreferences>(
  (Ref ref) => throw UnimplementedError('sharedPreferencesProvider must be overridden in main()'),
  name: 'sharedPreferences',
);

final Provider<Preferences> preferencesProvider = Provider<Preferences>(
  (Ref ref) => Preferences(ref.watch(sharedPreferencesProvider)),
  name: 'preferences',
);

final Provider<TokenStorage> tokenStorageProvider = Provider<TokenStorage>(
  (Ref ref) => TokenStorage(),
  name: 'tokenStorage',
);

/// The bridge the interceptor uses to tell the UI that the session died.
final Provider<SessionEvents> sessionEventsProvider = Provider<SessionEvents>(
  (Ref ref) {
    final SessionEvents events = SessionEvents();
    ref.onDispose(events.dispose);
    return events;
  },
  name: 'sessionEvents',
);

/// A bare client used only for token refresh and request replay, deliberately un-intercepted.
final Provider<Dio> refreshDioProvider = Provider<Dio>(
  (Ref ref) {
    final AppConfig config = ref.watch(appConfigProvider);
    return Dio(
      BaseOptions(
        baseUrl: config.apiBaseUrl,
        connectTimeout: config.apiTimeout,
        receiveTimeout: config.apiTimeout,
        contentType: Headers.jsonContentType,
        responseType: ResponseType.json,
      ),
    );
  },
  name: 'refreshDio',
);

/// The application HTTP client: auth refresh, retry with backoff, and dev logging.
final Provider<Dio> dioProvider = Provider<Dio>(
  (Ref ref) {
    final AppConfig config = ref.watch(appConfigProvider);
    final Dio refreshDio = ref.watch(refreshDioProvider);

    final Dio dio = Dio(
      BaseOptions(
        baseUrl: config.apiBaseUrl,
        connectTimeout: config.apiTimeout,
        receiveTimeout: config.apiTimeout,
        sendTimeout: config.apiTimeout,
        contentType: Headers.jsonContentType,
        responseType: ResponseType.json,
        // Non-2xx responses are handled explicitly so the error envelope can be parsed; Dio's
        // default "throw on 3xx+" would still give us the body, but being explicit documents intent.
        validateStatus: (int? status) => status != null && status >= 200 && status < 400,
      ),
    );

    dio.interceptors.addAll(<Interceptor>[
      AuthInterceptor(
        tokenStorage: ref.watch(tokenStorageProvider),
        refreshDio: refreshDio,
        sessionEvents: ref.watch(sessionEventsProvider),
      ),
      RetryInterceptor(dio: dio),
      LoggingInterceptor(enabled: config.enableNetworkLogs),
    ]);

    return dio;
  },
  name: 'dio',
);

final Provider<ApiClient> apiClientProvider = Provider<ApiClient>(
  (Ref ref) => ApiClient(dio: ref.watch(dioProvider), config: ref.watch(appConfigProvider)),
  name: 'apiClient',
);
