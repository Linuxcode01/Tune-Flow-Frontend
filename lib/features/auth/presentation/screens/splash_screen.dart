import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tuneflow/app/router/route_paths.dart';
import 'package:tuneflow/core/constants/app_constants.dart';
import 'package:tuneflow/core/theme/app_colors.dart';
import 'package:tuneflow/features/auth/domain/entities/auth_session.dart';
import 'package:tuneflow/features/auth/presentation/providers/auth_providers.dart';

/// Shown while the stored session is being restored.
///
/// This screen exists so a returning user never sees the login form flash before being signed back
/// in. Because the router keeps the user *here* until the auth status resolves, the screen also owns
/// the escape hatch: if restoration has not finished by [AppConstants.sessionRestoreTimeout], it
/// offers a way forward instead of leaving the user staring at a spinner.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  Timer? _fallbackTimer;
  bool _showFallback = false;

  @override
  void initState() {
    super.initState();
    // A little past the controller's own deadline, so the automatic resolution normally wins and the
    // buttons only appear if something is genuinely wedged.
    _fallbackTimer = Timer(
      AppConstants.sessionRestoreTimeout + const Duration(seconds: 2),
      () {
        if (mounted) {
          setState(() => _showFallback = true);
        }
      },
    );
  }

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AuthState auth = ref.watch(authControllerProvider);
    final bool resolving = auth.status == AuthStatus.unknown;

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.heroGradient),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const _Logo(),
                const SizedBox(height: 32),
                if (resolving && !_showFallback) ...<Widget>[
                  const SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Getting things ready…',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
                // Shown either because restore reported a failure, or because it is taking far too
                // long. Both cases need the same thing: a way off this screen.
                if (!resolving || _showFallback) ...<Widget>[
                  Text(
                    auth.errorMessage ??
                        (resolving
                            ? 'This is taking longer than expected.'
                            : 'Please sign in to continue.'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  if (resolving) ...<Widget>[
                    FilledButton.tonal(
                      onPressed: () {
                        setState(() => _showFallback = false);
                        _fallbackTimer?.cancel();
                        _fallbackTimer = Timer(
                          AppConstants.sessionRestoreTimeout + const Duration(seconds: 2),
                          () {
                            if (mounted) {
                              setState(() => _showFallback = true);
                            }
                          },
                        );
                        ref.read(authControllerProvider.notifier).restore();
                      },
                      child: const Text('Try again'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      style: TextButton.styleFrom(foregroundColor: Colors.white),
                      onPressed: () =>
                          ref.read(authControllerProvider.notifier).continueAsSignedOut(),
                      child: const Text('Continue to sign in'),
                    ),
                  ] else
                    FilledButton.tonal(
                      onPressed: () => context.go(RoutePaths.login),
                      child: const Text('Sign in'),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(24),
          ),
          child: const Icon(Icons.graphic_eq_rounded, size: 44, color: Colors.white),
        ),
        const SizedBox(height: 18),
        Text(
          'TuneFlow',
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
              ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Your music, everywhere',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
      ],
    );
  }
}
