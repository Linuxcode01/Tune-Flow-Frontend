import 'package:flutter/material.dart';

/// The TuneFlow palette (docs section 8).
///
/// A deliberately small set of tokens: one accent, a dark-first surface ramp, and semantic colours
/// for like/offline/error states so those never drift between features.
class AppColors {
  const AppColors._();

  /// Primary accent - used for the play button, active nav item and progress.
  static const Color accent = Color(0xFF1DB954);
  static const Color accentDark = Color(0xFF14833B);
  static const Color accentSoft = Color(0xFF0F2E1D);

  /// Brand secondary, used for gradients and the "new release" badge.
  static const Color secondary = Color(0xFF6C63FF);

  static const Color like = Color(0xFFE91E63);

  // Dark theme surfaces (the default - music apps are used in the dark).
  static const Color darkBackground = Color(0xFF0B0B0F);
  static const Color darkSurface = Color(0xFF14141A);
  static const Color darkSurfaceElevated = Color(0xFF1D1D25);
  static const Color darkDivider = Color(0xFF2A2A33);

  // Light theme surfaces.
  static const Color lightBackground = Color(0xFFFAFAFC);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceElevated = Color(0xFFF2F2F7);
  static const Color lightDivider = Color(0xFFE4E4EA);

  static const Color textPrimaryDark = Color(0xFFF5F5F7);
  static const Color textSecondaryDark = Color(0xFFA1A1AA);
  static const Color textPrimaryLight = Color(0xFF111118);
  static const Color textSecondaryLight = Color(0xFF5C5C66);

  static const Color success = Color(0xFF2ECC71);
  static const Color warning = Color(0xFFF5A623);
  static const Color error = Color(0xFFE5484D);

  /// Gradient used behind the expanded player and the artist header.
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[Color(0xFF1DB954), Color(0xFF0E7A5F), Color(0xFF14141A)],
    stops: <double>[0.0, 0.45, 1.0],
  );

  /// Deterministic placeholder colour for artwork that failed to load, keyed by entity id.
  static Color placeholderFor(String seed, {required bool dark}) {
    final List<Color> palette = dark
        ? const <Color>[
            Color(0xFF1D3B2A),
            Color(0xFF2A2A4A),
            Color(0xFF3A2340),
            Color(0xFF3A2E1F),
            Color(0xFF1F3A3A),
          ]
        : const <Color>[
            Color(0xFFD8F3E3),
            Color(0xFFE0DEFA),
            Color(0xFFFADCE6),
            Color(0xFFFCEBD5),
            Color(0xFFD9F1F1),
          ];
    if (seed.isEmpty) {
      return palette.first;
    }
    final int hash = seed.codeUnits.fold<int>(0, (int acc, int unit) => (acc * 31 + unit) & 0x7fffffff);
    return palette[hash % palette.length];
  }
}
