import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tuneflow/app/app.dart';
import 'package:tuneflow/core/providers/core_providers.dart';
import 'package:tuneflow/core/utils/app_logger.dart';

/// Application entry point.
///
/// Startup does the minimum before the first frame: resolve `SharedPreferences` (needed synchronously
/// by providers) and install the [ProviderScope] override. Session restoration happens inside the
/// auth controller, so a slow network never blocks the first paint - the splash screen covers it.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The player is a dark, immersive surface; matching the system chrome avoids a white flash.
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
  );

  FlutterError.onError = (FlutterErrorDetails details) {
    AppLogger.error('Uncaught Flutter error', error: details.exception, stackTrace: details.stack);
    FlutterError.presentError(details);
  };

  final SharedPreferences preferences = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(preferences),
      ],
      child: const TuneFlowApp(),
    ),
  );
}
