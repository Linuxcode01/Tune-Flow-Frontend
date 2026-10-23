/// Compile-time configuration for the TuneFlow client.
///
/// Values are injected with `--dart-define` so that no environment file is needed in the repo and
/// no secret is ever committed (docs section 10):
///
/// ```bash
/// flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080/api/v1
/// ```
library;

/// Immutable app-wide configuration resolved once at startup.
class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    required this.apiTimeout,
    required this.streamUrlSafetyMargin,
    required this.pageSize,
    required this.enableNetworkLogs,
  });

  /// Resolves configuration from the compile-time environment, falling back to sane local defaults.
  ///
  /// The default targets the Android emulator's host loopback alias, which is where a developer
  /// running `flutter run` will find the backend started in `dev` mode.
  factory AppConfig.fromEnvironment() {
    const String rawBaseUrl = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://13.233.131.251:8080/api/v1',
    );
    const bool logs = bool.fromEnvironment(
      'ENABLE_NETWORK_LOGS',
      defaultValue: true,
    );

    return AppConfig(
      apiBaseUrl: rawBaseUrl.endsWith('/')
          ? rawBaseUrl.substring(0, rawBaseUrl.length - 1)
          : rawBaseUrl,
      apiTimeout: const Duration(seconds: 20),
      streamUrlSafetyMargin: const Duration(seconds: 30),
      pageSize: 20,
      enableNetworkLogs: logs,
    );
  }

  /// Base URL of the backend, e.g. `https://api.tuneflow.example/api/v1`.
  final String apiBaseUrl;

  /// Applied to connect/receive/send timeouts on the shared [Dio] instance.
  final Duration apiTimeout;

  /// Signed stream URLs are short-lived; the client refreshes one this long before it expires so a
  /// track that is playing never dies mid-song.
  final Duration streamUrlSafetyMargin;

  /// Default page size for paginated catalogue requests (backend caps this at 100).
  final int pageSize;

  /// Verbose Dio logging. Always false in release builds.
  final bool enableNetworkLogs;

  @override
  String toString() => 'AppConfig(apiBaseUrl: $apiBaseUrl)';
}
