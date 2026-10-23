import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tuneflow/app/router/app_router.dart';
import 'package:tuneflow/core/theme/app_theme.dart';

/// Root widget: theme, router and the global overlays every screen relies on.
///
/// `MaterialApp.router` keeps navigation state inside GoRouter (so deep links and the auth guard work
/// the same way), while Riverpod owns application state.
class TuneFlowApp extends ConsumerStatefulWidget {
  const TuneFlowApp({super.key});

  @override
  ConsumerState<TuneFlowApp> createState() => _TuneFlowAppState();
}

class _TuneFlowAppState extends ConsumerState<TuneFlowApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'TuneFlow',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      // Dark first: a music player is used at night and in the car.
      themeMode: ThemeMode.dark,
      routerConfig: ref.watch(routerProvider),
      builder: (BuildContext context, Widget? child) {
        // Clamp text scaling to a range the layouts can actually honour, instead of letting a very
        // large accessibility setting break the mini-player.
        final MediaQueryData media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: media.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.3),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
